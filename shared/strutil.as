; strutil.as - small string helpers, shared by every module that needs
; them rather than copied into each one.
;
; The file exists for a nine-byte routine, which needs saying out loud.
; Four modules had their own copy of the same fold - cpupper in
; cmdline.as, dirupr in dirtab.as, mdupr in macros.as, and a fifth written
; into print_zero_string_upper's loop in msxdos.as - and a sixth was nearly
; typed when cond.as wanted a case-insensitive compare for IFIDN. dirupr was
; made global instead, which worked, but left cond.as and expr.as depending on
; the DIRECTIVE TABLE for a general string utility. That is the wrong shape,
; and it is the thing this file fixes.
;
; It is not a size win. One shared copy plus six calls costs about what
; the copies did. What it buys is one answer to "where is the case fold"
; instead of four, and somewhere for the next helper to go - expected
; to be a compare and a copy when something needs them
; twice. Nothing is written here before it has two callers.

STRUTIL_INCLUDED	equ	1	; skips the external in strutil.inc

		public	is_absolute_name
		public	directory_length
		public	compose_path
		public	path_buffer
		public	fold_to_upper
		public	find_extension
		public	parse_hex_number
		public	add_default_extension
		public	build_decimal
		public	build_hex_word
		public	build_hex_byte

		include	strutil.inc

		cseg

; parse_hex_number - one to four hex digits, as a number.
;
;   NO SUFFIX AND NO DECIMAL. M80 writes 0C000h because an expression
;   has to tell a number from a symbol; a command-line option has no
;   such problem, and L80's /P: has always been plain hex. Accepting
;   decimal as well would make /P:100 mean two things to two people.
;
;   Sixteen is four add hl,hl, so there is no multiplication here.
;
; Input:	DE -> the digits, ASCIIZ
; Output:	CY clear = HL is the number
;		CY set   = it is not one to four hex digits
; Modifies:	AF, BC, DE, HL

parse_hex_number:
		ld	hl,0
		ld	b,0		; how many digits so far
parse_hex_number.loop:
		ld	a,(de)
		or	a
		jr	z,parse_hex_number.done
		ld	a,b
		cp	4
		scf
		ret	z		; a fifth: not an address
		ld	a,(de)
		call	fold_to_upper
		sub	"0"
		jr	c,parse_hex_number.bad
		cp	10
		jr	c,parse_hex_number.digit
		sub	"A"-"0"		; the seven characters between
		jr	c,parse_hex_number.bad	;   "9" and "A" land here
		cp	6
		jr	nc,parse_hex_number.bad
		add	a,10
parse_hex_number.digit:
		add	hl,hl		; times sixteen
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	c,a
		ld	a,l
		or	c
		ld	l,a
		inc	b
		inc	de
		jr	parse_hex_number.loop
parse_hex_number.done:
		ld	a,b
		or	a
		scf
		ret	z		; "/P:" with nothing after it
		or	a		; CY clear: HL is the number
		ret
parse_hex_number.bad:
		scf
		ret

; find_extension - where a filename's extension starts.
;
;   THE LAST DOT AFTER THE LAST SEPARATOR. A separator resets the
;   search, because the dot in "A:\V1.0\FOO" belongs to the directory
;   and not to the file - which is the whole difficulty in what
;   otherwise looks like a one-line job.
;
;   A trailing dot counts as an extension, an empty one: "FOO." is
;   MS-DOS's way of saying "no extension, and I mean it".
;
;   IT ANSWERS WITH A POSITION rather than a yes or no, because its
;   callers want different things of it: add_default_extension wants to know
;   whether there is one, and default_output_name wants to cut it off.
;
;   This was lcmdot in lcmd.as, and moved here because
;   arglist.as needs it for ".lnk" and sits below lcmd.as.
;
; Input:	DE -> an ASCIIZ name
; Output:	CY clear = HL -> the dot
;		CY set   = it has none, and HL -> the terminator
; Modifies:	AF, BC, DE, HL

find_extension:	ex	de,hl
		ld	bc,0		; BC -> the dot, 0 until one is seen
find_extension.scan:
		ld	a,(hl)
		or	a
		jr	z,find_extension.done
		cp	"."
		jr	nz,find_extension.not_dot
		ld	c,l
		ld	b,h
		jr	find_extension.next
find_extension.not_dot:
		cp	05ch		; the backslash, by its code: written
		jr	z,find_extension.separator
					;   as a character it would sit
		cp	":"		;   awkwardly in this file
		jr	nz,find_extension.next
find_extension.separator:
		ld	bc,0		; A SEPARATOR RESETS IT
find_extension.next:
		inc	hl
		jr	find_extension.scan
find_extension.done:
		ld	a,b
		or	c
		scf
		ret	z		; no dot: HL is the terminator
		ld	h,b
		ld	l,c
		or	a
		ret

