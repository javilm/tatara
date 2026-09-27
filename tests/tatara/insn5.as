; INC and DEC take both widths; PUSH and POP take the stack set
t0:	inc	b
t1:	inc	(hl)
t2:	inc	(ix+1)
t3:	inc	bc
t4:	dec	iy
t5:	push	af
t6:	pop	ix
t7:	rst	38h
t8:	im	1
	end
