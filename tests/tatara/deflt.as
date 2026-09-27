count	defl	0
rep	macro
count	defl	count+1
	if	count EQ 1
	db	11h
	endif
	if	count EQ 2
	db	22h
	endif
	if	count EQ 3
	db	33h
	endif
	endm
	rep
	rep
	rep
	ifdef	count
	db	0aah
	endif
	ifndef	nosuch
	db	0bbh
	endif
	ret
