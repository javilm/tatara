; the other half of the object spec's worked example (6.1), and
; the routine TWO.AS has been calling into nothing.
;
; THE ex de,hl IS NOT IN THE SPEC'S VERSION. TWO.AS says "ld hl,msg"
; and BDOS function 09h takes its string in DE, so the example as
; printed would have printed whatever DE held. One byte, and it is
; why the linked image here is 16 bytes where section 6.5 says 15.
	public	putstr
_STROUT	equ	9		; MSX-DOS: print the string at DE
BDOS	equ	0005h		; and where its calls go
	cseg
putstr:	ex	de,hl
	ld	c,_STROUT
	jp	BDOS
	end
