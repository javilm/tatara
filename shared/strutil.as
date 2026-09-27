; strutil.as - small string helpers, shared by every module that needs
; them rather than copied into each one.
;
; The file exists for a nine-byte routine, which needs saying out loud.
; Four modules had their own copy of the same fold - cpupper in
; cmdline.as, dirupr in dirtab.as, mdupr in macros.as, and a fifth written
; into putszu's loop in msxdos.as - and a sixth was nearly typed when
; cond.as wanted a case-insensitive compare for IFIDN. dirupr was made
; global instead, which worked, but left cond.as and expr.as depending on
; the DIRECTIVE TABLE for a general string utility. That is the wrong
; shape, and it is the thing this file fixes.
;
; It is not a size win. One shared copy plus six calls costs about what
; the copies did. What it buys is one answer to "where is the case fold"
; instead of four, and somewhere for the next helper to go - expected
; to be a compare and a copy when something needs them
; twice. Nothing is written here before it has two callers.

STRLIB		equ	1		; skips the external in strutil.inc

		public	strabs
		public	strdirl
		public	strcomp
		public	strbuf
		public	strupr
		public	strdot
		public	strhex
		public	strext
		public	numdec
		public	numhex
		public	numhex2

		include	strutil.inc

		cseg

; strhex - one to four hex digits, as a number.
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

strhex:		ld	hl,0
		ld	b,0		; how many digits so far
strh.lp:	ld	a,(de)
		or	a
		jr	z,strh.end
		ld	a,b
		cp	4
		scf
		ret	z		; a fifth: not an address
		ld	a,(de)
		call	strupr
		sub	"0"
		jr	c,strh.bad
		cp	10
		jr	c,strh.dig
		sub	"A"-"0"		; the seven characters between
		jr	c,strh.bad	;   "9" and "A" land here
		cp	6
		jr	nc,strh.bad
		add	a,10
strh.dig:	add	hl,hl		; times sixteen
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	c,a
		ld	a,l
		or	c
		ld	l,a
		inc	b
		inc	de
		jr	strh.lp
strh.end:	ld	a,b
		or	a
		scf
		ret	z		; "/P:" with nothing after it
		or	a		; CY clear: HL is the number
		ret
strh.bad:	scf
		ret

; strdot - where a filename's extension starts.
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
;   callers want different things of it: strext wants to know whether
;   there is one, and lcmodef wants to cut it off.
;
;   This was lcmdot in lcmd.as, and moved here because
;   arglist.as needs it for ".lnk" and sits below lcmd.as.
;
; Input:	DE -> an ASCIIZ name
; Output:	CY clear = HL -> the dot
;		CY set   = it has none, and HL -> the terminator
; Modifies:	AF, BC, DE, HL

strdot:		ex	de,hl
		ld	bc,0		; BC -> the dot, 0 until one is seen
strd.sc:	ld	a,(hl)
		or	a
		jr	z,strd.end
		cp	"."
		jr	nz,strd.n1
		ld	c,l
		ld	b,h
		jr	strd.nx
strd.n1:	cp	05ch		; the backslash, by its code: written
		jr	z,strd.dir	;   as a character it would sit
		cp	":"		;   awkwardly in this file
		jr	nz,strd.nx
strd.dir:	ld	bc,0		; A SEPARATOR RESETS IT
strd.nx:	inc	hl
		jr	strd.sc
strd.end:	ld	a,b
		or	c
		scf
		ret	z		; no dot: HL is the terminator
		ld	h,b
		ld	l,c
		or	a
		ret

; strext - a default extension, on a name that has none.
;
;   This was lcmextx in lcmd.as.
;
; Input:	DE -> the name, ASCIIZ
;		HL -> the extension: a dot, three characters and a zero
; Output:	it is appended if the name had none
; Modifies:	AF, BC, DE, HL

strext:		push	hl
		call	strdot
		pop	de		; DE -> the extension
		ret	nc		; it has one: leave the name alone
		ex	de,hl		; HL -> the extension, DE -> the end
		ld	bc,5		; four characters and the zero
		ldir
		ret

; strupr - fold the character in A from a-z to A-Z; anything else passes
;   through unchanged.
;
;   The 26 ASCII letters and nothing else, which is what M80 folds. A
;   character above 127 is left alone rather than being folded into some
;   unrelated letter, so a name that uses one stays distinct.
;
; Input:	A = character
; Output:	A = folded character
; Modifies:	AF

strupr:		cp	"a"
		ret	c		; below "a" -> leave it alone
		cp	"z"+1
		ret	nc		; above "z" -> leave it alone
		sub	"a"-"A"
		ret

; numdec - HL as decimal digits, with no leading zeros, into a buffer.
;
;   Subtract-and-count, one power of ten at a time: the same arithmetic
;   putdec used to do for itself. C counts what has been written, which
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

; numhex - HL as four hex digits at DE. numhex2 - A as two.
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

numhex:		ld	a,h
		call	numhex2
		ld	a,l
numhex2:	push	af
		rrca
		rrca
		rrca
		rrca
		call	numhex1
		pop	af
numhex1:	and	0fh
		add	a,"0"
		cp	"9"+1
		jr	c,numhex.p
		add	a,7		; "9"+1 to "A": the seven characters
numhex.p:	ld	(de),a	;   between them in ASCII
		inc	de
		ret

