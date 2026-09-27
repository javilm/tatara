; before
	if	1
	db	1
	else
	db	2
	endif
defarg	macro	a,b
	ifb	<b>
	ld	hl,0
	else
	ld	hl,b
	endif
	endm
	defarg	x
	defarg	x,1234h
	ifidn	<abc>,<ABC>
	db	'same'
	endif
	ifdif	<abc>,<xyz>
	db	'different'
	endif
	ret