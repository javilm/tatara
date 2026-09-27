; before
	if	2*3 GT 5
	db	1
	endif
	if	2+3*4 EQ 14
	db	2
	endif
	if	(2+3)*4 EQ 20
	db	3
	endif
	if	0ffh EQ 255
	db	4
	endif
	if	NOT 0
	db	5
	endif
	ife	1 AND 2
	db	6
	endif
	if	'A' EQ 65
	db	7
	endif
	ret