; DB and DW, emitting: numbers, strings, and a character constant
	aseg
	org	0
t0:	db	1,2,3
t1:	db	'abc'
t2:	db	'A'+1
t3:	dw	1234h
t4:	dw	'AB'
t5:	nop
	end
