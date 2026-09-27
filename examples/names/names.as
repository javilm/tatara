; NAMES.AS - names as long as you like, in either case.
;
; A SYMBOL MAY BE 255 CHARACTERS AND ALL OF THEM COUNT. M80 keeps the
; first six, which is why so much CP/M-era assembly is written in
; abbreviations. The two names below differ only in their last five
; characters and are two different symbols here. 255 is the limit, and
; the test suite has a 240-character name in it; these are 48, which is
; as long as a line can carry and still be read on an MSX screen.

first_pass_symbol_table_high_water_mark_in_bytes	defl	1024
first_pass_symbol_table_high_water_mark_in_words	defl	512

; THE SAME SIX LETTERS IN TWO CASES. Without /C they are ONE symbol,
; and the second line changes its value. With /C they are TWO, with
; values 1 and 2. The symbol table of each run says which - and DEFL
; is used rather than EQU because a redefinition is legal, so the
; source assembles cleanly in both modes.

Counter		defl	1
counter		defl	2

; DIRECTIVES, MNEMONICS AND REGISTER NAMES ARE CASE-INSENSITIVE IN
; BOTH MODES. /C is about the names you choose, not the ones the Z80
; already has.

		cseg

start:		LD	A,1
		ld	b,a
		DB	Counter
		db	counter
		ret

		end	start
