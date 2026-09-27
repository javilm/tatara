; msxdos.as - the small MSX-DOS services Tatara needs everywere.

MSXDOS		equ	1		; skips the externals in msxdos.nc

		public	dosver
		public	putsz
		public	putszu
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

putsz:		ld	a,(de)
		or	a
		ret	z		; the terminator -> done
		push	de
		ld	e,a
		system	_CONOUT
		pop	de
		inc	de
		jr	putsz

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
		system	_CONOUT
		pop	de
		inc	de
		jr	putszu

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
		ld	b,a
		ld	hl,pdbuf
putdec.pr:	push	bc
		push	hl
		ld	e,(hl)
		system	_CONOUT
		pop	hl
		pop	bc
		inc	hl
		djnz	putdec.pr
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

pdbuf:		defs	5		; putdec: the digits numdec writes
