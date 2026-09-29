; labif.as - issue #15 as filed. A label on the IF line and on the ENDIF
; line of a conditional that is being assembled. M80 defines both; Tatara
; defined neither, and the two dw lines could not be assembled at all -
; which is how the bug was found, because the error named the dw and not
; the labels.

		cseg
first:		if	1
		nop
second:		endif
		dw	first
		dw	second
		end
