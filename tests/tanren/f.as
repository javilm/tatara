; f.as - one transient DSEG, three groups. The segment is as
; large as its LARGEST group, not the sum and not the last: 20 bytes,
; not 32 and not 4.
	public	fstart
	dseg	work,transient
	group	g1
f1:	ds	8
	group	g2
f2:	ds	20
	group	g3
f3:	ds	4
	cseg
fstart:	ret
	end
