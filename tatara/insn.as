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

INSN_INCLUDED	equ	1		; skips the external in insn.inc

		public	assemble_instruction

		include	insn.inc
		include	optab.inc
		include	fields.inc
					; FIELD_OPERATION,
					;   FIELD_OPERATION_LENGTH,
					;   FIELD_OPERAND,
					;   FIELD_OPERAND_LENGTH
		include	symtab.inc	; location_counter, require_placeable
		include	errs.inc	; error_not_a_form, and the four
		include	emit.inc
			; emit_byte, emit_opcode, saved_value, emitted_count

		cseg

; assemble_instruction - if this line's operation is an instruction, measure
; it.
;
;   The driver calls this when the line is neither a directive nor a
;   macro call. A line that is not an instruction either is
;   passed on as text, which is what Tatara has always done with a line
;   it does not recognise: until every class is implemented, "not in the
;   table" does not mean "not an instruction".
;
; Input:	IX -> the line's field block
; Output:	CY set   = not an instruction, and nothing has changed
;		CY clear = location_counter has been moved
; Modifies:	AF, BC, DE, HL
;
;   The fields arrive through IX rather than as a global, because the
;   driver exports nothing and this module has no business knowing the
;   name of its buffer. It is split_line's own convention, and macros.as
;   passes body_fields the same way.

assemble_instruction:
		ld	a,(ix+FIELD_OPERATION_LENGTH)
		or	a
		scf
		ret	z		; no operation on this line at all
		ld	b,a
		ld	e,(ix+FIELD_OPERATION)
		ld	d,(ix+FIELD_OPERATION+1)
		call	find_mnemonic	; CY set = no such mnemonic
		ret	c
		ld	(insn_class),a
		ld	a,c
		ld	(insn_base),a	; not read while measuring, except
					;   by CLASS_ARITH

		call	require_placeable
					; a transient DSEG with no group
					;   open cannot be placed in

		ld	e,(ix+FIELD_OPERAND)
		ld	d,(ix+FIELD_OPERAND+1)
		ld	a,(ix+FIELD_OPERAND_LENGTH)
		call	operand_start
		call	operand_skip_blanks

		ld	a,(insn_class)	; the handler, through class_table.
		dec	a		;   Classes are 1-based, and each
		add	a,a		;   entry is a word
		ld	e,a
		ld	d,0
		ld	hl,class_table
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		call	call_class_handler
					; the handler emits; the emitter
					;   counts

		call	operand_must_end	; nothing may be left over

; THE LENGTH IS WHAT THE EMITTER COUNTED. There is no second
; statement of it to disagree with: a handler cannot claim three bytes
; and emit four when it no longer claims anything. the cross-check
; and the ld hl,n in every handler went out together, and this note is
; not leaving a check unperformed - it removes the state the check was
; looking for.
;
; ONE HALF OF IT SURVIVES. No Z80 instruction is zero bytes long, so a
; handler that returned without emitting would advance location_counter by
; nothing and put every address below it out, in a file that assembled
; without a word. Nothing can reach that today; the mnemonic somebody
; adds in a year with a handler that forgets its emit_byte can, and that is
; exactly when nobody will be looking. Six bytes say so. It is the
; argument that kept assemble_bad_class.

		ld	hl,(emitted_count)
		ld	a,h
		or	l
		jp	z,error_emitted_nothing
					; a handler that emitted nothing
		ld	de,(location_counter)
		add	hl,de
		ld	(location_counter),hl
		or	a		; CY clear = it was an instruction
		ret

call_class_handler:
		jp	(hl)		; the call above is what returns
					;   here

; --- CLASS_NONE: no operands, one byte. NOP, HALT, DI, EI, EXX, DAA, CPL,
;     SCF, CCF and the four accumulator rotates.

assemble_no_operands:
		ld	a,(insn_base)
		call	emit_byte
		ret

; --- CLASS_NONE_ED: no operands, and an ED in front of the opcode. NEG, RETI,
;     RETN, RLD, RRD, and the twelve block instructions.

assemble_no_operands_ed:
		ld	a,0edh
		call	emit_byte
		ld	a,(insn_base)
		call	emit_byte
		ret

; --- CLASS_ALU: SUB, AND, XOR, OR and CP. One 8-bit source, or an
;     immediate byte. M80 takes ONE operand for these - "sub a,b" is not
;     its spelling - and so does Tatara: accepting the two-operand form
;     would let source through that M80 refuses, which is the wrong
;     direction to be incompatible in.

assemble_alu:	call	read_byte_source	; a register, (HL) or indexed?
		jr	c,assemble_alu.immediate
		ld	a,(operand_code)
					; base + the register's code, in the
		ld	hl,insn_base	;   ordinary shape: prefix first,
		add	a,(hl)		;   displacement last
		call	emit_opcode
		ret
assemble_alu.immediate:
		call	skip_expression	; no: then it is an immediate
		jp	c,error_not_a_form	; "cp" with nothing after it
		ld	a,(insn_base)
		add	a,046h		; every ALU family's immediate form is
		call	emit_byte	;   its base plus 46h
		call	emit_saved_byte
		ret

; --- CLASS_ARITH: ADD, ADC and SBC. The 8-bit form names the accumulator
;     first; the 16-bit ones take HL, or an index register for ADD only.

assemble_arith:	ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form	; it must say what it adds to
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		jr	z,assemble_arith.byte
		cp	OPERAND_PAIR
		jr	z,assemble_arith.word
		cp	OPERAND_IX
		jr	z,assemble_arith.ix
		jp	error_not_a_form

assemble_arith.byte:
		ld	a,(operand_code)
					; only the accumulator: "add b,c"
		cp	7		;   is not a form
		jp	nz,error_not_a_form
		call	expect_comma
		jp	c,error_not_a_form
		jp	assemble_alu	; and the rest is exactly CLASS_ALU

