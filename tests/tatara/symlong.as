; name lengths 1, 2, 31, 32, 33, 120 and 240, all read back
a	defl	1
ab	defl	2
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb	defl	31
cccccccccccccccccccccccccccccccc	defl	32
ddddddddddddddddddddddddddddddddd	defl	33
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee	defl	120
ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff	defl	1
	if	a EQ 1
	db	1
	endif
	if	ab EQ 2
	db	2
	endif
	if	bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb EQ 31
	db	31
	endif
	if	cccccccccccccccccccccccccccccccc EQ 32
	db	32
	endif
	if	ddddddddddddddddddddddddddddddddd EQ 33
	db	33
	endif
	if	eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee EQ 120
	db	120
	endif
	if	ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff EQ 1
	db	240
	endif
	ret
