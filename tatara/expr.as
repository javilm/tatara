; expr.as - expressions: turning text into a value.
;
; This is not a routine that conditionals happen to use. Pass 1
; will evaluate every operand in the program through evalexp, so it gets
; the whole operator set now rather than the handful IF needs.
;
; One routine does all five binary precedence levels. exlev is told how
; loose an operator it may accept; it reads a value, and then takes any
; operator that binds at least that tightly, parsing the right-hand side
; one level tighter so that a-b-c comes out as (a-b)-c. The unary
; operators live in exprim, because they attach to what follows them.
;
; The two rules are NOT the same, and getting them the same way round is
; the easiest mistake in this module:
;
;   a BINARY operator of level n parses its right side at level n+1, so
;     that it does not swallow another operator of its own level;
;   a PREFIX operator parses its operand at the level of the tightest
;     group BELOW it, so that it swallows everything binding more
;     tightly than itself.
;
; So NOT, which M80 puts below the comparisons, has its operand parsed
; at level 3 and NOT a EQ b means NOT (a EQ b).
;
; evalexp never searches for a symbol: it calls whatever address is in
; exlook. That is symlook in symtab.as, and what changes is
; what symlook answers rather than anything in this file.

EXPRLIB		equ	1		; skips the externals in expr.inc

		public	exinit
		public	evalexp
		public	evalabs
		public	exlook
		public	exty
		public	exeidx

		include	expr.inc
		include	ascii.inc
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been declared

		include	errs.inc
		include	strutil.inc	; strupr: the name tables are upper case
		include	symtab.inc	; symlook, which exlook now points at

		cseg

; exinit - get this module ready for a pass.
;
;   Per PASS, like macinit, mexinit and cndinit: a DEFL that ended pass 1
;   holding 7 must start pass 2 holding whatever it was first given, or
;   the two passes assemble different programs.
;
; Input:	nothing
; Output:	the pass-0 table is empty and exlook points at it
; Modifies:	AF, BC, DE, HL, IX

exinit:		ld	hl,symlook
		ld	(exlook),hl
		ret			; and nothing else. This once also
					; emptied a table of its own; the symbol
					; table must NOT be emptied per pass -
					; syminit owns it, once, beside heapinit

; evalexp - the value of an expression.
;
; Input:	DE -> the text, A = its length. It need not be
;		zero-terminated: the length is what ends it
; Output:	HL = the value
;		exty = its type (SY_ABS, SY_CODE, SY_DATA)
;		(a bad expression does not return - errxsyn stops)
; Modifies:	AF, BC, DE, HL, IX

evalexp:	ld	(exptr),de
		ld	(exleft),a
		ld	a,SY_ABS
		ld	(exty),a	; until something says otherwise
		ld	a,1		; level 1 accepts every operator
		call	exlev
		push	hl
		call	exws		; nothing may be left over
		ld	a,(exleft)
		or	a
		jp	nz,errxsyn
		pop	hl
		ret

; evalabs - evalexp, for an operand that must be a plain number: the DS
;   count, the REPT count. exabs is the check on its own, which exprim
;   uses for unary minus and NOT/HIGH/LOW; evalabs falls into it.
;
; Input:	as evalexp
; Output:	HL = the value (a relocatable one does not return -
;		errrel stops)
; Modifies:	AF, BC, DE, HL, IX

evalabs:	call	evalexp
exabs:		ld	a,(exty)
		or	a		; SY_ABS is 0
		ret	z
		cp	SYTEXT		; the two reasons read differently
		jp	z,errext	; to whoever wrote the line
		jp	errrel

; exlev - the value of a subexpression, taking only operators that bind
;   at least as tightly as A.
;
;   The whole precedence machinery is these twenty instructions.
;
; Input:	A = the loosest precedence this call may consume, 1..6
; Output:	HL = the value
; Modifies:	AF, BC, DE, HL, IX

exlev:		ld	(exmin),a
		push	af		; exprim can recurse into exlev -
		call	exprim		; through a "(", a "-" or a NOT - and
		pop	af		; that overwrites exmin, so put ours
					; back before using it
		ld	(exmin),a	; HL = the value on the left