assemble_arith.word:
		ld	a,(operand_code)
					; only HL: "add de,hl" is not a form
		cp	2
		jp	nz,error_not_a_form
		call	expect_comma
		jp	c,error_not_a_form
		ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_PAIR	; "add hl,ix" does not exist
		jp	nz,error_not_a_form
		ld	a,(operand_code)	; the pair code, times sixteen
		rlca
		rlca
		rlca
		rlca			; 3 is the largest, so nothing
		ld	c,a		;   leaves the byte
		ld	a,(insn_base)	; THE ONE PLACE MEASURING READ THE
		cp	080h		;   BASE OPCODE, and emitting reads it
		jr	z,assemble_arith.word_add
					;   for the same reason: ADD HL,rr is
		ld	a,0edh		;   one byte and ADC and SBC are ED-
		call	emit_byte	;   prefixed and two, and nothing in
		ld	a,(insn_base)	;   the operands says which
		cp	088h
		ld	a,04ah		; ADC HL,rr = ED 4Ah + 16p
		jr	z,assemble_arith.word_ed
		ld	a,042h		; SBC HL,rr = ED 42h + 16p
assemble_arith.word_ed:
		add	a,c
		call	emit_byte
		ret
assemble_arith.word_add:
		ld	a,009h		; ADD HL,rr = 09h + 16p
		add	a,c
		call	emit_byte
		ret

assemble_arith.ix:
		ld	a,(insn_base)
		cp	080h
		jp	nz,error_not_a_form
					; ADC and SBC have no index form
		ld	a,(operand_prefix)
		ld	(arith_prefix),a	; which index register it was
		call	expect_comma
		jp	c,error_not_a_form
		ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_IX
		jr	z,assemble_arith.ix_same
		cp	OPERAND_PAIR
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	2		; "add ix,hl" does not exist
		jp	z,error_not_a_form
		jr	assemble_arith.ix_emit
assemble_arith.ix_same:
		ld	a,(operand_prefix)
					; "add ix,ix" is a form and "add
		ld	hl,arith_prefix	;   ix,iy" is not, and the prefix
		cp	(hl)		;   byte is the only difference
		jp	nz,error_not_a_form
assemble_arith.ix_emit:
		ld	a,(arith_prefix)
					; the prefix the FIRST operand set -
		call	emit_byte
			;   find_operand_word overwrote operand_prefix with the
		ld	a,(operand_code)
				;   second one. And find_operand_word gives an
		rlca			;   index register pair code 2, so
		rlca			;   "add ix,ix" needs no special case:
		rlca			;   DD 29 falls out
		rlca
		add	a,009h
		call	emit_byte
		ret

; --- CLASS_LD: the whole of LD. Eighteen operand forms and four lengths,
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

assemble_ld:	call	read_operand	; the destination
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		ld	(ld_dest_kind),a
		ld	a,(operand_code)
		ld	(ld_dest_code),a
		ld	a,(operand_prefix)
					; THE BYTE THAT USED TO BE LOST: the
		ld	(ld_dest_prefix),a
				;   source's read_operand clears operand_prefix
		call	expect_comma
		jp	c,error_not_a_form
		call	read_operand	; the source
		jp	c,error_not_a_form

		ld	a,(ld_dest_kind)
		cp	OPERAND_BYTE
		jp	z,assemble_ld.byte
		cp	OPERAND_HALF
		jp	z,assemble_ld.half
		cp	OPERAND_INDEXED
		jp	z,assemble_ld.indexed
		cp	OPERAND_PAIR
		jp	z,assemble_ld.pair
		cp	OPERAND_IX
		jp	z,assemble_ld.ix
		cp	OPERAND_AT_BC
		jp	z,assemble_ld.at_pair
		cp	OPERAND_AT_DE
		jp	z,assemble_ld.at_pair
		cp	OPERAND_MEMORY
		jp	z,assemble_ld.mem
		cp	OPERAND_I
		jp	z,assemble_ld.i_or_r
		cp	OPERAND_R
		jp	z,assemble_ld.i_or_r
		jp	error_not_a_form

; --- one routine LD keeps and two it no longer owns. assemble_ld.emit is
;     emit_opcode with the DESTINATION's prefix and kind, for the four forms
;     whose prefix the source's read_operand has already cleared out of
;     operand_prefix, and no other class wants it; base_plus_8x and
;     base_plus_16x are the two shapes an operand code takes inside an opcode,
;     and five families use them.

assemble_ld.emit:
		ld	c,a		; the opcode, across the prefix
		ld	a,(ld_dest_prefix)
		or	a
		call	nz,emit_byte	; DD or FD, if the DESTINATION
		ld	a,c		;   forced one
		call	emit_byte
		ld	a,(ld_dest_kind)
			; ITS kind, not operand_kind: displacement_length is
		cp	OPERAND_INDEXED	;   not cleared per operand, and a
		ret	nz		;   stale one would go out
		jp	emit_displacement	; and "(ix)" is "(ix+0)"

base_plus_8x:	rlca			; base in C, code in A: base plus
		rlca			;   EIGHT times the code. 7 is the
		rlca			;   largest, so nothing leaves the
		add	a,c		;   byte
		ret			; AND NOT LD's: JP, JR, CALL and
					;   IN put a code in the same
					;   three bits, so the name says
					;   the arithmetic and not the
					;   one family that got here
					;   first

base_plus_16x:	rlca			; the same, sixteen times: a pair
		rlca			;   code, and 3 is the largest
		rlca
		rlca
		add	a,c
		ret

; --- the index halves. The prefix governs the INSTRUCTION, not the
;     operand, so it makes H and L into halves wherever they appear in
;     the line - which is why the operand that is NOT the half may not
;     be H, L or (HL), and why two halves must belong to the same
;     register. 101 listed three conflicts; assemble_ld.plain_only is two of
;     them.
;
;     operand_prefix is the asymmetry. When the half is the SOURCE it is
;     already right, the source's read_operand having run last; when the half
;     is the DESTINATION it holds whatever the source forced, so
;     assemble_ld.half puts the destination's prefix there and emit_opcode
;     serves both ways round without being touched.

