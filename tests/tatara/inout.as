; IN and OUT: two bytes, and the port decides which register is legal
t0:	in	a,(0aah)
t1:	in	b,(c)
t2:	in	a,(c)
t3:	out	(0aah),a
t4:	out	(c),e
t5:	nop
	end
