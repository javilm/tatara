; one fixup of each kind, and an entry point. Read the DATA
; record against the RELOC entries: every hole holds its ADDEND and
; nothing else, and each entry says what to add to it
	extrn	bar
	cseg
t0:	ld	hl,t0
	ld	hl,bar
	ld	hl,bar+5
	dw	t0+3
	end	t0
