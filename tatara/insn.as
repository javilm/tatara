; insn.as - the class handlers: what each family of instructions does
; with its operands, and how many bytes it comes to.
;
; MEASURING COMES FIRST. Every handler here returns a length in HL and
; nothing else, because on the Z80 an instruction's length is a function
; of its SYNTAX alone: no operand's value can change it. "ld a,(ix+5)"
; is three bytes and so is "ld a,(ix+later)", whatever later turns out
; to be. That is what lets pass 1 skip every expression it meets, and it
; is the same finding as the one about DB, one level up.
;
; The encodings go into these same handlers, which walk the
; identical path and this time keeps the bytes.

INSNLIB		equ	1		; skips the external in insn.inc

		public	insnline

		include	insn.inc
		include	optab.inc
		include	fields.inc	; FL_OP, FL_OPL, FL_ARG, FL_ARGL
		include	symtab.inc	; locctr, segwr
		include	errs.inc	; erroper, and the four
		include	emit.inc	; emitb, emitop, exsval, emitn

		cseg

; insnline - if this line's operation is an instruction, measure it.
;
;   The driver calls this when the line is neither a directive nor a
;   macro call. A line that is not an instruction either is
;   passed on as text, which is what Tatara has always done with a line
;   it does not recognise: until every class is implemented, "not in the
;   table" does not mean "not an instruction".
;
; Input:	IX -> the line's field block
; Output:	CY set   = not an instruction, and nothing has changed
;		CY clear = locctr has been moved
; Modifies:	AF, BC, DE, HL
;
;   The fields arrive through IX rather than as a global, because the
;   driver exports nothing and this module has no business knowing the
;   name of its buffer. It is splitln's own convention, and macros.as
;   passes mdflds the same way.

insnline:	ld	a,(ix+FL_OPL)
		or	a
		scf
		ret	z		; no operation on this line at all
		ld	b,a
		ld	e,(ix+FL_OP)
		ld	d,(ix+FL_OP+1)
		call	opfind		; CY set = no such mnemonic
		ret	c
		ld	(inscls),a
		ld	a,c
		ld	(insbase),a	; not read while measuring, except
					;   by C_ALUA

		call	segwr		; a transient DSEG with no group
					;   open cannot be placed in

		ld	e,(ix+FL_ARG)
		ld	d,(ix+FL_ARG+1)
		ld	a,(ix+FL_ARGL)
		call	opinit
		call	opskip

		ld	a,(inscls)	; the handler, through clstab.
		dec	a		;   Classes are 1-based, and each
		add	a,a		;   entry is a word
		ld	e,a
		ld	d,0
		ld	hl,clstab
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		call	insngo		; the handler emits; the emitter
					;   counts

		call	opnone		; nothing may be left over

; THE LENGTH IS WHAT THE EMITTER COUNTED. There is no second
; statement of it to disagree with: a handler cannot claim three bytes
; and emit four when it no longer claims anything. the cross-check
; and the ld hl,n in every handler went out together, and this note is
; not leaving a check unperformed - it removes the state the check was
; looking for.
;
; ONE HALF OF IT SURVIVES. No Z80 instruction is zero bytes long, so a
; handler that returned without emitting would advance locctr by
; nothing and put every address below it out, in a file that assembled
; without a word. Nothing can reach that today; the mnemonic somebody
; adds in a year with a handler that forgets its emitb can, and that is
; exactly when nobody will be looking. Six bytes say so. It is the
; argument that kept cls.soon.

		ld	hl,(emitn)
		ld	a,h
		or	l
		jp	z,errbytes	; a handler that emitted nothing
		ld	de,(locctr)
		add	hl,de
		ld	(locctr),hl
		or	a		; CY clear = it was an instruction
		ret

insngo:		jp	(hl)		; the call above is what returns
					;   here

; --- C_NONE: no operands, one byte. NOP, HALT, DI, EI, EXX, DAA, CPL,
;     SCF, CCF and the four accumulator rotates.

cls.none:	ld	a,(insbase)
		call	emitb
		ret

; --- C_NONED: no operands, and an ED in front of the opcode. NEG, RETI,
;     RETN, RLD, RRD, and the twelve block instructions.

cls.noned:	ld	a,0edh
		call	emitb
		ld	a,(insbase)
		call	emitb
		ret

; --- C_ALU: SUB, AND, XOR, OR and CP. One 8-bit source, or an
;     immediate byte. M80 takes ONE operand for these - "sub a,b" is not
;     its spelling - and so does Tatara: accepting the two-operand form
;     would let source through that M80 refuses, which is the wrong
;     direction to be incompatible in.

cls.alu:	call	opr8		; a register, (HL) or indexed?
		jr	c,cls.alui
		ld	a,(opcod)	; base + the register's code, in the
		ld	hl,insbase	;   ordinary shape: prefix first,
		add	a,(hl)		;   displacement last
		call	emitop
		ret
