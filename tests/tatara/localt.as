; before
delay	macro	n
	local	loop
	ld	b,n
loop:	djnz	loop
	endm
two	macro
	local	a,b
a:	nop
b:	nop
	endm
	delay	10
	delay	20
	two
	two
	ret
