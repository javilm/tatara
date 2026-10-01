; labch.as - a label holding a character that a name may not hold.
;
; M80 answers this line with a U and one fatal error (appendix J).
; Before 099 Tatara defined FOO*BAR and said nothing - a symbol that
; could never be referred to, because the expression parser stops a
; name at the "*" and reads it as a multiplication.

		aseg
		org	0100h

foo*bar		ret

		end
