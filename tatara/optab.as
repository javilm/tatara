; optab.as - the instruction table, its lookup, and the operand cursor.
;
; An operation is recognised as a mnemonic, and the
; class handler for its family is told where the operands are.
;
;   THE TABLE IS ONE ROW PER MNEMONIC, not one per operand form. A row
;   is a length byte, the name in upper case, a class and a base opcode
;   - six bytes for a three-character name, 425 for the whole Z80 and
;   R800 instruction set. The alternative, a row per (mnemonic, operand
;   form) pair, is about 2.2 KB of resident data for the same job, and
;   data has been the binding constraint in every phase of this project.
;   optable-design.md 5 is the argument in full.
;
;   THE CURSOR IS IN MEMORY, not in registers. An instruction's operands
;   are walked by several routines in turn - and
;   threading a pointer and a count through all of them costs more in
;   pushes and pops than the three bytes operand_cursor and operand_left take.

OPTAB_INCLUDED	equ	1		; skips the externals in optab.inc

		public	find_mnemonic
		public	operand_start
		public	operand_skip_blanks
		public	operand_must_end
		public	find_operand_word
		public	read_byte_source
		public	skip_expression
		public	expect_comma
		public	operand_advance
		public	operand_at_end
		public	read_operand
		public	skip_quoted_run
		public	condition_and_comma
		public	operand_is_c
		public	operand_is_sp
		public	no_displacement
		public	operand_restore
		public	expression_text
		public	displacement_text
		public	operand_kind
		public	operand_code
		public	operand_prefix
		public	register_table
		public	condition_table

		include	optab.inc
		include	strutil.inc	; fold_to_upper
		include	ascii.inc	; CHR_TAB
		include	errs.inc	; error_not_a_form

		cseg

; find_mnemonic - is this operation one of the Z80's or the R800's mnemonics?
;
;   The same walk as find_directive in dirtab.as, with two payload bytes rather
;   than one. They are deliberately NOT shared: they differ in payload
;   size, in return convention and in what they do when they fail, the
;   genuinely common part is a twelve-instruction compare loop, and one
;   routine with a payload-size parameter would save about 25 bytes and
;   add a parameter to the two most-executed lookups in the assembler.
;   If a third table ever appears, merge all three then.
;
;   The comparison folds to upper case, so a mnemonic is recognised in
;   either case even when /C makes symbols case-sensitive. That is not
;   an oversight: M80 2.3 says opcodes typed in lower case are converted
;   to upper case, and it says it about opcodes whatever the symbols do.
;
; Input:	DE -> the operation text, NOT zero-terminated
;		B  = how many characters it has
; Output:	CY set   = no such mnemonic
;		CY clear = A is its class, C its base opcode
; Modifies:	AF, BC, DE, HL

find_mnemonic:	ld	hl,mnemonic_table
find_mnemonic.entry:
		ld	a,(hl)		; this entry's length byte
		or	a
		scf
		ret	z		; the end marker: no such mnemonic
		cp	b
		jr	z,find_mnemonic.compare	; same length: worth comparing
find_mnemonic.next_entry:
		ld	a,(hl)		; step over length + name + class
		add	a,3		;   + base
		add	a,l
		ld	l,a
		jr	nc,find_mnemonic.entry
		inc	h
		jr	find_mnemonic.entry

find_mnemonic.compare:
		push	hl		; the entry, in case it does not
		push	de		;   match, and the operation text
		ld	c,b		; C = characters left to compare
find_mnemonic.compare_char:
		inc	hl		; HL -> the next character of the
		ld	a,(de)		;   name
		call	fold_to_upper
		cp	(hl)
		jr	nz,find_mnemonic.no_match
		inc	de
		dec	c
		jr	nz,find_mnemonic.compare_char
		inc	hl		; past the last character: the
		ld	a,(hl)		;   class byte
		inc	hl
		ld	c,(hl)		;   and the base opcode
		pop	de
		pop	hl
		or	a		; CY clear = found. No class is 0,
		ret			;   so this cannot set Z either

find_mnemonic.no_match:
		pop	de
		pop	hl
		jr	find_mnemonic.next_entry

; --- the operand cursor

; operand_start - point the cursor at this line's operand field.
;
; Input:	DE -> the operand text
;		A  = how long it is
; Output:	the cursor is set
; Modifies:	nothing

operand_start:	ld	(operand_cursor),de
		ld	(operand_left),a
		ret

; operand_skip_blanks - step the cursor over blanks and tabs.
;
; Input:	nothing
; Output:	the cursor is on the first character that is neither, or
;		at the end
; Modifies:	AF, DE

operand_skip_blanks:
		push	bc
		ld	de,(operand_cursor)
		ld	a,(operand_left)
		ld	b,a
