; expr.inc - public interface of expr.as: expressions and their values.
;
; expr.as includes this file too, for the shared equates: it defines
; EXPRLIB first, which skips the external declarations below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	EXPRLIB
		extrn exinit		; point exlook at the pass-0 table and
					;   empty it. Per PASS
		extrn evalexp		; the value of an expression
					; in:  DE -> the text, A = its length
					; out: HL = the value, exty = its type
		extrn evalabs		; the same, and it must be ABSOLUTE:
					;   errrel otherwise. DS, REPT
		extrn exlook		; the ADDRESS of the routine that
					;   looks a symbol up. Pass 1 stores
					;   pass 1's here
		extrn exty		; the type of the last value
		extrn exeidx		; A WORD: if that type is SYTEXT,
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
;     by segsel in the order contributions are first named. Three are
;     fixed, because seginit creates them first and expr.as tests "both
;     absolute" by ORing two of them - so SY_ABS MUST stay 0.
;
;     An EXTERNAL is not a place but a property, and lives in the
;     symbol's flags byte as SYF_EXT (symtab.inc).

SY_ABS		equ	0	; a plain number                   (ASEG)
SY_CODE		equ	1	; the classic unnamed code segment (CSEG)
SY_DATA		equ	2	; the classic unnamed data segment (DSEG)
				; 3 and up: named segments, in order

; --- and one type code that is NOT a segment: a value whose worth
;     another module promises. It lives in exty only, never in a
;     symbol's SY_TYPE - a record says external in its FLAGS, because a
;     symbol can be external and have a segment at the same time. 0FFh
;     is free here because no segment index ever reaches it: MAXSEGS
;     stops at 0FEh.

SYTEXT		equ	0ffh	; external, inside an expression
