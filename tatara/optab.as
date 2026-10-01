; optab.as - the instruction table, its lookup, and the operand cursor.
;
; An operation is recognised as a mnemonic, and the
; class handler for its family is told where the operands are.
;
;   THE TABLE IS ONE ROW PER MNEMONIC, not one per operand form. A row
;   is a length byte, the name in upper case, a class and a base opcode
;   - six bytes for a three-character name, 425 for the whole Z80 and
;   R800 instruction set. The alternative, a row per (mnemonic, operand
;   form) pair, is about 2.2 KB of resident data for the same job, and
;   data has been the binding constraint in every phase of this project.
;   optable-design.md 5 is the argument in full.
;
;   THE CURSOR IS IN MEMORY, not in registers. An instruction's operands
;   are walked by several routines in turn - and
;   threading a pointer and a count through all of them costs more in
;   pushes and pops than the three bytes opptr and oplen take.

OPTLIB		equ	1		; skips the externals in optab.inc

		public	opfind
		public	opinit
		public	opskip
		public	opnone
		public	opword
		public	opr8
		public	opexp
		public	opcomma
		public	opadv
		public	opend
		public	opany
		public	opqrun
		public	opccm
		public	opisc
		public	opissp
		public	opnodsp
		public	oprest
		public	opxtext
		public	opdtext
		public	opkind
		public	opcod
		public	opfix
		public	regtab
		public	cctab

		include	optab.inc
		include	strutil.inc	; strupr
		include	ascii.inc	; CHR_TAB
		include	errs.inc	; erroper

		cseg

; opfind - is this operation one of the Z80's or the R800's mnemonics?
;
;   The same walk as dirlook in dirtab.as, with two payload bytes rather
;   than one. They are deliberately NOT shared: they differ in payload
;   size, in return convention and in what they do when they fail, the
;   genuinely common part is a twelve-instruction compare loop, and one
;   routine with a payload-size parameter would save about 25 bytes and
;   add a parameter to the two most-executed lookups in the assembler.
;   If a third table ever appears, merge all three then.
;
;   The comparison folds to upper case, so a mnemonic is recognised in
;   either case even when /C makes symbols case-sensitive. That is not
;   an oversight: M80 2.3 says opcodes typed in lower case are converted
;   to upper case, and it says it about opcodes whatever the symbols do.
;
; Input:	DE -> the operation text, NOT zero-terminated
;		B  = how many characters it has
; Output:	CY set   = no such mnemonic
;		CY clear = A is its class, C its base opcode
; Modifies:	AF, BC, DE, HL

opfind:		ld	hl,optab
opf.ent:	ld	a,(hl)		; this entry's length byte
		or	a
		scf
		ret	z		; the end marker: no such mnemonic
		cp	b
		jr	z,opf.try	; same length: worth comparing
opf.next:	ld	a,(hl)		; step over length + name + class
		add	a,3		;   + base
		add	a,l
		ld	l,a
		jr	nc,opf.ent
		inc	h
		jr	opf.ent

opf.try:	push	hl		; the entry, in case it does not
		push	de		;   match, and the operation text
		ld	c,b		; C = characters left to compare
opf.ch:		inc	hl		; HL -> the next character of the
		ld	a,(de)		;   name
		call	strupr
		cp	(hl)
		jr	nz,opf.no
		inc	de
		dec	c
		jr	nz,opf.ch
		inc	hl		; past the last character: the
		ld	a,(hl)		;   class byte
		inc	hl
		ld	c,(hl)		;   and the base opcode
		pop	de
		pop	hl
		or	a		; CY clear = found. No class is 0,
		ret			;   so this cannot set Z either

opf.no:		pop	de
		pop	hl
		jr	opf.next

; --- the operand cursor

; opinit - point the cursor at this line's operand field.
;
; Input:	DE -> the operand text
;		A  = how long it is
; Output:	the cursor is set
; Modifies:	nothing

opinit:		ld	(opptr),de
		ld	(oplen),a
		ret

; opskip - step the cursor over blanks and tabs.
;
; Input:	nothing
; Output:	the cursor is on the first character that is neither, or
;		at the end
; Modifies:	AF, DE

opskip:		push	bc
		ld	de,(opptr)
		ld	a,(oplen)
		ld	b,a
