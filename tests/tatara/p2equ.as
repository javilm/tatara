; p2equ.as - THE REGRESSION GUARD FOR 087. The same shape as P2LAB.AS
; with equates instead of a label, and it must assemble clean.
;
; The guard in P2EQU.INC is set on pass 1 and skips the block on pass
; 2, so FIVE is never redefined - and nothing is wrong: it keeps its
; pass-1 value and LD A,FIVE assembles to 3E 05 on both readings. If
; this one reports an error, check_pass2_labels is checking equates and every
; guarded include file in existence has just become illegal.

		aseg
		org	0100h
		include	p2equ.inc
		ld	a,five
		end
