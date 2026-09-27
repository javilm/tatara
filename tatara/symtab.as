; symtab.as - the symbol table: a name to a value, a type and flags.
;
; It replaces the pass-0 stub that lived at the bottom of
; expr.as, and it is deliberately the same shape: exlook has
; been a variable since then precisely so that this swap would be one
; store and nothing else.
;
; ONE hash.as table, SYBUCKS buckets. Every record - the name bytes
; included - is in the mapper; only the descriptor is in ordinary RAM,
; because deref may move the window between any two calls but cannot
; move a descriptor the caller is holding.
;
; R1 (names up to 255 characters) therefore costs nothing here: hash.as
; already stores keys of 1..255 bytes, which is what the macro name
; table has been doing. The alternative the plan reserved -
; store a hash and a length, settle collisions by comparing against the
; source text - would also have needed the source line to still exist at
; look-up time, which inside a macro expansion it does not.

SYMLIB		equ	1		; skips the externals in symtab.inc

		public	syminit
		public	symset
		public	symlook
		public	symfl
		public	symdef
		public	sympub
		public	symext
		public	symdump
		public	lstsyms
		public	seginit
		public	segrst
		public	segdir
		public	seggrp
		public	segwr
		public	locctr
		public	curseg
		public	segpark
		public	symtab		; all three are walked: the object
		public	segtab		;   file's GRPDEF, SEGDEF, EXTDEF
		public	grptab		;   and PUBDEF records are what
		public	segnum		;   these tables already hold
		public	grpnum

		include	symtab.inc
		include	cmdline.inc	; optcase: HTCASES or HTCASEI, from /C
		include	hash.inc
		include	alloc.inc	; before farptr.inc: derefp needs deref
		include	farptr.inc	; to have been declared
		include	errs.inc
		include	expr.inc	; SY_ABS, SY_CODE, SY_DATA
		include	ascii.inc	; CHR_TAB, in segdir's scan
		include	strutil.inc	; strupr, to read TRANSIENT
		include	srcline.inc	; passno: symdef's two messages
		include	msxdos.inc	; putsz, putdec, _CONOUT - symdump
		include	emit.inc	; emitraw, emitchr, lstcrlf: the
					;   page writes through the listing,
					;   not to the screen

		cseg

; syminit - an empty table, in the case mode the command line asked for.
;
;   CALLED ONCE, beside heapinit - not once per pass like macinit and
;   mexinit. The symbol table is the one structure that has to survive
;   from pass 1 into pass 2; that is the exception recorded when pass
;   state was settled.
;
;   It reads optcase, so cmdparse must have run. tatara.as moves the
;   cmdparse call above the inits for exactly this reason.
;
; Input:	nothing (optcase)
; Output:	the table is empty
; 		extnum = 0: the first EXTRN gets index 0
; Modifies:	AF, BC, DE, HL

syminit:	xor	a
		ld	(extnum),a	; no externals declared yet
		ld	ix,symtab
		ld	a,(optcase)
		ld	b,SYMASK
		jp	htinit

; symset - define a symbol, or give an existing one a new value.
;
;   SET and DEFL redefine; a redefinition must land on the SAME record,
;   or the table grows by one every time round a loop and htfind keeps
;   answering with the first. So: htfind first, htadd only if it is not
;   there.
;
;   A NEW record's payload is uninitialised - hash.as says so plainly -
;   so the flags byte is cleared on the add path only. Not on the
;   redefine path: a symbol declared PUBLIC and then given a new value
;   by SET is still public.
;
; Input:	DE -> the name, B = its length
;		HL = the value
;		A  = the type (SY_ABS and the others)
; Output:	stored (errheap does not return)
; Modifies:	AF, BC, DE, HL, IX

symset:		ld	(syval),hl	; htfind clobbers all four of these
		ld	(synam),de
		ld	(sytyp),a
		ld	a,b
		ld	(sylen),a

		ld	ix,symtab
		ld	hl,sypay
		call	htfind		; A is still the length
		jr	nc,symset.put	; there already: overwrite it in place

		ld	de,(synam)	; htfind clobbered DE and A
		ld	a,(sylen)
		ld	bc,SYSIZE
		ld	hl,sypay
		call	htadd
		jp	c,errheap

		derefp	sypay		; new record: nothing has set the flags
		ld	de,SY_FLAGS
		add	hl,de
		ld	(hl),0

symset.put:	derefp	sypay		; HL -> the payload, mapped
		ld	de,(syval)
		ld	(hl),e		; SY_VAL
		inc	hl
		ld	(hl),d
		inc	hl
		ld	a,(sytyp)
		ld	(hl),a		; SY_TYPE
		ret

; symlook - what is this name worth?
;
;   exlook points here. The contract is p0look's, unchanged, which is
;   why nothing in expr.as above exlook had to be touched.
;
; Input:	DE -> the name, B = its length
; Output:	CY set   = no such symbol
;		CY clear = HL is the value, A is the type
; Modifies:	AF, BC, DE, HL, IX

symlook:	ld	a,b
		or	a
		scf
		ret	z		; an empty name is not a symbol

		ld	ix,symtab
		ld	hl,sypay
		call	htfind
		ret	c		; not found: the CY htfind set is the
					; answer

		derefp	sypay
		ld	e,(hl)		; SY_VAL
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)		; SY_TYPE
		inc	hl
		push	af
		ld	a,(hl)		; SY_FLAGS, for symdef and exsym:
		ld	(symfl),a	; one deref answers both questions
		pop	af
		ex	de,hl		; HL = the value
		or	a		; clears CY = found
		ret

; symdef - define a symbol, with the rules.
;
;   symset is the raw store; this is the one every caller should use.
;   The rules it keeps:
;
;     a name with no value yet    - PUBLIC made the record: define it
;     EXTRN named it              - another module defines it: errmdef
;     one side SET/DEFL, one not  - errmdef, M80's M error
;     both SET/DEFL               - redefine, as often as asked
;     both fixed, same value      - allowed: this is pass 2 re-reading
;                                   the line, and 2.6.11 allows it once
;     both fixed, different       - pass 1: errmdef. Pass 2: errphase,
;                                   because the SAME line answered
;                                   differently the second time
;
; Input:	DE -> the name
; 		B  = its length
; 		HL = the value
; 		A  = the type (a segment index)
; 		C  = SYF_VAR for SET/DEFL, 0 for everything else
; Output:	defined (errmdef and errphase do not return)
; Modifies:	AF, BC, DE, HL, IX

