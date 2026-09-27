; expand.as - replaying a stored macro body.
;
; An expansion is just another line source: mexline has the same shape
; as filelin in srcline.as, and getline calls whichever the enrty on top
; of the stack calls for. Nested calls need no code of their own - the
; inner one is another entry on the same stack.
;
; The page-2 rule, throughout: an address from deref is good only until
; the next deref, halloc, hfree, ht* call, p2restore of BDOS call. So the
; expansion record is mapped, read, and let go; then the block is mapped,
; read, and let go. Nothing is remembered across a mapping except by
; copying it into ordinary RAM first.
;
; No msxdos.inc here, and no BDOS call anywhere in the file: everything
; this module touches is mapper RAM or its own variables. It is the only
; module of which that is true.

EXPLIB		equ	1		; skips the externals in expand.inc

		public	mexinit
		public	mexnew
		public	mexrept
		public	mxpitem
		public	mexitm
		public	mxbfree
		public	mexline

		include	srcline.inc	; pushmac, curfile, curline, MAXLINE
		include	mdt.inc
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been declared
		include	ascii.inc	; CHR_SPACE, CHR_TAB
		include	expand.inc
		include	errs.inc
		include	expr.inc	; evalabs, for a "%" argument
		include	strutil.inc	; numdec, for its digits
		include	cond.inc	; cnddep: how many conditionals are
					;   open. Read when a record is made,
					;   written back by mexitm - the only
					;   two places outside cond.as

		cseg

; mexinit - get this module ready for a pass.
;
;   Called from main: alongside macinit and srcinit, and called AGAIN at
;   the start of pass 2 - which is the whole reason it exists. Pass 2
;   re-reads the source and re-expands it, so every ??nnnn must come out
;   with the number it had on pass 1. If the counter carried over, a label
;   DEFINED as ??0007 on pass 1 would be REFERENCED as ??0011 on pass 2,
;   and every local label in the program would become a phase error with
;   nothing in the message pointing at why.
;
; Input:	nothing
; Output:	the ??nnnn counter is back at zero
; Modifies:	AF, HL

mexinit:	ld	hl,0
		ld	(mxlctr),hl
		ld	hl,NULLOFF	; no IRP item block is waiting to be
		ld	(mxirpv+2),hl	; adopted. Without this the FIRST
		ret			; macro call of the run would read
					; whatever the dseg happened to hold
					; and take it for a pre-built block

; mexrept - start an anonymous body: the same as mexnew, but with a
;   repeat count and no arguments.
;
; Input:	HL -> the descriptor's far pointer
;		BC = how many times to replay it
; Output:	CY clear = it is on top of the line-source stack, or the
;		           count was zero and it was freed instead
; Modifies:	AF, BC, DE, HL, IX

mexrept:	ld	a,b		; nothing to do at all?
		or	c
		jr	z,mexrept.no
		ld	de,0		; a REPT has no argument text
		xor	a
		jr	mexnew.go

mexrept.no:	ld	de,mxmd		; rept 0: the body was collected and
		ld	bc,4		; is now unreachable, so give it back
		ldir
		ld	hl,mxmd
		call	mxbfree
		or	a		; CY clear = nothing was pushed. hfree
		ret			; ends in fladd, whose last instruction
					; is an ldir, and ldir leaves CY alone -
					; so hfree's CY is whatever the caller
					; had. It must be set here, not assumed

; mexnew - start expanding a macro: parse the call's arguments, allocate
;   an expansion record, fill it in, and push it on the line-source stack.
;
; Input:	HL -> the descriptor's far pointer
;		DE -> the call's argument text (not zero-terminated)
;		A   = how many characters of it
;		curfile/curline = where the call was
; Output:	CY clear = the expansion is on top of the stack, or the
;		           macro had an empty body and nothing was pushed
; Modifies:	AF, BC, DE, HL, IX

mexnew:		ld	bc,1		; a macro call replays its body once
		push	af		; A is the argument text's LENGTH, so
		ld	a,MDPARMX	; it has to be put back: a macro call
		ld	(mxamax),a	; caps at MDPARMX, because a 17th
		pop	af		; argument could never be named
mexnew.go:	ld	(mxiter),bc
		ld	(mxatxt),de	; the argument text lives in the line
		ld	(mxalen),a	; buffer, so note it before anything
					; else runs
		ld	de,mxmd		; keep the descriptor's pointer
		ld	bc,4
		ldir

		derefp	mxmd		; read what we need out of it in one
		ld	de,MD_NLOCL	; mapping, before anything else can
		add	hl,de		; take page 2 away
		ld	a,(hl)
		ld	(mxnloc),a	; MD_NLOCL
		ld	de,MD_DEFFIL-MD_NLOCL
		add	hl,de
		ld	a,(hl)
		ld	(mxfil),a	; MD_DEFFIL
		ld	de,MD_BODY-MD_DEFFIL
		add	hl,de
		fpsave	mxblk		; MD_BODY

		fpnull	mxblk
		jp	z,mexnew.nul	; no body at all. A jp, not a jr: the
					; code from here to the end of mexnew
					; is about 140 bytes and jr reaches 127

		fpnull	mxirpv		; did the driver already build one?
		jr	z,mexnew.arg	; no: parse the operand, as always
		fpcopy	mxargv,mxirpv	; yes: take it, and empty the holder
		ld	hl,NULLOFF	; so that it is used exactly once and
		ld	(mxirpv+2),hl	; the next macro call cannot adopt it
		jr	mexnew.rec
mexnew.arg:	call	mxargs		; the call's arguments, in the heap

