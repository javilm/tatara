; HELLO.AS - the smallest complete program.
;
; One source, one object, one .COM. It prints a line and gives the
; machine back to MSX-DOS.

BDOS		equ	0005h		; where MSX-DOS is called
_STROUT		equ	09h		; print the string at DE, up to a $
_TERM0		equ	00h		; terminate, no error

		cseg			; RELOCATABLE code. Nothing here
					;   knows its own address, and the
					;   linker chooses one - 0100h for a
					;   .COM, unless /P: says otherwise

start:		ld	de,msg
		ld	c,_STROUT
		call	BDOS
		ld	c,_TERM0
		jp	BDOS

msg:		db	"Hello from Tatara.",13,10,"$"

		end	start		; where it starts, for the linker
