; macros.as - macro definitions: collecting them and storing them.
;
; The body goes into mapper RAM: a name table
; record pointing at a descriptor, and a chain of 2048-byte blocks
; holding one record per body line. The text is stored EXACTLY as read -
; turning parameter references into markers is the next note's job.
;
; The discipline this file introduces, and never breaks:
;
;   an address from deref is valid only until the next deref, halloc,
;   hfree, ht* call, p2restore, or BDOS call.
;
; So anything needed after one of those is copied into ordinary RAM
; first. macdump below is built entirely around that rule.
;
; macdef is not re-entrant, and does not need to be: a MACRO line inside
; a body is text during collection, and only becomes a definition when
; the outer macro is expanded, long after this has finished.


MACSLIB		equ	1		; skips the external in macros.inc

		public	macinit
		public	macrst
		public	macfind
		public	macdef
		public	macrept
		public	mdorph
		public	macname
		public	macdump
		public	lstmacs

		include	macros.inc
		include	srcline.inc
		include	fields.inc
		include	dirtab.inc
		include	mdt.inc
		include	msxdos.inc
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been cleared
		include	hash.inc
		include	ascii.inc

SEMIC		equ	03bh		; ;
QUOTE1		equ	027h		; '
QUOTE2		equ	022h		; "
AMPER		equ	026h		; &

		include	errs.inc
		include	strutil.inc	; strupr: names fold before hashing
		include	cmdline.inc	; optcase: the case mode macinit hashes in
		include	emit.inc	; lstbody, emitchr, lstcrlf: M80
					;   lists the lines a
					;   definition is made of, and this
					;   module is the only thing that
					;   sees them
		include	expand.inc	; mxbfree: free a descriptor and its
					;   body chain

		cseg

; macinit - format the macro name table as empty.
;
;   ONCE PER RUN, beside syminit and heapinit - NOT per pass. dseg space
;   holds whatever MSX-DOS left in it, so the bucket array has to be
;   written before anything walks it, and macrst walks it. Emptying the
;   table between passes is macrst's job.
;
; Input:	nothing (heapinit and cmdparse must have run)
; Output:	the table is empty
; Modifies:	AF, BC, DE, HL, IX

macinit:	ld	ix,mnt
		ld	a,(optcase)	; /C reaches macro names as well as symbols:
		ld	b,MNMASK	; both are names the programmer invents, and
		jp	htinit		; macfind runs on the same text, on the same
					; line, as a symbol look-up

; macrst - free every macro definition and leave the table empty.
;
;   ONCE PER PASS. Pass 2 must start with the table exactly as pass 1
;   found it. Keeping pass 1's definitions was considered and refused:
;   a macro CALLED before it is DEFINED would be plain text on pass 1
;   and an expansion on pass 2, so the same line would be sized one way
;   and emitted another - a phase error one layer below where the phase
;   check can see it.
;
;   TWO SWEEPS, AND THE ORDER IS WHAT MAKES IT SAFE. The first frees
;   what each record's PAYLOAD points at - the descriptor and its body
;   chain, which mxbfree does in one call - and leaves the records
;   themselves alone, so htnext's position stays valid. htclear then
;   frees the records in one go. Freeing a record during the walk would
;   pull the ground out from under the iterator.
;
;   THE PAGE 2 RULE: the payload is copied into ordinary RAM before
;   mxbfree is called, because mxbfree derefs and would take the mapping
;   away from under the record being read.
;
;   Calling it before pass 1 as well costs nothing - htnext on an empty
;   table returns at once, and htclear on one does nothing - and uniform
;   beats conditional.
;
; Input:	nothing (macinit must have run)
; Output:	every descriptor and body block freed, the table empty
; Modifies:	AF, BC, DE, HL, IX

macrst:		xor	a		; start a walk: bucket 0, and the
		ld	(mfiter),a	; iterator's offset field null
		ld	hl,NULLOFF
		ld	(mfiter+3),hl

macrst.lp:	ld	ix,mnt
		ld	hl,mfiter
		call	htnext
		jr	c,macrst.end	; no more records

		derefp	mfiter+1	; HL -> this record, mapped
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)		; HT_KLEN
		inc	hl		; HL -> HT_KEY
		ld	e,a
		ld	d,0
		add	hl,de		; HL -> the payload, MN_MD
		fpsave	mfmd		; into ordinary RAM: mxbfree derefs

		ld	hl,mfmd
		call	mxbfree
		jr	macrst.lp

macrst.end:	ld	ix,mnt
		jp	htclear		; and now the records themselves

; macfind - is this operation the name of a macro?
;
;   The name table's payload is a far pointer to the descriptor, not the
;   descriptor itself - which is what lets a macro be redefined while it
;   is expanding without pulling the ground out from under the running
;   replay (mdt-design.md 5).
;
; Input:	DE -> the operation text, B = its length
;		HL -> a 4-byte buffer for the answer
; Output:	CY clear = it is a macro; the buffer holds the descriptor's
;		           far pointer
;		CY set   = it is not
; Modifies:	AF, BC, DE, HL, IX

macfind:	ld	a,b
		or	a
		scf
		ret	z		; no operation on this line at all
		push	hl		; where the answer goes. The stack
		ld	ix,mnt		; is the cheapest place to keep it:
		ld	hl,mdpay	; htfind is the only thing in the way
		ld	a,b		; and it leaves the stack alone
		call	htfind		; CY set = not in the table
		jr	c,macfind.no
		derefp	mdpay		; HL -> the payload, mapped
		pop	de
		ld	bc,4
		ldir			; out of the heap, into the caller's
		or	a		; buffer. Clear CY = found
		ret

macfind.no:	pop	hl		; pop does not touch the flags, so
		ret			; the CY htfind set is still there