opsk.lp:	ld	a,b
		or	a
		jr	z,opsk.end
		ld	a,(de)
		cp	" "
		jr	z,opsk.st
		cp	CHR_TAB
		jr	nz,opsk.end
opsk.st:	inc	de
		dec	b
		jr	opsk.lp
opsk.end:	ld	(opptr),de
		ld	a,b
		ld	(oplen),a
		pop	bc
		ret

; opnone - the operand field must have nothing left in it.
;
;   insnline calls this after the class handler has taken what it wants,
;   so every class gets the check and none of them can forget it. "nop
;   1" is the error it exists for.
;
; Input:	nothing
; Output:	returns, or erroper stops
; Modifies:	AF, DE

opnone:		call	opskip
		ld	a,(oplen)
		or	a
		ret	z
		jp	erroper

; opend - is anything left in the operand field?
;
;   The cursor is this module's business, so a handler asks rather than
;   reading oplen for itself. cls.ret is the one that needs to know, to
;   tell "ret" from "ret nz".
;
; Input:	nothing
; Output:	Z set = nothing is left
; Modifies:	AF, DE

opend:		call	opskip
		ld	a,(oplen)
		or	a
		ret

; opadv - step the cursor on by A characters.
;
; Input:	A = how many, and never more than is left
; Output:	the cursor has moved. A is unchanged
; Modifies:	F, HL

opadv:		push	bc
		ld	c,a
		ld	b,0
		ld	hl,(opptr)
		add	hl,bc
		ld	(opptr),hl
		ld	hl,oplen
		ld	a,(hl)
		sub	c
		ld	(hl),a
		ld	a,c		; give the caller its count back
		pop	bc
		ret

; opsave, oprest - remember where the cursor is, and put it back.
;
;   One level, and one user: opr8, which has to be able to change its
;   mind. "cp (foo)" must fall through to an expression, because in M80
;   parentheses are grouping and that line means "cp foo".
;
; Modifies:	AF, HL

opsave:		ld	hl,(opptr)
		ld	(opsptr),hl
		ld	a,(oplen)
		ld	(opslen),a
		ret

oprest:		ld	hl,(opsptr)
		ld	(opptr),hl
		ld	a,(opslen)
		ld	(oplen),a
		ret

; opisdl - does this character end an operand word?
;
;   An apostrophe is NOT one of these, so AF' measures three characters
;   and can be told from AF.
;
; Input:	A = a character
; Output:	Z set = yes, it ends a word
; Modifies:	F only

opisdl:		cp	" "
		ret	z
		cp	CHR_TAB
		ret	z
		cp	","
		ret	z
		cp	"("
		ret	z
		cp	")"
		ret	z
		cp	"+"
		ret	z
		cp	"-"
		ret

; opwmeas - how many characters at the cursor could be an operand word.
;
; Input:	nothing
; Output:	A = the count, 0 if the cursor is on a delimiter or at
;		the end
; Modifies:	AF, BC, DE

opwmeas:	ld	de,(opptr)
		ld	a,(oplen)
		ld	b,a
		ld	c,0
opwm.lp:	ld	a,b
		or	a
		jr	z,opwm.end
		ld	a,(de)
		call	opisdl
		jr	z,opwm.end
		inc	de
		inc	c
		dec	b
		jr	opwm.lp
opwm.end:	ld	a,c
		ret

; opword - is the word at the cursor one of this table's?
;
;   regtab and cctab have the same row shape: a length byte, the name in
;   upper case, a kind and a code. Which table to ask is the CALLER's
;   decision, and that is the whole answer to C being a register in one
;   and a condition in the other.
;
;   IX and IY carry their PREFIX in the code column, because it is the
;   only thing that tells them apart anywhere in the instruction set and
;   a fourth column would cost seventeen bytes to say it once.
;
; Input:	HL -> the table
; Output:	CY set   = no such word here, and the cursor has not
;			   moved
;		CY clear = (opkind) and (opcod) are set, (opfix) too for
;			   IX, IY and the four index halves, and the
;			   cursor is past the word
; Modifies:	AF, BC, DE, HL

opword:		ld	(opwtab),hl
		call	opwmeas
		or	a
		scf
		ret	z		; no word here at all
		ld	(opwn),a
		ld	hl,(opwtab)
opw.ent:	ld	a,(hl)
		or	a
		scf
		ret	z		; the end of the table
		ld	c,a
		ld	a,(opwn)
		cp	c
		jr	z,opw.try
