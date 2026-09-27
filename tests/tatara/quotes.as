; character constants in both delimiters. DB has taken "..."
; and the evaluator had only ever been given the apostrophe, so "db
; ""A""" assembled and "cp ""A""" did not - in the same assembler, on
; the same character
	aseg
	org	0
t0:	cp	" "
t1:	cp	'A'
t2:	cp	"A"
t3:	ld	hl,"AB"
t4:	db	""""
t5:	db	''''
t6:	nop
	end