; add_default_extension - a default extension, on a name that has none.
;
;   This was lcmextx in lcmd.as.
;
; Input:	DE -> the name, ASCIIZ
;		HL -> the extension: a dot, three characters and a zero
; Output:	it is appended if the name had none
; Modifies:	AF, BC, DE, HL

add_default_extension:
		push	hl
		call	find_extension
		pop	de		; DE -> the extension
		ret	nc		; it has one: leave the name alone
		ex	de,hl		; HL -> the extension, DE -> the end
		ld	bc,5		; four characters and the zero
		ldir
		ret

; fold_to_upper - fold the character in A from a-z to A-Z; anything else passes
;   through unchanged.
;
;   The 26 ASCII letters and nothing else, which is what M80 folds. A
;   character above 127 is left alone rather than being folded into some
;   unrelated letter, so a name that uses one stays distinct.
;
; Input:	A = character
; Output:	A = folded character
; Modifies:	AF

fold_to_upper:	cp	"a"
		ret	c		; below "a" -> leave it alone
		cp	"z"+1
		ret	nc		; above "z" -> leave it alone
		sub	"a"-"A"
		ret

; build_decimal - HL as decimal digits, with no leading zeros, into a buffer.
;
;   Subtract-and-count, one power of ten at a time: the same arithmetic
;   print_decimal used to do for itself. C counts what has been written, which
;   is also how a leading zero is recognised - nothing written yet. The
;   units digit is written whatever C says, so 0 comes out as "0" rather
;   than as nothing at all.
;
;   IX is the write pointer because DE holds the power of ten and HL the
;   number being reduced, and the z80 has nothing else left.
;
; Input:	HL = the number, 0 to 65535
; 		DE -> a buffer of at least 5 bytes
; Output:	A  = how many digits were written, 1 to 5
; 		the digits are at the START of the buffer
; Modifies:	AF, BC, DE, HL

; build_hex_word - HL as four hex digits at DE. build_hex_byte - A as two.
;
;   The first hex output in the program: every number so far has been
;   decimal, because every number so far has been a line or a count. An
;   address is read in hex, M80 prints them in hex, and the listing
;   compares against M80's.
;
;   No leading-zero suppression and none wanted: a listing column that
;   changes width is a listing column that cannot be read down.
;
; Input:	HL or A = the number
;		DE -> where to put the digits
; Output:	DE has moved on by four or two
; Modifies:	AF, DE

build_hex_word:	ld	a,h
		call	build_hex_byte
		ld	a,l
build_hex_byte:	push	af
		rrca
		rrca
		rrca
		rrca
		call	build_hex_nibble
		pop	af
build_hex_nibble:
		and	0fh
		add	a,"0"
		cp	"9"+1
		jr	c,build_hex_nibble.put
		add	a,7		; "9"+1 to "A": the seven characters
build_hex_nibble.put:
		ld	(de),a	;   between them in ASCII
		inc	de
		ret

build_decimal:	push	ix
		push	de
		pop	ix		; IX -> where the next digit goes
		ld	c,0		; nothing written yet
		ld	de,-10000
		call	build_decimal.digit
		ld	de,-1000
		call	build_decimal.digit
		ld	de,-100
		call	build_decimal.digit
		ld	de,-10
		call	build_decimal.digit
		ld	a,l		; whatever is left is the units digit
		add	a,"0"
		call	build_decimal.put
		ld	a,c
		pop	ix
		ret

build_decimal.digit:
		ld	a,"0"-1
build_decimal.subtract:
		inc	a
		add	hl,de		; CY set while there is still enough
		jr	c,build_decimal.subtract
		sbc	hl,de		; one too far: put it back
		cp	"0"
		jr	nz,build_decimal.put	; a real digit
		ld	a,c		; a zero. Anything written yet?
		or	a
		ret	z		; no: it is a leading zero, skip it
		ld	a,"0"
build_decimal.put:
		ld	(ix+0),a
		inc	ix
		inc	c
		ret

; --- paths. The first two of these were written inside srcline.as,
;     for the assembler, and moved here when the linker turned out to
;     need all three. There is no byte saved by sharing them - each
;     program links its own copy of this module - only one place where
;     they are written.

; is_absolute_name - is this name absolute?
;
;   A LEADING SEPARATOR OR A DRIVE. "B:X.INC" counts, even with no
;   backslash after the colon: it names a drive, and putting a
;   directory in front of it would be nonsense.
;
; Input:	DE -> the name, ASCIIZ
; Output:	CY set = absolute
; Modifies:	AF, HL

is_absolute_name:
		ld	h,d
		ld	l,e
		ld	a,(hl)
		or	a
		ret	z		; empty: CY is clear
		cp	05ch	; the backslash by its code, as find_extension
		jr	z,is_absolute_name.yes	;   above
		inc	hl
		ld	a,(hl)
		cp	":"
		jr	z,is_absolute_name.yes
		or	a		; clears CY
		ret
