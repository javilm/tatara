; lcmd.inc - public interface of lcmd.as: TANREN's command tail.
;
; SEPARATE FROM cmdline.as, because the two programs take different
; switches and print different screens. What they share is the shape:
; a version number that is one label, printed between the two halves
; of the banner, so that it is written once.

		ifndef	LCMDLIB
		extrn lcmparse		; parse the command tail
					; out: CY set = no filename given
		extrn objname		; the object file, ASCIIZ
		extrn outname		; and the file the image is
					; written to
		extrn loptout		; 0FFh = /O: named it
		extrn loptorg		; 0FFh = /P: gave the code a
		extrn lorgadr		; start address, and this is it
		extrn loptdat		; 0FFh = /D: gave the data one,
		extrn ldatadr		; and this is that
		extrn loptbin		; 0FFh = /B: a seven-byte BLOAD
					; header in front of the image,
					; and .bin as the default
					; extension
		extrn lcmodef		; and if it did not, the first
					; object file does: its name with
					; .com on it
		extrn lcmovch		; THE OUTPUT MAY NOT BE AN
					; INPUT. Checked before anything
					; is read
					; (errlover does not return)
		extrn lcmfrst		; start walking the object
					; filenames in the command tail
		extrn lcmnext		; the next one, into objname
					; out: CY set = there are no more
		extrn loptdump		; 0FFh = /D given: print every
					; record
		extrn loptmap		; 0FFh = /M given: print the
					; tables when the reading is done
		extrn loptquiet		; 0FFh = /Q given: no banner and
					; no summary. ERRORS STILL PRINT
		extrn loptver		; 0FFh = /V given
		extrn lopthelp		; 0FFh = /? given
		extrn lcmbann		; the banner, unless /Q
		extrn lcmwarn		; and the warning that the
					; command line may have been
					; truncated - which prints EVEN
					; under /Q
		extrn lcmver		; the banner, whatever was given
		extrn lcmusage		; the banner and the usage screen.
					; Does not return
		endif

LMAXPATH	equ	128	; the whole command tail is 127 bytes, so
				; one filename can never overflow this
LMAXENV		equ	128	; longest TANREN value we will accept. The
				; variable may hold 255; a longer one is an
				; error rather than a silently shortened
				; search path, as TATARA is for the assembler