; macrept - collect an unnamed body, for REPT, IRP and IRPC.
;
;   The same collector macdef uses, with a different prologue: no name is
;   taken and no name table entry is made, so nothing can ever look this
;   body up. It is reachable only through the expansion record the driver
;   is about to push, and it is freed when that record is.
;
;   It ends by jumping into macdef's own loop, which is why macrept sits
;   directly above it. Everything from macdef.next down is shared.
;
; Input:	HL -> a line buffer to use, MAXLINE+3 bytes
;		A   = MD_KIND for this block
;		IX -> the field block, with FL_ARGL already cut short at
;		      the dummy's comma. Read only when the kind is not
;		      MDK_REPT - a REPT has no dummy
; Output:	the body is stored; HL -> the descriptor's far pointer
;		(errors do not return)
; Modifies:	AF, BC, DE, HL, IX

macrept:	ld	(mdkind),a
		ld	(mdbuf),hl
		ld	a,(curfile)	; where this block opened, for errnoend:
		ld	(mdmfil),a	; macdef.next is shared, and it reports the
		ld	hl,(curline)	; line that opened the body, so a REPT
		ld	(mdmlin),hl	; must fill these in exactly as MACRO does
		xor	a
		ld	(mdntot),a	; the name pool starts empty, exactly
		ld	(mdnpar),a	; as it does for a named macro: a
		ld	(mdnloc),a	; LOCAL line inside the body still
		ld	(mdpuse),a	; works, and the dummy goes here
		ld	(mdseen),a
		ld	(mdnaml),a	; no name at all

		ld	a,(mdkind)	; a REPT has no dummy; IRP and IRPC
		cp	MDK_REPT	; have exactly one, and the caller has
		jr	z,macrept.nod	; already cut the operand short at its
		call	mdforms		; comma, so mdforms reads one name and
		ld	a,(mdntot)	; stops
		ld	(mdnpar),a

macrept.nod:	call	mdnew		; the descriptor

		derefp	mdmd		; mark what kind of block this is:
		ld	a,(mdkind)	; mxfree reads it to decide whether
		ld	(hl),a		; the body outlives the expansion

		ld	hl,1
		ld	(mddep),hl	; the REPT line we were called for
		jp	macdef.next	; and now it is an ordinary collection

; macname - what is this descriptor called?
;
;   The name table maps name -> descriptor. This is the other direction,
;   which hashing cannot answer: we hold a descriptor and want its name.
;   So it walks every record and compares payloads, and when one matches,
;   the name is in that same record - HT_KLEN bytes at HT_KEY.
;
;   O(n) in a structure built to be O(1), which would be indefensible
;   anywhere else. It runs once, from errdie, with the program about to
;   terminate: the scan is over before the BDOS call that prints the
;   line. Storing the name in every descriptor instead would cost a far
;   pointer and a heap block per macro, carried all run, to make a
;   once-per-run lookup fast.
;
;   Not found means the descriptor is anonymous (a REPT, IRP or IRPC
;   body, which never went in the table) or orphaned (redefined, so the
;   name now means something else). The caller says which,
;   from MD_KIND.
;
;   The name is copied into mdnam, which mdname uses while collecting a
;   definition. That is free here: nothing will read it again.
;
; Input:	HL -> a 4-byte far pointer to the descriptor
; Output:	CY clear = found; DE -> the name, zero-terminated, and
;		           mdnaml is its length
;		CY set   = no name reaches this descriptor
;		(the name is built in mdnam, which mdname uses while
;		 collecting - free here, since nothing reads it again)
; Modifies:	AF, BC, DE, HL, IX

macname:	ld	de,mnwant	; the descriptor we are looking for
		ld	bc,4
		ldir

		xor	a		; start a walk: bucket 0, and the
		ld	(mniter),a	; iterator's offset field null
		ld	hl,NULLOFF
		ld	(mniter+3),hl

macname.lp:	ld	ix,mnt
		ld	hl,mniter
		call	htnext
		ret	c		; no more records: not found

		derefp	mniter+1	; HL -> this record, mapped. Nothing
		ld	de,HT_KLEN	; below derefs again, so it stays
		add	hl,de		; mapped to the end of the comparison
		ld	a,(hl)		; HT_KLEN
		ld	(mnklen),a
		inc	hl		; HL -> HT_KEY
		push	hl		; keep it: the name is here
		ld	e,a
		ld	d,0
		add	hl,de		; HL -> the payload, MN_MD
		ld	de,mnwant	; the four bytes must match exactly
		ld	b,4
macname.cm:	ld	a,(de)
		cp	(hl)
		jr	nz,macname.no
		inc	hl
		inc	de
		djnz	macname.cm

		pop	hl		; a match: HL -> the key
		ld	de,mdnam
		ld	a,(mnklen)
		ld	(mdnaml),a
		ld	c,a
		ld	b,0
		ldir
		ex	de,hl
		ld	(hl),0		; zero-terminated, for putsz
		ld	de,mdnam	; and hand it back, so that errs.as does
		or	a		; not have to know where it lives
		ret

macname.no:	pop	hl
		jr	macname.lp

; macdef - collect one macro definition and store it.
;
;   The MACRO line has already been read and split by the caller. Its
;   name and parameter list are copied out FIRST, because the field block
;   points into the line buffer that the first getline below overwrites.
;
; Input:	HL -> a line buffer to use, MAXLINE+3 bytes
;		IX -> the field block describing the MACRO line
; Output:	CY clear = collected, and the ENDM consumed
;		(errors do not return)
; Modifies:	AB, BC, DE, HL, IX

macdef:		ld	(mdbuf),hl	; the caller's buffer, borrowed
		ld	a,(curfile)	; where this definition starts, for
		ld	(mdmfil),a	; errnoend: it fires at the end of the
		ld	hl,(curline)	; source, by which time curline points
		ld	(mdmlin),hl	; at the last line of the file
		ld	hl,(mdbuf)
		call	mdname		; the name, out of that bufefr
		xor	a
		ld	(mdntot),a	; the name pool starts empty. LOCAL
		ld	(mdnpar),a	; lines add to this same pool later,
		ld	(mdnloc),a	; after the parameters
		ld	(mdpuse),a
		ld	(mdseen),a	; and no body line is stored yet
		call	mdforms		; how many parameters
		ld	a,(mdntot)
		ld	(mdnpar),a	; everything so far is a parameter
		call	mdnew		; the descriptor
		call	mdmnt		; the name table entry
		ld	hl,1
		ld	(mddep),hl	; the MACRO line we were called for

