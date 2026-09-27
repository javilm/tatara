; cond.as - conditional assembly: which lines survive.
;
; One state per open conditional, in a small stack. The rule that keeps
; it simple: an IF met while we are already skipping is pushed as
; CS_DONE, so the innermost state alone answers "are we emitting?".
;
; Nothing here knows about macros, and macros know nothing about this.
; While a definition is being COLLECTED, macdef (macros.as) has its own
; loop and never calls cndline, so conditional directives in a body are
; stored as text and acted on when the macro expands. The two meet only
; in the driver, one line at a time.

CNDLIB		equ	1		; skips the externals in cond.inc

		public	cndinit
		public	cndline
		public	cndeof
		public	cnddep		; how many conditionals are open.
					;   expand.as reads it when an
					;   expansion record is created and
					;   writes it back on EXITM, which
					;   abandons every conditional the
					;   expansion had opened. Those are
					;   the only two places outside this
					;   module that touch it, and the
					;   only variable the program exports

		include	cond.inc
		include	expr.inc
		include	fields.inc
		include	dirtab.inc
		include	ascii.inc

		include	errs.inc
		include	strutil.inc	; strupr: IFIDN compares without case
		include	srcline.inc	; curfile/curline: where the line just
					;   handed over came from. cndpush
					;   records them for the outermost open
					;   conditional, so errncnd can name
					;   the IF rather than the end of the
					;   source

		cseg

; cndinit - no conditionals open.
;
;   Per PASS, not once-only: pass 2 re-reads the source and must start it
;   with an empty stack. Called from main: beside macinit and mexinit.
;
; Input:	nothing
; Output:	the stack is empty
; Modifies:	AF

cndinit:	xor	a
		ld	(cnddep),a
		ret

; cndline - act on this line's conditional directive, if it has one, and
;   say whether the line survives.
;
;   The whole IF..ENDIF family is numbered contiguously in dirtab.inc,
;   D_IF to D_ENDIF, which is what makes the test at the top two
;   compares instead of ten.
;
; Input:	A  = the directive number
;		IX -> the field block for this line
; Output:	CY set   = the line produces nothing
;		CY clear = it goes on to the rest of the driver
; Modifies:	AF, BC, DE, HL, IX

cndline:	cp	D_IF
		jp	c,cndskip	; below the family: an ordinary line
		cp	D_ENDIF+1
		jp	nc,cndskip	; above it
		cp	D_ELSE
		jr	z,cndline.els
		cp	D_ENDIF
		jr	z,cndline.end

; --- an opener. Note the order: whether we are ALREADY skipping is asked
;     first, because if we are, the condition must not be looked at.

		ld	(cnddir),a	; cndtest needs to know which one
		call	cndskip
		ld	a,CS_DONE	; inside a false branch: neither
		jr	c,cndline.psh	; branch of this one may be taken
		call	cndtest		; CY clear = the condition is true
		ld	a,CS_TAKE
		jr	nc,cndline.psh
		ld	a,CS_SKIP
cndline.psh:	call	cndpush
		scf			; the directive itself never survives
		ret

; --- ELSE

cndline.els:	ld	a,(cnddep)
		or	a
		jp	z,errcond	; an ELSE with no IF open
		call	cndtop
		bit	7,a
		jp	nz,errcond	; M80 allows only one ELSE per IF
		and	07fh
		cp	CS_SKIP
		ld	a,CS_DONE	; TAKE -> DONE, DONE -> DONE
		jr	nz,cndline.el2
		ld	a,CS_TAKE	; SKIP -> TAKE: this is the branch
cndline.el2:	or	CS_ELSE		; and it has had its ELSE now
		call	cndset
		scf
		ret

; --- ENDIF

cndline.end:	ld	a,(cnddep)
		or	a
		jp	z,errcond	; an ENDIF with no IF open
		dec	a
		ld	(cnddep),a
		scf
		ret