exlev.lp:	push	hl		; keep it across the look-ahead
		call	exop		; CY set = no operator here at all
		jr	c,exlev.end
		ld	a,(exmin)	; does it bind tightly enough for us?
		cp	c
		jr	z,exlev.take	; the same level: yes
		jr	nc,exlev.end	; looser than we may take: not ours

exlev.take:	call	exeat		; now consume it
		ld	a,(exty)	; the left side's type, on the stack
		push	af		; for the same reason as exmin: the
					; right side may recurse and overwrite
					; exty
		ld	a,(exopn)
		ld	b,a
		ld	a,(exmin)
		ld	c,a
		push	bc		; the operator, and our own limit
		ld	a,(exprec)
		inc	a		; the right side binds one tighter
		call	exlev
		pop	bc
		ld	a,c
		ld	(exmin),a	; the recursion overwrote it
		pop	af
		ld	(exlty),a	; the left side's type, for exapply
		pop	de		; the value on the left
		ld	a,b
		call	exapply		; DE op HL -> HL, exty = its type
		jr	exlev.lp

exlev.end:	pop	hl
		ret

; --- reading one value

; exprim - read a value: a number, a name, a bracketed expression, or one
;   of the unary operators applied to what follows it.
;
; Input:	nothing (reads exptr/exleft)
; Output:	HL = the value
; Modifies:	AF, BC, DE, HL, IX

exprim:		ld	a,SY_ABS	; a number or a character is absolute;
		ld	(exty),a	; a name, a bracket or a unary operator
					; overwrite it with what it produced
		call	exws
		call	expeek		; CY set = the text ran out
		jp	c,errxsyn
		cp	"("
		jr	z,exprim.par
		cp	"-"
		jr	z,exprim.neg
		cp	"+"
		jr	z,exprim.pos
		cp	QUOTE1
		jr	z,exprim.chr
		cp	QUOTE2		; M80 HAS TWO STRING DELIMITERS and so
		jr	z,exprim.chr	;   has this program: opisq,
					;   dbqstr and opqrun all take either.
					;   The evaluator was the one that did
					;   not: "db ""A""" worked and
					;   "cp ""A""" did not
		cp	"0"
		jr	c,exprim.nam	; below "0": not a digit
		cp	"9"+1
		jp	c,exnum		; a digit: M80 says it is a number

exprim.nam:	call	exword		; a name, or a word operator
		ld	a,(exwlen)
		or	a
		jp	z,errxsyn	; not a name character either
		call	exulk		; NOT, HIGH or LOW?
		jr	nc,exprim.un
		jp	exsym		; an ordinary name

exprim.un:	ld	a,(exopn)	; exulk left the PRECEDENCE in A, so
		push	af		; the operator itself comes from the
		ld	a,(exprec)	; variable - and it goes on the STACK,
		call	exlev		; because the operand may be another
		call	exabs		; unary operator and would overwrite
					; a variable.
		pop	af		; NOT, HIGH, LOW: absolute only
		jp	exuapp		; For a UNARY operator the table holds
					; the level to parse its operand at, so
					; there is no inc a here, unlike
					; exlev.take

exprim.par:	call	exeat1		; over the "("
		ld	a,1
		call	exlev
		push	hl
		call	exws
		call	expeek
		jp	c,errxsyn	; the text ended before the ")"
		cp	")"
		jp	nz,errxsyn
		call	exeat1
		pop	hl
		ret

exprim.neg:	call	exeat1		; over the "-"
		ld	a,5		; unary minus binds looser than "*",
		call	exlev		; so -a*b is -(a*b)
		call	exabs		; 0 - relocatable: no rule allows it
		ex	de,hl
		ld	hl,0
		or	a
		sbc	hl,de
		ret

; Unary plus, which does nothing and has to exist anyway: an index
; displacement is remembered WITH ITS SIGN, because the sign is part of
; the value, so emitd hands "+5" to the evaluator exactly as it hands it
; "-1". exprim had the minus and not the plus, and every "(ix+d)" in the
; suite reported "bad expression" the first time one was emitted.
;
; It is a gap in the expression language rather than anything to do with
; displacements - "db +1" was broken too, and had been for a long time.

exprim.pos:	call	exeat1		; over the "+", and start again on
		jp	exprim		;   what follows. "+ +5" is 5 too,
					;   which costs nothing to allow

