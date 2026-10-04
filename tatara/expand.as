; expand.as - replaying a stored macro body.
;
; An expansion is just another line source: expand_line has the same shape
; as file_line in srcline.as, and next_source_line calls whichever the enrty on
; top of the stack calls for. Nested calls need no code of their own - the
; inner one is another entry on the same stack.
;
; The page-2 rule, throughout: an address from deref is good only until
; the next deref, halloc, hfree, ht* call, page2_restore of BDOS call. So the
; expansion record is mapped, read, and let go; then the block is mapped,
; read, and let go. Nothing is remembered across a mapping except by
; copying it into ordinary RAM first.
;
; No msxdos.inc here, and no BDOS call anywhere in the file: everything
; this module touches is mapper RAM or its own variables. It is the only
; module of which that is true.

EXPAND_INCLUDED	equ	1		; skips the externals in expand.inc

		public	expand_init
		public	expand_start
		public	expand_start_repeat
		public	build_item_block
		public	expand_exit
		public	free_descriptor
		public	expand_line

		include	srcline.inc
			; push_macro, current_file, current_line, LINE_MAX
		include	mdt.inc
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been declared
		include	ascii.inc	; CHR_SPACE, CHR_TAB
		include	expand.inc
		include	errs.inc
		include	expr.inc	; eval_absolute, for a "%" argument
		include	strutil.inc	; build_decimal, for its digits
		include	cond.inc	; cond_depth: how many conditionals are
					;   open. Read when a record is made,
					;   written back by expand_exit - the
					;   only two places outside cond.as

		cseg

; expand_init - get this module ready for a pass.
;
;   Called from main: alongside macro_table_init and source_init, and called
;   AGAIN at the start of pass 2 - which is the whole reason it exists. Pass 2
;   re-reads the source and re-expands it, so every ??nnnn must come out with
;   the number it had on pass 1. If the counter carried over, a label DEFINED
;   as ??0007 on pass 1 would be REFERENCED as ??0011 on pass 2, and every
;   local label in the program would become a phase error with nothing in the
;   message pointing at why.
;
; Input:	nothing
; Output:	the ??nnnn counter is back at zero
; Modifies:	AF, HL

expand_init:	ld	hl,0
		ld	(next_local_number),hl
		ld	hl,NULL_OFFSET	; no IRP item block is waiting to be
		ld	(irp_item_block+2),hl
					; adopted. Without this the FIRST
		ret			; macro call of the run would read
					; whatever the dseg happened to hold
					; and take it for a pre-built block

; expand_start_repeat - start an anonymous body: the same as expand_start, but
; with a repeat count and no arguments.
;
; Input:	HL -> the descriptor's far pointer
;		BC = how many times to replay it
; Output:	CY clear = it is on top of the line-source stack, or the
;		           count was zero and it was freed instead
; Modifies:	AF, BC, DE, HL, IX

expand_start_repeat:
		ld	a,b		; nothing to do at all?
		or	c
		jr	z,expand_start_repeat.none
		ld	de,0		; a REPT has no argument text
		xor	a
		jr	expand_start.common

expand_start_repeat.none:
		ld	de,macro_descriptor
					; rept 0: the body was collected and
		ld	bc,4		; is now unreachable, so give it back
		ldir
		ld	hl,macro_descriptor
		call	free_descriptor
		or	a		; CY clear = nothing was pushed. hfree
		ret	; ends in free_list_add, whose last instruction
					; is an ldir, and ldir leaves CY alone -
					; so hfree's CY is whatever the caller
					; had. It must be set here, not assumed

; expand_start - start expanding a macro: parse the call's arguments, allocate
;   an expansion record, fill it in, and push it on the line-source stack.
;
; Input:	HL -> the descriptor's far pointer
;		DE -> the call's argument text (not zero-terminated)
;		A   = how many characters of it
;		current_file/current_line = where the call was
; Output:	CY clear = the expansion is on top of the stack, or the
;		           macro had an empty body and nothing was pushed
; Modifies:	AF, BC, DE, HL, IX

expand_start:	ld	bc,1		; a macro call replays its body once
		push	af		; A is the argument text's LENGTH, so
		ld	a,PARM_MAX	; it has to be put back: a macro call
		ld	(args_reserved),a
					; caps at PARM_MAX, because a 17th
		pop	af		; argument could never be named
expand_start.common:
		ld	(iterations),bc
		ld	(arg_text_at),de
					; the argument text lives in the line
		ld	(arg_text_length),a
					; buffer, so note it before anything
					; else runs
		ld	de,macro_descriptor	; keep the descriptor's pointer
		ld	bc,4
		ldir

		derefp	macro_descriptor
					; read what we need out of it in one
		; mapping, before anything else can
		ld	de,MACRO_LOCAL_COUNT
		add	hl,de		; take page 2 away
		ld	a,(hl)
		ld	(local_count),a	; MACRO_LOCAL_COUNT
		ld	de,MACRO_DEF_FILE-MACRO_LOCAL_COUNT
		add	hl,de
		ld	a,(hl)
		ld	(definition_file),a	; MACRO_DEF_FILE
		ld	de,MACRO_BODY-MACRO_DEF_FILE
		add	hl,de
		fpsave	body_block	; MACRO_BODY

		fpnull	body_block
		jp	z,expand_start.empty_body
					; no body at all. A jp, not a jr: the
					; code from here to the end of
					; expand_start is about 140 bytes and
					; jr reaches 127

		fpnull	irp_item_block	; did the driver already build one?
		jr	z,expand_start.parse_args
					; no: parse the operand, as always
		fpcopy	args_block,irp_item_block
					; yes: take it, and empty the holder
		ld	hl,NULL_OFFSET	; so that it is used exactly once and
		ld	(irp_item_block+2),hl
					; the next macro call cannot adopt it
		jr	expand_start.record
expand_start.parse_args:
		call	build_args	; the call's arguments, in the heap