operand_skip_blanks.scan:
		ld	a,b
		or	a
		jr	z,operand_skip_blanks.done
		ld	a,(de)
		cp	" "
		jr	z,operand_skip_blanks.step
		cp	CHR_TAB
		jr	nz,operand_skip_blanks.done
operand_skip_blanks.step:
		inc	de
		dec	b
		jr	operand_skip_blanks.scan
operand_skip_blanks.done:
		ld	(operand_cursor),de
		ld	a,b
		ld	(operand_left),a
		pop	bc
		ret

; operand_must_end - the operand field must have nothing left in it.
;
;   assemble_instruction calls this after the class handler has taken what it
;   wants, so every class gets the check and none of them can forget it. "nop
;   1" is the error it exists for.
;
; Input:	nothing
; Output:	returns, or error_not_a_form stops
; Modifies:	AF, DE

operand_must_end:
		call	operand_skip_blanks
		ld	a,(operand_left)
		or	a
		ret	z
		jp	error_not_a_form

; operand_at_end - is anything left in the operand field?
;
;   The cursor is this module's business, so a handler asks rather than
;   reading operand_left for itself. assemble_ret is the one that needs to
;   know, to tell "ret" from "ret nz".
;
; Input:	nothing
; Output:	Z set = nothing is left
; Modifies:	AF, DE

operand_at_end:	call	operand_skip_blanks
		ld	a,(operand_left)
		or	a
		ret

; operand_advance - step the cursor on by A characters.
;
; Input:	A = how many, and never more than is left
; Output:	the cursor has moved. A is unchanged
; Modifies:	F, HL

operand_advance:
		push	bc
		ld	c,a
		ld	b,0
		ld	hl,(operand_cursor)
		add	hl,bc
		ld	(operand_cursor),hl
		ld	hl,operand_left
		ld	a,(hl)
		sub	c
		ld	(hl),a
		ld	a,c		; give the caller its count back
		pop	bc
		ret

; operand_save, operand_restore - remember where the cursor is, and put it
; back.
;
;   One level, and one user: read_byte_source, which has to be able to change
;   its mind. "cp (foo)" must fall through to an expression, because in M80
;   parentheses are grouping and that line means "cp foo".
;
; Modifies:	AF, HL

operand_save:	ld	hl,(operand_cursor)
		ld	(saved_cursor),hl
		ld	a,(operand_left)
		ld	(saved_left),a
		ret

operand_restore:
		ld	hl,(saved_cursor)
		ld	(operand_cursor),hl
		ld	a,(saved_left)
		ld	(operand_left),a
		ret

; ends_operand_word - does this character end an operand word?
;
;   An apostrophe is NOT one of these, so AF' measures three characters
;   and can be told from AF.
;
; Input:	A = a character
; Output:	Z set = yes, it ends a word
; Modifies:	F only

ends_operand_word:
		cp	" "
		ret	z
		cp	CHR_TAB
		ret	z
		cp	","
		ret	z
		cp	"("
		ret	z
		cp	")"
		ret	z
		cp	"+"
		ret	z
		cp	"-"
		ret

; measure_operand_word - how many characters at the cursor could be an operand
; word.
;
; Input:	nothing
; Output:	A = the count, 0 if the cursor is on a delimiter or at
;		the end
; Modifies:	AF, BC, DE

measure_operand_word:
		ld	de,(operand_cursor)
		ld	a,(operand_left)
		ld	b,a
		ld	c,0
measure_operand_word.scan:
		ld	a,b
		or	a
		jr	z,measure_operand_word.done
		ld	a,(de)
		call	ends_operand_word
		jr	z,measure_operand_word.done
		inc	de
		inc	c
		dec	b
		jr	measure_operand_word.scan
measure_operand_word.done:
		ld	a,c
		ret

; find_operand_word - is the word at the cursor one of this table's?
;
;   register_table and condition_table have the same row shape: a length byte,
;   the name in upper case, a kind and a code. Which table to ask is the
;   CALLER's decision, and that is the whole answer to C being a register in
;   one and a condition in the other.
;
;   IX and IY carry their PREFIX in the code column, because it is the
;   only thing that tells them apart anywhere in the instruction set and
;   a fourth column would cost seventeen bytes to say it once.
;
; Input:	HL -> the table
; Output:	CY set   = no such word here, and the cursor has not
;			   moved
;		CY clear = (operand_kind) and (operand_code) are set,
;		(operand_prefix) too for
;			   IX, IY and the four index halves, and the
;			   cursor is past the word
; Modifies:	AF, BC, DE, HL

find_operand_word:
		ld	(word_table),hl
		call	measure_operand_word
		or	a
		scf
		ret	z		; no word here at all
		ld	(operand_word_length),a
		ld	hl,(word_table)
find_operand_word.entry:
		ld	a,(hl)
		or	a
		scf
		ret	z		; the end of the table
		ld	c,a
		ld	a,(operand_word_length)
		cp	c
		jr	z,find_operand_word.compare