; cndskip - are we inside a branch that is not being taken?
;
;   Only the innermost state is looked at. See the note at the top of the
;   file for why that is enough.
;
; Input:	nothing
; Output:	CY set = skipping
; Modifies:	AF, DE, HL

cndskip:	ld	a,(cnddep)
		or	a
		ret	z		; nothing open: emitting, CY clear
		call	cndtop
		and	07fh		; the ELSE-seen bit is not a state,
		ret	z		; and CS_TAKE is 0, so this clears CY
		scf
		ret

; cndtop - the innermost open conditional's state byte.
;
; Input:	cnddep > 0
; Output:	A = the state, HL -> where it lives
; Modifies:	AF, DE, HL

cndtop:		ld	a,(cnddep)
		dec	a
		ld	l,a
		ld	h,0
		ld	de,cndstk
		add	hl,de
		ld	a,(hl)
		ret

; cndset - replace the innermost state with A.
;
; Input:	A = the new state, cnddep > 0
; Output:	stored
; Modifies:	AF, DE, HL

cndset:		push	af
		call	cndtop
		pop	af
		ld	(hl),a
		ret

; cndpush - open a conditional with state A.
;
; Input:	A = the state
; Output:	pushed
;		(too deep does not return - errcdep stops)
; Modifies:	AF, BC, DE, HL

cndpush:	ld	c,a
		ld	a,(cnddep)
		cp	MAXCND
		jp	nc,errcdep
		or	a		; pushing level 0? Then this is the
		jr	nz,cndpush.go	; outermost conditional now open, and
		ld	a,(curfile)	; the one errncnd should point at if the
		ld	(cn0fil),a	; source ends with it still open. A
		ld	hl,(curline)	; matched pair at level 0 just
		ld	(cn0lin),hl	; overwrites it with the one that
					; matters
		xor	a
cndpush.go:	inc	a
		ld	(cnddep),a
		ld	a,c
		jp	cndset

; cndeof - the end of the source. Nothing may still be open.
;
; Input:	nothing
; Output:	returns only if the stack is empty
;		(an unclosed conditional does not return - errncnd stops)
; Modifies:	AF

cndeof:		ld	a,(cnddep)
		or	a
		ret	z
		ld	a,(cn0fil)	; the outermost one still open, not the
		ld	hl,(cn0lin)	; end of the source
		jp	errncnd

; --- the conditions themselves

; cndtest - is this conditional's condition true?
;
;   IFB, IFNB, IFIDN and IFDIF are text tests and need nothing but the
;   operand. IF and IFE go through evalexp (expr.as); IFDEF and IFNDEF
;   go straight to the symbol look-up, because for them "not found" is
;   an answer and not an error.
;
; Input:	cnddir = the directive number, IX -> the field block
; Output:	CY clear = true, CY set = false
; Modifies:	AF, BC, DE, HL, IX

cndtest:	ld	a,(cnddir)
		cp	D_IFB
		jr	z,cndtest.b
		cp	D_IFNB
		jr	z,cndtest.nb
		cp	D_IFIDN
		jr	z,cndtest.id
		cp	D_IFDIF
		jr	z,cndtest.df
		cp	D_IFDEF
		jp	z,cndtest.df1
		cp	D_IFNDEF
		jp	z,cndtest.nd
		cp	D_IF
		jp	z,cndtest.if
		cp	D_IFE
		jp	z,cndtest.ife
		cp	D_IF1
		jr	z,cndtest.p1
		cp	D_IF2
		jr	z,cndtest.p2
		or	a
		ret

; IF1 and IF2 ask which reading of the source this is. There was once
; was only one, and they were hardwired true and false.

cndtest.p1:	ld	a,(passno)
		dec	a
		jr	z,cndtest.t	; pass 1: IF1 is true
		jr	cndtest.f
cndtest.p2:	ld	a,(passno)
		dec	a
		jr	z,cndtest.f	; pass 1: IF2 is false
		jr	cndtest.t

cndtest.f:	scf
		ret
