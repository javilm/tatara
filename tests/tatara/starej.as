; starej.as - *EJECT and $EJECT, M80's other spellings of PAGE.
;
; MSX.M-80 2.00 takes both, breaks the page, and leaves NO symbol
; behind. Before 099 each one defined a label and the page ran on.
;
; Only these two spellings are followed. M80 reads any column-1 word
; beginning with * or $ as a control, and that general rule would stop
; $foo: being a label - so it is not taken.

		aseg
		org	0100h

		nop
*eject
		nop
$eject
		nop

		end