assemble_ld.half:
		ld	a,(operand_prefix)	; the SOURCE's prefix - only
		ld	(insn_saved_code),a	;   "ld ixh,ixl" has one - kept
		ld	a,(ld_dest_prefix)	;   across the store below
		ld	(operand_prefix),a
					; THE INSTRUCTION'S prefix is the
					;   destination's, and emit_opcode
					;   emits whatever operand_prefix holds
		ld	a,(operand_kind)
		cp	OPERAND_IMM
		jr	z,assemble_ld.half_imm	; "ld ixh,44h" is DD 26 44
		cp	OPERAND_HALF
		jr	z,assemble_ld.half_half	; "ld ixl,ixh" - one register
		cp	OPERAND_BYTE
		jp	nz,error_not_a_form	; and nothing else: no (hl), no
		ld	a,(operand_code)
					;   (nn), no (ix+d), no I and no R
		call	assemble_ld.plain_only
		jr	assemble_ld.half_emit

assemble_ld.half_half:
		ld	a,(insn_saved_code)
					; two halves, and ONE prefix can go
		ld	hl,ld_dest_prefix	;   out: "ld ixh,iyl" is not an
		cp	(hl)		;   instruction, because only one of
		jp	nz,error_not_a_form	;   the two could be emitted

assemble_ld.half_emit:
		ld	c,040h		; 40h + 8*dst + src, which is the
		ld	a,(ld_dest_code)
					;   ordinary register-to-register
		call	base_plus_8x	;   opcode behind a prefix
		ld	c,a
		ld	a,(operand_code)
		add	a,c
		jp	emit_opcode

assemble_ld.half_imm:
		ld	c,006h		; 06h + 8*dst, and the byte after
		ld	a,(ld_dest_code)
		call	base_plus_8x
		call	emit_opcode
		jp	emit_saved_byte

assemble_ld.byte_half:
		ld	a,(ld_dest_code)
					; "ld b,ixh": the PLAIN operand is
		call	assemble_ld.plain_only
					;   the destination here, and the
		jr	assemble_ld.half_emit
					;   rule does not care which it is.
					;   operand_prefix is the source's
					;   already

; assemble_ld.plain_only - the operand that is not the index half may not be H,
; L or (HL).
;
;   One prefix governs the whole instruction: "ld h,ixl" would assemble
;   as "ld ixh,ixl" and say something the source did not, and code 6
;   behind a prefix is the INDEXED form, so "ld ixh,(hl)" is
;   "ld h,(ix+d)". Both of those are this one test, from either
;   direction.
;
; Input:	A = the plain operand's register code
; Output:	returns, or error_not_a_form does not return
; Modifies:	AF

assemble_ld.plain_only:
		cp	4
		ret	c		; B, C, D and E
		cp	7
		jp	nz,error_not_a_form	; H is 4, L is 5 and (HL) is 6
		ret			; and A is 7

; --- the destination is an 8-bit register or (HL): code 6 is (HL), and
;     the two are the same thing everywhere but here.

assemble_ld.byte:
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		jr	z,assemble_ld.byte_byte
		cp	OPERAND_HALF
		jp	z,assemble_ld.byte_half	; "ld b,ixh"
		cp	OPERAND_INDEXED
		jr	z,assemble_ld.byte_indexed
		cp	OPERAND_IMM
		jp	z,assemble_ld.byte_imm	; "ld r,n" and "ld (hl),n"
		ld	a,(ld_dest_code)	; everything below is the
		cp	7		;   accumulator's alone
		jp	nz,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_AT_BC
		jp	z,assemble_ld.a_bc	; "ld a,(bc)"
		cp	OPERAND_AT_DE
		jp	z,assemble_ld.a_de	; "ld a,(de)"
		cp	OPERAND_MEMORY
		jp	z,assemble_ld.a_mem	; "ld a,(nn)"
		cp	OPERAND_I
		jp	z,assemble_ld.a_i_or_r	; "ld a,i"
		cp	OPERAND_R
		jp	z,assemble_ld.a_i_or_r	; "ld a,r"
		jp	error_not_a_form

assemble_ld.byte_byte:
		ld	a,(ld_dest_code)	; both (HL)? That encoding is
		cp	6		;   HALT, so LD has to refuse it
		jr	nz,assemble_ld.byte_byte_emit
		ld	a,(operand_code)
		cp	6
		jp	z,error_not_a_form
assemble_ld.byte_byte_emit:
		ld	c,040h		; 40h + 8*dst + src
		ld	a,(ld_dest_code)
		call	base_plus_8x
		ld	c,a
		ld	a,(operand_code)
		add	a,c
		call	emit_byte
		ret

assemble_ld.byte_indexed:
		ld	a,(ld_dest_code)
					; "ld (hl),(ix+d)": no instruction
		cp	6		;   reads two memory operands, and
		jp	z,error_not_a_form
					;   the prefix would have nowhere
		ld	c,046h		;   to point
		ld	a,(ld_dest_code)
		call	base_plus_8x
		call	emit_opcode	; THE SOURCE is the indexed one
		ret			;   here, so operand_prefix is current

assemble_ld.byte_imm:
		ld	c,006h		; 06h + 8*dst, and no prefix can
		ld	a,(ld_dest_code)	;   reach this form
		call	base_plus_8x
		call	emit_byte
		call	emit_saved_byte
		ret

assemble_ld.a_bc:
		ld	a,00ah		; "ld a,(bc)"
		call	emit_byte
		ret

assemble_ld.a_de:
		ld	a,01ah		; "ld a,(de)"
		call	emit_byte
		ret

assemble_ld.a_mem:
		ld	a,03ah		; "ld a,(nn)"
		call	emit_byte
		call	emit_saved_word
		ret

assemble_ld.a_i_or_r:
		ld	a,0edh		; "ld a,i" is ED 57h and "ld a,r"
		call	emit_byte
				;   is ED 5Fh: register_table gives I and
		ld	c,057h		;   R the same code 0, and only
		ld	a,(operand_kind)	;   the KIND tells them apart
		sub	OPERAND_I
		call	base_plus_8x
		call	emit_byte
		ret

