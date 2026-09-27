; cmdline.inc - public interface of cmdline.as (command tail parsing).
;
; cmdline.as includes this file too, for the shared equates: it defines
; CMDLIB first, which skips the external declarations below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	CMDLIB
		extrn cmdparse		; parse the command tail
					; out: CY set = no input filename
		extrn srcname		; input filename, ASCIIZ
		extrn dstname		; object filename, ASCIIZ ("" = none)
		extrn lstname		; listing filename, ASCIIZ ("" =
					; none). The third name on the
					; command line, and what outopen
					; creates
		extrn optscrn		; 0FFh = /P given: print to screen
		extrn optflds		; 0FFh = /F given: dump the fields
		extrn optmacs		; 0FFh = /M given: dump each macro
		extrn opthblk		; 0FFh = /H given: report the heap
		extrn optlist		; 0FFh = /L given: the address and
					; the bytes in front of every line
		extrn optsym		; 0FFh = /S given: dump the symbol
					; table when the assembly is over
		extrn optquiet		; 0FFh = /Q given: no banner and no
					; summary line. ERRORS STILL PRINT
		extrn optver		; 0FFh = /V given: the banner, and
					; stop
		extrn opthelp		; 0FFh = /? given: the usage screen,
					; and stop
		extrn cmdbann		; the banner, unless /Q. Called once,
					; from main, before anything else is
					; printed
		extrn cmdver		; the banner whatever was given: /V
					; asked for it, and so does the usage
					; screen
		extrn cmdusage		; the banner and the usage screen.
					; Does not return - it ends the
					; program
		extrn vertxt		; "Tatara v1.0.0": LSTNAMW bytes, and
					; the same bytes the banner prints.
					; The page header writes them with
					; emitraw, so there is no terminator
					; to avoid
		extrn optcase		; HTCASES if /C given, else HTCASEI. A
					; VALUE, not a flag like the four above:
					; syminit and macinit load it straight
					; into A for htinit
		endif

MAXPATH		equ	128	; longest path we store, inc. the terminator
				; (the whole command tail is 127 bytes max, so
				; one filename can never overflow this)
