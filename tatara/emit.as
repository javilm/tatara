; emit.as - the bytes an assembled line comes to.
;
;   MEASURING CAME FIRST: every handler returned a length and nothing
;   was ever evaluated. Emitting came after, and the length became how
;   bytes went through here - so a handler can no longer say three and
;   write four, which is a wrong program with no error message.
;
;   emit_byte is the sink. Everything below ends in a jp to it, and
;   an earlier design expected it to be replaced. IT DID NOT NEED
;   TO: EMIT_MAX is 256, which is exactly the most a line can
;   emit, so emitted_bytes holds every byte of a line and the DATA record is
;   written from it at the end of the line. The sink is unchanged
;   and the listing and the object file read the same buffer.
;
;   Pass 1 goes through all of this too, emitting zeros where an
;   expression should be and throwing the result away. That is safe for
;   exactly one reason - no value changes any length - and it is what
;   lets one set of handlers serve both passes.

EMIT_INCLUDED	equ	1		; skips the externals in emit.inc

		public	emit_line_start
		public	emit_line_skipped
		public	emit_show_value
		public	list_line	; the driver's tail, made
		public	list_body_line	;   callable - collect_macro lists the
		public	listing_on	;   lines it reads itself
		public	set_title	; TITLE and SUBTTL, the page
		public	listing_eject	;   break PAGE asks for, how long
		public	listing_form_feed	;   a form feed in the source,
		public	set_page_length	;   a page is, and the title
		public	title_text	;   itself, which names the module
		public	listing_init	; the listing's per-pass
		public	list_last_page	;   reset, the last page, and the
		public	write_char	;   one-character write a name
					;   out of the mapper needs
		public	write_crlf	;   and the line ending those two
		public	write_spaces	;   walks put between their lines,
					;   and the padding one of them owes
					;   a short name
		public	write_output	; and the two routines that put
		public	write_line	;   bytes and lines out, which moved
		public	output_handle	;   with it, and the handle they use
		public	emit_byte
		public	emit_word
		public	emit_expr_byte
		public	emit_expr_word
		public	emit_high_bit_last
		public	build_columns
		public	build_more_columns
		public	emitted_count
		public	emitted_bytes
		public	line_address	; they are written into a DATA
		public	line_segment	;   record: they are where the
					;   line's bytes belong
		public	line_source_kind	; and where the line
					;   itself came from
		public	line_calls_macro	; the driver says when a line
					;   called a macro, for .SALL's "+"
		public	expansion_mode
		public	emit_opcode
		public	emit_displacement
		public	emit_saved_byte
		public	emit_saved_word
		public	saved_value
		public	emit_relative

		include	emit.inc
		; expression_text, displacement_text, operand_prefix,
		;   operand_kind
		include	optab.inc
		include	expr.inc	; eval_expression, value_type, SY_ABS
		include	errs.inc	; error_relocation
		include	strutil.inc	; build_hex_word, build_hex_byte
		include	srcline.inc	; pass_number, SOURCE_IS_MACRO
		include	cmdline.inc	; opt_screen, opt_listing and
					;   listing_name: the three reasons
					;   to write text
		include	dos2func.inc	; _GDATE, for the header's date
		include	symtab.inc
				; list_symbols and list_macros: the last page
		include	macros.inc	;   is their tables, and they write it
		include	msxdos.inc
				; _WRITE: write_output and write_line moved
		include	ascii.inc	;   here, and CHR_CR/CHR_LF
					;   are what write_line puts over the
					;   terminator
		include	objout.inc
				; object_fixup: emit_expr_word is where a
					;   relocatable word is seen

		cseg

; emit_line_start - start a line: where it begins, and nothing emitted yet.
;
;   PER LINE. Every other init in the program is per pass or per run;
;   this one runs from main.next_line once a line has been split, because
;   emitted_count is what the listing prints and what checks a
;   handler's claimed length against.
;
;   IT IS TOLD THE ADDRESS RATHER THAN FETCHING IT. location_counter and
;   current_segment live in symtab.as and the listing columns live here, so
;   otherwise one module would reach into the other's data. The verification
;   rule's answer to that is a small routine and not a new global, and this is
;   the routine: main.next_line knows both already.
;
; Input:	HL = where the line begins
;		A  = its segment index
;		B  = non-zero if the line carries a label, which with
;		     the byte count decides whether the listing shows
;		     an address at all
; Output: (line_address), (line_segment), (line_source_kind), (line_has_label),
; (line_calls_macro) = 0
;		and (emitted_count) = 0
; Modifies:	AF, HL

emit_line_start:
		ld	(line_address),hl
		ld	(line_segment),a
		ld	a,b
		ld	(line_has_label),a
					; DID IT CARRY A LABEL? M80 shows an
		xor	a		;   address for a line with one, or
		ld	(line_calls_macro),a
					;   one that emitted - and nothing
					;   else. The driver sets
					;   line_calls_macro after this, on the
					;   macro-call path
		ld	hl,(source_top)	; AND WHERE THE LINE CAME FROM, now,
		ld	a,(hl)		;   while it still says this line's
		ld	(line_source_kind),a
					;   source. A macro call pushes its
		ld	hl,0		;   body before the call line is
		ld	(emitted_count),hl
					;   listed, so asking later would
		ret			;   call a file line an expansion

; emit_line_skipped - this line is inside a branch that is not taken.
;
;   IT NAMES NO PLACE. emit_line_start is told the label length before
;   cond_line has run, because the listing wants the line's starting
;   address recorded before any directive can move the counter - so a
;   skipped line arrives here already classified as one that names a
;   place, and the classification has to be withdrawn rather than
;   delayed.
;
;   emitted_count is already 0 and no emitter will run, so clearing
;   line_has_label is the whole of it: build_columns.start then leaves the
;   column blank, which is what M80 does. Checked against M80 on 2026-09-29 - a
;   label and an EQU inside a false branch both list with nothing in the
;   address column, and neither reaches the symbol table.
;
; Input:	nothing
; Output:	(line_has_label) = 0
; Modifies:	AF

emit_line_skipped:
		xor	a
		ld	(line_has_label),a
		ret

; emit_show_value - the address column shows a VALUE rather than a place.
;
;   EQU and DEFL name a value, and M80 puts it where the address would
;   go. It overwrites what emit_line_start recorded at the top of the line,
;   which is all this takes - and THE RELOCATION MARK FALLS OUT, since
;   that is built from the type: a space for an absolute value, "'" for
;   one relative to a segment, decided by nothing that is written here.
;
; Input:	HL = the value
;		A  = its type (value_type)
; Output:	the listing's address column is that value
; Modifies:	nothing