exprim.chr:	jp	exchar

; exuapp - apply the unary operator in A to HL.
;
; Input:	A = the operator number, HL = the operand
; Output:	HL = the result
; Modifies:	AF, HL

exuapp:		cp	OP_NOT
		jr	z,exuapp.not
		cp	OP_HIGH
		jr	z,exuapp.hi
		ld	h,0		; OP_LOW
		ret
exuapp.hi:	ld	l,h
		ld	h,0
		ret
exuapp.not:	ld	a,h
		cpl
		ld	h,a
		ld	a,l
		cpl
		ld	l,a
		ret

; exsym - a name: look it up through exlook and take its value.
;
;   exlook is a variable holding a routine's ADDRESS. "call exsym.go"
;   pushes the return, the push/ex/ret below transfers, and that
;   routine's own ret comes back here - the Z80's way of calling through
;   a pointer.
;
; Input:	exwptr/exwlen say where the name is
; Output:	HL = its value, exty updated
;		(an unknown name does not return - errxund stops)
; Modifies:	AF, BC, DE, HL, IX

exsym:		ld	de,(exwptr)
		ld	a,(exwlen)
		ld	b,a
		dec	a		; one character long...
		jr	nz,exsym.tab
		ld	a,(de)
		cp	"$"		; ...and it is "$": the location
		jr	nz,exsym.tab	; counter, in the current segment's
		ld	hl,(locctr)	; mode. "$foo" is longer, and an
		ld	a,(curseg)	; ordinary name
		ld	(exty),a
		ret
exsym.tab:	call	exsym.go	; CY set = no such symbol
		jp	c,errxund
		ld	(exty),a
		ld	a,(symfl)	; an external is not a place: it
		and	SYF_EXT		; carries SYTEXT so that exapply can
		ret	z		; apply 2.4.3's rules to it
		ld	(exeidx),hl	; ITS INDEX, WHICH IS NOT ITS VALUE.
		ld	hl,0		;   symext put the index in SY_VAL
		ld	a,SYTEXT	;   because that is where an external
		ld	(exty),a	;   record keeps it - but what goes in
		ret			;   the word is the ADDEND, and the
					;   index goes's RELOC record.
					;   "baz+5" used to store index+5
exsym.go:	push	hl
		ld	hl,(exlook)
		ex	(sp),hl
		ret

; exnum - a number, in decimal or in the base its suffix names.
;
;   M80: the default base is decimal; nnnnB, nnnnD, nnnnO, nnnnQ and
;   nnnnH name their own. A number always starts with a digit, which is
;   why exprim can tell one from a name without looking ahead.
;
; Input:	exptr/exleft at its first digit
; Output:	HL = its value
;		(a bad digit does not return - errxsyn stops)
; Modifies:	AF, BC, DE, HL

exnum:		call	exword		; the whole run of letters and digits
		ld	a,(exwlen)
		ld	c,a		; C = how many characters are left
		ld	b,10		; B = the base, decimal by default
		ld	hl,(exwptr)
		ld	e,a
		ld	d,0
		add	hl,de
		dec	hl		; HL -> the last character
		ld	a,(hl)
		call	strupr
		cp	"B"
		jr	z,exnum.b2
		cp	"D"
		jr	z,exnum.b10
		cp	"O"
		jr	z,exnum.b8
		cp	"Q"
		jr	z,exnum.b8
		cp	"H"
		jr	nz,exnum.go	; no suffix: the base stays 10
		ld	b,16
		jr	exnum.cut
exnum.b2:	ld	b,2
		jr	exnum.cut
exnum.b8:	ld	b,8
		jr	exnum.cut
exnum.b10:	ld	b,10
exnum.cut:	dec	c		; the suffix is not a digit
		jp	z,errxsyn	; a suffix with no digits before it

exnum.go:	ld	a,c
		ld	(exndig),a	; digits still to take
		ld	a,b
		ld	(exbase),a
		ld	hl,0
		ld	de,(exwptr)

exnum.ch:	ld	a,(exndig)
		or	a
		ret	z		; done: HL is the value
		dec	a
		ld	(exndig),a

		ld	a,(de)
		inc	de
		call	strupr
		sub	"0"
		jp	c,errxsyn
		cp	10
		jr	c,exnum.dg
		sub	"A"-"0"-10	; A-F, for base 16
		cp	10
		jp	c,errxsyn