opw.next:	ld	a,(hl)		; over length + name + kind + code
		add	a,3
		add	a,l
		ld	l,a
		jr	nc,opw.ent
		inc	h
		jr	opw.ent

opw.try:	push	hl
		ld	de,(opptr)
opw.ch:		inc	hl
		ld	a,(de)
		call	strupr		; the table is upper case, and a
		cp	(hl)		;   register name is recognised in
		jr	nz,opw.no	;   either
		inc	de
		dec	c
		jr	nz,opw.ch
		inc	hl		; past the name: the kind
		ld	a,(hl)
		ld	(opkind),a
		inc	hl
		ld	c,(hl)		; the code - or the prefix
		pop	hl
		cp	OK_IX		; A is still the kind
		jr	nz,opw.half
		ld	a,c		; IX and IY: the code column held
		ld	(opfix),a	;   0DDh or 0FDh, and the pair code
		ld	c,2		;   is HL's
		jr	opw.got

opw.half:	ld	b,0ddh		; an index half: the column held the
		cp	OK_R8IX		;   register code, 4 or 5, and the
		jr	z,opw.hf1	;   KIND says which prefix goes in
		ld	b,0fdh		;   front of it
		cp	OK_R8IY
		jr	nz,opw.got
opw.hf1:	ld	a,b
		ld	(opfix),a
		ld	a,OK_R8X	; ONE kind outside this routine, so
		ld	(opkind),a	;   a handler asks one question
opw.got:	ld	a,c
		ld	(opcod),a
		ld	a,(opwn)
		call	opadv		; over the word
		or	a		; a word is never 0 long, so this
		ret			;   clears CY

opw.no:		pop	hl
		jr	opw.next

; opclose - the ")" that ends an indexed operand.
;
; Output:	CY set = it is not there
; Modifies:	AF, DE, HL

opclose:	call	opskip
		ld	a,(oplen)
		or	a
		scf
		ret	z
		ld	de,(opptr)
		ld	a,(de)
		cp	")"
		scf
		ret	nz
		ld	a,1
		call	opadv
		or	a
		ret

; opdisp - the displacement inside (IX+d), if there is one.
;
;   "+" or "-" and then an expression, which pass 1 steps over without
;   reading. "(ix)" is legal and means a displacement of zero - still a
;   byte in the instruction, so the length does not change.
;
;   Brackets inside it nest, so "(ix+(3*2))" works. A ")" inside a
;   character constant does NOT, which is the same gap opexp has and
;   which LD's quote-aware scanner closes.
;
;   It reports nothing. Whatever goes wrong, opclose finds no ")".
;
; Modifies:	AF, BC, DE, HL

opdisp:		xor	a
		ld	(opdl),a	; none until one is found, and both the
		call	opskip		;   returns below leave it that way
		ld	a,(oplen)
		or	a
		ret	z
		ld	de,(opptr)
		ld	a,(de)
		cp	"+"
		jr	z,opd.go
		cp	"-"
		ret	nz		; the ")", presumably
opd.go:		ld	hl,(opptr)	; WHERE it starts, and that is AT THE
		ld	(opdp),hl	;   SIGN: "(ix-1)" is -1, and an
					;   expression starting at the "1"
					;   is +1
		ld	a,1
		ld	(opdsp),a	; there IS a displacement, which only
		call	opadv		;   JP cares about. A stays 1: over
					;   the sign
		ld	c,0		; C = how deep the brackets are
opd.lp:		ld	a,(oplen)
		or	a
		jr	z,opd.fin
		ld	de,(opptr)
		ld	a,(de)
		call	opisq		; a quoted run is opaque: a ")" in
		jr	nz,opd.nq	;   one does not close the operand
		push	bc		; C is the bracket depth, and
		call	opqrun		;   opqrun wants C for itself
		pop	bc
		jr	opd.lp
opd.nq:		cp	"("
		jr	z,opd.in
		cp	")"
		jr	nz,opd.on
		ld	a,c
		or	a
		jr	z,opd.fin	; the one that closes the operand
		dec	c
		jr	opd.on
opd.in:		inc	c
opd.on:		ld	a,1
		call	opadv
		jr	opd.lp

