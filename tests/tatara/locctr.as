; ORG, DS, and a label taking the location counter
	aseg
	org	100h
start:	ds	3
later:	ds	1
	if	start EQ 100h
	db	1
	endif
	if	later EQ 103h
	db	2
	endif
	ret