cndtest.t:	or	a
		ret

cndtest.b:	xor	a		; IFB: argument 0 is empty
		call	cndarg
		or	a
		ret	z		; blank: true, and or a clears CY
		scf
		ret

cndtest.nb:	xor	a		; IFNB: it is not
		call	cndarg
		or	a
		scf
		ret	z		; blank: false
		or	a
		ret

cndtest.id:	call	cndcmp		; IFIDN: Z set = the same
		jr	z,cndtest.t
		scf
		ret

cndtest.df:	call	cndcmp		; IFDIF
		jr	nz,cndtest.t
		scf
		ret

; --- IF and IFE: the operand is an expression, and a non-zero value is
;     true. It must be known already - an unknown name stops the
;     assembly inside evalexp - but it may be relocatable: zero or not
;     is all that is asked of it.

cndtest.if:	call	cndval
		ld	a,h
		or	l
		jp	nz,cndtest.t
		scf
		ret

cndtest.ife:	call	cndval
		ld	a,h
		or	l
		jp	z,cndtest.t
		scf
		ret

cndval:		ld	e,(ix+FL_ARG)
		ld	d,(ix+FL_ARG+1)
		ld	a,(ix+FL_ARGL)
		jp	evalexp		; HL = the value

; --- IFDEF and IFNDEF: the same look-up the evaluator uses, but here
;     "not found" is the answer rather than an error. That is the
;     manual's own distinction, and it is why these two do not go
;     through evalexp.

cndtest.df1:	call	cnddef		; CY clear = the symbol exists
		jp	nc,cndtest.t
		scf
		ret

cndtest.nd:	call	cnddef
		jp	c,cndtest.t
		scf
		ret

; cnddef - does the operand name a symbol that is defined?
;
;   exlook is a variable holding a routine's ADDRESS. The push/ex/ret
;   below is the Z80's way of calling through one: the target's own ret
;   comes back to cnddef's caller.
;
; Input:	IX -> the field block
; Output:	CY set = no such symbol
; Modifies:	AF, BC, DE, HL, IX

cnddef:		ld	e,(ix+FL_ARG)
		ld	d,(ix+FL_ARG+1)
		ld	a,(ix+FL_ARGL)
		ld	b,a
		or	a
		scf
		ret	z		; no operand at all: not defined
		push	hl
		ld	hl,(exlook)
		ex	(sp),hl
		ret

; cndcmp - are arguments 0 and 1 the same text, ignoring case?
;
;   Argument 0 has to be copied out of the way first - only its address
;   and length, not its text - because finding argument 1 overwrites
;   where cndarg keeps its answer.
;
; Input:	IX -> the field block
; Output:	Z set = identical
; Modifies:	AF, BC, DE, HL

cndcmp:		xor	a
		call	cndarg
		ld	(cnaptr),de
		ld	(cnalen0),a
		ld	a,1
		call	cndarg		; DE -> argument 1, A = its length
		ld	hl,cnalen0
		cp	(hl)
		ret	nz		; different lengths: different
		or	a
		ret	z		; both empty: the same
		ld	c,a		; C = characters to compare
		ld	hl,(cnaptr)
cndcmp.ch:	ld	a,(de)
		call	strupr
		ld	b,a
		ld	a,(hl)
		call	strupr
		cp	b
		ret	nz
		inc	hl
		inc	de
		dec	c
		jr	nz,cndcmp.ch
		ret			; C reached 0, so Z is set

; cndarg - find argument number A in the operand, with one level of
;   angle brackets taken off.
;
;   The same grammar mxargs (expand.as) reads, without the "!" escape and
;   without copying anything: the text stays in the line buffer and this
;   points at it. IRP wants the same routine, which is why it
;   is written to take an index rather than being folded into cndtest.
;
; Input:	A   = which argument, 0-based
;		IX -> the field block
; Output:	DE -> the text, A = its length. A is 0 when there is no
;		such argument, or it is empty
; Modifies:	AF, BC, DE, HL

