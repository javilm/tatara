; expr.as - expressions: turning text into a value.
;
; This is not a routine that conditionals happen to use. Pass 1
; will evaluate every operand in the program through eval_expression, so it
; gets the whole operator set now rather than the handful IF needs.
;
; One routine does all five binary precedence levels. eval_level is told how
; loose an operator it may accept; it reads a value, and then takes any
; operator that binds at least that tightly, parsing the right-hand side
; one level tighter so that a-b-c comes out as (a-b)-c. The unary
; operators live in read_value, because they attach to what follows them.
;
; The two rules are NOT the same, and getting them the same way round is
; the easiest mistake in this module:
;
;   a BINARY operator of level n parses its right side at level n+1, so
;     that it does not swallow another operator of its own level;
;   a PREFIX operator parses its operand at the level of the tightest
;     group BELOW it, so that it swallows everything binding more
;     tightly than itself.
;
; So NOT, which M80 puts below the comparisons, has its operand parsed
; at level 3 and NOT a EQ b means NOT (a EQ b).
;
; eval_expression never searches for a symbol: it calls whatever address is in
; symbol_lookup. That is look_up_symbol in symtab.as, and what changes is
; what look_up_symbol answers rather than anything in this file.

EXPR_INCLUDED	equ	1		; skips the externals in expr.inc

		public	expr_init
		public	eval_expression
		public	eval_absolute
		public	is_name_char
				; 099: define_label checks a label with it
		public	symbol_lookup
		public	value_type
		public	external_index

		include	expr.inc
		include	ascii.inc
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been declared

		include	errs.inc
		include	strutil.inc
				; fold_to_upper: the name tables are upper case
		include	symtab.inc
				; look_up_symbol, which symbol_lookup now
				; points at

		cseg

; expr_init - get this module ready for a pass.
;
;   Per PASS, like macro_table_init, expand_init and cond_init: a DEFL that
;   ended pass 1 holding 7 must start pass 2 holding whatever it was first
;   given, or the two passes assemble different programs.
;
; Input:	nothing
; Output:	the pass-0 table is empty and symbol_lookup points at it
; Modifies:	AF, BC, DE, HL, IX

expr_init:	ld	hl,look_up_symbol
		ld	(symbol_lookup),hl
		ret			; and nothing else. This once also
					; emptied a table of its own; the symbol
					; table must NOT be emptied per pass -
					; symbol_table_init owns it, once,
					; beside heap_init

; eval_expression - the value of an expression.
;
; Input:	DE -> the text, A = its length. It need not be
;		zero-terminated: the length is what ends it
; Output:	HL = the value
;		value_type = its type (SY_ABS, SY_CODE, SY_DATA)
;		(a bad expression does not return - error_bad_expression stops)
; Modifies:	AF, BC, DE, HL, IX

eval_expression:
		ld	(expr_cursor),de
		ld	(expr_left),a
		ld	a,SY_ABS
		ld	(value_type),a	; until something says otherwise
		ld	a,1		; level 1 accepts every operator
		call	eval_level
		push	hl
		call	expr_skip_blanks	; nothing may be left over
		ld	a,(expr_left)
		or	a
		jp	nz,error_bad_expression
		pop	hl
		ret

; eval_absolute - eval_expression, for an operand that must be a plain number:
; the DS count, the REPT count. require_absolute is the check on its own, which
; read_value uses for unary minus and NOT/HIGH/LOW; eval_absolute falls into
; it.
;
; Input:	as eval_expression
; Output:	HL = the value (a relocatable one does not return -
;		error_relocation stops)
; Modifies:	AF, BC, DE, HL, IX

eval_absolute:	call	eval_expression
require_absolute:
		ld	a,(value_type)
		or	a		; SY_ABS is 0
		ret	z
		cp	SY_EXTERNAL	; the two reasons read differently
		jp	z,error_external_here	; to whoever wrote the line
		jp	error_relocation

; eval_level - the value of a subexpression, taking only operators that bind
;   at least as tightly as A.
;
;   The whole precedence machinery is these twenty instructions.
;
; Input:	A = the loosest precedence this call may consume, 1..6
; Output:	HL = the value
; Modifies:	AF, BC, DE, HL, IX

eval_level:	ld	(min_precedence),a
		push	af	; read_value can recurse into eval_level -
		call	read_value	; through a "(", a "-" or a NOT - and
		pop	af	; that overwrites min_precedence, so put ours
					; back before using it
		ld	(min_precedence),a	; HL = the value on the left

eval_level.loop:
		push	hl		; keep it across the look-ahead
		call	peek_operator	; CY set = no operator here at all
		jr	c,eval_level.done
		ld	a,(min_precedence)
					; does it bind tightly enough for us?
		cp	c
		jr	z,eval_level.take	; the same level: yes
		jr	nc,eval_level.done
					; looser than we may take: not ours