cls.alui:	call	opexp		; no: then it is an immediate
		jp	c,erroper	; "cp" with nothing after it
		ld	a,(insbase)
		add	a,046h		; every ALU family's immediate form is
		call	emitb		;   its base plus 46h
		call	emitxs
		ret

; --- C_ALUA: ADD, ADC and SBC. The 8-bit form names the accumulator
;     first; the 16-bit ones take HL, or an index register for ADD only.

cls.alua:	ld	hl,regtab
		call	opword
		jp	c,erroper	; it must say what it adds to
		ld	a,(opkind)
		cp	OK_R8
		jr	z,cls.alu8
		cp	OK_RR
		jr	z,cls.al16
		cp	OK_IX
		jr	z,cls.alix
		jp	erroper

cls.alu8:	ld	a,(opcod)	; only the accumulator: "add b,c"
		cp	7		;   is not a form
		jp	nz,erroper
		call	opcomma
		jp	c,erroper
		jp	cls.alu		; and the rest is exactly C_ALU

cls.al16:	ld	a,(opcod)	; only HL: "add de,hl" is not a form
		cp	2
		jp	nz,erroper
		call	opcomma
		jp	c,erroper
		ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_RR		; "add hl,ix" does not exist
		jp	nz,erroper
		ld	a,(opcod)	; the pair code, times sixteen
		rlca
		rlca
		rlca
		rlca			; 3 is the largest, so nothing
		ld	c,a		;   leaves the byte
		ld	a,(insbase)	; THE ONE PLACE MEASURING READ THE
		cp	080h		;   BASE OPCODE, and emitting reads it
		jr	z,cls.al16a	;   for the same reason: ADD HL,rr is
		ld	a,0edh		;   one byte and ADC and SBC are ED-
		call	emitb		;   prefixed and two, and nothing in
		ld	a,(insbase)	;   the operands says which
		cp	088h
		ld	a,04ah		; ADC HL,rr = ED 4Ah + 16p
		jr	z,cls.al16b
		ld	a,042h		; SBC HL,rr = ED 42h + 16p
cls.al16b:	add	a,c
		call	emitb
		ret
cls.al16a:	ld	a,009h		; ADD HL,rr = 09h + 16p
		add	a,c
		call	emitb
		ret

cls.alix:	ld	a,(insbase)
		cp	080h
		jp	nz,erroper	; ADC and SBC have no index form
		ld	a,(opfix)
		ld	(insfix),a	; which index register it was
		call	opcomma
		jp	c,erroper
		ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_IX
		jr	z,cls.alix2
		cp	OK_RR
		jp	nz,erroper
		ld	a,(opcod)
		cp	2		; "add ix,hl" does not exist
		jp	z,erroper
		jr	cls.alixe
cls.alix2:	ld	a,(opfix)	; "add ix,ix" is a form and "add
		ld	hl,insfix	;   ix,iy" is not, and the prefix
		cp	(hl)		;   byte is the only difference
		jp	nz,erroper
cls.alixe:	ld	a,(insfix)	; the prefix the FIRST operand set -
		call	emitb		;   opword overwrote opfix with the
		ld	a,(opcod)	;   second one. And opword gives an
		rlca			;   index register pair code 2, so
		rlca			;   "add ix,ix" needs no special case:
		rlca			;   DD 29 falls out
		rlca
		add	a,009h
		call	emitb
		ret

; --- C_LD: the whole of LD. Eighteen operand forms and four lengths,
;     and NOT eighteen instructions: both operands are parsed first, and
;     then the instruction is a decision on the two KINDS together.
;
;     Written operand by operand this sprawls, and the temptation is to
;     give LD a little table of its own - at which point the class
;     design is carrying its overhead for nothing. optable-design.md 11
;     names this as the place the design is under pressure, and 16 has
;     the full table of forms.
;
;     The lengths are all in ld.one to ld.four, reached with jp rather
;     than jr: the chain is far longer than 127 bytes and an out-of-
;     range jr is emitted with the low byte of the displacement and no
;     link error (the evening).

cls.ld:		call	opany		; the destination
		jp	c,erroper
		ld	a,(opkind)
		ld	(lddst),a
		ld	a,(opcod)
		ld	(lddcod),a
		ld	a,(opfix)	; THE BYTE THAT USED TO BE LOST: the
		ld	(lddfix),a	;   source's opany clears opfix
		call	opcomma
		jp	c,erroper
		call	opany		; the source
		jp	c,erroper

		ld	a,(lddst)
		cp	OK_R8
		jp	z,ld.r8
		cp	OK_IDX
		jp	z,ld.idx
		cp	OK_RR
		jp	z,ld.rr
		cp	OK_IX
		jp	z,ld.ix
		cp	OK_MBC
		jp	z,ld.mrr
		cp	OK_MDE
		jp	z,ld.mrr
		cp	OK_MEM
		jp	z,ld.mem
		cp	OK_I
		jp	z,ld.ir
		cp	OK_R
		jp	z,ld.ir
		jp	erroper

