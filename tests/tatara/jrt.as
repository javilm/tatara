; JR, DJNZ and CALL: two bytes, two, and three
t0:	jr	t0
t1:	jr	nz,t0
t2:	jr	c,t0
t3:	djnz	t0
t4:	call	1234h
t5:	call	nc,1234h
t6:	call	pe,1234h
t7:	nop
	end
