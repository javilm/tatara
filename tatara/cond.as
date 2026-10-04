; cond.as - conditional assembly: which lines survive.
;
; One state per open conditional, in a small stack. The rule that keeps
; it simple: an IF met while we are already skipping is pushed as
; COND_DONE, so the innermost state alone answers "are we emitting?".
;
; Nothing here knows about macros, and macros know nothing about this.
; While a definition is being COLLECTED, collect_macro (macros.as) has its own
; loop and never calls cond_line, so conditional directives in a body are
; stored as text and acted on when the macro expands. The two meet only
; in the driver, one line at a time.

COND_INCLUDED	equ	1		; skips the externals in cond.inc

		public	cond_init
		public	cond_line
		public	cond_eof
		public	cond_label_assembled	; was the line just read being
					;   assembled? main.next_line asks
					;   after cond_line has returned, by
					;   which time the state has changed
		public	cond_depth	; how many conditionals are open.
					;   expand.as reads it when an
					;   expansion record is created and
					;   writes it back on EXITM, which
					;   abandons every conditional the
					;   expansion had opened. Those are
					;   the only two places outside this
					;   module that touch it, and the
					;   only variable the program exports

		include	cond.inc
		include	expr.inc
		include	fields.inc
		include	dirtab.inc
		include	ascii.inc

		include	errs.inc
		include	srcline.inc
			; current_file/current_line: where the line just
					;   handed over came from. cond_push
					;   records them for the outermost open
					;   conditional, so
					;   error_cond_not_closed can name the
					;   IF rather than the end of the
					;   source

		cseg

; cond_init - no conditionals open.
;
;   Per PASS, not once-only: pass 2 re-reads the source and must start it
;   with an empty stack. Called from main: beside macro_table_init and
;   expand_init.
;
; Input:	nothing
; Output:	the stack is empty
; Modifies:	AF

cond_init:	xor	a
		ld	(cond_depth),a
		ret

; cond_line - act on this line's conditional directive, if it has one, and
;   say whether the line survives.
;
;   The whole IF..ENDIF family is numbered contiguously in dirtab.inc,
;   DIRECTIVE_IF to DIRECTIVE_ENDIF, which is what makes the test at
;   the top two compares instead of ten.
;
; Input:	A  = the directive number
;		IX -> the field block for this line
; Output:	CY set   = the line produces nothing
;		CY clear = it goes on to the rest of the driver
; Modifies:	AF, BC, DE, HL, IX

cond_line:	cp	DIRECTIVE_IF
		jp	c,cond_skipping	; below the family: an ordinary line
		cp	DIRECTIVE_ENDIF+1
		jp	nc,cond_skipping	; above it
		cp	DIRECTIVE_ELSE
		jr	z,cond_line.else_branch
		cp	DIRECTIVE_ENDIF
		jr	z,cond_line.done

; --- an opener. Note the order: whether we are ALREADY skipping is asked
;     first, because if we are, the condition must not be looked at.

		ld	(cond_directive),a	; cond_true needs which one
		call	cond_skipping
		; inside a false branch: neither branch of this one may be
		;   taken
		ld	a,COND_DONE
		jr	c,cond_line.push
		call	cond_true	; CY clear = the condition is true
		ld	a,COND_TAKE
		jr	nc,cond_line.push
		ld	a,COND_SKIP
cond_line.push:	call	cond_push
		scf			; the directive itself never survives
		ret

; --- ELSE

cond_line.else_branch:
		ld	a,(cond_depth)
		or	a
		jp	z,error_cond_unmatched	; an ELSE with no IF open
		call	cond_skipping	; BEFORE the state changes: an ELSE is
					;   read while the branch ABOVE it is
					;   still the current one, and M80
					;   defines a label on it when THAT
					;   branch was the one being assembled
		call	cond_top
		bit	7,a
		jp	nz,error_cond_unmatched
					; M80 allows only one ELSE per IF
		and	07fh
		cp	COND_SKIP
		ld	a,COND_DONE	; TAKE -> DONE, DONE -> DONE
		jr	nz,cond_line.else_taken
		ld	a,COND_TAKE	; SKIP -> TAKE: this is the branch
cond_line.else_taken:
		or	COND_ELSE_SEEN	; and it has had its ELSE now
		call	cond_set_top
		scf
		ret

; --- ENDIF

cond_line.done:	ld	a,(cond_depth)
		or	a
		jp	z,error_cond_unmatched	; an ENDIF with no IF open
		call	cond_skipping	; BEFORE the level is closed: an ENDIF
		ld	a,(cond_depth)	;   that closes a SKIPPED branch names
		dec	a	;   no place. cond_skipping clobbers A, so
		ld	(cond_depth),a	;   the depth is read again
		scf
		ret