; --- the three routines the branches below share. ld.emit is emitop
;     with the DESTINATION's prefix and kind, for the four forms whose
;     prefix the source's opany has already cleared out of opfix; ld.x8
;     and ld.x16 are the two shapes an operand code takes inside an
;     opcode.

ld.emit:	ld	c,a		; the opcode, across the prefix
		ld	a,(lddfix)
		or	a
		call	nz,emitb	; DD or FD, if the DESTINATION
		ld	a,c		;   forced one
		call	emitb
		ld	a,(lddst)	; ITS kind, not opkind: opdl is
		cp	OK_IDX		;   not cleared per operand, and a
		ret	nz		;   stale one would go out
		jp	emitd		; and "(ix)" is "(ix+0)"

ld.x8:		rlca			; base in C, code in A: base plus
		rlca			;   EIGHT times the code. 7 is the
		rlca			;   largest, so nothing leaves the
		add	a,c		;   byte
		ret			; NOT LD's any more, whatever the
					;   name says: it went to JP,
					;   CALL, BIT and IN as well, and
					;   renaming eight call sites in
					;   code this new buys a better
					;   name at the price of churn

ld.x16:		rlca			; the same, sixteen times: a pair
		rlca			;   code, and 3 is the largest
		rlca
		rlca
		add	a,c
		ret

; --- the destination is an 8-bit register or (HL): code 6 is (HL), and
;     the two are the same thing everywhere but here.

ld.r8:		ld	a,(opkind)
		cp	OK_R8
		jr	z,ld.r8r
		cp	OK_IDX
		jr	z,ld.r8x
		cp	OK_IMM
		jp	z,ld.r8n	; "ld r,n" and "ld (hl),n"
		ld	a,(lddcod)	; everything below is the
		cp	7		;   accumulator's alone
		jp	nz,erroper
		ld	a,(opkind)
		cp	OK_MBC
		jp	z,ld.abc	; "ld a,(bc)"
		cp	OK_MDE
		jp	z,ld.ade	; "ld a,(de)"
		cp	OK_MEM
		jp	z,ld.ann	; "ld a,(nn)"
		cp	OK_I
		jp	z,ld.air	; "ld a,i"
		cp	OK_R
		jp	z,ld.air	; "ld a,r"
		jp	erroper

ld.r8r:		ld	a,(lddcod)	; both (HL)? That encoding is
		cp	6		;   HALT, so LD has to refuse it
		jr	nz,ld.r8r1
		ld	a,(opcod)
		cp	6
		jp	z,erroper
ld.r8r1:	ld	c,040h		; 40h + 8*dst + src
		ld	a,(lddcod)
		call	ld.x8
		ld	c,a
		ld	a,(opcod)
		add	a,c
		call	emitb
		ret

ld.r8x:		ld	a,(lddcod)	; "ld (hl),(ix+d)": no instruction
		cp	6		;   reads two memory operands, and
		jp	z,erroper	;   the prefix would have nowhere
		ld	c,046h		;   to point
		ld	a,(lddcod)
		call	ld.x8
		call	emitop		; THE SOURCE is the indexed one
		ret			;   here, so opfix is current

ld.r8n:		ld	c,006h		; 06h + 8*dst, and no prefix can
		ld	a,(lddcod)	;   reach this form
		call	ld.x8
		call	emitb
		call	emitxs
		ret

ld.abc:		ld	a,00ah		; "ld a,(bc)"
		call	emitb
		ret

ld.ade:		ld	a,01ah		; "ld a,(de)"
		call	emitb
		ret

ld.ann:		ld	a,03ah		; "ld a,(nn)"
		call	emitb
		call	emitxws
		ret

ld.air:		ld	a,0edh		; "ld a,i" is ED 57h and "ld a,r"
		call	emitb		;   is ED 5Fh: regtab gives I and
		ld	c,057h		;   R the same code 0, and only
		ld	a,(opkind)	;   the KIND tells them apart
		sub	OK_I
		call	ld.x8
		call	emitb
		ret

; --- the destination is (IX+d) or (IY+d)

ld.idx:		ld	a,(opkind)
		cp	OK_IMM
		jr	z,ld.idxn	; "ld (ix+d),n"
		cp	OK_R8
		jp	nz,erroper	; OK_IDX is one of these, so
		ld	a,(opcod)	;   "ld (ix+d),(iy+d)" never gets
		cp	6		;   as far as a prefix. This is
		jp	z,erroper	;   "ld (ix+d),(hl)", from the
		ld	c,070h		;   other direction
		add	a,c		; 70h + src, A being still the
		call	ld.emit		;   source's code
		ret