expand_start.record:
		derefp	macro_descriptor
					; one more expansion is reading this
		ld	de,MACRO_USES	; body. It is what makes redefining a
		add	hl,de		; macro while it expands safe, and it
		inc	(hl)		; is kept for all four kinds so that
					; the field is never wrong

		ld	bc,EXPANSION_SIZE	; the expansion record
		ld	hl,expansion_record
		call	halloc
		jp	c,error_out_of_memory

		; fill it in. EXPANSION_DESCRIPTOR is at offset 0 now
		derefp	expansion_record
		ex	de,hl		; that MX_PAR is gone: the record has no
					; parent pointer, because the origin
					; trail is the line source stack
		ld	hl,macro_descriptor
		ld	bc,4
		ldir			; EXPANSION_DESCRIPTOR
		ld	hl,body_block
		ld	bc,4
		ldir	; EXPANSION_BLOCK = the first body block

		ld	hl,BODY_DATA	; EXPANSION_OFFSET = the first record
		ex	de,hl
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),0		; EXPANSION_LINE
		inc	hl
		ld	(hl),0
		inc	hl
		ld	a,(current_file)
		ld	(hl),a		; EXPANSION_CALL_FILE
		inc	hl
		ld	de,(current_line)
		ld	(hl),e		; EXPANSION_CALL_LINE
		inc	hl
		ld	(hl),d
		inc	hl

		ex	de,hl		; DE -> EXPANSION_ARGS in the record
		ld	hl,args_block
		ld	bc,4
		ldir			; EXPANSION_ARGS
		ld	a,(args_stored)
		ld	(de),a		; EXPANSION_ARG_COUNT
		inc	de
		; EXPANSION_LABEL_BASE: the first ??nnnn this
		ld	hl,(next_local_number)
		ld	a,l		; expansion may use
		ld	(de),a
		inc	de
		ld	a,h
		ld	(de),a
		inc	de
		ld	a,(local_count)	; and the counter moves past the whole
		ld	c,a		; run, so the next expansion cannot
		ld	b,0		; collide with this one
		add	hl,bc
		ld	(next_local_number),hl
		ex	de,hl
		; EXPANSION_ITERATIONS: 1 for a macro, n for a REPT
		ld	de,(iterations)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),0	; EXPANSION_ITEM - the item list is walked
		inc	hl		; with it
		ld	(hl),0
		inc	hl
		; EXPANSION_COND_DEPTH: EXITM unwinds to here, so
		ld	a,(cond_depth)
		ld	(hl),a		; that a body abandoned part-way
					; through an IF does not leave that
					; level open for cond_eof to complain
					; about

		ld	hl,expansion_record	; and push it
		ld	a,(definition_file)
		jp	push_macro

; --- the body has no lines in it at all.
;
;     A named macro's descriptor stays where it is: the name table points
;     at it, calling it again is legal, and it does nothing. An anonymous
;     one has no owner - expand_start_repeat returns from here, BEFORE the
;     expansion record that would have freed it is ever allocated - so this is
;     the only place it can ever be given back. Without this, "rept n" with
;     nothing before its ENDM strands a descriptor per dispatch, and a REPT
;     inside a macro body is dispatched once per expansion.
;
;     MACRO_KIND decides, which is the same test free_expansion makes when the
;     body DOES have lines - the two places an anonymous body can end, asking
;     the same question.

expand_start.empty_body:
		derefp	macro_descriptor
		ld	a,(hl)		; MACRO_KIND
		or	a
		ret	z		; MACRO_IS_MACRO: not ours to free
		ld	hl,macro_descriptor
		call	free_descriptor
		or	a		; CY clear = nothing was pushed
		ret

; build_args - turn the call's argument text into a block in the heap.
;
;   One pass. The offset table is written at its final place while the
;   strings are appended after it, which works because the table's size
;   does not depend on how many arguments there turn out to be.
;
;   Page 2 is held for the whole routine on purpose: nothing here derefs,
;   allocates or calls MSX-DOS after the block is mapped, and the text
;   being read is in the line buffer, in ordinary RAM.
;
;   ONE EXCEPTION,: a "%" argument evaluates an expression,
;   which reaches look_up_symbol and so deref. It lets the mapping go and takes
;   it back with one derefp. Nothing else has to be redone, because deref
;   always answers 08000h + offset: the block reappears at the address it
;   had, and every pointer into it is still right. Anything added to this
;   routine later must obey the same rule or do the same thing.
;
;   The two jumps that leave the argument loop are jp, not jr: the loop
;   body is about 110 bytes and jr reaches 127, which is too close to
;   trust - the same arithmetic that caught split_line in fields.as.
;
; Input:	arg_text_at -> the argument text
;		arg_text_length  = its length
; Output:	args_block = far pointer to the block, null if there were none
;		args_stored = how many arguments were stored
; Modifies:	AF, BC, DE, HL

build_args:	xor	a
		ld	(args_stored),a
		ld	hl,NULL_OFFSET
		ld	(args_block+2),hl	; null until there is a block
		ld	a,(arg_text_length)
		or	a
		ret	z		; the call had no operand at all

		call	args_block_size	; BC = the block's size, from the
		ld	hl,args_block	; entries the caller reserved and the
		call	halloc		; text as it stands
		jp	c,error_out_of_memory

		derefp	args_block	; HL -> the block, and it stays
		ld	(args_base),hl	; mapped until this routine returns
		ld	de,(args_text_base)
					; the text starts where the table ends
		add	hl,de
		ex	de,hl		; DE -> where the first string goes
		ld	hl,(arg_text_at)	; HL -> the argument text
		ld	a,(arg_text_length)
		ld	(arg_text_left),a