; cond_skipping - are we inside a branch that is not being taken?
;
;   Only the innermost state is looked at. See the note at the top of the
;   file for why that is enough.
;
;   IT ALSO WRITES cond_label_assembled, which is the same answer
;   kept for main.next_line.
;   A label on a line that emits nothing takes the location counter if
;   that line is being assembled - M80 does it for the whole IF family,
;   for REPT, IRP and IRPC, and for END - and by the time cond_line
;   returns, the state it was decided by has already changed. Recording
;   it here costs nine bytes and covers every caller: the opener path
;   was already calling this routine before it pushed, and ELSE and
;   ENDIF now call it before they act.
;
; Input:	nothing
; Output:	CY set = skipping
;		(cond_label_assembled) = 0FFh emitting, 0 skipping
; Modifies:	AF, DE, HL

		;   ASSUME EMITTING, and say so first: the two exits below that
		;   mean emitting are the common ones, and neither has to
		;   repeat
		;   it
cond_skipping:	ld	a,0ffh
		ld	(cond_label_assembled),a
		ld	a,(cond_depth)
		or	a
		ret	z		; nothing open: emitting, CY clear
		call	cond_top
		and	07fh		; the ELSE-seen bit is not a state,
		ret	z		; and COND_TAKE is 0, so this clears CY
		; skipping: and no label on this line either. xor a CLEARS CY,
		;   which is why the scf comes after it and not before
		xor	a
		ld	(cond_label_assembled),a
		scf
		ret

; cond_top - the innermost open conditional's state byte.
;
; Input:	cond_depth > 0
; Output:	A = the state, HL -> where it lives
; Modifies:	AF, DE, HL

cond_top:	ld	a,(cond_depth)
		dec	a
		ld	l,a
		ld	h,0
		ld	de,cond_stack
		add	hl,de
		ld	a,(hl)
		ret

; cond_set_top - replace the innermost state with A.
;
; Input:	A = the new state, cond_depth > 0
; Output:	stored
; Modifies:	AF, DE, HL

cond_set_top:	push	af
		call	cond_top
		pop	af
		ld	(hl),a
		ret

; cond_push - open a conditional with state A.
;
; Input:	A = the state
; Output:	pushed
;		(too deep does not return - error_cond_too_deep stops)
; Modifies:	AF, BC, DE, HL

cond_push:	ld	c,a
		ld	a,(cond_depth)
		cp	COND_MAX_DEPTH
		jp	nc,error_cond_too_deep
		or	a		; pushing level 0? Then this is the
		jr	nz,cond_push.store	; outermost conditional now
		ld	a,(current_file)
			; open, and the one error_cond_not_closed points
		ld	(outer_file),a	; source ends with it still open. A
		ld	hl,(current_line)	; matched pair at level 0 just
		ld	(outer_line),hl	; overwrites it with the one that
					; matters
		xor	a
cond_push.store:
		inc	a
		ld	(cond_depth),a
		ld	a,c
		jp	cond_set_top

; cond_eof - the end of the source. Nothing may still be open.
;
; Input:	nothing
; Output:	returns only if the stack is empty
;		(an unclosed conditional does not return -
;		error_cond_not_closed stops)
; Modifies:	AF

cond_eof:	ld	a,(cond_depth)
		or	a
		ret	z
		ld	a,(outer_file)	; the outermost one still open, not the
		ld	hl,(outer_line)	; end of the source
		jp	error_cond_not_closed

; --- the conditions themselves

; cond_true - is this conditional's condition true?
;
;   IFB, IFNB, IFIDN and IFDIF are text tests and need nothing but the
;   operand. IF and IFE go through eval_expression (expr.as); IFDEF and IFNDEF
;   go straight to the symbol look-up, because for them "not found" is
;   an answer and not an error.
;
; Input:	cond_directive = the directive number, IX -> the field block
; Output:	CY clear = true, CY set = false
; Modifies:	AF, BC, DE, HL, IX

cond_true:	ld	a,(cond_directive)
		cp	DIRECTIVE_IFB
		jr	z,cond_true.ifb
		cp	DIRECTIVE_IFNB
		jr	z,cond_true.ifnb
		cp	DIRECTIVE_IFIDN
		jr	z,cond_true.ifidn
		cp	DIRECTIVE_IFDIF
		jr	z,cond_true.ifdif
		cp	DIRECTIVE_IFDEF
		jp	z,cond_true.ifdef
		cp	DIRECTIVE_IFNDEF
		jp	z,cond_true.ifndef
		cp	DIRECTIVE_IF
		jp	z,cond_true.if_expr
		cp	DIRECTIVE_IFE
		jp	z,cond_true.ife_expr
		cp	DIRECTIVE_IF1
		jr	z,cond_true.if1
		cp	DIRECTIVE_IF2
		jr	z,cond_true.if2
		or	a
		ret

