; the CB group: two bytes, four when the operand is indexed
t0:	rlc	b
t1:	rrc	(hl)
t2:	srl	a
t3:	rl	(ix+5)
t4:	bit	7,a
t5:	res	0,(hl)
t6:	set	3,(iy-1)
t7:	nop
	end