exnum.dg:	ld	c,a		; C = this digit
		ld	a,(exbase)
		cp	c
		jp	c,errxsyn	; too large for the base
		jp	z,errxsyn

		push	de		; HL = HL * base + digit
		ld	b,a
		ld	d,h
		ld	e,l
		ld	hl,0
exnum.mul:	add	hl,de		; the base is 2..16, so adding it up
		djnz	exnum.mul	; is smaller than a shift-and-add
		ld	e,c
		ld	d,0
		add	hl,de
		pop	de
		jr	exnum.ch

; exchar - a character constant: 'A', 'AB', "A" or "AB". Either
;   delimiter opens one and the same one closes it.
;
;   Two characters make a 16-bit value with the FIRST in the high byte,
;   which is the order that makes 'AB' read the way it is written.
;
; Input:	exptr at the opening quote
; Output:	HL = the value
; Modifies:	AF, BC, DE, HL

exchar:		call	expeek		; WHICH delimiter opened it: the same
		ld	b,a		;   one has to close it, and a doubled
		call	exeat1		;   pair stands for it. B carries it
		ld	hl,0		;   through the whole scan - exeat1
					;   modifies AF and HL, expeek modifies
					;   AF, and NEITHER TOUCHES BC
exchar.ch:	call	expeek
		jp	c,errxsyn	; the line ended inside the quotes
		cp	b
		jr	z,exchar.end
		ld	h,l		; shift the previous character up and
		ld	l,a		; take this one - BEFORE exeat1, which
		push	hl		; destroys A, and across it, because it
		call	exeat1		; destroys HL too. This is the only
		pop	hl		; place in the module that keeps a
		jr	exchar.ch	; value in HL while consuming text,
					; which is why it is the only place
					; that has to say so
; A delimiter: the end of the run, or two of them standing for one
; character of it? The same rule dbqstr and opqrun keep, and exchar is
; the fourth routine in the program to keep it. Reading all
; four side by side and says why they stay four: they share a RULE, not
; an interface - four different cursors, four different products, and
; one of them is not a routine at all.

exchar.end:	push	hl
		call	exeat1		; over the closing quote
		call	expeek
		jr	c,exchar.fin	; the text ran out: it closed here
		cp	b
		jr	nz,exchar.fin	; something else follows: it closed
		pop	hl		; two delimiters are ONE character of
		ld	h,l		;   the run: shift it in and go round
		ld	l,b		;   for the rest, whichever it is
		push	hl
		call	exeat1		; over the second one
		pop	hl
		jr	exchar.ch
exchar.fin:	pop	hl
		ret

; --- operators

; exop - what operator comes next? Does NOT consume it, because the
;   caller only takes it if it binds tightly enough.
;
; Input:	nothing
; Output:	CY set   = there is no operator here
;		CY clear = exopn = its number, exprec = its precedence,
;			   C = the same precedence, exlen1 = how many
;			   characters it occupies
; Modifies:	AF, BC, DE, HL

exop:		call	exws
		call	expeek
		ret	c		; the text ran out
		cp	")"
		scf
		ret	z		; a ")" ends this subexpression
		ld	hl,exop1	; one of the four punctuation ones?
exop.p:		ld	a,(hl)
		or	a
		jr	z,exop.wd	; the end of that little table
		push	hl
		call	expeek		; the character we are looking at
		pop	hl
		cp	(hl)
		jr	z,exop.got1
		inc	hl		; over the character, the number and
		inc	hl		; the precedence, to the next entry
		inc	hl
		jr	exop.p

exop.wd:	call	exwpk		; a word, without consuming it
		ld	a,(exwlen)
		or	a
		scf
		ret	z		; not a name character: no operator
		call	exwlk		; look it up in the operator table
		ret	c		; a name, not an operator
		ld	a,(exwlen)
		ld	(exlen1),a
		or	a		; clears CY = there is an operator
		ret

exop.got1:	inc	hl		; HL -> this entry's operator number
		ld	a,(hl)
		ld	(exopn),a
		inc	hl
		ld	a,(hl)
		ld	(exprec),a
		ld	c,a
		ld	a,1
		ld	(exlen1),a	; punctuation is always one character
		or	a		; no precedence is 0, so this clears CY
		ret

