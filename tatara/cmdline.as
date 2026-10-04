; cmdline.as - command tail parsing for Tatara.
;
; MSX-DOS leaves the command tail in memory and does nothing else with it:
;
;   0080h  one byte: how many characters of tail there are
;   0081h  the raw text as typed, including the space after the program name
;
; Splitting it into filenames and options is this module's job.
;
; Accepted forms:
;   TATARA TEST.AS OUT.TXT	expand TEST.AS into OUT.TXT
;   TATARA /P TEST.AS		expand TEST.AS to the screen
;   TATARA TEST.AS /P		the same - options may appear anywhere

CMDLINE_INCLUDED	equ	1	; skips the externals in cmdline.inc

		public	parse_command_line
		public	source_name
		public	object_name
		public	listing_name
		public	opt_screen
		public	opt_fields
		public	opt_macros
		public	opt_hex_block
		public	opt_symbols
		public	opt_listing
		public	opt_case
		public	opt_quiet	; /Q, /V and /?
		public	opt_version
		public	opt_help
		public	print_banner	;   the banner three ways
		public	print_version_banner
		public	print_usage
		public	msg_version_label	;   and the version, which the
					;   listing's page header writes

		include	cmdline.inc
		include	ascii.inc
		include	hash.inc	; HT_CASE_SENSITIVE/HT_CASE_FOLD,
					;   which opt_case holds
		include	errs.inc
		include	strutil.inc
		include	msxdos.inc	; _STROUT and dos_exit, for
					;   the banner and the usage screen
					;   from this module

TAIL_LENGTH	equ	00080h		; command tail: the length byte
TAIL_TEXT	equ	00081h		; command tail: the text

SWITCH_CHAR	equ	"/"		; option introducer, MSX-DOS style

		cseg

; parse_command_line - split the command tail into filenames and options.
;
; Input:	nothing (reads TAIL_LENGTH and TAIL_TEXT directly)
; Output:	CY clear = usable
;		CY set   = no input filename given
;		source_name  = input filename, ASCIIZ
;		object_name  = object filename, ASCIIZ (empty if not given)
;		listing_name  = listing filename, ASCIIZ (empty if not given)
;		opt_screen  = 0FFh if /P was given, else 0
; Modifies:	AF, BC, DE, HL

parse_command_line:
		xor	a
		ld	(opt_screen),a	; default: write to a file
		ld	(opt_symbols),a	; default: no symbol dump
		ld	(opt_listing),a	; default: no address and byte columns
		ld	(opt_fields),a	; default: lines pass through whole
		ld	(opt_macros),a	; default: no macro dump. This line was
		ld	(opt_hex_block),a	; defs space is
					; not written to the object file, so
					; opt_macros held whatever MSX-DOS
					; left in that byte. It read zero on
					; every run, which was luck and not
					; a guarantee
		ld	(opt_quiet),a	; default: the banner is printed
		ld	(opt_version),a	; default: assemble, do not just say
		ld	(opt_help),a	;   what this is
		ld	a,HT_CASE_FOLD	; default: case-INSENSITIVE symbols,
		ld	(opt_case),a	; which is M80's behaviour (R2). Not
		xor	a		; xor a: the mode is a value and
		ld	(source_name),a	; HT_CASE_FOLD is 1 and the three names
		ld	(object_name),a	;   all start empty
		ld	(listing_name),a
		ld	c,a		; C = filenames seen so far
		ld	a,(TAIL_LENGTH)
		ld	b,a		; B = characters left in the tail
		ld	hl,TAIL_TEXT	; HL = read pointer

parse_command_line.word:
		call	skip_blanks	; step over spaces and tabs
		ld	a,b
		or	a
		jr	z,parse_command_line.done	; tail exhausted
		ld	a,(hl)
		cp	SWITCH_CHAR
		jr	z,parse_command_line.switch
		call	take_filename	; a filename
		jr	parse_command_line.word
parse_command_line.switch:
		call	do_switch	; an option
		jr	parse_command_line.word

parse_command_line.done:
		ld	a,c
		or	a		; any filename at all? (also clears CY)
		ret	nz		; yes -> CY clear = success
		scf			; no  -> CY set   = nothing usable
		ret

; skip_blanks - advance HL past spaces and tabs, keeping B in step.
;
; Input:	HL -> next character
;               B   = characters left
; Output:	HL, B advanced
;		B = 0 means the tail ran out
; Modifies:	AF, B, HL

skip_blanks:	ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		cp	CHR_SPACE
		jr	z,skip_blanks.step
		cp	CHR_TAB
		ret	nz		; not whitespace -> done
skip_blanks.step:
		inc	hl
		dec	b
		jr	skip_blanks

