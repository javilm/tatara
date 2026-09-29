; labund.as - the other half. A label on a conditional line that is NOT
; being assembled is not defined, and referring to it is an error rather
; than a wrong answer. LEND here is LABCND.AS's LEND, referred to.

		cseg
		if	1
		nop
		else
		nop
lend:		endif
		dw	lend
		end
