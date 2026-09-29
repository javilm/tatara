; phaseobj.as - a phase error, with an object file named. The IFDEF is
; false on pass 1 and true on pass 2, because LATER is still defined
; when the second reading starts, so the DB inside it moves LAB by one
; and the two readings disagree about where LAB is.
;
; The point is not the phase error - PASSIF.AS and others cover that -
; but WHERE it happens: after pass 2 has written real content to the
; object file. PUBUNDF.AS stops at the other end, while the header
; records are still going out, and between them they show that the file
; goes whether it holds 33 bytes or 44.

		cseg
		ifdef	later
		db	0
		endif
lab:		db	1
later		equ	1
		end
