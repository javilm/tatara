; RET with a condition and without, then RST and IM
	aseg
	org	0
t0:	ret
t1:	ret	z
t2:	ret	m
t3:	rst	38h
t4:	im	0
t5:	im	1
t6:	im	2
t7:	nop
	end