; exwlk - is the word at exwptr a binary operator?
; exulk - is it one of the unary ones?
;
;   The same walk over two tables: a length byte, the name in upper case,
;   the operator number, the precedence; a zero length ends it. The same
;   shape as dirtab in dirtab.as.
;
; Input:	exwptr/exwlen say where the word is
; Output:	CY set   = not in that table
;		CY clear = exopn and exprec are set, C = the precedence
; Modifies:	AF, BC, DE, HL

exwlk:		ld	hl,exopw
		jr	exlk
exulk:		ld	hl,exopu

exlk:		ld	a,(exwlen)
		ld	b,a		; B = the length we are looking for
exlk.ent:	ld	a,(hl)
		or	a
		scf
		ret	z		; the end of the table: no match
		cp	b
		jr	z,exlk.try
exlk.nx:	ld	a,(hl)		; over the length, the name, and the
		add	a,3		; two bytes after it
		add	a,l
		ld	l,a
		jr	nc,exlk.ent
		inc	h
		jr	exlk.ent

exlk.try:	push	hl
		ld	de,(exwptr)
		ld	c,b		; C = characters left to compare
exlk.ch:	inc	hl
		ld	a,(de)
		call	strupr		; the tables are stored upper case
		cp	(hl)
		jr	nz,exlk.no
		inc	de
		dec	c
		jr	nz,exlk.ch
		inc	hl		; past the last character of the name
		ld	a,(hl)
		ld	(exopn),a	; the operator number
		inc	hl
		ld	a,(hl)
		ld	(exprec),a	; and its precedence
		ld	c,a
		pop	hl
		or	a		; no precedence is 0, so this clears CY
		ret

exlk.no:	pop	hl
		jr	exlk.nx

; exeat - consume the operator exop just found. exeat1 consumes one
;   character.
;
; Modifies:	AF, HL

exeat:		ld	a,(exlen1)
		jr	exeatn
exeat1:		ld	a,1
exeatn:		push	bc
		ld	c,a
		ld	a,(exleft)
		sub	c
		ld	(exleft),a
		ld	hl,(exptr)
		ld	b,0
		add	hl,bc
		ld	(exptr),hl
		pop	bc
		ret

; exapply - combine two values with the binary operator in A.
;
;   The comparisons answer 0ffffh for true and 0 for false, which is what
;   makes NOT and AND behave the way a programmer expects on their
;   results.
;
;   The TYPES are checked first, against M80's rules (manual 2.4.2):
;
;     abs + mode = mode        mode + abs = mode
;     mode - abs = mode        mode - same mode = abs
;     anything else needs both sides absolute, and gives absolute.
;
;   SY_ABS is 0, so "both absolute" is "the OR of the two is 0".
;
; Input:	A     = the operator
;		DE    = the left value
;		HL    = the right
;		exlty = the left's side type
;		exty  = the right side's
; Output:	HL   = the result
;		exty = its type
; Modifies:	AF, BC, DE, HL

exapply:	ld	c,a		; C = the operator: A is needed below
		ld	a,(exlty)
		ld	b,a		; B = the left side's type
		cp	SYTEXT		; is either side external? Those have
		jr	z,exa.ext	; their own rules, and the do not
		ld	a,(exty)	; apply to them at all
		cp	SYTEXT
		jr	z,exa.ext
		ld	a,c
		cp	OP_ADD
		jr	z,exa.tadd
		cp	OP_SUB
		jr	z,exa.tsub
		ld	a,(exty)	; anything else; both absolute, and so
		or	b		; is the result - exty is already 0
		jp	nz,errrel
		jr	exa.go

exa.tadd:	ld	a,b		; the left absolute: the result is the
		or	a		; right side's type, already in exty
		jr	z,exa.go
		ld	a,(exty)	; the left relative: the right must be
		or	a		; absolute, and the result is the
		jp	nz,errrel	; left's
		ld	a,b
		ld	(exty),a
		jr	exa.go

exa.tsub:	ld	a,(exty)
		or	a
		jr	nz,exa.tsub2
		ld	a,b		; mode - abs = mode
		ld	(exty),a
		jr	exa.go