find_operand_word.next_entry:
		ld	a,(hl)		; over length + name + kind + code
		add	a,3
		add	a,l
		ld	l,a
		jr	nc,find_operand_word.entry
		inc	h
		jr	find_operand_word.entry

find_operand_word.compare:
		push	hl
		ld	de,(operand_cursor)
find_operand_word.compare_char:
		inc	hl
		ld	a,(de)
		call	fold_to_upper	; the table is upper case, and a
		cp	(hl)		;   register name is recognised in
		jr	nz,find_operand_word.no_match	;   either
		inc	de
		dec	c
		jr	nz,find_operand_word.compare_char
		inc	hl		; past the name: the kind
		ld	a,(hl)
		ld	(operand_kind),a
		inc	hl
		ld	c,(hl)		; the code - or the prefix
		pop	hl
		cp	OPERAND_IX	; A is still the kind
		jr	nz,find_operand_word.index_half
		ld	a,c		; IX and IY: the code column held
		ld	(operand_prefix),a
					;   0DDh or 0FDh, and the pair code
		ld	c,2		;   is HL's
		jr	find_operand_word.found

find_operand_word.index_half:
		ld	b,0ddh		; an index half: the column held the
		cp	OPERAND_IX_HALF	;   register code, 4 or 5, and the
		jr	z,find_operand_word.half_prefix
					;   KIND says which prefix goes in
		ld	b,0fdh		;   front of it
		cp	OPERAND_IY_HALF
		jr	nz,find_operand_word.found
find_operand_word.half_prefix:
		ld	a,b
		ld	(operand_prefix),a
		ld	a,OPERAND_HALF	; ONE kind outside this routine, so
		ld	(operand_kind),a	;   a handler asks one question
find_operand_word.found:
		ld	a,c
		ld	(operand_code),a
		ld	a,(operand_word_length)
		call	operand_advance	; over the word
		or	a		; a word is never 0 long, so this
		ret			;   clears CY

find_operand_word.no_match:
		pop	hl
		jr	find_operand_word.next_entry

; expect_close_paren - the ")" that ends an indexed operand.
;
; Output:	CY set = it is not there
; Modifies:	AF, DE, HL

expect_close_paren:
		call	operand_skip_blanks
		ld	a,(operand_left)
		or	a
		scf
		ret	z
		ld	de,(operand_cursor)
		ld	a,(de)
		cp	")"
		scf
		ret	nz
		ld	a,1
		call	operand_advance
		or	a
		ret

; read_displacement - the displacement inside (IX+d), if there is one.
;
;   "+" or "-" and then an expression, which pass 1 steps over without
;   reading. "(ix)" is legal and means a displacement of zero - still a
;   byte in the instruction, so the length does not change.
;
;   Brackets inside it nest, so "(ix+(3*2))" works. A ")" inside a
;   character constant does NOT, which is the same gap skip_expression has and
;   which LD's quote-aware scanner closes.
;
;   It reports nothing. Whatever goes wrong, expect_close_paren finds no ")".
;
; Modifies:	AF, BC, DE, HL

read_displacement:
		xor	a
		ld	(displacement_length),a
					; none until one is found, and both the
		call	operand_skip_blanks
					;   returns below leave it that way
		ld	a,(operand_left)
		or	a
		ret	z
		ld	de,(operand_cursor)
		ld	a,(de)
		cp	"+"
		jr	z,read_displacement.found
		cp	"-"
		ret	nz		; the ")", presumably
read_displacement.found:
		ld	hl,(operand_cursor)
					; WHERE it starts, and that is AT THE
		ld	(displacement_at),hl
					;   SIGN: "(ix-1)" is -1, and an
					;   expression starting at the "1"
					;   is +1
		ld	a,1
		ld	(displacement_seen),a
					; there IS a displacement, which only
		call	operand_advance	;   JP cares about. A stays 1: over
					;   the sign
		ld	c,0		; C = how deep the brackets are
read_displacement.scan:
		ld	a,(operand_left)
		or	a
		jr	z,read_displacement.done
		ld	de,(operand_cursor)
		ld	a,(de)
		call	is_quote_char	; a quoted run is opaque: a ")" in
		jr	nz,read_displacement.not_quote
					;   one does not close the operand
		push	bc		; C is the bracket depth, and
		call	skip_quoted_run	;   skip_quoted_run wants C for itself
		pop	bc
		jr	read_displacement.scan
read_displacement.not_quote:
		cp	"("
		jr	z,read_displacement.nest
		cp	")"
		jr	nz,read_displacement.step
		ld	a,c
		or	a
		jr	z,read_displacement.done
					; the one that closes the operand
		dec	c
		jr	read_displacement.step
read_displacement.nest:
		inc	c
read_displacement.step:
		ld	a,1
		call	operand_advance
		jr	read_displacement.scan

