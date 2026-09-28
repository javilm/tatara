; HELLO.AS - the smallest complete program.
;
; One source, one object, one .COM. It prints a line and gives the
; machine back to MSX-DOS.

		include	msxdos.inc	; BDOS, _STROUT, _TERM0 and the
					;   "system" macro, found through
					;   TATARA - see BUILD.BAT

		cseg			; RELOCATABLE code. Nothing here
					;   knows its own address, and the
					;   linker chooses one - 0100h for a
					;   .COM, unless /P: says otherwise

start:		ld	de,msg
		system	_STROUT
		ld	c,_TERM0
		jp	BDOS

msg:		db	"Hello from Tatara.",13,10,"$"

		end	start		; where it starts, for the linker