exa.tsub2:	cp	b		; mode - the same mode = abs
		jp	nz,errrel
		xor	a
		ld	(exty),a
		jr	exa.go

; --- an external: M80 2.4.3. It may be added to a plain number, or have
;     one subtracted from it, and that is the whole list. The result is
;     external, and there may be only one in an expression - which falls
;     out of insisting that the other side be absolute.

exa.ext:	ld	a,c
		cp	OP_ADD
		jr	z,exa.eadd
		cp	OP_SUB
		jp	nz,errext	; multiplied, compared, anything else
		ld	a,b		; the LEFT must be the external one:
		cp	SYTEXT		; "5 - extern" is not a number the
		jp	nz,errext	; linker can finish
		ld	a,(exty)
		or	a		; and the right must be absolute
		jp	nz,errext
		jr	exa.eset

exa.eadd:	ld	a,b		; one side external, the other
		cp	SYTEXT		; absolute - either way round
		jr	nz,exa.eadd2
		ld	a,(exty)
		or	a
		jp	nz,errext
		jr	exa.eset
exa.eadd2:	ld	a,b
		or	a
		jp	nz,errext

exa.eset:	ld	a,SYTEXT	; and the answer is still external
		ld	(exty),a
exa.go:		ld	a,c		; the operator again
		cp	OP_ADD
		jr	z,exa.add
		cp	OP_SUB
		jr	z,exa.sub
		cp	OP_AND
		jr	z,exa.and
		cp	OP_OR
		jr	z,exa.or
		cp	OP_XOR
		jr	z,exa.xor
		cp	OP_MUL
		jp	z,exa.mul
		cp	OP_DIV
		jp	z,exa.div
		cp	OP_MOD
		jp	z,exa.mod
		cp	OP_SHL
		jp	z,exa.shl
		cp	OP_SHR
		jp	z,exa.shr
		jp	exa.cmp		; one of the six comparisons

exa.add:	add	hl,de
		ret
exa.sub:	ex	de,hl
		or	a
		sbc	hl,de
		ret
exa.and:	ld	a,h
		and	d
		ld	h,a
		ld	a,l
		and	e
		ld	l,a
		ret
exa.or:		ld	a,h
		or	d
		ld	h,a
		ld	a,l
		or	e
		ld	l,a
		ret
exa.xor:	ld	a,h
		xor	d
		ld	h,a
		ld	a,l
		xor	e
		ld	l,a
		ret

exa.shl:	ld	a,l		; HL = DE shifted left by HL
		ex	de,hl
		or	a
		ret	z
		ld	b,a
exa.shl1:	add	hl,hl
		djnz	exa.shl1
		ret
exa.shr:	ld	a,l
		ex	de,hl
		or	a
		ret	z
		ld	b,a
exa.shr1:	srl	h
		rr	l
		djnz	exa.shr1
		ret

; exa.mul, exa.div, exa.mod - nothing in the Z80 multiplies or divides,
;   so these are the schoolbook shift-and-add and shift-and-subtract.

exa.mul:	ld	b,h		; BC = the right-hand value
		ld	c,l
		ex	de,hl		; HL = the left
		ld	de,0		; DE = the running product
exa.mul1:	ld	a,b
		or	c
		jr	z,exa.mule
		srl	b		; is the low bit of BC set?
		rr	c
		jr	nc,exa.mul2
		ex	de,hl		; yes: add HL into the product
		add	hl,de
		ex	de,hl
exa.mul2:	add	hl,hl		; and double the multiplicand
		jr	exa.mul1
exa.mule:	ex	de,hl
		ret

exa.div:	jp	exdiv		; HL = the quotient
exa.mod:	call	exdiv
		ex	de,hl		; DE held the remainder
		ret

; exdiv - HL = DE / HL, DE = DE MOD HL. Division by zero gives all ones
;   and a remainder of the numerator, which is what M80 does and is not
;   an error.
;
; Modifies:	AF, BC, DE, HL

exdiv:		ld	a,h
		or	l
		jr	nz,exdiv.go
		ex	de,hl		; by zero: all ones
		ld	hl,0ffffh
		ret
exdiv.go:	ld	b,h		; BC = the divisor
		ld	c,l
		ex	de,hl		; HL = the numerator
		ld	de,0		; DE = the running remainder
		ld	a,16