macdef.next:	ld	hl,(mdbuf)
		call	getline		; CY set = the file ran out first
		ld	c,a		; ITS LENGTH, before errnoend's setup
					;   takes A. ld c,a leaves the flags
					;   alone, like the two lines below
		ld	a,(mdmfil)	; the MACRO line, for errnoend. Neither
		ld	hl,(mdmlin)	; of these touches the flags, so the CY
		jp	c,errnoend	; from getline survives them
		ld	de,(mdbuf)	; M80 LISTS A DEFINITION'S LINES, and
		ld	a,c		;   this loop is the only thing that
		call	lstbody		;   sees them. Before mdscan, because
					;   what gets stored is the prescanned
					;   form and the listing wants what the
					;   file said
		ld	hl,(mdbuf)
		ld	ix,mdflds	; getline used IX for its own purposes
		call	splitln
		ld	de,(mdflds+FL_OP)
		ld	a,(mdflds+FL_OPL)
		ld	b,a
		call	dirlook		; A = the directive number

		cp	D_ENDM
		jr	z,macdef.end
		cp	D_LOCAL
		jr	z,macdef.loc

		call	macdef.opn	; does this line open another body?
		jr	nz,macdef.st	; no: it is just text
		ld	hl,(mddep)
		inc	hl		; yes: one level deeper
		ld	(mddep),hl

macdef.st:	ld	a,1
		ld	(mdseen),a	; from here on a LOCAL line is late
		ld	hl,(mdbuf)	; prescan the line, then store what
		call	mdscan		; the prescan produced - not the
		ld	hl,mdsline	; line as it was read
		ld	a,(mdslen)
		call	mdapp
		jp	macdef.next

macdef.end:	ld	hl,(mddep)
		dec	hl
		ld	(mddep),hl
		ld	a,h
		or	l
		jr	z,macdef.done
		jr	macdef.st	; a nested ENDM: body text, store it

macdef.done:	call	mdnlocs		; MD_NLOCL, now that no more LOCAL
		ld	a,(mdmfil)	; lines can arrive.
		ld	(curfile),a	; Put the position back to the line that
		ld	hl,(mdmlin)	; OPENED the body. Collecting it moved
		ld	(curline),hl	; curline to the ENDM, and mexnew reads
					; curfile/curline as the call site - so a
					; REPT would name its ENDM instead of its
					; REPT line, off by the length of the body.
					; The next getline overwrites both anyway,
					; so it costs a named macro nothing
		ld	hl,mdmd		; HL -> the descriptor, for macrept's
		or	a		; caller; macdef's caller ignores it.
		ret			; or a clears CY = collected

; A LOCAL line is ours only while we are collecting our OWN body. At depth
; two or more it belongs to the macro being defined inside ours, and is
; stored as text like everything else there.

macdef.loc:	ld	hl,(mddep)
		dec	hl
		ld	a,h
		or	l
		jp	nz,macdef.st	; not ours: body text
		call	mdlocal
		jp	macdef.next	; ours: the line is consumed

; macdef.opn - does this directive open a body that needs its own ENDM?
;
; Input:	A = directive number
; Output:	Z set = yes, it opens a body
; Modifies:	F

macdef.opn:	cp	D_MACRO
		ret	z
		cp	D_REPT
		ret	z
		cp	D_IRP
		ret	z
		cp	D_IRPC
		ret

; mdname - copy the macro's name out of the line bufefr
;
;   The name is the label field of the MACRO line, and that field points
;   into the buffer macdef is about to reuse. A zero terminator is added
;   so the dump can print it with putsz; the length is kept separately
;   because htadd and htfind want it in A.
;
; Input:	IX -> the MACRO line's field block
; Output:	mdnam holds the name, mdnaml its length
; Modifies:	AF, BC, DE, HL

mdname:		ld	a,(ix+FL_LABL)
		or	a
		jp	z,errmnam	; nothing in the label field
		cp	MDNAMSZ
		jp	nc,errmnam	; longer than we can remember
		ld	(mdnaml),a
		ld	c,a
		ld	b,0
		ld	l,(ix+FL_LAB)
		ld	h,(ix+FL_LAB+1)
		ld	de,mdnam
		ldir
		xor	a
		ld	(de),a		; terminate it, for printing
		ret

; mdforms - split the MACRO line/s operand into the parameter
;   names, and keep them in ordinary RAM for the prescan.
;
;   Stored one after another as a length byte and that many characters,
;   with mdnpar counting them. They live only while this definition is
;   being collected - nothing above needs them afterwards.
;
;   Called twice: once for the MACRO line's parameters, and again for each
;   LOCAL line. It appends; clearing the pool is macdef's job.
;
; Input:	IX -> the MACRO line's field block
; Output:	mdnpar, mdpars
; Modifies:	AF, BC, DE, HL

mdforms:	ld	a,(ix+FL_ARGL)
		or	a
		ret	z		; no parameters at all
		ld	c,a		; C = characters left in the operand
		ld	l,(ix+FL_ARG)
		ld	h,(ix+FL_ARG+1)
		ld	de,mdpars	; DE -> where the next name goes. It
		ld	a,(mdpuse)	; APPENDS: a LOCAL line's names land
		add	a,e		; after the parameters already in the
		ld	e,a		; pool, and mdpuse is exactly how many
		ld	a,0		; bytes those took
		adc	a,d
		ld	d,a

mdforms.one:	call	mdfsk		; step over spaces and tabs
		ld	a,c
		or	a
		ret	z		; nothing but blanks left
		call	mdproom		; room for the length byte?
		ld	(mdplen),de	; where it goes, once we know it
		inc	de
		ld	b,0		; B = characters in this name

mdforms.ch:	ld	a,c
		or	a
		jr	z,mdforms.end	; the operand ran out
		ld	a,(hl)
		cp	","
		jr	z,mdforms.end
		call	mdisws
		jr	z,mdforms.end
		call	mdproom		; room for one more character?
		ld	a,(hl)
		ld	(de),a
		inc	de
		inc	hl
		dec	c
		inc	b
		jr	mdforms.ch