build_args.next_arg:
		ld	a,(args_reserved)
					; B, not HL: HL is the text pointer
		ld	b,a		; and is live all the way round this
		ld	a,(args_stored)	; loop, while B is set to 0 two
		cp	b		; instructions below
		jp	nc,build_args.done
					; as many as the caller reserved room
					; for. A macro call asks for PARM_MAX,
					; and a 17th argument could never be
					; referenced: M80 ignores extras too.
					; An IRP asks for the arithmetic
					; maximum, so for one it never fires
		call	arg_new_slot	; the table entry, and room for the
		ld	b,0		; length byte. B = characters stored

		call	arg_skip_blanks	; blanks before it are not part of it
		jr	c,build_args.finish_arg
					; the text ran out: an empty argument
		cp	","
		jr	z,build_args.finish_arg	; ",,": an empty argument
		cp	"%"
		jp	z,build_args.percent
					; a macro call by value: the VALUE
					; goes in, as digits. arg_skip_blanks
					; has just skipped the blanks, so this
					; is the argument's FIRST character -
					; the only place % is special
		cp	"<"
		jr	nz,build_args.plain	; A is its first character

; --- <bracketed>: one level of brackets comes off, inner ones stay

build_args.bracket:
		ld	c,1		; C = how deep in brackets we are
build_args.bracket_char:
		call	arg_next_char
		jr	c,build_args.finish_arg
					; unterminated: the line closes it
		cp	"!"
		jr	z,build_args.bracket_literal
		cp	"<"
		jr	nz,build_args.bracket_close
		inc	c
		jr	build_args.bracket_keep
build_args.bracket_close:
		cp	">"
		jr	nz,build_args.bracket_keep
		dec	c
		jr	z,build_args.bracket_end
					; the matching one: this is the end
build_args.bracket_keep:
		call	arg_put_char
		jr	build_args.bracket_char
build_args.bracket_literal:
		call	arg_next_char	; "!x": x, whatever x is - and it must
		jr	c,build_args.finish_arg	; not be counted as a bracket
		call	arg_put_char
		jr	build_args.bracket_char
build_args.bracket_end:
		call	arg_skip_to_comma
					; anything between ">" and the comma
		jr	build_args.finish_arg	; is not part of anything

; --- a plain argument: everything up to the next comma

build_args.plain:
		cp	"!"
		jr	nz,build_args.plain_comma
		call	arg_next_char	; "!x": x, whatever x is - including
		jr	c,build_args.finish_arg	; a comma
		call	arg_put_char
		jr	build_args.plain_next
build_args.plain_comma:
		cp	","
		jr	z,build_args.finish_arg	; the argument ends here
		call	arg_put_char
build_args.plain_next:
		call	arg_next_char
		jr	nc,build_args.plain
					; and if the text ran out, it also
					; ends here

build_args.finish_arg:
		call	arg_trim	; trailing blanks, then the length
		ld	a,(args_stored)
		inc	a
		ld	(args_stored),a
		ld	a,(arg_text_left)
		or	a
		jp	nz,build_args.next_arg	; there is more after the comma

build_args.done:
		ld	hl,(args_base)	; ARGS_COUNT last, because the count is
		ld	a,(args_stored)	; not known until the parsing is over -
		ld	(hl),a		; and page 2 is still ours to write it
		ret

; --- %expression: the value, in decimal digits, instead of the text
;
;     The manual (2.7.9) requires an expression "returning a
;     non-relocatable constant", with the same rules as DS - so eval_absolute,
;     which is exactly that check.
;
;     This is the one place in build_args where page 2 is let go. HL (the
;     text) and DE (where the next character goes in the block) are put
;     in RAM first, because the evaluator uses every register, and the
;     block is mapped again afterwards.

build_args.percent:
		ld	(percent_text),hl	; where the expression starts
		ld	b,0		; and how long it is, to the comma
build_args.percent_scan:
		call	arg_next_char
		jr	c,build_args.percent_eval
					; the text ran out: that ends it
		cp	","
		jr	z,build_args.percent_eval
					; and so does the comma, consumed
		inc	b		; here exactly as the plain branch
		jr	build_args.percent_scan	; would have consumed it
build_args.percent_eval:
		ld	a,b
		ld	(percent_length),a
		ld	(percent_write),de
					; the two pointers the evaluator
		ld	(percent_read),hl	; would otherwise destroy

		ld	de,(percent_text)
					; the text is in the line buffer, in
		ld	a,(percent_length)
					; ordinary RAM, so it is readable
		call	eval_absolute	; with page 2 in anybody's hands
		ld	de,percent_buffer
		call	build_decimal	; A = how many digits
		ld	(percent_digits),a

		derefp	args_block	; page 2 is ours again, and the block
		ld	de,(percent_write)	; is back at the address it had
		ld	hl,(percent_read)

		ld	a,(percent_digits)
		ld	c,a
		ld	b,0		; B counts this argument's characters,
		push	hl		; which is what arg_trim writes as its
		ld	hl,percent_buffer	; length
build_args.percent_copy:
		ld	a,(hl)
		inc	hl
		call	arg_put_char
		dec	c
		jr	nz,build_args.percent_copy
		pop	hl
		jp	build_args.finish_arg

; arg_next_char - the next character of the argument text.
;
; Input:	HL      -> the text
;		arg_text_left  = how much is unread
; Output:	CY clear = A is it, HL advanced
;		CY set   = the text is exhausted
; Modifies:	AF, HL

arg_next_char:	ld	a,(arg_text_left)
		or	a
		scf
		ret	z		; nothing left
		dec	a
		ld	(arg_text_left),a
		ld	a,(hl)
		inc	hl
		or	a		; A is a real character, so this only
		ret			; clears CY

; arg_skip_blanks - skip blanks and return the first character that is not one.
;
; Output:	CY clear = A is it
;		CY set   = the text ran out
; Modifies:	AF, HL

arg_skip_blanks:
		call	arg_next_char
		ret	c
		cp	CHR_SPACE
		jr	z,arg_skip_blanks
		cp	CHR_TAB
		jr	z,arg_skip_blanks
		or	a		; a control character would leave CY
		ret			; est after the compare above

; arg_skip_to_comma - throw away everything up to and including the next comma.
;
; Modifies:	AF, HL

arg_skip_to_comma:
		call	arg_next_char
		ret	c
		cp	","
		jr	nz,arg_skip_to_comma
		ret