ld.idxn:	ld	a,036h		; THE ONE FORM THAT EMITS FROM
		call	ld.emit		;   BOTH OPERANDS: the displace-
		call	emitxs		;   ment goes out inside ld.emit,
		ret			;   the immediate after it

; --- the destination is BC, DE, HL or SP

ld.rr:		ld	a,(opkind)
		cp	OK_IMM
		jr	z,ld.rrn	; "ld rr,nn"
		cp	OK_MEM
		jr	z,ld.rrm
		cp	OK_RR
		jr	z,ld.sphl
		cp	OK_IX
		jr	z,ld.spix
		jp	erroper

ld.rrn:		ld	c,001h		; 01h + 16p
		ld	a,(lddcod)
		call	ld.x16
		call	emitb
		call	emitxws
		ret

ld.rrm:		ld	a,(lddcod)	; "ld hl,(nn)" is 2Ah and THREE
		cp	2		;   bytes; every other pair is
		jr	nz,ld.rrm2	;   ED 4Bh+16p and four. Choosing
		ld	a,02ah		;   wrongly is a WRONG LENGTH
		call	emitb		;   here, not a wasted byte
		call	emitxws
		ret

ld.rrm2:	ld	a,0edh
		call	emitb
		ld	c,04bh
		ld	a,(lddcod)
		call	ld.x16
		call	emitb
		call	emitxws
		ret

ld.sphl:	ld	a,(lddcod)	; "ld sp,hl" is the only pair-to-
		cp	3		;   pair move there is
		jp	nz,erroper
		ld	a,(opcod)
		cp	2
		jp	nz,erroper
		ld	a,0f9h
		call	emitb
		ret

ld.spix:	ld	a,(lddcod)	; "ld sp,ix"
		cp	3
		jp	nz,erroper
		ld	a,0f9h
		call	emitop		; THE SOURCE holds the prefix,
		ret			;   and OK_IX carries no
					;   displacement

; --- the destination is IX or IY

ld.ix:		ld	a,(opkind)
		cp	OK_IMM
		jr	z,ld.ixn	; "ld ix,nn"
		cp	OK_MEM
		jr	z,ld.ixm	; "ld ix,(nn)"
		jp	erroper

ld.ixn:		ld	a,021h		; THE DESTINATION holds the
		call	ld.emit		;   prefix in both of these, and
		call	emitxws		;   carries no displacement
		ret

ld.ixm:		ld	a,02ah
		call	ld.emit
		call	emitxws
		ret

; --- the destination is (BC) or (DE): the accumulator goes there and
;     nothing else does

ld.mrr:		ld	a,(opkind)
		cp	OK_R8
		jp	nz,erroper
		ld	a,(opcod)
		cp	7
		jp	nz,erroper
		ld	a,(lddst)	; 02h for (BC), 12h for (DE), and
		cp	OK_MBC		;   the kind is the only thing
		ld	a,002h		;   that says which: both carry
		jr	z,ld.mrr1	;   code 0
		ld	a,012h
ld.mrr1:	call	emitb
		ret

; --- the destination is an address

ld.mem:		ld	a,(opkind)	; the ADDRESS is the
		cp	OK_R8		;   destination's, and opxp still
		jr	z,ld.mema	;   holds it: every source here is
		cp	OK_RR		;   a bare register word, so opexp
		jr	z,ld.memr	;   never ran a second time
		cp	OK_IX
		jr	z,ld.memx	; "ld (nn),ix"
		jp	erroper

ld.mema:	ld	a,(opcod)	; "ld (nn),a", and no other
		cp	7		;   register
		jp	nz,erroper
		ld	a,032h
		call	emitb
		call	emitxws
		ret

ld.memr:	ld	a,(opcod)	; "ld (nn),hl" is 22h and three;
		cp	2		;   the rest are ED 43h+16p and
		jr	nz,ld.memr2	;   four
		ld	a,022h
		call	emitb
		call	emitxws
		ret

ld.memr2:	ld	a,0edh
		call	emitb
		ld	c,043h
		ld	a,(opcod)	; the SOURCE's pair code here
		call	ld.x16
		call	emitb
		call	emitxws
		ret

ld.memx:	ld	a,022h
		call	emitop		; THE SOURCE holds the prefix
		call	emitxws
		ret

; --- the destination is I or R

ld.ir:		ld	a,(opkind)
		cp	OK_R8
		jp	nz,erroper
		ld	a,(opcod)
		cp	7
		jp	nz,erroper
		ld	a,0edh		; "ld i,a" is ED 47h and "ld r,a"
		call	emitb		;   is ED 4Fh - the same code 0,
		ld	c,047h		;   and the kind again
		ld	a,(lddst)
		sub	OK_I
		call	ld.x8
		call	emitb
		ret

; --- C_INCDEC: INC and DEC, in both widths.