exdiv.lp:	push	af
		add	hl,hl		; the top bit of HL into DE
		ex	de,hl
		adc	hl,hl
		or	a
		sbc	hl,bc		; does the divisor go in?
		jr	nc,exdiv.one
		add	hl,bc		; no: put it back
		ex	de,hl
		pop	af
		dec	a
		jr	nz,exdiv.lp
		ret
exdiv.one:	ex	de,hl
		inc	l		; yes: a 1 into the quotient
		pop	af
		dec	a
		jr	nz,exdiv.lp
		ret

; exa.cmp - the six comparisons. Unsigned, because M80's numbers are
;   16-bit unsigned quantities.
;
; Input:	A = the operator, DE = the left value, HL = the right
; Output:	HL = 0ffffh for true, 0 for false
; Modifies:	AF, BC, DE, HL

exa.cmp:	ld	(excmp),a
		ex	de,hl		; HL = the left, DE = the right
		or	a
		sbc	hl,de		; CY set = left < right, Z = equal
		ld	a,(excmp)	; ld does not touch the flags
		push	af
		ld	a,0
		adc	a,0		; A = 1 when left was less
		ld	c,a
		pop	af		; the sbc flags, and A = the operator
		ld	b,0
		jr	nz,exa.cmp1
		inc	b		; B = 1 when they were equal
exa.cmp1:	cp	OP_EQ
		jr	z,exa.cmpe
		cp	OP_NE
		jr	z,exa.cmpn
		cp	OP_LT
		jr	z,exa.cmpl
		cp	OP_GE
		jr	z,exa.cmpge
		cp	OP_LE
		jr	z,exa.cmple
		ld	a,b		; OP_GT: neither less nor equal
		or	c
		jr	exa.cmpf
exa.cmpe:	ld	a,b
		jr	exa.cmpt
exa.cmpn:	ld	a,b
		jr	exa.cmpf
exa.cmpl:	ld	a,c
		jr	exa.cmpt
exa.cmpge:	ld	a,c
		jr	exa.cmpf
exa.cmple:	ld	a,b
		or	c

exa.cmpt:	or	a		; true when A is non-zero
		jr	nz,exa.true
		jr	exa.false
exa.cmpf:	or	a		; true when A is zero
		jr	z,exa.true
exa.false:	ld	hl,0
		ret
exa.true:	ld	hl,0ffffh
		ret

; --- the little scanners. All of them work on exptr/exleft rather than
;     on registers, because there are not enough registers to carry a
;     position through a recursive descent.

; expeek - the character at the scan position, without consuming it.
;
; Output:	CY set = nothing left; CY clear = A is it
; Modifies:	AF

expeek:		push	hl
		ld	a,(exleft)
		or	a
		jr	z,expeek.no
		ld	hl,(exptr)
		ld	a,(hl)
		pop	hl
		or	a		; a real character, so this clears CY
		ret
expeek.no:	pop	hl
		scf
		ret

; exws - step over spaces and tabs.
;
; Modifies:	AF

exws:		call	expeek
		ret	c
		cp	CHR_SPACE
		jr	z,exws.s
		cp	CHR_TAB
		ret	nz
exws.s:		call	exeat1
		jr	exws

; exword - find the run of name characters at the scan position and
;   consume it. exwpk does the same WITHOUT consuming it.
;
;   IT DOES NOT COPY. The word is left where it already is - in the text
;   evalexp was handed, which stays put for as long as evalexp runs - and
;   exwptr/exwlen say where it is and how long. This once copied
;   into a 32-byte buffer and every consumer read the copy, which cost 32
;   bytes of ordinary RAM and silently truncated any name past 32
;   characters into a lie: the truncation was looked up, not found, and
;   reported as "undefined symbol" for a symbol defined three lines up.
;
;   cond.as reached the same conclusion from the other direction:
;   cndarg points into the line buffer rather than copying, because
;   IFIDN is finished before the next getline. An expression is a cndarg,
;   not a mxargs.
;
;   The cap that remains is 255, because exwlen is one byte. That one is
;   not a truncation of anything real: R1's limit is 255 and MAXLINE is
;   255 too, so a longer name could never have been defined, and looking
;   up the first 255 characters of it fails with "undefined symbol" -
;   which is the truth.
;
; Output:	exwptr, exwlen
; Modifies:	AF, BC, HL

