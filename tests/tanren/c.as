; c.as - a transient DSEG in a group, which is [R4]'s shape and
; the reason a segment's key carries its group. The syntax is the
; assembler's own: "dseg <name>,transient" and then a GROUP, which is
; what SEGNGRP.AS and GRPMIX.AS in the other suite use.
	public	cstart
	dseg	scratch,transient
	group	frame
cwork:	ds	8
	cseg
cstart:	ret
	end