; --- the destination is (IX+d) or (IY+d)

assemble_ld.indexed:
		ld	a,(operand_kind)
		cp	OPERAND_IMM
		jr	z,assemble_ld.indexed_imm	; "ld (ix+d),n"
		cp	OPERAND_BYTE
		jp	nz,error_not_a_form
					; OPERAND_INDEXED is one of these, so
		ld	a,(operand_code)
					;   "ld (ix+d),(iy+d)" never gets
		cp	6		;   as far as a prefix. This is
		jp	z,error_not_a_form	;   "ld (ix+d),(hl)", from the
		ld	c,070h		;   other direction
		add	a,c		; 70h + src, A being still the
		call	assemble_ld.emit	;   source's code
		ret

assemble_ld.indexed_imm:
		ld	a,036h		; THE ONE FORM THAT EMITS FROM
		call	assemble_ld.emit
					;   BOTH OPERANDS: the displace-
		call	emit_saved_byte
				;   ment goes out inside assemble_ld.emit,
		ret			;   the immediate after it

; --- the destination is BC, DE, HL or SP

assemble_ld.pair:
		ld	a,(operand_kind)
		cp	OPERAND_IMM
		jr	z,assemble_ld.pair_imm	; "ld rr,nn"
		cp	OPERAND_MEMORY
		jr	z,assemble_ld.pair_mem
		cp	OPERAND_PAIR
		jr	z,assemble_ld.sp_hl
		cp	OPERAND_IX
		jr	z,assemble_ld.sp_ix
		jp	error_not_a_form

assemble_ld.pair_imm:
		ld	c,001h		; 01h + 16p
		ld	a,(ld_dest_code)
		call	base_plus_16x
		call	emit_byte
		call	emit_saved_word
		ret

assemble_ld.pair_mem:
		ld	a,(ld_dest_code)	; "ld hl,(nn)" is 2Ah and THREE
		cp	2		;   bytes; every other pair is
		jr	nz,assemble_ld.pair_mem_ed
					;   ED 4Bh+16p and four. Choosing
		ld	a,02ah		;   wrongly is a WRONG LENGTH
		call	emit_byte	;   here, not a wasted byte
		call	emit_saved_word
		ret

assemble_ld.pair_mem_ed:
		ld	a,0edh
		call	emit_byte
		ld	c,04bh
		ld	a,(ld_dest_code)
		call	base_plus_16x
		call	emit_byte
		call	emit_saved_word
		ret

assemble_ld.sp_hl:
		ld	a,(ld_dest_code)
					; "ld sp,hl" is the only pair-to-
		cp	3		;   pair move there is
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	2
		jp	nz,error_not_a_form
		ld	a,0f9h
		call	emit_byte
		ret

assemble_ld.sp_ix:
		ld	a,(ld_dest_code)	; "ld sp,ix"
		cp	3
		jp	nz,error_not_a_form
		ld	a,0f9h
		call	emit_opcode	; THE SOURCE holds the prefix,
		ret			;   and OPERAND_IX carries no
					;   displacement

; --- the destination is IX or IY

assemble_ld.ix:	ld	a,(operand_kind)
		cp	OPERAND_IMM
		jr	z,assemble_ld.ix_imm	; "ld ix,nn"
		cp	OPERAND_MEMORY
		jr	z,assemble_ld.ix_mem	; "ld ix,(nn)"
		jp	error_not_a_form

assemble_ld.ix_imm:
		ld	a,021h		; THE DESTINATION holds the
		call	assemble_ld.emit
					;   prefix in both of these, and
		call	emit_saved_word	;   carries no displacement
		ret

assemble_ld.ix_mem:
		ld	a,02ah
		call	assemble_ld.emit
		call	emit_saved_word
		ret

; --- the destination is (BC) or (DE): the accumulator goes there and
;     nothing else does

assemble_ld.at_pair:
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	7
		jp	nz,error_not_a_form
		ld	a,(ld_dest_kind)
					; 02h for (BC), 12h for (DE), and
		cp	OPERAND_AT_BC	;   the kind is the only thing
		ld	a,002h		;   that says which: both carry
		jr	z,assemble_ld.at_pair_emit	;   code 0
		ld	a,012h
assemble_ld.at_pair_emit:
		call	emit_byte
		ret

; --- the destination is an address

assemble_ld.mem:
		ld	a,(operand_kind)	; the ADDRESS is the
		cp	OPERAND_BYTE
				;   destination's, and expression_at still
		jr	z,assemble_ld.mem_a
					;   holds it: every source here is
		cp	OPERAND_PAIR
				;   a bare register word, so skip_expression
		jr	z,assemble_ld.mem_pair	;   never ran a second time
		cp	OPERAND_IX
		jr	z,assemble_ld.mem_ix	; "ld (nn),ix"
		jp	error_not_a_form

assemble_ld.mem_a:
		ld	a,(operand_code)	; "ld (nn),a", and no other
		cp	7		;   register
		jp	nz,error_not_a_form
		ld	a,032h
		call	emit_byte
		call	emit_saved_word
		ret

assemble_ld.mem_pair:
		ld	a,(operand_code)
					; "ld (nn),hl" is 22h and three;
		cp	2		;   the rest are ED 43h+16p and
		jr	nz,assemble_ld.mem_pair_ed	;   four
		ld	a,022h
		call	emit_byte
		call	emit_saved_word
		ret

assemble_ld.mem_pair_ed:
		ld	a,0edh
		call	emit_byte
		ld	c,043h
		ld	a,(operand_code)	; the SOURCE's pair code here
		call	base_plus_16x
		call	emit_byte
		call	emit_saved_word
		ret

assemble_ld.mem_ix:
		ld	a,022h
		call	emit_opcode	; THE SOURCE holds the prefix
		call	emit_saved_word
		ret

; --- the destination is I or R

