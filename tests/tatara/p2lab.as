; p2lab.as - issue #12: a label defined on the first reading of the
; source and not on the second. The guard in P2LAB.INC is already set
; by the time pass 2 reads it, so SHARED's RET is never emitted while
; CALL SHARED still assembles to the address pass 1 gave it.
;
; M80 assembles this into a three-byte program that calls past its own
; end and says nothing. Tatara stops, naming P2LAB.INC's line.

		cseg
		call	shared
		include	p2lab.inc
		end
