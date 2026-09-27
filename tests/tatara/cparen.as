; (c) is an ADDRESS to LD and GROUPING to CP, and a kind of its own to
; neither. M80 makes the first line 3A 0005
c	equ	5
t0:	ld	a,(c)
t1:	cp	(c)
t2:	nop
	end
