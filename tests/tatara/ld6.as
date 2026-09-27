; the first INSTRUCTION to carry a relocatable operand. emitxw was proved
; emitxw on a DW; this is the same routine with a different caller,
; and the listing marks both addresses
	cseg
t0:	ld	hl,t2
t1:	ld	(t2),a
t2:	nop
	end
