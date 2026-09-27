; the bit number is part of the opcode - 40h + 8*b - so an eighth bit
; would encode as some other instruction entirely
	aseg
	org	0
t0:	bit	8,b
	end