; arg_put_char - add the character in A to the argument being built.
;
;   No length check: the block was sized from the operand's length, and
;   removing brackets and "!" can only make the text shorter.
;
; Input:	A   = the character
;		DE -> where it goes
;		B   = the count
; Output:	stored, DE and B advanced
; Modifies:	AF

arg_put_char:	ld	(de),a
		inc	de
		inc	b
		ret

; arg_new_slot - start a new argument: record where its length byte is, both
;   in arg_length_at and in the offset table, and step DE past it.
;
;   The offset stored is from the block's start, not an address, because
;   the block moves in page 2 every time it is mapped.
;
; Input:	DE    -> where this argument goes
;		args_stored = its index
; Output:	AF, BC, DE

arg_new_slot:	push	hl
		ld	(arg_length_at),de	; where the length byte goes
		ld	hl,(args_base)
		ex	de,hl		; HL = the address, DE = the block
		or	a
		sbc	hl,de		; HL = the offset of the length byte
		ex	de,hl		; DE = the offset, HL -> the block
		ld	a,(args_stored)	; each table entry is two bytes, and
		ld	c,a		; the doubling is done in 16 bits: an
		ld	b,0		; IRPC can have up to 255 items, and
		add	hl,bc		; "add a,a" would lose the 128th
		add	hl,bc
		ld	bc,ARGS_TABLE
		add	hl,bc		; HL -> this argument's table entry
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	hl,(arg_length_at)
		inc	hl		; the text starts after the length
		ex	de,hl		; DE -> there
		pop	hl
		ret

; arg_trim - trailing blanks are not part of an argument. Then write the
;   length into the byte arg_new_slot left for it.
;
; Input:	B = characters stored
;		DE -> just past the last one
; Output:	B and DE cut back, the length byte written
; Modifies:	AF, B, DE

arg_trim:	ld	a,b
		or	a
		jr	z,arg_trim.store
					; an empty argument: nothing to trim
		push	hl
		ld	h,d
		ld	l,e
		dec	hl		; HL -> the last character stored
arg_trim.scan:	ld	a,(hl)
		cp	CHR_SPACE
		jr	z,arg_trim.cut
		cp	CHR_TAB
		jr	nz,arg_trim.pop
arg_trim.cut:	dec	hl
		dec	de
		djnz	arg_trim.scan	; and if B reaches 0 the argument was
					; nothing but blanks
arg_trim.pop:	pop	hl
arg_trim.store:	push	hl
		ld	hl,(arg_length_at)
		ld	(hl),b		; the length, at last
		pop	hl
		ret

; expand_exit - EXITM: abandon the expansion on top of the stack.
;
;   The manual (books/m80l80.txt 2.7.7): "the expansion is exited
;   immediately and any remaining expansion or repetition is not
;   generated. If the block containing the EXITM is nested within another
;   block, the outer level continues to be expanded."
;
;   All three fall out of freeing the record and popping one source. The
;   remaining rounds of a REPT go because the count lives in the record;
;   the outer level continues because only the top entry is popped; and
;   free_expansion already frees the body and descriptor too when the block was
;   anonymous.
;
;   The conditional stack is the part that does NOT fall out. This is the
;   shape EXITM exists for:
;
;       foo	macro	x
;		ifb	<x>
;		exitm
;		endif
;
;   and the ENDIF is never reached. Without the unwind, one call leaves a
;   level open for cond_eof to complain about at the end of a program with
;   nothing wrong with it, and sixteen exhaust COND_MAX_DEPTH.
;
; Input:	nothing
; Output:	the top expansion is gone
;		(an EXITM with no expansion open does not return)
; Modifies:	AF, BC, DE, HL, IX

expand_exit:	ld	a,(source_depth)
		or	a
		jp	z,error_exitm_outside	; nothing stacked at all
		ld	ix,(source_top)
		ld	a,(ix+SOURCE_KIND)
		cp	SOURCE_IS_MACRO
		jp	nz,error_exitm_outside	; the top source is a file

		call	map_record	; the depth this expansion started at
		ld	de,EXPANSION_COND_DEPTH
		add	hl,de
		ld	a,(hl)
		ld	(cond_depth),a	; every conditional it opened is
					; abandoned along with the lines that
					; would have closed them

		call	free_expansion	; the record, its arguments, and for
		jp	pop_source	; a REPT/IRP/IRPC the body as well

; build_item_block - build the item block for an IRP or an IRPC, before the
; body is collected.
;
;   The timing is the whole point. The item text is in line_buffer, and
;   collect_block is about to borrow line_buffer for every body line it reads -
;   so by the time the ENDM arrives, a pointer into it aims at rubbish. The
;   block has to exist before that, and the answer (work it out early, it is
;   only two bytes) does not scale to a list.
;
;   The block's pointer does NOT go in args_block. An IRP inside a macro body
;   is collected while that macro is expanding, and every line collect_block
;   reads runs map_arguments, which overwrites args_block. irp_item_block is
;   touched by nothing else, and its being null is what tells
;   expand_start.common to parse an operand of its own.
;
; Input:	DE -> the item text, one level of <> already off
;		A   = its length
;		C   = MACRO_IS_IRP or MACRO_IS_IRPC
; Output:	irp_item_block = the block, or null when there was no text
;		BC = iterations
; Modifies:	AF, BC, DE, HL

build_item_block:
		ld	(arg_text_at),de
		ld	(arg_text_length),a
		ld	hl,NULL_OFFSET
		ld	(irp_item_block+2),hl	; no block yet

		or	a
		jr	nz,build_item_block.text

		ld	a,c		; the kind, BEFORE BC becomes the count
		ld	bc,0		; nothing after the comma. IRPC "" is
		cp	MACRO_IS_IRPC	; no characters, so no repetitions;
		ret	z		; IRP <> is once with the dummy removed
		inc	bc		; - and a null block is exactly what
		ret	; "removed" looks like to line_put_argument

