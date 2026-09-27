; does M80 list the lines inside a branch it did not take? The
; first block says yes explicitly, the second says no - and what M80
; does with NEITHER said is the default this test is really asking for
	.lfcond
	if	0
	db	1
	endif
	.sfcond
	if	0
	db	2
	endif
	end
