; labcnd.as - the whole of 088 in one source. A label on a line that emits
; no bytes takes the location counter IF THAT LINE IS BEING ASSEMBLED, and
; nothing else about the line matters.
;
; LEND IS THE ONE THAT MUST NOT BE DEFINED. It closes the skipped ELSE
; branch, so by the time it is read we are not assembling - the same
; directive as a defined ENDIF elsewhere, answering the other way. M80
; leaves its address column blank and its name out of the symbol table;
; note 088 quotes the listing.
;
; Run with /S: the symbol table is the only thing that shows LEND is
; absent rather than merely unprinted.

		aseg
		org	0100h
lif1:		if	1
		nop
lels:		else
		nop
lend:		endif
lif0:		if	0
		nop
		endif
lrpt:		rept	2
		nop
		endm
		dw	lif1
		dw	lels
		dw	lif0
		dw	lrpt
lend2:		end