emit_show_value:
		ld	(line_address),hl
		ld	(line_segment),a
		ret

; emit_byte - one byte on its way out. THE SINK.
;
;   Past EMIT_MAX it keeps counting and stops storing. The count is what
;   location_counter and the cross-check use, so it must never be capped; the
;   buffer is only what the listing prints, so losing its tail costs a
;   cosmetic column on a line nobody writes.
;
; Input:	A = the byte
; Output:	it is counted, and stored if there is room
; Modifies:	NOTHING - the pop af puts the flags back too, which
;		is worth having in a routine every encoder calls
;		between one half of an opcode and the other

emit_byte:	push	hl
		push	de
		push	af
		ld	hl,(emitted_count)
		ld	de,EMIT_MAX
		or	a
		sbc	hl,de
		jr	nc,emit_byte.counted_only
					; full: count it and no more
		ld	hl,(emitted_count)
		ld	de,emitted_bytes
		add	hl,de
		pop	af
		ld	(hl),a
		push	af
emit_byte.counted_only:
		ld	hl,(emitted_count)
		inc	hl
		ld	(emitted_count),hl
		pop	af
		pop	de
		pop	hl
		ret

; emit_word - a word, low byte first, which is the Z80's order and the one
;   every 16-bit operand and every DW uses.
;
; Input:	HL = the word
; Output:	two bytes out
; Modifies:	AF

emit_word:	ld	a,l
		call	emit_byte
		ld	a,h
		jp	emit_byte

; emit_expr_byte - the expression at DE, as ONE byte.
;
;   ON PASS 1 IT DOES NOT LOOK AT THE TEXT. It emits a zero and counts
;   it, because the length of a line never depends on what an expression
;   is worth and nothing reads pass 1's bytes. Evaluating here would
;   report an undefined symbol for "db later" - a forward reference,
;   which is the whole reason there are two passes. TESTS\EMFWD.AS.
;
; Input:	DE -> the text
;		A  = how long it is
; Output:	one byte out
; Modifies:	AF, BC, DE, HL

emit_expr_byte:	ld	c,a		; the length, across the pass test
		ld	a,(pass_number)
		cp	2
		jr	z,emit_expr_byte.pass2
		xor	a
		jp	emit_byte	; pass 1: a byte worth nothing
emit_expr_byte.pass2:
		ld	a,c
		call	eval_expression
		ld	a,(value_type)
		cp	SY_ABS
		jp	nz,error_relocation
					; ONE byte cannot hold a value the
					;   linker still has to add to. M80
					;   refuses it too; "db low lab" is
					;   how you say what you meant
		ld	a,l
		jp	emit_byte

; emit_expr_word - the same, as TWO bytes.
;
;   No test on the type here, and that is deliberate: two bytes CAN hold
;   a relocatable or external value, because what goes in the hole is
;   the addend and the linker adds the rest. The record that tells it to
;   is the object writer's; this leaves the right bytes in the right
;   and says so in emit-design.md 7.
;
; Input:	DE -> the text
;		A  = how long it is
; Output:	two bytes out
; Modifies:	AF, BC, DE, HL

emit_expr_word:	ld	c,a
		ld	a,(pass_number)
		cp	2
		jr	z,emit_expr_word.pass2
		ld	hl,0
		jp	emit_word	; pass 1: two bytes worth nothing
emit_expr_word.pass2:
		ld	a,c
		call	eval_expression
		push	hl		; the ADDEND goes in the hole. What
		ld	hl,(emitted_count)
					;   has to be added to it is the
		ld	de,(line_address)
					;   business, and it needs to know
		add	hl,de		;   where the hole is - which is
		call	object_fixup	;   exactly here, before the word
		pop	hl		;   goes out
		jp	emit_word

; emit_saved_byte, emit_saved_word - the expression the parser remembered, as
; one byte or as two.
;
;   The wrappers that were expected with the first instruction
;   handler, over the emit_expr_byte and emit_expr_word that take their text in
;   registers. DB, DW and DC keep using those directly: walk_data_items knows
;   where each item begins and ends at the moment it emits it, and
;   never needs a slot.
;
; Input:	nothing
; Output:	one byte / two
; Modifies:	AF, BC, DE, HL

emit_saved_byte:
		call	expression_text
		jp	emit_expr_byte

emit_saved_word:
		call	expression_text
		jp	emit_expr_word

; saved_value - the remembered expression's VALUE.
;
;   For an expression that goes into an OPCODE rather than a byte of
;   its own: RST's operand, IM's, and BIT's number.
;
;   ZERO ON PASS 1, without evaluating - and the zero is not arbitrary.
;   "rst 0" is an instruction, "im 0" is an instruction, and a
;   displacement of 0 is in range, so it passes every check the
;   will hand it. That is what lets "rst later" work with later
;   defined below: a placeholder that could FAIL a pass-2 check would
;   turn every forward reference into a false error, which is the
;   whole thing emit_expr_byte was built to avoid.
;
; Input:	nothing
; Output:	HL = the value, or 0 on pass 1
; Modifies:	AF, BC, DE, HL

saved_value:	ld	a,(pass_number)
		cp	2
		jr	z,saved_value.pass2
		ld	hl,0
		ret
saved_value.pass2:
		call	expression_text
		jp	eval_expression

; emit_displacement - the displacement the last indexed operand carried, as one
;   SIGNED byte.
;
;   "(ix)" is "(ix+0)": the byte goes out whether the source wrote one
;   or not, because every indexed encoding has room for it. JP is the
;   one exception, and "jp (ix+5)" is refused rather than making this
;   routine care.
;
;   THE RANGE CHECK IS HERE and nowhere else, which is why it covers
;   every indexed instruction in the program from the first one that
;   encodes: they all reach their displacement through this routine.
;
; Input:	nothing
; Output:	one byte
; Modifies:	AF, BC, DE, HL

emit_displacement:
		call	displacement_text
		or	a
		jr	nz,emit_displacement.written
		xor	a
		jp	emit_byte	; none written: "(ix)" is "(ix+0)"
emit_displacement.written:
		ld	c,a		; the length, across the pass test
		ld	a,(pass_number)
		cp	2
		jr	z,emit_displacement.pass2
		xor	a
		jp	emit_byte	; pass 1: a byte worth nothing
