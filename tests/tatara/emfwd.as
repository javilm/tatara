; THE TEST THAT PASS 1 DOES NOT EVALUATE. A forward reference in a DW
; must survive pass 1, which can only happen if emitx leaves the text
; alone and emits a zero
	aseg
	org	0
t0:	dw	later
t1:	db	0
later:	nop
	end