assemble_ld.i_or_r:
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	7
		jp	nz,error_not_a_form
		ld	a,0edh		; "ld i,a" is ED 47h and "ld r,a"
		call	emit_byte	;   is ED 4Fh - the same code 0,
		ld	c,047h		;   and the kind again
		ld	a,(ld_dest_kind)
		sub	OPERAND_I
		call	base_plus_8x
		call	emit_byte
		ret

; --- CLASS_INCDEC: INC and DEC, in both widths.

assemble_incdec:
		call	read_byte_source
		jr	c,assemble_incdec.word
		ld	a,(operand_code)
					; base + EIGHT times the code: INC is
		rlca			;   04h+8r and DEC is 05h+8r, and the
		rlca			;   row's base byte is the 04h or the
		rlca			;   05h
		ld	hl,insn_base
		add	a,(hl)
		call	emit_opcode
		ret
assemble_incdec.word:
		ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_IX
		jr	z,assemble_incdec.ix
		cp	OPERAND_PAIR	; not AF, not I, not R
		jp	nz,error_not_a_form
		call	assemble_incdec.opcode
					; 03h or 0Bh, plus sixteen times
					;   the pair code
		ret
assemble_incdec.ix:
		ld	a,(operand_prefix)
					; DD or FD, then 23h or 2Bh - which
		call	emit_byte	;   is the pair form with HL's code
		call	assemble_incdec.opcode
		ret

; assemble_incdec.opcode - the sixteen-bit opcode: 03h for INC and 0Bh for DEC,
; plus sixteen times the pair code. WHICH ONE comes from bit 0 of the row's
; base byte - INC's is 04h and DEC's is 05h - which is one rrca instead of a
; third byte in every row of the table.
;
; Input:	(operand_code) = the pair code, (insn_base) = 04h or 05h
; Output:	one byte emitted
; Modifies:	AF, BC, HL

assemble_incdec.opcode:
		ld	a,(operand_code)
		rlca
		rlca
		rlca
		rlca
		ld	c,a
		ld	a,(insn_base)
		rrca			; bit 0 into carry: INC 04h -> clear,
		ld	a,003h		;   DEC 05h -> set
		jr	nc,assemble_incdec.opcode_emit
		ld	a,00bh
assemble_incdec.opcode_emit:
		add	a,c
		jp	emit_byte

; --- CLASS_STACK: PUSH and POP. The stack set is BC, DE, HL and AF: SP is
;     not in it and AF takes its place, which is why register_table gives them
;     different KINDS and the same code.

assemble_stack:	ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_AF
		jr	z,assemble_stack.pair
		cp	OPERAND_IX
		jr	z,assemble_stack.ix
		cp	OPERAND_PAIR
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	3		; "push sp" does not exist
		jp	z,error_not_a_form
assemble_stack.pair:
		call	assemble_stack.opcode
					; base + sixteen times the code. AF
					;   and SP share code 3 and differ in
		ret			;   KIND, which is the doing
assemble_stack.ix:
		ld	a,(operand_prefix)
					; DD or FD, then the same byte with
		call	emit_byte
			;   HL's code - find_operand_word gives an index
		call	assemble_stack.opcode	;   register pair code 2
		ret

assemble_stack.opcode:
		ld	a,(operand_code)
		rlca
		rlca
		rlca
		rlca
		ld	c,a
		ld	a,(insn_base)
		add	a,c
		jp	emit_byte

; --- CLASS_RET: one byte with a condition or without one.

assemble_ret:	call	operand_at_end	; nothing left is "ret" on its own
		jr	z,assemble_ret.plain
		ld	hl,condition_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_code)
					; C0h + eight times the condition
		rlca
		rlca
		rlca
		add	a,0c0h
		jr	assemble_ret.emit
assemble_ret.plain:
		ld	a,(insn_base)	; plain RET: the row carries 0C9h
assemble_ret.emit:
		call	emit_byte
		ret

; --- CLASS_RST and CLASS_IM: one expression each, and the length does not
;     depend on what it says. Whether RST's operand is a multiple of
;     eight below 40h, and whether IM's is 0, 1 or 2, are questions pass
;     1 cannot answer for a forward reference - so pass 2 answers them
;     for every case rather than for some.

assemble_rst:	call	skip_expression
		jp	c,error_not_a_form
		call	saved_value	; 0 on pass 1, which is "rst 0" and
		ld	a,h		;   passes every test below
		or	a
		jp	nz,error_bad_rst	; above 00FFh, let alone 38h
		ld	a,l
		cp	040h
		jp	nc,error_bad_rst	; 40h and up
		and	007h
		jp	nz,error_bad_rst	; not a multiple of eight
		ld	a,l
		ld	hl,insn_base	; the operand IS the opcode: 0C7h + n
		add	a,(hl)
		call	emit_byte
		ret

; --- CLASS_DJNZ is CLASS_IM's body under a second name. One expression, always
;     two bytes, and the length does not depend on what the expression
;     says: DJNZ's displacement is "loop - ($ + 2)", a subtraction pass
;     2 does and pass 1 never needs.

; DJNZ STOPS SHARING THIS BODY. It was given a second label here
; because both were "one expression, always two bytes" - but IM is
; ED 46h/56h/5Eh and DJNZ is 10h and a displacement from $. They
; agreed about the LENGTH and about nothing else, and the sharing was
; a coincidence of the measuring phase rather than a shared idea.
; CLASS_DJNZ arrives later, so it keeps a measuring-only body until then.

assemble_djnz:	call	skip_expression
		jp	c,error_not_a_form
		ld	a,(insn_base)	; 10h, and then the same distance
		call	emit_byte	;   JR measures - which is the whole
		call	emit_relative	;   of what these two had
					;   in common and IM never did
		ret

assemble_im:	call	skip_expression
		jp	c,error_not_a_form
		call	saved_value	; 0 on pass 1, which is "im 0"
		ld	a,h
		or	a
		jp	nz,error_bad_im
		ld	a,0edh
		call	emit_byte
		ld	a,l		; 0, 1 and 2 encode as 46h, 56h and
		or	a		;   5Eh, which is not an arithmetic
		ld	a,046h		;   progression - so three bytes in
		jr	z,assemble_im.emit
					; the handler carries all three,
		dec	l		;   and the table carries none
		ld	a,056h
		jr	z,assemble_im.emit
		dec	l
		ld	a,05eh
		jp	nz,error_bad_im
