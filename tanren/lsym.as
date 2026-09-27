; lsym.as - the link's symbols, all of them in one table.
;
; A record is seven bytes: the flags, the value, and a far pointer to
; the segment the value is measured in. THE VALUE IS ALREADY
; RELATIVE TO THE COMBINED SEGMENT - lsgsm hands over the module's
; base and lsypub adds it - so the layout adds one address per symbol
; and never looks at a module again.

LSYMLIB		equ	1	; skips the externals in lsym.inc

		public	lsyinit
		public	lsycase
		public	lsypub
		public	lsyext
		public	lsyfix
		public	lsyval
		public	lsychk
		public	lsymod
		public	lsydump
		public	lsfld2

		include	lsym.inc
		include	lseg.inc	; lsgsm, lsgcase, lsgnam, lsnamp,
					;   and the SGP_BAS
		include	lobj.inc	; lobbuf, lobsln
		include	lerrs.inc
		include	hash.inc
		include	alloc.inc	; derefp
		include	farptr.inc
		include	msxdos.inc	; putsz
		include	strutil.inc	; numhex
		include	ascii.inc

		cseg

; lsyinit - the table, empty, in the default mode.
;
; Input:	nothing
; Output:	the table is ready
; Modifies:	AF, BC, DE, HL, IX

lsyinit:	ld	a,HTCASEI
		call	lsyicase
		xor	a
		ld	(lsycgot),a
		ret

; lsyicase - the table's case mode, for lsycase to set again once it
;   knows. htinit only empties buckets, and nothing has been added.
;
; Input:	A = HTCASES or HTCASEI
; Output:	the table is empty and in that mode
; Modifies:	AF, BC, DE, HL, IX

lsyicase:	ld	ix,lsymtab
		ld	b,LSYBKTS-1
		jp	htinit

; lsycase - MODNAME's flags byte.
;
;   BIT 0 SAYS THE MODULE WAS ASSEMBLED /C. The first module decides
;   the whole link's mode - it is the only moment the tables can
;   still be re-formatted - and a later module that disagrees is
;   refused, because a mixed link resolves some symbols and silently
;   fails to resolve others.
;
; Input:	A = the flags byte from MODNAME
; Output:	the mode is set, or checked (errlymix does not return)
; Modifies:	AF, BC, DE, HL, IX

lsycase:	and	1		; HTCASES is 0 and HTCASEI is 1, so
		xor	1		;   the flag and the mode are
		ld	c,a		;   opposites: /C means SENSITIVE
		ld	a,(lsycgot)
		or	a
		jr	nz,lsyc.cmp
		ld	a,0ffh		; the first module: it decides
		ld	(lsycgot),a
		ld	a,c
		ld	(lsycas),a
		push	bc
		call	lsgcase		; all three tables, before any of
		pop	bc		;   them holds a record
		ld	a,c
		jp	lsyicase
lsyc.cmp:	ld	a,(lsycas)
		cp	c
		ret	z
		jp	errlymix

; lsymod - a module is starting: keep its name.
;
;   ONE NAME AT A TIME, not one per symbol. D4: a duplicate public
;   names the module it was found in, and that is this one. Sixteen
;   characters is enough for a filename's basename, which is what
;   MODNAME holds, and a longer one is cut rather than refused.
;
; Input:	lobbuf, lobsln
; Output:	lmodnam, zero-terminated
; Modifies:	AF, BC, DE, HL

lsymod:		ld	a,(lobsln)
		cp	LMODMAX
		jr	c,lsym.ok
		ld	a,LMODMAX-1
lsym.ok:	ld	c,a
		ld	b,0
		ld	hl,lobbuf
		ld	de,lmodnam
		ldir
		xor	a
		ld	(de),a
		ret

; lsyfind - the record for the name in lobbuf, made if it is new.
;
; Input:	lobbuf, lobsln
; Output:	lspay2 = its payload far pointer
;		CY set = it was new, and its flags are zero
;		(errlheap does not return)
; Modifies:	AF, BC, DE, HL, IX

