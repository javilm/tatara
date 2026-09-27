; the first RELATIVE displacements. Measured from the address AFTER
; the instruction, so "t2: djnz t2" is -2 and not 0 - which is the
; arithmetic most likely to be out by exactly the length of the
; instruction
	aseg
	org	0
t0:	jr	t1
t1:	jr	t0
t2:	djnz	t2
t3:	jr	nz,t4
t4:	jr	c,t3
t5:	nop
	end
