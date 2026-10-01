; labdir.as - a label on the three directive lines 098 gave one to, and
; on the two it deliberately did not.
;
; THE RULE IS 088'S, UNCHANGED: a label on a line that emits no bytes
; takes the location counter, if that line is being assembled. PUBLIC,
; EXTRN, INCLUDE and EXITM are assembled. A LOCAL line and an ENDM line
; are read while the macro body is COLLECTED and are never assembled, so
; they have nothing to take - and M80 drops those two as well.
;
; LINC takes the counter the INCLUDE line had, and ONELINE.INC holds a
; db 1 - so the included byte lands at that same address, the INCLUDE
; line itself having emitted none. THE INCLUDE LINE IS NOT LISTED; only
; the included line is.
;
; LLOC AND LEM ARE THE ONES THAT MUST BE ABSENT. Run with /S: the symbol
; table is the only thing that shows a name is missing rather than
; merely unprinted.

		aseg
		org	0100h

lpub:		public	fpub
lext:		extrn	ext1
linc:		include	oneline.inc

fpub:		nop

mm		macro
lloc:		local	q
q:		nop
lxm:		exitm
		nop
lem:		endm

		mm

		dw	ext1
		end
