; C_LD: the destination is a register or (HL). Register code 6 IS
; (HL), which is why "ld (hl),(hl)" has to be refused: that encoding
; is HALT
	aseg
	org	0
t0:	ld	b,c
t1:	ld	b,(hl)
t2:	ld	(hl),b
t3:	ld	b,5
t4:	ld	(hl),5
t5:	ld	a,(bc)
t6:	ld	a,(de)
t7:	ld	(bc),a
t8:	ld	(de),a
t9:	nop
	end
