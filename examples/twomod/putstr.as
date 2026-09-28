; PUTSTR.AS - the other module.
;
; PUBLIC is what makes the name visible outside this file. Without it
; the name would still assemble here and the link of MAIN.AS would
; stop with an undefined symbol - which is worth trying once.

		public	putstr

		include	msxdos.inc	; BDOS, _CONOUT and "system"

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
		system	_CONOUT
		pop	hl
		inc	hl
		jr	putstr

		end
