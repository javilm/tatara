; a line that emits more than the eight-byte column holds. Once
; the listing showed eight and a "+", and the rest were in the buffer
; but never printed
	aseg
	org	0
t0:	db	"ABCDEFGHIJKLMNOPQRST"
t1:	nop
	end