exword:		call	exwpk
		ld	a,(exwlen)
		ld	(exlen1),a
		or	a
		ret	z
		jp	exeat

exwpk:		ld	hl,(exptr)
		ld	(exwptr),hl	; where the word starts, in the text
		ld	a,(exleft)
		ld	b,a		; B = characters left in the text
		ld	c,0		; C = how many are name characters
exwpk.ch:	ld	a,b
		or	a
		jr	z,exwpk.end
		ld	a,c
		inc	a
		jr	z,exwpk.end	; 255 is all exwlen can count
		ld	a,(hl)
		call	exisid
		jr	nz,exwpk.end
		inc	hl
		dec	b
		inc	c
		jr	exwpk.ch
exwpk.end:	ld	a,c
		ld	(exwlen),a
		ret

; exisid - may this character appear in a name? M80's set is the
;   letters, the digits, and ? @ . _ $ - the same set mdisid uses in
;   macros.as, and the fifth place this test has been written. It belongs
;   in strutil.as with the case fold.
;
; Output:	Z set = yes
; Modifies:	F

exisid:		cp	"0"
		jr	c,exisid.p
		cp	"9"+1
		jr	c,exisid.y
		cp	"A"
		jr	c,exisid.p
		cp	"Z"+1
		jr	c,exisid.y
		cp	"a"
		jr	c,exisid.p
		cp	"z"+1
		jr	c,exisid.y
exisid.p:	cp	"?"
		ret	z
		cp	"@"
		ret	z
		cp	"."
		ret	z
		cp	"_"
		ret	z
		cp	"$"
		ret
exisid.y:	cp	a
		ret

		dseg

; The four operators that need no space around them: the character, the
; number, the precedence. A zero ends the table.

exop1:		defb	"*",	OP_MUL,	5
		defb	"/",	OP_DIV,	5
		defb	"+",	OP_ADD,	4
		defb	"-",	OP_SUB,	4
		defb	0

; The word operators: a length, the name in UPPER CASE, the number, the
; precedence. Anything else that looks like a word is a name.

exopw:		defb	3,"MOD",  OP_MOD,  5
		defb	3,"SHR",  OP_SHR,  5
		defb	3,"SHL",  OP_SHL,  5
		defb	2,"EQ",   OP_EQ,   3
		defb	2,"NE",   OP_NE,   3
		defb	2,"LT",   OP_LT,   3
		defb	2,"LE",   OP_LE,   3
		defb	2,"GT",   OP_GT,   3
		defb	2,"GE",   OP_GE,   3
		defb	3,"AND",  OP_AND,  2
		defb	2,"OR",   OP_OR,   1
		defb	3,"XOR",  OP_XOR,  1
		defb	0

; The unary ones, which exprim looks up separately because they take a
; following operand rather than joining two. Here the last column is the
; level their OPERAND is parsed at, not their own precedence - see the
; note at the top of the file.

exopu:		defb	3,"NOT",  OP_NOT,  3
		defb	4,"HIGH", OP_HIGH, 6
		defb	3,"LOW",  OP_LOW,  6
		defb	0

exptr:		defs	2	; where the scan has got to
exleft:		defs	1	; how much of the expression is unread
exmin:		defs	1	; exlev: the loosest operator it may take
exlook:		defs	2	; the ADDRESS of the symbol look-up. Phase
				;   13 stores the real one here and nothing
				;   else in this module changes
exty:		defs	1	; the type of the value just produced
exeidx:		defs	2	; the external index of the name exsym
				;   last looked up. One variable is enough
				;   because exapply allows only one external
				;   in an expression
exlty:		defs	1	; exapply: the type of its LEFT operand.
				;   exlev.take keeps it on the stack across
				;   the right side and stores it here last
exopn:		defs	1	; exop: which operator it found
exprec:		defs	1	; exop: and its precedence
exlen1:		defs	1	; exop: how many characters it occupies
excmp:		defs	1	; exa.cmp: which comparison
exbase:		defs	1	; exnum: the base this number is in
exndig:		defs	1	; exnum: digits still to take
exwlen:		defs	1	; the word just collected
exwptr:		defs	2	; and where it is, in evalexp's own text

