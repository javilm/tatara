; EX: one byte, except through an index register. The apostrophe in
; af' reaches the operand parser only because of the splitln fix
t0:	ex	de,hl
t1:	ex	af,af'
t2:	ex	(sp),hl
t3:	ex	(sp),ix
t4:	ex	(sp),iy
t5:	nop
	end