cls.incd:	call	opr8
		jr	c,cls.inc16
		ld	a,(opcod)	; base + EIGHT times the code: INC is
		rlca			;   04h+8r and DEC is 05h+8r, and the
		rlca			;   row's base byte is the 04h or the
		rlca			;   05h
		ld	hl,insbase
		add	a,(hl)
		call	emitop
		ret
cls.inc16:	ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_IX
		jr	z,cls.inc2
		cp	OK_RR		; not AF, not I, not R
		jp	nz,erroper
		call	cls.incw	; 03h or 0Bh, plus sixteen times
					;   the pair code
		ret
cls.inc2:	ld	a,(opfix)	; DD or FD, then 23h or 2Bh - which
		call	emitb		;   is the pair form with HL's code
		call	cls.incw
		ret

; cls.incw - the sixteen-bit opcode: 03h for INC and 0Bh for DEC, plus
;   sixteen times the pair code. WHICH ONE comes from bit 0 of the
;   row's base byte - INC's is 04h and DEC's is 05h - which is one
;   rrca instead of a third byte in every row of the table.
;
; Input:	(opcod) = the pair code, (insbase) = 04h or 05h
; Output:	one byte emitted
; Modifies:	AF, BC, HL

cls.incw:	ld	a,(opcod)
		rlca
		rlca
		rlca
		rlca
		ld	c,a
		ld	a,(insbase)
		rrca			; bit 0 into carry: INC 04h -> clear,
		ld	a,003h		;   DEC 05h -> set
		jr	nc,cls.incw1
		ld	a,00bh
cls.incw1:	add	a,c
		jp	emitb

; --- C_STACK: PUSH and POP. The stack set is BC, DE, HL and AF: SP is
;     not in it and AF takes its place, which is why regtab gives them
;     different KINDS and the same code.

cls.stk:	ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_AF
		jr	z,cls.stk1
		cp	OK_IX
		jr	z,cls.stk2
		cp	OK_RR
		jp	nz,erroper
		ld	a,(opcod)
		cp	3		; "push sp" does not exist
		jp	z,erroper
cls.stk1:	call	cls.stkb	; base + sixteen times the code. AF
					;   and SP share code 3 and differ in
		ret			;   KIND, which is the doing
cls.stk2:	ld	a,(opfix)	; DD or FD, then the same byte with
		call	emitb		;   HL's code - opword gives an index
		call	cls.stkb	;   register pair code 2
		ret

cls.stkb:	ld	a,(opcod)
		rlca
		rlca
		rlca
		rlca
		ld	c,a
		ld	a,(insbase)
		add	a,c
		jp	emitb

; --- C_RET: one byte with a condition or without one.

cls.ret:	call	opend		; nothing left is "ret" on its own
		jr	z,cls.retp
		ld	hl,cctab
		call	opword
		jp	c,erroper
		ld	a,(opcod)	; C0h + eight times the condition
		rlca
		rlca
		rlca
		add	a,0c0h
		jr	cls.ret1
cls.retp:	ld	a,(insbase)	; plain RET: the row carries 0C9h
cls.ret1:	call	emitb
		ret

; --- C_RST and C_IM: one expression each, and the length does not
;     depend on what it says. Whether RST's operand is a multiple of
;     eight below 40h, and whether IM's is 0, 1 or 2, are questions pass
;     1 cannot answer for a forward reference - so pass 2 answers them
;     for every case rather than for some.

cls.rst:	call	opexp
		jp	c,erroper
		call	exsval		; 0 on pass 1, which is "rst 0" and
		ld	a,h		;   passes every test below
		or	a
		jp	nz,errrst	; above 00FFh, let alone 38h
		ld	a,l
		cp	040h
		jp	nc,errrst	; 40h and up
		and	007h
		jp	nz,errrst	; not a multiple of eight
		ld	a,l
		ld	hl,insbase	; the operand IS the opcode: 0C7h + n
		add	a,(hl)
		call	emitb
		ret

; --- C_DJNZ is C_IM's body under a second name. One expression, always
;     two bytes, and the length does not depend on what the expression
;     says: DJNZ's displacement is "loop - ($ + 2)", a subtraction pass
;     2 does and pass 1 never needs.

; DJNZ STOPS SHARING THIS BODY. It was given a second label here
; because both were "one expression, always two bytes" - but IM is
; ED 46h/56h/5Eh and DJNZ is 10h and a displacement from $. They
; agreed about the LENGTH and about nothing else, and the sharing was
; a coincidence of the measuring phase rather than a shared idea.
; C_DJNZ arrives later, so it keeps a measuring-only body until then.

cls.djnz:	call	opexp
		jp	c,erroper
		ld	a,(insbase)	; 10h, and then the same distance
		call	emitb		;   JR measures - which is the whole
		call	emitjr		;   of what these two had
					;   in common and IM never did
		ret