lsyfind:	ld	ix,lsymtab
		ld	de,lobbuf
		ld	a,(lobsln)
		ld	hl,lspay2
		call	htfind
		ret	nc
		ld	ix,lsymtab
		ld	de,lobbuf
		ld	a,(lobsln)
		ld	bc,LSYSIZE
		ld	hl,lspay2
		call	htadd
		jp	c,errlheap
		derefp	lspay2
		ld	(hl),0		; nothing is known about it yet
		scf
		ret

; lsypub - a PUBDEF entry.
;
;   THE VALUE IS MADE SEGMENT-RELATIVE HERE, while the module's base
;   is still in hand. That is the whole reason the table keeps the
;   base beside the record.
;
; Input:	lsfld2 = segment index, offset; lobbuf = the name
; Output:	the symbol is defined (errlydup does not return)
; Modifies:	everything

lsypub:		ld	a,(lsfld2)
		cp	0ffh
		jr	z,lsyp.abs
		call	lsgsm		; -> lsgptr, lsgbas
		ld	hl,(lsfld2+1)	; the offset within its module
		ld	de,(lsgbas)
		add	hl,de		; and now within the whole segment
		ld	(lsyrec+1),hl
		ld	hl,lsgptr	; which segment that is
		ld	de,lsyrec+3
		ld	bc,4
		ldir
		ld	a,SYF_DEF
		jr	lsyp.flg
lsyp.abs:	ld	hl,(lsfld2+1)	; an absolute public: the value is
		ld	(lsyrec+1),hl	;   an address already
		ld	a,SYF_DEF+SYF_ABS
lsyp.flg:	ld	(lsyrec),a

		call	lsyfind
		derefp	lspay2
		ld	a,(hl)
		ld	(lsyold),a	; what was known before
		and	SYF_DEF
		jp	nz,lsyp.dup
		ld	a,(lsyold)	; KEEP SYF_REF if somebody had
		ld	hl,lsyrec	;   already asked for this name
		or	(hl)
		ld	(hl),a
		derefp	lspay2
		ex	de,hl
		ld	hl,lsyrec
		ld	bc,LSYSIZE
		ldir
		ret

lsyp.dup:	ld	de,msg_ydup1	; the name and the module, before
		call	putsz		;   the error, because the message
		ld	de,lobbuf	;   itself names neither.
		call	putsz		; AND THE NAME IS ALREADY HERE,
					;   zero-terminated by lobstr.
					;   lsynam prints the record a WALK
					;   is standing on, and no walk is in
					;   progress - it printed 255 bytes
					;   of whatever lsyit held
		ld	de,msg_ydup2
		call	putsz
		ld	de,lmodnam
		call	putsz
		ld	de,msg_ycrlf
		call	putsz
		jp	errlydup

; lsyext - an EXTDEF entry.
;
;   It says only that somebody wants the name. Everything else about
;   a symbol belongs to whichever module defines it.
;
; Input:	lobbuf = the name
; Output:	SYF_REF is set
; Modifies:	everything

lsyext:		call	lsyfind
		derefp	lspay2
		ld	a,(hl)
		or	SYF_REF
		ld	(hl),a
		ret

; lsyval - the final value of the name in lobbuf.
;
;   PASS 2 CALLS IT ONCE PER EXTDEF, to build the map a RELOC's
;   external index points into. By then lsychk has stopped the program
;   if anything was undefined and lsyfix has turned every value into
;   an address, so there is nothing to check and nothing to add.
;
;   If the name were somehow new, lsyfind would make a record and this
;   would answer zero. It cannot happen; answering zero rather than
;   reading an uninitialised payload is what makes that true instead
;   of nearly true.
;
; Input:	lobbuf, lobsln
; Output:	HL = its value
; Modifies:	everything