assemble_im.emit:
		call	emit_byte
		ret

; --- CLASS_JP: three bytes to an address, with a condition or without one;
;     ONE byte to (HL); TWO to (IX) or (IY).
;
;     JP is the one instruction whose indexed form has no displacement
;     byte. Everywhere else "(ix)" and "(ix+5)" are the same length -
;     "ld a,(ix)" is DD 7E 00 - so read_displacement's answer is thrown away.
;     Here it is the difference between a form and a typo, which is why
;     no_displacement exists and why clsxtra is NOT used below.

assemble_jp:	call	condition_and_comma	; "jp cc,nn"?
		jr	c,assemble_jp.register
					; no - it may still be (hl) or (ix)
		ld	c,0c2h		; C2h + 8*cc. The LITERAL is the
		ld	a,(operand_code)
					;   honest one: the table's base is
		call	base_plus_8x	;   C3h, which is the UNconditional
		ld	(insn_saved_code),a	;   form. And it goes to memory
		call	skip_expression	;   because skip_expression modifies BC
		jp	c,error_not_a_form
		ld	a,(insn_saved_code)
		call	emit_byte
		call	emit_saved_word
		ret

assemble_jp.register:
		call	read_byte_source	; "jp (hl)", "jp (ix)"?
		jr	c,assemble_jp.address
		ld	a,(operand_code)
		cp	6		; any other register code means a
		jr	nz,assemble_jp.restart	;   SYMBOL named B, C, D...
		call	no_displacement
		jp	nz,error_not_a_form
					; "jp (ix+5)": DD E9 has nowhere to
		ld	a,(operand_prefix)
					; the prefix if there is one, then
		or	a		;   E9h. "jp (ix)" is DD E9 and the
		call	nz,emit_byte	;   emitter has been counting the
		ld	a,0e9h		;   prefix all along
		call	emit_byte
		ret

assemble_jp.restart:
		call	operand_restore
				; read_operand's save still points at the
					;   start of this operand
assemble_jp.address:
		call	skip_expression
		jp	c,error_not_a_form	; "jp" with nothing after it
		ld	a,(insn_base)	; C3h, straight from the table
		call	emit_byte
		call	emit_saved_word
		ret

; --- CLASS_JR: two bytes, and only four of the eight conditions.

assemble_jr:	call	condition_and_comma
		jr	c,assemble_jr.plain
		ld	a,(operand_code)
					; JR has NZ, Z, NC and C and stops
		cp	4		;   there: "jr po,x" is not an
		jp	nc,error_not_a_form	;   instruction on any Z80
		ld	c,020h		; 20h + 8*cc is 20h, 28h, 30h and
		call	base_plus_8x	;   38h, and there is no 40h
		ld	(insn_saved_code),a
		call	skip_expression
		jp	c,error_not_a_form
		ld	a,(insn_saved_code)
		call	emit_byte
		jr	assemble_jr.distance
assemble_jr.plain:
		call	skip_expression
		jp	c,error_not_a_form
		ld	a,(insn_base)	; 18h, straight from the table
		call	emit_byte
assemble_jr.distance:
		call	emit_relative
				; NOT emit_expr_word: the byte is a distance
					;   from the address after this
		ret			;   instruction, not an address

; --- CLASS_CALL: three bytes either way, so condition_and_comma's answer does
; not change the length - only where the cursor ends up.

assemble_call:	call	condition_and_comma
		jr	c,assemble_call.plain
		ld	c,0c4h		; C4h + 8*cc; the table's CDh is
		ld	a,(operand_code)	;   the unconditional form
		call	base_plus_8x
		ld	(insn_saved_code),a
		call	skip_expression
		jp	c,error_not_a_form
		ld	a,(insn_saved_code)
		jr	assemble_call.emit
assemble_call.plain:
		call	skip_expression
		jp	c,error_not_a_form
		ld	a,(insn_base)	; CDh
assemble_call.emit:
		call	emit_byte
		call	emit_saved_word
		ret

; --- CLASS_BIT and CLASS_ROT: ten mnemonics and one body. "bit b,s" is "rlc s"
;     with a number and a comma in front of it, so CLASS_BIT reads those
;     two and FALLS THROUGH.

assemble_bit:	call	skip_expression	; the bit number. PASS 1 DOES NOT
		jp	c,error_not_a_form
					;   READ IT: bit 0 and bit 7 are the
		call	expect_comma	;   same length, so "bit n,b" with n
		jp	c,error_not_a_form
					;   defined below still measures
		call	saved_value	; its VALUE, and 0 on pass 1 - so
		ld	a,h		;   the range check is pass 2's, as
		or	a		;   RST's and IM's have been since
		jp	nz,error_bad_bit_number	;   and for the same reason
		ld	a,l
		cp	8
		jp	nc,error_bad_bit_number
		rlca			; eight times it, and into the base:
		rlca			;   "bit 7,b" is CB 78h, which is
		rlca			;   40h + 56 + 0
		ld	hl,insn_base
		add	a,(hl)
		ld	(hl),a
					; and on into assemble_rot

assemble_rot:	call	read_byte_source
		jp	c,error_not_a_form
		ld	a,(operand_kind)	; AND NO INDEX HALF: DD CB d op
		cp	OPERAND_HALF	;   addresses memory, so there is no
		jp	z,error_not_a_form
					;   room for a register - "rlc ixh"
					;   would be three bytes of a four-
					;   byte instruction. The DD CB forms
					;   that DO name a register are the
					;   family 101 declined
		ld	a,(operand_prefix)
					; DD CB d op - THE ONE ENCODING IN
		or	a		;   THE INSTRUCTION SET whose
		call	nz,emit_byte	;   displacement comes BEFORE its
		ld	a,0cbh		;   opcode. emit_opcode puts them the
		call	emit_byte	;   other way round and cannot serve
		ld	a,(operand_kind)	;   it, so the four bytes are
		cp	OPERAND_INDEXED	;   written out here, next to the
		call	z,emit_displacement	;   comment that says why
		ld	a,(operand_code)
		ld	hl,insn_base
		add	a,(hl)
		call	emit_byte
		ret