cls.im:		call	opexp
		jp	c,erroper
		call	exsval		; 0 on pass 1, which is "im 0"
		ld	a,h
		or	a
		jp	nz,errim
		ld	a,0edh
		call	emitb
		ld	a,l		; 0, 1 and 2 encode as 46h, 56h and
		or	a		;   5Eh, which is not an arithmetic
		ld	a,046h		;   progression - so three bytes in
		jr	z,cls.im1	; the handler carries all three,
		dec	l		;   and the table carries none
		ld	a,056h
		jr	z,cls.im1
		dec	l
		ld	a,05eh
		jp	nz,errim
cls.im1:	call	emitb
		ret

; --- C_JP: three bytes to an address, with a condition or without one;
;     ONE byte to (HL); TWO to (IX) or (IY).
;
;     JP is the one instruction whose indexed form has no displacement
;     byte. Everywhere else "(ix)" and "(ix+5)" are the same length -
;     "ld a,(ix)" is DD 7E 00 - so opdisp's answer is thrown away. Here
;     it is the difference between a form and a typo, which is why
;     opnodsp exists and why clsxtra is NOT used below.

cls.jp:		call	opccm		; "jp cc,nn"?
		jr	c,cls.jp1	; no - it may still be (hl) or (ix)
		ld	c,0c2h		; C2h + 8*cc. The LITERAL is the
		ld	a,(opcod)	;   honest one: the table's base is
		call	ld.x8		;   C3h, which is the UNconditional
		ld	(inscod),a	;   form. And it goes to memory
		call	opexp		;   because opexp modifies BC
		jp	c,erroper
		ld	a,(inscod)
		call	emitb
		call	emitxws
		ret

cls.jp1:	call	opr8		; "jp (hl)", "jp (ix)"?
		jr	c,cls.jp3
		ld	a,(opcod)
		cp	6		; any other register code means a
		jr	nz,cls.jp2	;   SYMBOL named B, C, D...
		call	opnodsp
		jp	nz,erroper	; "jp (ix+5)": DD E9 has nowhere to
		ld	a,(opfix)	; the prefix if there is one, then
		or	a		;   E9h. "jp (ix)" is DD E9 and the
		call	nz,emitb	;   emitter has been counting the
		ld	a,0e9h		;   prefix all along
		call	emitb
		ret

cls.jp2:	call	oprest		; opany's save still points at the
					;   start of this operand
cls.jp3:	call	opexp
		jp	c,erroper	; "jp" with nothing after it
		ld	a,(insbase)	; C3h, straight from the table
		call	emitb
		call	emitxws
		ret

; --- C_JR: two bytes, and only four of the eight conditions.

cls.jr:		call	opccm
		jr	c,cls.jr1
		ld	a,(opcod)	; JR has NZ, Z, NC and C and stops
		cp	4		;   there: "jr po,x" is not an
		jp	nc,erroper	;   instruction on any Z80
		ld	c,020h		; 20h + 8*cc is 20h, 28h, 30h and
		call	ld.x8		;   38h, and there is no 40h
		ld	(inscod),a
		call	opexp
		jp	c,erroper
		ld	a,(inscod)
		call	emitb
		jr	cls.jr2
cls.jr1:	call	opexp
		jp	c,erroper
		ld	a,(insbase)	; 18h, straight from the table
		call	emitb
cls.jr2:	call	emitjr		; NOT emitxw: the byte is a distance
					;   from the address after this
		ret			;   instruction, not an address

; --- C_CALL: three bytes either way, so opccm's answer does not change
;     the length - only where the cursor ends up.

cls.call:	call	opccm
		jr	c,cls.cal1
		ld	c,0c4h		; C4h + 8*cc; the table's CDh is
		ld	a,(opcod)	;   the unconditional form
		call	ld.x8
		ld	(inscod),a
		call	opexp
		jp	c,erroper
		ld	a,(inscod)
		jr	cls.cal2
cls.cal1:	call	opexp
		jp	c,erroper
		ld	a,(insbase)	; CDh
cls.cal2:	call	emitb
		call	emitxws
		ret

; --- C_BIT and C_ROT: ten mnemonics and one body. "bit b,s" is "rlc s"
;     with a number and a comma in front of it, so C_BIT reads those
;     two and FALLS THROUGH.

cls.bit:	call	opexp		; the bit number. PASS 1 DOES NOT
		jp	c,erroper	;   READ IT: bit 0 and bit 7 are the
		call	opcomma		;   same length, so "bit n,b" with n
		jp	c,erroper	;   defined below still measures
		call	exsval		; its VALUE, and 0 on pass 1 - so
		ld	a,h		;   the range check is pass 2's, as
		or	a		;   RST's and IM's have been since
		jp	nz,errbit	;   and for the same reason
		ld	a,l
		cp	8
		jp	nc,errbit
		rlca			; eight times it, and into the base:
		rlca			;   "bit 7,b" is CB 78h, which is
		rlca			;   40h + 56 + 0
		ld	hl,insbase
		add	a,(hl)
		ld	(hl),a
					; and on into cls.rot