; cpwend - advance HL past the rest of the current word.
;
;   Used after an option letter, so that "/PXYZ" does not confuse the
;   next round of the main loop.
;
; Input:	HL -> inside a word
;		B   = characters left
; Output:	HL -> the whitespace ending the word, or B = 0
; Modifies:	AF, B, HL

skip_word:	ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret	z
		inc	hl
		dec	b
		jr	skip_word

; do_switch - handle one option word. Never returns on a bad option:
; error_unknown_option prints the message and terminates.
;
; Input:	HL -> the "/"
;		B   = characters left
; Output:	opt_screen or opt_fields updated
;		HL, B past the word
; Modifies:	AF, B, DE, HL

do_switch:	inc	hl		; step over the "/"
		dec	b
		ld	a,b
		or	a
		jp	z,error_unknown_option	; a "/" with nothing after it
		ld	a,(hl)
		call	fold_to_upper
		cp	"P"
		jr	z,do_switch.screen
		cp	"F"
		jr	z,do_switch.fields
		cp	"M"
		jr	z,do_switch.macros
		cp	"C"
		jr	z,do_switch.case
		cp	"H"
		jr	z,do_switch.hex_block
		cp	"L"
		jr	z,do_switch.listing
		cp	"S"
		jr	z,do_switch.symbols
		cp	"Q"
		jr	z,do_switch.quiet
		cp	"V"
		jr	z,do_switch.version
		cp	"?"	; NOT a letter, so fold_to_upper left it
		jp	nz,error_unknown_option
					;   alone and this test is exact
		ld	a,0ffh
		ld	(opt_help),a
		jp	skip_word
do_switch.symbols:
		ld	a,0ffh
		ld	(opt_symbols),a
		jp	skip_word
do_switch.quiet:
		ld	a,0ffh
		ld	(opt_quiet),a
		jp	skip_word
do_switch.version:
		ld	a,0ffh
		ld	(opt_version),a
		jp	skip_word
do_switch.listing:
		ld	a,0ffh	; /L: the address and the bytes in
		ld	(opt_listing),a	;   front of every line, M80's shape.
		jp	skip_word	;   A switch and not the default
					;   because 140 tests read the output
					;   and a few depend on its shape -
					;   whether a real
					;   listing becomes the default
do_switch.hex_block:
		ld	a,0ffh
		ld	(opt_hex_block),a
		jp	skip_word
do_switch.case:			; /C: symbols and macro names are
		ld	a,HT_CASE_SENSITIVE
		ld	(opt_case),a	; case-SENSITIVE. Not directives,
		jp	skip_word	; mnemonics or registers - R2 says
					; those are insensitive in both
					; modes
do_switch.macros:
		ld	a,0ffh
		ld	(opt_macros),a
		jp	skip_word
do_switch.fields:
		ld	a,0ffh
		ld	(opt_fields),a
		jp	skip_word	; skip anything else in this word
do_switch.screen:
		ld	a,0ffh
		ld	(opt_screen),a
		jp	skip_word

; print_banner - the banner, unless /Q said not to.
;
; Input:	nothing
; Output:	four lines, or none
; Modifies:	AF, DE

print_banner:	ld	a,(opt_quiet)
		or	a
		ret	nz

; print_version_banner - the banner whatever was asked for. IN THREE
;   PIECES,
;   because the version number in the middle is a label of its own -
;   see msg_version_label below for why.
;
; Input:	nothing
; Output:	four lines, the last of them blank
; Modifies:	AF, DE

print_version_banner:
		ld	de,msg_banner_head
		call	print_dollar_string
		ld	de,msg_version
		call	print_dollar_string
		ld	de,msg_banner_tail
		call	print_dollar_string
		ret

; print_usage - the banner and the usage screen, and stop.
;
;   TWENTY-TWO LINES, which is what fits: the command that was typed
;   takes the first row of a 24-row screen and the prompt takes the
;   last, so nothing scrolls away. Every line is inside 79 columns.
;
;   /Q DOES NOT SILENCE THIS. Asking for the screen and asking for
;   silence at once is a contradiction, and the screen is the answer.
;
; Input:	nothing
; Output:	the screen, and the program ends
; Modifies:	does not return

print_usage:	call	print_version_banner
		ld	de,msg_usage
		call	print_dollar_string
		jp	dos_exit

; take_filename - copy the word at HL into the next free filename slow.
;
;   No length check is needed: the whole command tail is at most 127
;   characters, so a single filename cannot overflow PATH_MAX.
;   A third filename is an error - error_too_many_filenames prints and
;   terminates.
;
; Input:	HL -> first character of the word
;		B   = characters left
;		C   = filenames seen so far
; Output:	the name stored ASCIIZ
;		C incremented
;		HL and B past the word
; Modifies:	AB, BC, DE, HL