mdforms.end:	push	hl		; fill in the length byte
		ld	hl,(mdplen)
		ld	(hl),b
		pop	hl
		ld	a,b
		or	a
		jp	z,errplst	; an empty name, as in "addr,,val"

		ld	a,(mdntot)
		inc	a
		cp	MDPARMX+1
		jp	nc,errparm	; too many parameters
		ld	(mdntot),a

		call	mdfsk		; is another one coming?
		ld	a,c
		or	a
		ret	z		; the operand is finished
		ld	a,(hl)
		cp	","
		ret	nz		; something unexpected: stop here
		inc	hl
		dec	c
		jp	mdforms.one

; mdlocal - a LOCAL line: add its names to the pool the parameters are
;   already in.
;
;   It calls mdforms, which is the same job: split an operand at commas
;   into length-prefixed names and append them. mdforms no longer clears
;   the pool - macdef does that once - which is what makes calling it a
;   second time safe.
;
; Input:	mdflds describes the LOCAL line
; Output:	the names are in the pool, mdnloc = how many
;		(a LOCAL after body lines does not return - errlocl stops)
; Modifies:	AF, BC, DE, HL, IX

mdlocal:	ld	a,(mdseen)
		or	a
		jp	nz,errlocl	; body lines are already stored: the
					; name would be a marker on some and
					; plain text on others
		ld	ix,mdflds
		call	mdforms
		ld	a,(mdntot)	; whatever mdforms just added to the
		ld	hl,mdnpar	; pool is a LOCAL
		sub	(hl)
		ld	(mdnloc),a
		ret

; mdnlocs - write the LOCAL count into the descriptor.
;
;   Not done when the descriptor is created: at that moment the LOCAL
;   lines have not been read yet. Done once, when the body is closed.
;
; Input:	mdmd, mdnloc
; Output:	MD_NLOCL is set
; Modifies:	AF, BC, DE, HL

mdnlocs:	derefp	mdmd
		ld	de,MD_NLOCL
		add	hl,de
		ld	a,(mdnloc)
		ld	(hl),a
		ret

; mdproom - is there romo for one more byte in the name pool?
;
;   Counting the bytes is simpler than comparing pointers, and it does
;   not care where mdpars happens to sit in memory.
;
; Input:	nothing
; Output:	the pool has one more byte in it
;		(a full pool does not return - errparm stops)
; Modifies:	AF

mdproom:	ld	a,(mdpuse)
		inc	a
		cp	MDPARSZ+1
		jp	nc,errparm
		ld	(mdpuse),a
		ret

; mdfsk - step HL over spaces and tabs, counting them off C.
;
; Input:	HL -> somewhere in the operand
;		C   = characters left
; Output:	HL, C past any run of spaces and tabs
; Modifies:	AF, C, HL

mdfsk:		ld	a,c
		or	a
		ret	z
		ld	a,(hl)
		call	mdisws
		ret	nz
		inc	hl
		dec	c
		jr	mdfsk

; mdisws - is the character in A a space or a tab?
;
; Input:	A = character
; Output:	Z set = yes
; Modifies:	F only

mdisws:		cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret

; mdscan - prescan one body line: every reference to a parameter
;   becomes a two-byte marker, so that replaying the line never has to
;   compare a name against anything.
;
;   Three pieces of state, all in ordinary RAM because this routine is
;   long enough that keeping them in registers would be a puzzle:
;
;     mdquot   which quote character we are inside, 0 = none
;     mdforce  the last character was "&", so the next identifier is
;              substituted even inside a string
;     mdslen   how much has been produced so far
;
; Input:	HL -> the line, zero-terminated
; Output:	mdsline = the prescanned line, zero-terminated
;		mdslen  = its length
; Modifies:	AF, BC, DE, HL

mdscan:		ld	de,mdsline	; DE = where the next byte goes
		xor	a
		ld	(mdslen),a
		ld	(mdquot),a	; not inside a string
		ld	(mdforce),a	; no "&" seen

mdscan.ch:	ld	a,(hl)
		or	a
		jp	z,mdscan.end	; the line is finished

		cp	AMPER
		jp	z,mdscan.amp

		ld	a,(mdquot)
		or	a
		jp	nz,mdscan.inq	; inside a string: different rules

; --- outside a string

		ld	a,(hl)
		cp	SEMIC
		jp	z,mdscan.cmt
		cp	QUOTE1
		jr	z,mdscan.opn
		cp	QUOTE2
		jr	z,mdscan.opn
		call	mdisi1		; does it start an identifier?
		jp	z,mdscan.id
		jp	mdscan.put

mdscan.opn:	ld	(mdquot),a	; remember which quote opened it
		jp	mdscan.put

; --- the "&" is a concatenation operator: it is consumed, never stored,
;     and it forces the next identifier to be substituted even inside a
;     string.

;     One "&" is spent per expansion level: a single one is consumed here
;     and forces the next identifier, while "&&" stores ONE of them as
;     ordinary text for the next level in to spend.
;
;     The manual describes only the single-level case and never mentions
;     "&&" at all (books/m80l80.txt 2.7.9), so this follows the MASM
;     family. It is strictly additive: "&" behaves exactly as it did, and
;     "&&" previously did nothing useful.
;
;     Note which case needs which. A nested definition whose LABEL is
;     built from the OUTER macro's parameter wants a single "&" -
;     "poke&sfx macro addr" - because that concatenation happens at the
;     outer level. "&&" is only for concatenation against the INNER
;     macro's own parameters.

mdscan.amp:	inc	hl		; the "&" is consumed either way
		ld	a,(hl)
		cp	AMPER
		jr	z,mdscan.am2
		ld	a,1		; a single "&": force the next
		ld	(mdforce),a	; identifier, even inside a string
		jp	mdscan.ch

mdscan.am2:	inc	hl		; "&&": one of them survives into the
		ld	a,AMPER		; stored line as data. mdforce is NOT
		call	mdput		; set - this "&" is not spent here
		jp	mdscan.ch

; --- inside a string. Only the matching quote closes it, and only an
;     "&"-marked reference is substituted (the M80 rule).

