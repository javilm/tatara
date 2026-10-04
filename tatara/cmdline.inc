; cmdline.inc - public interface of cmdline.as (command tail parsing).
;
; cmdline.as includes this file too, for the shared equates: it defines
; CMDLINE_INCLUDED first, which skips the external declarations
; below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	CMDLINE_INCLUDED
		extrn parse_command_line	; parse the command tail
					; out: CY set = no input filename
		extrn source_name	; input filename, ASCIIZ
		extrn object_name	; object filename, ASCIIZ ("" = none)
		extrn listing_name	; listing filename, ASCIIZ ("" =
					; none). The third name on the
					; command line, and what open_output
					; creates
		extrn opt_screen	; 0FFh = /P given: print to screen
		extrn opt_fields	; 0FFh = /F given: dump the fields
		extrn opt_macros	; 0FFh = /M given: dump each macro
		extrn opt_hex_block	; 0FFh = /H given: report the heap
		extrn opt_listing	; 0FFh = /L given: the address and
					; the bytes in front of every line
		extrn opt_symbols	; 0FFh = /S given: dump the symbol
					; table when the assembly is over
		extrn opt_quiet		; 0FFh = /Q given: no banner and no
					; summary line. ERRORS STILL PRINT
		extrn opt_version	; 0FFh = /V given: the banner, and
					; stop
		extrn opt_help		; 0FFh = /? given: the usage screen,
					; and stop
		extrn print_banner	; the banner, unless /Q. Called once,
					; from main, before anything else is
					; printed
		extrn print_version_banner
					; the banner whatever was given: /V
					; asked for it, and so does the usage
					; screen
		extrn print_usage	; the banner and the usage screen.
					; Does not return - it ends the
					; program
		extrn msg_version_label
				; "Tatara v1.0.0": NAME_FIELD_WIDTH bytes, and
					; the same bytes the banner prints.
					; The page header writes them with
					; write_output, so there is no
					; terminator to avoid
		extrn opt_case		; HT_CASE_SENSITIVE if /C given,
					; else HT_CASE_FOLD. A
					; VALUE, not a flag like the four above:
					; symbol_table_init and
					; macro_table_init load it straight
					; into A for htinit
		endif

PATH_MAX	equ	128	; longest path we store, inc. the terminator
				; (the whole command tail is 127 bytes max, so
				; one filename can never overflow this)
