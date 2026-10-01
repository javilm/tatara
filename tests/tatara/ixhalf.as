; ixhalf.as - the index halves: IXH, IXL, IYH and IYL, the two bytes of
; IX and IY named one at a time. A DD or FD in front of any instruction
; that mentions H or L makes that H or L a half instead, which is the
; whole encoding.
;
; NEITHER ORACLE HAS THEM, AND ONE OF THEM IS WRONG. M80 knows none of
; the four. SOLiD AS spells them hx, lx, hy and ly, which Tatara does
; not accept - and its own support is partial, taking ixl and never ixh
; (101). And openMSX's DISASSEMBLER is wrong here: it prints DD 65 as
; "ld ixh,l", a spelling that cannot be right, since one prefix cannot
; reach only half of one operand.
;
; So the authority is EXECUTION, plus the table in z80-documented v0.91.
; Measured in openMSX on 2026-10-02, seven of these in a row:
;
;   ld ix,1122h / ld b,33h / ld ixh,b / ld c,ixl / ld ixl,44h /
;   inc ixh / ld a,ixh / add a,ixl / ld iy,5566h / ld iyh,iyl
;
;   Z80 and R800 both: IX=3444, IY=6666, A=78, C=22. IDENTICAL ON BOTH
;   CORES - unlike SLL, there is nothing machine-dependent to say.
;
; What is NOT here is in the error tests beside it: LD H,IXL and
; LD IXH,IYL, because one prefix governs the instruction and not the
; operand, and RLC IXH, because the CB group has no register field to
; spare.

t0:	ld	a,ixh
t1:	ld	ixh,b
t2:	ld	ixl,ixh
t3:	ld	ixh,44h
t4:	ld	iyl,a
t5:	ld	iyh,iyl
t6:	inc	ixh
t7:	dec	iyl
t8:	add	a,ixh
t9:	cp	iyl
ta:	sub	ixl
tb:	nop
	end
