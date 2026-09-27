; srcline.inc - public interface of srcline.as: where source lines come
; from.
;
; srcline.as includes this file too, for the shared equates: it defines
; SRCLIB first, which skips the external declarations below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	SRCLIB
		extrn srcinit		; empty the stack of line sources
		extrn pushfile		; open a file and put it on top
					; in : DE -> filename, ASCIIZ
					; out: CY set = could not open it
		extrn pushmac		; make a macro expansion the source
					; in : HL -> far pointer to the expansion
					;            record
					;      A   = the definition's file number
		extrn popsrc		; remove the top line source
		extrn filelin		; next line from a file source
					; in:  IX -> entry
					;      HL -> line buffer
					; out: CY set = no more lines
					;      A      = length
		extrn getline		; next line from whatever is on top
					; in:  HL -> line buffer
					; out: CY set = no more lines, anywhere
					;      A      = length
		extrn curfile		; file number of the line just given
		extrn passno		; which pass is running, 1 or 2. A pass is
					; a READING of the source, which is what
					; this module owns - hence its home here,
					; beside where in the source we are
		extrn curline		; line number of the line just given
		extrn srcdep		; how many sources are we stacked now
		extrn srctop		; address of the top entry
		extrn getfnam		; A = file number -> DE = its name
		extrn srcopen		; open an INCLUDEd file, looking in
					; the including file's directory, the
					; current directory, then TATARA
					; in : DE -> filename, ASCIIZ
					; out: CY set = found nowhere
		extrn entaddr		; A = entry number -> HL = its address
					;   in srcstk. errs.as walks the stack
					;   with it to print the origin trail
		endif

MAXSRC		equ	16	; how many sources may be stacked at once
				; (files + macro expansions + repeat blocks)
MAXINC		equ	4	; how many FILES may be open at once - each
				; one costs a CHUNK-sized buffer
CHUNK		equ	512	; bytes of file buffered per open file
MAXLINE		equ	255	; longest source line we accept
MAXFILE		equ	32	; how many file OPENINGS we remember a name
				;   for - the same file opened twice gets two
				;   entries, on purpose. tatara.as needs
				;   17 of them
MAXFNAM		equ	32	; longest file name kept for messages. A
				;   POWER OF TWO: fnaddr shifts rather than
				;   multiplies. Longer names are truncated by
				;   addfnam, in diagnostics only
MAXENV		equ	128	; longest TATARA value we will accept. The
				;   variable may hold 255; a longer one is an
				;   error rather than a silently shortened
				;   search path

; --- kinds of line source: files, macro expansions
;     and repeat blocks.

LSK_FILE	equ	0
LSK_MACRO	equ	1

; --- one line source entry. Eleven bytes are used; the entry is padded
;     to 16 so that "entry number n" is four shifts, not a multiply.

LS_KIND		equ	0	; +0 which sort of source this is
LS_HAND		equ	1	; +1 MSX-DOS file handle
LS_FILE		equ	2	; +2 file number, for error messages
LS_LINE		equ	3	; +3 line number of the line just handed over
LS_PTR		equ	5	; +5 read position inside this source's buffer
LS_LEFT		equ	7	; +7 bytes still unread in that buffer
LS_BUF		equ	9	; +9 address of this source's buffer
LS_EOF		equ	11	; +11 non-zero once the file is finished
LS_MX		equ	12	; +12 far pointer to the expansion record (4)
LSSIZE		equ	16	; size of one entry
