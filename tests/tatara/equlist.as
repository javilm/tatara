; what does M80 put in the address column for EQU and DEFL? A
; label is there, so Tatara shows the location counter - and I think
; M80 shows the VALUE.
foo	equ	5
bar	defl	7
t0:	db	foo
	db	bar
	end
