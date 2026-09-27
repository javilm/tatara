; optab.inc - public interface of optab.as: the instruction table, its
; lookup, and the cursor the operand parser walks.
;
; optab.as includes this file too: it defines OPTLIB first, which skips
; the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.
;
; The table holds one row per MNEMONIC: a CLASS, which says which family
; of operand shapes the instruction belongs to, and a BASE opcode, which
; the class handler folds the operand codes into. The grammar lives in
; the handlers (insn.as), not in the table. optable-design.md has the
; reasoning, and 5 of it has the arithmetic that chose this shape over a
; row per operand form.

		ifndef	OPTLIB

		extrn opfind		; is this operation a mnemonic?
					; in:  DE -> the operation text
					;      B  = how long it is
					; out: CY set = no such mnemonic
					;      A  = its class
					;      C  = its base opcode
		extrn opinit		; point the operand cursor at this
					; line's operand field
					; in:  DE -> the operand text
					;      A  = how long it is
		extrn opskip		; step the cursor over blanks and
					; tabs
		extrn opnone		; the operand field must have
					; nothing left in it
					; (erroper does not return)
		extrn opword		; is the word at the cursor one of
					; this table's?
					; in:  HL -> regtab or cctab
					; out: CY set = no, and the cursor
					;          has not moved
					;      opkind, opcod and, for IX
					;          and IY, opfix are set
		extrn opr8		; an 8-bit source: a register,
					; (HL), or an indexed operand
					; out: CY set = none of those, and
					;          the cursor has not moved
		extrn opexp		; step over an expression: pass 1
					; does not read it
					; out: CY set = there was nothing
					;          there
		extrn opcomma		; step over a comma
					; out: CY set = there is none here
		extrn opadv		; step the cursor on by A
					; characters
					; in:  A = how many
					; out: A is unchanged
		extrn opend		; is anything left in the operand
					; field?
					; out: Z set = nothing is
		extrn opany		; what is the operand at the
					; cursor? It names anything the Z80
					; has, and calls whatever it cannot
					; name an expression - so the carry
					; means only "there is nothing here"
					; out: CY set = nothing at all
					;      opkind, opcod and opfix
					;          describe it
		extrn opqrun		; step the cursor over a quoted
					; run, opening delimiter to closing
		extrn opccm		; a condition AND the comma after
					; it - the two together, because a
					; condition without one is a symbol
					; out: CY set = it was not that, and
					;          the cursor has not moved
					;      opcod = the condition code
		extrn opisc		; was the operand opany last
					; returned the literal "(C)"?
					; out: Z set = yes
		extrn opissp		; ... the literal "(SP)"?
					; out: Z set = yes
		extrn opnodsp			; did the indexed operand opany
					; last returned carry NO
					; displacement? Only JP asks
					; out: Z set = there was none
		extrn opxtext		; the text opexp stepped over, for a
					; handler that parses everything and
					; THEN emits - by which time the
					; cursor is past it
					; out: DE -> it, A = how long
		extrn opdtext		; the same for opdisp's displacement
					; out: DE -> it, A = how long,
					;      and A = 0 = there was none
		extrn oprest		; put the cursor back to where
					; opany found the last operand, so
					; that the same text can be read
					; as an expression instead.
					; opsave is NOT exported and must
					; not be: only opany may write the
					; slot, and a caller may only
					; wind back to it
		extrn opkind		; A BYTE: what the last operand was
		extrn opcod		; A BYTE: the register, pair or
					; condition code it contributes
		extrn opfix		; A BYTE: 0, 0DDh or 0FDh - the
					; prefix it forces
		extrn regtab		; the operand words
		extrn cctab		; the conditions
		endif

; --- what an operand turned out to be. An operand is never classified
;     out of context: the HANDLER knows which table to ask, which is why
;     C is register code 1 in regtab and condition code 3 in cctab and
;     neither of them has to be a special case.

OK_R8		equ	1	; B C D E H L A, or (HL): code 0-7
OK_IDX		equ	2	; (IX+d) or (IY+d): code 6 and a prefix
OK_RR		equ	3	; BC DE HL SP: code 0-3
OK_IX		equ	4	; IX or IY as a 16-bit register
OK_AF		equ	5	; AF: code 3, and only PUSH and POP take it
OK_AFP		equ	6	; AF' - EX wants it,
OK_CC		equ	7	; a condition: code 0-7
OK_I		equ	8	; the interrupt vector register
OK_R		equ	9	; the refresh register
OK_MEM		equ	10	; (expression) - an address
OK_MBC		equ	11	; (BC), which only LD reads
OK_MDE		equ	12	; (DE), the same
OK_IMM		equ	13	; a plain expression

; (SP) AND (C) have no kinds of their own, and must not get them: M80
; assembles "ld a,(c)" as 3A nn when C is a symbol, so a kind for (C)
; would refuse a line M80 accepts. opany REMEMBERS what regtab said
; about the word inside the brackets instead, and opisc and opissp are
; the only two things that ever ask. EX, IN and OUT are the only three
; instructions that need to.

; --- the classes. The numbers match optable-design.md 15 and DO NOT
;     CHANGE: a note adds handlers to this list, it does not renumber
;     it. The note that implements each one is named beside it.

C_NONE		equ	1	; no operands
C_NONED		equ	2	; no operands, an ED in front
C_ALU		equ	3	; SUB AND XOR OR CP
C_ALUA		equ	4	; ADD ADC SBC
C_INCDEC	equ	5	; INC DEC
C_BIT		equ	6	; BIT RES SET
C_ROT		equ	7	; RLC RRC RL RR SLA SRA SRL
C_LD		equ	8	; LD, on its own
C_JP		equ	9
C_JR		equ	10
C_DJNZ		equ	11
C_CALL		equ	12
C_RET		equ	13
C_RST		equ	14
C_STACK		equ	15	; PUSH POP
C_EX		equ	16
C_IN		equ	17
C_OUT		equ	18
C_IM		equ	19
C_MULUB		equ	20	; the R800's
C_MULUW		equ	21	; the R800's

CLSMAX		equ	21	; how many entries clstab has