opd.fin:	ld	hl,(opptr)	; how long it turned out to be, sign
		ld	de,(opdp)	;   included - the sign is part of
		or	a		;   the value, not punctuation
		sbc	hl,de
		ld	a,l
		ld	(opdl),a
		ret

; opisq - is this character a string delimiter?
;
; Input:	A = a character
; Output:	Z set = yes, either sort. A is unchanged
; Modifies:	F only

opisq:		cp	QUOTE1
		ret	z
		cp	QUOTE2
		ret

; opqrun - step the cursor over a quoted run, opening delimiter to
;   closing.
;
;   TWO DELIMITERS TOGETHER ARE ONE CHARACTER of the string and do not
;   close it (M80 2.3.4). Without that, "ld (""a"""),b" would end in the
;   wrong place.
;
;   This is the program's third quote scanner, and deliberately so.
;   splitln (fields.as) walks a raw line to find where a comment starts;
;   dbqstr (tatara.as) walks DE and B over a DB item and counts its
;   characters; this one walks the operand cursor and counts nothing.
;   They share a RULE, not an interface. If a fourth appears, merge all
;   four.
;
; Input:	the cursor is on the opening delimiter
; Output:	the cursor is past the closing one, or at the end of the
;		field if the line ended inside the run
; Modifies:	AF, BC, DE, HL

opqrun:		ld	de,(opptr)
		ld	a,(de)
		ld	c,a		; C = the delimiter that opened it
		ld	a,1
		call	opadv
opq.lp:		ld	a,(oplen)
		or	a
		ret	z		; the line ended inside the run
		ld	de,(opptr)
		ld	a,(de)
		ld	b,a		; opadv keeps BC, so B survives it
		ld	a,1
		call	opadv
		ld	a,b
		cp	c
		jr	nz,opq.lp	; an ordinary character
		ld	a,(oplen)	; a delimiter: doubled, or the end?
		or	a
		ret	z
		ld	de,(opptr)
		ld	a,(de)
		cp	c
		ret	nz		; something else follows: closed
		ld	a,1
		call	opadv		; "" - one character, and on we go
		jr	opq.lp

; opany - what is the operand at the cursor?
;
;   It names anything the Z80 has, and calls whatever it cannot name an
;   expression - so IT ALMOST NEVER FAILS, and the carry flag means only
;   "there is nothing here at all".
;
;   That is what makes "cp (foo)" work. opany answers OK_MEM, opr8 does
;   not want it and puts the cursor back, and cls.alu reads the same
;   text again as an expression. Which of the two (foo) is depends on
;   the INSTRUCTION, and the instruction is the only thing that knows.
;
;   IT WRITES opsave FOR EVERY OPERAND, at the start, for its own
;   backtracking - and opr8 leans on that instead of saving again. The
;   slot is valid from the moment opany returns until the next opany
;   call, and nothing else writes it.
;
; Input:	nothing
; Output:	CY set   = there is nothing here at all
;		CY clear = (opkind), (opcod) and (opfix) describe it
; Modifies:	AF, BC, DE, HL

opany:		xor	a
		ld	(opfix),a
		ld	(opinner),a	; nothing remembered from inside a
		ld	(opdsp),a	;   bracket yet, and no displacement
		call	opskip
		ld	a,(oplen)
		or	a
		scf
		ret	z		; nothing here at all
		call	opsave
		ld	de,(opptr)
		ld	a,(de)
		cp	"("
		jr	z,opa.par
		ld	hl,regtab	; a bare word: whatever regtab says
		call	opword
		ret	nc
		jr	opa.imm

opa.par:	ld	a,1
		call	opadv		; over the "("
		ld	hl,regtab
		call	opword
		jr	c,opa.mem
		ld	a,(opkind)
		cp	OK_RR
		jr	z,opa.prr
		cp	OK_IX
		jr	z,opa.pix
		jr	opsinn		; (af), (i), (c): not a form, and an
					;   expression is the honest answer -
					;   but IN and OUT want to know that
					;   the word in there was "C"

opa.prr:	ld	a,(opcod)
		or	a
		jr	z,opa.pbc	; (BC)
		dec	a
		jr	z,opa.pde	; (DE)
		dec	a
		jr	nz,opsinn	; (SP): an address to everything but
					;   EX, which asks opissp about it
		call	opclose		; (HL) is register code 6
		jr	c,opa.mem
		ld	a,OK_R8
		ld	(opkind),a
		ld	a,6
		jr	opa.got

