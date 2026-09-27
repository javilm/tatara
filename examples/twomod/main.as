; MAIN.AS - one of two modules.
;
; It knows that putstr exists. It does not know where putstr is, and
; it does not need to: EXTRN says the name is somebody else's, and the
; linker fills the address in.

		extrn	putstr		; defined in PUTSTR.AS

BDOS		equ	0005h
_TERM0		equ	00h

		cseg

start:		ld	hl,msg1
		call	putstr
		ld	hl,msg2
		call	putstr
		ld	c,_TERM0
		jp	BDOS

msg1:		db	"Two modules, one program.",13,10,0
msg2:		db	"The linker joined them.",13,10,0

		end	start
