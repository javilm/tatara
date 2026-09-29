; labirp.as - REPT's relatives. This source is the one M80 assembled on
; 2026-09-30, unchanged, so m80ref/labirp.prn can be frozen beside it if
; the cross-check is ever wanted: THE dw LINES EMIT BYTES, which is what
; cmpm80.py compares, and those bytes ARE the two label values. 0104 holds
; 0100 and 0106 holds 0102.

		aseg
		org	100h
lirp:		irp	x,<1,2>
		nop
		endm
lirpc:		irpc	c,ab
		nop
		endm
		dw	lirp
		dw	lirpc
		end
