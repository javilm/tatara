; JP: three bytes to an address, one to (HL), two to (IX)
t0:	jp	1234h
t1:	jp	nz,1234h
t2:	jp	m,1234h
t3:	jp	(hl)
t4:	jp	(ix)
t5:	jp	(iy)
t6:	nop
	end