emit_displacement.pass2:
		ld	a,c
		call	eval_expression
		ld	a,(value_type)
		cp	SY_ABS
		jp	nz,error_relocation
					; a displacement the linker would have
					;   to adjust is not a thing
		ld	a,h		; a signed byte is 0000-007F or
		or	a		;   FF80-FFFF and nothing else
		jr	z,emit_displacement.positive
		inc	a
		jp	nz,error_bad_displacement
		ld	a,l
		and	080h
		jp	z,error_bad_displacement
		jr	emit_displacement.store
emit_displacement.positive:
		ld	a,l
		and	080h
		jp	nz,error_bad_displacement
emit_displacement.store:
		ld	a,l
		jp	emit_byte

; emit_relative - the expression the parser remembered, as a RELATIVE
;   displacement: one signed byte.
;
;   THE ONLY PLACE IN THE PROGRAM THAT SUBTRACTS ONE ADDRESS FROM
;   ANOTHER. The target is measured from the address AFTER the
;   instruction, and the opcode has already gone out when this is
;   called, so that address is line_address + emitted_count + 1: where the line
;   began, plus what it has emitted, plus the byte about to go out.
;   Nothing is passed in and location_counter is not read.
;
;   A displacement between two CONTRIBUTIONS is not a number. The linker
;   places them independently, so the distance is unknown here, and
;   there is no relocation record that can fix up a displacement later -
;   two bytes can carry an addend, one relative byte cannot. The target
;   must be absolute or in the same contribution as the instruction,
;   which is value_type against line_segment: SYMBOL_TYPE holds a segment's
;   index and line_segment is the same space.
;
;   PASS 1 EMITS A ZERO without reading the text, as emit_expr_byte and
;   emit_displacement do. No value changes a length, and zero is in range -
;   which is what lets "jr later" work with LATER defined below the line that
;   jumps to it.
;
; Input:	nothing (the remembered expression, line_address, line_segment,
;		emitted_count)
; Output:	one byte
; Modifies:	AF, BC, DE, HL

emit_relative:	ld	a,(pass_number)
		cp	2
		jr	z,emit_relative.pass2
		xor	a
		jp	emit_byte	; pass 1: a byte worth nothing
emit_relative.pass2:
		call	expression_text	; DE -> the text, A = how long
		or	a
		jp	z,error_not_a_form	; a JR with nothing after it
		call	eval_expression	; HL = the target
		ld	a,(value_type)
		cp	SY_ABS
		jr	z,emit_relative.subtract
					; absolute: always subtractable
		ld	c,a
		ld	a,(line_segment)
		cp	c
		jp	nz,error_relocation
					; another contribution: the distance
					;   is not known here and no record
					;   can fix a displacement later
emit_relative.subtract:
		ld	de,(line_address)
					; where the NEXT instruction starts:
		push	hl		;   this line, plus what it has
		ld	hl,(emitted_count)	;   emitted, plus this byte
		inc	hl
		add	hl,de
		ex	de,hl
		pop	hl
		or	a
		sbc	hl,de		; the target, less that
		ld	a,h		; a signed byte is 0000-007F or
		or	a		;   FF80-FFFF and nothing else
		jr	z,emit_relative.positive
		inc	a
		jp	nz,error_jump_too_far
		ld	a,l
		and	080h
		jp	z,error_jump_too_far
		jr	emit_relative.store
emit_relative.positive:
		ld	a,l
		and	080h
		jp	nz,error_jump_too_far
emit_relative.store:
		ld	a,l
		jp	emit_byte

; emit_opcode - an opcode in the ORDINARY shape: the prefix an index
;   register forces goes out FIRST, the opcode next, the displacement
;   LAST.
;
;   This is what clsxtra becomes. clsxtra added those same bytes to a
;   LENGTH and had no opinion about their order, which is the whole
;   difference between measuring and emitting - and it is why one
;   routine can replace it at every site rather than every handler
;   restating the rule.
;
;   THE CB GROUP DOES NOT COME THROUGH HERE. Its order is prefix, CB,
;   displacement, opcode - the only place in the instruction set where
;   the operand byte precedes the opcode. The
;   two classes that cannot call this are exactly the two that are
;   different, which is the contrast being drawn.
;
; Input:	A = the opcode
; Output:	one to three bytes
; Modifies:	AF, BC, DE, HL

emit_opcode:	ld	c,a
		ld	a,(operand_prefix)
		or	a
		call	nz,emit_byte	; DD or FD, if the operand forced one
		ld	a,c
		call	emit_byte
		ld	a,(operand_kind)
		cp	OPERAND_INDEXED
		ret	nz		; not indexed: nothing follows
		jp	emit_displacement

; emit_high_bit_last - set bit 7 of the last byte emitted.
;
;   DC and nothing else: 2.6.5 says the last character of the string
;   carries the high bit, and it is the last one only once the whole
;   string has gone out. If the buffer truncated, the byte is not there
;   to set - which cannot happen for a DC, because a DC is ONE string
;   and a string is at most the operand field.
;
; Input:	nothing
; Output:	the last byte in emitted_bytes has bit 7 set
; Modifies:	AF, DE, HL

emit_high_bit_last:
		ld	hl,(emitted_count)
		ld	a,h
		or	l
		ret	z		; nothing emitted: nothing to set
		ld	de,EMIT_MAX+1
		or	a
		sbc	hl,de
		ret	nc		; past the buffer: not there to set
		ld	hl,(emitted_count)
		dec	hl
		ld	de,emitted_bytes
		add	hl,de
		ld	a,(hl)
		or	080h
		ld	(hl),a
		ret

; write_output - write A bytes starting at DE, exactly as they are.
;   No terminator, no CR+LF. Asking for 0 bytes writes nothing at all,
;   which is what makes an empty field print as "[]".
;
; Input:	DE -> the bytes
;		A   = how many
; Output:	they are written
; Modifies:	AF, BC, DE, HL - EVERYTHING. MSX-DOS's _WRITE gives
;		back A and HL and keeps nothing else, DE included. This
;		line said "AF, BC, HL", and write_line believed it:
;		it kept its read pointer in DE across a write and read
;		the rest of every line out of whatever DOS left there

write_output:	or	a
		ret	z		; nothing to write
		ld	l,a
		ld	h,0		; HL = how many bytes
		ld	a,(output_handle)
		ld	b,a		; B = the handle
		system	_WRITE		; -> A = the error
		or	a
		ret	z
		jp	error_write_failed	; disk full, or write-protected

; write_line - write one line, followed by CR+LF, to wherever output goes.
;
;   The CR and LF are written over the line's own zero terminator, which
;   is why line_buffer has two spare bytes at the end. One MSX-DOS call per
;   line, and never a request to write zero bytes.
;
; Input:	DE -> the line, zero-terminated
;		A = its length
; Output:	the line is written
; Modifies:	AF, BC, DE, HL