lsyval:		call	lsyfind
		jr	c,lsyv.new
		derefp	lspay2
		inc	hl
		ld	c,(hl)		; IN BC: nothing else is free of
		inc	hl		;   the deref above
		ld	b,(hl)
		ld	h,b
		ld	l,c
		ret
lsyv.new:	ld	hl,0
		ret

; lsyfix - every symbol's value becomes an address.
;
;   AFTER lsglay, and only for symbols that are defined and not
;   absolute: an undefined symbol's segment pointer means nothing,
;   and an absolute one is an address already. SYF_ABS exists so
;   that this routine cannot forget.
;
; Input:	nothing (the table, and every segment placed)
; Output:	every defined value is final
; Modifies:	everything

lsyfix:		call	lsyfrst
lsyf.lp:	ld	ix,lsymtab
		ld	hl,lsyit
		call	htnext
		ret	c
		call	lsyflg
		ld	a,(lsyfl)
		and	SYF_DEF
		jr	z,lsyf.lp	; nobody defined it
		ld	a,(lsyfl)
		and	SYF_ABS
		jr	nz,lsyf.lp	; it is an address already
		call	lsypl		; HL -> its payload
		ld	de,3
		add	hl,de
		ld	de,lsyseg	; its segment, out of the mapper
		ld	bc,4
		ldir
		derefp	lsyseg		; and that segment's base
		ld	de,SGP_BAS
		add	hl,de
		ld	c,(hl)
		inc	hl
		ld	b,(hl)		; IN BC: the deref below destroys DE
		ld	hl,(lsyvl)
		add	hl,bc
		ld	(lsyvl),hl
		call	lsypl
		inc	hl
		ld	a,(lsyvl)
		ld	(hl),a
		inc	hl
		ld	a,(lsyvl+1)
		ld	(hl),a
		jp	lsyf.lp

; lsypl - the payload of the record lsyit is on.
;
; Input:	lsyit is on a record
; Output:	HL -> the payload
; Modifies:	AF, BC, DE, HL

lsypl:		derefp	lsyit+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)
		ld	c,a		; IN BC across the deref
		ld	b,0
		derefp	lsyit+1
		add	hl,bc
		ld	bc,HTHDR
		add	hl,bc
		ret

; lsychk - END OF PASS 1: every external nobody defined.
;
;   ALL OF THEM, and then the error. Every other error in both
;   programs stops at the first; this one does not, because a
;   fifty-module link missing three symbols would otherwise take
;   three runs to learn three names. The departure is deliberate.
;
; Input:	nothing
; Output:	nothing, or the names and errlyunr, which does not
;		return
; Modifies:	everything

lsychk:		xor	a
		ld	(lsymiss),a
		call	lsyfrst
lsyc.lp:	ld	ix,lsymtab
		ld	hl,lsyit
		call	htnext
		jr	c,lsyc.end
		call	lsyflg		; its flags, out of the mapper
		ld	a,(lsyfl)
		and	SYF_REF
		jr	z,lsyc.lp
		ld	a,(lsyfl)
		and	SYF_DEF
		jr	nz,lsyc.lp
		ld	a,(lsymiss)	; the first one prints a heading
		or	a
		jr	nz,lsyc.nm
		ld	de,msg_yunr
		call	putsz
lsyc.nm:	ld	de,msg_yind
		call	putsz
		call	lsynam
		ld	de,msg_ycrlf
		call	putsz
		ld	hl,lsymiss
		inc	(hl)
		jr	lsyc.lp
lsyc.end:	ld	a,(lsymiss)
		or	a
		ret	z
		jp	errlyunr

; lsydump - /M: the symbols.
;
; Input:	nothing
; Output:	one line each
; Modifies:	everything

lsydump:	ld	de,msg_ysyms
		call	putsz
		call	lsyfrst
