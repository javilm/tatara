; a displacement between two contributions is not a number: the linker
; places them independently and no record can fix up a relative byte.
; Tatara says error_relocation and M80 has the casting vote
	cseg
t0:	jr	t1
	dseg
t1:	ds	1
	end