symdef:		ld	(syval),hl	; the same scratch symset uses
		ld	(synam),de
		ld	(sytyp),a
		ld	a,b
		ld	(sylen),a
		ld	a,c
		ld	(sydflg),a

		call	symlook		; CY set = nothing by that name
		jr	c,symdef.put
		ld	(sdold),hl	; keep what it was worth
		ld	(sdoldt),a	;   and which segment it was in
		ld	a,(symfl)
		and	SYF_DEF
		jr	z,symdef.put	; PUBLIC made it; this is its value
		ld	a,(symfl)
		and	SYF_EXT
		jp	nz,errmdef	; EXTRN gave it to another module

		ld	a,(symfl)	; fixed and variable do not mix
		and	SYF_VAR
		ld	c,a
		ld	a,(sydflg)
		and	SYF_VAR
		cp	c
		jp	nz,errmdef
		or	a
		jr	nz,symdef.put	; both variable: SET may redefine

		ld	hl,(sdold)	; both fixed: the same value is no
		ld	de,(syval)	; redefinition at all
		or	a
		sbc	hl,de
		jr	nz,symdef.dif
		ld	a,(sdoldt)
		ld	hl,sytyp
		cp	(hl)
		ret	z		; and the same segment: nothing to do
symdef.dif:	ld	a,(passno)
		dec	a
		jp	z,errmdef	; pass 1: the source says it twice
		jp	errphase	; pass 2: the same line, two answers

symdef.put:	ld	hl,(syval)
		ld	de,(synam)
		ld	a,(sylen)
		ld	b,a
		ld	a,(sytyp)
		call	symset
		derefp	sypay		; the flags, on top of whatever the
		ld	de,SY_FLAGS	; record already carried
		add	hl,de
		ld	a,(sydflg)
		or	SYF_DEF
		or	(hl)
		ld	(hl),a
		ret

; sympub - mark one name PUBLIC, creating a record with no value if
;   nothing has defined it yet.
;
;   "public foo" at the top and "foo:" two hundred lines down is the
;   ordinary way to write it, which is what SYF_DEF exists for.
;
; Input:	DE -> the name
; 		B  = its length
; Output:	the record carries SYF_PUB
; Modifies:	AF, BC, DE, HL, IX

sympub:		ld	(synam),de
		ld	a,b
		ld	(sylen),a
		call	symlook		; CY set = make one
		jr	c,sympub.new
		ld	a,(symfl)
		and	SYF_EXT
		jp	nz,errmdef	; EXTRN claimed it first - 2.6.10
		derefp	sypay		; it is there: just add the flag
		ld	de,SY_FLAGS
		add	hl,de
		ld	a,(hl)
		or	SYF_PUB
		ld	(hl),a
		ret

sympub.new:	ld	de,(synam)	; a record with no value: SYF_DEF
		ld	a,(sylen)	; stays clear, so symdef will treat
		ld	b,a		; the first definition as one
		ld	hl,0
		ld	a,SY_ABS
		call	symset
		derefp	sypay
		ld	de,SY_FLAGS
		add	hl,de
		ld	(hl),SYF_PUB
		ret

; symext - declare one name external, and give it the next index.
;
;   An external has no value, so SY_VAL carries its INDEX: the
;   writes the EXTDEF records in that order, and a fixup naming an
;   external already has the number to write.
;
; Input:	DE -> the name
; 		B  = its length
; Output:	the record carries SYF_EXT, SY_VAL = its index
; Modifies:	AF, BC, DE, HL, IX

symext:		ld	(synam),de
		ld	a,b
		ld	(sylen),a
		call	symlook
		jr	c,symext.new
		ld	a,(symfl)
		and	SYF_EXT
		ret	nz		; already external: the source said
					; EXTRN twice, or pass 2 is reading
					; the same line again. Its index is
					; handed out and must not change
		ld	a,(symfl)
		and	SYF_DEF
		jp	nz,errmdef	; this module defines it - 2.6.12

symext.new:	ld	a,(extnum)	; its index
		cp	MAXEXT
		jp	nc,errmseg
		ld	l,a
		inc	a
		ld	(extnum),a
		ld	h,0		; HL = the index, as the value
		ld	de,(synam)
		ld	a,(sylen)
		ld	b,a
		ld	a,SY_ABS
		ld	c,SYF_EXT
		jp	symdef

; lstsyms - every symbol, in M80's columns, for the listing's last
;   page: four hex digits, the relocation mark, three spaces, and the
;   name in sixteen. Three to a line.
;
;   A SECOND WALK, not a reformatting of symdump. That one is a
;   diagnostic and prints the flags and the segment index; this one is
;   M80's page and prints neither. Sharing them would mean a formatter
;   argument, which is more machinery than the eight lines it saves.
;
;   The name comes out of the mapper a character at a time, for the
;   reason symdump's own header gives.
;
; Input:	nothing
; Output:	the symbols are written
; Modifies:	AF, BC, DE, HL, IX

lstsyms:	xor	a
		ld	(lsiter),a	; bucket 0...
		ld	hl,NULLOFF
		ld	(lsiter+3),hl	; ...and no record yet
		xor	a
		ld	(lscol),a	; and none on this line

lsym.lp:	ld	ix,symtab
		ld	hl,lsiter
		call	htnext
		jr	c,lsym.end
		call	lspay		; the value and the segment
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)
		ld	(lsseg),a
		push	de
		ld	de,lsbuf	; four digits, then the mark
		ld	h,d
		ld	l,e
		pop	de
		ex	de,hl
		call	numhex
		ld	a,(lsseg)
		or	a
		ld	a," "
		jr	z,lsym.abs
		ld	a,"'"
lsym.abs:	ld	(de),a
		ld	de,lsbuf
		ld	a,5
		call	emitraw
		ld	a,3
		call	emitsp

		ld	c,0		; the name, and how long it was