opa.pbc:	ld	c,OK_MBC
		jr	opa.pm
opa.pde:	ld	c,OK_MDE
opa.pm:		call	opclose		; opclose keeps BC
		jr	c,opa.mem
		ld	a,c
		ld	(opkind),a
		xor	a
		jr	opa.got

opa.pix:	call	opdisp
		call	opclose
		jr	c,opa.mem
		ld	a,OK_IDX
		ld	(opkind),a
		ld	a,6
opa.got:	ld	(opcod),a
		or	a		; or a clears CY whatever A holds
		ret

; opsinn - opany found a word inside the brackets and is about to call
;   the whole thing an address anyway. Keep what regtab said about it.
;
;   This is the whole of the answer to "(C)" and "(SP)". Giving them
;   kinds of their own would have been simpler to read and WRONG: M80
;   assembles "ld a,(c)" as 3A 0005 when C is an equate, so a kind for
;   (C) refuses a line M80 takes. The word is remembered, not
;   reclassified, and the three instructions that care ask.
;
;   Valid from the moment opany returns until the next opany - the same
;   lifetime as opsave's slot, and for the same reason.

opsinn:		ld	a,(opkind)
		ld	(opinner),a
		ld	a,(opcod)
		ld	(opincod),a
		; and on into opa.mem

opa.mem:	call	oprest		; back to the "(", and take the
		call	opexp		;   whole thing as an address
		ret	c
		ld	a,OK_MEM
		jr	opa.kind

opa.imm:	call	opexp		; not a register word: an expression
		ret	c
		ld	a,OK_IMM
opa.kind:	ld	(opkind),a
		xor	a		; no code, and CY cleared with it -
		ld	(opcod),a	;   ld (nn),a touches no flags
		ret

; opisc, opissp - was the operand opany last returned the literal "(C)"
;   or the literal "(SP)"?
;
;   Both come back as OK_MEM, because they are addresses to every
;   instruction but three. IN and OUT want (C); EX wants (SP); nothing
;   else may be allowed to notice, or "ld a,(c)" stops being the
;   absolute load M80 makes of it.
;
; Input:	nothing
; Output:	Z set = yes
; Modifies:	AF

opisc:		ld	a,(opinner)
		cp	OK_R8
		ret	nz
		ld	a,(opincod)
		cp	1		; C is register code 1
		ret

opissp:		ld	a,(opinner)
		cp	OK_RR
		ret	nz
		ld	a,(opincod)
		cp	3		; SP is pair code 3
		ret

; opnodsp - did the indexed operand opany last returned carry NO
;   displacement?
;
;   Only JP asks, and only JP can. Everywhere else the displacement
;   byte is emitted whether the source wrote one or not - "ld a,(ix)"
;   is DD 7E 00, three bytes, exactly like "ld a,(ix+5)". "jp (ix)" is
;   DD E9 and TWO, with nowhere to put one, so "jp (ix+5)" is a form
;   that does not exist rather than a byte to ignore.
;
; Input:	nothing
; Output:	Z set = there was no displacement
; Modifies:	AF

opnodsp:	ld	a,(opdsp)
		or	a
		ret

; opxtext, opdtext - the text opexp and opdisp stepped over.
;
;   A handler parses ALL its operands and only then emits, because the
;   prefix goes out before the opcode and is not known until the
;   operand has been read. By then the cursor is past the expression,
;   so the parser remembers where it was and these two hand it over.
;
;   TWO SLOTS AND NOT AN ARRAY. The most expressions any Z80
;   instruction has is two - "bit 7,(ix+5)" and "ld (ix+0),9" - and in
;   both the second is the displacement, which has a slot of its own
;   because opdisp is what found it. No instruction has two general
;   expressions. DB, DW and DC have as many as you like and need
;   neither slot: dbwalk visits items one at a time and emits each
;   before measuring the next.
;
;   Valid from the moment the handler's parsing is done until the next
;   line - the same lifetime as opsave's slot and opinner's, and they
;   live beside them for that reason.
;
;   Routines and not exported bytes, because a module reaching into
;   another module's data is what the verification rule is about: the
;   answer is a small routine, and here it is two of them.
;
; Input:	nothing
; Output:	DE -> the text, A = how long it is
;		opdtext answers A = 0 when there was no displacement
; Modifies:	AF, DE

