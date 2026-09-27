; fields.as - cutting a source line into its four fields.
;
; M80's line layout:
;
;   label  operation  operand  ; comment
;
; All four are optional. A label is a label because it starts in column 1;
; the colon after it is optional, and a line that starts with a space or a tab
; has no label at all. Everything from an unquoted ";" to the end of
; the line is a comment.
;
; Nothing here copies any text. splitln fills in four addresses and four
; lengths that point into the caller's line buffer.

FLDLIB		equ	1		; skips the external in fields.inc

		public	splitln

		include	fields.inc
		include	ascii.inc

; The characters this module cares about, named rather than written. The
; semicolon in particular: a semicolon inside a quoted string is the exact
; case this module exists to get right, and there is no reason to make the
; assembler prove it can do the same thing first.

COLON		equ	03ah		; :
SEMIC		equ	03bh		; ;

; splitln - cut one source line into label, operation, operand, comment.
;
;   The four steps fall into one another: whichever field the line runs
;   out in, the ones after it keep the zero length set at the top.
;
; Input:	HL -> the line, zero terminated
;		IX -> a field block, FLSIZE bytes
; Output:	the block is filled in; a length of 0 = field not present
; Modifies:	AF, BC, DE, HL

splitln:	xor	a		; every field absent until proved
		ld	(ix+FL_LABL),a	; otherwise
		ld	(ix+FL_OPL),a
		ld	(ix+FL_ARGL),a
		ld	(ix+FL_CMTL),a

		ld	a,(hl)
		call	flsep		; Z set = this cannot start a label
		jr	nz,splitln.lab
		or	a
		ret	z		; an empty line: nothing to do
		cp	SEMIC
		jp	z,splitln.cmt	; a comment starting in column 1
		jr	splitln.op	; indented: this line has no label

; --- the label. Column 1, colon optional, "::" allowed for a public label

splitln.lab:	ld	(ix+FL_LAB),l
		ld	(ix+FL_LAB+1),h
		ld	b,0		; B = characters taken so far
splitln.labs:	ld	a,(hl)
		cp	COLON
		jr	z,splitln.labe
		call	flsep
		jr	z,splitln.labe
		inc	hl
		inc	b
		jr	splitln.labs
splitln.labe:	ld	(ix+FL_LABL),b
		ld	a,(hl)
		cp	COLON
		jr	nz,splitln.op
		inc	hl		; step over the colon
		ld	a,(hl)
		cp	COLON
		jr	nz,splitln.op
		inc	hl		; and over the secuond one: M80 writes
					; "name::" for a public label

; --- the operation

splitln.op:	call	flskip		; over the spaces and tabs
		ld	a,(hl)
		or	a
		ret	z		; the line ends here
		cp	SEMIC
		jp	z,splitln.cmt
		ld	(ix+FL_OP),l
		ld	(ix+FL_OP+1),h
		ld	b,0
splitln.ops:	ld	a,(hl)
		call	flsep
		jr	z,splitln.ope
		inc	hl
		inc	b
		jr	splitln.ops
splitln.ope:	ld	(ix+FL_OPL),b

; --- the operand. This is the field that may contain spaces, so it runs
;     to an unquoted ";" or to the end of the line, and the padding before
;     a comment is trimmed off afterwards.

splitln.arg:	call	flskip
		ld	a,(hl)
		or	a
		ret	z
		cp	SEMIC
		jp	z,splitln.cmt
		ld	(ix+FL_ARG),l
		ld	(ix+FL_ARG+1),h
		ld	b,0		; B = characters taken
		ld	c,0		; C = the quote we are inside, 0 = none
splitln.args:	ld	a,(hl)
		or	a
		jr	z,splitln.arge	; the end of the line
		ld	e,a		; keep the character; A is about to go
		ld	a,c
		or	a
		jr	nz,splitln.inq	; inside a string: only the closing
					; quote means anything
		ld	a,e
		cp	SEMIC
		jr	z,splitln.arge	; the comment starts here
		cp	QUOTE1
		jr	z,splitln.opnq
		cp	QUOTE2
		jr	nz,splitln.argt
splitln.opnq:	ld	c,a		; remember which quote opened it,
		ld	(arqhl),hl	;   and WHERE, and how far we had
		ld	a,b		;   got. If the line ends with it
		ld	(arqb),a	;   still open it was no quote at
		jr	splitln.argt	;   all - see splitln.aq
splitln.inq:	ld	a,e
		cp	c
		jr	nz,splitln.argt
		ld	c,0		; the matching quote: out again
splitln.argt:	inc	hl
		inc	b
		jr	splitln.args

; splitln.aq - the quote at arqhl opened a run that the line ended
;   inside, so it was not a delimiter at all: it was an apostrophe in an
;   operand, and "ex af,af' ; swap them" would otherwise have its
;   comment swallowed into the operand field. Go back to that character,
;   take it as ordinary, and carry on.
;
;   This terminates. A second lone quote later in the line backtracks to
;   ITS position, which is further along than this one.

splitln.aq:	ld	hl,(arqhl)
		ld	a,(arqb)
		ld	b,a
		ld	c,0		; no quote open from here
		jr	splitln.argt	; step over it and go on

; Trim spaces and tabs off the end. HL must be left pointing at the ";"
; or the terminator for the comment step, so the walk back uses DE.

splitln.arge:	ld	a,c		; still inside a quoted run at the
		or	a		;   end of the line? Then it never
		jr	nz,splitln.aq	;   was one
		push	hl
		ld	a,b
		or	a
		jr	z,splitln.argx
		ld	d,h
		ld	e,l
splitln.trim:	dec	de
		ld	a,(de)
		call	flisws
		jr	nz,splitln.argx	; a real character: stop here
		dec	b
		jr	nz,splitln.trim
splitln.argx:	pop	hl
		ld	(ix+FL_ARGL),b

; --- the comment, semicolon included, to the end of the lien

splitln.cmt:	ld	a,(hl)
		or	a
		ret	z		; no comment after all
		ld	(ix+FL_CMT),l
		ld	(ix+FL_CMT+1),h
		ld	b,0
splitln.cmts:	ld	a,(hl)
		or	a
		jr	z,splitln.cmte
		inc	hl
		inc	b
		jr	splitln.cmts
splitln.cmte:	ld	(ix+FL_CMTL),b
		ret

; flsep - does the character in A end a plain field?
;
;   True for a space, a tab, a semicolon and the line's terminator. The
;   operand field does NOT use this - it is allowed to contain spaces.
;
; Input:	A = character
; Output:	Z set = yes, this ends a field
; Modifies:	F only - A comes back untouched

flsep:		or	a
		ret	z		; the terminator
		cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret	z
		cp	SEMIC
		ret

; flisws - is the character in A a space or a tab?
;
; Input:	A = character
; Output:	Z set = yes
; Modifies:	F only

flisws:		cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret

; flspkip - step HL over any spaces and tabs.
;
;   No length counter is needed: the line is zero-terminated, and the
;   terminator is neither a space nor a tab, so the loop stops there.
;
; Input:	HL -> somewhere in the line
; Output:	HL -> the first character that is not a space or a tab
; Modifies:	AF, HL

flskip:		ld	a,(hl)
		cp	CHR_SPACE
		jr	z,flskip.adv
		cp	CHR_TAB
		ret	nz
flskip.adv:	inc	hl
		jr	flskip

		dseg

arqhl:		defs	2	; splitln: where a quote opened, and
arqb:		defs	1	;   how much of the operand had been
				;   taken when it did