take_filename:	ld	a,c
		or	a
		jr	nz,take_filename.second
		ld	de,source_name	; first filename
		jr	take_filename.copy
take_filename.second:
		cp	1
		jr	nz,take_filename.third
		ld	de,object_name	; second: the OBJECT file
		jr	take_filename.copy
take_filename.third:
		cp	2
		jp	nz,error_too_many_filenames	; a fourth is an error
		ld	de,listing_name	; third: the LISTING
take_filename.copy:
		ld	a,b
		or	a
		jr	z,take_filename.done	; tail ran out
		ld	a,(hl)
		cp	CHR_SPACE
		jr	z,take_filename.done
		cp	CHR_TAB
		jr	z,take_filename.done
		ld	(de),a
		inc	hl
		inc	de
		dec	b
		jr	take_filename.copy
take_filename.done:
		xor	a
		ld	(de),a		; ASCIIZ terminator, for _OPEN
		inc	c		; one more filename seen
		ret

; THE VERSION IS WRITTEN ONCE, and these two labels are adjacent on
; purpose. msg_version_label is the thirteen bytes the listing's page header
; wants - "Tatara v" is eight and "1.2.0" is five - because msg_version
; follows it in memory. msg_version on its own is the number with a "$"
; behind it, which is what print_version_banner prints between the
; two halves of the banner.
;
; THIRTEEN IS M80'S WIDTH: "MSX.M-80 2.00" is thirteen characters and
; every column of the page header after it was measured from there.
; A two-digit major version would be fourteen and would move them
; all, so NAME_FIELD_WIDTH and these two labels have to be changed together.

msg_version_label:
		defb	"Tatara v"
msg_version:	defb	"1.2.0","$"

msg_banner_head:
		defb	"Tatara MSX Macro-Assembler v$"
msg_banner_tail:
		defb	CHR_CR,CHR_LF
		defb	"Copyright (C) 2026 Javier Lavandeira"
		defb	CHR_CR,CHR_LF
		defb	"https://tatara.tools"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF,"$"

msg_usage:	defb	"Usage:  TATARA [options] <source> [output]"
		defb	CHR_CR,CHR_LF
		defb	"        TATARA /P [options] <source> [output]"
		defb	CHR_CR,CHR_LF
		defb	"        TATARA /L [options] <source> <output>"
		defb	" <listing>",CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"Options:  /P Assemble to the screen"
		defb	CHR_CR,CHR_LF
		defb	"          /L Write a listing file, named third"
		defb	" on the line",CHR_CR,CHR_LF
		defb	"          /S Print the symbol table when the"
		defb	" assembly ends",CHR_CR,CHR_LF
		defb	"          /C Make symbol and macro names"
		defb	" case-sensitive",CHR_CR,CHR_LF
		defb	"          /F Print the fields of each line, for"
		defb	" diagnosis",CHR_CR,CHR_LF
		defb	"          /M Print every macro definition, for"
		defb	" diagnosis",CHR_CR,CHR_LF
		defb	"          /H Print how many heap blocks are"
		defb	" still in use",CHR_CR,CHR_LF
		defb	"          /Q Omit the banner above and the"
		defb	" summary line",CHR_CR,CHR_LF
		defb	"          /V Print the program version"
		defb	CHR_CR,CHR_LF
		defb	"          /? Print this screen"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"<source>  : The file to assemble, M80 syntax"
		defb	" (.as, .asm or .z80)",CHR_CR,CHR_LF
		defb	"<output>  : The relocatable object it produces,"
		defb	" usually .tro",CHR_CR,CHR_LF
		defb	"<listing> : The listing file, usually .lst or"
		defb	" .prn",CHR_CR,CHR_LF,"$"

		dseg

source_name:	defs	PATH_MAX	; input filename
object_name:	defs	PATH_MAX	; output filename ("" = none given)
listing_name:	defs	PATH_MAX	; listing filename ("" = none), the
					;   third on the command line
opt_screen:	defs	1		; 0FFh = /P given
opt_fields:	defs	1		; 0FFh = /F given
opt_macros:	defs	1		; 0FFh = /M given
opt_hex_block:	defs	1		; 0FFh = /H given
opt_symbols:	defs	1		; 0FFh = /S given
opt_listing:	defs	1		; 0FFh = /L given
opt_quiet:	defs	1		; 0FFh = /Q given
opt_version:	defs	1		; 0FFh = /V given
opt_help:	defs	1		; 0FFh = /? given
opt_case:	defs	1	; HT_CASE_SENSITIVE or
				;   HT_CASE_FOLD. Fixed for the
					; run: changing it part-way would mean
					; rehashing every populated table, and
					; R2 wants one mode across a whole
					; link job
