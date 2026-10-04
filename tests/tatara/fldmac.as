; fldmac.as - issue #20: /F replaces every line's listing with its field
; dump, and a macro definition used to be listed anyway - with a page
; heading over it - because list_body_line tested nothing. Expect field dumps
; and NOTHING else.

two		macro	x
		db	x,x
		endm
		two	3
		end