lsym.nm:	call	lskey
		ld	b,a
		ld	a,c
		cp	b
		jr	nc,lsym.pad
		ld	e,c
		ld	d,0
		add	hl,de
		ld	a,(hl)
		push	bc
		call	emitchr
		pop	bc
		inc	c
		jr	lsym.nm
lsym.pad:	ld	a,16		; sixteen columns, whatever the name
		sub	c		;   came to
		jr	c,lsym.eol
		call	emitsp

lsym.eol:	ld	hl,lscol	; three to a line
		inc	(hl)
		ld	a,(hl)
		cp	3
		jp	c,lsym.lp
		ld	(hl),0
		call	lstcrlf
		jp	lsym.lp

lsym.end:	ld	a,(lscol)	; and a last line ending if the last
		or	a		;   line was not full
		ret	z
		jp	lstcrlf

; lskey, lspay - the record the walk is on, mapped. EVERY BDOS CALL
;   UNDOES THIS, which is why the name loop calls lskey again for each
;   character.

lskey:		derefp	lsiter+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)
		inc	hl
		ret

lspay:		call	lskey
		ld	e,a
		ld	d,0
		add	hl,de
		ret

; symdump - print every symbol: /S.
;
;   In the hash table's order, which is neither alphabetical nor the
;   order of the source. Sorting would need somewhere to put the sorted
;   list, and a reader can scan twenty lines.
;
;   THE NAME IS PRINTED ONE CHARACTER AT A TIME, re-mapping the record
;   for each. The name is in the mapper, and every BDOS call hands page 2
;   back to MSX-DOS - so the mapping is gone after the first character.
;   The alternative is a buffer in ordinary RAM, and a dump that two
;   tests use does not deserve 33 bytes of it.
;
; Input:	nothing
; Output:	the table is printed
; Modifies:	AF, BC, DE, HL, IX

; symdump - the symbol table, grouped by segment. /S.
;
;   ONE COLUMN USED TO MEAN THREE THINGS. A symbol once printed
;   as "name = N seg I", and N was a literal for an absolute, an
;   OFFSET into this module's contribution for a segment-relative one,
;   and an external's INDEX IN THE EXTERNAL TABLE for an external.
;   Three meanings, nothing to tell them apart, in decimal, in
;   hash-bucket order.
;
;   Now the segment carries the meaning, which is what it is for: one
;   section per segment, its own line saying what it is and how big,
;   then its symbols in order of offset. Externals and symbols a
;   PUBLIC named but nothing defined have no address in this module,
;   so they go in sections with no address column at all.
;
;   NOT THE LISTING'S SYMBOL TABLE. emit.as writes that one in M80's
;   layout and cmpm80 compares it; the two walks have been separate
; and stay separate.
;
; Input:	nothing (segnum)
; Output:	the table is printed
; Modifies:	everything

symdump:	call	segpark		; THE LAST CONTRIBUTION'S SIZE IS
					;   STILL LIVE IN locctr. objhead
					;   parks it - and returns at once
					;   when there is no object file, so
					;   under /P the last segment read
					;   0000h. the own run found it
		xor	a
		ld	(sdidx),a
sdmp.sg:	ld	a,(segnum)
		ld	hl,sdidx
		cp	(hl)
		jr	z,sdmp.pl	; every segment done
		call	sdshdr
		call	sdord
		ld	hl,sdidx
		inc	(hl)
		jr	sdmp.sg

sdmp.pl:	ld	hl,msg_sdext	; the two with no address
		ld	(sdhdrp),hl
		ld	b,SYF_EXT
		ld	c,SYF_EXT
		call	sdplain
		ld	hl,msg_sdund
		ld	(sdhdrp),hl
		ld	b,SYF_EXT+SYF_DEF
		ld	c,0
		jp	sdplain

; sdshdr - one segment's heading line.
;
;   THE FIELDS COME OUT OF THE MAPPER FIRST. Printing hands page 2
;   back to MSX-DOS, so a record read after the first _STROUT is read
;   from whatever DOS has put there.
;
; Input:	sdidx
; Output:	the line, and sdsize, sdflag and sdgrp
; Modifies:	everything

sdshdr:		ld	ix,segtab
		ld	c,SG_IDX
		ld	a,(sdidx)
		call	sdfind
		ret	c		; no such index: cannot happen
		call	sdpay
		ld	de,SG_SIZE
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(sdsize),de
		inc	hl
		ld	a,(hl)
		ld	(sdflag),a
		inc	hl
		ld	a,(hl)
		ld	(sdgrp),a

		call	sdname		; IT ANSWERS IN sdresv AND NOT IN A
		ld	de,msg_sddsh	;   FLAG: the _STROUT below would
		system	_STROUT		;   destroy one, and did
		ld	a,(sdflag)
		and	SGF_ABS
		jr	nz,sdsh.ab	; the ASEG is neither code nor data
		ld	a,(sdresv)
		or	a
		jr	z,sdsh.df
		ld	de,msg_sdnmd	; "named "
		system	_STROUT
		jr	sdsh.kd
sdsh.df:	ld	de,msg_sddef	; "default "
		system	_STROUT
sdsh.kd:	ld	a,(sdflag)
		and	SGF_DATA
		ld	de,msg_sdcod
		jr	z,sdsh.kw
		ld	de,msg_sddat
sdsh.kw:	system	_STROUT
		jr	sdsh.tr
sdsh.ab:	ld	de,msg_sdabs
		system	_STROUT

sdsh.tr:	ld	a,(sdflag)
		and	SGF_TRAN
		jr	z,sdsh.gr
		ld	de,msg_sdtrn
		system	_STROUT

sdsh.gr:	ld	a,(sdgrp)
		cp	GRPNONE
		jr	z,sdsh.sz
		ld	de,msg_sdgrp
		system	_STROUT
		ld	ix,grptab
		ld	c,0		; A GROUP RECORD'S PAYLOAD IS ITS
		ld	a,(sdgrp)	;   NUMBER, with nothing in front of
					;   it - objgrps says so too. And its
					;   key is the bare name: only a
					;   SEGMENT's key carries a group byte
		call	sdfind
		jr	c,sdsh.sz	; no such group: cannot happen
		call	sdkey
		ld	(sdklen),a
		xor	a
		ld	(sdkoff),a
		call	sdkstr

