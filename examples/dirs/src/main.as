; SRC\MAIN.AS - a program whose parts are in three directories.
;
; AN INCLUDE IS LOOKED FOR IN THREE PLACES, IN THIS ORDER:
;
;   1. the directory of the file doing the including
;   2. the current directory
;   3. each directory named in the TATARA environment variable
;
; Rule 1 comes first so that a file always finds the header sitting
; beside it, whatever directory you happen to be standing in when you
; run the build. Neither line below depends on where that is.

		include	inc\text.inc	; rule 1, with a separator:
					;   relative to THIS file
		include	sysmsg.inc	; rule 3: TATARA names the
					;   directory it is in
		include	msxdos.inc	; rule 3 as well, from the OTHER
					;   directory in TATARA

		cseg

start:		ld	de,text
		call	prtstr
		ld	de,deeper
		call	prtstr
		ld	de,sysmsg
		call	prtstr
		ld	c,_TERM0
		jp	BDOS

prtstr:		ld	c,_STROUT
		jp	BDOS		; and BDOS returns to the caller

		end	start
