; two bytes can hold a relocatable value - the hole takes the addend
; and the linker adds the segment. ONE byte cannot
	cseg
t0:	dw	t0
t1:	nop
	end