write_line:	ld	(line_left),a	; how many characters are left
		ld	a,c
		ld	(line_column),a	;   and which column we are at
		ld	h,d		; AND WHERE TO READ, IN RAM: _WRITE
		ld	l,e		;   does not give DE back, so nothing
		ld	(line_read_at),hl
					;   may hold a pointer across a write
write_line.scan:
		ld	a,(line_left)
		or	a
		jr	z,write_line.line_end
		ld	de,(line_read_at)
		ld	a,(de)
		cp	CHR_TAB
		jr	z,write_line.tab

		ld	h,d		; a run of ordinary characters: how
		ld	l,e		;   far does it go? HL walks, DE
		ld	b,0		;   stays at its start, for the write
		ld	a,(line_left)
		ld	c,a
write_line.run:	ld	a,(hl)
		cp	CHR_TAB
		jr	z,write_line.run_end
		inc	hl
		inc	b
		dec	c
		jr	nz,write_line.run
write_line.run_end:
		ld	a,b
		ld	(line_run),a
				; write_output keeps NOTHING: AF, BC, DE
		call	write_output	;   and HL are all gone afterwards
		ld	a,(line_run)
		ld	c,a
		ld	a,(line_column)	; the column and the count move on
		add	a,c		;   by the run
		ld	(line_column),a
		ld	a,(line_left)
		sub	c
		ld	(line_left),a
		ld	hl,(line_read_at)	; and so does the read pointer
		ld	d,0
		ld	e,c
		add	hl,de
		ld	(line_read_at),hl
		jr	write_line.scan

write_line.tab:	ld	hl,(line_read_at)	; over the tab itself
		inc	hl
		ld	(line_read_at),hl
		ld	hl,line_left
		dec	(hl)
		ld	a,(line_column)
		ld	c,a		; where we are now
		or	7		; and the NEXT stop, which is a
		inc	a		;   different column even when we are
		ld	(line_column),a	;   already on one: a tab moves
		sub	c		; how many spaces that is, 1 to 8
		ld	de,eight_spaces
		call	write_output
		jr	write_line.scan

write_line.line_end:
		ld	de,crlf_bytes	; AND THE LINE ENDS WITHOUT THE
		ld	a,2		;   BUFFER BEING TOUCHED. It used to
		jp	write_output	;   take the CR and LF over the zero
					;   terminator, which is why
					;   line_buffer has two spare bytes -
					;   and why collect_macro, which lists
					;   a line before split_line reads it,
					;   was handed one with no end

crlf_bytes:	defb	CHR_CR,CHR_LF
eight_spaces:	defb	"        "	; eight, the most a tab can need
form_feed_char:	defb	CHR_FF		; the page break itself
page_dash:	defb	"-"
page_symbol_mark:
		defb	"S"		; the last page's number
page_label:	defb	"PAGE    "	; and the four spaces after it
heading_macros:	defb	"Macros:"
heading_symbols:
		defb	"Symbols:"

; THE NAME IN THE HEADER IS OURS. M80 writes "MSX.M-80 2.00" there and
; Tatara writes this: the columns are M80's, the text is not, because a
; listing should say what made it.


month_names:	defb	"Jan",0,"Feb",0,"Mar",0,"Apr",0
		defb	"May",0,"Jun",0,"Jul",0,"Aug",0
		defb	"Sep",0,"Oct",0,"Nov",0,"Dec",0

; list_line - list one source line, if anything is listening.
;
;   THE DRIVER'S TAIL, MADE CALLABLE. It was the end of main.emit_line until
;   it moved because collect_macro lists the lines it collects and
;   has to do it the same way: the modes, the three reasons to want
;   text, the columns, the continuation lines. One copy.
;
;   It tests pass_number itself, so a caller in the middle of pass 1 needs
;   no guard of its own.
;
; Input:	DE -> the text
;		A  = its length
; Output:	nothing, or a listing line
; Modifies:	AF, BC, DE, HL

list_line:	ld	(list_text_at),de
		ld	(list_text_length),a
		ld	a,(pass_number)
		cp	2
		ret	nz
		ld	a,(listing_on)	; .XLIST
		or	a
		ret	z
		ld	a,(line_source_kind)
					; out of a macro? Then how much of
		cp	SOURCE_IS_MACRO	;   the expansion shows is the mode
		jr	nz,list_line.wanted
		ld	a,(expansion_mode)
		cp	LST_SALL
		ret	z
		cp	LST_XALL
		jr	nz,list_line.wanted
		ld	hl,(emitted_count)
					; .XALL: only the lines that emitted
		ld	a,h
		or	l
		ret	z
list_line.wanted:
		ld	a,(opt_screen)	; /P, /L, or a listing file to put it
		ld	hl,opt_listing	;   in: any of the three asks for the
		or	(hl)		;   text, and with none of them an
		ld	hl,listing_name	;   assembly is silent but for its
		or	(hl)		;   errors and its summary line
		ret	z
		ld	a,(lines_left)	; room on this page? The counter
		or	a		;   starts at zero, so the first line
		call	z,start_page	;   of a listing writes a header and
		ld	hl,lines_left	;   no form feed
		dec	(hl)
		ld	a,(opt_listing)	; /L: the address and the bytes go in
		or	a		;   front, and the source line follows
		ld	c,0		;   unchanged. WITHOUT a prefix the
		jr	z,list_line.text	;   text starts at column zero
		call	build_columns
		ld	c,a		; WITH one, it starts where the prefix
		push	bc		;   ends - and that is what the tab
		call	write_output	;   stops are counted from
		pop	bc
list_line.text:	ld	de,(list_text_at)
		ld	a,(list_text_length)
		call	write_line
		ld	a,(opt_listing)
				; more than COLUMN_BYTES bytes? They wrap,
		or	a		;   one column-wide line each, with no
		jr	z,list_line.done	;   source text
list_line.more:	call	build_more_columns
		jr	c,list_line.done
		ld	c,0		; a built column, and no tabs in it
		call	write_line
		jr	list_line.more

; The line is written. Did a PAGE directive on it ask for a break? Then
; it happens HERE, after the line and not before it: the directive
; belongs to the page it was written on. The next line finds lines_left
; at zero and writes a header, exactly as the first line of a listing
; does.

list_line.done:	ld	a,(page_break_due)
		or	a
		ret	z
		xor	a
		ld	(page_break_due),a
		ld	(lines_left),a	; A SUBPAGE, not a main page: M80
		ret			;   answers 1-1, which PAGEDIR.AS
					;   asked it. A FORM FEED is what moves
					;   the main number -
					;   listing_form_feed, 090 - and NOT
					;   title, the guess written here until
					;   M80PGNUM.MAC put one mid-file and
					;   nothing happened

