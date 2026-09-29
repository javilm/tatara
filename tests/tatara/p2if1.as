; p2if1.as - a label inside an IF1 block, on line 9. Legal M80, and
; 087's accepted casualty: a label that exists on the first reading
; only is a phase error waiting to happen whether a guard or IF1 put it
; there, and nothing can be assembled from it that links.

		cseg
		call	only1
		if1
only1:		ret
		endif
		end
