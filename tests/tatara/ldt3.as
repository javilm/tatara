; the accumulator's own forms: (BC), (DE), (nn), I and R
t0:	ld	a,(bc)
t1:	ld	(de),a
t2:	ld	a,(1234h)
t3:	ld	(5678h),a
t4:	ld	a,i
t5:	ld	r,a
t6:	ret
	end