; listing_init - the listing, back to where a pass starts it.
;
;   PER PASS, from main.start_pass, for the same reason segment_reset and
;   cond_init are: a .XLIST on pass 1 must not silence pass 2. It also sets the
;   page number, which nothing else did - the first listing came out headed
;   PAGE 0.
;
; Input:	nothing
; Output:	listing on, .XALL, page 1, and a page break due
; Modifies:	AF

listing_init:	ld	a,0ffh
		ld	(listing_on),a
		ld	a,LST_XALL
		ld	(expansion_mode),a
		ld	a,1
		ld	(page_number),a
		xor	a
		ld	(subpage_number),a
		ld	(lines_left),a	; zero: the first line writes a
		ld	(subtitle_text),a	;   header, and no form feed
		ld	(page_break_due),a
					; THE SUBTITLE AND NOT THE TITLE:
		ld	a,PAGE_LENGTH	;   M80 keeps a title from pass 1
		ld	(page_body_lines),a
					;   and does not keep a subtitle,
		ret			;   which TITLLST.PRN shows

; start_page - start a page: the form feed, the header, two blank lines.
;
;   M80'S COLUMNS, measured off its own LONGLST.PRN: eight spaces, the
;   name and version, three spaces, the date, seven spaces, "PAGE",
;   four spaces, the number. THE NAME IS OURS - the columns are M80's
;   and the text is not, because a listing should say what made it.
;
;   Written in pieces. The header is 49 characters and column_buffer is 40,
;   and a line does not need a buffer.
;
; Input:	nothing
; Output:	the page is started, lines_left = PAGE_LENGTH
; Modifies:	AF, BC, DE, HL

start_page:	xor	a
		ld	(form_feed_columns),a
		ld	a,(subpage_number)
					; page 1 subpage 0 is the first page
		or	a		;   of all, and the only one with no
		jr	nz,start_page.form_feed	;   form feed in front of it
		ld	a,(page_number)
		dec	a
		jr	z,start_page.header
start_page.form_feed:
		ld	a,2		; AND THE FORM FEED TAKES TWO COLUMNS
		ld	(form_feed_columns),a
					;   of the field below. Measured off
		ld	de,form_feed_char
					;   five M80 headers, and it is why
		ld	a,1		;   M80's own paged headers sit two
		call	write_output	;   to the left of its first one
start_page.header:
		ld	a,(title_text)	; THE ONE VARIABLE FIELD: the title,
		or	a		;   TWO SPACES, and then on to the
		jr	z,start_page.no_title
					;   next tab stop - staying put if
		ld	de,title_text+1	;   it is already on one, which is
		call	write_output	;   why a title of 14 gives 16 and
start_page.no_title:
		ld	hl,form_feed_columns	;   one of 12 gives 16 as well.
		ld	a,(title_text)	;   AND THE FORM FEED'S TWO COLUMNS
		add	a,(hl)		;   COUNT TOWARD THAT STOP without
		add	a,2+7		;   being printed, so they go into
		and	0f8h		;   the sum and come back out of it
		sub	(hl)
		ld	hl,title_text
		sub	(hl)
		call	write_spaces
				; EMITSP AND NOT eight_spaces: the pad runs
					;   to nine and eight_spaces is eight
					;   long, so a title of fourteen wrote
					;   the two bytes after it into the
					;   header
		; "Tatara v1.0.0" - THE SAME BYTES the banner prints, in a
		;   field as wide as M80's own name and version. See
		;   msg_version_label in cmdline.as
		ld	de,msg_version_label
		ld	a,NAME_FIELD_WIDTH
		call	write_output
		ld	de,eight_spaces
		ld	a,3
		call	write_output
		call	listing_date	; DE -> nine bytes, dd-Mmm-yy
		ld	a,9
		call	write_output
		ld	de,eight_spaces
		ld	a,7
		call	write_output
		ld	de,page_label	; "PAGE" and four more spaces
		ld	a,8
		call	write_output

		ld	a,(subpage_number)
					; the number: "S" for the last page,
		cp	0ffh		;   "n" for the first, "n-m" after
		jr	nz,start_page.number	;   that
		ld	de,page_symbol_mark
		ld	a,1
		call	write_output
		jr	start_page.header_end
start_page.number:
		ld	a,(page_number)
		ld	l,a
		ld	h,0
		ld	de,number_buffer
		call	build_decimal	; A = how many digits
		ld	de,number_buffer
		call	write_output
		ld	a,(subpage_number)
		or	a
		jr	z,start_page.header_end
		ld	de,page_dash
		ld	a,1
		call	write_output
		ld	a,(subpage_number)
		ld	l,a
		ld	h,0
		ld	de,number_buffer
		call	build_decimal
		ld	de,number_buffer
		call	write_output

start_page.header_end:
		call	write_crlf	; the header's own line ending
		ld	a,(subtitle_text)
					; then the subtitle's line, which is
		or	a		;   blank unless a SUBTTL was in force
		jr	z,start_page.no_subtitle
					;   when this page STARTED - so a
		ld	de,subtitle_text+1
					;   SUBTTL never shows on the page it
		call	write_output	;   is written on
start_page.no_subtitle:
		call	write_crlf
		call	write_crlf	;   and the blank one under that
		ld	a,(subpage_number)
					; the next overflow is a subpage on
		inc	a		;   from this one
		ld	(subpage_number),a
		ld	a,(page_body_lines)
		ld	(lines_left),a
		ret

; write_crlf - one line ending.
;
; Input:	nothing
; Output:	two bytes
; Modifies:	AF, BC, DE, HL

write_crlf:	ld	de,crlf_bytes
		ld	a,2
		jp	write_output

; set_title - remember a TITLE or a SUBTTL.
;
;   The buffer is a length byte and then the text, which is the shape
;   module_name wants and one byte cheaper than a separate count.
;
; Input:	DE -> the text
;		A  = its length
;		C  = 0 for the title, 1 for the subtitle
; Output:	the buffer holds it, cut to TITLE_MAX
; Modifies:	AF, BC, DE, HL

set_title:	ld	b,a		; which of the two buffers
		ld	hl,title_text
		ld	a,c
		or	a
		jr	z,set_title.buffer
		ld	hl,subtitle_text
set_title.buffer:
		ld	a,b		; and how much of the text fits
		cp	TITLE_MAX+1
		jr	c,set_title.length
		ld	a,TITLE_MAX
