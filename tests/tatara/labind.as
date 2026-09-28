; labind.as - a label that does not start in column 1.
;
; M80 accepts an indented label when a colon ends it, and 082 makes
; Tatara do the same. Five shapes, then their values: an indented
; instruction must still be an instruction and not a label.

top:		ld	a,1		; column 1, colon
bare		ld	a,2		; column 1, no colon
	mid:	ld	a,3		; indented, colon
	pub::	ld	a,4		; indented, "::" stepped over
	only:				; indented, nothing after the colon
		ld	a,5		; indented, no colon: an instruction

		dw	top		; 0000
		dw	bare		; 0002
		dw	mid		; 0004
		dw	pub		; 0006
		dw	only		; 0008
