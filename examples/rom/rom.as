; ROM.AS - a 16 KB cartridge.
;
; A cartridge in page 1 begins at 4000h with a sixteen-byte header.
; The BIOS looks for the letters AB, and calls the INIT address if it
; is not zero - before there is an operating system of any kind.
;
; NOTHING HERE MAY CALL MSX-DOS. There is no MSX-DOS yet. The screen
; and the printing are the BIOS, and the code never returns, because
; there is nothing to return to.
;
; THE LAST TWO LINES ARE WHAT MAKES THE FILE 16 KB. TANREN writes the
; span from the lowest byte of content to the highest, and a gap
; inside that span comes out as zeros. One byte at 7FFFh therefore
; makes the file exactly 16384 bytes, which is what a cartridge has
; to be. A DS would not do it: the space a DS reserves after the last
; byte of content is deliberately not in the file.

		include	bios.inc	; INITXT, CHPUT, and the rest

		aseg
		org	4000h

		db	"AB"		; a cartridge, says the BIOS
		dw	init		; INIT: called at once
		dw	0		; STATEMENT: no CALL statements
		dw	0		; DEVICE: no device
		dw	0		; TEXT: no BASIC program in here
		dw	0,0,0		; reserved, and zero

init:		call	INITXT		; a text screen, from nothing
		ld	hl,msg
ini.lp:		ld	a,(hl)
		or	a
		jr	z,ini.end
		push	hl
		call	CHPUT
		pop	hl
		inc	hl
		jr	ini.lp
ini.end:	jr	ini.end		; a cartridge has nowhere to go

msg:		db	"Assembled by Tatara. Linked by TANREN.",13,10,0

		org	7fffh		; the last byte of the 16 KB...
		db	0		;   ...so that the file is all of it

		end
