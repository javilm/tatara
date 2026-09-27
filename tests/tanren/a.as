; a.as - contributes to both classic segments.
	public	astart
	cseg
astart:	ld	hl,adata
	ret
	dseg
adata:	defb	"a",0
	end