; --- CLASS_EX: three forms, and (SP) is an address that EX alone looks
;     inside. Every jump below is a jp: the block is longer than a jr
;     reaches and an out-of-range one is emitted with the low byte of
;     the displacement and no link error (the evening).

assemble_ex:	call	read_operand
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_PAIR
		jp	z,assemble_ex.de_hl
		cp	OPERAND_AF
		jp	z,assemble_ex.af_af
		cp	OPERAND_MEMORY
		jp	nz,error_not_a_form
		call	operand_is_sp	; an address, and only "(sp)" of all
		jp	nz,error_not_a_form	;   the addresses there are
		call	expect_comma
		jp	c,error_not_a_form
		ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_IX
		jp	z,assemble_ex.sp_ix	; "ex (sp),ix" is DD E3
		cp	OPERAND_PAIR
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	2		; "ex (sp),bc" does not exist
		jp	nz,error_not_a_form
		ld	a,0e3h
			; read_operand cleared operand_prefix, and HL does
		call	emit_opcode
				;   not set it - find_operand_word sets it for
		ret			;   IX, IY and the four index halves,
					;   none of which reaches here - so
					;   this is E3h alone

assemble_ex.sp_ix:
		ld	a,0e3h		; and the same call is DD E3 here,
		call	emit_opcode	;   the prefix having come from the
		ret	;   SECOND operand - so operand_prefix is the
					;   current one and the
					;   assemble_ld.emit is not wanted

assemble_ex.de_hl:
		ld	a,(operand_code)
					; "ex de,hl" and no other pair -
		cp	1		;   and not "ex hl,de" either, which
		jp	nz,error_not_a_form	;   is not M80's spelling
		call	expect_comma
		jp	c,error_not_a_form
		ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_PAIR
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	2
		jp	nz,error_not_a_form
		ld	a,0ebh		; EBh, and measuring could not tell
		call	emit_byte	;   it from 08h or E3h: all three
		ret			;   are one byte

assemble_ex.af_af:
		call	expect_comma	; "ex af,af'". The apostrophe gets
		jp	c,error_not_a_form
					;   this far only because of the
		ld	hl,register_table
					;   split_line fix: without it the
		call	find_operand_word
					;   operand field swallows the rest
		jp	c,error_not_a_form
					;   of the line, comment and all
		ld	a,(operand_kind)
		cp	OPERAND_AF_ALT
		jp	nz,error_not_a_form
		ld	a,008h
		call	emit_byte
		ret

; --- CLASS_IN and CLASS_OUT: one instruction written backwards. Both are two
;     bytes; in both, the PORT decides which register is allowed. The
;     only difference is which operand comes first, so they share
;     read_port and emit_in_out.
;
;     AND BOTH HAVE AN UNDOCUMENTED FORM at register code 6 - the slot
;     (HL) fills everywhere else, and the one register field of the ED
;     group that names no register. "IN F,(C)" is ED 70 and
;     "OUT (C),0" is ED 71. Neither operand is a register, so neither
;     is in register_table: each has a one-row table of its own, asked only
;     where this code used to go straight to error_not_a_form. 103 has the
;     measurements, and the warning that the value ED 71 writes is not
;     0 on these machines.

assemble_in:	ld	hl,register_table	; the register comes first here
		call	find_operand_word
		jr	nc,assemble_in.register
		ld	hl,in_f_table	; not a register: "IN F,(C)" is the
		call	find_operand_word
					;   only other first operand there is
		jp	c,error_not_a_form
assemble_in.register:
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		ld	(insn_saved_code),a
					; read_operand clobbers every register
		call	expect_comma
		jp	c,error_not_a_form
		call	read_port
		ld	a,(insn_saved_code)
		ld	b,0dbh		; "in a,(n)" is DB n
		ld	c,040h		; "in r,(c)" is ED 40h + 8*r
		jp	emit_in_out

assemble_out:	call	read_port	; and the port comes first here
		call	expect_comma
		jp	c,error_not_a_form
		ld	hl,register_table
		call	find_operand_word
		jr	nc,assemble_out.register
		ld	hl,out_0_table	; not a register: "OUT (C),0" is the
		call	find_operand_word	;   only other second operand
		jp	c,error_not_a_form
assemble_out.register:
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		jp	nz,error_not_a_form
		ld	a,(operand_code)
					; no need to keep it: nothing runs
		ld	b,0d3h		;   between here and emit_in_out
		ld	c,041h		; "out (n),a" is D3 n, "out (c),r"
		jp	emit_in_out	;   is ED 41h + 8*r

; read_port - the port half of an IN or an OUT: "(C)" or "(n)", and
;   nothing else.
;
;   Both are OPERAND_MEMORY, because both are addresses to every other
;   instruction. What was inside the brackets is REMEMBERED rather than
;   reclassified, and it survives until the next read_operand - which is what
;   lets assemble_out ask about its first operand after parsing its second.
;
;   It also leaves the port EXPRESSION remembered, in expression_at, for the
;   "(n)" form to emit. assemble_out parses its register with
;   find_operand_word, which never calls skip_expression, so the port text is
;   still there when emit_in_out wants it - the same two-slot trick as "ld
;   (ix+d),n".
;
; Input:	nothing
; Output:	nothing, or it does not return
; Modifies:	AF, BC, DE, HL

read_port:	call	read_operand
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_MEMORY
		jp	nz,error_not_a_form
		ret

; emit_in_out - the half IN and OUT share.
;
;   (C) takes any of the eight registers; (n) takes the accumulator and
;   no other. "in b,(0aah)" is two legal operands and no instruction,
;   which is the same kind of refusal as "ld (bc),hl".
;
;   emit_byte modifies NOTHING, flags included, which is what lets B, C and
;   D hold the three things this routine needs across two of them.
;
; Input:	A = the register's code
;		B = the "(n)" form's opcode
;		C = the "(C)" form's base
;		the last read_operand was the port
; Output:	HL = 2
; Modifies:	AF, BC, DE, HL

