; fcondlab.as - a LABEL and an EQU inside a branch that is not taken.
; M80 lists both with the address column blank and defines neither;
; before 085 Tatara printed the location counter on each.

	if	0
lab:	ret
val	equ	5
	endif
t0:	db	3
	end
