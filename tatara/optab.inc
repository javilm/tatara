; optab.inc - public interface of optab.as: the instruction table, its
; lookup, and the cursor the operand parser walks.
;
; optab.as includes this file too: it defines OPTAB_INCLUDED first, which skips
; the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.
;
; The table holds one row per MNEMONIC: a CLASS, which says which family
; of operand shapes the instruction belongs to, and a BASE opcode, which
; the class handler folds the operand codes into. The grammar lives in
; the handlers (insn.as), not in the table. optable-design.md has the
; reasoning, and 5 of it has the arithmetic that chose this shape over a
; row per operand form.

		ifndef	OPTAB_INCLUDED

		extrn find_mnemonic	; is this operation a mnemonic?
					; in:  DE -> the operation text
					;      B  = how long it is
					; out: CY set = no such mnemonic
					;      A  = its class
					;      C  = its base opcode
		extrn operand_start	; point the operand cursor at this
					; line's operand field
					; in:  DE -> the operand text
					;      A  = how long it is
		extrn operand_skip_blanks
					; step the cursor over blanks and
					; tabs
		extrn operand_must_end	; the operand field must have
					; nothing left in it
					; (error_not_a_form does not return)
		extrn find_operand_word	; is the word at the cursor one of
					; this table's?
					; in: HL -> register_table or
					; condition_table out: CY set = no, and
					; the cursor has not moved
					; operand_kind, operand_code and, for
					; IX and IY, operand_prefix are set
		extrn read_byte_source	; an 8-bit source: a register,
					; (HL), or an indexed operand
					; out: CY set = none of those, and
					;          the cursor has not moved
		extrn skip_expression	; step over an expression: pass 1
					; does not read it
					; out: CY set = there was nothing
					;          there
		extrn expect_comma	; step over a comma
					; out: CY set = there is none here
		extrn operand_advance	; step the cursor on by A
					; characters
					; in:  A = how many
					; out: A is unchanged
		extrn operand_at_end	; is anything left in the operand
					; field?
					; out: Z set = nothing is
		extrn read_operand	; what is the operand at the
					; cursor? It names anything the Z80
					; has, and calls whatever it cannot
					; name an expression - so the carry
					; means only "there is nothing here"
					; out: CY set = nothing at all
					;      operand_kind, operand_code and
					;      operand_prefix describe it
		extrn skip_quoted_run	; step the cursor over a quoted
					; run, opening delimiter to closing
		extrn condition_and_comma
					; a condition AND the comma after
					; it - the two together, because a
					; condition without one is a symbol
					; out: CY set = it was not that, and
					;          the cursor has not moved
					;      operand_code = the condition
					;      code
		extrn operand_is_c	; was the operand read_operand last
					; returned the literal "(C)"?
					; out: Z set = yes
		extrn operand_is_sp	; ... the literal "(SP)"?
					; out: Z set = yes
		extrn no_displacement	; did the indexed operand read_operand
					; last returned carry NO
					; displacement? Only JP asks
					; out: Z set = there was none
		extrn expression_text
				; the text skip_expression stepped over, for a
					; handler that parses everything and
					; THEN emits - by which time the
					; cursor is past it
					; out: DE -> it, A = how long
		extrn displacement_text
				; the same for read_displacement's displacement
					; out: DE -> it, A = how long,
					;      and A = 0 = there was none
		extrn operand_restore	; put the cursor back to where
					; read_operand found the last operand,
					; so that the same text can be read as
					; an expression instead. operand_save
					; is NOT exported and must not be: only
					; read_operand may write the slot, and
					; a caller may only wind back to it
		extrn operand_kind	; A BYTE: what the last operand was
		extrn operand_code	; A BYTE: the register, pair or
					; condition code it contributes
		extrn operand_prefix	; A BYTE: 0, 0DDh or 0FDh - the
					; prefix it forces
		extrn register_table	; the operand words
		extrn condition_table	; the conditions
		endif

; --- what an operand turned out to be. An operand is never classified
;     out of context: the HANDLER knows which table to ask, which is why
;     C is register code 1 in register_table and condition code 3 in
;     condition_table and neither of them has to be a special case.

OPERAND_BYTE	equ	1	; B C D E H L A, or (HL): code 0-7
OPERAND_INDEXED	equ	2	; (IX+d) or (IY+d): code 6 and a prefix
OPERAND_PAIR	equ	3	; BC DE HL SP: code 0-3
OPERAND_IX	equ	4	; IX or IY as a 16-bit register
OPERAND_AF	equ	5	; AF: code 3, and only PUSH and POP take it
OPERAND_AF_ALT	equ	6	; AF' - EX wants it,
OPERAND_COND	equ	7	; a condition: code 0-7
OPERAND_I	equ	8	; the interrupt vector register
OPERAND_R	equ	9	; the refresh register
OPERAND_MEMORY	equ	10	; (expression) - an address
OPERAND_AT_BC	equ	11	; (BC), which only LD reads
OPERAND_AT_DE	equ	12	; (DE), the same
OPERAND_IMM	equ	13	; a plain expression
OPERAND_HALF	equ	14	; AN INDEX HALF - IXH, IXL, IYH or IYL.
				;   (operand_code) is 4 or 5, which are H's
				;   code and L's, and (operand_prefix) says
				;   which index register. This is what
				;   find_operand_word leaves, and the only one
				;   of the three below a handler ever sees
OPERAND_IX_HALF	equ	15	; the table's two: a half of IX, and a
OPERAND_IY_HALF	equ	16	;   half of IY. THE CODE COLUMN HOLDS THE
				;   REGISTER CODE here - the other way round
				;   from OPERAND_IX, where the pair code is
				;   always 2 so the column holds the prefix
				;   instead. find_operand_word turns either of
				;   these into OPERAND_HALF plus the prefix the
				;   kind names, and neither is seen outside it

; (SP) AND (C) have no kinds of their own, and must not get them: M80
; assembles "ld a,(c)" as 3A nn when C is a symbol, so a kind for (C)
; would refuse a line M80 accepts. read_operand REMEMBERS what register_table
; said about the word inside the brackets instead, and operand_is_c and
; operand_is_sp are the only two things that ever ask. EX, IN and OUT are the
; only three instructions that need to.

; --- the classes. The numbers match optable-design.md 15 and DO NOT
;     CHANGE: a note adds handlers to this list, it does not renumber
;     it. The note that implements each one is named beside it.

CLASS_NONE	equ	1	; no operands
CLASS_NONE_ED	equ	2	; no operands, an ED in front
CLASS_ALU	equ	3	; SUB AND XOR OR CP
CLASS_ARITH	equ	4	; ADD ADC SBC
CLASS_INCDEC	equ	5	; INC DEC
CLASS_BIT	equ	6	; BIT RES SET
CLASS_ROT	equ	7	; RLC RRC RL RR SLA SRA SRL
CLASS_LD	equ	8	; LD, on its own
CLASS_JP	equ	9
CLASS_JR	equ	10
CLASS_DJNZ	equ	11
CLASS_CALL	equ	12
CLASS_RET	equ	13
CLASS_RST	equ	14
CLASS_STACK	equ	15	; PUSH POP
CLASS_EX	equ	16
CLASS_IN	equ	17
CLASS_OUT	equ	18
CLASS_IM	equ	19
CLASS_MULUB	equ	20	; the R800's
CLASS_MULUW	equ	21	; the R800's

CLASS_MAX	equ	21	; how many entries class_table has
