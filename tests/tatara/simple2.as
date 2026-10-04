; CLASS_ALU: a register, (HL), an indexed operand, an immediate
	aseg
	org	0
t0:	and	b
t1:	and	(hl)
t2:	and	(ix+5)
t3:	and	7
t4:	cp	a
t5:	xor	(iy-1)
t6:	nop
	end