lsyd.lp:	ld	ix,lsymtab
		ld	hl,lsyit
		call	htnext
		ret	c
		call	lsyflg		; flags and value, into RAM first
		ld	de,msg_yind
		call	putsz
		ld	a,(lsyfl)
		and	SYF_DEF
		ld	de,msg_ydef
		jr	nz,lsyd.d
		ld	de,msg_ynot
lsyd.d:		call	putsz
		ld	a,(lsyfl)
		and	SYF_REF
		ld	de,msg_yref
		jr	nz,lsyd.r
		ld	de,msg_ynot
lsyd.r:		call	putsz
		ld	de,msg_ysp
		call	putsz
		ld	a,(lsyfl)	; NO VALUE FOR A SYMBOL NOBODY HAS
		and	SYF_DEF		;   DEFINED: the bytes in the record
		ld	de,msg_yudef	;   are whatever htadd left there,
		jr	z,lsyd.v	;   and printing them suggests they
		ld	hl,(lsyvl)	;   mean something
		ld	de,lsyhex
		call	numhex
		ld	hl,lsyhex+4
		ld	(hl),0
		ld	de,lsyhex
lsyd.v:		call	putsz
		ld	de,msg_ysp
		call	putsz
		call	lsynam
		ld	de,msg_ycrlf
		call	putsz
		jp	lsyd.lp		; jp for the same reason

; lsyflg - the record lsyit is on: its flags and value, in ordinary
;   RAM before anything is printed. The page 2 rule, again.
;
; Input:	lsyit is on a record
; Output:	lsyfl, lsyvl
; Modifies:	AF, BC, DE, HL

lsyflg:		call	lsypl
		ld	a,(hl)
		ld	(lsyfl),a
		inc	hl
		ld	a,(hl)
		ld	(lsyvl),a
		inc	hl
		ld	a,(hl)
		ld	(lsyvl+1),a
		ret

; lsynam - this symbol's name, through lseg.as's printer.
;
;   A symbol's key is its name with nothing in front of it, so the
;   skip is zero.
;
; Input:	lsyit is on a record
; Output:	the name is printed
; Modifies:	everything

lsynam:		ld	hl,lsyit+1
		ld	de,lsnamp
		ld	bc,4
		ldir
		xor	a
		ld	(lsskp),a
		jp	lsgnam

lsyfrst:	xor	a
		ld	(lsyit),a
		ld	hl,NULLOFF
		ld	(lsyit+3),hl
		ret

		dseg

lsymtab:	defs	2+LSYBKTS*4	; the descriptor: 258 bytes of
					;   ordinary RAM, records in the
					;   mapper
lsfld2:		defs	3	; a PUBDEF's segment and offset
lsyrec:		defs	LSYSIZE	; one record, built before it is stored
lsyold:		defs	1	; the flags it had before
lspay2:		defs	4	; htfind and htadd's answer
lsyit:		defs	5	; a walk: the bucket, then htnext's
lsyfl:		defs	1	; one record, in ordinary RAM
lsyvl:		defs	2
lsymiss:	defs	1	; how many externals went undefined
lsycgot:	defs	1	; 0 until the first MODNAME has spoken
lsycas:		defs	1	;   and then HTCASES or HTCASEI
lsyhex:		defs	5	; numhex's answer, zero-terminated
lsyseg:		defs	4	; lsyfix: the symbol's segment, out of
				;   the mapper before it is dereffed
lmodnam:	defs	LMODMAX	; THE MODULE BEING READ, for the
				;   messages that name one

msg_ysyms:	defb	"Symbols:",CHR_CR,CHR_LF,0
msg_yind:	defb	"  ",0
msg_ydef:	defb	"D",0
msg_yref:	defb	"R",0
msg_ynot:	defb	"-",0
msg_ysp:	defb	" ",0
msg_ycrlf:	defb	CHR_CR,CHR_LF,0
msg_yunr:	defb	"Never defined:",CHR_CR,CHR_LF,0
msg_yudef:	defb	"----",0
msg_ydup1:	defb	"  ",0
msg_ydup2:	defb	" is defined again in module ",0