mexnew.rec:	derefp	mxmd		; one more expansion is reading this
		ld	de,MD_USES	; body. It is what makes redefining a
		add	hl,de		; macro while it expands safe, and it
		inc	(hl)		; is kept for all four kinds so that
					; the field is never wrong

		ld	bc,MXSIZE	; the expansion record
		ld	hl,mxfp
		call	halloc
		jp	c,errheap

		derefp	mxfp		; fill it in. MX_MD is at offset 0 now
		ex	de,hl		; that MX_PAR is gone: the record has no
					; parent pointer, because the origin
					; trail is the line source stack
		ld	hl,mxmd
		ld	bc,4
		ldir			; MX_MD
		ld	hl,mxblk
		ld	bc,4
		ldir			; MX_BLK = the first body block

		ld	hl,MB_DATA	; MX_OFF = the first record
		ex	de,hl
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),0		; MX_LINE
		inc	hl
		ld	(hl),0
		inc	hl
		ld	a,(curfile)
		ld	(hl),a		; MX_CFIL
		inc	hl
		ld	de,(curline)
		ld	(hl),e		; MX_CLIN
		inc	hl
		ld	(hl),d
		inc	hl

		ex	de,hl		; DE -> MX_ARGV in the record
		ld	hl,mxargv
		ld	bc,4
		ldir			; MX_ARGV
		ld	a,(mxnarg)
		ld	(de),a		; MX_NARG
		inc	de
		ld	hl,(mxlctr)	; MX_LBASE: the first ??nnnn this
		ld	a,l		; expansion may use
		ld	(de),a
		inc	de
		ld	a,h
		ld	(de),a
		inc	de
		ld	a,(mxnloc)	; and the counter moves past the whole
		ld	c,a		; run, so the next expansion cannot
		ld	b,0		; collide with this one
		add	hl,bc
		ld	(mxlctr),hl
		ex	de,hl
		ld	de,(mxiter)	; MX_ITER: 1 for a macro, n for a REPT
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),0		; MX_ITEM - the item list is walked
		inc	hl		; with it
		ld	(hl),0
		inc	hl
		ld	a,(cnddep)	; MX_CDEP: EXITM unwinds to here, so
		ld	(hl),a		; that a body abandoned part-way
					; through an IF does not leave that
					; level open for cndeof to complain
					; about

		ld	hl,mxfp		; and push it
		ld	a,(mxfil)
		jp	pushmac

; --- the body has no lines in it at all.
;
;     A named macro's descriptor stays where it is: the name table points
;     at it, calling it again is legal, and it does nothing. An anonymous
;     one has no owner - mexrept returns from here, BEFORE the expansion
;     record that would have freed it is ever allocated - so this is the
;     only place it can ever be given back. Without this, "rept n" with
;     nothing before its ENDM strands a descriptor per dispatch, and a
;     REPT inside a macro body is dispatched once per expansion.
;
;     MD_KIND decides, which is the same test mxfree makes when the body
;     DOES have lines - the two places an anonymous body can end, asking
;     the same question.

mexnew.nul:	derefp	mxmd
		ld	a,(hl)		; MD_KIND
		or	a
		ret	z		; MDK_MACRO: not ours to free
		ld	hl,mxmd
		call	mxbfree
		or	a		; CY clear = nothing was pushed
		ret

; mxargs - turn the call's argument text into a block in the heap.
;
;   One pass. The offset table is written at its final place while the
;   strings are appended after it, which works because the table's size
;   does not depend on how many arguments there turn out to be.
;
;   Page 2 is held for the whole routine on purpose: nothing here derefs,
;   allocates or calls MSX-DOS after the block is mapped, and the text
;   being read is in the line buffer, in ordinary RAM.
;
;   ONE EXCEPTION,: a "%" argument evaluates an expression,
;   which reaches symlook and so deref. It lets the mapping go and takes
;   it back with one derefp. Nothing else has to be redone, because deref
;   always answers 08000h + offset: the block reappears at the address it
;   had, and every pointer into it is still right. Anything added to this
;   routine later must obey the same rule or do the same thing.
;
;   The two jumps that leave the argument loop are jp, not jr: the loop
;   body is about 110 bytes and jr reaches 127, which is too close to
;   trust - the same arithmetic that caught splitln in fields.as.
;
; Input:	mxatxt -> the argument text
;		mxalen  = its length
; Output:	mxargv = far pointer to the block, null if there were none
;		mxnarg = how many arguments were stored
; Modifies:	AF, BC, DE, HL

mxargs:		xor	a
		ld	(mxnarg),a
		ld	hl,NULLOFF
		ld	(mxargv+2),hl	; null until there is a block
		ld	a,(mxalen)
		or	a
		ret	z		; the call had no operand at all

		call	mxaover		; BC = the block's size, from the
		ld	hl,mxargv	; entries the caller reserved and the
		call	halloc		; text as it stands
		jp	c,errheap

		derefp	mxargv		; HL -> the block, and it stays
		ld	(mxabas),hl	; mapped until this routine returns
		ld	de,(mxatb)	; the text starts where the table ends
		add	hl,de
		ex	de,hl		; DE -> where the first string goes
		ld	hl,(mxatxt)	; HL -> the argument text
		ld	a,(mxalen)
		ld	(mxaleft),a