read_displacement.done:
		ld	hl,(operand_cursor)
					; how long it turned out to be, sign
		ld	de,(displacement_at)
					;   included - the sign is part of
		or	a		;   the value, not punctuation
		sbc	hl,de
		ld	a,l
		ld	(displacement_length),a
		ret

; is_quote_char - is this character a string delimiter?
;
; Input:	A = a character
; Output:	Z set = yes, either sort. A is unchanged
; Modifies:	F only

is_quote_char:	cp	QUOTE1
		ret	z
		cp	QUOTE2
		ret

; skip_quoted_run - step the cursor over a quoted run, opening delimiter to
;   closing.
;
;   TWO DELIMITERS TOGETHER ARE ONE CHARACTER of the string and do not
;   close it (M80 2.3.4). Without that, "ld (""a"""),b" would end in the
;   wrong place.
;
;   This is the program's third quote scanner, and deliberately so.
;   split_line (fields.as) walks a raw line to find where a comment starts;
;   count_quoted_run (tatara.as) walks DE and B over a DB item and counts its
;   characters; this one walks the operand cursor and counts nothing.
;   They share a RULE, not an interface. If a fourth appears, merge all
;   four.
;
; Input:	the cursor is on the opening delimiter
; Output:	the cursor is past the closing one, or at the end of the
;		field if the line ended inside the run
; Modifies:	AF, BC, DE, HL

skip_quoted_run:
		ld	de,(operand_cursor)
		ld	a,(de)
		ld	c,a		; C = the delimiter that opened it
		ld	a,1
		call	operand_advance
skip_quoted_run.scan:
		ld	a,(operand_left)
		or	a
		ret	z		; the line ended inside the run
		ld	de,(operand_cursor)
		ld	a,(de)
		ld	b,a	; operand_advance keeps BC, so B survives it
		ld	a,1
		call	operand_advance
		ld	a,b
		cp	c
		jr	nz,skip_quoted_run.scan	; an ordinary character
		ld	a,(operand_left)
					; a delimiter: doubled, or the end?
		or	a
		ret	z
		ld	de,(operand_cursor)
		ld	a,(de)
		cp	c
		ret	nz		; something else follows: closed
		ld	a,1
		call	operand_advance	; "" - one character, and on we go
		jr	skip_quoted_run.scan

; read_operand - what is the operand at the cursor?
;
;   It names anything the Z80 has, and calls whatever it cannot name an
;   expression - so IT ALMOST NEVER FAILS, and the carry flag means only
;   "there is nothing here at all".
;
;   That is what makes "cp (foo)" work. read_operand answers OPERAND_MEMORY,
;   read_byte_source does not want it and puts the cursor back, and
;   assemble_alu reads the same text again as an expression. Which of the two
;   (foo) is depends on the INSTRUCTION, and the instruction is the only thing
;   that knows.
;
;   IT WRITES operand_save FOR EVERY OPERAND, at the start, for its own
;   backtracking - and read_byte_source leans on that instead of saving again.
;   The slot is valid from the moment read_operand returns until the next
;   read_operand call, and nothing else writes it.
;
; Input:	nothing
; Output:	CY set   = there is nothing here at all
;		CY clear = (operand_kind), (operand_code) and (operand_prefix)
;		describe it
; Modifies:	AF, BC, DE, HL

read_operand:	xor	a
		ld	(operand_prefix),a
		ld	(inner_kind),a	; nothing remembered from inside a
		ld	(displacement_seen),a
					;   bracket yet, and no displacement
		call	operand_skip_blanks
		ld	a,(operand_left)
		or	a
		scf
		ret	z		; nothing here at all
		call	operand_save
		ld	de,(operand_cursor)
		ld	a,(de)
		cp	"("
		jr	z,read_operand.bracket
		ld	hl,register_table
				; a bare word: whatever register_table says
		call	find_operand_word
		ret	nc
		jr	read_operand.expression

read_operand.bracket:
		ld	a,1
		call	operand_advance	; over the "("
		ld	hl,register_table
		call	find_operand_word
		jr	c,read_operand.address
		ld	a,(operand_kind)
		cp	OPERAND_PAIR
		jr	z,read_operand.bracket_pair
		cp	OPERAND_IX
		jr	z,read_operand.bracket_ix
		jr	remember_inner_word
					; (af), (i), (c): not a form, and an
					;   expression is the honest answer -
					;   but IN and OUT want to know that
					;   the word in there was "C"

read_operand.bracket_pair:
		ld	a,(operand_code)
		or	a
		jr	z,read_operand.bc	; (BC)
		dec	a
		jr	z,read_operand.de	; (DE)
		dec	a
		jr	nz,remember_inner_word
					; (SP): an address to everything but
					;   EX, which asks operand_is_sp about
					;   it
		call	expect_close_paren	; (HL) is register code 6
		jr	c,read_operand.address
		ld	a,OPERAND_BYTE
		ld	(operand_kind),a
		ld	a,6
		jr	read_operand.store_code

