; BEEP.AS - a machine-code file for MSX BASIC.
;
; BLOAD"BEEP.BIN",R loads this and runs it. The seven bytes BASIC
; reads first - FEh, the first address, the LAST address, and the
; address to call - are written by TANREN when /B is given, and
; nothing else makes a file a .BIN.
;
; ASEG and ORG: the code is at a fixed address and the linker moves
; nothing. It has to be, because BASIC loads it where the header says
; and does not relocate anything.
;
; There is no MSX-DOS here, so the printing is the BIOS.

CHPUT		equ	00a2h		; BIOS: print the character in A
BEEP		equ	00c0h		; BIOS: the beep

		aseg
		org	8000h		; above BASIC in a 64 KB machine

start:		ld	hl,msg
loop:		ld	a,(hl)
		or	a
		jr	z,done
		push	hl
		call	CHPUT
		pop	hl
		inc	hl
		jr	loop
done:		call	BEEP
		ret			; back to BASIC, which is waiting

msg:		db	"Loaded by BLOAD, run from BASIC.",13,10,0

		end	start		; the address the header carries