mxargs.arg:	ld	a,(mxamax)	; B, not HL: HL is the text pointer
		ld	b,a		; and is live all the way round this
		ld	a,(mxnarg)	; loop, while B is set to 0 two
		cp	b		; instructions below
		jp	nc,mxargs.done	; as many as the caller reserved room
					; for. A macro call asks for MDPARMX,
					; and a 17th argument could never be
					; referenced: M80 ignores extras too.
					; An IRP asks for the arithmetic
					; maximum, so for one it never fires
		call	mxaslot		; the table entry, and room for the
		ld	b,0		; length byte. B = characters stored

		call	mxablk		; blanks before it are not part of it
		jr	c,mxargs.emit	; the text ran out: an empty argument
		cp	","
		jr	z,mxargs.emit	; ",,": an empty argument
		cp	"%"
		jp	z,mxargs.pct	; a macro call by value: the VALUE
					; goes in, as digits. mxablk has
					; just skipped the blanks, so this
					; is the argument's FIRST character
					; - the only place % is special
		cp	"<"
		jr	nz,mxargs.pl	; A is its first character

; --- <bracketed>: one level of brackets comes off, inner ones stay

mxargs.br:	ld	c,1		; C = how deep in brackets we are
mxargs.br1:	call	mxanext
		jr	c,mxargs.emit	; unterminated: the line closes it
		cp	"!"
		jr	z,mxargs.brl
		cp	"<"
		jr	nz,mxargs.br2
		inc	c
		jr	mxargs.bre
mxargs.br2:	cp	">"
		jr	nz,mxargs.bre
		dec	c
		jr	z,mxargs.brx	; the matching one: this is the end
mxargs.bre:	call	mxaput
		jr	mxargs.br1
mxargs.brl:	call	mxanext		; "!x": x, whatever x is - and it must
		jr	c,mxargs.emit	; not be counted as a bracket
		call	mxaput
		jr	mxargs.br1
mxargs.brx:	call	mxacom		; anything between ">" and the comma
		jr	mxargs.emit	; is not part of anything

; --- a plain argument: everything up to the next comma

mxargs.pl:	cp	"!"
		jr	nz,mxargs.pl2
		call	mxanext		; "!x": x, whatever x is - including
		jr	c,mxargs.emit	; a comma
		call	mxaput
		jr	mxargs.pl3
mxargs.pl2:	cp	","
		jr	z,mxargs.emit	; the argument ends here
		call	mxaput
mxargs.pl3:	call	mxanext
		jr	nc,mxargs.pl	; and if the text ran out, it also
					; ends here

mxargs.emit:	call	mxatrim		; trailing blanks, then the length
		ld	a,(mxnarg)
		inc	a
		ld	(mxnarg),a
		ld	a,(mxaleft)
		or	a
		jp	nz,mxargs.arg	; there is more after the comma

mxargs.done:	ld	hl,(mxabas)	; MA_CNT last, because the count is
		ld	a,(mxnarg)	; not known until the parsing is over -
		ld	(hl),a		; and page 2 is still ours to write it
		ret

; --- %expression: the value, in decimal digits, instead of the text
;
;     The manual (2.7.9) requires an expression "returning a
;     non-relocatable constant", with the same rules as DS - so evalabs,
;     which is exactly that check.
;
;     This is the one place in mxargs where page 2 is let go. HL (the
;     text) and DE (where the next character goes in the block) are put
;     in RAM first, because the evaluator uses every register, and the
;     block is mapped again afterwards.

mxargs.pct:	ld	(mxpptr),hl	; where the expression starts
		ld	b,0		; and how long it is, to the comma
mxargs.pc1:	call	mxanext
		jr	c,mxargs.pc2	; the text ran out: that ends it
		cp	","
		jr	z,mxargs.pc2	; and so does the comma, consumed
		inc	b		; here exactly as the plain branch
		jr	mxargs.pc1	; would have consumed it
mxargs.pc2:	ld	a,b
		ld	(mxplen),a
		ld	(mxpwr),de	; the two pointers the evaluator
		ld	(mxphl),hl	; would otherwise destroy

		ld	de,(mxpptr)	; the text is in the line buffer, in
		ld	a,(mxplen)	; ordinary RAM, so it is readable
		call	evalabs		; with page 2 in anybody's hands
		ld	de,mxpbuf
		call	numdec		; A = how many digits
		ld	(mxpcnt),a

		derefp	mxargv		; page 2 is ours again, and the block
		ld	de,(mxpwr)	; is back at the address it had
		ld	hl,(mxphl)

		ld	a,(mxpcnt)
		ld	c,a
		ld	b,0		; B counts this argument's characters,
		push	hl		; which is what mxatrim writes as its
		ld	hl,mxpbuf	; length
mxargs.pc3:	ld	a,(hl)
		inc	hl
		call	mxaput
		dec	c
		jr	nz,mxargs.pc3
		pop	hl
		jp	mxargs.emit

; mxanext - the next character of the argument text.
;
; Input:	HL      -> the text
;		mxaleft  = how much is unread
; Output:	CY clear = A is it, HL advanced
;		CY set   = the text is exhausted
; Modifies:	AF, HL

mxanext:	ld	a,(mxaleft)
		or	a
		scf
		ret	z		; nothing left
		dec	a
		ld	(mxaleft),a
		ld	a,(hl)
		inc	hl
		or	a		; A is a real character, so this only
		ret			; clears CY

; mxablk - skip blanks and return the first character that is not one.
;
; Output:	CY clear = A is it
;		CY set   = the text ran out
; Modifies:	AF, HL

mxablk:		call	mxanext
		ret	c
		cp	CHR_SPACE
		jr	z,mxablk
		cp	CHR_TAB
		jr	z,mxablk
		or	a		; a control character would leave CY
		ret			; est after the compare above

; mxacom - throw away everything up to and including the next comma.
;
; Modifies:	AF, HL

mxacom:		call	mxanext
		ret	c
		cp	","
		jr	nz,mxacom
		ret

; mxaput - add the character in A to the argument being built.
;
;   No length check: the block was sized from the operand's length, and
;   removing brackets and "!" can only make the text shorter.
;
; Input:	A   = the character
;		DE -> where it goes
;		B   = the count
; Output:	stored, DE and B advanced
; Modifies:	AF

