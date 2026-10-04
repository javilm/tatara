; the first INSTRUCTION with a relocatable operand. emit_expr_word was proved
; emit_expr_word on a DW; this is the same routine with a different caller,
; and the listing marks both addresses
	cseg
t0:	ld	hl,t2
t1:	ld	(t2),a
t2:	nop
	end