mdscan.inq:	ld	b,a		; B = the quote we are inside
		ld	a,(hl)
		cp	b
		jr	nz,mdscan.inq2
		xor	a
		ld	(mdquot),a	; the string closes here
		jp	mdscan.put
mdscan.inq2:	ld	a,(mdforce)
		or	a
		jp	z,mdscan.put	; not forced: literal text
		ld	a,(hl)
		call	mdisi1
		jp	z,mdscan.id
		jp	mdscan.put

; --- an identifier. It is copied into the output FIRST and looked up
;     there; if it turns out to be a parameter, the output is wound back
;     over it and the marker written instead. The saves a buffer to
;     collect it in, and costs nothing in the common case.

mdscan.id:	xor	a
		ld	(mdforce),a	; the force applies to this one only
		ld	(mdsst),de	; where the name begins in the output
		ld	b,0		; B = how long it is
mdscan.idch:	ld	a,(hl)
		call	mdisid
		jr	nz,mdscan.idend
		call	mdput
		inc	hl
		inc	b
		jr	mdscan.idch

mdscan.idend:	ld	a,(hl)		; an "&" right after also ends the
		cp	AMPER		; identifier, and is consumed
		jr	nz,mdscan.idlk
		inc	hl
		ld	a,(hl)		; ...unless it is "&&", which is left
		cp	AMPER		; whole for mdscan.amp. It must not be
		jr	nz,mdscan.idlk	; stored here: mdplook below may wind
		dec	hl		; the output back over this name, and
					; anything written first would go with
					; it. Putting HL back on the first "&"
					; defers the pair until after the
					; lookup has resolved

mdscan.idlk:	push	hl
		push	de		; mdplook walks the table with DE,
		ld	hl,(mdsst)	; which is our output pointer
		call	mdplook		; CY set = not a parameter
		pop	de
		pop	hl
		jp	c,mdscan.ch	; not one: it is already copied

		ld	c,a		; C = its index in the combined list
		ld	de,(mdsst)	; wind the output back over the name
		ld	a,(mdslen)
		sub	b
		ld	(mdslen),a

		ld	a,(mdnpar)	; below mdnpar it is a parameter; at
		ld	b,a		; or above it, a LOCAL, renumbered
		ld	a,c		; from zero
		cp	b
		jr	c,mdscan.idp
		sub	b
		ld	c,a
		ld	a,MP_LOCL
		jr	mdscan.idm
mdscan.idp:	ld	a,MP_PARM
mdscan.idm:	call	mdput
		ld	a,c
		call	mdput
		jp	mdscan.ch

; --- a comment, outside a string. ";;" is definition-time commentary
;     and is dropped; ";" is stored so the listing can show it. Nothing
;     after either is prescanned.

mdscan.cmt:	inc	hl
		ld	a,(hl)
		cp	SEMIC
		jr	z,mdscan.end	; ";;" - the rest of the line goes
		dec	hl
mdscan.cpy:	ld	a,(hl)
		or	a
		jr	z,mdscan.end
		call	mdput
		inc	hl
		jr	mdscan.cpy

; --- store the character at (HL) and step over it

mdscan.put:	xor	a
		ld	(mdforce),a	; an "&" only reaches the next thing
		ld	a,(hl)
		call	mdput
		inc	hl
		jp	mdscan.ch

mdscan.end:	xor	a
		ld	(de),a		; terminate the prescanned line
		ret

; mdput - add the character in A to the prescanned line.
;
;   Two bytes can replace a one-character name, so the line may grow;
;   the length is checked before every byte rather than afterwards.
;
; Input:	A   = the character
;		DE -> where it goes
; Output:	stored, DE and mdslen advanced
;		(a line that grew too long does not return - errblen stops)
; Modifies:	AF, DE

mdput:		push	af
		ld	a,(mdslen)
		cp	MAXLINE
		jp	nc,errblen
		inc	a
		ld	(mdslen),a
		pop	af
		ld	(de),a
		inc	de
		ret

; mdplook - is this identifier one of the names?
;
;   Compared ignoring case, like every other name M80 matches.
;
;   The index is "how many parameters there are" minus "how many are left
;   to try", so no separate counter is carried round the loop.
;
; Input:	HL -> the identifier
; 		B   = its length
; Output:	CY clear = yes, A = its index in the combined list
;		CY set   = no
; Modifies:	AF, C, DE

mdplook:	ld	a,(mdntot)
		or	a
		scf
		ret	z		; no parameters at all
		ld	c,a		; C = names left to try
		ld	de,mdpars	; DE -> the entry being tried

mdplook.one:	ld	a,(de)		; its length
		cp	b
		jr	nz,mdplook.nx	; different length: cannot match

		push	hl
		push	de
		push	bc
		ld	c,b		; C = characters to compare
		inc	de		; DE -> the name itself
mdplook.ch:	ld	a,(de)
		call	strupr
		ld	b,a
		ld	a,(hl)
		call	strupr
		cp	b
		jr	nz,mdplook.dif
		inc	hl
		inc	de
		dec	c
		jr	nz,mdplook.ch

		pop	bc		; matched. B = length, C = names left
		pop	de
		pop	hl
		ld	a,(mdntot)
		sub	c		; mdntot >= c, so this clears CY too
		ret

mdplook.dif:	pop	bc
		pop	de
		pop	hl
mdplook.nx:	ld	a,(de)		; step over this entry: the length
		add	a,1		; byte and the name
		add	a,e
		ld	e,a
		jr	nc,mdplook.nc
		inc	d
mdplook.nc:	dec	c
		jr	nz,mdplook.one
		scf			; every name tried: not a parameter
		ret

; mdisid - may this character appear in an identifier?
; mdisi1 - may it START one? The same set, without the digits.
;
;   M80's set is the letters, the digits, and ? @ . _ $
;
; Input:	A = character
; Output:	Z set = yes
; Modifies:	F only

mdisid:		cp	"0"
		jr	c,mdisi1	; below "0": try the rest of the set
		cp	"9"+1
		jr	c,mdidyes	; a digit
mdisi1:		cp	"A"
		jr	c,mdisi1.p
		cp	"Z"+1
		jr	c,mdidyes
		cp	"a"
		jr	c,mdisi1.p
		cp	"z"+1
		jr	c,mdidyes