; IF1 and IF2 ask which reading of the source this is. There was once
; was only one, and they were hardwired true and false.

cond_true.if1:	ld	a,(pass_number)
		dec	a
		jr	z,cond_true.true	; pass 1: IF1 is true
		jr	cond_true.false
cond_true.if2:	ld	a,(pass_number)
		dec	a
		jr	z,cond_true.false	; pass 1: IF2 is false
		jr	cond_true.true

cond_true.false:
		scf
		ret
cond_true.true:	or	a
		ret

cond_true.ifb:	xor	a		; IFB: argument 0 is empty
		call	find_argument
		or	a
		ret	z		; blank: true, and or a clears CY
		scf
		ret

cond_true.ifnb:	xor	a		; IFNB: it is not
		call	find_argument
		or	a
		scf
		ret	z		; blank: false
		or	a
		ret

cond_true.ifidn:
		call	args_are_same	; IFIDN: Z set = the same
		jr	z,cond_true.true
		scf
		ret

cond_true.ifdif:
		call	args_are_same	; IFDIF
		jr	nz,cond_true.true
		scf
		ret

; --- IF and IFE: the operand is an expression, and a non-zero value is
;     true. It must be known already - an unknown name stops the
;     assembly inside eval_expression - but it may be relocatable: zero or not
;     is all that is asked of it.

cond_true.if_expr:
		call	operand_value
		ld	a,h
		or	l
		jp	nz,cond_true.true
		scf
		ret

cond_true.ife_expr:
		call	operand_value
		ld	a,h
		or	l
		jp	z,cond_true.true
		scf
		ret

operand_value:	ld	e,(ix+FIELD_OPERAND)
		ld	d,(ix+FIELD_OPERAND+1)
		ld	a,(ix+FIELD_OPERAND_LENGTH)
		jp	eval_expression	; HL = the value

; --- IFDEF and IFNDEF: the same look-up the evaluator uses, but here
;     "not found" is the answer rather than an error. That is the
;     manual's own distinction, and it is why these two do not go
;     through eval_expression.

cond_true.ifdef:
		call	symbol_is_defined	; CY clear = the symbol exists
		jp	nc,cond_true.true
		scf
		ret

cond_true.ifndef:
		call	symbol_is_defined
		jp	c,cond_true.true
		scf
		ret

; symbol_is_defined - does the operand name a symbol that is defined?
;
;   symbol_lookup is a variable holding a routine's ADDRESS. The push/ex/ret
;   below is the Z80's way of calling through one: the target's own ret
;   comes back to symbol_is_defined's caller.
;
; Input:	IX -> the field block
; Output:	CY set = no such symbol
; Modifies:	AF, BC, DE, HL, IX

symbol_is_defined:
		ld	e,(ix+FIELD_OPERAND)
		ld	d,(ix+FIELD_OPERAND+1)
		ld	a,(ix+FIELD_OPERAND_LENGTH)
		ld	b,a
		or	a
		scf
		ret	z		; no operand at all: not defined
		push	hl
		ld	hl,(symbol_lookup)
		ex	(sp),hl
		ret

; args_are_same - are arguments 0 and 1 the same text?
;
;   EXACTLY THE SAME TEXT, case included. M80 compares these byte for
;   byte - IFCASE.AS, cross-checked in m80ref - and it is not simply
;   upper-casing the source on the way in: a macro's dummy parameter IS
;   matched ignoring case in the same assembler (PCASE.AS, and find_pool_name
;   in macros.as does the same). A NAME is matched ignoring case; IFIDN
;   and IFDIF compare TEXT, and text is compared exactly.
;
;   This folded until 089, in both modes, and /C had nothing to do with
;   it either way: /C makes NAMES case-sensitive, and this was never a
;   name. The bug was in the default mode.
;
;   Argument 0 has to be copied out of the way first - only its address
;   and length, not its text - because finding argument 1 overwrites
;   where find_argument keeps its answer.
;
; Input:	IX -> the field block
; Output:	Z set = identical
; Modifies:	AF, C, DE, HL

args_are_same:	xor	a
		call	find_argument
		ld	(arg0_text),de
		ld	(arg0_length),a
		ld	a,1
		call	find_argument	; DE -> argument 1, A = its length
		ld	hl,arg0_length
		cp	(hl)
		ret	nz		; different lengths: different
		or	a
		ret	z		; both empty: the same
		ld	c,a		; C = characters to compare
		ld	hl,(arg0_text)
args_are_same.compare:
		ld	a,(de)
		cp	(hl)		; the bytes, as they were written. B
		ret	nz		;   held the folded copy and is now
					;   not touched at all
		inc	hl
		inc	de
		dec	c
		jr	nz,args_are_same.compare
		ret			; C reached 0, so Z is set

