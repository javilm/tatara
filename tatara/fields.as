; fields.as - cutting a source line into its four fields.
;
; M80's line layout:
;
;   label  operation  operand  ; comment
;
; All four are optional. A label in column 1 needs no colon; an indented
; label must end with one, which is what M80 accepts and what most M80
; source is written as. Everything from an unquoted ";" to the end of the
; line is a comment.
;
; Nothing here copies any text. split_line fills in four addresses and four
; lengths that point into the caller's line buffer.

FIELDS_INCLUDED	equ	1		; skips the external in fields.inc

		public	split_line

		include	fields.inc
		include	ascii.inc

; The characters this module cares about, named rather than written. The
; semicolon in particular: a semicolon inside a quoted string is the exact
; case this module exists to get right, and there is no reason to make the
; assembler prove it can do the same thing first.

COLON		equ	03ah		; :
SEMICOLON	equ	03bh		; ;
EXCLAMATION	equ	021h		; !
ANGLE_OPEN	equ	03ch		; <
ANGLE_CLOSE	equ	03eh		; >

; split_line - cut one source line into label, operation, operand, comment.
;
;   The four steps fall into one another: whichever field the line runs
;   out in, the ones after it keep the zero length set at the top.
;
; Input:	HL -> the line, zero terminated
;		IX -> a field block, FIELD_BLOCK_SIZE bytes
; Output:	the block is filled in; a length of 0 = field not present
; Modifies:	AF, BC, DE, HL

split_line:	xor	a		; every field absent until proved
		ld	(ix+FIELD_LABEL_LENGTH),a	; otherwise
		ld	(ix+FIELD_OPERATION_LENGTH),a
		ld	(ix+FIELD_OPERAND_LENGTH),a
		ld	(ix+FIELD_COMMENT_LENGTH),a

		ld	c,0		; C = 0: column 1, where a label is
					;   a label with or without a colon
		ld	a,(hl)
		call	is_field_end	; Z set = this cannot start a label
		jr	nz,split_line.label
		or	a
		ret	z		; an empty line: nothing to do
		cp	SEMICOLON
		jp	z,split_line.comment	; a comment in column 1
		call	skip_spaces	; indented: on to the first word
		ld	a,(hl)
		or	a
		ret	z		; spaces and nothing else
		cp	SEMICOLON
		jp	z,split_line.comment	; an indented comment
		inc	c		; C = 1: out here only a colon makes
					;   a label, and without one the word
					;   is the operation

; --- the label. In column 1 the colon is optional; indented it is what
;     makes this a label at all. "::" is M80's public label, either way.

split_line.label:
		ld	(ix+FIELD_LABEL),l
		ld	(ix+FIELD_LABEL+1),h
		ld	b,0		; B = characters taken so far
split_line.label_scan:
		ld	a,(hl)
		cp	COLON
		jr	z,split_line.label_ended
		call	is_field_end
		jr	z,split_line.label_ended
		inc	hl
		inc	b
		jr	split_line.label_scan

; The word is cut and A holds the character that ended it: is_field_end leaves
; A alone, and the colon test above falls through with the colon still
; in it. In column 1 the word is the label whatever ended it. Indented,
; only a colon makes it one - and if none did, the word just walked was
; the operation.

split_line.label_ended:
		cp	COLON
		jr	z,split_line.label_take
		ld	a,c
		or	a
		jr	nz,split_line.word_was_operation
split_line.label_take:
		ld	(ix+FIELD_LABEL_LENGTH),b
		ld	a,(hl)
		cp	COLON
		jr	nz,split_line.operation
		inc	hl		; step over the colon
		ld	a,(hl)
		cp	COLON
		jr	nz,split_line.operation
		inc	hl		; and over the secuond one: M80 writes
					; "name::" for a public label
		; NOT a fall-through: split_line.word_was_operation now sits
		;   between this and the operation step
		jr	split_line.operation

; split_line.word_was_operation - the indented word was not a label.
;   HL and B already
;   describe it and FIELD_LABEL already holds its address, so the operation
;   field is those same three things under another name. FIELD_LABEL_LENGTH was
;   never written and still holds the zero from the top of split_line:
;   there is nothing to undo.
;
;   JP and not JR. The jump clears the whole operation step, and 073
;   spent a build on a JR that went out of range in the short routine a
;   correction had just grown.

split_line.word_was_operation:
		ld	a,(ix+FIELD_LABEL)
		ld	(ix+FIELD_OPERATION),a
		ld	a,(ix+FIELD_LABEL+1)
		ld	(ix+FIELD_OPERATION+1),a
		ld	(ix+FIELD_OPERATION_LENGTH),b
		jp	split_line.operand

; --- the operation

split_line.operation:
		call	skip_spaces	; over the spaces and tabs
		ld	a,(hl)
		or	a
		ret	z		; the line ends here
		cp	SEMICOLON
		jp	z,split_line.comment
		ld	(ix+FIELD_OPERATION),l
		ld	(ix+FIELD_OPERATION+1),h
		ld	b,0
split_line.operation_scan:
		ld	a,(hl)
		call	is_field_end
		jr	z,split_line.operation_take
		inc	hl
		inc	b
		jr	split_line.operation_scan
split_line.operation_take:
		ld	(ix+FIELD_OPERATION_LENGTH),b

; --- the operand. This is the field that may contain spaces, so it runs
;     to an unquoted ";" or to the end of the line, and the padding before
;     a comment is trimmed off afterwards.

