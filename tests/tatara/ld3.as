; C_LD: the pairs, SP and the index registers. "ld hl,(nn)" is THREE
; bytes and every other pair is four: 2Ah exists for HL alone, and
; choosing wrongly here is a wrong LENGTH, not a wasted byte
	aseg
	org	0
t0:	ld	bc,1234h
t1:	ld	sp,1234h
t2:	ld	hl,(1234h)
t3:	ld	de,(1234h)
t4:	ld	sp,(1234h)
t5:	ld	sp,hl
t6:	ld	sp,ix
t7:	ld	ix,1234h
t8:	ld	iy,(1234h)
t9:	nop
	end