mxaput:		ld	(de),a
		inc	de
		inc	b
		ret

; mxaslot - start a new argument: record where its length byte is, both
;   in mxasp and in the offset table, and step DE past it.
;
;   The offset stored is from the block's start, not an address, because
;   the block moves in page 2 every time it is mapped.
;
; Input:	DE    -> where this argument goes
;		mxnarg = its index
; Output:	AF, BC, DE

mxaslot:	push	hl
		ld	(mxasp),de	; where the length byte goes
		ld	hl,(mxabas)
		ex	de,hl		; HL = the address, DE = the block
		or	a
		sbc	hl,de		; HL = the offset of the length byte
		ex	de,hl		; DE = the offset, HL -> the block
		ld	a,(mxnarg)	; each table entry is two bytes, and
		ld	c,a		; the doubling is done in 16 bits: an
		ld	b,0		; IRPC can have up to 255 items, and
		add	hl,bc		; "add a,a" would lose the 128th
		add	hl,bc
		ld	bc,MA_TAB
		add	hl,bc		; HL -> this argument's table entry
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	hl,(mxasp)
		inc	hl		; the text starts after the length
		ex	de,hl		; DE -> there
		pop	hl
		ret

; mxatrim - trailing blanks are not part of an argument. Then write the
;   length into the byte mxaslot left for it.
;
; Input:	B = characters stored
;		DE -> just past the last one
; Output:	B and DE cut back, the length byte written
; Modifies:	AF, B, DE

mxatrim:	ld	a,b
		or	a
		jr	z,mxatrim.st	; an empty argument: nothing to trim
		push	hl
		ld	h,d
		ld	l,e
		dec	hl		; HL -> the last character stored
mxatrim.lp:	ld	a,(hl)
		cp	CHR_SPACE
		jr	z,mxatrim.cut
		cp	CHR_TAB
		jr	nz,mxatrim.pop
mxatrim.cut:	dec	hl
		dec	de
		djnz	mxatrim.lp	; and if B reaches 0 the argument was
					; nothing but blanks
mxatrim.pop:	pop	hl
mxatrim.st:	push	hl
		ld	hl,(mxasp)
		ld	(hl),b		; the length, at last
		pop	hl
		ret

; mexitm - EXITM: abandon the expansion on top of the stack.
;
;   The manual (books/m80l80.txt 2.7.7): "the expansion is exited
;   immediately and any remaining expansion or repetition is not
;   generated. If the block containing the EXITM is nested within another
;   block, the outer level continues to be expanded."
;
;   All three fall out of freeing the record and popping one source. The
;   remaining rounds of a REPT go because the count lives in the record;
;   the outer level continues because only the top entry is popped; and
;   mxfree already frees the body and descriptor too when the block was
;   anonymous.
;
;   The conditional stack is the part that does NOT fall out. This is the
;   shape EXITM exists for:
;
;       foo	macro	x
;		ifb	<x>
;		exitm
;		endif
;
;   and the ENDIF is never reached. Without the unwind, one call leaves a
;   level open for cndeof to complain about at the end of a program with
;   nothing wrong with it, and sixteen exhaust MAXCND.
;
; Input:	nothing
; Output:	the top expansion is gone
;		(an EXITM with no expansion open does not return)
; Modifies:	AF, BC, DE, HL, IX

mexitm:		ld	a,(srcdep)
		or	a
		jp	z,errexit	; nothing stacked at all
		ld	ix,(srctop)
		ld	a,(ix+LS_KIND)
		cp	LSK_MACRO
		jp	nz,errexit	; the top source is a file

		call	mxmap		; the depth this expansion started at
		ld	de,MX_CDEP
		add	hl,de
		ld	a,(hl)
		ld	(cnddep),a	; every conditional it opened is
					; abandoned along with the lines that
					; would have closed them

		call	mxfree		; the record, its arguments, and for
		jp	popsrc		; a REPT/IRP/IRPC the body as well

; mxpitem - build the item block for an IRP or an IRPC, before the body
;   is collected.
;
;   The timing is the whole point. The item text is in linebuf, and
;   macrept is about to borrow linebuf for every body line it reads - so
;   by the time the ENDM arrives, a pointer into it aims at rubbish. The
;   block has to exist before that, and the answer (work it out early,
;   it is only two bytes) does not scale to a list.
;
;   The block's pointer does NOT go in mxargv. An IRP inside a macro body
;   is collected while that macro is expanding, and every line macrept
;   reads runs mxamap, which overwrites mxargv. mxirpv is touched by
;   nothing else, and its being null is what tells mexnew.go to parse an
;   operand of its own.
;
; Input:	DE -> the item text, one level of <> already off
;		A   = its length
;		C   = MDK_IRP or MDK_IRPC
; Output:	mxirpv = the block, or null when there was no text
;		BC = iterations
; Modifies:	AF, BC, DE, HL

mxpitem:	ld	(mxatxt),de
		ld	(mxalen),a
		ld	hl,NULLOFF
		ld	(mxirpv+2),hl	; no block yet

		or	a
		jr	nz,mxpitem.go

		ld	a,c		; the kind, BEFORE BC becomes the count
		ld	bc,0		; nothing after the comma. IRPC "" is
		cp	MDK_IRPC	; no characters, so no repetitions;
		ret	z		; IRP <> is once with the dummy removed
		inc	bc		; - and a null block is exactly what
		ret			; "removed" looks like to mxbarg

mxpitem.go:	ld	a,c
		cp	MDK_IRPC
		jr	z,mxpitem.c
		ld	a,(mxalen)	; an IRP: "a,b,c" holds at most
		or	a		; len/2 + 1 items. or a clears the
		rra			; carry rra would otherwise rotate in
		inc	a		; from the top
		ld	(mxamax),a
		call	mxargs
		jr	mxpitem.kp

