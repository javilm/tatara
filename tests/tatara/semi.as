; semi.as - a semicolon passed to a macro, both ways M80 allows.
;
; "!;" and "<;>" are equivalent and both pass one - measured against
; MSX.M-80 2.00, which emits 61 3B 62 for each (appendix J). Before 099
; splitln ended the operand at the ";" before mxargs could see either
; form, and both expanded to db 'a'.

m		macro	x
		db	'&x'
		endm

		aseg
		org	0100h

		m	a!;b
		m	<a;b>

		end