; find_argument - find argument number A in the operand, with one level of
;   angle brackets taken off.
;
;   The same grammar build_args (expand.as) reads, without the "!" escape and
;   without copying anything: the text stays in the line buffer and this
;   points at it. IRP wants the same routine, which is why it
;   is written to take an index rather than being folded into cond_true.
;
; Input:	A   = which argument, 0-based
;		IX -> the field block
; Output:	DE -> the text, A = its length. A is 0 when there is no
;		such argument, or it is empty
; Modifies:	AF, BC, DE, HL

find_argument:	ld	(arg_wanted),a
		; B = characters left in the operand
		ld	b,(ix+FIELD_OPERAND_LENGTH)
		ld	l,(ix+FIELD_OPERAND)
		ld	h,(ix+FIELD_OPERAND+1)

find_argument.loop:
		call	step_argument	; one argument -> arg_text, arg_length
		ld	a,(arg_wanted)
		or	a
		jr	z,find_argument.found	; that was the one asked for
		dec	a
		ld	(arg_wanted),a
		ld	a,b
		or	a
		jr	nz,find_argument.loop
		xor	a		; the operand ran out first: treat the
		ld	(arg_length),a	; missing argument as empty
find_argument.found:
		ld	de,(arg_text)
		ld	a,(arg_length)
		ret

; step_argument - step over one argument, noting where its text is and how long
;   it is. HL and B are left past its comma.
;
; Input:	HL -> the operand, B = characters left
; Output:	arg_text, arg_length; HL and B advanced
; Modifies:	AF, B, C, DE, HL

step_argument:	call	skip_arg_blanks	; blanks before it are not part of it
		ld	(arg_text),hl
		ld	c,0		; C = characters in it
		ld	a,b
		or	a
		jr	z,step_argument.done	; nothing left
		ld	a,(hl)
		cp	"<"
		jr	z,step_argument.bracketed

; --- unbracketed: everything up to the next comma

step_argument.plain:
		ld	a,b
		or	a
		jr	z,step_argument.done
		ld	a,(hl)
		cp	","
		jr	z,step_argument.comma
		inc	hl
		dec	b
		inc	c
		jr	step_argument.plain

step_argument.comma:
		inc	hl		; step over the comma
		dec	b
		jr	step_argument.done

; --- <bracketed>: one level comes off, inner ones stay

step_argument.bracketed:
		inc	hl		; over the "<"
		dec	b
		ld	(arg_text),hl	; the text starts after it
		ld	d,1		; D = how deep in brackets we are
step_argument.bracket_scan:
		ld	a,b
		or	a
		; unterminated: the line closes it
		jr	z,step_argument.done
		ld	a,(hl)
		cp	"<"
		jr	nz,step_argument.bracket_close
		inc	d
		jr	step_argument.bracket_take
step_argument.bracket_close:
		cp	">"
		jr	nz,step_argument.bracket_take
		dec	d
		; the matching one: this is the end
		jr	z,step_argument.bracket_done
step_argument.bracket_take:
		inc	hl
		dec	b
		inc	c
		jr	step_argument.bracket_scan
step_argument.bracket_done:
		inc	hl		; over the ">"
		dec	b
		call	skip_to_comma	; anything before the comma is not
					; part of anything

step_argument.done:
		ld	a,c
		ld	(arg_length),a
		ret

; skip_to_comma - throw away everything up to and including the next comma.
;
; Input:	HL -> the operand, B = characters left
; Output:	HL and B past it
; Modifies:	AF, B, HL

skip_to_comma:	ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		inc	hl
		dec	b
		cp	","
		ret	z
		jr	skip_to_comma

; skip_arg_blanks - step over spaces and tabs.
;
; Input:	HL -> the operand, B = characters left
; Output:	HL and B past any run of them
; Modifies:	AF, B, HL

skip_arg_blanks:
		ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		cp	CHR_SPACE
		jr	z,skip_arg_blanks.step
		cp	CHR_TAB
		ret	nz
skip_arg_blanks.step:
		inc	hl
		dec	b
		jr	skip_arg_blanks

		dseg

cond_depth:	defs	1		; how many conditionals are open
cond_label_assembled:
		defs	1
			; cond_skipping's answer, kept for main.next_line:
					;   0FFh = the line just read was being
					;   assembled, so a label on it is
					;   defined
cond_stack:	defs	COND_MAX_DEPTH	; one state byte each
cond_directive:	defs	1		; the opener cond_true is working on
outer_file:	defs	1		; cond_push: where the outermost open
outer_line:	defs	2	;   conditional is, for error_cond_not_closed

arg_text:	defs	2	; find_argument: where the argument's text is
arg_length:	defs	1		; find_argument: how long it is
arg_wanted:	defs	1		; find_argument: which one is wanted
arg0_text:	defs	2		; args_are_same: argument 0's text
arg0_length:	defs	1		; args_are_same: and its length
