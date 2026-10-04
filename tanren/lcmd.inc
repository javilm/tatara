; lcmd.inc - public interface of lcmd.as: TANREN's command tail.
;
; SEPARATE FROM cmdline.as, because the two programs take different
; switches and print different screens. What they share is the shape:
; a version number that is one label, printed between the two halves
; of the banner, so that it is written once.

		ifndef	LCMD_INCLUDED
		extrn parse_command_line	; parse the command tail
					; out: CY set = no filename given
		extrn object_name	; the object file, ASCIIZ
		extrn output_name	; and the file the image is
					; written to
		extrn opt_output	; 0FFh = /O: named it
		extrn opt_code_origin	; 0FFh = /P: gave the code a
		extrn code_origin	; start address, and this is it
		extrn opt_data_origin	; 0FFh = /D: gave the data one,
		extrn data_origin	; and this is that
		extrn opt_bload		; 0FFh = /B: a seven-byte BLOAD
					; header in front of the image,
					; and .bin as the default
					; extension
		extrn default_output_name	; and if it did not, the first
					; object file does: its name with
					; .com on it
		extrn check_output_not_input	; THE OUTPUT MAY NOT BE AN
					; INPUT. Checked before anything
					; is read
					; (error_output_is_input does
					; not return)
		extrn objects_first	; start walking the object
					; filenames in the command tail
		extrn objects_next	; the next one, into object_name
					; out: CY set = there are no more
		extrn opt_dump		; 0FFh = /D given: print every
					; record
		extrn opt_map		; 0FFh = /M given: print the
					; tables when the reading is done
		extrn opt_quiet		; 0FFh = /Q given: no banner and
					; no summary. ERRORS STILL PRINT
		extrn opt_version	; 0FFh = /V given
		extrn opt_help		; 0FFh = /? given
		extrn print_banner	; the banner, unless /Q
		extrn print_truncation_warning	; and the warning that the
					; command line may have been
					; truncated - which prints EVEN
					; under /Q
		extrn print_version_banner
					; the banner, whatever was given
		extrn print_usage	; the banner and the usage screen.
					; Does not return
		endif

PATH_MAX	equ	128	; the whole command tail is 127 bytes, so
				; one filename can never overflow this
ENV_VALUE_MAX	equ	128	; longest TANREN value we will accept. The
				; variable may hold 255; a longer one is an
				; error rather than a silently shortened
				; search path, as TATARA is for the assembler