mdisi1.p:	cp	"?"
		ret	z
		cp	"@"
		ret	z
		cp	"."
		ret	z
		cp	"_"
		ret	z
		cp	"$"
		ret
mdidyes:	cp	a		; whatever A holds, this sets Z
		ret


; mdnew - allocate the descriptor and fill in what is known now.
;
;   The three far pointers in it start null - which is offset FFFFh, not
;   four zero bytes: zeros would be a perfectly good pointer to segment
;   0, and would be followed.
;
; Input:	mdnpar, and the current origin in curfile/curline
; Output:	mdmd holds the descriptor far pointer
; Modifies:	AF, BC, DE, HL

mdnew:		ld	bc,MDSIZE
		ld	hl,mdmd
		call	halloc
		jp	c,errheap
		derefp	mdmd		; HL -> the descriptor, mapped
		ld	(hl),MDK_MACRO	; MD_KIND
		inc	hl
		ld	(hl),0		; MD_FLAGS
		inc	hl
		ld	a,(mdnpar)
		ld	(hl),a		; MD_NPARM
		inc	hl
		ld	(hl),0		; MD_NLOCL
		inc	hl
		ld	(hl),0		; MD_USES
		inc	hl
		ld	a,(curfile)
		ld	(hl),a		; MD_DEFFIL
		inc	hl
		ld	de,(curline)
		ld	(hl),e		; MD_DEFLIN
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),0		; MD_NLINES
		inc	hl
		ld	(hl),0
		inc	hl
		ld	b,12		; MD_BODY, MD_LAST and MD_PNAM,
		ld	a,0ffh		; all null
mdnew.n:	ld	(hl),a
		inc	hl
		djnz	mdnew.n

		ld	hl,mdlast	; no body block yet
		ld	b,4
		ld	a,0ffh
mdnew.l:	ld	(hl),a
		inc	hl
		djnz	mdnew.l
		ld	hl,MBBLK	; "the block is full", so the first
		ld	(mdused),hl	; line stored allocates one
		ret

; mdmnt - make the name table point at this descriptor.
;
;   A redefinition overwrites the four-byte pointer in the record that is
;   already there, and walks away from the old descriptor and its body.
;   That is correct - the new definition wins from the next invocation -
;   but it LEAKS. Freeing the old one safely needs hte use count, because
;   an expansion may be reading the old body at this very moment; that is
;
; Input:	mdnam/mdnaml, mdmd
; Output:	the table points at mdmd
; Modifies:	AF, BC, DE, HL, IX

mdmnt:		ld	ix,mnt
		ld	de,mdnam
		ld	a,(mdnaml)
		ld	hl,mdpay
		call	htfind		; CY set = this name is new
		jr	c,mdmnt.new

		derefp	mdpay		; a redefinition. Keep the OLD
		fpsave	mdold		; descriptor's pointer BEFORE the new
					; one goes over it: the payload is four
					; bytes and that write is what destroys
					; the only reference to it. These two
					; steps cannot be reordered
		call	mdmnt.put	; the name now means the new one
		jp	mdorph		; and the old one is nobody's by name

mdmnt.new:	ld	de,mdnam	; htfind clobbered DE and A
		ld	a,(mdnaml)
		ld	bc,MNSIZE
		ld	hl,mdpay
		call	htadd
		jp	c,errheap

mdmnt.put:	derefp	mdpay		; HL -> the payload, mapped
		ex	de,hl		; DE -> where the pointer goes
		ld	hl,mdmd		; from ordinary RAM
		ld	bc,4
		ldir
		ret

; mdorph - the descriptor in mdold is no longer reachable by name.
;
;   Half of the freeing rule; the other half is in mxfree (expand.as).
;   A descriptor goes back to the heap when nothing is reading it AND
;   nothing can reach it by name, and whichever of those two becomes true
;   second is what frees it. This is the "by name" side.
;
;   The common case is that MD_USES is 0 and it is freed right here. The
;   interesting case is a macro that redefines itself from inside its own
;   body: the count is at least 1, this returns having done nothing but
;   set a bit, and the replay carries on reading a body that no name
;   points at any more (mdt-design.md 5).
;
; Input:	mdold = the displaced descriptor's far pointer
; Output:	MDF_ORPH set, and freed if nothing is reading it
; Modifies:	AF, BC, DE, HL

mdorph:		derefp	mdold
		ld	de,MD_FLAGS
		add	hl,de
		set	0,(hl)		; MDF_ORPH - no name reaches it now
		ld	de,MD_USES-MD_FLAGS
		add	hl,de
		ld	a,(hl)
		or	a
		ret	nz		; an expansion is still reading it.
					; Its mxfree will free it

		ld	hl,mdold	; nothing is: it goes now
		jp	mxbfree

; mdapp - append one body line to the block chain.
;
; Input:	HL -> the text
;		A   = its length
;		curline = the line it came from
; Output:	the record is stored, MD_NLINES incremented
; Modifies:	AF, BC, DE, HL

mdapp:		ld	(mdtxt),hl
		ld	(mdlen),a

		ld	hl,(mdused)	; would the record run past the end?
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,MLHDR
		add	hl,de
		ld	de,MBBLK
		or	a
		sbc	hl,de
		jr	c,mdapp.fits	; it ends before the block does
		call	mdblock		; no room: chain a new block on

mdapp.fits:	derefp	mdlast		; HL -> the block, mapped
		ld	de,(mdused)
		add	hl,de		; HL -> where this record goes
		ld	a,(mdlen)
		ld	(hl),a		; ML_LEN
		inc	hl
		ld	de,(curline)
		ld	(hl),e		; ML_LINE
		inc	hl
		ld	(hl),d
		inc	hl		; HL -> ML_TEXT
		ex	de,hl		; DE -> its place in the block
		ld	a,(mdlen)
		or	a
		jr	z,mdapp.non	; an empty line stores no text
		ld	c,a
		ld	b,0
		ld	hl,(mdtxt)
		ldir

