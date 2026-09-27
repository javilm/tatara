; b.as - contributes to the code segment only, so CODE's total
; is the sum of two modules and DATA's is not.
	public	bstart
	extrn	astart
	cseg
bstart:	call	astart
	ret
	end