sdsh.sz:	ld	a,(sdflag)	; ASEG has no size worth printing
		and	SGF_ABS
		jr	nz,sdsh.nl
		ld	de,msg_sdcom
		system	_STROUT
		ld	hl,(sdsize)
		ld	de,sdhex
		call	numhex
		ld	de,sdhex
		system	_STROUT
		ld	de,msg_sdbyt
		system	_STROUT
sdsh.nl:	ld	de,msg_sdnl
		system	_STROUT
		ld	de,msg_sdnl
		system	_STROUT
		ret

; sdname - the segment's name.
;
;   THE KEY DECIDES, NOT THE INDEX. seginit's three records are keyed
;   " A", " C" and " D" - a space and a letter, which segdir cannot
;   produce from a source line - but they are NOT always indices 0, 1
;   and 2: "group work" then "cseg" makes a second record keyed " C"
;   with a different group and an index of its own, and it is still
;   the default code segment.
;
;   The key's first byte is the group number; the name follows it.
;
; Input:	the iterator is on the record
; Output:	Z set = it was one of the three reserved names
; Modifies:	everything

sdname:		call	sdkey
		dec	a		; without the group byte
		ld	(sdklen),a
		ld	b,a
		inc	hl		; past it
		ld	a,b
		cp	2
		jr	nz,sdnm.own	; only a two-byte name can be one
		ld	a,(hl)
		cp	" "
		jr	nz,sdnm.own
		inc	hl
		ld	a,(hl)
		ld	de,msg_sdas
		cp	"A"
		jr	z,sdnm.w
		ld	de,msg_sdcs
		cp	"C"
		jr	z,sdnm.w
		ld	de,msg_sdds
		cp	"D"
		jr	nz,sdnm.own
sdnm.w:		system	_STROUT
		xor	a
		ld	(sdresv),a	; one of the three
		ret
sdnm.own:	ld	a,1
		ld	(sdkoff),a	; over the group byte
		call	sdkstr
		ld	a,1
		ld	(sdresv),a	; a name of its own
		ret

; sdfind - the record in table IX whose byte at payload offset C holds
;   A. One walk, and the iterator is left on it.
;
;   Serves the segment table and the group table both, which is why it
;   takes the table and the field rather than knowing them.
;
; Input:	IX -> the table, C = the field, A = the value
; Output:	CY clear = sditer is on it
; Modifies:	everything

sdfind:		ld	(sdwant),a
		xor	a
		ld	(sditer),a
		ld	hl,NULLOFF
		ld	(sditer+3),hl
sdfn.lp:	push	bc
		ld	hl,sditer
		call	htnext		; IX SURVIVES IT, and survives sdpay:
		pop	bc		;   objseek has relied on that since
		ret	c		;   and this is its shape
		push	bc
		call	sdpay
		pop	bc
		ld	b,0
		add	hl,bc
		ld	a,(hl)
		ld	hl,sdwant
		cp	(hl)
		jr	nz,sdfn.lp
		or	a		; found it: CY clear
		ret

; sdkstr - sdklen characters of the current record's key, from sdkoff.
;
;   THE KEY IS MAPPED AGAIN FOR EVERY CHARACTER, and the count lives in
;   RAM rather than a register for the same reason: _CONOUT is a BDOS
;   call and page 2 goes back to MSX-DOS with it.
;
; Input:	sdkoff, sdklen, the iterator on a record
; Output:	they are printed
; Modifies:	everything

sdkstr:		ld	a,(sdklen)
		or	a
		ret	z
sdks.lp:	call	sdkey
		ld	a,(sdkoff)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	e,(hl)
		system	_CONOUT
		ld	hl,sdkoff
		inc	(hl)
		ld	hl,sdklen
		dec	(hl)
		jr	nz,sdks.lp
		ret

; sdord - one segment's symbols, in order of offset.
;
; Input:	sdidx
; Output:	they are printed, or "(no symbols)"
; Modifies:	everything

sdord:		ld	hl,0
		ld	(sdcur),hl
		xor	a
		ld	(sdskip),a
		ld	(sdany),a
sdor.lp:	call	sdscan
		jr	nc,sdor.pr	; it printed one
		ld	a,(sdmore)
		or	a
		jr	z,sdor.end
		ld	hl,(sdnext)	; on to the next offset
		ld	(sdcur),hl
		xor	a
		ld	(sdskip),a
		jr	sdor.lp
sdor.pr:	ld	hl,sdskip	; another at the same offset?
		inc	(hl)
		jr	sdor.lp
sdor.end:	ld	a,(sdany)
		or	a
		jr	nz,sdor.nl
		ld	de,msg_sdnon
		system	_STROUT
sdor.nl:	ld	de,msg_sdnl
		system	_STROUT
		ret

; sdscan - ONE walk of the symbol table, doing two jobs at once.
;
;   It prints the record at (sdcur, sdskip) if there is one, and it
;   finds the smallest offset strictly above sdcur for when there is
;   not. Both in the same pass, because the pass is the expensive part.
;
;   THE ORDINAL IS THE TIE-BREAK, and it is why no buffer is needed.
;   Two labels at one address must not print each other forever; the
;   obvious cure is to remember the last NAME, which costs 256 bytes
;   because [R1] allows 255 characters. But the walk is deterministic
;   and nothing changes the table while it runs, so "the third record
;   with this offset, in walk order" is a thing that can be counted to.
;
; Input:	sdidx, sdcur, sdskip
; Output:	CY clear = a line was printed
;		sdnext, sdmore = the next offset up, if any
; Modifies:	everything

sdscan:		xor	a
		ld	(sdcnt),a
		ld	(sdmore),a
		ld	(sdgot),a
		ld	(sditer),a	; start the walk
		ld	hl,NULLOFF
		ld	(sditer+3),hl