cls.rot:	call	opr8
		jp	c,erroper
		ld	a,(opfix)	; DD CB d op - THE ONE ENCODING IN
		or	a		;   THE INSTRUCTION SET whose
		call	nz,emitb	;   displacement comes BEFORE its
		ld	a,0cbh		;   opcode. emitop puts them the
		call	emitb		;   other way round and cannot serve
		ld	a,(opkind)	;   it, so the four bytes are
		cp	OK_IDX		;   written out here, next to the
		call	z,emitd		;   comment that says why
		ld	a,(opcod)
		ld	hl,insbase
		add	a,(hl)
		call	emitb
		ret

; --- C_EX: three forms, and (SP) is an address that EX alone looks
;     inside. Every jump below is a jp: the block is longer than a jr
;     reaches and an out-of-range one is emitted with the low byte of
;     the displacement and no link error (the evening).

cls.ex:		call	opany
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_RR
		jp	z,ex.de
		cp	OK_AF
		jp	z,ex.af
		cp	OK_MEM
		jp	nz,erroper
		call	opissp		; an address, and only "(sp)" of all
		jp	nz,erroper	;   the addresses there are
		call	opcomma
		jp	c,erroper
		ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_IX
		jp	z,ex.spx	; "ex (sp),ix" is DD E3
		cp	OK_RR
		jp	nz,erroper
		ld	a,(opcod)
		cp	2		; "ex (sp),bc" does not exist
		jp	nz,erroper
		ld	a,0e3h		; opany cleared opfix and opword
		call	emitop		;   only sets it for IX and IY, so
		ret			;   this is E3h alone

ex.spx:		ld	a,0e3h		; and the same call is DD E3 here,
		call	emitop		;   the prefix having come from the
		ret			;   SECOND operand - so opfix is the
					;   current one and the ld.emit is
					;   not wanted

ex.de:		ld	a,(opcod)	; "ex de,hl" and no other pair -
		cp	1		;   and not "ex hl,de" either, which
		jp	nz,erroper	;   is not M80's spelling
		call	opcomma
		jp	c,erroper
		ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_RR
		jp	nz,erroper
		ld	a,(opcod)
		cp	2
		jp	nz,erroper
		ld	a,0ebh		; EBh, and measuring could not tell
		call	emitb		;   it from 08h or E3h: all three
		ret			;   are one byte

ex.af:		call	opcomma		; "ex af,af'". The apostrophe gets
		jp	c,erroper	;   this far only because of the
		ld	hl,regtab	;   splitln fix: without it the
		call	opword		;   operand field swallows the rest
		jp	c,erroper	;   of the line, comment and all
		ld	a,(opkind)
		cp	OK_AFP
		jp	nz,erroper
		ld	a,008h
		call	emitb
		ret

; --- C_IN and C_OUT: one instruction written backwards. Both are two
;     bytes; in both, the PORT decides which register is allowed. The
;     only difference is which operand comes first, so they share
;     opport and inout and differ in nine lines.

cls.in:		ld	hl,regtab	; the register comes first here
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_R8
		jp	nz,erroper
		ld	a,(opcod)
		ld	(inscod),a	; opany clobbers every register
		call	opcomma
		jp	c,erroper
		call	opport
		ld	a,(inscod)
		ld	b,0dbh		; "in a,(n)" is DB n
		ld	c,040h		; "in r,(c)" is ED 40h + 8*r
		jp	inout

cls.out:	call	opport		; and the port comes first here
		call	opcomma
		jp	c,erroper
		ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_R8
		jp	nz,erroper
		ld	a,(opcod)	; no need to keep it: nothing runs
		ld	b,0d3h		;   between here and inout
		ld	c,041h		; "out (n),a" is D3 n, "out (c),r"
		jp	inout		;   is ED 41h + 8*r

; opport - the port half of an IN or an OUT: "(C)" or "(n)", and
;   nothing else.
;
;   Both are OK_MEM, because both are addresses to every other
;   instruction. What was inside the brackets is REMEMBERED rather than
;   reclassified, and it survives until the next opany - which is what
;   lets cls.out ask about its first operand after parsing its second.
;
;   It also leaves the port EXPRESSION remembered, in opxp, for the
;   "(n)" form to emit. cls.out parses its register with opword, which
;   never calls opexp, so the port text is still there when inout wants
;   it - the same two-slot trick as "ld (ix+d),n".
;
; Input:	nothing
; Output:	nothing, or it does not return
; Modifies:	AF, BC, DE, HL

opport:		call	opany
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_MEM
		jp	nz,erroper
		ret

