; INC and DEC in both widths, then PUSH and POP
	aseg
	org	0
t0:	inc	b
t1:	dec	(hl)
t2:	inc	(ix+1)
t3:	inc	bc
t4:	dec	iy
t5:	push	af
t6:	pop	ix
t7:	nop
	end