mdapp.non:	ld	hl,(mdused)	; used = used + MLHDR + length
		ld	a,(mdlen)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,MLHDR
		add	hl,de
		ld	(mdused),hl

		derefp	mdlast		; write it into the block as well
		ld	de,(mdused)	; deref clobbers DE, so the value is
		ld	bc,MB_USED	; fetched AFTER it, not befrore
		add	hl,bc
		ld	(hl),e
		inc	hl
		ld	(hl),d

		derefp	mdmd		; add one more body line
		ld	de,MD_NLINES
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	de
		ld	(hl),d
		dec	hl
		ld	(hl),e
		ret

; mdblock - allocate a body block and chain it on the end.
;
; Input:	mdmd, mdlast (null if this is the first block)
; Output:	mdlast points at the new block, mdused = MB_DATA
; Modifies:	AF, BC, DE, HL

mdblock:	ld	bc,MBBLK
		ld	hl,mdblkp
		call	halloc
		jp	c,errheap

		derefp	mdblkp		; the new block: no next, empty
		ld	b,4
		ld	a,0ffh
mdblock.n:	ld	(hl),a
		inc	hl
		djnz	mdblock.n
		ld	de,MB_DATA
		ld	(hl),e		; MB_USED = MB_DATA
		inc	hl
		ld	(hl),d

		fpnull	mdlast
		jr	z,mdblock.1st

		derefp	mdlast		; HL -> the old last block, whose
		ex	de,hl		; MB_NEXT is at offset 0
		ld	hl,mdblkp
		ld	bc,4
		ldir
		jr	mdblock.set

mdblock.1st:	derefp	mdmd		; the first block goes in MD_BODY
		ld	de,MD_BODY
		add	hl,de
		ex	de,hl
		ld	hl,mdblkp
		ld	bc,4
		ldir

mdblock.set:	fpcopy	mdlast,mdblkp
		ld	hl,MB_DATA
		ld	(mdused),hl
		ret

; macdump - read the definition just stored back out and print it.
;
;   Called by the main program when /M was given. It lives here because
;   it knows the shape of the tables, but WHEN to call it is the main
;   program's business - this module has no reason to know what letters
;   were on the command line.
;
;   Only valid immediately after macdef returns: it reads the collection
;   variables, which the next definition overwrites.
;
;   This is the shape the replay engine has, so it is
;   worth reading closely. The block is mapped again on EVERY trip round
;   the inner loop, because printing class BDOS, and BDOS takes page 2
;   back. Each record is copied into ordinary RAM before a single
;   character of it is printed.
;
;   The dump goes to the screen, never to the output file: it is a
;   diagnostic, not translated source.
;
; Input:	mdmd, mdnam, and the borrowed line buffer in mdbuf
; Output:	the definition in printed
; Modified:	AF, BC, DE, HL

;   Everything wanted from the descriptor is read out first, in one
;   mapping, and only then printed. That is the pattern, not an
;   optimisation: the first _STROUT below would take page 2 away.

; lstmacs - every macro's name, sixteen columns each, one to a line,
;   for the listing's last page. M80 lists the names there and nothing
;   else - the bodies are /M's business.
;
;   macrst's walk, without the freeing.
;
; Input:	nothing
; Output:	the names are written
; Modifies:	AF, BC, DE, HL, IX

lstmacs:	xor	a
		ld	(lmiter),a
		ld	hl,NULLOFF
		ld	(lmiter+3),hl
lmac.lp:	ld	ix,mnt
		ld	hl,lmiter
		call	htnext
		ret	c
		ld	c,0
lmac.nm:	derefp	lmiter+1	; the record again: a name lives in
		ld	de,HT_KLEN	;   the mapper and every write takes
		add	hl,de		;   page 2 away
		ld	a,(hl)
		inc	hl
		ld	b,a
		ld	a,c
		cp	b
		jr	nc,lmac.eol
		ld	e,c
		ld	d,0
		add	hl,de
		ld	a,(hl)
		push	bc
		call	emitchr
		pop	bc
		inc	c
		jr	lmac.nm
lmac.eol:	call	lstcrlf
		jr	lmac.lp

macdump:	derefp	mdmd
		ld	de,MD_NLOCL
		add	hl,de
		ld	a,(hl)		; MD_NLOCL
		ld	(mddloc),a
		inc	hl		; over MD_USES
		inc	hl
		ld	a,(hl)		; MD_DEFFIL
		ld	(mddfil),a
		inc	hl
		ld	e,(hl)		; MD_DEFLIN
		inc	hl
		ld	d,(hl)
		ld	(mddorg),de
		inc	hl
		ld	e,(hl)		; MD_NLINES
		inc	hl
		ld	d,(hl)
		ld	(mddn),de
		inc	hl		; HL -> MD_BODY
		fpsave	mddblk		; the first block, into ordinary RAM

		ld	de,msg_mac
		system	_STROUT
		ld	de,mdnam
		call	putsz
		ld	de,msg_mcol
		system	_STROUT
		ld	a,(mdnpar)
		ld	l,a
		ld	h,0
		call	putdec
		ld	de,msg_mpar
		system	_STROUT
		ld	a,(mddloc)
		ld	l,a
		ld	h,0
		call	putdec
		ld	de,msg_mloc
		system	_STROUT
		ld	hl,(mddn)
		call	putdec
		ld	de,msg_mlin
		system	_STROUT
		ld	a,(mddfil)
		call	getfnam
		call	putszu		; a filename: upper case
		ld	de,msg_mlp
		system	_STROUT
		ld	hl,(mddorg)
		call	putdec
		ld	de,msg_mrp
		system	_STROUT

macdump.blk:	fpnull	mddblk
		ret	z		; no more blocks: done
		derefp	mddblk
		ld	de,MB_USED
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(mddend),de	; how far this block is filled
		ld	hl,MB_DATA
		ld	(mddoff),hl

macdump.rec:	ld	hl,(mddoff)
		ld	de,(mddend)
		or	a
		sbc	hl,de
		jr	nc,macdump.nxt	; this block is finished
		call	macdump.one
		jr	macdump.rec

macdump.nxt:	derefp	mddblk		; MB_NEXT is at offset 0, and it
		fpsave	mddblk		; replaces the pointer we just used
		jr	macdump.blk

