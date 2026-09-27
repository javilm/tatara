; M80 flags a macro-generated line with a "+". WHERE it puts it
; is what this test asks M80, which is why it obeys M80's rules - t0
; upward, and an END line
byte	macro	n
	db	n
	endm
t0:	byte	1
	byte	2
	end