read_operand.bc:
		ld	c,OPERAND_AT_BC
		jr	read_operand.pair_address
read_operand.de:
		ld	c,OPERAND_AT_DE
read_operand.pair_address:
		call	expect_close_paren	; expect_close_paren keeps BC
		jr	c,read_operand.address
		ld	a,c
		ld	(operand_kind),a
		xor	a
		jr	read_operand.store_code

read_operand.bracket_ix:
		call	read_displacement
		call	expect_close_paren
		jr	c,read_operand.address
		ld	a,OPERAND_INDEXED
		ld	(operand_kind),a
		ld	a,6
read_operand.store_code:
		ld	(operand_code),a
		or	a		; or a clears CY whatever A holds
		ret

; remember_inner_word - read_operand found a word inside the brackets and is
; about to call the whole thing an address anyway. Keep what register_table
; said about it.
;
;   This is the whole of the answer to "(C)" and "(SP)". Giving them
;   kinds of their own would have been simpler to read and WRONG: M80
;   assembles "ld a,(c)" as 3A 0005 when C is an equate, so a kind for
;   (C) refuses a line M80 takes. The word is remembered, not
;   reclassified, and the three instructions that care ask.
;
;   Valid from the moment read_operand returns until the next read_operand -
;   the same lifetime as operand_save's slot, and for the same reason.

remember_inner_word:
		ld	a,(operand_kind)
		ld	(inner_kind),a
		ld	a,(operand_code)
		ld	(inner_code),a
		; and on into read_operand.address

read_operand.address:
		call	operand_restore	; back to the "(", and take the
		call	skip_expression	;   whole thing as an address
		ret	c
		ld	a,OPERAND_MEMORY
		jr	read_operand.store_kind

read_operand.expression:
		call	skip_expression	; not a register word: an expression
		ret	c
		ld	a,OPERAND_IMM
read_operand.store_kind:
		ld	(operand_kind),a
		xor	a		; no code, and CY cleared with it -
		ld	(operand_code),a	;   ld (nn),a touches no flags
		ret

; operand_is_c, operand_is_sp - was the operand read_operand last returned the
; literal "(C)" or the literal "(SP)"?
;
;   Both come back as OPERAND_MEMORY, because they are addresses to every
;   instruction but three. IN and OUT want (C); EX wants (SP); nothing
;   else may be allowed to notice, or "ld a,(c)" stops being the
;   absolute load M80 makes of it.
;
; Input:	nothing
; Output:	Z set = yes
; Modifies:	AF

operand_is_c:	ld	a,(inner_kind)
		cp	OPERAND_BYTE
		ret	nz
		ld	a,(inner_code)
		cp	1		; C is register code 1
		ret

operand_is_sp:	ld	a,(inner_kind)
		cp	OPERAND_PAIR
		ret	nz
		ld	a,(inner_code)
		cp	3		; SP is pair code 3
		ret

; no_displacement - did the indexed operand read_operand last returned carry NO
;   displacement?
;
;   Only JP asks, and only JP can. Everywhere else the displacement
;   byte is emitted whether the source wrote one or not - "ld a,(ix)"
;   is DD 7E 00, three bytes, exactly like "ld a,(ix+5)". "jp (ix)" is
;   DD E9 and TWO, with nowhere to put one, so "jp (ix+5)" is a form
;   that does not exist rather than a byte to ignore.
;
; Input:	nothing
; Output:	Z set = there was no displacement
; Modifies:	AF

no_displacement:
		ld	a,(displacement_seen)
		or	a
		ret

; expression_text, displacement_text - the text skip_expression and
; read_displacement stepped over.
;
;   A handler parses ALL its operands and only then emits, because the
;   prefix goes out before the opcode and is not known until the
;   operand has been read. By then the cursor is past the expression,
;   so the parser remembers where it was and these two hand it over.
;
;   TWO SLOTS AND NOT AN ARRAY. The most expressions any Z80
;   instruction has is two - "bit 7,(ix+5)" and "ld (ix+0),9" - and in
;   both the second is the displacement, which has a slot of its own
;   because read_displacement is what found it. No instruction has two general
;   expressions. DB, DW and DC have as many as you like and need
;   neither slot: walk_data_items visits items one at a time and emits each
;   before measuring the next.
;
;   Valid from the moment the handler's parsing is done until the next
;   line - the same lifetime as operand_save's slot and inner_kind's, and they
;   live beside them for that reason.
;
;   Routines and not exported bytes, because a module reaching into
;   another module's data is what the verification rule is about: the
;   answer is a small routine, and here it is two of them.
;
; Input:	nothing
; Output:	DE -> the text, A = how long it is
;		displacement_text answers A = 0 when there was no displacement
; Modifies:	AF, DE

expression_text:
		ld	de,(expression_at)
		ld	a,(expression_length)
		ret

