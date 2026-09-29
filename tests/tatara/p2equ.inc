; p2equ.inc - a guarded include holding nothing but equates. Correct,
; and skipped on pass 2 exactly as P2LAB.INC is.

		ifndef	p2equ_inc
p2equ_inc	equ	1
five		equ	5
		endif
