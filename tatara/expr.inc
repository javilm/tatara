; expr.inc - public interface of expr.as: expressions and their values.
;
; expr.as includes this file too, for the shared equates: it defines
; EXPR_INCLUDED first, which skips the external declarations below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	EXPR_INCLUDED
		extrn expr_init	; point symbol_lookup at the pass-0 table and
					;   empty it. Per PASS
		extrn eval_expression	; the value of an expression
					; in:  DE -> the text, A = its length
					; out: HL = the value, value_type = its
					; type
		extrn eval_absolute	; the same, and it must be ABSOLUTE:
					;   error_relocation otherwise. DS,
					;   REPT
		extrn is_name_char	; may this character appear in a
					;   name? Z set = yes
					; in:  A = the character
		extrn symbol_lookup	; the ADDRESS of the routine that
					;   looks a symbol up. Pass 1 stores
					;   pass 1's here
		extrn value_type	; the type of the last value
		extrn external_index	; A WORD: if that type is SY_EXTERNAL,
					; the external's INDEX. The value
					; itself is the addend, which is
					; what goes in the word; the
					; RELOC record carries this
		endif

; --- the operators, numbered. The number is only ever compared against
;     these names, so the order is free; they are grouped the way the
;     manual lists them so that a missing one is easy to spot.

OP_MUL		equ	1	; *
OP_DIV		equ	2	; /
OP_MOD		equ	3	; MOD
OP_SHR		equ	4	; SHR
OP_SHL		equ	5	; SHL
OP_ADD		equ	6	; +
OP_SUB		equ	7	; -
OP_EQ		equ	8	; EQ
OP_NE		equ	9	; NE
OP_LT		equ	10	; LT
OP_LE		equ	11	; LE
OP_GT		equ	12	; GT
OP_GE		equ	13	; GE
OP_AND		equ	14	; AND
OP_OR		equ	15	; OR
OP_XOR		equ	16	; XOR
OP_NOT		equ	17	; NOT   - unary
OP_HIGH		equ	18	; HIGH  - unary
OP_LOW		equ	19	; LOW   - unary

; --- what a value is relative to: a SEGMENT INDEX, handed out
;     by select_contribution in the order contributions are first named. Three
;     are fixed, because segment_table_init creates them first and expr.as
;     tests "both absolute" by ORing two of them - so SY_ABS MUST stay 0.
;
;     An EXTERNAL is not a place but a property, and lives in the
;     symbol's flags byte as SYMBOL_EXTERNAL (symtab.inc).

SY_ABS		equ	0	; a plain number                   (ASEG)
SY_CODE		equ	1	; the classic unnamed code segment (CSEG)
SY_DATA		equ	2	; the classic unnamed data segment (DSEG)
				; 3 and up: named segments, in order

; --- and one type code that is NOT a segment: a value whose worth
;     another module promises. It lives in value_type only, never in a
;     symbol's SYMBOL_TYPE - a record says external in its FLAGS, because a
;     symbol can be external and have a segment at the same time. 0FFh
;     is free here because no segment index ever reaches it: SEGMENT_MAX
;     stops at 0FEh.

SY_EXTERNAL	equ	0ffh	; external, inside an expression
