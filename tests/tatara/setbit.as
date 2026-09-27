; SET is the bit instruction and ONLY that. M80 has no SET pseudo-op
; in .Z80 mode - "foo set 5" is a fatal error there - and DEFL is the
; redefinable symbol. The opposite was assumed once and M80 said no
foo	defl	5
t0:	set	7,a
	set	1,b
t1:	set	0,(hl)
foo	defl	7
t2:	nop
	end