build_item_block.text:
		ld	a,c
		cp	MACRO_IS_IRPC
		jr	z,build_item_block.chars
		ld	a,(arg_text_length)	; an IRP: "a,b,c" holds at most
		or	a		; len/2 + 1 items. or a clears the
		rra			; carry rra would otherwise rotate in
		inc	a		; from the top
		ld	(args_reserved),a
		call	build_args
		jr	build_item_block.keep

build_item_block.chars:
		call	build_char_args	; an IRPC: one item per character

build_item_block.keep:
		fpcopy	irp_item_block,args_block
					; out of the shared scratch and into
		ld	a,(args_stored)	; somewhere collection cannot reach
		ld	c,a
		ld	b,0
		ret

; build_char_args - build an argument block holding one character per item.
;
;   IRPC's "arglist" is a string, and every character of it is an item -
;   spaces and commas included. So there is no grammar here: no brackets
;   come off, no "!" escapes are honoured and no blanks are trimmed. What
;   it shares with build_args is the block itself, and arg_new_slot, which
;   writes one table entry.
;
;   It writes each length byte itself rather than calling arg_trim, which
;   would trim a space and turn a perfectly good item into an empty one.
;
; Input:	arg_text_at -> the string, arg_text_length = its length
; Output: args_block = the block, args_stored = how many characters it held
; Modifies:	AF, BC, DE, HL

build_char_args:
		xor	a
		ld	(args_stored),a
		ld	hl,NULL_OFFSET
		ld	(args_block+2),hl	; null until there is a block
		ld	a,(arg_text_length)
		or	a
		ret	z		; an empty string: no items

		ld	(args_reserved),a
					; one entry per character, exactly
		ld	(arg_text_left),a
		call	args_block_size	; BC = the block's size
		ld	hl,args_block
		call	halloc
		jp	c,error_out_of_memory

		derefp	args_block	; HL -> the block, and it stays
		ld	(args_base),hl	; mapped until this returns
		ld	de,(args_text_base)
		add	hl,de
		ex	de,hl		; DE -> where the first item goes
		ld	hl,(arg_text_at)

build_char_args.next_char:
		call	arg_new_slot	; the table entry, and DE past the
		push	hl		; length byte it left room for
		ld	hl,(arg_length_at)
		ld	(hl),1		; always exactly one character
		pop	hl
		ld	a,(hl)
		inc	hl
		ld	(de),a
		inc	de
		ld	a,(args_stored)
		inc	a
		ld	(args_stored),a
		ld	a,(arg_text_left)
		dec	a
		ld	(arg_text_left),a
		jr	nz,build_char_args.next_char

		; ARGS_COUNT last, with page 2 still ours
		ld	hl,(args_base)
		ld	a,(args_stored)
		ld	(hl),a
		ret

; args_block_size - one argument block's size, from args_reserved and
; arg_text_length.
;
;   Three bytes an entry: two of offset table and one length byte, plus
;   ARGS_COUNT itself, plus room for the text as it stands. args_text_base is
;   kept as well because the text base is where the table ends - ARGS_TEXT is
;   no longer a constant now that the table is sized by its caller.
;
;   For args_reserved = PARM_MAX this computes exactly the ARGS_OVERHEAD in
;   mdt.inc, which is why that equate stays there to be compared against.
;
; Input:	args_reserved, arg_text_length
; Output: args_text_base = ARGS_TABLE plus the table's length, BC = the block
; size
; Modifies:	AF, BC, DE, HL

args_block_size:
		ld	a,(args_reserved)
		ld	l,a
		ld	h,0
		ld	e,l
		ld	d,h
		add	hl,hl		; two bytes of table per entry
		inc	hl	; past ARGS_COUNT: this is the text base
		ld	(args_text_base),hl
		add	hl,de		; one length byte per entry
		ld	a,(arg_text_length)
		ld	e,a
		ld	d,0
		add	hl,de		; and the text
		call	args_percent_room
					; plus room for the digits a "%"
		ld	b,h		; turns into
		ld	c,l
		ret

; args_percent_room - add three bytes to the size for every "%" in the text.
;
;   "%A" is two characters and 65535 is five, so three bytes each is the
;   most the digits can add. EVERY "%" is counted, not only the ones that
;   start an argument: telling them apart means splitting the text into
;   arguments, which is build_args' whole job and not worth doing twice. A
;   stray "%" inside an argument costs three bytes of heap and nothing
;   else.
;
; Input:	HL = the size so far
; 		arg_text_at -> the text
; 		arg_text_length  = its length
; Output:	HL = the size, with room for the digits
; Modifies:	AF, BC, DE, HL

args_percent_room:
		ld	a,(arg_text_length)
		or	a
		ret	z
		ld	b,a
		ld	de,(arg_text_at)
args_percent_room.scan:
		ld	a,(de)
		inc	de
		cp	"%"
		jr	nz,args_percent_room.next
		push	de
		ld	de,3
		add	hl,de
		pop	de
args_percent_room.next:
		djnz	args_percent_room.scan
		ret

; expand_line - the next line of a macro expansion
;
;   The same shape as file_line: entry in IX, buffer in HL, carry set when
;   there is nothing left. next_source_line calls one or the other and does not
;   care which.
;
; Input:	IX -> a line source entry of the macro kind
;		HL -> where to put the line
; Output:	CY clear = a line is there, zero-terminated, A = its length
;		CY set   = the body is finished, and the expansion record
;		           has been freed
; Modified:	AF, BC, DE, HL

expand_line:	ld	(line_dest),hl

expand_line.find_record:
		call	map_record	; where are we in the body?
		ld	de,EXPANSION_BLOCK
		add	hl,de
		fpsave	body_block
				; and fpsave leaves HL at EXPANSION_OFFSET
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(body_offset),de

		fpnull	body_block
		jp	z,expand_line.body_done
					; no body block: nothing to replay

		derefp	body_block	; how full is this block?
		ld	de,BODY_USED
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(body_filled),de

		ld	hl,(body_offset)
		ld	de,(body_filled)
		or	a
		sbc	hl,de
		jr	c,expand_line.copy_record
					; there is a record at this offset

		derefp	body_block	; block finished: follow BODY_NEXT,
		fpsave	body_block	; which is at offset 0
		fpnull	body_block
		jp	z,expand_line.body_done
					; no next block: the body is over
		ld	hl,BODY_DATA
		ld	(body_offset),hl
		call	save_position
		jp	expand_line.find_record