mxpitem.c:	call	mxchars		; an IRPC: one item per character

mxpitem.kp:	fpcopy	mxirpv,mxargv	; out of the shared scratch and into
		ld	a,(mxnarg)	; somewhere collection cannot reach
		ld	c,a
		ld	b,0
		ret

; mxchars - build an argument block holding one character per item.
;
;   IRPC's "arglist" is a string, and every character of it is an item -
;   spaces and commas included. So there is no grammar here: no brackets
;   come off, no "!" escapes are honoured and no blanks are trimmed. What
;   it shares with mxargs is the block itself, and mxaslot, which writes
;   one table entry.
;
;   It writes each length byte itself rather than calling mxatrim, which
;   would trim a space and turn a perfectly good item into an empty one.
;
; Input:	mxatxt -> the string, mxalen = its length
; Output:	mxargv = the block, mxnarg = how many characters it held
; Modifies:	AF, BC, DE, HL

mxchars:	xor	a
		ld	(mxnarg),a
		ld	hl,NULLOFF
		ld	(mxargv+2),hl	; null until there is a block
		ld	a,(mxalen)
		or	a
		ret	z		; an empty string: no items

		ld	(mxamax),a	; one entry per character, exactly
		ld	(mxaleft),a
		call	mxaover		; BC = the block's size
		ld	hl,mxargv
		call	halloc
		jp	c,errheap

		derefp	mxargv		; HL -> the block, and it stays
		ld	(mxabas),hl	; mapped until this returns
		ld	de,(mxatb)
		add	hl,de
		ex	de,hl		; DE -> where the first item goes
		ld	hl,(mxatxt)

mxchars.ch:	call	mxaslot		; the table entry, and DE past the
		push	hl		; length byte it left room for
		ld	hl,(mxasp)
		ld	(hl),1		; always exactly one character
		pop	hl
		ld	a,(hl)
		inc	hl
		ld	(de),a
		inc	de
		ld	a,(mxnarg)
		inc	a
		ld	(mxnarg),a
		ld	a,(mxaleft)
		dec	a
		ld	(mxaleft),a
		jr	nz,mxchars.ch

		ld	hl,(mxabas)	; MA_CNT last, with page 2 still ours
		ld	a,(mxnarg)
		ld	(hl),a
		ret

; mxaover - one argument block's size, from mxamax and mxalen.
;
;   Three bytes an entry: two of offset table and one length byte, plus
;   MA_CNT itself, plus room for the text as it stands. mxatb is kept as
;   well because the text base is where the table ends - MA_TEXT is no
;   longer a constant now that the table is sized by its caller.
;
;   For mxamax = MDPARMX this computes exactly the MAOVER in mdt.inc,
;   which is why that equate stays there to be compared against.
;
; Input:	mxamax, mxalen
; Output:	mxatb = MA_TAB plus the table's length, BC = the block size
; Modifies:	AF, BC, DE, HL

mxaover:	ld	a,(mxamax)
		ld	l,a
		ld	h,0
		ld	e,l
		ld	d,h
		add	hl,hl		; two bytes of table per entry
		inc	hl		; past MA_CNT: this is the text base
		ld	(mxatb),hl
		add	hl,de		; one length byte per entry
		ld	a,(mxalen)
		ld	e,a
		ld	d,0
		add	hl,de		; and the text
		call	mxapc		; plus room for the digits a "%"
		ld	b,h		; turns into
		ld	c,l
		ret

; mxapc - add three bytes to the size for every "%" in the text.
;
;   "%A" is two characters and 65535 is five, so three bytes each is the
;   most the digits can add. EVERY "%" is counted, not only the ones that
;   start an argument: telling them apart means splitting the text into
;   arguments, which is mxargs' whole job and not worth doing twice. A
;   stray "%" inside an argument costs three bytes of heap and nothing
;   else.
;
; Input:	HL = the size so far
; 		mxatxt -> the text
; 		mxalen  = its length
; Output:	HL = the size, with room for the digits
; Modifies:	AF, BC, DE, HL

mxapc:		ld	a,(mxalen)
		or	a
		ret	z
		ld	b,a
		ld	de,(mxatxt)
mxapc.lp:	ld	a,(de)
		inc	de
		cp	"%"
		jr	nz,mxapc.nx
		push	de
		ld	de,3
		add	hl,de
		pop	de
mxapc.nx:	djnz	mxapc.lp
		ret

; mexline - the next line of a macro expansion
;
;   The same shape as filelin: entry in IX, buffer in HL, carry set when
;   there is nothing left. getline calls one or the other and does not
;   care which.
;
; Input:	IX -> a line source entry of the macro kind
;		HL -> where to put the line
; Output:	CY clear = a line is there, zero-terminated, A = its length
;		CY set   = the body is finished, and the expansion record
;		           has been freed
; Modified:	AF, BC, DE, HL

mexline:	ld	(mxdest),hl

mexline.try:	call	mxmap		; where are we in the body?
		ld	de,MX_BLK
		add	hl,de
		fpsave	mxblk		; and fpsave leaves HL at MX_OFF
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(mxoff),de

		fpnull	mxblk
		jp	z,mexline.end	; no body block: nothing to replay

		derefp	mxblk		; how full is this block?
		ld	de,MB_USED
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(mxend),de

		ld	hl,(mxoff)
		ld	de,(mxend)
		or	a
		sbc	hl,de
		jr	c,mexline.rec	; there is a record at this offset

		derefp	mxblk		; block finished: follow MB_NEXT,
		fpsave	mxblk		; which is at offset 0
		fpnull	mxblk
		jp	z,mexline.end	; no next block: the body is over
		ld	hl,MB_DATA
		ld	(mxoff),hl
		call	mxsave
		jp	mexline.try