cndarg:		ld	(cnaidx),a
		ld	b,(ix+FL_ARGL)	; B = characters left in the operand
		ld	l,(ix+FL_ARG)
		ld	h,(ix+FL_ARG+1)

cndarg.lp:	call	cndarg1		; one argument -> cnastr, cnalen
		ld	a,(cnaidx)
		or	a
		jr	z,cndarg.got	; that was the one asked for
		dec	a
		ld	(cnaidx),a
		ld	a,b
		or	a
		jr	nz,cndarg.lp
		xor	a		; the operand ran out first: treat the
		ld	(cnalen),a	; missing argument as empty
cndarg.got:	ld	de,(cnastr)
		ld	a,(cnalen)
		ret

; cndarg1 - step over one argument, noting where its text is and how long
;   it is. HL and B are left past its comma.
;
; Input:	HL -> the operand, B = characters left
; Output:	cnastr, cnalen; HL and B advanced
; Modifies:	AF, B, C, DE, HL

cndarg1:	call	cndaws		; blanks before it are not part of it
		ld	(cnastr),hl
		ld	c,0		; C = characters in it
		ld	a,b
		or	a
		jr	z,cndarg1.end	; nothing left
		ld	a,(hl)
		cp	"<"
		jr	z,cndarg1.br

; --- unbracketed: everything up to the next comma

cndarg1.pl:	ld	a,b
		or	a
		jr	z,cndarg1.end
		ld	a,(hl)
		cp	","
		jr	z,cndarg1.cm
		inc	hl
		dec	b
		inc	c
		jr	cndarg1.pl

cndarg1.cm:	inc	hl		; step over the comma
		dec	b
		jr	cndarg1.end

; --- <bracketed>: one level comes off, inner ones stay

cndarg1.br:	inc	hl		; over the "<"
		dec	b
		ld	(cnastr),hl	; the text starts after it
		ld	d,1		; D = how deep in brackets we are
cndarg1.b1:	ld	a,b
		or	a
		jr	z,cndarg1.end	; unterminated: the line closes it
		ld	a,(hl)
		cp	"<"
		jr	nz,cndarg1.b2
		inc	d
		jr	cndarg1.b3
cndarg1.b2:	cp	">"
		jr	nz,cndarg1.b3
		dec	d
		jr	z,cndarg1.bx	; the matching one: this is the end
cndarg1.b3:	inc	hl
		dec	b
		inc	c
		jr	cndarg1.b1
cndarg1.bx:	inc	hl		; over the ">"
		dec	b
		call	cndacm		; anything before the comma is not
					; part of anything

cndarg1.end:	ld	a,c
		ld	(cnalen),a
		ret

; cndacm - throw away everything up to and including the next comma.
;
; Input:	HL -> the operand, B = characters left
; Output:	HL and B past it
; Modifies:	AF, B, HL

cndacm:		ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		inc	hl
		dec	b
		cp	","
		ret	z
		jr	cndacm

; cndaws - step over spaces and tabs.
;
; Input:	HL -> the operand, B = characters left
; Output:	HL and B past any run of them
; Modifies:	AF, B, HL

cndaws:		ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		cp	CHR_SPACE
		jr	z,cndaws.s
		cp	CHR_TAB
		ret	nz
cndaws.s:	inc	hl
		dec	b
		jr	cndaws

		dseg

cnddep:		defs	1		; how many conditionals are open
cndstk:		defs	MAXCND		; one state byte each
cnddir:		defs	1		; the opener cndtest is working on
cn0fil:		defs	1		; cndpush: where the outermost open
cn0lin:		defs	2		;   conditional is, for errncnd

cnastr:		defs	2		; cndarg: where the argument's text is
cnalen:		defs	1		; cndarg: how long it is
cnaidx:		defs	1		; cndarg: which one is wanted
cnaptr:		defs	2		; cndcmp: argument 0's text
cnalen0:	defs	1		; cndcmp: and its length
