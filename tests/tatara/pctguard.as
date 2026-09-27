; the MAKERR/MAKLAB shape from the manual, which needs %
lb	defl	1
maklab	macro	y
	db	'Error &y',0
	endm
	maklab	%lb
	ret