sdsc.lp:	ld	ix,symtab
		ld	hl,sditer
		call	htnext
		jr	c,sdsc.end
		call	sdpay
		ld	e,(hl)		; SY_VAL
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)		; SY_TYPE
		inc	hl
		ld	b,(hl)		; SY_FLAGS
		ld	hl,sdidx
		cp	(hl)
		jr	nz,sdsc.lp	; another segment's
		ld	a,b
		and	SYF_EXT
		jr	nz,sdsc.lp	; has a section of its own
		ld	a,b
		and	SYF_DEF
		jr	z,sdsc.lp	;   and so has this one
		ld	a,b
		ld	(sdflags),a

		ld	hl,(sdcur)	; DE = SY_VAL, HL = sdcur
		or	a
		sbc	hl,de
		jr	z,sdsc.same
		jr	c,sdsc.abov	; sdcur < SY_VAL
		jr	sdsc.lp		; below: already printed

sdsc.same:	ld	a,(sdcnt)	; the sdskip-th at this offset
		ld	hl,sdskip
		cp	(hl)
		jr	nz,sdsc.cnt
		ld	a,(sdgot)
		or	a
		jr	nz,sdsc.cnt	; one per pass
		call	sdline
		ld	a,0ffh
		ld	(sdgot),a
		ld	(sdany),a
sdsc.cnt:	ld	hl,sdcnt
		inc	(hl)
		jr	sdsc.lp

sdsc.abov:	ld	a,(sdmore)	; the smallest one above sdcur
		or	a
		jr	z,sdsc.tak
		ld	hl,(sdnext)
		or	a
		sbc	hl,de
		jr	c,sdsc.lp	; sdnext is already smaller
		jr	z,sdsc.lp
sdsc.tak:	ld	(sdnext),de
		ld	a,0ffh
		ld	(sdmore),a
		jr	sdsc.lp

sdsc.end:	ld	a,(sdgot)
		or	a
		scf
		ret	z		; nothing printed
		or	a		; CY clear: one was
		ret

; sdline - one symbol: its offset, its type and its name.
;
;   The four hex digits go into the four bytes in front of "h  $", so
;   the whole column is one _STROUT and there is no arithmetic.
;
; Input:	sdcur, sdflags, the iterator on the record
; Output:	one line
; Modifies:	everything

sdline:		ld	hl,(sdcur)
		ld	de,sdhex
		call	numhex
		ld	de,sdhex
		system	_STROUT
		ld	de,msg_sdgap	; the two spaces a HEADING must not
		system	_STROUT		;   have: it wants "0003h bytes"
		ld	a,(sdflags)
		and	SYF_PUB+SYF_VAR
		ld	de,msg_sdloc
		jr	z,sdln.ty
		cp	SYF_PUB
		ld	de,msg_sdpub
		jr	z,sdln.ty
		cp	SYF_VAR
		ld	de,msg_sdvar
		jr	z,sdln.ty
		ld	de,msg_sdpv
sdln.ty:	system	_STROUT
		call	sdkey
		ld	(sdklen),a
		xor	a
		ld	(sdkoff),a
		call	sdkstr
		ld	de,msg_sdnl
		system	_STROUT
		ret

; sdplain - a section with no address column: the externals, and the
;   symbols a PUBLIC named that nothing defined.
;
;   THE HEADING IS PRINTED ON THE FIRST MATCH, so a module with no
;   externals gets no empty section.
;
; Input:	B = the mask, C = what it must equal
;		sdhdrp -> the heading
; Output:	the section, or nothing at all
; Modifies:	everything

sdplain:	ld	a,b
		ld	(sdmask),a
		ld	a,c
		ld	(sdwant),a
		xor	a
		ld	(sdgot),a
		ld	(sditer),a
		ld	hl,NULLOFF
		ld	(sditer+3),hl
sdpl.lp:	ld	ix,symtab
		ld	hl,sditer
		call	htnext
		jr	nc,sdpl.on
		ld	a,(sdgot)	; a blank line after the section, and
		or	a		;   only if there was a section
		ret	z
		ld	de,msg_sdnl
		system	_STROUT
		ret
sdpl.on:	call	sdpay
		ld	de,SY_FLAGS
		add	hl,de
		ld	a,(hl)
		ld	hl,sdmask
		and	(hl)
		ld	hl,sdwant
		cp	(hl)
		jr	nz,sdpl.lp
		ld	a,(sdgot)
		or	a
		jr	nz,sdpl.nm
		ld	a,0ffh
		ld	(sdgot),a
		ld	de,(sdhdrp)
		system	_STROUT
		ld	de,msg_sdnl
		system	_STROUT
		ld	de,msg_sdnl
		system	_STROUT
sdpl.nm:	ld	de,msg_sdind
		system	_STROUT
		call	sdkey
		ld	(sdklen),a
		xor	a
		ld	(sdkoff),a
		call	sdkstr
		ld	de,msg_sdnl
		system	_STROUT
		jp	sdpl.lp		; jp AND NOT jr: the section heading
					;   at the top of the loop put this
					;   past 127 bytes

; sdkey - map the record the walk is on: HL -> its name, A = how long.
; sdpay - the same, but HL -> its payload.
;
;   EVERY BDOS CALL UNDOES THIS, which is why every caller above calls
;   them again rather than keeping what they returned.

sdkey:		derefp	sditer+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)		; the key's length
		inc	hl
		ret

sdpay:		call	sdkey
		ld	e,a
		ld	d,0
		add	hl,de		; over the name, to the payload
		ret

; sdchar - one character, BC kept.

sdchar:		push	bc
		system	_CONOUT
		pop	bc
		ret

; --- symdump's fragments.

msg_sdas:	defb	"ASEG$"
msg_sdcs:	defb	"CSEG$"
msg_sdds:	defb	"DSEG$"
msg_sddsh:	defb	" - $"
msg_sddef:	defb	"default $"
msg_sdnmd:	defb	"named $"
msg_sdcod:	defb	"code segment$"
msg_sddat:	defb	"data segment$"
msg_sdtrn:	defb	", transient$"
msg_sdgrp:	defb	", group $"
msg_sdabs:	defb	"absolute$"
msg_sdgap:	defb	"  $"
msg_sdcom:	defb	", $"
msg_sdbyt:	defb	" bytes$"
msg_sdnon:	defb	"(no symbols)",CHR_CR,CHR_LF,"$"
msg_sdext:	defb	"EXTERNAL - resolved by the linker$"
msg_sdund:	defb	"UNDEFINED - named by PUBLIC, never defined$"
msg_sdind:	defb	"                  $"
msg_sdloc:	defb	"          $"
msg_sdpub:	defb	"public    $"
msg_sdvar:	defb	"var       $"
msg_sdpv:	defb	"public var$"
msg_sdnl:	defb	CHR_CR,CHR_LF,"$"

