; two segments, a public, an external and a fixup - one of every
; record type the dump has an arm for, except GRPDEF and COMMENT.
	public	start
	extrn	putstr
	cseg
start:	ld	hl,msg		; a segment-relative fixup
	call	putstr		; an external fixup
	ret
	dseg
msg:	defb	"Hi$"
	end	start