; macdump.one - copy one record out of the heap and print it.

macdump.one:	derefp	mddblk
		ld	de,(mddoff)
		add	hl,de		; HL -> the record
		ld	a,(hl)
		ld	(mddlen),a	; ML_LEN
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(mddlin),de	; ML_LINE
		inc	hl		; HL -> the text
		ld	de,(mdbuf)	; the borrowed line buffer
		ld	a,(mddlen)
		or	a
		jr	z,macdump.one0
		ld	c,a
		ld	b,0
		ldir			; out of the heap, into ordinary RAM
macdump.one0:	ex	de,hl
		ld	(hl),0		; terminate it

; Everything wanted is now in ordinary RAM, so page 2 may go.

		ld	de,msg_mrl
		system	_STROUT
		ld	hl,(mddlin)
		call	putdec
		ld	de,msg_mrb
		system	_STROUT
		ld	de,(mdbuf)
		call	mdpr		; markers show as <n>
		ld	de,msg_mnl
		system	_STROUT

		ld	hl,(mddoff)	; step over the record
		ld	a,(mddlen)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,MLHDR
		add	hl,de
		ld	(mddoff),hl
		ret

; mdpr - print a stored body line, showing parameter markers as <n>.
;
;   A marker is two bytes that would print as control characters, so the
;   dump has to expand them or show nothing useful.
;
; Input:	DE -> the line, zero-terminated
; Output:	printed
; Modifies:	AF, BC, DE, HL

mdpr:		ld	a,(de)
		or	a
		ret	z
		cp	MP_PARM
		jr	z,mdpr.parm
		cp	MP_LOCL
		jr	z,mdpr.locl
		push	de
		ld	e,a
		system	_CONOUT
		pop	de
		inc	de
		jr	mdpr

mdpr.parm:	ld	hl,msg_mlt	; a parameter prints as <n>
		jr	mdpr.mk2
mdpr.locl:	ld	hl,msg_mll	; a LOCAL prints as <Ln>
mdpr.mk2:	ld	(mdprb),hl

mdpr.mark:	inc	de		; the index follows the marker byte
		ld	a,(de)
		ld	(mdprn),a
		push	de
		ld	de,(mdprb)
		system	_STROUT
		ld	a,(mdprn)
		ld	l,a
		ld	h,0
		call	putdec
		ld	de,msg_mgt
		system	_STROUT
		pop	de
		inc	de
		jr	mdpr

 		dseg

; --- while a definition is being collected

mdbuf:		defs	2		; the line buffer the called lent us
mdkind:		defs	1		; macrept: MDK_REPT, IRP or IRPC
mdold:		defs	4		; far pointer: a descriptor the name
					;   table has just stopped naming
mdmfil:		defs	1		; macdef and macrept: the line that
mdmlin:		defs	2		;   opened the body, for errnoend
mnwant:		defs	4		; macname: the descriptor being named
mniter:		defs	5		; macname: htnext's iterator
mnklen:		defs	1		; macname: this record's key length
lmiter:		defs	5		; lstmacs's walk over the same table
mfiter:		defs	5		; macrst: htnext's iterator. NOT shared with
mfmd:		defs	4		;   macname's - nine bytes is a cheap price
					;   for two walks that cannot interfere, and
					;   what a shared precondition
					;   costs when it is undocumented
mddep:		defs	2		; opened bodies not yet closed
mdflds:		defs	FLSIZE		; the body line being looked at
mdnam:		defs	MDNAMSZ+1	; the macro's name, zero-terminated
mdnaml:		defs	1		; and its length, for htadd/htfind
mdnpar:		defs	1		; how many parameters
mdpars:		defs	MDPARSZ		; their names, length-prefixed
mdpuse:		defs	1		; bytes of that pool in use
mdplen:		defs	2		; mdforms: where a length byte goes
mdnloc:		defs	1		; how many LOCAL names
mdntot:		defs	1		; parameters + LOCALs, for mdplook
mdseen:		defs	1		; a body line has been stored, so a
					;   LOCAL line would now be too late
mddloc:		defs	1		; macdump: the LOCAL count
mdprb:		defs	2		; mdpr: which bracket this marker uses

mdsline:	defs	MAXLINE+1	; the prescanned line
mdslen:		defs	1		; how long it is
mdquot:		defs	1		; the quote we are inside, 0 = none
mdforce:	defs	1		; the last character was "&"
mdsst:		defs	2		; where an identifier begins in mdsline

mdprn:		defs	1		; mdpr: the index being printed

mdmd:		defs	4		; far pointer: the descriptor
mdpay:		defs	4		; far pointer: its name table payload
mdlast:		defs	4		; far pointer: the last body block
mdblkp:		defs	4		; far pointer: a block being allocated
mdused:		defs	2		; first free byte in the last block
mdtxt:		defs	2		; mdapp: the text to store
mdlen:		defs	1		; mdapp: how long it is

; --- while a definition is being dumped

mddblk:		defs	4		; far pointer: the block being read
mddoff:		defs	2		; offset of the next record in it
mddend:		defs	2		; how far that block is filled
mddlen:		defs	1		; the record's text length
mddlin:		defs	2		; the record's source line number
mddn:		defs	2		; the body's line count
mddfil:		defs	1		; the file the definition came from
mddorg:		defs	2		; the line the MACRO line was on

; --- the macro name table itself. hash.as requires the descriptor to be
;     in ordinary RAM, never in the heap: it is read while a record is
;     mapped into page 2.

mnt:		defs	2+MNBUCKS*4

msg_mac:	defb	"MACRO $"
msg_mcol:	defb	": $"
msg_mpar:	defb	" parameters, $"
msg_mlin:	defb	" lines, $"
msg_mlp:	defb	"($"
msg_mrp:	defb	")",CHR_CR,CHR_LF,"$"
msg_mrl:	defb	"  $"
msg_mrb:	defb	" | $"
msg_mnl:	defb	CHR_CR,CHR_LF,"$"
msg_mlt:	defb	"<$"
msg_mgt:	defb	">$"
msg_mloc:	defb	" locals, $"
msg_mll:	defb	"<L$"