; --- copy one record out of the heap, then let page 2 go

mexline.rec:	derefp	mxblk
		ld	de,(mxoff)
		add	hl,de		; HL -> the record
		ld	a,(hl)
		ld	(mxlen),a	; ML_LEN
		inc	hl
		ld	e,(hl)		; ML_LINE
		inc	hl
		ld	d,(hl)
		ld	(mxlin),de
		inc	hl		; HL -> the text
		ld	de,mxrec
		ld	a,(mxlen)
		or	a
		jr	z,mexline.nz
		ld	c,a
		ld	b,0
		ldir
mexline.nz:	ex	de,hl
		ld	(hl),0		; terminate it

		ld	hl,(mxoff)	; step past the record
		ld	a,(mxlen)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,MLHDR
		add	hl,de
		ld	(mxoff),hl
		call	mxsave

		ld	de,(mxlin)	; this line came from body line n of
		ld	(ix+LS_LINE),e	; the definition's file, which is
		ld	(ix+LS_LINE+1),d	; already in LS_FILE

		call	mxbuild		; A = the length
		or	a		; clears CY = a line is there
		ret

; --- the body has run out. For a macro that is the end; for a REPT it
;     may be the end of one iteration out of several.

mexline.end:	call	mxmap
		ld	de,MX_ITER
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		dec	de		; one iteration used up
		ld	a,d
		or	e
		jr	z,mexline.fin	; that was the last of them
		ld	(hl),d		; write the new count back
		dec	hl
		ld	(hl),e
		call	mxrew
		jp	mexline.try

mexline.fin:	call	mxfree
		scf			; CY set = the body is finished
		ret

; mxrew - go back to the first stored line for another iteration.
;
;   MD_BODY is re-read from the descriptor rather than remembered from
;   when the expansion started: one more deref per iteration, and one
;   less far pointer to keep in step inside the record.
;
;   The fresh run of ??nnnn numbers is not housekeeping. Without it every
;   iteration of a REPT containing a LOCAL emits the SAME label, which is
;   precisely what LOCAL exists to prevent (mdt-design.md 7).
;
; Input:	IX -> the entry
; Output:	the record points at the first body line again
; Modifies:	AF, BC, DE, HL

mxrew:		call	mxmap		; the descriptor, out of the record
		ld	de,MX_MD
		add	hl,de
		fpsave	mxmd

		derefp	mxmd		; MD_NLOCL and MD_BODY, one mapping
		ld	de,MD_NLOCL
		add	hl,de
		ld	a,(hl)
		ld	(mxnloc),a
		ld	de,MD_BODY-MD_NLOCL
		add	hl,de
		fpsave	mxblk

		ld	hl,MB_DATA	; back to the first record in it
		ld	(mxoff),hl
		call	mxsave

		call	mxmap		; a fresh run of ??nnnn for this
		ld	de,MX_LBASE	; iteration
		add	hl,de
		ld	de,(mxlctr)
		ld	(hl),e
		inc	hl
		ld	(hl),d

		ld	hl,(mxlctr)	; and the counter moves past it
		ld	a,(mxnloc)
		ld	c,a
		ld	b,0
		add	hl,bc
		ld	(mxlctr),hl

		call	mxmap		; and on to the next item, for an IRP.
		ld	de,MX_ITEM	; A REPT has this incremented too and
		add	hl,de		; does not care: it has no argument
		inc	(hl)		; block, so mxbarg never reads it
		ret

; mxbuild - build the line to deliver from the record just copied out.
;
;   The line can now GROW: a two-byte marker becomes an argument of any
;   length. That is why mxbput checks the room left before every byte,
;   and why this is the first phase in which an expansion can be too long.
;
; Input:	mxrec holds the stored text
;		mxdest holds where the line goes
;		IX -> the line source entry
; Output:	the line is built, zero-terminated, A = its length
; Modifies:	AF, BC, DE, HL

mxbuild:	call	mxamap		; the arguments, mapped once for the
					; whole line
		ld	hl,mxrec
		ld	de,(mxdest)
		ld	b,0		; B = characters delivered
mxbuild.ch:	ld	a,(hl)
		or	a
		jr	z,mxbuild.end
		cp	MP_PARM
		jr	z,mxbuild.mk
		cp	MP_LOCL
		jr	z,mxbuild.lo
		call	mxbput
		inc	hl
		jr	mxbuild.ch
mxbuild.mk:	inc	hl		; the index follows the marker byte
		ld	a,(hl)
		inc	hl
		push	hl
		call	mxbarg
		pop	hl
		jr	mxbuild.ch
mxbuild.lo:	inc	hl		; the same shape, a different source
		ld	a,(hl)
		inc	hl
		push	hl
		call	mxbloc
		pop	hl
		jr	mxbuild.ch
mxbuild.end:	ex	de,hl
		ld	(hl),0		; terminate the delivered line
		ld	a,b		; A = its length
		ret

; mxbput - add the character in A to the line being delivered.
;
; Input:	A   = the character
;		DE -> where it goes
;		B   = the count
; Output:	stored, DE and B advanced
;		(a line that grew too long does not return - errblen stops)
; Modifies:	AF

mxbput:		ld	(mxbch),a
		ld	a,b
		cp	MAXLINE
		jp	nc,errblen
		ld	a,(mxbch)
		ld	(de),a
		inc	de
		inc	b
		ret

