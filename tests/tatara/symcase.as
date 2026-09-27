; the same source read in both case modes
foo	defl	1
FOO	defl	2
	if	foo EQ 1
	db	0aah
	endif
	if	foo EQ 2
	db	0bbh
	endif
bar	macro
	db	0cch
	endm
	BAR
	ret
