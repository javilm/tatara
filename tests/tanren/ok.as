; the driver of the fixup test. It asks for MSG+1, so the word
; in the object file holds 0001 and not 0000; and it calls a routine
; in the module behind it.
	public	start
	extrn	second
	cseg
start:	ld	hl,msg+1
	call	second
	ret
	dseg
msg:	defb	"xOK $"
	end	start
