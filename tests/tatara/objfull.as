; every record the linker's first pass reads, in one 59-byte file.
; One group would need a transient DSEG; GRPFULL.AS can wait until
; something reads these.
	extrn	bar
	public	start
	cseg
start:	ld	hl,bar
	ret
	dseg
	ds	4
	end
