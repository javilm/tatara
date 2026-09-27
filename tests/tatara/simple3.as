; C_ALUA: the 8-bit form, and the three 16-bit ones
	aseg
	org	0
t0:	add	a,b
t1:	add	hl,de
t2:	adc	hl,de
t3:	sbc	hl,sp
t4:	add	ix,bc
t5:	add	ix,ix
t6:	adc	a,(ix+0)
t7:	nop
	end