is_absolute_name.yes:
		scf
		ret

; directory_length - how much of a name is the directory part.
;
;   Everything up to and INCLUDING the last separator. A name with
;   none gives zero, which is how "the current directory" is spelled -
;   and that is exactly what a bare name means.
;
; Input:	DE -> an ASCIIZ name
; Output:	A = how many bytes, 0 = none
; Modifies:	AF, BC, HL

directory_length:
		ld	h,d
		ld	l,e
		ld	b,0		; B = the answer so far
		ld	c,0		; C = how far we have walked
directory_length.find:
		ld	a,(hl)
		or	a
		jr	z,directory_length.done
		inc	c
		cp	05ch
		jr	z,directory_length.mark
		cp	":"
		jr	nz,directory_length.next
directory_length.mark:
		ld	b,c		; the separator itself is part of it
directory_length.next:
		inc	hl
		jr	directory_length.find
directory_length.done:
		ld	a,b
		ret

; compose_path - prefix + separator + name, into path_buffer.
;
;   THE PREFIX ENDS AT A ZERO OR A SEMICOLON, which is what lets one
;   routine serve both a directory taken from a table and one entry of
;   a ";"-separated path list. No entry is ever copied out of the list.
;
;   An EMPTY prefix produces the name unchanged - that is how "the
;   current directory" is spelled - and a prefix already ending in a
;   separator gets none added.
;
;   The prefix is walked to its terminator EVEN WHEN THE RESULT WILL
;   NOT FIT, because the caller needs that terminator to reach the next
;   entry.
;
; Input:	HL -> the prefix, ended by 0 or ";"
;		DE -> the name, ASCIIZ
; Output:	CY clear = path_buffer holds the composed name
;		CY set   = it would not fit in DOS_PATH_MAX
;		HL -> the prefix's terminator, either way
; Modifies:	AF, BC, DE, HL

compose_path:	ld	(compose_name),de
		ld	(compose_prefix),hl
		ld	b,0		; B = how long the prefix is
compose_path.measure_prefix:
		ld	a,(hl)
		or	a
		jr	z,compose_path.prefix_done
		cp	";"
		jr	z,compose_path.prefix_done
		inc	hl
		inc	b
		jr	compose_path.measure_prefix
compose_path.prefix_done:
		push	hl		; the terminator, handed back below
		xor	a
		; does a separator have to go between?
		ld	(compose_separator),a
		ld	a,b
		or	a
		jr	z,compose_path.measure_name	; an empty prefix: no
		dec	hl
		ld	a,(hl)		; its last character
		cp	05ch
		jr	z,compose_path.measure_name
					; already ends in one: no
		cp	":"
		jr	z,compose_path.measure_name	; a bare drive: no
		ld	a,1
		ld	(compose_separator),a
compose_path.measure_name:
		ld	hl,(compose_name)	; E = how long the name is
		ld	e,0
compose_path.measure_char:
		ld	a,(hl)
		or	a
		jr	z,compose_path.measured
		inc	hl
		inc	e
		jr	compose_path.measure_char
compose_path.measured:
		ld	a,(compose_separator)
		add	a,b		; what the prefix costs, at most 129
		cp	DOS_PATH_MAX
		jr	nc,compose_path.too_long
					; the prefix alone does not fit
		ld	d,a
		ld	a,DOS_PATH_MAX-1
		sub	d		; room left for the name
		cp	e
		jr	c,compose_path.too_long
		ld	hl,(compose_prefix)	; it fits: build it
		ld	de,path_buffer
		ld	c,b
		ld	b,0
		ld	a,c
		or	a
		jr	z,compose_path.separator
		ldir			; the prefix, without its terminator
compose_path.separator:
		ld	a,(compose_separator)
		or	a
		jr	z,compose_path.copy_name
		ld	a,05ch
		ld	(de),a
		inc	de
compose_path.copy_name:
		ld	hl,(compose_name)
compose_path.copy_char:
		ld	a,(hl)
		ld	(de),a
		or	a		; A = 0 here clears CY as well
		jr	z,compose_path.done
		inc	hl
		inc	de
		jr	compose_path.copy_char
compose_path.done:
		pop	hl		; the prefix's terminator
		ret

compose_path.too_long:
		pop	hl		; the same, so the caller can step to
		scf			;   the next entry
		ret

		dseg

path_buffer:	defs	DOS_PATH_MAX
				; the composed path. ONE buffer for both
				;   programs, because every caller opens it
				;   at once and none of them keeps it
compose_name:	defs	2	; compose_path: the name it was given
compose_prefix:	defs	2	; compose_path: where that prefix starts
compose_separator:
		defs	1	; compose_path: 1 = a separator goes between