emit_in_out:	ld	d,a		; the register's code, out of A's way
		call	operand_is_c	; was the port the literal "(C)"?
		jr	z,emit_in_out.port_c	; then any register goes
		ld	a,d
		cp	7
		jp	nz,error_not_a_form
		ld	a,b		; DBh or D3h, and the port is an
		call	emit_byte	;   ordinary byte-wide expression
		call	emit_saved_byte
		ret

emit_in_out.port_c:
		ld	a,0edh
		call	emit_byte
		ld	a,d
		call	base_plus_8x	; base + 8*r, C still holding the
		call	emit_byte	;   base emit_byte did not disturb
		ret

; --- CLASS_MULUB and CLASS_MULUW: the R800's two. Tatara assembles them on any
;     machine - what the source says does not depend on what the
;     assembler is running on - and they are the only two mnemonics in
;     the program with no oracle, because M80 does not know them.

assemble_mulub:	ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	7		; the accumulator and no other
		jp	nz,error_not_a_form
		call	expect_comma
		jp	c,error_not_a_form
		ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_BYTE	; any 8-bit register. (HL) cannot
		jp	nz,error_not_a_form
				;   arrive here at all: register_table has no
					;   entry for it, and only
					;   read_operand's bracket branch ever
					;   makes one
		ld	a,0edh
		call	emit_byte
		ld	a,(operand_code)
					; ED C1h + eight times the register
		rlca
		rlca
		rlca
		ld	hl,insn_base
		add	a,(hl)
		call	emit_byte
		ret

assemble_muluw:	ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_PAIR
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		cp	2		; HL is the only destination
		jp	nz,error_not_a_form
		call	expect_comma
		jp	c,error_not_a_form
		ld	hl,register_table
		call	find_operand_word
		jp	c,error_not_a_form
		ld	a,(operand_kind)
		cp	OPERAND_PAIR
		jp	nz,error_not_a_form
		ld	a,(operand_code)
		or	a
		ld	a,(insn_base)	; MULUW HL,BC is ED C3 - the row's
		jr	z,assemble_muluw.sp	;   base
		ld	a,(operand_code)
		cp	3		; MULUW HL,SP is ED F3, and there
		jp	nz,error_not_a_form	;   is no third form
		ld	a,0f3h
assemble_muluw.sp:
		ld	c,a
		ld	a,0edh
		call	emit_byte
		ld	a,c
		call	emit_byte
		ret

; --- every class has a handler now, so nothing in class_table points here.
;     It stays: a mistyped class byte in a future row would otherwise
;     jump to whatever the jump table happened to hold, and finding
;     THAT would cost an evening. It is the cheapest insurance in the
;     program - three bytes.

assemble_bad_class:
		jp	error_not_a_form

		dseg

insn_class:	defs	1	; what find_mnemonic answered: the class,
insn_base:	defs	1	;   and the base opcode
arith_prefix:	defs	1	; assemble_arith.ix: which index register the
				;   first operand was, since find_operand_word
				;   overwrites operand_prefix with the second
insn_saved_code:
		defs	1	; A CODE A HANDLER MUST KEEP across a
				;   parse that clobbers operand_code:
				;   assemble_in's register across the
				;   read_operand that reads the port, and JP's,
				;   JR's and CALL's opcode across
				;   skip_expression, which modifies BC so a
				;   register will not do. And
				;   assemble_ld.half's SOURCE prefix across the
				;   one store that replaces it with the
				;   destination's - a byte, not a code, and the
				;   same need
ld_dest_kind:	defs	1	; assemble_ld: what the destination was,
ld_dest_code:	defs	1	;   the code it gave, and the PREFIX
ld_dest_prefix:	defs	1	;   it forced, across the second
				;   read_operand call - which clears
				;   operand_prefix

; The two operands that are not registers, in register_table's row shape so
; that find_operand_word can read them: a length byte, the name in upper case,
; a kind and a code. BOTH ARE REGISTER CODE 6 - the slot (HL) occupies
; everywhere else - which is the whole reason ED 70 and ED 71 exist.
;
; TWO TABLES AND NOT ONE, for the reason register_table and condition_table are
; two: the handler knows what it is asking for. One table with both rows would
; accept "in 0,(c)" and "out (c),f", which are instructions nowhere.

in_f_table:	defb	1,	"F",	OPERAND_BYTE,	6
		defb	0		; the end of the table

out_0_table:	defb	1,	"0",	OPERAND_BYTE,	6
		defb	0		; the end of the table

; The jump table, one word per class, in the order of optab.inc. All
; twenty-one entries are here from the start so that the later notes
; replace one word each rather than renumbering anything.

class_table:	defw	assemble_no_operands	; CLASS_NONE
		defw	assemble_no_operands_ed	; CLASS_NONE_ED
		defw	assemble_alu	; CLASS_ALU
		defw	assemble_arith	; CLASS_ARITH
		defw	assemble_incdec	; CLASS_INCDEC
		defw	assemble_bit	; CLASS_BIT
		defw	assemble_rot	; CLASS_ROT
		defw	assemble_ld	; CLASS_LD
		defw	assemble_jp	; CLASS_JP
		defw	assemble_jr	; CLASS_JR
		defw	assemble_djnz	; CLASS_DJNZ
		defw	assemble_call	; CLASS_CALL
		defw	assemble_ret	; CLASS_RET
		defw	assemble_rst	; CLASS_RST
		defw	assemble_stack	; CLASS_STACK
		defw	assemble_ex	; CLASS_EX
		defw	assemble_in	; CLASS_IN
		defw	assemble_out	; CLASS_OUT
		defw	assemble_im	; CLASS_IM
		defw	assemble_mulub	; CLASS_MULUB
		defw	assemble_muluw	; CLASS_MULUW