; --- the segments
;
;   A SEGMENT is a named pool of storage that the linker concatenates
;   across modules. What the assembler counts is not a segment but a
;   (segment, GROUP) CONTRIBUTION, because that is what one SEGDEF
;   record describes: a name, flags, one group, one size.
;
;   Two contributions with the same name and group are laid end to end,
;   here and across modules: they coexist. With different groups they
;   both start at 0 and overlay, and the segment is as large as its
;   largest group. That is [R4]'s transient DSEG, and it is why a label
;   may only be subtracted from a label in the SAME contribution.
;
;   One hash.as table holds the records, in the mapper, keyed by the
;   group's number followed by the name - so the two groups of one
;   transient DSEG are two keys and two counters, for free. Ordinary RAM
;   holds the bucket arrays, the key, and the far pointer to whichever
;   record is current.
;
;   The classic ASEG, CSEG and DSEG are records like any other, created
;   by seginit under the names " A", " C" and " D". Each holds a space,
;   and segdir ends a name at the first blank, so no source can name
;   them.

; seginit - both tables, and the three classic segments.
;
;   CALLED ONCE, beside syminit and heapinit. NOT per pass: a symbol
;   stored on pass 1 holds a segment index, so the indices have to mean
;   the same thing on pass 2. segrst empties the counters instead.
;
;   It reads optcase, so cmdparse must have run - the same reason
;   syminit sits where it does.
;
; Input:	nothing (optcase)
; Output:	the tables exist
;		indices 0, 1 and 2 are ASEG, CSEG and DSEG
; Modifies:	AF, BC, DE, HL, IX

seginit:	ld	ix,segtab
		ld	a,(optcase)
		ld	b,SGMASK
		call	htinit
		ld	ix,grptab
		ld	a,(optcase)
		ld	b,GRMASK
		call	htinit

		xor	a
		ld	(segnum),a	; the next index to hand out
		ld	(grpnum),a
		ld	hl,NULLOFF	; nothing is current yet, so the
		ld	(cursfp+2),hl	;   first segsel parks nothing

		ld	hl,sgabs	; index 0: ASEG
		ld	a,SGF_ABS
		call	seginit.one
		ld	hl,sgcode	; index 1: the classic CSEG
		xor	a
		call	seginit.one
		ld	hl,sgdata	; index 2: the classic DSEG
		ld	a,SGF_DATA

seginit.one:	ld	(sgflg),a
		ld	(sgnptr),hl
		ld	a,2		; every reserved name is two bytes
		ld	(sgnlen),a
		ld	a,GRPNONE
		ld	(sggrp),a
		jp	segsel

; segrst - every counter and size to zero, the classic CSEG current.
;
;   Per PASS. It walks the table rather than emptying it: the records
;   and their indices must survive, only the counting starts again.
;
; Input:    nothing
; Output:   as above
; Modifies: AF, BC, DE, HL, IX

segrst:		ld	hl,NULLOFF	; nothing is current: segsel must
		ld	(cursfp+2),hl	;   not park pass 1's counter into
					;   a record we are about to clear
		xor	a
		ld	(sgiter),a	; start the walk: bucket 0...
		ld	hl,NULLOFF
		ld	(sgiter+3),hl	; ...and no record yet

segrst.lp:	ld	ix,segtab
		ld	hl,sgiter
		call	htnext		; CY set = that was the last one
		jr	c,segrst.end
		derefp	sgiter+1	; HL -> the record
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)		; the key's length...
		inc	hl
		ld	e,a
		ld	d,0
		add	hl,de		; ...steps over the key
		ld	b,4		; SG_CTR and SG_SIZE, four bytes
segrst.z:	ld	(hl),0
		inc	hl
		djnz	segrst.z
		jr	segrst.lp

segrst.end:	ld	hl,sgcode	; M80 starts every module in CSEG
		ld	(sgnptr),hl
		ld	a,2
		ld	(sgnlen),a
		xor	a
		ld	(sgflg),a
		ld	a,GRPNONE
		ld	(sggrp),a
		jp	segsel

; segdir - an ASEG, CSEG or DSEG line.
;
;   The operand is a name, optionally followed by ",TRANSIENT". The name
;   is everything up to the first blank, tab or comma, so no character
;   set has to be defined for it. No name at all means the classic
;   unnamed segment of that kind.
;
;   A fresh mention opens no group: inside a transient DSEG a GROUP line
;   has to come before anything is placed, which is what segwr checks.
;
; Input:	A  = 0 for ASEG, 1 for CSEG, 2 for DSEG
;		DE -> the operand field
;		B  = its length
; Output:	that segment is current
; 		(a bad line does not return - errseg stops)
; Modifies:	AF, BC, DE, HL, IX

segdir:		ld	(sgkind),a
		call	sgws		; over any blanks in front
		push	de		; where the name starts
		ld	c,0		; how long it is

segdir.nm:	ld	a,b
		or	a
		jr	z,segdir.got
		ld	a,(de)
		cp	" "
		jr	z,segdir.got
		cp	CHR_TAB
		jr	z,segdir.got
		cp	","
		jr	z,segdir.got
		inc	de
		inc	c
		dec	b
		jr	segdir.nm
segdir.got:	pop	hl		; HL -> the name, C = its length
		ld	(sgnptr),hl
		ld	a,c
		ld	(sgnlen),a

		ld	a,(sgkind)	; ASEG takes no operand at all
		or	a
		jr	nz,segdir.cd
		ld	a,c
		or	a
		jp	nz,errseg
		ld	hl,sgabs	; and it has a name of its own
		ld	(sgnptr),hl
		ld	a,2
		ld	(sgnlen),a
		ld	a,SGF_ABS
		jr	segdir.flg

segdir.cd:	ld	a,c		; CSEG or DSEG with no name: the
		or	a		;   classic one, under its own name
		jr	nz,segdir.k
		ld	hl,sgcode
		ld	a,(sgkind)
		dec	a
		jr	z,segdir.cn
		ld	hl,sgdata
