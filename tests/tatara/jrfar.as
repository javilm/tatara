; -128 to 127 from the address after the instruction, and no long
; form to fall back on
	aseg
	org	0
far	equ	200h
t0:	jr	far
	end
