; the same macro called three times, once under each mode. What
; M80 keeps under each - and whether it lists the control line itself,
; and whether it flags the CALL line - is what this asks M80
byte	macro	n
	db	n
	if	n
	endif
	endm
	.lall
t0:	byte	1
	.xall
	byte	2
	.sall
	byte	3
	end
