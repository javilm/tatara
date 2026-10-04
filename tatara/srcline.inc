; srcline.inc - public interface of srcline.as: where source lines come
; from.
;
; srcline.as includes this file too, for the shared equates: it defines
; SRCLINE_INCLUDED first, which skips the external declarations below - a
; symbol cannot be declared external in the module that defines it as global.

		ifndef	SRCLINE_INCLUDED
		extrn source_init	; empty the stack of line sources
		extrn push_file		; open a file and put it on top
					; in : DE -> filename, ASCIIZ
					; out: CY set = could not open it
		extrn push_macro	; make a macro expansion the source
					; in : HL -> far pointer to the expansion
					;            record
					;      A   = the definition's file number
		extrn pop_source	; remove the top line source
		extrn file_line		; next line from a file source
					; in:  IX -> entry
					;      HL -> line buffer
					; out: CY set = no more lines
					;      A      = length
		extrn next_source_line	; next line from whatever is on top
					; in:  HL -> line buffer
					; out: CY set = no more lines, anywhere
					;      A      = length
		extrn current_file	; file number of the line just given
		extrn pass_number
				; which pass is running, 1 or 2. A pass is
					; a READING of the source, which is what
					; this module owns - hence its home here,
					; beside where in the source we are
		extrn current_line	; line number of the line just given
		extrn source_depth	; how many sources are we stacked now
		extrn source_top	; address of the top entry
		extrn get_filename	; A = file number -> DE = its name
		extrn source_open	; open an INCLUDEd file, looking in
					; the including file's directory, the
					; current directory, then TATARA
					; in : DE -> filename, ASCIIZ
					; out: CY set = found nowhere
		extrn entry_address	; A = entry number -> HL = its address
					;   in source_stack. errs.as walks the
					;   stack with it to print the origin
					;   trail
		endif

		; how many sources may be stacked at once
SOURCE_STACK_MAX	equ	16
				; (files + macro expansions + repeat blocks)
OPEN_FILE_MAX	equ	4	; how many FILES may be open at once - each
				; one costs a FILE_CHUNK_SIZE-sized buffer
FILE_CHUNK_SIZE	equ	512	; bytes of file buffered per open file
LINE_MAX	equ	255	; longest source line we accept
FILE_NAMES_MAX	equ	32	; how many file OPENINGS we remember a name
				;   for - the same file opened twice gets two
				;   entries, on purpose. tatara.as needs
				;   17 of them
FILE_NAME_MAX	equ	32	; longest file name kept for messages. A
				;   POWER OF TWO: filename_address shifts
				;   rather than multiplies. Longer names are
				;   truncated by add_filename, in diagnostics
				;   only
ENV_VALUE_MAX	equ	128	; longest TATARA value we will accept. The
				;   variable may hold 255; a longer one is an
				;   error rather than a silently shortened
				;   search path

; --- kinds of line source: files, macro expansions
;     and repeat blocks.

SOURCE_IS_FILE	equ	0
SOURCE_IS_MACRO	equ	1

; --- one line source entry. Eleven bytes are used; the entry is padded
;     to 16 so that "entry number n" is four shifts, not a multiply.

SOURCE_KIND	equ	0	; +0 which sort of source this is
SOURCE_HANDLE	equ	1	; +1 MSX-DOS file handle
SOURCE_FILE_NUMBER	equ	2	; +2 file number, for error messages
SOURCE_LINE	equ	3	; +3 line number of the line just handed over
SOURCE_READ_AT	equ	5	; +5 read position inside this source's buffer
SOURCE_LEFT	equ	7	; +7 bytes still unread in that buffer
SOURCE_BUFFER	equ	9	; +9 address of this source's buffer
SOURCE_EOF	equ	11	; +11 non-zero once the file is finished
		; +12 far pointer to the expansion record (4)
SOURCE_EXPANSION	equ	12
SOURCE_ENTRY_SIZE	equ	16	; size of one entry