segdir.cn:	ld	(sgnptr),hl
		ld	a,2
		ld	(sgnlen),a

segdir.k:	ld	a,(sgkind)	; 1 = CSEG, 2 = DSEG
		dec	a
		ld	a,0		; ld does not touch the flags, so
		jr	z,segdir.flg	;   the dec above still decides
		ld	a,SGF_DATA
segdir.flg:	ld	(sgflg),a

		call	sgws		; anything after the name?
		ld	a,b
		or	a
		jr	z,segdir.end
		ld	a,(de)
		cp	","
		jp	nz,errseg
		inc	de
		dec	b
		call	sgws
		ld	a,b		; the only word allowed there is
		cp	9		;   TRANSIENT, nine characters
		jp	c,errseg
		ld	hl,sgtran
		ld	c,9
segdir.tr:	ld	a,(de)
		call	strupr
		cp	(hl)
		jp	nz,errseg
		inc	de
		inc	hl
		dec	b
		dec	c
		jr	nz,segdir.tr
		call	sgws
		ld	a,b		; and nothing after it
		or	a
		jp	nz,errseg
		ld	a,(sgflg)	; TRANSIENT is for a DSEG only
		and	SGF_DATA
		jp	z,errseg
		ld	a,(sgflg)
		or	SGF_TRAN
		ld	(sgflg),a

segdir.end:	ld	a,GRPNONE	; a fresh mention opens no group
		ld	(sggrp),a
		jp	segsel

; seggrp - a GROUP line: open a coexistence group inside the current
;   transient DSEG.
;
;   The group's number is global to the program, so the same name in two
;   modules is one group and their variables are laid end to end. A
;   different group of the same DSEG starts again at 0 and overlays it.
;
; Input:	DE -> the operand field
; 		B  = its length
; Output:	the (segment, group) contribution is current
; 		(a bad line does not return - errgrp stops)
; Modifies:	AF, BC, DE, HL, IX

seggrp:		ld	a,(sgflg)	; only inside a transient DSEG
		and	SGF_TRAN
		jp	z,errgrp
		call	sgws
		ld	a,b		; the name is the rest of the
		or	a		;   operand, blanks trimmed
		jp	z,errgrp
		cp	SGNMAX+1
		jp	nc,errseg

		ld	ix,grptab	; its number, or the next free one
		ld	a,b
		ld	hl,sgpay
		push	de
		push	bc
		call	htfind		; CY set = a new group
		pop	bc
		pop	de
		jr	nc,seggrp.old

		ld	a,b
		ld	bc,1		; the payload is its number
		ld	hl,sgpay
		call	htadd
		jp	c,errheap
		ld	a,(grpnum)
		cp	MAXSEGS
		jp	nc,errmseg
		ld	(sggrp),a	; the number this name now has.
		inc	a		;   In RAM, not in B: derefp goes
		ld	(grpnum),a	;   through deref, which clobbers BC
		derefp	sgpay
		ld	a,(sggrp)
		ld	(hl),a
		jr	seggrp.sel

seggrp.old:	derefp	sgpay
		ld	a,(hl)
		ld	(sggrp),a

seggrp.sel:	ld	hl,sgkey+1	; the same segment, the new group.
		ld	(sgnptr),hl	;   segsel left the current name in
					;   sgkey, where nothing moves it
		ld	a,(sgklen)
		dec	a		; the key is the group byte + name
		ld	(sgnlen),a
		jp	segsel

; segsel - make a (segment, group) contribution current, creating its
;   record the first time it is named.
;
; Input:	sgnptr -> the name
; 		sgnlen = its length, 1..SGNMAX
; 		sgflg  = SGF_DATA / SGF_TRAN / SGF_ABS
; 		sggrp  = the group's number, GRPNONE if none
; Output:	locctr, curseg and cursfp describe it
; 		sgnptr points at the copy inside sgkey
; 		(errseg, errsflg, errmseg and errheap do not return)
; Modifies:	AF, BC, DE, HL, IX

segsel:		ld	a,(sgnlen)
		cp	SGNMAX+1
		jp	nc,errseg	; longer than the key can hold
		ld	c,a
		ld	b,0
		ld	a,(sggrp)
		ld	(sgkey),a	; the key is the group's number...
		ld	hl,(sgnptr)
		ld	de,sgkey+1
		ld	a,c
		or	a
		jr	z,segsel.k	; ldir with BC = 0 copies 65536
		ldir			; ...and then the name
segsel.k:	ld	a,(sgnlen)
		inc	a
		ld	(sgklen),a
		ld	hl,sgkey+1	; from here the current name is
		ld	(sgnptr),hl	;   this copy, which nothing moves

		call	segpark		; the counter we are leaving

		ld	ix,segtab
		ld	de,sgkey
		ld	a,(sgklen)
		ld	hl,sgpay
		call	htfind		; CY set = its first mention
		jr	nc,segsel.old

		ld	de,sgkey
		ld	a,(sgklen)
		ld	bc,SGSIZE
		ld	hl,sgpay
		call	htadd
		jp	c,errheap
		ld	a,(segnum)	; the index it will answer to.
		cp	MAXSEGS		;   Kept in RAM, not in B: derefp
		jp	nc,errmseg	;   goes through deref, and deref
		ld	(sgidx),a	;   clobbers BC
		inc	a
		ld	(segnum),a
		derefp	sgpay		; a new record: fill it in
		ld	(hl),0		; SG_CTR
		inc	hl
		ld	(hl),0
		inc	hl
		ld	(hl),0		; SG_SIZE
		inc	hl
		ld	(hl),0
		inc	hl
		ld	a,(sgflg)
		ld	(hl),a		; SG_FLAGS
		inc	hl
		ld	a,(sgkey)
		ld	(hl),a		; SG_GRP: the key's first byte
		inc	hl
		ld	a,(sgidx)
		ld	(hl),a		; SG_IDX
		jr	segsel.use

segsel.old:	derefp	sgpay		; it exists: it must be the same
		ld	de,SG_FLAGS	;   kind of segment as last time
		add	hl,de
		ld	a,(sgflg)
		cp	(hl)
		jp	nz,errsflg