set_title.length:
		ld	(hl),a
		or	a
		ret	z		; "title" with nothing after it
		ld	c,a
		ld	b,0
		inc	hl
		ex	de,hl		; HL -> the text, DE -> the buffer
		ldir
		ret

; listing_eject - the PAGE directive.
;
;   IT DOES NOT BREAK THE PAGE. It leaves a note, and list_line.done reads
;   it after the PAGE line itself has been listed - the directive
;   belongs to the page it was written on.
;
; Input:	nothing
; Output:	the note is left
; Modifies:	AF

listing_eject:	ld	a,0ffh
		ld	(page_break_due),a
		ret

; listing_form_feed - a form feed in the source.
;
;   IT BREAKS THE PAGE AT ONCE, which is the opposite of listing_eject
;   above, and M80 is the reason for both: the PAGE directive belongs
;   to the page it was written on and is listed there, while a form
;   feed's own line is printed EMPTY AT THE TOP OF THE NEW PAGE -
;   m80pgnum.prn shows one of each, two pages apart.
;
;   AND IT MOVES THE MAIN NUMBER. That is the question list_line.done used
;   to leave open: PAGE gives 2-1 and never touches the first number,
;   and the guess written there was that TITLE moved it. It does not -
;   M80PGNUM.MAC has a TITLE in the middle of the file and it starts no
;   page at all. A form feed does, and nothing else we have seen does.
;
;   lines_left goes to zero rather than a page being written here: the
;   next line listed finds no room and opens the page itself, which is
;   the same path the first line of a listing takes.
;
; Input:	nothing
; Output:	the next line listed starts a new main page
; Modifies:	AF, HL

listing_form_feed:
		ld	hl,page_number
		inc	(hl)
		xor	a
		ld	(subpage_number),a
					; a MAIN page, not a subpage: the
		ld	(lines_left),a	;   numbering starts again under it
		ret

; set_page_length - PAGE expr: how long a page is.
;
;   M80 takes 10 to 255 and marks anything else as a fatal error,
;   which is what PAGEDIR.AS asked it. THE COUNT IS THE WHOLE PAGE,
;   four of whose lines are furniture: "page 12" gives eight lines of
;   text, measured.
;
; Input:	HL = the count
; Output:	page_body_lines (error_bad_page_length does not return)
; Modifies:	AF

set_page_length:
		ld	a,h
		or	a
		jp	nz,error_bad_page_length
		ld	a,l
		cp	10
		jp	c,error_bad_page_length
		sub	4		; THE COUNT IS THE WHOLE PAGE and
		ld	(page_body_lines),a
				;   page_body_lines is its body: the form
		ret			;   feed, the header and the two
					;   blank lines are the other four

; listing_date - the date, dd-Mmm-yy, fetched once.
;
;   It cannot change during an assembly, so the first header asks
;   MSX-DOS and every later one writes the same nine bytes.
;
; Input:	nothing
; Output:	DE -> nine characters
; Modifies:	AF, BC, DE, HL

listing_date:	ld	a,(date_ready)
		or	a
		jr	nz,listing_date.ready
		system	_GDATE		; -> HL = year, D = month, E = day
		ld	a,d		; ALL THREE INTO RAM FIRST. Everything
		ld	(date_month),a	;   below wants DE or HL for its own
		ld	a,e		;   purposes, and the first "ld de,"
		ld	(date_day),a	;   would take the month with it
		ld	(date_year),hl

		ld	a,(date_day)	; the day, two digits
		ld	de,date_buffer
		call	two_digits
		ld	a,"-"
		ld	(date_buffer+2),a
		ld	(date_buffer+6),a

		ld	hl,(date_year)	; the year's last two digits: MSX-DOS
		ld	de,1900		;   answers 1980 to 2079, so take
		or	a		;   1900 off and then hundreds until
		sbc	hl,de		;   what is left is under one
listing_date.century:
		ld	a,h
		or	a
		jr	nz,listing_date.century_sub
		ld	a,l
		cp	100
		jr	c,listing_date.year
listing_date.century_sub:
		ld	de,100
		or	a
		sbc	hl,de
		jr	listing_date.century
listing_date.year:
		ld	a,l
		ld	de,date_buffer+7
		call	two_digits

		ld	a,(date_month)	; the month's name, three letters
		dec	a		;   out of the table
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl		; three would need a multiply, so
		ld	de,month_names	;   the table is four bytes an entry
		add	hl,de		;   and the fourth is never written
		ld	de,date_buffer+3
		ld	bc,3
		ldir
		ld	a,0ffh
		ld	(date_ready),a
listing_date.ready:
		ld	de,date_buffer
		ret

; two_digits - A as two decimal digits at DE.
;
; Input:	A = 0 to 99
;		DE -> where
; Output:	two bytes written, DE unchanged
; Modifies:	AF, BC, HL

two_digits:	ld	h,d
		ld	l,e
		ld	b,"0"-1
two_digits.tens:
		inc	b		; tens by subtraction: no divide, and
		sub	10		;   the number is under 100
		jr	nc,two_digits.tens
		add	a,10
		ld	(hl),b
		inc	hl
		add	a,"0"
		ld	(hl),a
		ret

; list_last_page - the last page: Macros: and Symbols:, M80's layout.
;
;   CALLED FROM main.finish, before close_output. ONLY WHEN A LISTING FILE
;   WAS NAMED - not for /P. M80 puts this page in its .PRN because the
;   .PRN is the listing; Tatara keeps the screen clean and says so.
;
; Input:	nothing
; Output:	the page, or nothing
; Modifies:	AF, BC, DE, HL, IX

		; A LISTING FILE, NOT /P: a .prn is a document and the symbols
		;   belong in it, where screen output is watched going past and
		;   would be worse for ending in a form feed and a dump
list_last_page:	ld	a,(listing_name)
		or	a
		ret	z
		xor	a		; AND NO SUBTITLE: M80's own S page
		ld	(subtitle_text),a
					;   has none, whatever was in force
		ld	a,0ffh		; the number is "S", and start_page
		ld	(subpage_number),a
					;   writes the form feed before it
		call	start_page
		ld	de,heading_macros	; "Macros:"
		ld	a,7
		call	write_output
		call	write_crlf
		call	list_macros
		call	write_crlf	; one blank, with macros or without
		ld	de,heading_symbols	; "Symbols:"
		ld	a,8
		call	write_output
		call	write_crlf
		jp	list_symbols