; inout - the half IN and OUT share.
;
;   (C) takes any of the eight registers; (n) takes the accumulator and
;   no other. "in b,(0aah)" is two legal operands and no instruction,
;   which is the same kind of refusal as "ld (bc),hl".
;
;   emitb modifies NOTHING, flags included, which is what lets B, C and
;   D hold the three things this routine needs across two of them.
;
; Input:	A = the register's code
;		B = the "(n)" form's opcode
;		C = the "(C)" form's base
;		the last opany was the port
; Output:	HL = 2
; Modifies:	AF, BC, DE, HL

inout:		ld	d,a		; the register's code, out of A's way
		call	opisc		; was the port the literal "(C)"?
		jr	z,inout1	; then any register goes
		ld	a,d
		cp	7
		jp	nz,erroper
		ld	a,b		; DBh or D3h, and the port is an
		call	emitb		;   ordinary byte-wide expression
		call	emitxs
		ret

inout1:		ld	a,0edh
		call	emitb
		ld	a,d
		call	ld.x8		; base + 8*r, C still holding the
		call	emitb		;   base emitb did not disturb
		ret

; --- C_MULUB and C_MULUW: the R800's two. Tatara assembles them on any
;     machine - what the source says does not depend on what the
;     assembler is running on - and they are the only two mnemonics in
;     the program with no oracle, because M80 does not know them.

cls.mlub:	ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_R8
		jp	nz,erroper
		ld	a,(opcod)
		cp	7		; the accumulator and no other
		jp	nz,erroper
		call	opcomma
		jp	c,erroper
		ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_R8		; any 8-bit register. (HL) cannot
		jp	nz,erroper	;   arrive here at all: regtab has no
					;   entry for it, and only opany's
					;   bracket branch ever makes one
		ld	a,0edh
		call	emitb
		ld	a,(opcod)	; ED C1h + eight times the register
		rlca
		rlca
		rlca
		ld	hl,insbase
		add	a,(hl)
		call	emitb
		ret

cls.mluw:	ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_RR
		jp	nz,erroper
		ld	a,(opcod)
		cp	2		; HL is the only destination
		jp	nz,erroper
		call	opcomma
		jp	c,erroper
		ld	hl,regtab
		call	opword
		jp	c,erroper
		ld	a,(opkind)
		cp	OK_RR
		jp	nz,erroper
		ld	a,(opcod)
		or	a
		ld	a,(insbase)	; MULUW HL,BC is ED C3 - the row's
		jr	z,mluw2		;   base
		ld	a,(opcod)
		cp	3		; MULUW HL,SP is ED F3, and there
		jp	nz,erroper	;   is no third form
		ld	a,0f3h
mluw2:		ld	c,a
		ld	a,0edh
		call	emitb
		ld	a,c
		call	emitb
		ret

; --- every class has a handler now, so nothing in clstab points here.
;     It stays: a mistyped class byte in a future row would otherwise
;     jump to whatever the jump table happened to hold, and finding
;     THAT would cost an evening. It is the cheapest insurance in the
;     program - three bytes.

cls.soon:	jp	erroper

		dseg

inscls:		defs	1	; what opfind answered: the class,
insbase:	defs	1	;   and the base opcode
insfix:		defs	1	; cls.alix: which index register the
				;   first operand was, since opword
				;   overwrites opfix with the second
inscod:		defs	1	; A CODE A HANDLER MUST KEEP across a
				;   parse that clobbers opcod: cls.in's
				;   register across the opany that reads
				;   the port, and JP's, JR's and CALL's
				;   opcode across opexp, which modifies
				;   BC so a register will not do
lddst:		defs	1	; cls.ld: what the destination was,
lddcod:		defs	1	;   the code it gave, and the PREFIX
lddfix:		defs	1	;   it forced, across the second
				;   opany call - which clears opfix

; The jump table, one word per class, in the order of optab.inc. All
; twenty-one entries are here from the start so that the later notes
; replace one word each rather than renumbering anything.

clstab:		defw	cls.none	; C_NONE
		defw	cls.noned	; C_NONED
		defw	cls.alu		; C_ALU
		defw	cls.alua	; C_ALUA
		defw	cls.incd	; C_INCDEC
		defw	cls.bit		; C_BIT
		defw	cls.rot		; C_ROT
		defw	cls.ld		; C_LD
		defw	cls.jp		; C_JP
		defw	cls.jr		; C_JR
		defw	cls.djnz	; C_DJNZ
		defw	cls.call	; C_CALL
		defw	cls.ret		; C_RET
		defw	cls.rst		; C_RST
		defw	cls.stk		; C_STACK
		defw	cls.ex		; C_EX
		defw	cls.in		; C_IN
		defw	cls.out		; C_OUT
		defw	cls.im		; C_IM
		defw	cls.mlub	; C_MULUB
		defw	cls.mluw	; C_MULUW
