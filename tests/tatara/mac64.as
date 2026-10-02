; mac64.as - a macro name of exactly 64 characters, which is MDNAMSZ:
; the length mdt.inc calls the longest it remembers, and the length
; mdnam is sized for - the name plus its terminator.
;
; ISSUE #29 REPORTED THIS FILE REFUSED, with "MACRO without a name" on a
; line holding sixty-four characters of name. Two faults: the message was
; shared with the no-name case, and the test was cp MDNAMSZ where
; symtab.as's two of the same shape are cp SGNMAX+1 - so 64 was refused
; by a limit that is 64. THIS FILE IS THE REGRESSION GUARD: it must
; assemble, and both bytes must come out.
;
; M80 is no oracle here. Javier, 2026-10-02: M80's own macro names keep
; about six significant characters - his recollection, not a measured
; run - so 64 is generous rather than incompatible either way.

a_macro_whose_name_is_long_enough_to_say_what_it_is_for_yyyyyyyy	macro
	nop
	endm

	a_macro_whose_name_is_long_enough_to_say_what_it_is_for_yyyyyyyy
t0:	nop
	end
