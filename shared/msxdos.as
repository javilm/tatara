; msxdos.as - the small MSX-DOS services Tatara needs everywere.

MSXDOS		equ	1		; skips the externals in msxdos.nc

		public	dosver
		public	putsz
		public	putszu
		public	putstr
		public	putch
		public	dosexit
		public	putdec
		public	p2safe

		include	msxdos.inc
		include	alloc.inc
		include	strutil.inc

		cseg

; dosver - find out whether we are running under MSX-DOS2 (or Nextor).
;
;   BDOS function 6Fh exists noly from MSX-DOS2 onwards. Under MSX-DOS1
;   the call does nothing at all, so B is loaded with 1 first and still
;   holds 1 when the call returns.
;
; Input:	nothing
; Output:	A      = MSX-DOS major version (1 = DOS1, 2 or more = DOS2)
;		CY set = NOT MSX-DOS, so the caller can use "jr c,..."
; Modifies:	AB, BC, DE, HL

dosver:		ld	b,1		; the value DOS1 will leave untouched
		system	_DOSVER		; DOS2 -> B = the major version
		ld	a,b
		cp	2
		ret	nc		; 2 or more -> DOS2, carry clear
		scf			; otherwise -> carry set
		ret

; putsz - print the zero-terminated string at DE.
;
;   BDOS function 09h stops at a "$", which is no use for filenames, so
;   this walks the string and prints one character at a time.
;
; Input:	DE -> zero-terminated string
; Output:	the string is printed
; Modifies:	AB, BC, DE, HL

putsz:		ld	h,d		; measure first, then one _WRITE:
		ld	l,e		;   see putstr below for why every
		ld	bc,0		;   path to standard output has to be
putsz.m:	ld	a,(hl)		;   the same one
		or	a
		jr	z,putsz.go
		inc	hl
		inc	bc
		jr	putsz.m
putsz.go:	ld	h,b
		ld	l,c
		ld	a,h
		or	l
		ret	z		; an empty string writes nothing
		ld	b,STDOUT
		system	_WRITE
		ret

; putszu - print the zero-terminated string at DE, folding a-z to A-Z.
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

putszu:		ld	a,(de)
		or	a
		ret	z		; the terminator -> done
		call	strupr
		push	de
		ld	e,a
		call	putch
		pop	de
		inc	de
		jr	putszu

; putstr - write the "$"-terminated string at DE to standard output.
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
;   function. dosver is the first call in the program and the message
;   saying so is the only one that can be printed before it, so that
;   one message keeps 09h - see main.dos1 in tatara.as and tanren.as.
;
;   A WRITE ERROR IS IGNORED. emitraw reports one by printing a
;   message, and here a message is what has just failed.
;
; Input:	DE -> the string, "$" terminated
; Output:	it is written to standard output
; Modifies:	AF, BC, DE, HL

putstr:		ld	h,d
		ld	l,e
		ld	bc,0
putstr.m:	ld	a,(hl)
		cp	"$"
		jr	z,putstr.go
		inc	hl
		inc	bc
		jr	putstr.m
putstr.go:	ld	h,b
		ld	l,c
		ld	a,h
		or	l
		ret	z		; "$" first: nothing to write
		ld	b,STDOUT
		system	_WRITE
		ret

; putch - write the one character in E to standard output.
;
;   _WRITE takes an address and a length, so the character has to be
;   somewhere. pcbuf is that somewhere.
;
; Input:	E = the character
; Output:	it is written to standard output
; Modifies:	AF, BC, DE, HL

putch:		ld	a,e
		ld	(pcbuf),a
		ld	de,pcbuf
		ld	hl,1
		ld	b,STDOUT
		system	_WRITE
		ret

; dosexit - hand control back to MSX-DOS2.
;
; Input:	nothing
; Output:	does not return

dosexit:	system	_TERM0
		ret			; never reached

; putdec - print HL in decimal, with no leading zeros.
;
;   The arithmetic moved to numdec in strutil.as when something needed
;   digits written into a macro argument instead of onto the screen. What
;   is left here is the printing.
;
; Input:	HL = the number, 0 to 65535
; Output:	the number is printed
; Modifies:	AF, BC, DE, HL

putdec:		ld	de,pdbuf
		call	numdec		; A = how many digits
		or	a
		ret	z		; no digits: nothing to write
		ld	l,a		; HL = how many numdec wrote
		ld	h,0
		ld	de,pdbuf
		ld	b,STDOUT
		system	_WRITE
		ret

; p2safe - hand page 2 back to MSX-DOS without disturbing anything.
;
;   p2restore modifies AF, BC, DE and HL, which is exactly what a BDOS
;   call needs left alone - DE usually points at the string or buffer the
;   call is about to use. So it is wrapped once, here, and the "system"
;   macro calls this instead.
;
;   Safe before heapinit has run: p2restore is documented as a no-op
;   until then, which matters because dosver is called first of all.
;
; Input:	nothing
; Output:	page 2 belongs to MSX-DOS
; Modifies:	nothing

p2safe:		push	af
		push	bc
		push	de
		push	hl
		call	p2restore
		pop	hl
		pop	de
		pop	bc
		pop	af
		ret
		
		dseg

pcbuf:		defs	1	; putch: _WRITE wants an address and a
				;   length, so one character needs one byte
pdbuf:		defs	5		; putdec: the digits numdec writes
