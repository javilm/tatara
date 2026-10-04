; msxdos.inc - MSX-DOS interface: BDOS function numbers, the "system"
; macro, and the helper routines implemented in msxdos.as.
;
; msxdos.as includes this file too, for the macro and the equates: it
; defines MSXDOS_INCLUDED first, which skips the external
; declarations below - a
; symbol cannot be declared external in the module that defines it as
; global.

BDOS		equ	00005h		; the MSX-DOS function call entry

; --- BDOS function numbers used by Tatara

_TERM0		equ	00000h		; terminate the program
_CONOUT		equ	00002h		; print the character in E
_STROUT		equ	00009h		; print the "$"-terminated string at DE
_OPEN		equ	00043h		; open an existing file
_CREATE		equ	00044h		; create a file
_CLOSE		equ	00045h		; close a file handle
_DELETE		equ	0004dh		; delete the file DE names, zero-
					;   terminated. MSX-DOS 2 only, like
					;   the handle calls around it
_READ		equ	00048h		; read from a file handle
_WRITE		equ	00049h		; write to a file handle
_SEEK		equ	0004ah		; move a file handle's pointer.
					;   B = handle, A = 0 from the start,
					;   1 from here, 2 from the end,
					;   DE:HL = the offset with DE THE
					;   HIGH WORD, and DE:HL comes back
					;   as the new position.
					;   THIS ONCE SAID HL:DE and
					;   nothing had caught it:
					;   remember_position seeks +0, where
					;   the order cannot show, and
					;   seek_remembered hands back the very
					;   pair remember_position was given,
					;   so it round-trips either way. The
					;   first seek in this program that
					;   moved a real distance was
					;   objfile_skip_record's, and it went
					;   to the end of the file
_GENV		equ	0006bh		; get an environment variable.
					;   HL -> the name, DE -> a buffer,
					;   B = its size. MSX-DOS 2 only
_DOSVER		equ	0006fh		; get the MSX-DOS version

ERR_ELONG	equ	000bfh		; _GENV: the value did not fit, and
					;   what is in the buffer HAS NO
					;   TERMINATOR

STDOUT		equ	1		; file handle of the standard output

; system func - call BDOS function "func".
;
;   page2_safe first: page 2 belongs to MSX-DOS whenever MSX-DOS runs, and
;   a mapper segment may be banked in there. Putting
;   the call HERE rather than at every BDOS call siet means every module
;   in the program obeys the rule, including the ones written before the
;   heap existed and the ones not written yet.
;
;   page2_safe preserves every register, so this macro still only clobbers C
;   plus whatever the function itself clobbers.

system		macro	func
		call	page2_safe
		ld	c,func
		call	BDOS
		endm

		ifndef	MSXDOS_INCLUDED
		extrn dos_version	; MSX-DOS2 present?
					; out: A       = major version
					;      CY set  = NOT MSX-DOS2
		extrn print_zero_string	; print the ASCIIZ string at DE
		extrn print_zero_string_upper
					; print the ASCIIZ string at DE, in
					; upper case (filenames)
		extrn print_decimal	; print HL in decimal, no leading zeros
		extrn print_dollar_string
					; write the "$"-terminated string at
					; DE to standard output. REPLACES
					; BDOS 09h: see print_dollar_string in
					; msxdos.as for why there is only one
					; way to write to standard output
		extrn print_char	; write the one character in E
					; in:  E = the character
		extrn page2_safe	; hand page 2 back, spoiling nothing
		extrn dos_exit		; hand control back to MSX-DOS
		endif