; write_spaces - A spaces, wherever the listing goes.
;
;   The eight-space run write_line expands a tab with, reused: any count
;   is that run written until it has been enough. It exists because
;   list_symbols pads a name to sixteen columns and eight_spaces is this
;   module's, not something to hand out.
;
; Input:	A = how many, 0 to 255
; Output:	they are written
; Modifies:	AF, BC, DE, HL

write_spaces:	or	a
		ret	z
write_spaces.loop:
		cp	9
		jr	c,write_spaces.last
		push	af
		ld	de,eight_spaces
		ld	a,8
		call	write_output
		pop	af
		sub	8
		jr	nz,write_spaces.loop
		ret
write_spaces.last:
		ld	de,eight_spaces
		jp	write_output

; write_char - one character, wherever the listing goes.
;
;   A name lives in the mapper and cannot be handed to _WRITE, so the
;   walks that print one re-map the record and send a character at a
;   time. dump_symbols has done this; this is the same thing
;   writing to the listing rather than to the screen.
;
; Input:	A = the character
; Output:	it is written
; Modifies:	AF, BC, DE, HL

write_char:	ld	(one_char),a
		ld	de,one_char
		ld	a,1
		jp	write_output

; list_body_line - the same, for a line the driver never sees.
;
;   A MACRO, REPT, IRP or IRPC line, or a line of a body: collect_macro reads
;   those itself and the driver's loop never gets them. NO LABEL AND NO
;   ADDRESS - "byte" in "byte macro n" sits in the label field and
;   names nowhere, and M80 leaves the column blank. the rule does the
;   rest once the flag is off.
;
; Input:	DE -> the text
;		A  = its length
; Output:	nothing, or a listing line
; Modifies:	AF, BC, DE, HL

list_body_line:	ld	c,a	; the length: emit_line_start leaves BC alone
		ld	a,(opt_fields)	; /F REPLACES THE LISTING WITH THE
		or	a	;   FIELD DUMP, and main.emit_line refuses
		ret	nz		;   list_line for that reason. THIS IS
					;   THE OTHER WAY IN: the MACRO line,
					;   every line of a body as
					;   collect_macro reads it, and REPT,
					;   IRP and IRPC. One guard here rather
					;   than five at the callers - issue
					;   #20
		ld	b,0		; no label, so no address column
		ld	hl,0
		xor	a		; and no segment: nothing shows either
		call	emit_line_start	;   way, and emitted_count goes to zero
		ld	a,c
		jp	list_line	; the line's zero terminator went
					;   back here, because write_line wrote
					;   CR+LF over it. Now it writes those
					;   two bytes on their own and the
					;   buffer is not touched at all

; build_columns - build the listing's two columns for the FIRST eight bytes.
;
;   The column is "  ", four hex digits, the relocation mark, three
;   spaces, then three characters a byte. A line that emitted more than
;   eight WRAPS: build_more_columns below builds the next eight, and the caller
;   keeps asking until it says there are none left.
;
; Input: nothing (line_address, line_segment, emitted_count, emitted_bytes)
; Output:	DE -> the text
;		A  = how long it is
; Modifies:	AF, BC, DE, HL

build_columns:	ld	hl,0
		ld	(next_byte_shown),hl
					; this line's bytes start at zero
		jr	build_columns.start

; build_more_columns - the same column for the next eight bytes of the same
; line.
;
;   A "+" was printed here and stopped, on the grounds that the listing
;   would wrap them. Nothing emitted more than eight bytes on one line
;   until tatara.as assembled its own message tables - and a listing
;   that silently drops bytes is worse than no listing, because the
;   only reason to read one is to check what was generated.
;
;   Each answer is a whole listing line: a real address of its own,
;   the same relocation mark, and no source text, because it is still
;   one source line.
;
; Input:	nothing (next_byte_shown)
; Output:	CY set   = there were none left, and nothing was built
;		CY clear = DE -> the text, A = how long it is
; Modifies:	AF, BC, DE, HL

build_more_columns:
		call	bytes_kept	; how many bytes there are to show
		ld	bc,(next_byte_shown)
		or	a
		sbc	hl,bc		; still some past the ones shown?
		jr	nz,build_columns.start
		scf
		ret			; no: this line is finished

build_columns.start:
		ld	de,column_buffer
		ld	a,(line_has_label)
					; A LABEL OR BYTES, OR NO ADDRESS AT
		or	a		;   ALL. M80 leaves the column blank
		jr	nz,build_columns.address
					;   on a comment, on END, on a
		ld	hl,(emitted_count)
					;   listing control - on any line that
		ld	a,h		;   neither names a place nor puts
		or	l		;   anything in one
		jr	nz,build_columns.address
		ld	b,10		; the whole column: 2 + 4 + 1 + 3
		call	pad_spaces
		jr	build_columns.bytes

build_columns.address:
		ld	b,2
		call	pad_spaces
		ld	hl,(line_address)
					; THIS chunk's address: where the line
		ld	bc,(next_byte_shown)
					;   began, plus the bytes already shown
		add	hl,bc
		call	build_hex_word	; four digits, DE moves on
		ld	a,(line_segment)
		or	a		; SY_ABS is 0 and must stay 0
		ld	a," "
		jr	z,build_columns.absolute
		ld	a,"'"		; M80's mark for an address the
build_columns.absolute:
		ld	(de),a		;   linker has still to place
		inc	de
		ld	b,3
		call	pad_spaces

build_columns.bytes:

		call	bytes_kept	; how many are left to show: what is
		ld	bc,(next_byte_shown)
					;   in the buffer, less what is done
		or	a
		sbc	hl,bc
		ld	bc,COLUMN_BYTES
				; a column holds COLUMN_BYTES of them, and
		or	a		;   this chunk shows that many or all
		sbc	hl,bc		;   that remain, whichever is fewer
		jr	nc,build_columns.chunk
		add	hl,bc
		ld	b,h
		ld	c,l
build_columns.chunk:
		push	bc		; how many, for next_byte_shown below
		push	de		; DE is the OUTPUT cursor throughout
		ld	hl,(next_byte_shown)
		ld	de,emitted_bytes
		add	hl,de		; HL -> this chunk's first byte
		pop	de
build_columns.next_byte:
		ld	a,b
		or	c
		jr	z,build_columns.advance
		ld	a,(hl)
		inc	hl
		call	build_hex_byte
		ld	a," "
		ld	(de),a
		inc	de
		dec	bc
		jr	build_columns.next_byte

build_columns.advance:
		pop	bc		; how many this chunk showed
		ld	hl,(next_byte_shown)
		add	hl,bc
		ld	(next_byte_shown),hl	; where the next one starts

