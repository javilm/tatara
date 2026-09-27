; lobj.as - reading a Tatara object file, one record at a time.
;
; The file is read FORWARD ONLY. Both of the linker's passes are
; sequential, so nothing here seeks backwards and nothing buffers
; more than one field at a time - MSX-DOS does the buffering, and a
; record's fields are read as they are wanted.
;
; THE LENGTH FIELD IS WHAT MAKES THIS WORK. A record whose type this
; program does not know is skipped by its length without being
; understood, which is the property spec 5 is about and the dump in
; tanren.as demonstrates.

LOBJLIB		equ	1	; skips the externals in lobj.inc

		public	lobopen
		public	lobnext
		public	lobpay
		public	lobstr
		public	lobskip
		public	lobend
		public	lobclose
		public	lobtyp
		public	lobleft
		public	lobbuf
		public	lobsln
		public	lobgot

		include	lobj.inc
		include	lerrs.inc	; errlopn, errlmag, errlver, errltrn
		include	msxdos.inc	; _OPEN, _READ, _SEEK, _CLOSE

		cseg

; lobrd - HL bytes into DE: all of them, or carry.
;
;   MSX-DOS 2 answers a short read with the .EOF error AND the number
;   of bytes it did manage, so lobgot is kept either way. The
;   difference between "nothing at all" and "one byte of a three-byte
;   header" is the difference between a file that ended and a file
;   that was cut, and lobnext tells them apart by that count.
;
; Input:	HL = how many
;		DE -> where
; Output:	CY clear = all of them arrived
;		CY set   = fewer, or an error. lobgot says how many
; Modifies:	AF, BC, DE, HL

lobrd:		ld	(lobwant),hl
		ld	a,(lobhand)
		ld	b,a
		system	_READ		; -> A = error, HL = bytes read
		ld	(lobgot),hl	; BDOS gives the count either way
		or	a
		scf
		ret	nz
		ld	de,(lobwant)
		or	a		; all of them?
		sbc	hl,de
		ret	z
		scf
		ret

; lobopen - open the object file and check its header.
;
; Input:	DE -> the ASCIIZ filename
; Output:	the file is open (the three errors do not return)
; Modifies:	AF, BC, DE, HL

lobopen:	ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error, B = handle
		or	a
		jp	nz,errlopn
		ld	a,b
		ld	(lobhand),a
		ld	de,lobbuf
		ld	hl,5
		call	lobrd
		jp	c,errlmag	; a file too short to be one
		ld	a,(lobbuf)
		cp	"T"
		jp	nz,errlmag
		ld	a,(lobbuf+1)
		cp	"R"
		jp	nz,errlmag
		ld	a,(lobbuf+2)
		cp	"O"
		jp	nz,errlmag
		ld	a,(lobbuf+3)
		cp	01ah		; the stopper, so TYPE prints "TRO"
		jp	nz,errlmag	;   and stops
		ld	a,(lobbuf+4)
		cp	TROVER
		jp	nz,errlver	; a Tatara object, but not ours
		ret

; lobnext - the next record's header.
;
; Input:	nothing
; Output:	CY clear = lobtyp and lobleft describe a record
;		CY set   = the file ended cleanly, after the last one
;		(errltrn does not return)
; Modifies:	AF, BC, DE, HL

lobnext:	ld	de,lobbuf
		ld	hl,3
		call	lobrd
		jr	nc,lobn.got
		ld	hl,(lobgot)	; nothing at all is a clean end;
		ld	a,h		;   one or two bytes is a header
		or	l		;   that was cut in half
		jp	nz,errltrn
		scf
		ret
lobn.got:	ld	a,(lobbuf)
		ld	(lobtyp),a
		ld	hl,(lobbuf+1)
		ld	(lobleft),hl
		or	a		; CY clear: a record is open
		ret

; lobpay - A bytes of the open record's payload.
;
;   TWO CHECKS, and they catch different lies. lobrd catches a file
;   that is shorter than the record says; the subtraction catches a
;   record that says less than its fields need.
;
; Input:	A  = how many, 1 to 255
;		DE -> where they go
; Output:	they are there, and lobleft is that much smaller
;		(errltrn does not return)
; Modifies:	AF, BC, DE, HL

lobpay:		ld	l,a
		ld	h,0
		ld	(lobn),hl
		call	lobrd		; DE is already where they go
		jp	c,errltrn
		ld	hl,(lobleft)
		ld	de,(lobn)
		or	a
		sbc	hl,de
		jp	c,errltrn
		ld	(lobleft),hl
		ret

; lobstr - one string: a length byte, then that many bytes.
;
;   Zero-terminated in lobbuf, because everything that prints a name
;   here goes through putsz. A length of 0 is forbidden by the format
;   (spec 8), so it is a broken file and not an empty name.
;
; Input:	nothing
; Output:	lobbuf holds it, lobsln is its length
; Modifies:	AF, BC, DE, HL

lobstr:		ld	de,lobsln
		ld	a,1
		call	lobpay
		ld	a,(lobsln)
		or	a
		jp	z,errltrn
		ld	de,lobbuf
		call	lobpay		; A is still the length
		ld	hl,lobbuf
		ld	a,(lobsln)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	(hl),0
		ret

; lobskip - whatever is left of the open record.
;
;   A FORWARD SEEK. "Sequential, no backward seeking" forbids going
;   back, not going on, and reading tatara.tro's DATA records into a
;   buffer to throw them away would move six kilobytes for nothing.
;
; Input:	nothing
; Output:	the record is consumed (errltrn does not return)
; Modifies:	AF, BC, DE, HL

lobskip:	ld	hl,(lobleft)
		ld	a,h
		or	l
		ret	z		; nothing left: END is like this
		ld	hl,(lobleft)	; DE:HL = how far, DE THE HIGH WORD.
		ld	de,0		;   The other way round asks for a
					;   seek of 12 * 65536, which MSX-DOS
					;   grants by stopping at the end of
					;   the file - no error, and the next
					;   read says the records ran out
		ld	a,(lobhand)
		ld	b,a
		ld	a,1		; 1 = from where we are
		system	_SEEK
		or	a
		jp	nz,errltrn
		ld	hl,0
		ld	(lobleft),hl
		ret

; lobend - after the last record, is that the end of the file?
;
;   One byte is asked for. Getting it means something follows the END
;   record, which is legal (spec 11 says a reader ignores it) but
;   worth saying out loud, because for Tatara's own writer it would
;   mean a length that did not add up.
;
; Input:	nothing
; Output:	CY clear = the file ends exactly here
;		CY set   = at least one byte follows
; Modifies:	AF, BC, DE, HL

lobend:		ld	de,lobbuf
		ld	hl,1
		call	lobrd
		ccf			; lobrd's carry means NOTHING was
		ret			;   there, which is the good answer

; lobclose - done with the file.
;
; Input:	nothing
; Output:	the handle is closed
; Modifies:	AF, BC

lobclose:	ld	a,(lobhand)
		ld	b,a
		system	_CLOSE
		ret

		dseg

lobhand:	defs	1	; MSX-DOS's handle for the object file
lobtyp:		defs	1	; the open record's type
lobleft:	defs	2	;   and how much of its payload is unread
lobwant:	defs	2	; lobrd: how many bytes were asked for,
lobgot:		defs	2	;   and how many came back
lobn:		defs	2	; lobpay: this call's count
lobsln:		defs	1	; lobstr: the length byte it just read
lobbuf:		defs	LMAXSTR	; and the string itself, terminated
