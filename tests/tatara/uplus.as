; unary plus. An index displacement is remembered WITH its sign, so
; the evaluator is handed "+5" as readily as "-1" - and it had the
; minus and not the plus
	aseg
	org	0
t0:	db	+1
t1:	dw	+1234h
t2:	and	(ix+5)
t3:	and	(ix-5)
t4:	nop
	end