opxtext:	ld	de,(opxp)
		ld	a,(opxl)
		ret

opdtext:	ld	de,(opdp)
		ld	a,(opdl)
		ret

; opccm - a condition AND the comma after it.
;
;   The two together, never one at a time: "jp z,foo" is the
;   conditional jump and "jp z" is a jump to a symbol called Z. Only
;   the comma tells them apart, so a condition that is not followed by
;   one is not a condition, and the cursor goes back.
;
;   JP, JR and CALL are the three that ask. RET does not: "ret z" has
;   no comma and no second operand, so cctab alone answers it.
;
; Input:	nothing
; Output:	CY set   = not a condition and a comma, and the cursor
;			   has not moved
;		CY clear = it was, the cursor is past the comma, and
;			   (opcod) is the condition code
; Modifies:	AF, BC, DE, HL

opccm:		call	opsave
		ld	hl,cctab
		call	opword
		ret	c		; not a condition word at all
		call	opcomma
		ret	nc		; a condition and a comma: the
		call	oprest		;   conditional form. Without the
		scf			;   comma it was a symbol that
		ret			;   happens to be named Z, C or M

; opr8 - an 8-bit source: a register, (HL), an indexed operand, or an
;   index half.
;
;   AN INDEX HALF IS NOT SAFE EVERYWHERE THIS ROUTINE IS CALLED. It
;   comes back as OK_R8X with opfix set, so a handler that emits through
;   emitop is right without knowing it exists - and cls.rot, which
;   cannot use emitop, has to refuse it by hand. 104 has the four
;   handlers this routine serves and what each of them does with it.
;
;   (IX+d) IS (HL) with a prefix in front and a byte after. Both answer
;   code 6, which is the whole of the indexed forms - everything else
;   about them is the two extra bytes, and clsxtra adds those.
;
;   A filter on opany, not a parser of its own: on anything else it puts
;   the cursor back to where opany found the operand, so that the caller
;   can read the same text as an expression instead.
;
; Input:	nothing
; Output:	CY set   = not one of those, and the cursor has not moved
;		CY clear = (opkind) is OK_R8 or OK_IDX, (opcod) is the
;			   code, (opfix) the prefix or 0
; Modifies:	AF, BC, DE, HL

opr8:		call	opany
		ret	c		; nothing there at all
		ld	a,(opkind)
		cp	OK_R8
		ret	z
		cp	OK_IDX
		ret	z
		cp	OK_R8X		; an index half is an 8-bit source
		ret	z		;   wherever emitop does the emitting
		call	oprest		; opany's own save still points at
		scf			;   the start of this operand
		ret

; opexp - step over an expression: the rest of the operand field.
;
;   Pass 1 does not READ it. How much room an instruction takes does not
;   depend on what its operand is worth, so the text is skipped here and
;   evaluated when the bytes are emitted.
;
;   It stops at the next comma AT THE TOP LEVEL - one inside a quoted
;   run does not count, so "ld (','),a" reads the way it looks. LD
;   needed that for its first operand, and it is an improvement
;   everywhere else: "cp 1,2" used to size as two quiet bytes and is now
;   an error, because opnone finds the ",2" left over.
;
; Output:	CY set = there was nothing there
; Modifies:	AF, BC, DE, HL

opexp:		call	opskip
		ld	a,(oplen)
		or	a
		scf
		ret	z		; an operand that is not there
		ld	hl,(opptr)	; WHERE it starts. Measuring had to
		ld	(opxp),hl	;   step over it; emitting has to come
					;   back and evaluate it, by which time
					;   the cursor is long past
opx.lp:		ld	a,(oplen)
		or	a
		jr	z,opx.end
		ld	de,(opptr)
		ld	a,(de)
		cp	","
		jr	z,opx.end	; it belongs to the next operand
		call	opisq
		jr	nz,opx.one
		call	opqrun		; a comma inside a quoted run does
		jr	opx.lp		;   not end anything
opx.one:	ld	a,1
		call	opadv
		jr	opx.lp
opx.end:	ld	hl,(opptr)	; and how long it turned out to be
		ld	de,(opxp)
		or	a
		sbc	hl,de
		ld	a,l		; an operand field is 255 at most, so
		ld	(opxl),a	;   L is all of it
		or	a		; CY clear = there was an expression
		ret

; opcomma - step over a comma.
;
; Output:	CY set = there is not one here
; Modifies:	AF, DE, HL

