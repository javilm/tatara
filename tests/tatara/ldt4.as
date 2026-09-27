; the sixteen-bit forms, and HL's short ones
t0:	ld	bc,1234h
t1:	ld	ix,5678h
t2:	ld	hl,(1000h)
t3:	ld	de,(1002h)
t4:	ld	(1004h),hl
t5:	ld	(1006h),sp
t6:	ld	sp,hl
t7:	ld	sp,iy
t8:	ret
	end
