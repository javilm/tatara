; d.as - wants two symbols that no module in the link defines,
; so that symbols_check has to name BOTH of them and not just the first.
	extrn	nowhere1
	extrn	nowhere2
	public	dstart
	cseg
dstart:	call	nowhere1
	call	nowhere2
	ret
	end