segsel.use:	derefp	sgpay
		ld	e,(hl)		; SG_CTR: the counter goes live
		inc	hl
		ld	d,(hl)
		ld	(locctr),de
		ld	de,SG_IDX-1	; HL is at SG_CTR+1
		add	hl,de
		ld	a,(hl)		; SG_IDX
		ld	(curseg),a
		fpcopy	cursfp,sgpay	; where segpark will write back
		ret

; segpark - write the live counter back into the record it came from,
;   and keep the high-water mark.
;
;   The size is a high-water mark rather than a count because ORG can
;   move the counter backwards. It is what the SEGDEF record will carry
;   in the object file.
;
; Input:	locctr, cursfp
; Output:	that record's SG_CTR and SG_SIZE are up to date
; Modifies:	AF, BC, DE, HL

segpark:	ld	hl,(cursfp+2)	; null = nothing is current yet
		ld	de,NULLOFF
		or	a
		sbc	hl,de
		ret	z
		derefp	cursfp
		ld	de,(locctr)
		ld	(hl),e		; SG_CTR
		inc	hl
		ld	(hl),d
		inc	hl
		ld	c,(hl)		; SG_SIZE
		inc	hl
		ld	b,(hl)
		ld	h,d		; HL = the counter
		ld	l,e
		or	a
		sbc	hl,bc		; counter - size
		ret	c		; the size is still the larger
		derefp	cursfp		; a new high-water mark
		ld	bc,SG_SIZE
		add	hl,bc
		ld	de,(locctr)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ret

; segwr - may a label or the location counter be placed here?
;
;   Inside a transient DSEG nothing may, until a GROUP line has said
;   what it is allowed to overlay. Called by deflab, ORG, DS, the data
;   directives and every instruction.
;
; Input:	sgflg, sggrp
; Output:	returns, or errngrp stops
; Modifies:	AF

segwr:		ld	a,(sgflg)
		and	SGF_TRAN
		ret	z		; an ordinary segment: anything goes
		ld	a,(sggrp)
		inc	a		; GRPNONE + 1 = 0
		ret	nz
		jp	errngrp

; sgws - step DE over blanks and tabs, B counting down what is left.
;
; Input:	DE -> the text
; 		B  = how much of it is left
; Output:	DE and B at the first character that is not a blank
; Modifies:	AF, B, DE

sgws:		ld	a,b
		or	a
		ret	z
		ld	a,(de)
		cp	" "
		jr	z,sgws.eat
		cp	CHR_TAB
		ret	nz
sgws.eat:	inc	de
		dec	b
		jr	sgws

; --- the reserved names. Each holds a space, which segdir can never
;     put in a name, so no source can reach these three segments by
;     name - only through ASEG, CSEG and DSEG themselves.

sgabs:		defb	" A"
sgcode:		defb	" C"
sgdata:		defb	" D"
sgtran:		defb	"TRANSIENT"

		dseg

synam:		defs	2	; symset: the name it was given
sylen:		defs	1	;   and its length
syval:		defs	2	;   and the value to store
sytyp:		defs	1	;   and the type
sypay:		defs	4	; far pointer to a record's payload
symfl:		defs	1	; symlook: the flags it found
sydflg:		defs	1	; symdef: the flags the caller asked for,
				;   and symdump: the flags it is printing
sdold:		defs	2	; symdef: what the symbol was worth
sdoldt:		defs	1	;   and its segment, for symdump too
sditer:		defs	5	; symdump's walk over the table
sdidx:		defs	1	; the segment index being dumped
sdsize:		defs	2	; that segment's fields, out of the mapper
sdflag:		defs	1	;   BEFORE the first _STROUT takes page 2
sdgrp:		defs	1	;   back to MSX-DOS
sdkoff:		defs	1	; sdkstr's walk: where it is,
sdklen:		defs	1	;   and how much is left
sdcur:		defs	2	; the offset being printed,
sdskip:		defs	1	;   and how many at it are done
sdcnt:		defs	1	; how many at it this pass has seen
sdnext:		defs	2	; the smallest offset above sdcur,
sdmore:		defs	1	;   and whether there was one
sdgot:		defs	1	; this pass printed a line
sdany:		defs	1	; this segment printed any
sdflags:	defs	1	; the record's SY_FLAGS, for the type
sdmask:		defs	1	; sdplain's test,
sdwant:		defs	1	;   and sdfind's value
sdhdrp:		defs	2	; sdplain's heading
sdresv:		defs	1	; sdname's answer: 0 = ASEG, CSEG or DSEG
sdhex:		defs	4	; numhex writes the digits HERE, and the
		defb	"h$"	;   "h" is in place. The two spaces after
				;   it on a symbol line are sdline's, so
				;   that a heading can say "0003h bytes"
lsiter:		defs	5	; and lstsyms's, over the same one
lsbuf:		defs	5	; four digits and the relocation mark
lsseg:		defs	1	; which segment this symbol is in
lscol:		defs	1	; how many are on this line, 0 to 2
extnum:		defs	1	; the next external index to hand out
symtab:		defs	2+SYBUCKS*4

locctr:		defs	2	; the live location counter: the current
				;   contribution's
curseg:		defs	1	; that contribution's index
cursfp:		defs	4	; and where its record is, for segpark
sgnptr:		defs	2	; segsel's inputs: the name,
sgnlen:		defs	1	;   its length,
sgflg:		defs	1	;   the flags, and afterwards the current
				;   segment's flags
sggrp:		defs	1	;   the group, and afterwards the current
                		;   group's number
sgkind:		defs	1	; segdir: 0 ASEG, 1 CSEG, 2 DSEG
sgidx:		defs	1	; segsel: the index it is handing out
sgkey:		defs	1+SGNMAX	; the key: the group's number, the name
sgklen:		defs	1	;   and its length
sgpay:		defs	4	; far pointer to a record's payload
sgiter:		defs	5	; segrst's walk over the table
segnum:		defs	1	; the next segment index to hand out
grpnum:		defs	1	; the next group number
segtab:		defs	2+SGBUCKS*4
grptab:		defs	2+GRBUCKS*4