numdec:		push	ix
		push	de
		pop	ix		; IX -> where the next digit goes
		ld	c,0		; nothing written yet
		ld	de,-10000
		call	numdec.dig
		ld	de,-1000
		call	numdec.dig
		ld	de,-100
		call	numdec.dig
		ld	de,-10
		call	numdec.dig
		ld	a,l		; whatever is left is the units digit
		add	a,"0"
		call	numdec.put
		ld	a,c
		pop	ix
		ret

numdec.dig:	ld	a,"0"-1
numdec.sub:	inc	a
		add	hl,de		; CY set while there is still enough
		jr	c,numdec.sub
		sbc	hl,de		; one too far: put it back
		cp	"0"
		jr	nz,numdec.put	; a real digit
		ld	a,c		; a zero. Anything written yet?
		or	a
		ret	z		; no: it is a leading zero, skip it
		ld	a,"0"
numdec.put:	ld	(ix+0),a
		inc	ix
		inc	c
		ret

; --- paths. The first two of these were written inside srcline.as,
;     for the assembler, and moved here when the linker turned out to
;     need all three. There is no byte saved by sharing them - each
;     program links its own copy of this module - only one place where
;     they are written.

; strabs - is this name absolute?
;
;   A LEADING SEPARATOR OR A DRIVE. "B:X.INC" counts, even with no
;   backslash after the colon: it names a drive, and putting a
;   directory in front of it would be nonsense.
;
; Input:	DE -> the name, ASCIIZ
; Output:	CY set = absolute
; Modifies:	AF, HL

strabs:		ld	h,d
		ld	l,e
		ld	a,(hl)
		or	a
		ret	z		; empty: CY is clear
		cp	05ch		; the backslash by its code, as strdot
		jr	z,strab.y	;   above
		inc	hl
		ld	a,(hl)
		cp	":"
		jr	z,strab.y
		or	a		; clears CY
		ret
strab.y:	scf
		ret

; strdirl - how much of a name is the directory part.
;
;   Everything up to and INCLUDING the last separator. A name with
;   none gives zero, which is how "the current directory" is spelled -
;   and that is exactly what a bare name means.
;
; Input:	DE -> an ASCIIZ name
; Output:	A = how many bytes, 0 = none
; Modifies:	AF, BC, HL

strdirl:	ld	h,d
		ld	l,e
		ld	b,0		; B = the answer so far
		ld	c,0		; C = how far we have walked
strdl.f:	ld	a,(hl)
		or	a
		jr	z,strdl.e
		inc	c
		cp	05ch
		jr	z,strdl.mk
		cp	":"
		jr	nz,strdl.nx
strdl.mk:	ld	b,c		; the separator itself is part of it
strdl.nx:	inc	hl
		jr	strdl.f
strdl.e:	ld	a,b
		ret

; strcomp - prefix + separator + name, into strbuf.
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
; Output:	CY clear = strbuf holds the composed name
;		CY set   = it would not fit in DOSPATH
;		HL -> the prefix's terminator, either way
; Modifies:	AF, BC, DE, HL

strcomp:	ld	(strcnam),de
		ld	(strcpfx),hl
		ld	b,0		; B = how long the prefix is
strc.m:		ld	a,(hl)
		or	a
		jr	z,strc.me
		cp	";"
		jr	z,strc.me
		inc	hl
		inc	b
		jr	strc.m
strc.me:	push	hl		; the terminator, handed back below
		xor	a
		ld	(strcsep),a	; does a separator have to go between?
		ld	a,b
		or	a
		jr	z,strc.nm	; an empty prefix: no
		dec	hl
		ld	a,(hl)		; its last character
		cp	05ch
		jr	z,strc.nm	; already ends in one: no
		cp	":"
		jr	z,strc.nm	; a bare drive: no
		ld	a,1
		ld	(strcsep),a
strc.nm:	ld	hl,(strcnam)	; E = how long the name is
		ld	e,0
strc.n2:	ld	a,(hl)
		or	a
		jr	z,strc.n2e
		inc	hl
		inc	e
		jr	strc.n2
strc.n2e:	ld	a,(strcsep)
		add	a,b		; what the prefix costs, at most 129
		cp	DOSPATH
		jr	nc,strc.long	; the prefix alone does not fit
		ld	d,a
		ld	a,DOSPATH-1
		sub	d		; room left for the name
		cp	e
		jr	c,strc.long
		ld	hl,(strcpfx)	; it fits: build it
		ld	de,strbuf
		ld	c,b
		ld	b,0
		ld	a,c
		or	a
		jr	z,strc.cs
		ldir			; the prefix, without its terminator
strc.cs:	ld	a,(strcsep)
		or	a
		jr	z,strc.cn
		ld	a,05ch
		ld	(de),a
		inc	de
strc.cn:	ld	hl,(strcnam)
strc.cnl:	ld	a,(hl)
		ld	(de),a
		or	a		; A = 0 here clears CY as well
		jr	z,strc.done
		inc	hl
		inc	de
		jr	strc.cnl
strc.done:	pop	hl		; the prefix's terminator
		ret

strc.long:	pop	hl		; the same, so the caller can step to
		scf			;   the next entry
		ret

		dseg

strbuf:		defs	DOSPATH	; the composed path. ONE buffer for both
				;   programs, because every caller opens it
				;   at once and none of them keeps it
strcnam:	defs	2	; strcomp: the name it was given
strcpfx:	defs	2	; strcomp: where that prefix starts
strcsep:	defs	1	; strcomp: 1 = a separator goes between