displacement_text:
		ld	de,(displacement_at)
		ld	a,(displacement_length)
		ret

; condition_and_comma - a condition AND the comma after it.
;
;   The two together, never one at a time: "jp z,foo" is the
;   conditional jump and "jp z" is a jump to a symbol called Z. Only
;   the comma tells them apart, so a condition that is not followed by
;   one is not a condition, and the cursor goes back.
;
;   JP, JR and CALL are the three that ask. RET does not: "ret z" has
;   no comma and no second operand, so condition_table alone answers it.
;
; Input:	nothing
; Output:	CY set   = not a condition and a comma, and the cursor
;			   has not moved
;		CY clear = it was, the cursor is past the comma, and
;			   (operand_code) is the condition code
; Modifies:	AF, BC, DE, HL

condition_and_comma:
		call	operand_save
		ld	hl,condition_table
		call	find_operand_word
		ret	c		; not a condition word at all
		call	expect_comma
		ret	nc		; a condition and a comma: the
		call	operand_restore	;   conditional form. Without the
		scf			;   comma it was a symbol that
		ret			;   happens to be named Z, C or M

; read_byte_source - an 8-bit source: a register, (HL), an indexed operand, or
; an index half.
;
;   AN INDEX HALF IS NOT SAFE EVERYWHERE THIS ROUTINE IS CALLED. It
;   comes back as OPERAND_HALF with operand_prefix set, so a handler that emits
;   through emit_opcode is right without knowing it exists - and assemble_rot,
;   which cannot use emit_opcode, has to refuse it by hand. 104 has the four
;   handlers this routine serves and what each of them does with it.
;
;   (IX+d) IS (HL) with a prefix in front and a byte after. Both answer
;   code 6, which is the whole of the indexed forms - everything else
;   about them is the two extra bytes, and clsxtra adds those.
;
;   A filter on read_operand, not a parser of its own: on anything else it puts
;   the cursor back to where read_operand found the operand, so that the caller
;   can read the same text as an expression instead.
;
; Input:	nothing
; Output:	CY set   = not one of those, and the cursor has not moved
;		CY clear = (operand_kind) is OPERAND_BYTE or OPERAND_INDEXED,
;		(operand_code)
;		is the
;			   code, (operand_prefix) the prefix or 0
; Modifies:	AF, BC, DE, HL

read_byte_source:
		call	read_operand
		ret	c		; nothing there at all
		ld	a,(operand_kind)
		cp	OPERAND_BYTE
		ret	z
		cp	OPERAND_INDEXED
		ret	z
		cp	OPERAND_HALF	; an index half is an 8-bit source
		ret	z	;   wherever emit_opcode does the emitting
		call	operand_restore
				; read_operand's own save still points at
		scf			;   the start of this operand
		ret

; skip_expression - step over an expression: the rest of the operand field.
;
;   Pass 1 does not READ it. How much room an instruction takes does not
;   depend on what its operand is worth, so the text is skipped here and
;   evaluated when the bytes are emitted.
;
;   It stops at the next comma AT THE TOP LEVEL - one inside a quoted
;   run does not count, so "ld (','),a" reads the way it looks. LD
;   needed that for its first operand, and it is an improvement
;   everywhere else: "cp 1,2" used to size as two quiet bytes and is now
;   an error, because operand_must_end finds the ",2" left over.
;
; Output:	CY set = there was nothing there
; Modifies:	AF, BC, DE, HL

skip_expression:
		call	operand_skip_blanks
		ld	a,(operand_left)
		or	a
		scf
		ret	z		; an operand that is not there
		ld	hl,(operand_cursor)
					; WHERE it starts. Measuring had to
		ld	(expression_at),hl
					;   step over it; emitting has to come
					;   back and evaluate it, by which time
					;   the cursor is long past
skip_expression.scan:
		ld	a,(operand_left)
		or	a
		jr	z,skip_expression.done
		ld	de,(operand_cursor)
		ld	a,(de)
		cp	","
		jr	z,skip_expression.done
					; it belongs to the next operand
		call	is_quote_char
		jr	nz,skip_expression.step
		call	skip_quoted_run	; a comma inside a quoted run does
		jr	skip_expression.scan	;   not end anything
skip_expression.step:
		ld	a,1
		call	operand_advance
		jr	skip_expression.scan
skip_expression.done:
		ld	hl,(operand_cursor)
					; and how long it turned out to be
		ld	de,(expression_at)
		or	a
		sbc	hl,de
		ld	a,l		; an operand field is 255 at most, so
		ld	(expression_length),a	;   L is all of it
		or	a		; CY clear = there was an expression
		ret

; expect_comma - step over a comma.
;
; Output:	CY set = there is not one here
; Modifies:	AF, DE, HL

