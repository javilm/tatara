; PUTSTR.AS - the other module.
;
; PUBLIC is what makes the name visible outside this file. Without it
; the name would still assemble here and the link of MAIN.AS would
; stop with an undefined symbol - which is worth trying once.

		public	putstr

BDOS		equ	0005h
_CONOUT		equ	02h		; print the character in E

		cseg

; putstr - print a string.
;
;   HL is pushed around the BDOS call because MSX-DOS promises nothing
;   about the registers it hands back.
;
; Input:	HL -> the string, ending in a zero byte
; Output:	it is printed
; Modifies:	AF, BC, DE, HL

putstr:		ld	a,(hl)
		or	a
		ret	z
		push	hl
		ld	e,a
		ld	c,_CONOUT
		call	BDOS
		pop	hl
		inc	hl
		jr	putstr

		end
