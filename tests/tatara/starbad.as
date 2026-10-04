; starbad.as - a control line this assembler does not have.
;
; M80 takes $TITLE('x') and *TITLE('x') as SUBTTL. We do not, and the
; reason is not SUBTTL: the title text holds a SPACE, so split_line has
; already cut this line into a label "$title('Dollar" and an operation
; "title')" before any handler could look at it. Reading it would mean
; taking the whole line before the fields are cut.
;
; So the message names the two control lines there are. Write SUBTTL.

		aseg
		org	0100h

$title('Dollar title')

		end
