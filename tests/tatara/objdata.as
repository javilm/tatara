; DATA records, and what breaks a run. Four of them - the CSEG's
; first two lines in one, the DSEG's one byte, the DSEG again after a
; DS gap, and the CSEG when it comes back to where it left off
	cseg
	db	1,2,3
	db	4
	dseg
	db	5
	ds	2
	db	7
	cseg
	db	6
	end
