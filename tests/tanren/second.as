; the other half. ITS STRING IS NOT AT THE START OF THE DATA
; SEGMENT - OK.AS's five bytes come first - so msg2 is measured from a
; module base of 5, and it asks for msg2+2 on top of that. If either
; number is dropped the program prints the wrong letters.
	public	second
	extrn	putstr
	cseg
second:	call	putstr		; the caller's string
	ld	hl,msg2+2
	jp	putstr		; and its own, from two bytes in
	dseg
msg2:	defb	"yzDONE$"
	end