split_line.operand:
		call	skip_spaces
		ld	a,(hl)
		or	a
		ret	z
		cp	SEMICOLON
		jp	z,split_line.comment
		ld	(ix+FIELD_OPERAND),l
		ld	(ix+FIELD_OPERAND+1),h
		ld	b,0		; B = characters taken
		ld	c,0		; C = the quote we are inside, 0 = none
		ld	d,0		; D = how deep in <> we are. A macro
					;   argument may hold a ";" inside
					;   brackets or behind a "!", and M80
					;   passes both - measured, appendix J
split_line.operand_scan:
		ld	a,(hl)
		or	a
		jr	z,split_line.operand_end	; the end of the line
		ld	e,a		; keep the character; A is about to go
		ld	a,c
		or	a
		; inside a string: only the closing quote means anything
		jr	nz,split_line.inside_quote
		ld	a,e
		cp	EXCLAMATION
		; "!x": x is text, whatever x is
		jr	z,split_line.escaped
		cp	ANGLE_OPEN
		jr	z,split_line.bracket_open
		cp	ANGLE_CLOSE
		jr	z,split_line.bracket_close
		cp	SEMICOLON
		jr	nz,split_line.quote_test
		; A SEMICOLON INSIDE BRACKETS IS TEXT. build_args is what takes
		; the brackets off and what strips the "!" - this module's only
		; job is to stop the field ending here
		ld	a,d
		or	a
		jr	z,split_line.operand_end
		ld	a,e
split_line.quote_test:
		cp	QUOTE1		;   field ending here
		jr	z,split_line.quote_opens
		cp	QUOTE2
		jr	nz,split_line.take_char
split_line.quote_opens:
		ld	c,a		; remember which quote opened it,
		ld	(quote_position),hl	;   and WHERE, and how far we
		ld	a,b		;   had got. If the line ends with
		ld	(quote_taken),a	;   still open it was no quote at
		jr	split_line.take_char	;   all - see .lone_quote
split_line.inside_quote:
		ld	a,e
		cp	c
		jr	nz,split_line.take_char
		ld	c,0		; the matching quote: out again
split_line.take_char:
		inc	hl
		inc	b
		jr	split_line.operand_scan

split_line.escaped:
		inc	hl	; THE "!" IS KEPT: build_args removes it
		inc	b		;   and has to see it. The character
		ld	a,(hl)		;   after it is taken whatever it is,
		or	a		;   and if the line ended instead, HL
		jr	z,split_line.operand_end	;   is on it already
		jr	split_line.take_char
split_line.bracket_open:
		inc	d
		jr	split_line.take_char
split_line.bracket_close:
		ld	a,d		; never below zero: an unmatched ">"
		or	a		;   is not this module's to report
		jr	z,split_line.take_char
		dec	d
		jr	split_line.take_char

; split_line.lone_quote - the quote at quote_position opened a run
;   that the line ended
;   inside, so it was not a delimiter at all: it was an apostrophe in an
;   operand, and "ex af,af' ; swap them" would otherwise have its
;   comment swallowed into the operand field. Go back to that character,
;   take it as ordinary, and carry on.
;
;   This terminates. A second lone quote later in the line backtracks to
;   ITS position, which is further along than this one.

split_line.lone_quote:
		ld	hl,(quote_position)
		ld	a,(quote_taken)
		ld	b,a
		ld	c,0		; no quote open from here
		jr	split_line.take_char	; step over it and go on

; Trim spaces and tabs off the end. HL must be left pointing at the ";"
; or the terminator for the comment step, so the walk back uses DE.

split_line.operand_end:
		ld	a,c		; still inside a quoted run at the
		or	a		;   end of the line? Then it never
		jr	nz,split_line.lone_quote	;   was one
		push	hl
		ld	a,b
		or	a
		jr	z,split_line.operand_take
		ld	d,h
		ld	e,l
split_line.trim:
		dec	de
		ld	a,(de)
		call	is_space_or_tab
		; a real character: stop here
		jr	nz,split_line.operand_take
		dec	b
		jr	nz,split_line.trim
split_line.operand_take:
		pop	hl
		ld	(ix+FIELD_OPERAND_LENGTH),b

; --- the comment, semicolon included, to the end of the lien

split_line.comment:
		ld	a,(hl)
		or	a
		ret	z		; no comment after all
		ld	(ix+FIELD_COMMENT),l
		ld	(ix+FIELD_COMMENT+1),h
		ld	b,0
split_line.comment_scan:
		ld	a,(hl)
		or	a
		jr	z,split_line.comment_take
		inc	hl
		inc	b
		jr	split_line.comment_scan
split_line.comment_take:
		ld	(ix+FIELD_COMMENT_LENGTH),b
		ret

; is_field_end - does the character in A end a plain field?
;
;   True for a space, a tab, a semicolon and the line's terminator. The
;   operand field does NOT use this - it is allowed to contain spaces.
;
; Input:	A = character
; Output:	Z set = yes, this ends a field
; Modifies:	F only - A comes back untouched

is_field_end:	or	a
		ret	z		; the terminator
		cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret	z
		cp	SEMICOLON
		ret

; is_space_or_tab - is the character in A a space or a tab?
;
; Input:	A = character
; Output:	Z set = yes
; Modifies:	F only

is_space_or_tab:
		cp	CHR_SPACE
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

skip_spaces:	ld	a,(hl)
		cp	CHR_SPACE
		jr	z,skip_spaces.step
		cp	CHR_TAB
		ret	nz
skip_spaces.step:
		inc	hl
		jr	skip_spaces

		dseg

quote_position:	defs	2	; split_line: where a quote opened, and
quote_taken:	defs	1	;   how much of the operand had been
				;   taken when it did