; mxbarg - copy argument number A into the line being delivered.
;
;   Both "no arguments at all" and "not that many arguments" produce
;   nothing, which is M80's rule: a parameter with nothing supplied for
;   it is null.
;
; Input:	A   = the index, 0-based
;		DE -> where the text goes
;		B   = characters so far
; Output:	the argument's text is added, DE and B advanced
; Modifies:	AF, C, DE, HL

mxbarg:		ld	hl,mxitem	; an IRP's marker is always index 0,
		add	a,(hl)		; so index + MX_ITEM is the item this
		ld	(mxbidx),a	; iteration wants. A macro's MX_ITEM is
		ld	hl,(mxargp)	; 0, so nothing changes for it
		ld	a,h
		or	l
		ret	z		; the call supplied nothing
		ld	a,(hl)		; MA_CNT
		ld	c,a
		ld	a,(mxbidx)
		cp	c
		ret	nc		; fewer arguments than parameters

		push	bc		; HL -> this argument's table entry. B
		ld	c,a		; is the running character count and
		ld	b,0		; must survive the only 16-bit add the
		add	hl,bc		; z80 has - and the doubling is done in
		add	hl,bc		; 16 bits, because an IRPC can have 255
		pop	bc		; items and "add a,a" would lose the
		inc	hl		; 128th. MA_TAB

		ld	a,(hl)		; HL = the offset in the block
		inc	hl
		ld	h,(hl)
		ld	l,a
		push	de
		ld	de,(mxargp)
		add	hl,de		; HL -> the length byte
		pop	de
		ld	a,(hl)
		or	a
		ret	z		; an empty argument
		ld	c,a		; C = how many characters
		inc	hl
mxbarg.cp:	ld	a,(hl)
		inc	hl
		call	mxbput
		dec	c
		jr	nz,mxbarg.cp
		ret

; mxbloc - put the generated name for LOCAL number A into the line.
;
;   MX_LBASE is read out of the record every time rather than remembered,
;   for the same reason mxargp is: a nested expansion has its own, and
;   nothing may be held across a call.
;
; Input:	A  = the LOCAL's index, 0-based
;		DE -> where the text goes, B = characters so far
; Output:	"??nnnn" is added, DE and B advanced
; Modifies:	AF, C, DE, HL

mxbloc:		ld	(mxbidx),a
		push	de		; DE is the line being built, and
		call	mxmap		; mxmap wants it for the far pointer
		ld	de,MX_LBASE
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl		; HL = this expansion's first number
		push	bc		; B is the running character count
		ld	a,(mxbidx)
		ld	c,a
		ld	b,0
		add	hl,bc		; plus this LOCAL's index
		pop	bc
		pop	de

		ld	a,"?"
		call	mxbput
		ld	a,"?"
		call	mxbput
		ld	a,h		; four hex digits, high byte first
		call	mxbhex
		ld	a,l
		jp	mxbhex

; mxbhex - two hex digits for the byte in A, into the line.
;
;   rrca four times, not rra: rra would rotate the carry flag in through
;   the top. The same shape as puthex in tatara.as, which writes to the
;   output file instead.
;
; Input:	A = the byte
; Output:	two characters are added
; Modifies:	AF, DE (B advanced)

mxbhex:		push	af
		rrca
		rrca
		rrca
		rrca
		call	mxbhex.n	; the high nibble
		pop	af
		jr	mxbhex.n	; the low one, and its return is ours
mxbhex.n:	and	00fh
		add	a,"0"
		cp	"9"+1
		jr	c,mxbhex.p	; 0-9
		add	a,"A"-"9"-1	; A-F
mxbhex.p:	jp	mxbput

; mxamap - map this expansion's argument block, once per line.
;
;   mxargp is where it landed, or zero when the call had no arguments.
;   It is read out of the record eevry time rather than remembered,
;   because a nested expansion overwrites it the moment it starts.
;
; Input:	IX -> the entry
; Output:	mxargp = the block's address in page 2, or 0
; Modifies:	AF, BC, DE, HL

mxamap:		ld	hl,0
		ld	(mxargp),hl
		call	mxmap
		ld	de,MX_ARGV
		add	hl,de
		fpsave	mxargv		; fpsave leaves HL at MX_NARG
		ld	de,MX_ITEM-MX_NARG
		add	hl,de
		ld	a,(hl)		; which item an IRP is on. Zero for
		ld	(mxitem),a	; everything else, and only mxrew ever
					; changes it - so mxbarg can add it
					; without asking what kind this is
		fpnull	mxargv
		ret	z		; the call had no arguments
		derefp	mxargv
		ld	(mxargp),hl
		ret

; mxmap - map the expansion record belonging to this entry.
;
;   The far pointer lives in the entry itself, which is in ordinary RAM,
;   so deref can be handed its address directly - no copy needed.
;
; Input:	IX -> the entry
; Output:	HL -> the expansion record, in page 2
; Modifies:	AF, DE, HL (IX preserved - deref does not touch it)

mxmap:		push	ix
		pop	hl
		ld	de,LS_MX
		add	hl,de
		jp	deref

; mxsave - write mxblk and mxoff back into the expansion record.
;
; Input:	IX -> the entry, mxblk and mxoff
; Output:	the record is updated
; Modifies:	AF, BC, DE, HL

mxsave:		call	mxmap
		ld	de,MX_BLK
		add	hl,de
		ex	de,hl		; DE -> MX_BLK in the record
		ld	hl,mxblk
		ld	bc,4
		ldir			; DE now -> MX_OFF
		ld	hl,(mxoff)
		ex	de,hl		; HL -> MX_OFF, DE = the value
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ret

