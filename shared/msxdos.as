; msxdos.as - the small MSX-DOS services Tatara needs everywere.

MSXDOS_INCLUDED	equ	1		; skips the externals in msxdos.nc

		public	dos_version
		public	print_zero_string
		public	print_zero_string_upper
		public	print_dollar_string
		public	print_char
		public	dos_exit
		public	print_decimal
		public	page2_safe

		include	msxdos.inc
		include	alloc.inc
		include	strutil.inc

		cseg

; dos_version - find out whether we are running under MSX-DOS2 (or Nextor).
;
;   BDOS function 6Fh exists noly from MSX-DOS2 onwards. Under MSX-DOS1
;   the call does nothing at all, so B is loaded with 1 first and still
;   holds 1 when the call returns.
;
; Input:	nothing
; Output:	A      = MSX-DOS major version (1 = DOS1, 2 or more = DOS2)
;		CY set = NOT MSX-DOS, so the caller can use "jr c,..."
; Modifies:	AB, BC, DE, HL

dos_version:	ld	b,1		; the value DOS1 will leave untouched
		system	_DOSVER		; DOS2 -> B = the major version
		ld	a,b
		cp	2
		ret	nc		; 2 or more -> DOS2, carry clear
		scf			; otherwise -> carry set
		ret

; print_zero_string - print the zero-terminated string at DE.
;
;   BDOS function 09h stops at a "$", which is no use for filenames, so
;   this walks the string and prints one character at a time.
;
; Input:	DE -> zero-terminated string
; Output:	the string is printed
; Modifies:	AB, BC, DE, HL

print_zero_string:
		ld	h,d		; measure first, then one _WRITE:
		ld	l,e	;   see print_dollar_string below for why every
		ld	bc,0		;   path to standard output has to be
print_zero_string.measure:
		ld	a,(hl)		;   the same one
		or	a
		jr	z,print_zero_string.write
		inc	hl
		inc	bc
		jr	print_zero_string.measure
print_zero_string.write:
		ld	h,b
		ld	l,c
		ld	a,h
		or	l
		ret	z		; an empty string writes nothing
		ld	b,STDOUT
		system	_WRITE
		ret

; print_zero_string_upper - print the zero-terminated string at DE, folding a-z
; to A-Z.
;
;   Filenames are printed in upper case throughout Tatara, so that a name
;   is easy to pick out of a sentence of ordinary text. It also evens out
;   an inconsistency: a name from the command tail has already been folded
;   by MSX-DOS, while a name from an INCLUDE operand is whatever the
;   programmer typed.
;
;   The fold itself is strutil.as's, which is where all four copies of it
;   ended up.
;
; Input:	DE -> zero-terminated string
; Output:	the string is printed, in upper case
; Modifies:	AF, BC, DE, HL

print_zero_string_upper:
		ld	a,(de)
		or	a
		ret	z		; the terminator -> done
		call	fold_to_upper
		push	de
		ld	e,a
		call	print_char
		pop	de
		inc	de
		jr	print_zero_string_upper

; print_dollar_string - write the "$"-terminated string at DE to standard
; output.
;
;   IT REPLACES BDOS 09h EVERYWHERE. Standard output used to be
;   written two ways: 09h and 02h for messages, and _WRITE on a handle
;   for the listing, whose bytes are arbitrary and so cannot go
;   through a call that stops at a "$". Redirected, both landed in one
;   file by two mechanisms, each with its own idea of where the file
;   position was. Nothing was ever proved to go wrong because of it -
;   the bug that prompted the change turned out to be the emulator's -
;   but one mechanism is simpler than two and 243 bytes smaller, which
;   is reason enough on its own.
;
;   THE "$" TERMINATOR STAYS so that every call site keeps the string
;   it already had.
;
;   NOT USABLE UNDER MSX-DOS 1, which has no handles: _WRITE is a DOS 2
;   function. dos_version is the first call in the program and the message
;   saying so is the only one that can be printed before it, so that
;   one message keeps 09h - see main.need_dos2 in tatara.as and tanren.as.
;
;   A WRITE ERROR IS IGNORED. write_output reports one by printing a
;   message, and here a message is what has just failed.
;
; Input:	DE -> the string, "$" terminated
; Output:	it is written to standard output
; Modifies:	AF, BC, DE, HL

print_dollar_string:
		ld	h,d
		ld	l,e
		ld	bc,0
print_dollar_string.measure:
		ld	a,(hl)
		cp	"$"
		jr	z,print_dollar_string.write
		inc	hl
		inc	bc
		jr	print_dollar_string.measure
print_dollar_string.write:
		ld	h,b
		ld	l,c
		ld	a,h
		or	l
		ret	z		; "$" first: nothing to write
		ld	b,STDOUT
		system	_WRITE
		ret

; print_char - write the one character in E to standard output.
;
;   _WRITE takes an address and a length, so the character has to be
;   somewhere. char_buffer is that somewhere.
;
; Input:	E = the character
; Output:	it is written to standard output
; Modifies:	AF, BC, DE, HL

print_char:	ld	a,e
		ld	(char_buffer),a
		ld	de,char_buffer
		ld	hl,1
		ld	b,STDOUT
		system	_WRITE
		ret

; dos_exit - hand control back to MSX-DOS2.
;
; Input:	nothing
; Output:	does not return

dos_exit:	system	_TERM0
		ret			; never reached

; print_decimal - print HL in decimal, with no leading zeros.
;
;   The arithmetic moved to build_decimal in strutil.as when something needed
;   digits written into a macro argument instead of onto the screen. What
;   is left here is the printing.
;
; Input:	HL = the number, 0 to 65535
; Output:	the number is printed
; Modifies:	AF, BC, DE, HL

print_decimal:	ld	de,decimal_buffer
		call	build_decimal	; A = how many digits
		or	a
		ret	z		; no digits: nothing to write
		ld	l,a		; HL = how many build_decimal wrote
		ld	h,0
		ld	de,decimal_buffer
		ld	b,STDOUT
		system	_WRITE
		ret

; page2_safe - hand page 2 back to MSX-DOS without disturbing anything.
;
;   page2_restore modifies AF, BC, DE and HL, which is exactly what a BDOS
;   call needs left alone - DE usually points at the string or buffer the
;   call is about to use. So it is wrapped once, here, and the "system"
;   macro calls this instead.
;
;   Safe before heap_init has run: page2_restore is documented as a no-op
;   until then, which matters because dos_version is called first of all.
;
; Input:	nothing
; Output:	page 2 belongs to MSX-DOS
; Modifies:	nothing

page2_safe:	push	af
		push	bc
		push	de
		push	hl
		call	page2_restore
		pop	hl
		pop	de
		pop	bc
		pop	af
		ret

		dseg

char_buffer:	defs	1	; print_char: _WRITE wants an address and a
				;   length, so one character needs one byte
decimal_buffer:	defs	5
			; print_decimal: the digits build_decimal writes
