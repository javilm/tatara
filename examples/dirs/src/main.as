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
; run the build. No include here depends on where that is.
;
; THE TWO INCLUDES THAT CARRY MESSAGES ARE AT THE BOTTOM, after the
; code, and that is not a matter of taste. A .COM is entered at its
; FIRST BYTE, 0100h, whatever address END names: that address goes
; into the object file and the linker prints it, and MSX-DOS never
; reads it. Included up here, the messages would be the first bytes
; of the code segment and the machine would run the text.

		include	msxdos.inc	; rule 3: TATARA names the
					;   directories to look in. EQUATES
					;   ONLY - it emits no bytes, so it
					;   is safe above the code

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

		include	inc\text.inc	; rule 1, with a separator:
					;   relative to THIS file
		include	sysmsg.inc	; rule 3 as well, from the OTHER
					;   directory in TATARA

		end	start