opcomma:	call	opskip
		ld	a,(oplen)
		or	a
		scf
		ret	z
		ld	de,(opptr)
		ld	a,(de)
		cp	","
		scf
		ret	nz
		ld	a,1
		call	opadv
		or	a
		ret

		dseg

opptr:		defs	2	; the operand cursor: where the unread
oplen:		defs	1	;   text starts, and how much is left
opsptr:		defs	2	; opsave's copy of it, for opr8
opslen:		defs	1
opwtab:		defs	2	; opword: which table, across opwmeas
opwn:		defs	1	;   and how long the word is
opkind:		defs	1	; what the last operand turned out to
opcod:		defs	1	;   be, the code it contributes, and
opfix:		defs	1	;   the prefix it forces
opinner:	defs	1	; what regtab said about the word inside
opincod:	defs	1	;   a "(...)" that turned out to be an
				;   address anyway - see opsinn
opdsp:		defs	1	; did the indexed operand carry a
				;   displacement? Only JP asks
opxp:		defs	2	; opexp: where the expression it stepped
opxl:		defs	1	;   over began, and how long it was
opdp:		defs	2	; opdisp: the same for a displacement,
opdl:		defs	1	;   where 0 long means there was none

; The table. A length byte, the name in UPPER CASE, the class, and the
; base opcode. A length byte of 0 ends it.
;
; THE BASE OPCODE IS NOT READ WHILE MEASURING, and every
; handler here returns a length. It is typed now because these rows are
; entered by hand once, and leaving the column out would mean retyping
; all sixty-nine of them when the emitter wants them.
;
; The rows arrive with their handlers, a class at a time. A mnemonic
; that is not
; here yet is not recognised, so its line passes through as text - which
; is what Tatara has always done with a line it does not understand.

optab:		defb	3,	"NOP",	C_NONE,		000h
		defb	4,	"HALT",	C_NONE,		076h
		defb	2,	"DI",	C_NONE,		0f3h
		defb	2,	"EI",	C_NONE,		0fbh
		defb	3,	"EXX",	C_NONE,		0d9h
		defb	3,	"DAA",	C_NONE,		027h
		defb	3,	"CPL",	C_NONE,		02fh
		defb	3,	"SCF",	C_NONE,		037h
		defb	3,	"CCF",	C_NONE,		03fh
		defb	4,	"RLCA",	C_NONE,		007h
		defb	4,	"RRCA",	C_NONE,		00fh
		defb	3,	"RLA",	C_NONE,		017h
		defb	3,	"RRA",	C_NONE,		01fh

		defb	3,	"NEG",	C_NONED,	044h
		defb	4,	"RETI",	C_NONED,	04dh
		defb	4,	"RETN",	C_NONED,	045h
		defb	3,	"RLD",	C_NONED,	06fh
		defb	3,	"RRD",	C_NONED,	067h
		defb	3,	"LDI",	C_NONED,	0a0h
		defb	3,	"LDD",	C_NONED,	0a8h
		defb	4,	"LDIR",	C_NONED,	0b0h
		defb	4,	"LDDR",	C_NONED,	0b8h
		defb	3,	"CPI",	C_NONED,	0a1h
		defb	3,	"CPD",	C_NONED,	0a9h
		defb	4,	"CPIR",	C_NONED,	0b1h
		defb	4,	"CPDR",	C_NONED,	0b9h
		defb	3,	"INI",	C_NONED,	0a2h
		defb	3,	"IND",	C_NONED,	0aah
		defb	4,	"INIR",	C_NONED,	0b2h
		defb	4,	"INDR",	C_NONED,	0bah
		defb	4,	"OUTI",	C_NONED,	0a3h
		defb	4,	"OUTD",	C_NONED,	0abh
		defb	4,	"OTIR",	C_NONED,	0b3h
		defb	4,	"OTDR",	C_NONED,	0bbh

		defb	3,	"ADD",	C_ALUA,		080h
		defb	3,	"ADC",	C_ALUA,		088h
		defb	3,	"SBC",	C_ALUA,		098h
		defb	3,	"SUB",	C_ALU,		090h
		defb	3,	"AND",	C_ALU,		0a0h
		defb	3,	"XOR",	C_ALU,		0a8h
		defb	2,	"OR",	C_ALU,		0b0h
		defb	2,	"CP",	C_ALU,		0b8h

		defb	3,	"INC",	C_INCDEC,	004h
		defb	3,	"DEC",	C_INCDEC,	005h

		defb	4,	"PUSH",	C_STACK,	0c5h
		defb	3,	"POP",	C_STACK,	0c1h
		defb	3,	"RET",	C_RET,		0c9h
		defb	3,	"RST",	C_RST,		0c7h
		defb	2,	"IM",	C_IM,		046h

		defb	2,	"LD",	C_LD,		000h

		defb	3,	"BIT",	C_BIT,		040h
		defb	3,	"RES",	C_BIT,		080h
		defb	3,	"SET",	C_BIT,		0c0h

		defb	3,	"RLC",	C_ROT,		000h
		defb	3,	"RRC",	C_ROT,		008h
		defb	2,	"RL",	C_ROT,		010h
		defb	2,	"RR",	C_ROT,		018h
		defb	3,	"SLA",	C_ROT,		020h
		defb	3,	"SRA",	C_ROT,		028h
		defb	3,	"SLL",	C_ROT,		030h
		defb	3,	"SRL",	C_ROT,		038h

		defb	2,	"JP",	C_JP,		0c3h
		defb	2,	"JR",	C_JR,		018h
		defb	4,	"DJNZ",	C_DJNZ,	010h
		defb	4,	"CALL",	C_CALL,	0cdh

		defb	2,	"EX",	C_EX,		000h
		defb	2,	"IN",	C_IN,		000h
		defb	3,	"OUT",	C_OUT,		000h

		defb	5,	"MULUB",C_MULUB,	0c1h
		defb	5,	"MULUW",C_MULUW,	0c3h

		defb	0		; the end of the table. SIXTY-NINE rows
					;   above it, and measuring is complete

