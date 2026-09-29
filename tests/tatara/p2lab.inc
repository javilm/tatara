; p2lab.inc - the guarded include from issue #12. SHARED, on line 7, is
; the label pass 2 never defines.

		ifndef	p2lab_inc
p2lab_inc	equ	1
		cseg
shared:		ret
		endif
