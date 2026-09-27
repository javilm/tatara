; DC puts the high bit on the last character and only the last
	aseg
	org	0
t0:	dc	'abc'
t1:	dc	'a'
t2:	nop
	end
