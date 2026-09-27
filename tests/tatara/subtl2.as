; a SUBTTL, and then enough lines to reach a second page. The
; model says the subtitle is on page 1-1 and not on page 1. If M80
; prints no subtitle at all, both pages are blank under the header and
; the model is wrong.
	title	Two Pages
	subttl	The Subtitle
	rept	80
	db	0
	endm
t0:	nop
	end
