; CLASS_LD: indexed, in both directions. t2 is the one form that emits
; from BOTH operands - the displacement from the destination and the
; immediate from the source - and t5 is a bare "(ix)", which is
; "(ix+0)" and the first test to write one
	aseg
	org	0
t0:	ld	b,(ix+5)
t1:	ld	(ix+5),b
t2:	ld	(ix+5),42h
t3:	ld	c,(iy-1)
t4:	ld	(iy-1),c
t5:	ld	a,(ix)
t6:	nop
	end
