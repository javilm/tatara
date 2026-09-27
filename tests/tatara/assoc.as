; left association, and how far a prefix operator reaches
	if	8-3-2 EQ 3
	db	1
	endif
	if	8-3-2 EQ 7
	db	0ffh
	endif
	if	NOT 1 EQ 2
	db	2
	endif
	if	-2*3 EQ 0fffah
	db	3
	endif
	if	HIGH 1234h EQ 12h
	db	4
	endif
	if	1 SHL 3 EQ 8
	db	5
	endif
	if	5 MOD 3 EQ 2
	db	6
	endif
	ret