; --- copy one record out of the heap, then let page 2 go

expand_line.copy_record:
		derefp	body_block
		ld	de,(body_offset)
		add	hl,de		; HL -> the record
		ld	a,(hl)
		ld	(stored_length),a	; LINE_LENGTH
		inc	hl
		ld	e,(hl)		; LINE_NUMBER
		inc	hl
		ld	d,(hl)
		ld	(stored_line_number),de
		inc	hl		; HL -> the text
		ld	de,stored_record
		ld	a,(stored_length)
		or	a
		jr	z,expand_line.terminate
		ld	c,a
		ld	b,0
		ldir
expand_line.terminate:
		ex	de,hl
		ld	(hl),0		; terminate it

		ld	hl,(body_offset)	; step past the record
		ld	a,(stored_length)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,LINE_HEADER_SIZE
		add	hl,de
		ld	(body_offset),hl
		call	save_position

		ld	de,(stored_line_number)
					; this line came from body line n of
		; the definition's file, which is
		ld	(ix+SOURCE_LINE),e
		ld	(ix+SOURCE_LINE+1),d	; already in SOURCE_FILE_NUMBER

		call	build_line	; A = the length
		or	a		; clears CY = a line is there
		ret

; --- the body has run out. For a macro that is the end; for a REPT it
;     may be the end of one iteration out of several.

expand_line.body_done:
		call	map_record
		ld	de,EXPANSION_ITERATIONS
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		dec	de		; one iteration used up
		ld	a,d
		or	e
		jr	z,expand_line.finished	; that was the last of them
		ld	(hl),d		; write the new count back
		dec	hl
		ld	(hl),e
		call	expand_rewind
		jp	expand_line.find_record

expand_line.finished:
		call	free_expansion
		scf			; CY set = the body is finished
		ret

; expand_rewind - go back to the first stored line for another iteration.
;
;   MACRO_BODY is re-read from the descriptor rather than remembered from
;   when the expansion started: one more deref per iteration, and one
;   less far pointer to keep in step inside the record.
;
;   The fresh run of ??nnnn numbers is not housekeeping. Without it every
;   iteration of a REPT containing a LOCAL emits the SAME label, which is
;   precisely what LOCAL exists to prevent (mdt-design.md 7).
;
; Input:	IX -> the entry
; Output:	the record points at the first body line again
; Modifies:	AF, BC, DE, HL

expand_rewind:	call	map_record	; the descriptor, out of the record
		ld	de,EXPANSION_DESCRIPTOR
		add	hl,de
		fpsave	macro_descriptor

		derefp	macro_descriptor
				; MACRO_LOCAL_COUNT and MACRO_BODY, one mapping
		ld	de,MACRO_LOCAL_COUNT
		add	hl,de
		ld	a,(hl)
		ld	(local_count),a
		ld	de,MACRO_BODY-MACRO_LOCAL_COUNT
		add	hl,de
		fpsave	body_block

		ld	hl,BODY_DATA	; back to the first record in it
		ld	(body_offset),hl
		call	save_position

		call	map_record	; a fresh run of ??nnnn for this
		ld	de,EXPANSION_LABEL_BASE	; iteration
		add	hl,de
		ld	de,(next_local_number)
		ld	(hl),e
		inc	hl
		ld	(hl),d

		ld	hl,(next_local_number)	; and the counter moves past it
		ld	a,(local_count)
		ld	c,a
		ld	b,0
		add	hl,bc
		ld	(next_local_number),hl

		call	map_record	; and on to the next item, for an IRP.
		; A REPT has this incremented too and
		ld	de,EXPANSION_ITEM
		add	hl,de		; does not care: it has no argument
		inc	(hl)	; block, so line_put_argument never reads it
		ret

; build_line - build the line to deliver from the record just copied out.
;
;   The line can now GROW: a two-byte marker becomes an argument of any
;   length. That is why line_put_char checks the room left before every byte,
;   and why this is the first phase in which an expansion can be too long.
;
; Input:	stored_record holds the stored text
;		line_dest holds where the line goes
;		IX -> the line source entry
; Output:	the line is built, zero-terminated, A = its length
; Modifies:	AF, BC, DE, HL

build_line:	call	map_arguments	; the arguments, mapped once for the
					; whole line
		ld	hl,stored_record
		ld	de,(line_dest)
		ld	b,0		; B = characters delivered
build_line.next_char:
		ld	a,(hl)
		or	a
		jr	z,build_line.terminate
		cp	MARK_PARAMETER
		jr	z,build_line.parameter
		cp	MARK_LOCAL
		jr	z,build_line.local
		call	line_put_char
		inc	hl
		jr	build_line.next_char
build_line.parameter:
		inc	hl		; the index follows the marker byte
		ld	a,(hl)
		inc	hl
		push	hl
		call	line_put_argument
		pop	hl
		jr	build_line.next_char
build_line.local:
		inc	hl		; the same shape, a different source
		ld	a,(hl)
		inc	hl
		push	hl
		call	line_put_local
		pop	hl
		jr	build_line.next_char
build_line.terminate:
		ex	de,hl
		ld	(hl),0		; terminate the delivered line
		ld	a,b		; A = its length
		ret

; line_put_char - add the character in A to the line being delivered.
;
; Input:	A   = the character
;		DE -> where it goes
;		B   = the count
; Output:	stored, DE and B advanced
;		(a line that grew too long does not return -
;		error_macro_line_long stops)
; Modifies:	AF

line_put_char:	ld	(line_char),a
		ld	a,b
		cp	LINE_MAX
		jp	nc,error_macro_line_long
		ld	a,(line_char)
		ld	(de),a
		inc	de
		inc	b
		ret