expect_comma:	call	operand_skip_blanks
		ld	a,(operand_left)
		or	a
		scf
		ret	z
		ld	de,(operand_cursor)
		ld	a,(de)
		cp	","
		scf
		ret	nz
		ld	a,1
		call	operand_advance
		or	a
		ret

		dseg

operand_cursor:	defs	2	; the operand cursor: where the unread
operand_left:	defs	1	;   text starts, and how much is left
saved_cursor:	defs	2
			; operand_save's copy of it, for read_byte_source
saved_left:	defs	1
word_table:	defs	2
		; find_operand_word: which table, across measure_operand_word
operand_word_length:
		defs	1	;   and how long the word is
operand_kind:	defs	1	; what the last operand turned out to
operand_code:	defs	1	;   be, the code it contributes, and
operand_prefix:	defs	1	;   the prefix it forces
inner_kind:	defs	1
			; what register_table said about the word inside
inner_code:	defs	1	;   a "(...)" that turned out to be an
				;   address anyway - see remember_inner_word
displacement_seen:
		defs	1	; did the indexed operand carry a
				;   displacement? Only JP asks
expression_at:	defs	2
			; skip_expression: where the expression it stepped
expression_length:
		defs	1	;   over began, and how long it was
displacement_at:
		defs	2
			; read_displacement: the same for a displacement,
displacement_length:
		defs	1	;   where 0 long means there was none

; The table. A length byte, the name in UPPER CASE, the class, and the
; base opcode. A length byte of 0 ends it.
;
; THE BASE OPCODE IS NOT READ WHILE MEASURING, and every
; handler here returns a length. It is typed now because these rows are
; entered by hand once, and leaving the column out would mean retyping
; all sixty-nine of them when the emitter wants them.
;
; The rows arrive with their handlers, a class at a time. A mnemonic
; that is not
; here yet is not recognised, so its line passes through as text - which
; is what Tatara has always done with a line it does not understand.

mnemonic_table:
		defb	3,	"NOP",	CLASS_NONE,	000h
		defb	4,	"HALT",	CLASS_NONE,	076h
		defb	2,	"DI",	CLASS_NONE,	0f3h
		defb	2,	"EI",	CLASS_NONE,	0fbh
		defb	3,	"EXX",	CLASS_NONE,	0d9h
		defb	3,	"DAA",	CLASS_NONE,	027h
		defb	3,	"CPL",	CLASS_NONE,	02fh
		defb	3,	"SCF",	CLASS_NONE,	037h
		defb	3,	"CCF",	CLASS_NONE,	03fh
		defb	4,	"RLCA",	CLASS_NONE,	007h
		defb	4,	"RRCA",	CLASS_NONE,	00fh
		defb	3,	"RLA",	CLASS_NONE,	017h
		defb	3,	"RRA",	CLASS_NONE,	01fh

		defb	3,	"NEG",	CLASS_NONE_ED,	044h
		defb	4,	"RETI",	CLASS_NONE_ED,	04dh
		defb	4,	"RETN",	CLASS_NONE_ED,	045h
		defb	3,	"RLD",	CLASS_NONE_ED,	06fh
		defb	3,	"RRD",	CLASS_NONE_ED,	067h
		defb	3,	"LDI",	CLASS_NONE_ED,	0a0h
		defb	3,	"LDD",	CLASS_NONE_ED,	0a8h
		defb	4,	"LDIR",	CLASS_NONE_ED,	0b0h
		defb	4,	"LDDR",	CLASS_NONE_ED,	0b8h
		defb	3,	"CPI",	CLASS_NONE_ED,	0a1h
		defb	3,	"CPD",	CLASS_NONE_ED,	0a9h
		defb	4,	"CPIR",	CLASS_NONE_ED,	0b1h
		defb	4,	"CPDR",	CLASS_NONE_ED,	0b9h
		defb	3,	"INI",	CLASS_NONE_ED,	0a2h
		defb	3,	"IND",	CLASS_NONE_ED,	0aah
		defb	4,	"INIR",	CLASS_NONE_ED,	0b2h
		defb	4,	"INDR",	CLASS_NONE_ED,	0bah
		defb	4,	"OUTI",	CLASS_NONE_ED,	0a3h
		defb	4,	"OUTD",	CLASS_NONE_ED,	0abh
		defb	4,	"OTIR",	CLASS_NONE_ED,	0b3h
		defb	4,	"OTDR",	CLASS_NONE_ED,	0bbh

		defb	3,	"ADD",	CLASS_ARITH,	080h
		defb	3,	"ADC",	CLASS_ARITH,	088h
		defb	3,	"SBC",	CLASS_ARITH,	098h
		defb	3,	"SUB",	CLASS_ALU,	090h
		defb	3,	"AND",	CLASS_ALU,	0a0h
		defb	3,	"XOR",	CLASS_ALU,	0a8h
		defb	2,	"OR",	CLASS_ALU,	0b0h
		defb	2,	"CP",	CLASS_ALU,	0b8h

		defb	3,	"INC",	CLASS_INCDEC,	004h
		defb	3,	"DEC",	CLASS_INCDEC,	005h

		defb	4,	"PUSH",	CLASS_STACK,	0c5h
		defb	3,	"POP",	CLASS_STACK,	0c1h
		defb	3,	"RET",	CLASS_RET,	0c9h
		defb	3,	"RST",	CLASS_RST,	0c7h
		defb	2,	"IM",	CLASS_IM,	046h

		defb	2,	"LD",	CLASS_LD,	000h

		defb	3,	"BIT",	CLASS_BIT,	040h
		defb	3,	"RES",	CLASS_BIT,	080h
		defb	3,	"SET",	CLASS_BIT,	0c0h

		defb	3,	"RLC",	CLASS_ROT,	000h
		defb	3,	"RRC",	CLASS_ROT,	008h
		defb	2,	"RL",	CLASS_ROT,	010h
		defb	2,	"RR",	CLASS_ROT,	018h
		defb	3,	"SLA",	CLASS_ROT,	020h
		defb	3,	"SRA",	CLASS_ROT,	028h
		defb	3,	"SLL",	CLASS_ROT,	030h
		defb	3,	"SRL",	CLASS_ROT,	038h

		defb	2,	"JP",	CLASS_JP,	0c3h
		defb	2,	"JR",	CLASS_JR,	018h
		defb	4,	"DJNZ",	CLASS_DJNZ,	010h
		defb	4,	"CALL",	CLASS_CALL,	0cdh

		defb	2,	"EX",	CLASS_EX,	000h
		defb	2,	"IN",	CLASS_IN,	000h
		defb	3,	"OUT",	CLASS_OUT,	000h

		defb	5,	"MULUB",CLASS_MULUB,	0c1h
		defb	5,	"MULUW",CLASS_MULUW,	0c3h

		defb	0		; the end of the table. SIXTY-NINE rows
					;   above it, and measuring is complete