; A "+" was printed here when a line emitted more than EMIT_MAX, meaning
; "there were more bytes than the buffer kept". That became an error
; instead - error_too_many_bytes - because the buffer IS the object file's
; content, and a lost tail is a wrong program rather than a short
; column. So the branch is gone, and the character is free for the
; meaning M80 gives it below.

build_columns.pad:
		ld	hl,column_buffer+COLUMN_WIDTH
		or	a
		sbc	hl,de		; HL = how many spaces are owed
		jr	z,build_columns.macro_mark
		jr	c,build_columns.macro_mark
					; already past: no padding
		ld	b,l		; COLUMN_WIDTH is well under 256
		call	pad_spaces

; M80 flags a line that came out of a macro expansion. The top line
; source says whether this one did - a file cannot expand anything -
; and the column is the last space before the source text.
;
; THE COLUMN IS M80'S, measured off its listing of MACPLUS.AS: 26, a
; column of its own rather than the last space before the source.

build_columns.macro_mark:
		ld	a,(line_source_kind)
					; where THIS line came from, from
		cp	SOURCE_IS_MACRO
				;   emit_line_start - not where the stack
					;   has got to by now
		jr	z,build_columns.plus
		ld	a,(line_calls_macro)
					; a call line under .SALL: M80 flags
		or	a		;   it, because it is standing in for
		jr	z,build_columns.done
					;   an expansion nobody asked to see.
		ld	a,(expansion_mode)
					;   Under .LALL and .XALL it does not
		cp	LST_SALL
		jr	nz,build_columns.done
build_columns.plus:
		ld	hl,column_buffer+COLUMN_PLUS
		ld	(hl),"+"
build_columns.done:
		ld	hl,column_buffer
		ex	de,hl		; DE -> column_buffer, HL = the cursor
		or	a
		sbc	hl,de		; HL = how long it came to
		ld	a,l
		or	a		; CY CLEAR: something was built
		ret

; bytes_kept - how many of this line's bytes are actually in emitted_bytes.
;
;   emitted_count counts every byte the line emitted; emitted_bytes holds the
;   first EMIT_MAX of them. The listing can only show what was kept.
;
; Input:	nothing
; Output:	HL = the smaller of emitted_count and EMIT_MAX
; Modifies:	AF, BC, HL

bytes_kept:	ld	hl,(emitted_count)
		ld	bc,EMIT_MAX
		or	a
		sbc	hl,bc
		jr	c,bytes_kept.all
					; fewer than the buffer holds: all
		ld	hl,EMIT_MAX	;   of them. Otherwise EMIT_MAX is
		ret			;   every one there is
bytes_kept.all:	add	hl,bc		; put emitted_count back
		ret

; pad_spaces - B spaces at DE.
;
; Input:	B = how many, DE -> where
; Output:	DE has moved on
; Modifies:	AF, B, DE

pad_spaces:	ld	a," "
		ld	(de),a
		inc	de
		djnz	pad_spaces
		ret

		dseg

emitted_count:	defs	2	; how many bytes this line emitted. A
				;   WORD: a DW can pass 255
emitted_bytes:	defs	EMIT_MAX	; the first EMIT_MAX of them - for the
				;   listing now, and for the
				;   object record later
column_buffer:	defs	COLUMN_WIDTH+8
				; the two columns, built per line. The
				;   slack is the "+" and the room a
				;   COLUMN_BYTES-byte line needs past
				;   COLUMN_WIDTH
line_address:	defs	2	; where this line began, before anything
				;   moved location_counter
line_source_kind:
		defs	1	; and the SOURCE_KIND of the source it came
				;   from, for the "+" and for .SALL/.XALL
line_has_label:	defs	1	; non-zero if it carried a label, which
				;   with emitted_count decides the address
				;   column
line_calls_macro:
		defs	1	; non-zero if it called a macro. Only
				;   .SALL reads it
output_handle:	defs	1	; where write_output and write_line write: the
				;   listing file, or STDOUT. open_output sets
				;   it, close_output reads it, and they stay
				;   with the driver - the file is its
listing_on:	defs	1	; 0 once .XLIST has been seen, and 0FFh
				;   again after .LIST. It moved here with
				;   list_line, which is what reads it
list_text_at:	defs	2	; list_line's line: where it is,
list_text_length:
		defs	1	;   and how long
line_left:	defs	1	; write_line: characters still to write,
line_column:	defs	1	;   which column it has reached,
line_run:	defs	1	;   and how long the run it just wrote
line_read_at:	defs	2	;   was, and WHERE IT IS READING - which
				;   cannot live in DE across a _WRITE
one_char:	defs	1	; write_char's one byte
lines_left:	defs	1	; lines still to go on this page. ZERO to
				;   start with, so the first line of a
				;   listing writes a header
page_number:	defs	1	; the main page number, which the PAGE
				;   directive moves on
page_break_due:	defs	1	; non-zero = a PAGE directive is waiting
				;   for its line to be listed
form_feed_columns:
		defs	1	; 2 if this page opened with a form feed,
				;   which costs the title's field two
				;   columns, and 0 if it did not
page_body_lines:
		defs	1	; lines on a page: PAGE_LENGTH until a
				;   PAGE expr says otherwise
title_text:	defs	1+TITLE_MAX	; the title: a length byte, then
				;   the text. NOT cleared between the
				;   passes, which is how a title on
				;   source line 3 heads page 1
subtitle_text:	defs	1+TITLE_MAX	; the subtitle, the same shape -
				;   and cleared per pass, and again
				;   before the S page
subpage_number:	defs	1	; and the subpage: 0 on the first page,
				;   1 on the next, 0FFh on the last
number_buffer:	defs	5	; build_decimal's answer
date_buffer:	defs	9	; the date, dd-Mmm-yy
date_day:	defs	1	; the day, the month and the year, out
date_month:	defs	1	;   of DE and HL before anything else
date_year:	defs	2	;   is allowed to use them
date_ready:	defs	1	; 0 until MSX-DOS has been asked
				;   was - write_output keeps none of them
expansion_mode:	defs	1	; LST_LALL, LST_SALL or LST_XALL: how much
				;   of an expansion the listing shows. THE
				;   DRIVER WRITES IT, from .LALL/.SALL/.XALL,
				;   and both it and build_columns.macro_mark
				;   read it - so it lives with the listing
				;   rather than with the driver
next_byte_shown:
		defs	2
			; the byte build_more_columns shows next. A WORD:
				;   EMIT_MAX is 256 and this reaches it
line_segment:	defs	1	;   and in which contribution, which is
				;   what decides the apostrophe