; line_put_argument - copy argument number A into the line being delivered.
;
;   Both "no arguments at all" and "not that many arguments" produce
;   nothing, which is M80's rule: a parameter with nothing supplied for
;   it is null.
;
; Input:	A   = the index, 0-based
;		DE -> where the text goes
;		B   = characters so far
; Output:	the argument's text is added, DE and B advanced
; Modifies:	AF, C, DE, HL

line_put_argument:
		ld	hl,item_index	; an IRP's marker is always index 0,
		add	a,(hl)	; so index + EXPANSION_ITEM is the item this
		; iteration wants. A macro's EXPANSION_ITEM is
		ld	(splice_index),a
		ld	hl,(args_mapped)	; 0, so nothing changes for it
		ld	a,h
		or	l
		ret	z		; the call supplied nothing
		ld	a,(hl)		; ARGS_COUNT
		ld	c,a
		ld	a,(splice_index)
		cp	c
		ret	nc		; fewer arguments than parameters

		push	bc		; HL -> this argument's table entry. B
		ld	c,a		; is the running character count and
		ld	b,0		; must survive the only 16-bit add the
		add	hl,bc		; z80 has - and the doubling is done in
		add	hl,bc		; 16 bits, because an IRPC can have 255
		pop	bc		; items and "add a,a" would lose the
		inc	hl		; 128th. ARGS_TABLE

		ld	a,(hl)		; HL = the offset in the block
		inc	hl
		ld	h,(hl)
		ld	l,a
		push	de
		ld	de,(args_mapped)
		add	hl,de		; HL -> the length byte
		pop	de
		ld	a,(hl)
		or	a
		ret	z		; an empty argument
		ld	c,a		; C = how many characters
		inc	hl
line_put_argument.copy:
		ld	a,(hl)
		inc	hl
		call	line_put_char
		dec	c
		jr	nz,line_put_argument.copy
		ret

; line_put_local - put the generated name for LOCAL number A into the line.
;
;   EXPANSION_LABEL_BASE is read out of the record every time rather than
;   remembered, for the same reason args_mapped is: a nested expansion has its
;   own, and nothing may be held across a call.
;
; Input:	A  = the LOCAL's index, 0-based
;		DE -> where the text goes, B = characters so far
; Output:	"??nnnn" is added, DE and B advanced
; Modifies:	AF, C, DE, HL

line_put_local:	ld	(splice_index),a
		push	de		; DE is the line being built, and
		call	map_record
				; map_record wants it for the far pointer
		ld	de,EXPANSION_LABEL_BASE
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl		; HL = this expansion's first number
		push	bc		; B is the running character count
		ld	a,(splice_index)
		ld	c,a
		ld	b,0
		add	hl,bc		; plus this LOCAL's index
		pop	bc
		pop	de

		ld	a,"?"
		call	line_put_char
		ld	a,"?"
		call	line_put_char
		ld	a,h		; four hex digits, high byte first
		call	line_put_hex
		ld	a,l
		jp	line_put_hex

; line_put_hex - two hex digits for the byte in A, into the line.
;
;   rrca four times, not rra: rra would rotate the carry flag in through
;   the top. The same shape as write_hex_byte in tatara.as, which writes to the
;   output file instead.
;
; Input:	A = the byte
; Output:	two characters are added
; Modifies:	AF, DE (B advanced)

line_put_hex:	push	af
		rrca
		rrca
		rrca
		rrca
		call	line_put_hex.nibble	; the high nibble
		pop	af
		jr	line_put_hex.nibble
					; the low one, and its return is ours
line_put_hex.nibble:
		and	00fh
		add	a,"0"
		cp	"9"+1
		jr	c,line_put_hex.store	; 0-9
		add	a,"A"-"9"-1	; A-F
line_put_hex.store:
		jp	line_put_char

; map_arguments - map this expansion's argument block, once per line.
;
;   args_mapped is where it landed, or zero when the call had no arguments.
;   It is read out of the record eevry time rather than remembered,
;   because a nested expansion overwrites it the moment it starts.
;
; Input:	IX -> the entry
; Output:	args_mapped = the block's address in page 2, or 0
; Modifies:	AF, BC, DE, HL

map_arguments:	ld	hl,0
		ld	(args_mapped),hl
		call	map_record
		ld	de,EXPANSION_ARGS
		add	hl,de
		fpsave	args_block
				; fpsave leaves HL at EXPANSION_ARG_COUNT
		ld	de,EXPANSION_ITEM-EXPANSION_ARG_COUNT
		add	hl,de
		ld	a,(hl)		; which item an IRP is on. Zero for
		ld	(item_index),a
				; everything else, and only expand_rewind ever
					; changes it - so line_put_argument can
					; add it without asking what kind this
					; is
		fpnull	args_block
		ret	z		; the call had no arguments
		derefp	args_block
		ld	(args_mapped),hl
		ret

; map_record - map the expansion record belonging to this entry.
;
;   The far pointer lives in the entry itself, which is in ordinary RAM,
;   so deref can be handed its address directly - no copy needed.
;
; Input:	IX -> the entry
; Output:	HL -> the expansion record, in page 2
; Modifies:	AF, DE, HL (IX preserved - deref does not touch it)

map_record:	push	ix
		pop	hl
		ld	de,SOURCE_EXPANSION
		add	hl,de
		jp	deref

; save_position - write body_block and body_offset back into the expansion
; record.
;
; Input:	IX -> the entry, body_block and body_offset
; Output:	the record is updated
; Modifies:	AF, BC, DE, HL

save_position:	call	map_record
		ld	de,EXPANSION_BLOCK
		add	hl,de
		ex	de,hl		; DE -> EXPANSION_BLOCK in the record
		ld	hl,body_block
		ld	bc,4
		ldir			; DE now -> EXPANSION_OFFSET
		ld	hl,(body_offset)
		ex	de,hl	; HL -> EXPANSION_OFFSET, DE = the value
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ret

