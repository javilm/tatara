; where the PAGE line itself is listed, and whether the
; page after it is 2 or 1-1. PAGE 12 asks what the count counts - M80
; leaves eight lines of text, so it is the whole page and not its
; body. A length out of range is PAGEBAD.AS: it is an error, and an
; error ends the assembly before a listing file is finished.
	title	Page Directive
	db	1
	page
	db	2
	page	12
	rept	30
	db	3
	endm
	db	4
	end