; The operand words, and the conditions, in the same row shape as optab:
; a length byte, the name in UPPER CASE, a kind, and a code.
;
; TWO TABLES, NOT ONE WITH A MASK. C is register code 1 here and
; condition code 3 in cctab, and nothing has to decide which - the
; handler knows what it is asking for, because the grammar it implements
; says so. optable-design.md 7 has the argument.
;
; IX and IY hold their PREFIX in the code column. opword turns that into
; opfix and gives them HL's pair code, 2.
;
; THE FOUR INDEX HALVES ARE THE OTHER WAY ROUND. Their code is 4 or 5 -
; H's and L's, because the prefix is all that tells them apart from H
; and L - so the column holds the CODE and the KIND holds the prefix.
; opword normalises both to OK_R8X. A handler that wants them says so
; once; every handler that does not, and there are eight, refuses them
; by testing OK_R8 as it always did. 104 has the argument.

regtab:		defb	1,	"B",	OK_R8,	0
		defb	1,	"C",	OK_R8,	1
		defb	1,	"D",	OK_R8,	2
		defb	1,	"E",	OK_R8,	3
		defb	1,	"H",	OK_R8,	4
		defb	1,	"L",	OK_R8,	5
		defb	1,	"A",	OK_R8,	7
		defb	2,	"BC",	OK_RR,	0
		defb	2,	"DE",	OK_RR,	1
		defb	2,	"HL",	OK_RR,	2
		defb	2,	"SP",	OK_RR,	3
		defb	2,	"AF",	OK_AF,	3
		defb	3,	"AF'",	OK_AFP,	0
		defb	2,	"IX",	OK_IX,	0ddh
		defb	2,	"IY",	OK_IX,	0fdh
		defb	3,	"IXH",	OK_R8IX,	4
		defb	3,	"IXL",	OK_R8IX,	5
		defb	3,	"IYH",	OK_R8IY,	4
		defb	3,	"IYL",	OK_R8IY,	5
		defb	1,	"I",	OK_I,	0
		defb	1,	"R",	OK_R,	0
		defb	0		; the end of the table

cctab:		defb	2,	"NZ",	OK_CC,	0
		defb	1,	"Z",	OK_CC,	1
		defb	2,	"NC",	OK_CC,	2
		defb	1,	"C",	OK_CC,	3
		defb	2,	"PO",	OK_CC,	4
		defb	2,	"PE",	OK_CC,	5
		defb	1,	"P",	OK_CC,	6
		defb	1,	"M",	OK_CC,	7
		defb	0		; the end of the table
