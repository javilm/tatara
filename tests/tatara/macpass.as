; a macro CALLED before it is DEFINED is an ERROR. On pass 0 the name
; is not a macro yet, and a word that is not a directive, a
; macro or an instruction is not text either
	poke	4000h
poke	macro	addr
	ld	(addr),hl
	endm
	poke	8000h
	ret