; free_expansion - give the expansion record, and its arguments, back to the
;   heap - and for an anonymous body, the body and its descriptor too.
;
;   The argument block goes first: its far pointer ilves inside the
;   expansion record, so it has to be read out while the record is still
;   there to read.
;
;   A named macro's descriptor and body outlive the expansion: the next
;   call needs them. A REPT's cannot be reached by anything once the
;   record is gone, so this is the last chance to give them back.
;   MACRO_KIND is what tells the two apart, and this is that field's first
;   real use.
;
; Input:	IX -> the entry
; Output:	everything this expansion owned is freed
; Modifies:	AF, BC, DE, HL

free_expansion:	call	map_record	; the arguments first: their far
		; pointer lives inside the record
		ld	de,EXPANSION_ARGS
		add	hl,de
		fpsave	args_block
		fpnull	args_block
		jr	z,free_expansion.descriptor
					; the call had no arguments
		ld	hl,args_block
		call	hfree

free_expansion.descriptor:
		call	map_record	; the descriptor's pointer, before
		ld	de,EXPANSION_DESCRIPTOR	; the record goes
		add	hl,de
		fpsave	macro_descriptor

		push	ix		; the record itself
		pop	hl
		ld	de,SOURCE_EXPANSION
		add	hl,de
		call	hfree

		derefp	macro_descriptor
				; MACRO_KIND and MACRO_FLAGS, kept in DE:
		ld	e,(hl)		; nothing between here and the tests
		inc	hl		; below disturbs it
		ld	d,(hl)
		ld	bc,MACRO_USES-MACRO_FLAGS
		add	hl,bc
		dec	(hl)		; one fewer expansion is reading it
		ret	nz		; others still are: it stays

		ld	a,e		; MACRO_KIND
		or	a
		jr	nz,free_expansion.unreachable
					; anonymous: no name ever reached it,
					; so this was the last chance
		ld	a,d		; MACRO_FLAGS
		and	MACRO_ORPHANED
		ret	z		; still reachable by name: it stays

free_expansion.unreachable:
		ld	hl,macro_descriptor
					; nothing reads it and nothing names it
		jp	free_descriptor

; free_descriptor - free a descriptor and its body chain.
;
;   Called from four places when a body has become unreachable: an
;   anonymous one whose expansion has ended (free_expansion above), one that
;   was never expanded at all (expand_start_repeat and
;   expand_start.empty_body), and a named one that has been redefined and whose
;   last reader has finished (orphan_descriptor, in macros.as).
;
;   The chain walk copies each block's BODY_NEXT into ordinary RAM before
;   freeing the block it came from - the block is in page 2, and hfree
;   remaps it.
;
;   It uses macro_descriptor, body_block and expansion_record as scratch. That
;   is safe even when macros.as calls it in the middle of collecting a
;   definition, because all three are re-read from the expansion record at the
;   top of every expand_line, map_arguments and expand_rewind: nothing in this
;   module holds them across a next_source_line.
;
; Input:	HL -> a 4-byte far pointer to the descriptor
; Output:	the body chain and the descriptor are freed
; Modifies:	AF, BC, DE, HL

free_descriptor:
		ld	de,macro_descriptor
		ld	bc,4
		ldir
		derefp	macro_descriptor	; the chain of blocks, then the
		ld	de,MACRO_BODY	; descriptor itself
		add	hl,de
		fpsave	body_block
free_descriptor.next_block:
		fpnull	body_block
		jr	z,free_descriptor.itself
		fpcopy	expansion_record,body_block
					; keep this one while its successor
		derefp	body_block	; is read out of it
		fpsave	body_block	; BODY_NEXT is at offset 0
		ld	hl,expansion_record
		call	hfree
		jr	free_descriptor.next_block

free_descriptor.itself:
		ld	hl,macro_descriptor
		jp	hfree

		dseg

macro_descriptor:
		defs	4	; far pointer: the descriptor being expanded
expansion_record:
		defs	4	; far pointer: the expansion record
body_block:	defs	4	; far pointer: the body block being read
body_offset:	defs	2	; offset of the next record in it
body_filled:	defs	2	; how full that block is
definition_file:
		defs	1	; the file the definition came from
stored_length:	defs	1	; the record's text length
stored_line_number:
		defs	2	; the record's body line number
line_dest:	defs	2	; where the delivered line goes
arg_text_at:	defs	2	; build_args: the call's argument text
arg_text_length:
		defs	1	; build_args: how long it is
arg_text_left:	defs	1	; build_args: how much of it is still unread
args_base:	defs	2	; build_args: the block's address in page 2
arg_length_at:	defs	2	; build_args: this argument's length byte
args_block:	defs	4	; far pointer: the argument block
args_stored:	defs	1	; how many arguments it holds
args_mapped:	defs	2	; build_line: that block, mapped
splice_index:	defs	1	; line_put_argument: the index being spliced
line_char:	defs	1	; line_put_char: the character being added
next_local_number:
		defs	2	; the running ??nnnn number. expand_init puts
				;   it back to zero at the start of a pass
iterations:	defs	2
		; expand_start/expand_start_repeat: iterations, on its way
				;   into EXPANSION_ITERATIONS
args_reserved:	defs	1
			; build_args/build_char_args: table entries to reserve
args_text_base:	defs	2	; ARGS_TABLE plus the table, so the text base
item_index:	defs	1
		; map_arguments: EXPANSION_ITEM, for line_put_argument to add
irp_item_block:	defs	4	; far pointer: an item block built before
				;   the body was collected, waiting for the
				;   expand_start_repeat that will adopt it
		; expand_start: MACRO_LOCAL_COUNT of the macro being called
local_count:	defs	1
percent_text:	defs	2
			; build_args.percent: where the % expression starts
percent_length:	defs	1	;   and how long it is
percent_write:	defs	2
			;   where the digits go, kept across eval_absolute
percent_read:	defs	2	;   and the text pointer, the same way
percent_digits:	defs	1	;   how many digits build_decimal made
percent_buffer:	defs	5	;   and where it put them
stored_record:	defs	LINE_MAX+1	; one stored record, out of the heap
					; and into ordinary RAM. Separate from
					; scanned_line in macros.as on purpose:
					; from a macro can be defined while
					; another is expanding
