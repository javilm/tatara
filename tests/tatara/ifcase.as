; ifcase.as - issue #16. IFIDN and IFDIF compare TEXT, and text is
; compared exactly: <abc> and <ABC> are different. Tatara folded both
; sides until 089, so the first branch was taken and the third was not.
;
; CROSS-CHECKED. Both db lines emit bytes, which is what cmpm80.py
; compares, so m80ref/ifcase.prn checks the rule on every run rather
; than a note asserting it. Expect 02 at 0000h and 03 at 0001h, and no
; 01 anywhere.

		ifidn	<abc>,<ABC>
		db	1
		endif
		ifidn	<abc>,<abc>
		db	2
		endif
		ifdif	<abc>,<ABC>
		db	3
		endif
		end