; mxfree - give the expansion record, and its arguments, back to the
;   heap - and for an anonymous body, the body and its descriptor too.
;
;   The argument block goes first: its far pointer ilves inside the
;   expansion record, so it has to be read out while the record is still
;   there to read.
;
;   A named macro's descriptor and body outlive the expansion: the next
;   call needs them. A REPT's cannot be reached by anything once the
;   record is gone, so this is the last chance to give them back.
;   MD_KIND is what tells the two apart, and this is that field's first
;   real use.
;
; Input:	IX -> the entry
; Output:	everything this expansion owned is freed
; Modifies:	AF, BC, DE, HL

mxfree:		call	mxmap		; the arguments first: their far
		ld	de,MX_ARGV	; pointer lives inside the record
		add	hl,de
		fpsave	mxargv
		fpnull	mxargv
		jr	z,mxfree.md	; the call had no arguments
		ld	hl,mxargv
		call	hfree

mxfree.md:	call	mxmap		; the descriptor's pointer, before
		ld	de,MX_MD	; the record goes
		add	hl,de
		fpsave	mxmd

		push	ix		; the record itself
		pop	hl
		ld	de,LS_MX
		add	hl,de
		call	hfree

		derefp	mxmd		; MD_KIND and MD_FLAGS, kept in DE:
		ld	e,(hl)		; nothing between here and the tests
		inc	hl		; below disturbs it
		ld	d,(hl)
		ld	bc,MD_USES-MD_FLAGS
		add	hl,bc
		dec	(hl)		; one fewer expansion is reading it
		ret	nz		; others still are: it stays

		ld	a,e		; MD_KIND
		or	a
		jr	nz,mxfree.go	; anonymous: no name ever reached it,
					; so this was the last chance
		ld	a,d		; MD_FLAGS
		and	MDF_ORPH
		ret	z		; still reachable by name: it stays

mxfree.go:	ld	hl,mxmd		; nothing reads it and nothing names it
		jp	mxbfree

; mxbfree - free a descriptor and its body chain.
;
;   Called from four places when a body has become unreachable: an
;   anonymous one whose expansion has ended (mxfree above), one that was
;   never expanded at all (mexrept and mexnew.nul), and a named one that
;   has been redefined and whose last reader has finished (mdorph, in
;   macros.as).
;
;   The chain walk copies each block's MB_NEXT into ordinary RAM before
;   freeing the block it came from - the block is in page 2, and hfree
;   remaps it.
;
;   It uses mxmd, mxblk and mxfp as scratch. That is safe even when
;   macros.as calls it in the middle of collecting a definition, because
;   all three are re-read from the expansion record at the top of every
;   mexline, mxamap and mxrew: nothing in this module holds them across a
;   getline.
;
; Input:	HL -> a 4-byte far pointer to the descriptor
; Output:	the body chain and the descriptor are freed
; Modifies:	AF, BC, DE, HL

mxbfree:	ld	de,mxmd
		ld	bc,4
		ldir
		derefp	mxmd		; the chain of blocks, then the
		ld	de,MD_BODY	; descriptor itself
		add	hl,de
		fpsave	mxblk
mxbfree.lp:	fpnull	mxblk
		jr	z,mxbfree.md
		fpcopy	mxfp,mxblk	; keep this one while its successor
		derefp	mxblk		; is read out of it
		fpsave	mxblk		; MB_NEXT is at offset 0
		ld	hl,mxfp
		call	hfree
		jr	mxbfree.lp

mxbfree.md:	ld	hl,mxmd
		jp	hfree

		dseg

mxmd:		defs	4	; far pointer: the descriptor being expanded
mxfp:		defs	4	; far pointer: the expansion record
mxblk:		defs	4	; far pointer: the body block being read
mxoff:		defs	2	; offset of the next record in it
mxend:		defs	2	; how full that block is
mxfil:		defs	1	; the file the definition came from
mxlen:		defs	1	; the record's text length
mxlin:		defs	2	; the record's body line number
mxdest:		defs	2	; where the delivered line goes
mxatxt:		defs	2	; mxargs: the call's argument text
mxalen:		defs	1	; mxargs: how long it is
mxaleft:	defs	1	; mxargs: how much of it is still unread
mxabas:		defs	2	; mxargs: the block's address in page 2
mxasp:		defs	2	; mxargs: this argument's length byte
mxargv:		defs	4	; far pointer: the argument block
mxnarg:		defs	1	; how many arguments it holds
mxargp:		defs	2	; mxbuild: that block, mapped
mxbidx:		defs	1	; mxbarg: the index being spliced
mxbch:		defs	1	; mxbput: the character being added
mxlctr:		defs	2	; the running ??nnnn number. mexinit puts
				;   it back to zero at the start of a pass
mxiter:		defs	2	; mexnew/mexrept: iterations, on its way
				;   into MX_ITER
mxamax:		defs	1	; mxargs/mxchars: table entries to reserve
mxatb:		defs	2	; MA_TAB plus the table, so the text base
mxitem:		defs	1	; mxamap: MX_ITEM, for mxbarg to add
mxirpv:		defs	4	; far pointer: an item block built before
				;   the body was collected, waiting for the
				;   mexrept that will adopt it
mxnloc:		defs	1	; mexnew: MD_NLOCL of the macro being called
mxpptr:		defs	2	; mxargs.pct: where the % expression starts
mxplen:		defs	1	;   and how long it is
mxpwr:		defs	2	;   where the digits go, kept across evalabs
mxphl:		defs	2	;   and the text pointer, the same way
mxpcnt:		defs	1	;   how many digits numdec made
mxpbuf:		defs	5	;   and where it put them
mxrec:		defs	MAXLINE+1	; one stored record, out of the heap
					; and into ordinary RAM. Separate from
					; mdsline in macros.as on purpose: from
					; a macro can be defined while
					; another is expanding
