; CLASS_LD: I and R. register_table gives both of them code 0, so only the KIND
; tells them apart - and the two pairs are one expression each:
; 57h + 8*(kind - OPERAND_I) and 47h + 8*(kind - OPERAND_I)
	aseg
	org	0
t0:	ld	a,i
t1:	ld	a,r
t2:	ld	i,a
t3:	ld	r,a
t4:	nop
	end