; The operand words, and the conditions, in the same row shape as
; mnemonic_table: a length byte, the name in UPPER CASE, a kind, and a code.
;
; TWO TABLES, NOT ONE WITH A MASK. C is register code 1 here and
; condition code 3 in condition_table, and nothing has to decide which - the
; handler knows what it is asking for, because the grammar it implements
; says so. optable-design.md 7 has the argument.
;
; IX and IY hold their PREFIX in the code column. find_operand_word turns that
; into operand_prefix and gives them HL's pair code, 2.
;
; THE FOUR INDEX HALVES ARE THE OTHER WAY ROUND. Their code is 4 or 5 -
; H's and L's, because the prefix is all that tells them apart from H
; and L - so the column holds the CODE and the KIND holds the prefix.
; find_operand_word normalises both to OPERAND_HALF. A handler that wants them
; says so once; every handler that does not, and there are eight, refuses them
; by testing OPERAND_BYTE as it always did. 104 has the argument.

register_table:
		defb	1,	"B",	OPERAND_BYTE,	0
		defb	1,	"C",	OPERAND_BYTE,	1
		defb	1,	"D",	OPERAND_BYTE,	2
		defb	1,	"E",	OPERAND_BYTE,	3
		defb	1,	"H",	OPERAND_BYTE,	4
		defb	1,	"L",	OPERAND_BYTE,	5
		defb	1,	"A",	OPERAND_BYTE,	7
		defb	2,	"BC",	OPERAND_PAIR,	0
		defb	2,	"DE",	OPERAND_PAIR,	1
		defb	2,	"HL",	OPERAND_PAIR,	2
		defb	2,	"SP",	OPERAND_PAIR,	3
		defb	2,	"AF",	OPERAND_AF,	3
		defb	3,	"AF'",	OPERAND_AF_ALT,	0
		defb	2,	"IX",	OPERAND_IX,	0ddh
		defb	2,	"IY",	OPERAND_IX,	0fdh
		defb	3,	"IXH",	OPERAND_IX_HALF,	4
		defb	3,	"IXL",	OPERAND_IX_HALF,	5
		defb	3,	"IYH",	OPERAND_IY_HALF,	4
		defb	3,	"IYL",	OPERAND_IY_HALF,	5
		defb	1,	"I",	OPERAND_I,	0
		defb	1,	"R",	OPERAND_R,	0
		defb	0		; the end of the table

condition_table:
		defb	2,	"NZ",	OPERAND_COND,	0
		defb	1,	"Z",	OPERAND_COND,	1
		defb	2,	"NC",	OPERAND_COND,	2
		defb	1,	"C",	OPERAND_COND,	3
		defb	2,	"PO",	OPERAND_COND,	4
		defb	2,	"PE",	OPERAND_COND,	5
		defb	1,	"P",	OPERAND_COND,	6
		defb	1,	"M",	OPERAND_COND,	7
		defb	0		; the end of the table
