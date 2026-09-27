; C_LD: the destination is an address. The same asymmetry as LD3 the
; other way round - 22h is HL alone - and the address is the
; DESTINATION's expression, remembered before the source was parsed
	aseg
	org	0
t0:	ld	(1234h),a
t1:	ld	(1234h),hl
t2:	ld	(1234h),bc
t3:	ld	(1234h),sp
t4:	ld	(1234h),ix
t5:	ld	a,(1234h)
t6:	nop
	end