eval_level.take:
		call	consume_operator	; now consume it
		ld	a,(value_type)	; the left side's type, on the stack
		push	af	; for the same reason as min_precedence: the
					; right side may recurse and overwrite
					; value_type
		ld	a,(operator_number)
		ld	b,a
		ld	a,(min_precedence)
		ld	c,a
		push	bc		; the operator, and our own limit
		ld	a,(operator_precedence)
		inc	a		; the right side binds one tighter
		call	eval_level
		pop	bc
		ld	a,c
		ld	(min_precedence),a	; the recursion overwrote it
		pop	af
		ld	(left_type),a
				; the left side's type, for apply_binary
		pop	de		; the value on the left
		ld	a,b
		call	apply_binary	; DE op HL -> HL, value_type = its type
		jr	eval_level.loop

eval_level.done:
		pop	hl
		ret

; --- reading one value

; read_value - read a value: a number, a name, a bracketed expression, or one
;   of the unary operators applied to what follows it.
;
; Input:	nothing (reads expr_cursor/expr_left)
; Output:	HL = the value
; Modifies:	AF, BC, DE, HL, IX

read_value:	ld	a,SY_ABS	; a number or a character is absolute;
		ld	(value_type),a	; a name, a bracket or a unary operator
					; overwrite it with what it produced
		call	expr_skip_blanks
		call	expr_peek	; CY set = the text ran out
		jp	c,error_bad_expression
		cp	"("
		jr	z,read_value.bracket
		cp	"-"
		jr	z,read_value.minus
		cp	"+"
		jr	z,read_value.plus
		cp	QUOTE1
		jr	z,read_value.character
		cp	QUOTE2		; M80 HAS TWO STRING DELIMITERS and so
		jr	z,read_value.character
					;   has this program: is_quote_char,
					;   count_quoted_run and
					;   skip_quoted_run all take either.
					;   The evaluator was the one that did
					;   not: "db ""A""" worked and "cp
					;   ""A""" did not
		cp	"0"
		jr	c,read_value.word	; below "0": not a digit
		cp	"9"+1
		jp	c,read_number	; a digit: M80 says it is a number

read_value.word:
		call	read_word	; a name, or a word operator
		ld	a,(expr_word_length)
		or	a
		jp	z,error_bad_expression	; not a name character either
		call	find_unary_operator	; NOT, HIGH or LOW?
		jr	nc,read_value.unary
		jp	read_symbol	; an ordinary name

read_value.unary:
		ld	a,(operator_number)
			; find_unary_operator left the PRECEDENCE in A, so
		push	af		; the operator itself comes from the
		ld	a,(operator_precedence)
					; variable - and it goes on the STACK,
		call	eval_level	; because the operand may be another
		call	require_absolute
					; unary operator and would overwrite
					; a variable.
		pop	af		; NOT, HIGH, LOW: absolute only
		jp	apply_unary	; For a UNARY operator the table holds
					; the level to parse its operand at, so
					; there is no inc a here, unlike
					; eval_level.take

read_value.bracket:
		call	consume_one	; over the "("
		ld	a,1
		call	eval_level
		push	hl
		call	expr_skip_blanks
		call	expr_peek
		jp	c,error_bad_expression	; the text ended before the ")"
		cp	")"
		jp	nz,error_bad_expression
		call	consume_one
		pop	hl
		ret

read_value.minus:
		call	consume_one	; over the "-"
		ld	a,5		; unary minus binds looser than "*",
		call	eval_level	; so -a*b is -(a*b)
		call	require_absolute
					; 0 - relocatable: no rule allows it
		ex	de,hl
		ld	hl,0
		or	a
		sbc	hl,de
		ret

; Unary plus, which does nothing and has to exist anyway: an index
; displacement is remembered WITH ITS SIGN, because the sign is part of
; the value, so emit_displacement hands "+5" to the evaluator exactly as it
; hands it "-1". read_value had the minus and not the plus, and every "(ix+d)"
; in the suite reported "bad expression" the first time one was emitted.
;
; It is a gap in the expression language rather than anything to do with
; displacements - "db +1" was broken too, and had been for a long time.

read_value.plus:
		call	consume_one	; over the "+", and start again on
		jp	read_value	;   what follows. "+ +5" is 5 too,
					;   which costs nothing to allow

read_value.character:
		jp	read_character

; apply_unary - apply the unary operator in A to HL.
;
; Input:	A = the operator number, HL = the operand
; Output:	HL = the result
; Modifies:	AF, HL

apply_unary:	cp	OP_NOT
		jr	z,apply_unary.complement
		cp	OP_HIGH
		jr	z,apply_unary.high
		ld	h,0		; OP_LOW
		ret
apply_unary.high:
		ld	l,h
		ld	h,0
		ret
apply_unary.complement:
		ld	a,h
		cpl
		ld	h,a
		ld	a,l
		cpl
		ld	l,a
		ret

; read_symbol - a name: look it up through symbol_lookup and take its value.
;
;   symbol_lookup is a variable holding a routine's ADDRESS.
;   "call read_symbol.call_lookup" pushes the return, the push/ex/ret below
;   transfers, and that routine's own ret comes back here - the Z80's way
;   of calling through a pointer.
;
; Input:	expr_word_at/expr_word_length say where the name is
; Output:	HL = its value, value_type updated
;		(an unknown name does not return - error_undefined_symbol
;		stops)
; Modifies:	AF, BC, DE, HL, IX

read_symbol:	ld	de,(expr_word_at)
		ld	a,(expr_word_length)
		ld	b,a
		dec	a		; one character long...
		jr	nz,read_symbol.look_up
		ld	a,(de)
		cp	"$"		; ...and it is "$": the location
		jr	nz,read_symbol.look_up
					; counter, in the current segment's
		ld	hl,(location_counter)
					; mode. "$foo" is longer, and an
		ld	a,(current_segment)	; ordinary name
		ld	(value_type),a
		ret
read_symbol.look_up:
		call	read_symbol.call_lookup	; CY set = no such symbol
		jp	c,error_undefined_symbol
		ld	(value_type),a
		ld	a,(found_flags)	; an external is not a place: it
		and	SYMBOL_EXTERNAL
				; carries SY_EXTERNAL so that apply_binary can
		ret	z		; apply 2.4.3's rules to it
		ld	(external_index),hl
					; ITS INDEX, WHICH IS NOT ITS VALUE.
		ld	hl,0
			;   declare_external put the index in SYMBOL_VALUE
		ld	a,SY_EXTERNAL	;   because that is where an external
		ld	(value_type),a	;   record keeps it - but what goes in
		ret			;   the word is the ADDEND, and the
					;   index goes's RELOC record.
					;   "baz+5" used to store index+5
read_symbol.call_lookup:
		push	hl
		ld	hl,(symbol_lookup)
		ex	(sp),hl
		ret

; read_number - a number, in decimal or in the base its suffix names.
;
;   M80: the default base is decimal; nnnnB, nnnnD, nnnnO, nnnnQ and
;   nnnnH name their own. A number always starts with a digit, which is
;   why read_value can tell one from a name without looking ahead.
;
; Input:	expr_cursor/expr_left at its first digit
; Output:	HL = its value
;		(a bad digit does not return - error_bad_expression stops)
; Modifies:	AF, BC, DE, HL

read_number:	call	read_word	; the whole run of letters and digits
		ld	a,(expr_word_length)
		ld	c,a		; C = how many characters are left
		ld	b,10		; B = the base, decimal by default
		ld	hl,(expr_word_at)
		ld	e,a
		ld	d,0
		add	hl,de
		dec	hl		; HL -> the last character
		ld	a,(hl)
		call	fold_to_upper
		cp	"B"
		jr	z,read_number.base_2
		cp	"D"
		jr	z,read_number.base_10
		cp	"O"
		jr	z,read_number.base_8
		cp	"Q"
		jr	z,read_number.base_8
		cp	"H"
		jr	nz,read_number.start	; no suffix: the base stays 10
		ld	b,16
		jr	read_number.drop_suffix
read_number.base_2:
		ld	b,2
		jr	read_number.drop_suffix
read_number.base_8:
		ld	b,8
		jr	read_number.drop_suffix
read_number.base_10:
		ld	b,10
read_number.drop_suffix:
		dec	c		; the suffix is not a digit
		jp	z,error_bad_expression
					; a suffix with no digits before it

read_number.start:
		ld	a,c
		ld	(digits_left),a	; digits still to take
		ld	a,b
		ld	(number_base),a
		ld	hl,0
		ld	de,(expr_word_at)

read_number.next_digit:
		ld	a,(digits_left)
		or	a
		ret	z		; done: HL is the value
		dec	a
		ld	(digits_left),a

		ld	a,(de)
		inc	de
		call	fold_to_upper
		sub	"0"
		jp	c,error_bad_expression
		cp	10
		jr	c,read_number.digit
		sub	"A"-"0"-10	; A-F, for base 16
		cp	10
		jp	c,error_bad_expression
read_number.digit:
		ld	c,a		; C = this digit
		ld	a,(number_base)
		cp	c
		jp	c,error_bad_expression	; too large for the base
		jp	z,error_bad_expression

		push	de		; HL = HL * base + digit
		ld	b,a
		ld	d,h
		ld	e,l
		ld	hl,0
read_number.times_base:
		add	hl,de		; the base is 2..16, so adding it up
		djnz	read_number.times_base
					; is smaller than a shift-and-add
		ld	e,c
		ld	d,0
		add	hl,de
		pop	de
		jr	read_number.next_digit

; read_character - a character constant: 'A', 'AB', "A" or "AB". Either
;   delimiter opens one and the same one closes it.
;
;   Two characters make a 16-bit value with the FIRST in the high byte,
;   which is the order that makes 'AB' read the way it is written.
;
; Input:	expr_cursor at the opening quote
; Output:	HL = the value
; Modifies:	AF, BC, DE, HL

read_character:	call	expr_peek	; WHICH delimiter opened it: the same
		ld	b,a		;   one has to close it, and a doubled
		call	consume_one	;   pair stands for it. B carries it
		ld	hl,0	;   through the whole scan - consume_one
					;   modifies AF and HL, expr_peek
					;   modifies AF, and NEITHER TOUCHES BC
read_character.next_char:
		call	expr_peek
		jp	c,error_bad_expression
					; the line ended inside the quotes
		cp	b
		jr	z,read_character.delimiter
		ld	h,l		; shift the previous character up and
		ld	l,a	; take this one - BEFORE consume_one, which
		push	hl		; destroys A, and across it, because it
		call	consume_one	; destroys HL too. This is the only
		pop	hl		; place in the module that keeps a
		jr	read_character.next_char
					; value in HL while consuming text,
					; which is why it is the only place
					; that has to say so
; A delimiter: the end of the run, or two of them standing for one
; character of it? The same rule count_quoted_run and skip_quoted_run keep, and
; read_character is the fourth routine in the program to keep it. Reading all
; four side by side and says why they stay four: they share a RULE, not an
; interface - four different cursors, four different products, and one of them
; is not a routine at all.

read_character.delimiter:
		push	hl
		call	consume_one	; over the closing quote
		call	expr_peek
		jr	c,read_character.done
					; the text ran out: it closed here
		cp	b
		jr	nz,read_character.done
					; something else follows: it closed
		pop	hl		; two delimiters are ONE character of
		ld	h,l		;   the run: shift it in and go round
		ld	l,b		;   for the rest, whichever it is
		push	hl
		call	consume_one	; over the second one
		pop	hl
		jr	read_character.next_char
read_character.done:
		pop	hl
		ret

; --- operators

; peek_operator - what operator comes next? Does NOT consume it, because the
;   caller only takes it if it binds tightly enough.
;
; Input:	nothing
; Output:	CY set   = there is no operator here
;		CY clear = operator_number = its number, operator_precedence =
;		its precedence,
;			   C = the same precedence, operator_length = how many
;			   characters it occupies
; Modifies:	AF, BC, DE, HL

peek_operator:	call	expr_skip_blanks
		call	expr_peek
		ret	c		; the text ran out
		cp	")"
		scf
		ret	z		; a ")" ends this subexpression
		ld	hl,punctuation_operators
					; one of the four punctuation ones?
peek_operator.punctuation:
		ld	a,(hl)
		or	a
		jr	z,peek_operator.word	; the end of that little table
		push	hl
		call	expr_peek	; the character we are looking at
		pop	hl
		cp	(hl)
		jr	z,peek_operator.found_punctuation
		inc	hl		; over the character, the number and
		inc	hl		; the precedence, to the next entry
		inc	hl
		jr	peek_operator.punctuation

peek_operator.word:
		call	peek_word	; a word, without consuming it
		ld	a,(expr_word_length)
		or	a
		scf
		ret	z		; not a name character: no operator
		call	find_binary_operator
					; look it up in the operator table
		ret	c		; a name, not an operator
		ld	a,(expr_word_length)
		ld	(operator_length),a
		or	a		; clears CY = there is an operator
		ret

peek_operator.found_punctuation:
		inc	hl		; HL -> this entry's operator number
		ld	a,(hl)
		ld	(operator_number),a
		inc	hl
		ld	a,(hl)
		ld	(operator_precedence),a
		ld	c,a
		ld	a,1
		ld	(operator_length),a
					; punctuation is always one character
		or	a		; no precedence is 0, so this clears CY
		ret

; find_binary_operator - is the word at expr_word_at a binary operator?
; find_unary_operator - is it one of the unary ones?
;
;   The same walk over two tables: a length byte, the name in upper case,
;   the operator number, the precedence; a zero length ends it. The same
;   shape as directive_table in dirtab.as.
;
; Input:	expr_word_at/expr_word_length say where the word is
; Output:	CY set   = not in that table
;		CY clear = operator_number and operator_precedence are set, C =
;		the precedence
; Modifies:	AF, BC, DE, HL

find_binary_operator:
		ld	hl,binary_operators
		jr	find_operator
find_unary_operator:
		ld	hl,unary_operators

find_operator:	ld	a,(expr_word_length)
		ld	b,a		; B = the length we are looking for
find_operator.entry:
		ld	a,(hl)
		or	a
		scf
		ret	z		; the end of the table: no match
		cp	b
		jr	z,find_operator.compare
find_operator.next_entry:
		ld	a,(hl)		; over the length, the name, and the
		add	a,3		; two bytes after it
		add	a,l
		ld	l,a
		jr	nc,find_operator.entry
		inc	h
		jr	find_operator.entry

find_operator.compare:
		push	hl
		ld	de,(expr_word_at)
		ld	c,b		; C = characters left to compare
find_operator.compare_char:
		inc	hl
		ld	a,(de)
		call	fold_to_upper	; the tables are stored upper case
		cp	(hl)
		jr	nz,find_operator.no_match
		inc	de
		dec	c
		jr	nz,find_operator.compare_char
		inc	hl		; past the last character of the name
		ld	a,(hl)
		ld	(operator_number),a	; the operator number
		inc	hl
		ld	a,(hl)
		ld	(operator_precedence),a	; and its precedence
		ld	c,a
		pop	hl
		or	a		; no precedence is 0, so this clears CY
		ret

find_operator.no_match:
		pop	hl
		jr	find_operator.next_entry

; consume_operator - consume the operator peek_operator just found. consume_one
; consumes one character.
;
; Modifies:	AF, HL

consume_operator:
		ld	a,(operator_length)
		jr	consume_chars
consume_one:	ld	a,1
consume_chars:	push	bc
		ld	c,a
		ld	a,(expr_left)
		sub	c
		ld	(expr_left),a
		ld	hl,(expr_cursor)
		ld	b,0
		add	hl,bc
		ld	(expr_cursor),hl
		pop	bc
		ret

; apply_binary - combine two values with the binary operator in A.
;
;   The comparisons answer 0ffffh for true and 0 for false, which is what
;   makes NOT and AND behave the way a programmer expects on their
;   results.
;
;   The TYPES are checked first, against M80's rules (manual 2.4.2):
;
;     abs + mode = mode        mode + abs = mode
;     mode - abs = mode        mode - same mode = abs
;     anything else needs both sides absolute, and gives absolute.
;
;   SY_ABS is 0, so "both absolute" is "the OR of the two is 0".
;
; Input:	A     = the operator
;		DE    = the left value
;		HL    = the right
;		left_type = the left's side type
;		value_type  = the right side's
; Output:	HL   = the result
;		value_type = its type
; Modifies:	AF, BC, DE, HL

apply_binary:	ld	c,a		; C = the operator: A is needed below
		ld	a,(left_type)
		ld	b,a		; B = the left side's type
		cp	SY_EXTERNAL	; is either side external? Those have
		jr	z,apply_binary.external
					; their own rules, and the do not
		ld	a,(value_type)	; apply to them at all
		cp	SY_EXTERNAL
		jr	z,apply_binary.external
		ld	a,c
		cp	OP_ADD
		jr	z,apply_binary.type_add
		cp	OP_SUB
		jr	z,apply_binary.type_sub
		ld	a,(value_type)	; anything else; both absolute, and so
		or	b	; is the result - value_type is already 0
		jp	nz,error_relocation
		jr	apply_binary.dispatch

apply_binary.type_add:
		ld	a,b		; the left absolute: the result is the
		or	a	; right side's type, already in value_type
		jr	z,apply_binary.dispatch
		ld	a,(value_type)	; the left relative: the right must be
		or	a		; absolute, and the result is the
		jp	nz,error_relocation	; left's
		ld	a,b
		ld	(value_type),a
		jr	apply_binary.dispatch

apply_binary.type_sub:
		ld	a,(value_type)
		or	a
		jr	nz,apply_binary.type_sub_both
		ld	a,b		; mode - abs = mode
		ld	(value_type),a
		jr	apply_binary.dispatch
apply_binary.type_sub_both:
		cp	b		; mode - the same mode = abs
		jp	nz,error_relocation
		xor	a
		ld	(value_type),a
		jr	apply_binary.dispatch

; --- an external: M80 2.4.3. It may be added to a plain number, or have
;     one subtracted from it, and that is the whole list. The result is
;     external, and there may be only one in an expression - which falls
;     out of insisting that the other side be absolute.

apply_binary.external:
		ld	a,c
		cp	OP_ADD
		jr	z,apply_binary.external_add
		cp	OP_SUB
		jp	nz,error_external_here
					; multiplied, compared, anything else
		ld	a,b		; the LEFT must be the external one:
		cp	SY_EXTERNAL	; "5 - extern" is not a number the
		jp	nz,error_external_here	; linker can finish
		ld	a,(value_type)
		or	a		; and the right must be absolute
		jp	nz,error_external_here
		jr	apply_binary.external_result

apply_binary.external_add:
		ld	a,b		; one side external, the other
		cp	SY_EXTERNAL	; absolute - either way round
		jr	nz,apply_binary.external_add_right
		ld	a,(value_type)
		or	a
		jp	nz,error_external_here
		jr	apply_binary.external_result
apply_binary.external_add_right:
		ld	a,b
		or	a
		jp	nz,error_external_here

apply_binary.external_result:
		ld	a,SY_EXTERNAL	; and the answer is still external
		ld	(value_type),a
apply_binary.dispatch:
		ld	a,c		; the operator again
		cp	OP_ADD
		jr	z,apply_binary.add
		cp	OP_SUB
		jr	z,apply_binary.sub
		cp	OP_AND
		jr	z,apply_binary.and
		cp	OP_OR
		jr	z,apply_binary.or
		cp	OP_XOR
		jr	z,apply_binary.xor
		cp	OP_MUL
		jp	z,apply_binary.multiply
		cp	OP_DIV
		jp	z,apply_binary.quotient
		cp	OP_MOD
		jp	z,apply_binary.remainder
		cp	OP_SHL
		jp	z,apply_binary.shift_left
		cp	OP_SHR
		jp	z,apply_binary.shift_right
		jp	apply_binary.compare	; one of the six comparisons

apply_binary.add:
		add	hl,de
		ret
apply_binary.sub:
		ex	de,hl
		or	a
		sbc	hl,de
		ret
apply_binary.and:
		ld	a,h
		and	d
		ld	h,a
		ld	a,l
		and	e
		ld	l,a
		ret
apply_binary.or:
		ld	a,h
		or	d
		ld	h,a
		ld	a,l
		or	e
		ld	l,a
		ret
apply_binary.xor:
		ld	a,h
		xor	d
		ld	h,a
		ld	a,l
		xor	e
		ld	l,a
		ret

apply_binary.shift_left:
		ld	a,l		; HL = DE shifted left by HL
		ex	de,hl
		or	a
		ret	z
		ld	b,a
apply_binary.shift_left_loop:
		add	hl,hl
		djnz	apply_binary.shift_left_loop
		ret
apply_binary.shift_right:
		ld	a,l
		ex	de,hl
		or	a
		ret	z
		ld	b,a
apply_binary.shift_right_loop:
		srl	h
		rr	l
		djnz	apply_binary.shift_right_loop
		ret

; apply_binary.multiply, apply_binary.quotient, apply_binary.remainder -
; nothing in the Z80 multiplies or divides, so these are the schoolbook
; shift-and-add and shift-and-subtract.

apply_binary.multiply:
		ld	b,h		; BC = the right-hand value
		ld	c,l
		ex	de,hl		; HL = the left
		ld	de,0		; DE = the running product
apply_binary.multiply_loop:
		ld	a,b
		or	c
		jr	z,apply_binary.multiply_done
		srl	b		; is the low bit of BC set?
		rr	c
		jr	nc,apply_binary.multiply_double
		ex	de,hl		; yes: add HL into the product
		add	hl,de
		ex	de,hl
apply_binary.multiply_double:
		add	hl,hl		; and double the multiplicand
		jr	apply_binary.multiply_loop
apply_binary.multiply_done:
		ex	de,hl
		ret

apply_binary.quotient:
		jp	divide		; HL = the quotient
apply_binary.remainder:
		call	divide
		ex	de,hl		; DE held the remainder
		ret

; divide - HL = DE / HL, DE = DE MOD HL. Division by zero gives all ones
;   and a remainder of the numerator, which is what M80 does and is not
;   an error.
;
; Modifies:	AF, BC, DE, HL

divide:		ld	a,h
		or	l
		jr	nz,divide.start
		ex	de,hl		; by zero: all ones
		ld	hl,0ffffh
		ret
divide.start:	ld	b,h		; BC = the divisor
		ld	c,l
		ex	de,hl		; HL = the numerator
		ld	de,0		; DE = the running remainder
		ld	a,16
divide.bit:	push	af
		add	hl,hl		; the top bit of HL into DE
		ex	de,hl
		adc	hl,hl
		or	a
		sbc	hl,bc		; does the divisor go in?
		jr	nc,divide.one
		add	hl,bc		; no: put it back
		ex	de,hl
		pop	af
		dec	a
		jr	nz,divide.bit
		ret
divide.one:	ex	de,hl
		inc	l		; yes: a 1 into the quotient
		pop	af
		dec	a
		jr	nz,divide.bit
		ret

; apply_binary.compare - the six comparisons. Unsigned, because M80's numbers
; are 16-bit unsigned quantities.
;
; Input:	A = the operator, DE = the left value, HL = the right
; Output:	HL = 0ffffh for true, 0 for false
; Modifies:	AF, BC, DE, HL

apply_binary.compare:
		ld	(comparison_operator),a
		ex	de,hl		; HL = the left, DE = the right
		or	a
		sbc	hl,de		; CY set = left < right, Z = equal
		ld	a,(comparison_operator)	; ld does not touch the flags
		push	af
		ld	a,0
		adc	a,0		; A = 1 when left was less
		ld	c,a
		pop	af		; the sbc flags, and A = the operator
		ld	b,0
		jr	nz,apply_binary.compare_which
		inc	b		; B = 1 when they were equal
apply_binary.compare_which:
		cp	OP_EQ
		jr	z,apply_binary.compare_eq
		cp	OP_NE
		jr	z,apply_binary.compare_ne
		cp	OP_LT
		jr	z,apply_binary.compare_lt
		cp	OP_GE
		jr	z,apply_binary.compare_ge
		cp	OP_LE
		jr	z,apply_binary.compare_le
		ld	a,b		; OP_GT: neither less nor equal
		or	c
		jr	apply_binary.true_if_clear
apply_binary.compare_eq:
		ld	a,b
		jr	apply_binary.true_if_set
apply_binary.compare_ne:
		ld	a,b
		jr	apply_binary.true_if_clear
apply_binary.compare_lt:
		ld	a,c
		jr	apply_binary.true_if_set
apply_binary.compare_ge:
		ld	a,c
		jr	apply_binary.true_if_clear
apply_binary.compare_le:
		ld	a,b
		or	c

apply_binary.true_if_set:
		or	a		; true when A is non-zero
		jr	nz,apply_binary.true
		jr	apply_binary.false
apply_binary.true_if_clear:
		or	a		; true when A is zero
		jr	z,apply_binary.true
apply_binary.false:
		ld	hl,0
		ret
apply_binary.true:
		ld	hl,0ffffh
		ret

; --- the little scanners. All of them work on expr_cursor/expr_left rather
; than on registers, because there are not enough registers to carry a position
; through a recursive descent.

; expr_peek - the character at the scan position, without consuming it.
;
; Output:	CY set = nothing left; CY clear = A is it
; Modifies:	AF

expr_peek:	push	hl
		ld	a,(expr_left)
		or	a
		jr	z,expr_peek.at_end
		ld	hl,(expr_cursor)
		ld	a,(hl)
		pop	hl
		or	a		; a real character, so this clears CY
		ret
expr_peek.at_end:
		pop	hl
		scf
		ret

; expr_skip_blanks - step over spaces and tabs.
;
; Modifies:	AF

expr_skip_blanks:
		call	expr_peek
		ret	c
		cp	CHR_SPACE
		jr	z,expr_skip_blanks.step
		cp	CHR_TAB
		ret	nz
expr_skip_blanks.step:
		call	consume_one
		jr	expr_skip_blanks

; read_word - find the run of name characters at the scan position and
;   consume it. peek_word does the same WITHOUT consuming it.
;
;   IT DOES NOT COPY. The word is left where it already is - in the text
;   eval_expression was handed, which stays put for as long as eval_expression
;   runs - and expr_word_at/expr_word_length say where it is and how long. This
;   once copied into a 32-byte buffer and every consumer read the copy, which
;   cost 32 bytes of ordinary RAM and silently truncated any name past 32
;   characters into a lie: the truncation was looked up, not found, and
;   reported as "undefined symbol" for a symbol defined three lines up.
;
;   cond.as reached the same conclusion from the other direction:
;   find_argument points into the line buffer rather than copying,
;   because IFIDN is finished before the next next_source_line. An expression
;   is a find_argument, not a build_args.
;
;   The cap that remains is 255, because expr_word_length is one byte. That one
;   is not a truncation of anything real: R1's limit is 255 and LINE_MAX is 255
;   too, so a longer name could never have been defined, and looking up the
;   first 255 characters of it fails with "undefined symbol" - which is the
;   truth.
;
; Output:	expr_word_at, expr_word_length
; Modifies:	AF, BC, HL

read_word:	call	peek_word
		ld	a,(expr_word_length)
		ld	(operator_length),a
		or	a
		ret	z
		jp	consume_operator

peek_word:	ld	hl,(expr_cursor)
		ld	(expr_word_at),hl
					; where the word starts, in the text
		ld	a,(expr_left)
		ld	b,a		; B = characters left in the text
		ld	c,0		; C = how many are name characters
peek_word.next_char:
		ld	a,b
		or	a
		jr	z,peek_word.done
		ld	a,c
		inc	a
		jr	z,peek_word.done
					; 255 is all expr_word_length can count
		ld	a,(hl)
		call	is_name_char
		jr	nz,peek_word.done
		inc	hl
		dec	b
		inc	c
		jr	peek_word.next_char
peek_word.done:	ld	a,c
		ld	(expr_word_length),a
		ret

; is_name_char - may this character appear in a name? M80's set is the
;   letters, the digits, and ? @ . _ $ - the same set is_identifier_char uses
;   in macros.as, and the fifth place this test has been written.
;
;   PUBLIC SINCE 099: define_label asks it of every character of a label,
;   which is what stops "foo*bar" becoming a symbol nothing can name.
;   is_identifier_char is still a second copy and should be deleted in favour
;   of this one the next time macros.as is open. NOT strutil.as, which is
;   shared with TANREN - the linker would carry it and never call it.
;
; Output:	Z set = yes
; Modifies:	F

is_name_char:	cp	"0"
		jr	c,is_name_char.punctuation
		cp	"9"+1
		jr	c,is_name_char.yes
		cp	"A"
		jr	c,is_name_char.punctuation
		cp	"Z"+1
		jr	c,is_name_char.yes
		cp	"a"
		jr	c,is_name_char.punctuation
		cp	"z"+1
		jr	c,is_name_char.yes
is_name_char.punctuation:
		cp	"?"
		ret	z
		cp	"@"
		ret	z
		cp	"."
		ret	z
		cp	"_"
		ret	z
		cp	"$"
		ret
is_name_char.yes:
		cp	a
		ret

		dseg

; The four operators that need no space around them: the character, the
; number, the precedence. A zero ends the table.

punctuation_operators:
		defb	"*",	OP_MUL,	5
		defb	"/",	OP_DIV,	5
		defb	"+",	OP_ADD,	4
		defb	"-",	OP_SUB,	4
		defb	0

; The word operators: a length, the name in UPPER CASE, the number, the
; precedence. Anything else that looks like a word is a name.

binary_operators:
		defb	3,"MOD",  OP_MOD,  5
		defb	3,"SHR",  OP_SHR,  5
		defb	3,"SHL",  OP_SHL,  5
		defb	2,"EQ",   OP_EQ,   3
		defb	2,"NE",   OP_NE,   3
		defb	2,"LT",   OP_LT,   3
		defb	2,"LE",   OP_LE,   3
		defb	2,"GT",   OP_GT,   3
		defb	2,"GE",   OP_GE,   3
		defb	3,"AND",  OP_AND,  2
		defb	2,"OR",   OP_OR,   1
		defb	3,"XOR",  OP_XOR,  1
		defb	0

; The unary ones, which read_value looks up separately because they take a
; following operand rather than joining two. Here the last column is the
; level their OPERAND is parsed at, not their own precedence - see the
; note at the top of the file.

unary_operators:
		defb	3,"NOT",  OP_NOT,  3
		defb	4,"HIGH", OP_HIGH, 6
		defb	3,"LOW",  OP_LOW,  6
		defb	0

expr_cursor:	defs	2	; where the scan has got to
expr_left:	defs	1	; how much of the expression is unread
min_precedence:	defs	1	; eval_level: the loosest operator it may take
symbol_lookup:	defs	2	; the ADDRESS of the symbol look-up. Phase
				;   13 stores the real one here and nothing
				;   else in this module changes
value_type:	defs	1	; the type of the value just produced
external_index:	defs	2	; the external index of the name read_symbol
				;   last looked up. One variable is enough
				;   because apply_binary allows only one
				;   external in an expression
left_type:	defs	1	; apply_binary: the type of its LEFT operand.
				;   eval_level.take keeps it on the stack
				;   across the right side and stores it here
				;   last
operator_number:
		defs	1	; peek_operator: which operator it found
operator_precedence:
		defs	1	; peek_operator: and its precedence
operator_length:
		defs	1
			; peek_operator: how many characters it occupies
comparison_operator:
		defs	1	; apply_binary.compare: which comparison
number_base:	defs	1	; read_number: the base this number is in
digits_left:	defs	1	; read_number: digits still to take
expr_word_length:
		defs	1	; the word just collected
expr_word_at:	defs	2
			; and where it is, in eval_expression's own text

