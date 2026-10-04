; tatara.as - Tatara: an M80-compatible macro assembler for MSX.
;
; The driver. It reads the command line, opens the source as a line
; source, and pulls lines through the stack until there are none left.
; A line may come from a file, from an INCLUDE opened in place, or from
; a macro body replayed out of mapper RAM, and next_source_line does not say
; which.
;
; What this file acts on itself: INCLUDE, the conditional family,
; SET/DEFL, and the directives that measure and emit. Everything else
; is passed on to the listing, the object file, or both.
;
; /P assembles to the screen and /L writes a listing. /F prints each
; line's four fields in brackets, with its directive number, instead of
; the line itself.

;		.z80

		include	msxdos.inc
		include	cmdline.inc
		include	srcline.inc
		include	fields.inc
		include	dirtab.inc
		include	ascii.inc
		include	macros.inc
		include	mdt.inc		; MACRO_IS_REPT, for main.rept. Without
					;   this the assembler takes
					;   MACRO_IS_REPT for an undefined
					;   symbol, resolves it to 0000h -
					;   which is MACRO_IS_MACRO - and
					;   writes the .com anyway
		include	cond.inc
		include	expr.inc
		include	alloc.inc
		include	errs.inc
		include	expand.inc
		include	symtab.inc
		include	insn.inc
		include	emit.inc
		; object_open, write_tables, object_finish
		include	objout.inc

		cseg

main:		call	dos_version	; CY set = not MSX-DOS2
		jp	c,main.need_dos2

		call	heap_init	; CY set = no mapper support
		jp	c,main.need_mapper

		call	parse_command_line	; CY set = no input filename
		push	af		; BEFORE the inits, not after: /C
					; decides the case mode, and
					; macro_table_init and
					; symbol_table_init hand it to htinit.
					; parse_command_line needs nothing they
					; provide
		ld	a,(opt_help)	; /? and /V ANSWER AND STOP, with a
		or	a		;   filename or without one - so they
		jp	nz,main.usage	;   come before the carry, which only
		ld	a,(opt_version)	;   says whether a source was named.
		or	a		;   Neither returns, so the pushed
		jp	nz,main.version	;   flags are the program's last word
		pop	af
		jp	c,main.usage
		call	print_banner	; and now the banner, unless /Q -
					;   before any other output, because
					;   it is what the program is
		call	symbol_table_init
					; ONCE ONLY, like heap_init and for the
					; same reason: the symbol table is what
					; has to survive from pass 1 into pass
		call	segment_table_init
					; ONCE ONLY as well: a symbol holds
					; its segment's INDEX, so the
					; indices must not be handed out
					; again on pass 2
		call	macro_table_init
					; 2 and the macro name table's bucket
					; array, which is dseg space and
					; therefore garbage until it is
					; formatted. EMPTYING it between passes
					; is macro_table_reset's job, not this
					; one's

		ld	a,(object_name)	; NO OUTPUT FILE IS NOT AN ERROR any
		or	a		;   more: it means "assemble it and
		jr	z,main.start	;   tell me what you find", which is
		call	same_name	;   what all 165 tests ask for
		jp	z,main.same_file	; object over the input? refuse

main.start:	ld	a,1
		ld	(pass_number),a
		ld	a,STDOUT
				; open_output does not run until the END of
		ld	(output_handle),a
					;   pass 1, so that a source that will
					;   not assemble cannot truncate the
					;   user's file. Until then anything
					;   written - the /F dump is the only
					;   thing - goes to the standard
					;   output, which is redirectable. An
					;   unset handle is not

; Each pass re-reads the source from the beginning, so everything that
; remembers where pass 0 had got to is reset here. The symbol table and
; the formatted macro table are NOT - that is the whole distinction, and
; it is why symbol_table_init and macro_table_init sit above with heapinit.

main.start_pass:
		call	source_init	; no line sources yet
		ld	de,source_name
		call	push_file	; CY set = could not open it
		jp	c,main.cannot_open
		call	macro_table_reset
					; free the previous pass's definitions
		call	expand_init	; the ??nnnn counter back to zero, so
					; pass 2 generates the same names pass
		call	cond_init	; 1 did no conditionals open
		call	expr_init
				; symbol_lookup points at look_up_symbol
		call	segment_reset	; every counter 0, CSEG current
		xor	a
		ld	(end_seen),a	; pass 2 must stop at the same END
		call	listing_init	; the listing on, .XALL, page 1: a
					;   .XLIST on pass 1 must not silence
					;   pass 2
		ld	a,0ffh		; and a branch not taken is listed
		ld	(list_false_conditionals),a
					;   until .SFCOND says otherwise

; One line at a time: get it, understand it, then decide what becomes of
; it. Only the last of those three steps knows anything about output.

main.next_line:	ld	a,(end_seen)	; an END line ends the pass, and
		or	a		; with it the file that included
		jp	nz,main.pass_done
					; this one, and every file above

		ld	hl,line_buffer
		call	next_source_line
					; CY set = no more lines, anywhere
		jp	c,main.pass_done
		ld	(source_line_length),a	; split_line and find_directive
					;   clobber A
		dec	a		; A FORM FEED ON A LINE OF ITS OWN
		jr	nz,main.not_form_feed
					;   STARTS A PAGE, and A still holds
		ld	a,(line_buffer)	;   the length. It must not reach
		cp	CHR_FF	;   split_line: nothing there ends a field
		jp	z,main.form_feed
					;   on 0Ch, so it would become a label
					;   and be defined like any other -
					;   issue #17
main.not_form_feed:
		ld	hl,line_buffer
		ld	ix,line_fields
				; next_source_line used IX for its own purposes
		call	split_line

		; did it carry a label? With the byte count that is what
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		ld	b,a
		ld	hl,(location_counter)
					; where this line begins, and in
		ld	a,(current_segment)
					;   what, BEFORE anything moves the
		call	emit_line_start	;   counter - and nothing emitted yet
		; is the operation a directive?
		ld	de,(line_fields+FIELD_OPERATION)
		ld	a,(line_fields+FIELD_OPERATION_LENGTH)
		ld	b,a
		call	find_directive	; A = the number, 0 = it is not one
		ld	(directive_number),a

		; A COLUMN-1 WORD BEGINNING WITH * OR $ IS A CONTROL LINE,
		;   which is M80's rule and now ours. 099 took only the two
		;   names and only on a line with no operation, for two reasons
		;   that were both weaker than they looked: $foo: is not a
		;   label in M80 either, so no portable source has one; and
		;   M80's answer for an unknown starred word being inconsistent
		;   was a reason not to copy ITS answers, never a reason not to
		;   have one of our own.
		;
		;   THE OPERATION FIELD IS NOT LOOKED AT: $title('Dollar
		;   title') has one, because the quote holds a space and
		;   is_field_end ends a field there - and that line is what the
		;   message is for. 100
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		or	a
		jr	z,main.not_control_line
		ld	de,(line_fields+FIELD_LABEL)
		ld	a,(de)
		cp	"*"
		jr	z,main.control_line
		cp	"$"
		jr	nz,main.not_control_line
main.control_line:
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		ld	b,a
		call	find_directive
		or	a
		jp	z,error_bad_control_line
		ld	(directive_number),a
		xor	a
		ld	(line_fields+FIELD_LABEL_LENGTH),a
main.not_control_line:

		ld	a,(pass_number)	; /F and /M are diagnostics of pass 0's
		dec	a		; work, and pass 0 now runs twice.
		jr	nz,main.no_field_dump	; Dumping on pass 1 only says
		ld	a,(opt_fields)	; everything, once
		or	a
		call	nz,dump_line_fields
					; /F: show what split_line made of it
main.no_field_dump:

; A conditional directive, or a line inside a branch we are not taking?
; Either way it produces nothing and the rest of the driver never sees
; it - which is what keeps INCLUDE, MACRO and macro calls from happening
; inside a false branch. The /F dump above still shows the line, so that
; the skipping can be watched.

		ld	a,(directive_number)
		call	cond_line	; CY set = this line produces nothing
		jr	nc,main.dispatch
		ld	a,(directive_number)
					; IT PRODUCES NOTHING FOR ONE OF TWO
		cp	DIRECTIVE_IF	;   REASONS, and the number says which:
		jr	c,main.skipped_line
					;   the IF family is contiguous,
					;   which is the same property
					;   cond_line opens
		cp	DIRECTIVE_ENDIF+1
		jr	nc,main.skipped_line	;   with

; A directive of the IF family, on its own line. M80 lists those wherever
; they are - AND DEFINES A LABEL ON ONE when the line is being assembled.
; cond_label_assembled is that question answered before cond_line changed the
; state, which is the only moment it can be answered: "lels: else" is defined
; because the branch ABOVE it was being taken, and "lend: endif" on the next
; line is not, because by then we are inside the skipped ELSE. Issue #15.
; emit_line_skipped is NOT called on the defining path. emit_line_start
; recorded the label before cond_line ran, so the address column already holds
; what M80 prints there - 085's mechanism, used the other way up.

		ld	a,(cond_label_assembled)
		or	a
		jr	z,main.cond_no_label
					; not being assembled: no label, and
		call	define_label	;   no address either
		jp	main.emit_line
main.cond_no_label:
		call	emit_line_skipped
		jp	main.emit_line

main.skipped_line:
		call	emit_line_skipped
					; a line inside a branch we are not
		ld	a,(list_false_conditionals)
					;   taking names no place: 085. And
		or	a		;   .LFCOND shows it while .SFCOND
		jp	nz,main.emit_line
					;   does not - either way nothing on
		jp	main.next_line	;   it is acted on
main.dispatch:

		ld	a,(directive_number)	; cond_line used A
		cp	DIRECTIVE_INCL
		jp	z,main.include
		cp	DIRECTIVE_MACRO
		jp	z,main.macro
		cp	DIRECTIVE_REPT
		jp	z,main.rept
		cp	DIRECTIVE_IRP
		jp	z,main.irp
		cp	DIRECTIVE_IRPC
		jp	z,main.irpc
		cp	DIRECTIVE_EXITM
		jp	z,main.exitm
		cp	DIRECTIVE_ENDM
		jp	z,error_endm_without_macro
					; nothing was open to close
		cp	DIRECTIVE_SET
		jp	z,main.set	; a DEFL's label names its VALUE,
					;   not $. SET shared this number
					;
		cp	DIRECTIVE_GROUP
		jp	z,main.group	; a GROUP line takes no label at all
		cp	DIRECTIVE_EQU
		jp	z,main.equ	; like SET, its label names the VALUE
					; THESE TWO DEFINE THEIR OWN LABEL,
		cp	DIRECTIVE_PUBLIC
		jp	z,main.public	;   at main.name_list, and come through
		cp	DIRECTIVE_EXTRN	;   here only because they share the
		jp	z,main.extrn	;   routine that walks a name list.
					;   The comment that stood here said
					;   they "take no label either" and
					;   cited nothing: M80 defines a label
					;   on both, at the location counter.
					;   Issue #28, note 098
		cp	DIRECTIVE_END
		jp	z,main.end

		call	define_label	; any other label takes the location
					; counter

		ld	a,(directive_number)
		cp	DIRECTIVE_ORG
		jp	z,main.org
		cp	DIRECTIVE_DS
		jp	z,main.ds
		cp	DIRECTIVE_DB
		jp	z,main.db
		cp	DIRECTIVE_DW
		jp	z,main.dw
		cp	DIRECTIVE_DC
		jp	z,main.dc
		cp	DIRECTIVE_LIST	; one of the five listing controls?
		jr	c,main.not_listing_control	;   DIRECTIVE_LIST to
					;   DIRECTIVE_XALL, consecutive
		cp	DIRECTIVE_XALL+1
		jp	c,main.list
		cp	DIRECTIVE_TFCOND+1
		jp	c,main.lfcond
		cp	DIRECTIVE_TITLE		; TITLE and SUBTTL, consecutive
		jr	c,main.not_listing_control
		cp	DIRECTIVE_SUBTTL+1
		jp	c,main.title
		cp	DIRECTIVE_PAGE
		jp	z,main.page
main.not_listing_control:
		cp	DIRECTIVE_ASEG		; ASEG, CSEG or DSEG?
		jr	c,main.not_segment
		cp	DIRECTIVE_DSEG+1
		jp	c,main.segment
main.not_segment:
		or	a
		jp	nz,main.emit_line
					; some other directive: pass it on

; Not a directive. is the operation the name of a macro? The fields still
; describe this line - dump_line_fields only read them - so DE and B can be
; loaded from line_fields again, exactly as find_directive was given them.

		ld	de,(line_fields+FIELD_OPERATION)
		ld	a,(line_fields+FIELD_OPERATION_LENGTH)
		ld	b,a
		ld	hl,called_macro
		call	find_macro	; CY set = not a macro name
		jr	c,main.instruction
		ld	de,(line_fields+FIELD_OPERAND)
					; the call's arguments, still
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
					; describing this line
		ld	hl,called_macro	; find_macro returned through HL
		call	expand_start	; its body is now the line source
		ld	a,0ffh		; .SALL flags this line, because it
		ld	(line_calls_macro),a
					;   is all the call will produce
		jp	main.emit_line	; AND THE CALL LINE IS LISTED, which
					;   M80 does and it did not.
					;   It emits nothing, so it shows an
					;   address and no bytes - and under
					;   .SALL it is all a call produces.
					;   emit_line_start already recorded
					;   that this line came from a file, so
					;   expand_start's push does not
					;   disguise it

; Not a directive and not a macro. An instruction moves the location
; counter and is passed on to the listing like any other line.
;
; Anything else is now an ERROR. All sixty-nine mnemonics have handlers
;, so "not in the table" finally means "not an instruction",
; and M80's own answer here - to assemble it as a DB (2.3.1), so that a
; mistyped "xro a" becomes one byte of data and breaks the program
; somewhere else - is the departure optable-design.md 8 decided
; against.
;
; The guard first. assemble_instruction says "no" to a line with no operation
; at all as well as to a word it does not know, and a label or a comment on its
; own is neither an error nor an instruction.

main.instruction:
		ld	a,(line_fields+FIELD_OPERATION_LENGTH)
		or	a
		jp	z,main.emit_line	; a label or a comment alone
		ld	ix,line_fields
		call	assemble_instruction
		jp	c,error_unknown_operation
		jp	main.emit_line

; A SET or DEFL line is acted on AND passed on: pass 0 needs the value so
; that a conditional can ask about it, and pass 1 needs the line so that
; the symbol exists for the rest of the program. Every other directive so
; far has been consumed; this is the first that is not, which is why the
; branch below ends by falling into main.emit_line. It used to get there by
; falling off its last line; main.equ went in between, so it jumps now.

main.set:	ld	a,(line_fields+FIELD_LABEL_LENGTH)
		or	a
		jp	z,error_bad_expression
					; DEFL with no name in front of it.
					;   SET reached here too and
					;   does not now - it is the bit
					;   instruction and nothing else
		call	colon_after_label
					; a name, not a label, as for EQU
		jp	z,error_name_not_label
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		call	eval_expression	; HL = the value
		ld	a,(value_type)	; which the listing shows where an
		call	emit_show_value	;   address would go, as for EQU
		ld	de,(line_fields+FIELD_LABEL)
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		ld	b,a
		ld	a,(value_type)	; the value's own type: "here set $" is
		ld	c,SYMBOL_VARIABLE
					; relative to the current segment. SET
		call	define_symbol	; and DEFL are the only variables
		jp	main.emit_line	; main.equ sits between this and the
					; emit now, so say it

; EQU is SET's opposite: one value, for good. M80 2.6.11 allows the same
; line to say it twice with the same value, which is what makes pass 2
; work without a special case here.

main.equ:	ld	a,(line_fields+FIELD_LABEL_LENGTH)
		or	a
		jp	z,error_bad_expression
					; EQU with no name in front of it
		call	colon_after_label
					; and a NAME is what it takes: a
		jp	z,error_name_not_label
					;   colon would make it a label,
					;   which is M80 2.3.1 and leaves
					;   the EQU nameless - error O
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		call	eval_expression
		ld	a,(value_type)
		cp	SY_EXTERNAL
		jp	z,error_external_here
					; "If <exp> is external, an error is
					; generated" - 2.6.11
		ld	a,(value_type)	; the listing shows the VALUE where
		call	emit_show_value	;   an address would go, which is
					;   where M80 puts it. HL still holds
					;   it: emit_show_value modifies
					;   nothing
		ld	de,(line_fields+FIELD_LABEL)
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		ld	b,a
		ld	a,(value_type)
		ld	c,0		; fixed: define_symbol keeps the rules
		call	define_symbol
		jp	main.emit_line

; PUBLIC/ENTRY and EXTRN/EXT take a list of names and nothing else. The
; walk is shared; which routine each name goes to is the only difference,
; and it goes in declare_routine rather than being duplicated.

main.public:	ld	hl,declare_public
		jr	main.name_list
main.extrn:	ld	hl,declare_external
main.name_list:	ld	(declare_routine),hl
		call	define_label	; AFTER THE STORE, not before it:
					;   define_label destroys HL, and HL is
					;   how these two tell each other apart
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		ld	b,a

main.next_name:	call	main.skip_blanks	; blanks in front of the name
		ld	a,b
		or	a
		jp	z,error_bad_declaration
					; nothing there: "public ," or "public"
		push	de		; where this name starts
		ld	c,0
main.name_char:	ld	a,b
		or	a
		jr	z,main.declare_name
		ld	a,(de)
		cp	" "
		jr	z,main.declare_name
		cp	CHR_TAB
		jr	z,main.declare_name
		cp	","
		jr	z,main.declare_name
		inc	de
		inc	c
		dec	b
		jr	main.name_char

main.declare_name:
		pop	hl		; HL -> the name, C = its length
		ld	a,c
		or	a
		jp	z,error_bad_declaration
		push	de		; the scan, kept across the call
		push	bc
		ex	de,hl		; DE -> the name, B = its length
		ld	b,c
		ld	hl,(declare_routine)
		call	main.call_hl	; declare_public or declare_external
		pop	bc
		pop	de

		call	main.skip_blanks
					; a comma means another name follows
		ld	a,b
		or	a
		jp	z,main.emit_line
		ld	a,(de)
		cp	","
		jp	nz,error_bad_declaration
		inc	de
		dec	b
		jr	 main.next_name

main.call_hl:	jp	(hl)		; the call above is what returns here

main.skip_blanks:
		ld	a,b		; step DE over blanks and tabs
		or	a
		ret	z
		ld	a,(de)
		cp	" "
		jr	z,main.skip_step
		cp	CHR_TAB
		ret	nz
main.skip_step:	inc	de
		dec	 b
		jr	main.skip_blanks

; END stops the assembly here, whatever is left in this file or in the
; one that included it. Its operand is the program's start address, and
; object_entry keeps it until object_finish can write the ENTRY record - which
; is after pass 2, because until then there is an unfinished DATA record in the
; file.

main.end:	call	define_label	; "lend2: end" defines lend2 as the
					;   counter, BEFORE the operand is
					;   looked at - define_label's own rule
					;   for ORG and DS. M80 lists 0103
					;   there
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		or	a
		jr	z,main.mark_end
		ld	de,(line_fields+FIELD_OPERAND)
		call	eval_expression
		ld	a,(value_type)	; the ENTRY record needs a segment as
		; well as an offset, and object_finish is where it can be
		;   written
		call	object_entry
main.mark_end:	ld	a,0ffh
		ld	(end_seen),a
		jp	main.emit_line

main.emit_line:	ld	a,(pass_number)
		cp	2
		jp	nz,main.next_line
					; pass 1 emits nothing at all: it is
					; there to find out what the symbols
		ld	hl,(emitted_count)
					; PROVED: a line cannot emit more
		ld	de,EMIT_MAX	;   than EMIT_MAX, and the
		or	a		;   buffer is the object file's
		sbc	hl,de		;   content. The assertion moved
		; here from object_data, which only runs
		jr	c,main.emit_ok
		jp	nz,error_too_many_bytes
					;   when a file is open - "tatara /p"
main.emit_ok:	call	object_data	;   would have truncated in silence
					; THE OBJECT FILE FIRST. This makes
					;   everything below this return early
					;   when no listing was asked for, and
					;   an object file is normally written
					;   with no listing at all
		ld	a,(opt_fields)	; are worth with /F the dump has
		or	a		; replace the line, so there is nothing
					; to write
		jp	nz,main.next_line
		ld	de,line_buffer	; and the rest is list_line, which
		ld	a,(source_line_length)
					;   collect_macro calls too: it moved
		call	list_line	;   into emit.as so that there is one
		jp	main.next_line	;   copy of what a listing line is

; ORG and DS use the STRICT evaluator. Their operand decides where
; everything after them sits, so an unknown value is not a forward
; reference that pass 2 will fix - it is a source that cannot be
; assembled at all. Same reasoning as the REPT count.

main.org:	call	require_placeable
					; a transient DSEG with no group
					;   open cannot be placed in
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		call	eval_expression
		ld	a,(value_type)	; absolute, or in the current segment's
		or	a		; own mode - M80 2.6.28.1. "dseg" then
		jr	z,main.org_store	; "org 20" is data offset 20
		ld	b,a
		ld	a,(current_segment)
		cp	b
		jp	nz,error_relocation
					; a data address for the code counter
main.org_store:	ld	(location_counter),hl
		jp	main.emit_line

main.ds:	call	require_placeable	; as ORG above
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		call	eval_absolute	; a count of bytes: absolute only
		ld	de,(location_counter)
		add	hl,de
		ld	(location_counter),hl
		jp	main.emit_line

; DB, DW and DC in their SIZING role. This measures; the bytes
; themselves are the object writer's.
;
;   HOW MUCH ROOM AN ITEM TAKES DOES NOT DEPEND ON WHAT IT IS WORTH.
;   "db later" is one byte whether later is defined above, defined
;   below, or promised by another module. So nothing here calls the
;   evaluator, and a forward reference costs no machinery at all - the
;   first one in Tatara's life arrives for free.
;
;   The only thing that changes an item's size is whether it is a
;   STRING, and M80 2.6.4 decides that by what FOLLOWS the closing
;   quote: a comma or the end of the line means a string, one byte per
;   character; anything else means the quotes were a character constant
;   inside an expression. That is what makes "db 'AB'" two bytes and
;   "db 'AB' AND 0FFH" one, and it needs no lookahead past one
;   character.

main.db:	ld	a,1		; one byte per expression
		jr	main.data_line
main.dw:	ld	a,2		; two
main.data_line:	ld	(data_width),a
		call	require_placeable	; as ORG and DS above
		call	walk_data_items	; (data_bytes) = what this line adds
		ld	hl,(data_bytes)
main.advance_counter:
		ld	de,(location_counter)
		add	hl,de
		ld	(location_counter),hl
		jp	main.emit_line

; DC takes ONE string and it may not be empty: a null string has no last
; character to set the high bit of, and 2.6.5 calls that an error.

main.dc:	call	require_placeable
		ld	a,1
		ld	(data_width),a	; DC emits a byte per character,
					;   like a DB
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		ld	b,a
		call	main.skip_blanks
		ld	(item_at),de
				; where the string begins. walk_data_items
		call	measure_data_item
					;   does this for DB and DW; DC does
					;   not go through walk_data_items at
					;   all
		ld	a,(item_is_string)
		or	a
		jp	z,error_bad_data_operand	; not a string at all
		ld	a,h
		or	l
		jp	z,error_bad_data_operand	; a null string
		push	hl		; the count, for main.advance_counter
		push	de	; and DE, which main.skip_blanks will move
		call	emit_data_item	; WHILE DE IS STILL JUST PAST THE
		call	emit_high_bit_last
					;   ITEM - emit_data_item measures from
					;   item_at
		pop	de	;   to here, and main.skip_blanks below would
		pop	hl		;   fold trailing spaces into it
		call	main.skip_blanks
		ld	a,b
		or	a
		jp	nz,error_bad_data_operand
					; one string, and nothing after it
		jr	main.advance_counter

; walk_data_items - measure a whole DB or DW operand.
;
; Input:	(data_width) = 1 for DB, 2 for DW
; 		the operand, in line_fields
; Output:	(data_bytes) = how many bytes the line adds
; 		error_bad_data_operand does not return
; Modifies:	AF, BC, DE, HL

walk_data_items:
		ld	hl,0
		ld	(data_bytes),hl
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		ld	b,a
walk_data_items.next_item:
		call	main.skip_blanks
		ld	(item_at),de
			; where this item begins: measure_data_item leaves
		call	measure_data_item
				;   DE past it, and emit_data_item needs both
		ld	a,(item_is_string)
		or	a
		jr	z,walk_data_items.expression
		ld	a,(data_width)	; a string standing on its own
		dec	a
		jr	z,walk_data_items.add_size
					; DB: one byte per character
		ld	a,h		; DW: one or two characters is a
		or	a		;   number, and fits the word. Three
		jp	nz,error_bad_data_operand
					;   or more may not be used in an
		ld	a,l		;   expression at all - 2.6.4
		cp	3
		jp	nc,error_bad_data_operand
walk_data_items.expression:
		ld	a,(data_width)	; an expression, or a short string in
		ld	l,a		;   a DW: the width, whatever it
		ld	h,0		;   turns out to be worth
walk_data_items.add_size:
		push	de
		push	bc		; B is the text left, not a count
		ex	de,hl
		ld	hl,(data_bytes)
		add	hl,de
		ld	(data_bytes),hl
		pop	bc
		pop	de
		push	bc
		call	emit_data_item	; Counting once stopped here. The
		pop	bc		;   count is still wanted - main.db
					;   moves location_counter by it - but
					;   the bytes go out on the way past
					;   now
		call	main.skip_blanks
		ld	a,b
		or	a
		ret	z		; the operand ends: the line is done
		ld	a,(de)
		cp	","
		jp	nz,error_bad_data_operand
					; two items with nothing between
		inc	de
		dec	b
		jr	walk_data_items.next_item

; emit_data_item - emit the item measure_data_item has just measured.
;
;   item_at says where it began and DE says where it ended - on the comma,
;   or at the end of the operand - so the two together are its text.
;
;   A string in a DB or a DC is emitted character by character. Anything
;   else is an expression, INCLUDING a one or two character string in a
;   DW: "dw 'AB'" is the single value 4142h, read_character has always known
;   it, and M80 lists it as 4142 (CHARC.PRN). The two are not a special case of
;   each other and measure_data_item has already decided which this is.
;
; Input:	(item_at) -> the item, DE -> just past it
;		(item_is_string) = 1 if it was a string on its own
;		(data_width) = 1 for DB and DC, 2 for DW
; Output:	its bytes are emitted
; Modifies:	AF, BC, DE, HL

emit_data_item:	push	bc
		push	de
		push	hl
		ld	h,d
		ld	l,e		; HL -> just past the item
		ld	de,(item_at)	; DE -> its first character
		or	a
		sbc	hl,de		; HL = how many characters it has -
		ld	a,l		;   a line is 255 at most, so L is all
		ld	(item_length),a	;   of it
		ld	a,(item_is_string)
		or	a
		jr	z,emit_data_item.expression	; an expression
		ld	a,(data_width)
		dec	a
		jr	nz,emit_data_item.expression
					; a string in a DW is an expression too
		call	emit_data_string
					; a DB or DC string: its characters
		jr	emit_data_item.done
emit_data_item.expression:
		ld	a,(data_width)
		dec	a
		ld	a,(item_length)	; ld a,(nn) leaves the flags alone
		jr	nz,emit_data_item.word
		call	emit_expr_byte	; DB or DC: one byte
		jr	emit_data_item.done
emit_data_item.word:
		call	emit_expr_word	; DW: two
emit_data_item.done:
		pop	hl
		pop	de
		pop	bc
		ret

; emit_data_string - emit the characters of a string in a DB or a DC, two
;   delimiters together counting as one.
;
;   This is count_quoted_run's walk with an emit_byte where its "inc hl" was,
;   and it is the FIFTH routine in the program to step over a quoted run.
;   Reading the other four side by side kept them apart: they share a RULE, not
;   an interface - four cursors, four products, and split_line's is not a
;   routine at all. The rule, once, so that the sixth has something to copy:
;
;     a run ends at the next delimiter that is NOT followed by the same
;     delimiter again; two together are one character of the string
;
;   measure_data_item has already counted this item, so nothing here can run
;   off the end: the text it walks is the text count_quoted_run measured.
;
; Input:	(item_at) -> the opening delimiter
;		(item_length) = how many characters the item has
; Output:	its characters are emitted
; Modifies:	AF, BC, DE, HL

emit_data_string:
		ld	de,(item_at)
		ld	a,(de)
		ld	c,a		; C = the delimiter that opened it
		inc	de
		ld	a,(item_length)
		dec	a
		ld	b,a		; B = characters left, the quote gone
emit_data_string.next_char:
		ld	a,b
		or	a
		ret	z
		ld	a,(de)
		inc	de
		dec	b
		cp	c
		jr	nz,emit_data_string.emit_char	; an ordinary character
		ld	a,b		; a delimiter: doubled, or the end?
		or	a
		ret	z		; the item ends: it closed here
		ld	a,(de)
		cp	c
		ret	nz		; something else follows: closed
		inc	de		; "" - one character, and on we go
		dec	b
		ld	a,c
emit_data_string.emit_char:
		call	emit_byte
		jr	emit_data_string.next_char

; measure_data_item - measure ONE item, and say which kind it was.
;
;   Either way it leaves DE on the comma that ends the item, or at the
;   end of the operand, because an expression is SKIPPED rather than
;   read. What it is worth is the emitter's business.
;
; Input:	DE -> the item's first character
; 		B  = characters left in the operand
; Output: (item_is_string) = 1 for a string on its own, 0 for an expression
; 		HL = its characters, when (item_is_string) is 1
; 		DE -> the comma, or the end
; 		B  = characters left
; 		error_bad_data_operand does not return
; Modifies:	AF, BC, DE, HL

measure_data_item:
		xor	a
		ld	(item_is_string),a
		ld	h,a
		ld	l,a		; HL = 0: nothing counted yet
		ld	a,b
		or	a
		jp	z,error_bad_data_operand
					; "db 1," - nothing after the comma
		ld	a,(de)
		cp	","
		jp	z,error_bad_data_operand
					; "db 1,,2" - nothing between them
		call	measure_data_item.is_quote
		jr	nz,measure_data_item.expression
					; no quote: an expression
		call	count_quoted_run	; HL = the run's characters
		call	main.skip_blanks
		ld	a,b
		or	a
		jr	z,measure_data_item.string
					; the operand ends here: a string
		ld	a,(de)
		cp	","
		jr	nz,measure_data_item.expression
					; something else follows: the run was
					;   a character constant, and this
					;   item is an expression after all
measure_data_item.string:
		ld	a,1
		ld	(item_is_string),a
		ret

measure_data_item.expression:
		ld	a,b
		or	a
		ret	z
		ld	a,(de)
		cp	","
		ret	z
		call	measure_data_item.is_quote
		jr	nz,measure_data_item.next_char
		call	count_quoted_run
					; a quoted run inside an expression
		jr	measure_data_item.expression
					;   is stepped over whole, so a
					;   comma inside it does not end the
					;   item
measure_data_item.next_char:
		inc	de
		dec	b
		jr	measure_data_item.expression

; count_quoted_run - step over one quoted run, counting its characters.
;
;   TWO DELIMITERS TOGETHER ARE ONE CHARACTER and do not close the run -
;   2.3.4's own rule, and the reason the count is not simply the
;   distance between the quotes. "I am ""great"" today" is eighteen
;   characters, not twenty, and every label below the line depends on
;   which number this routine gives.
;
; Input:	DE -> the opening quote
; 		B  = characters left in the operand
; 		HL = a running count
; Output:	DE -> past the closing quote
; 		B  = characters left
; 		HL = the count, plus this run's characters
; 		error_bad_data_operand does not return
; Modifies:	AF, BC, DE, HL

count_quoted_run:
		ld	a,(de)
		ld	c,a		; C = the quote that opened it
		inc	de
		dec	b
count_quoted_run.next_char:
		ld	a,b
		or	a
		jp	z,error_bad_data_operand
					; the line ended inside a string
		ld	a,(de)
		inc	de
		dec	b
		cp	c
		jr	nz,count_quoted_run.count_it	; an ordinary character
		ld	a,b		; a delimiter: doubled, or the end?
		or	a
		ret	z		; the operand ends: it closed here
		ld	a,(de)
		cp	c
		ret	nz		; something else follows: closed
		inc	de		; "" - one character, and on we go
		dec	b
count_quoted_run.count_it:
		inc	hl
		jr	count_quoted_run.next_char

; measure_data_item.is_quote - is the character in A a string delimiter?
;
; Input:    A = a character
; Output:   Z set = it is a quote, either sort
; Modifies: AF

measure_data_item.is_quote:
		cp	QUOTE1
		ret	z
		cp	QUOTE2
		ret

; ASEG, CSEG and DSEG are numbered in the order of SY_ABS, SY_CODE and
; SY_DATA, so the segment's type is the directive's number minus
; DIRECTIVE_ASEG. The line is passed on, like ORG's.

main.segment:	sub	DIRECTIVE_ASEG		; 0 ASEG, 1 CSEG, 2 DSEG
		ld	de,(line_fields+FIELD_OPERAND)
		ld	hl,line_fields+FIELD_OPERAND_LENGTH
		ld	b,(hl)
		call	segment_directive
					; the name and TRANSIENT are its
		jp	main.emit_line	;   problem, not the driver's

; A GROUP line opens a coexistence group inside the current transient
; DSEG. It comes through before define_label, so a label in front of it is
; caught rather than quietly given the counter.

main.group:	ld	a,(line_fields+FIELD_LABEL_LENGTH)
		or	a
		jp	nz,error_bad_group_line
		ld	de,(line_fields+FIELD_OPERAND)
		ld	hl,line_fields+FIELD_OPERAND_LENGTH
		ld	b,(hl)
		call	group_directive
		jp	main.emit_line

COLON		equ	03ah	; ":" - named rather than written, the
				;   habit fields.as keeps for the
				;   characters it tests

; colon_after_label - the character that follows the label's name.
;
;   NOTHING IS RECORDED WHEN THE LINE IS SPLIT, and nothing needs to
;   be: split_line steps over the colons but leaves FIELD_LABEL and
;   FIELD_LABEL_LENGTH
;   pointing into the line buffer, so what was written after the name
;   is still there to read.
;
;   A LINE WITH NO LABEL ANSWERS "no colon", which is what both
;   callers want. That is why the empty case returns 1 and not 0 -
;   the flags have to say NZ, and 0 would say the opposite.
;
; Input:	line_fields describes the line
; Output:	Z set = a colon follows the name, "name:" or "name::"
;		NZ    = no label at all, or a name with no colon
;		HL -> that character, when there is a label
; Modifies:	AF, DE, HL

colon_after_label:
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		or	a
		jr	nz,colon_after_label.have_label
		inc	a		; no label: 1 is not a colon, and
		ret			;   INC leaves NZ to say so
colon_after_label.have_label:
		ld	e,a
		ld	d,0
		ld	hl,(line_fields+FIELD_LABEL)
		add	hl,de		; the character after the name
		ld	a,(hl)
		cp	COLON
		ret

; public_if_double_colon - "name::" declares name PUBLIC.
;
;   M80 2.3.1: "If it is followed by two colons, it is declared as
;   PUBLIC", and "FOO:: RET" is equivalent to "PUBLIC FOO" then
;   "FOO: RET".
;
;   BEFORE THE SYMBOL IS DEFINED. declare_public creates a record with
;   SYMBOL_DEFINED clear so that the definition which follows counts as the
;   first one - the path "public foo" at the top of a file and "foo:"
;   two hundred lines down has always taken.
;
;   Both passes run it. On pass 2 the record is already there and
;   declare_public ORs a flag that is already set.
;
; Input:	line_fields describes the line
; Output:	the name carries SYMBOL_PUBLIC if two colons followed it
; Modifies:	AF, BC, DE, HL, IX

public_if_double_colon:
		call	colon_after_label
		ret	nz		; no label, or no colon at all
		inc	hl
		ld	a,(hl)
		cp	COLON
		ret	nz		; "name:" - the ordinary label
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		ld	b,a		; where declare_public wants it
		ld	de,(line_fields+FIELD_LABEL)
		jp	declare_public	; "name::"

; define_label - a label in the label field takes the location counter.
;
;   BEFORE ORG and DS act, which looks wrong and is right: "here: ds 4"
;   makes here the address OF the space, not the address after it, and
;   "here: org 100h" gives here the value the counter had BEFORE the
;   ORG. M80 does both.
;
;   On pass 2 the value must agree with what pass 1 recorded. If it does
;   not, the two readings assembled different programs and everything
;   after this label is wrong by the difference - error_phase.
;
; Input:	line_fields describes the line, location_counter, pass_number
; Output:	the symbol is defined
; Modifies:	AF, BC, DE, HL, IX

define_label:	ld	a,(line_fields+FIELD_LABEL_LENGTH)
		or	a
		ret	z		; no label on this line
		ld	b,a		; EVERY CHARACTER OF IT, before any of
		ld	hl,(line_fields+FIELD_LABEL)
					; it is believed. split_line
define_label.next_char:
		ld	a,(hl)		;   the label as everything up to a
		call	is_name_char	;   or a separator, which is M80's own
		jp	nz,error_bad_name_char
					;   rule for finding one - and M80 then
		inc	hl		;   refuses the ones that are not names
		djnz	define_label.next_char
					;   (U, appendix J). We defined them,
					;   and is_name_char stops an
					;   expression's name scan at the first
					;   such character - so the symbol
					;   could be defined and never referred
					;   to
		call	public_if_double_colon
					; "name::", before the definition
		call	require_placeable
					; a variable in a transient DSEG
					;   must be inside a GROUP
		ld	a,(line_fields+FIELD_LABEL_LENGTH)
		ld	b,a
		ld	de,(line_fields+FIELD_LABEL)
		ld	hl,(location_counter)
		ld	a,(current_segment)
					; relative to the current segment
		ld	c,SYMBOL_IS_LABEL
				; a label is FIXED - SYMBOL_VARIABLE is what
					;   makes a symbol variable and this
					;   is not it - and it is a LABEL,
					;   which is what check_pass2_labels
					;   checks and what SYMBOL_FILE and
					;   SYMBOL_LINE are kept for. So
					;   define_symbol does
		jp	define_symbol	; the multiply-defined check AND the
					; pass-2 agreement check that used to
					; be written out here

; An INCLUDE line is consumed here and never written out. From the next
; time round the loop, next_source_line is reading the file it opened.

main.include:	call	define_label	; THE INCLUDING LINE'S COUNTER, before
					;   a byte of the included file exists.
					;   M80 cannot be asked - it will not
					;   run an include at all - so this
					;   follows the rule the other eight
					;   rows were measured against. 088,
					;   and decisions-pending until now
		call	open_include	; CY set = could not open it
		jp	c,main.cannot_open_include
		jp	main.next_line

; A macro definition is consumed whole - the MACRO line, the body and the
; ENDM - and none of it is written out. collect_macro borrows line_buffer, so
; the contents of line_fields are rubbish by the time it returns.

; .LIST, .XLIST, .LALL, .SALL and .XALL. The last three are consecutive
; and in that order, so the mode is what is left after subtracting.
;
; WHETHER A CONTROL LINE LISTS ITSELF IS PROVISIONAL: .XLIST eats its
; own line here and the other four keep theirs. MACLIST.AS puts M80's
; answer in RESULTS.TXT.

main.list:	ld	a,(directive_number)
		cp	DIRECTIVE_LIST
		jr	nz,main.xlist
		ld	a,0ffh		; .LIST: text again, starting here
		ld	(listing_on),a
		jp	main.emit_line
main.xlist:	cp	DIRECTIVE_XLIST
		jr	nz,main.lall
		xor	a		; .XLIST: none, and this line is the
		ld	(listing_on),a	;   first one it eats
		jp	main.next_line
main.lall:	sub	DIRECTIVE_LALL	; 0, 1 or 2 - LST_LALL, LST_SALL,
		ld	(expansion_mode),a	;   LST_XALL, in that order
		jp	main.emit_line

; .LFCOND, .SFCOND and .TFCOND: whether the lines inside a branch that
; was not taken appear in the listing.
;
; .TFCOND FLIPS WHAT IS IN FORCE, which is an approximation - M80's
; wording is about flipping the default. FCOND.AS asks M80 what the
; default is; nothing yet asks what .TFCOND does to it.

main.lfcond:	ld	a,(directive_number)
		cp	DIRECTIVE_LFCOND
		jr	nz,main.sfcond
		ld	a,0ffh
		jr	main.fcond_store
main.sfcond:	cp	DIRECTIVE_SFCOND
		jr	nz,main.tfcond
		xor	a
		jr	main.fcond_store
main.tfcond:	ld	a,(list_false_conditionals)
					; .TFCOND: the other one
		cpl
main.fcond_store:
		ld	(list_false_conditionals),a
		jp	main.emit_line

; TITLE, SUBTTL and PAGE.
;
; A TITLE SURVIVES THE PASS AND A SUBTTL DOES NOT. That is not a
; choice: M80's own TITLLST.PRN has a title from source line 3 heading
; page 1 of the listing, and a subtitle from line 4 appearing nowhere
; at all. listing_init clears one buffer and leaves the other.
;
; Both are stored in both passes. The second store writes what the
; first one did.

main.title:	ld	a,(directive_number)	; DIRECTIVE_TITLE and
					;   DIRECTIVE_SUBTTL are one apart
		sub	DIRECTIVE_TITLE		;   and set_title takes 0 or 1
		ld	c,a
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		call	set_title
		jp	main.emit_line

; PAGE alone breaks the page; PAGE with an operand says how long a
; page is. The break happens after this line - see listing_eject.

main.page:	ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		or	a
		jr	z,main.page_break
		ld	de,(line_fields+FIELD_OPERAND)
		call	eval_expression	; HL = the count, and absolute:
		call	set_page_length	;   a page length in pass 1
main.page_break:
		call	listing_eject	; WITH AN OPERAND OR WITHOUT: M80
		jp	main.emit_line	;   breaks the page either way, which
					;   PAGEDIR.AS showed and the manual
					;   does not say

main.macro:	call	colon_after_label
					; a name, not a label - and BEFORE
		jp	z,error_name_not_label
					;   collect_macro, so the macro is
					;   never opened. M80 does the same:
					;   its ENDM then gets an error of its
					;   own, for closing nothing
		ld	de,line_buffer	; M80 lists the MACRO line and every
		ld	a,(source_line_length)
				;   line of the body. collect_macro lists
		call	list_body_line	;   the body as it reads it; this is
		ld	hl,line_buffer	;   the one line it never sees
		ld	ix,line_fields
		call	collect_macro
		ld	a,(pass_number)	; pass 1 only, as with /F above
		dec	a
		jp	nz,main.next_line
				; a jp: main.next_line is 180-odd bytes back
		ld	a,(opt_macros)
		or	a
		call	nz,dump_macro	; /M: read it back out and print it
		jp	main.next_line

; A REPT is a macro without a name, expanded on the spot. The count has
; to be worked out BEFORE the body is collected: collect_macro's loop
; overwrites body_fields, and line_fields describes the REPT line only until
; the next next_source_line.

main.rept:	call	define_label	; "lrpt: rept 2" names the place the
					;   first round will start at, which
					;   is where M80 puts it
		ld	de,(line_fields+FIELD_OPERAND)
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		call	eval_absolute	; HL = how many times: absolute only
		ld	(repeat_count),hl
		ld	de,line_buffer	; the REPT line, for the same reason
		ld	a,(source_line_length)	;   the MACRO line above
		call	list_body_line
		ld	hl,line_buffer
				; no IX: collect_block takes no name and no
		ld	a,MACRO_IS_REPT	; parameters, so it never looks at the
		call	collect_block	; field block. the IRP will, and can
					; pass it then
					; HL -> the descriptor's far pointer
		ld	bc,(repeat_count)
		call	expand_start_repeat
					; its body is now the line source
		jp	main.next_line	; the REPT line is not written out

; IRP and IRPC are a REPT with a parameter. The operand is "dummy,items",
; so the comma has to be found first: the left half becomes parameter 0
; and the right half becomes the item list.
;
; The item block is built BEFORE the body is collected, because the items
; are in line_buffer and collect_block is about to reuse line_buffer for every
; body line it reads. Cutting FIELD_OPERAND_LENGTH short at the comma is what
; makes split_parameters read one name and stop.

main.irpc:	ld	a,MACRO_IS_IRPC
		jr	main.irp_both
main.irp:	ld	a,MACRO_IS_IRP
main.irp_both:	ld	(irp_kind),a
		call	define_label	; as REPT above, and for both of them:
					;   main.irp_both is below the two
					;   entry points and above the dummy
					;   scan, which reads line_fields again
					;   anyway

		ld	hl,(line_fields+FIELD_OPERAND)
					; find the dummy's comma
		ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		ld	b,a
		ld	c,0		; C = characters before it
main.irp_find_comma:
		ld	a,b
		or	a
		jp	z,error_bad_parameter_list
					; no comma: there is no dummy, so the
					; operand is not a parameter list
		ld	a,(hl)
		cp	","
		jr	z,main.irp_after_comma
		inc	hl
		dec	b
		inc	c
		jr	main.irp_find_comma

main.irp_after_comma:
		inc	hl		; over the comma: HL -> the items,
		dec	b		; B = how many characters of them
		ld	a,c
		; the operand is now the dummy
		ld	(line_fields+FIELD_OPERAND_LENGTH),a

		ld	a,b		; one level of <> comes off if it is
		or	a		; there. IRPC's are optional and IRP's
		jr	z,main.irp_build
					; are required, so taking them off the
		ld	a,(hl)		; same way costs nothing and accepts
		cp	"<"		; both
		jr	nz,main.irp_build
		inc	hl
		dec	b
		jr	z,main.irp_build	; "<" and nothing else
		push	hl		; is the last character the ">"?
		ld	e,b
		ld	d,0
		add	hl,de
		dec	hl
		ld	a,(hl)
		pop	hl
		cp	">"
		jr	nz,main.irp_build
		dec	b		; yes: leave it out

main.irp_build:	ex	de,hl		; DE -> the items, A = how many,
		ld	a,b		; C = which of the two kinds
		ld	hl,irp_kind
		ld	c,(hl)
		call	build_item_block
					; the block, while line_buffer still
					; holds
		ld	(irp_iterations),bc	; the text. BC = iterations

		ld	de,line_buffer	; the IRP or IRPC line itself, before
		ld	a,(source_line_length)	;   its body
		call	list_body_line
		ld	hl,line_buffer	; collect the body, with the dummy as
		ld	ix,line_fields	; parameter 0
		ld	a,(irp_kind)
		call	collect_block	; HL -> the descriptor's far pointer

		ld	bc,(irp_iterations)
		call	expand_start_repeat
					; its body is now the line source
		jp	main.next_line	; the IRP line is not written out

; EXITM abandons the expansion on top of the stack, including any rounds
; of a REPT that have not run yet, and unwinds every conditional that
; expansion had opened. The line itself is not written out.
;
; It sits after the cond_line call above, like every other directive, so an
; EXITM inside a branch that is not being taken is swallowed rather than
; obeyed.

main.exitm:	call	define_label
				; FIRST: expand_exit does not return when
		call	expand_exit	;   no expansion is open, and the
		jp	main.next_line	;   label is M80's whether or not
					;   this one is the stray kind

; A form feed. The page breaks BEFORE the line is listed - the opposite
; of PAGE, whose note listing_eject leaves is read after - and then the line
; itself is listed with a length of zero, which is M80's empty line at
; the top of the new page. list_body_line is the routine that lists text with
; no address column, and zero characters of text is an empty line.
;
; Nothing else happens to it: no fields, no label, no bytes, and the
; object file never hears of it.

main.form_feed:	call	listing_form_feed
		ld	de,line_buffer
		xor	a
		call	list_body_line
		jp	main.next_line

; next_source_line has already closed and removed every source, so there is
; nothing left to pop here. Report what was done, on the screen either way.

main.pass_done:	call	cond_eof	; an IF left open at the end of the
					; source is an error, not a shrug
		ld	a,(pass_number)
		cp	2
		jr	z,main.finish

		ld	a,2		; round again. The object file is
		ld	(pass_number),a	; created only NOW: making it before
		call	open_output	; the source has been read once would
		call	object_open	; truncate a file the user already had
		jp	c,main.cannot_create	; on a source that cannot be
		call	write_tables	; assembled at all
		jp	main.start_pass

main.finish:	call	check_pass2_labels
					; a label pass 1 defined and pass 2
					;   did not. BEFORE object_finish: an
					;   object file short of a routine
					;   should not be finished and closed
		call	object_finish
		call	list_last_page	; the listing's last page: Macros:
		call	close_output	;   and Symbols:, then the file
		ld	a,(opt_symbols)	; /S: the symbol table, before the
		or	a		; summary line, so the summary is
		call	nz,dump_symbols	; still the last thing on the screen
		ld	a,(opt_quiet)	; /Q: no summary line either. It is
		or	a		;   a report and not output, and a
		jr	nz,main.no_summary	;   batch file wants neither
		ld	de,msg_ended_at	; "ended at FILE(line)", in the
		call	print_dollar_string
					;   notation the errors use. NOT
		ld	a,(current_file)
					;   "N lines": the number is where
		call	get_filename	;   END was, and END inside an
		call	print_zero_string_upper
					;   include ends every file above
		ld	de,msg_line_open
					;   it, so the file named here is
		call	print_dollar_string
					;   where the assembly stopped and
		ld	hl,(current_line)
					;   not always the one you typed
		call	print_decimal
		ld	de,msg_line_close
		call	print_dollar_string
main.no_summary:
		ld	a,(opt_hex_block)
		or	a
		call	nz,main.heap_report
		jp	dos_exit

; /H - how many heap blocks are still allocated. NOT zero in a correct
; run: every macro's descriptor and body are still there, and should be.
; The number is only useful compared against another run - see HEAP1.AS
; and HEAP2.AS in the tests, which differ only in how many times the same
; macro is expanded and print the same figure.
;
; THAT HOLDS ONLY FOR A MACRO THAT DEFINES NO SYMBOLS, which is what
; those two are: a REPT of "db a,b" and no LOCAL. hash.as calls halloc
; once per record, so EVERY SYMBOL IS A BLOCK, and a LOCAL name becomes
; one symbol per expansion - ??0000, ??0001, ??0002 - which live to the
; end of the assembly because pass 2, forward references and the
; listing's last page all need them. Three expansions of a macro with a
; LOCAL therefore leave two more blocks than one expansion does, and
; nothing is leaking. Issue #19, which is why this paragraph exists.

main.heap_report:
		ld	de,msg_heap_prefix
		call	print_dollar_string
		ld	hl,(blocks_out)
		call	print_decimal
		ld	de,msg_heap_blocks
		call	print_dollar_string
		ret

; --- INCLUDE

; open_include - act on an INCLUDE line: open the named file and make it the
;   source that lines now come from.
;
;   The name is zero-terminated where it lies, on top of whatever followed
;   it in the line buffer. That is safe because an INCLUDE line is never
;   written out, and the buffer is overwritten by the next line anyway -
;   so no buffer of its own is needed for the name. push_file copies the
;   name into the file-name table before it returns, which is what makes
;   this survive the next next_source_line.
;
;   source_open AND NOT push_file: the name is looked for in the
;   including file's directory, then the current directory, then the
;   TATARA path. The top-level source still goes straight to push_file,
;   because a file the user typed is not searched for.
;
; Input:	line_fields holds the split line
; Output:	CY clear = the file is open and on top of the stack
;		CY set   = MSX-DOS would not open it
;		(no filename at all does not return - error_include_no_file
;		stops)
; Modifies:	AF, BC, DE, HL, IX

open_include:	ld	a,(line_fields+FIELD_OPERAND_LENGTH)
		or	a
		jp	z,error_include_no_file	; INCLUDE with nothing after it
		ld	hl,(line_fields+FIELD_OPERAND)
		ld	e,a
		ld	d,0
		add	hl,de		; HL -> just past the last character
		ld	(hl),0		; terminate the name where it lies
		ld	de,(line_fields+FIELD_OPERAND)
		jp	source_open	; CY set = found in none of the
					;   places it looks

; --- the /F dump: what split_line made of this line

; dump_line_fields - one line of the dump: the four fields in brackers, then
; the directive number, then where the line came from.
;
;     [start][ld][hl,msg][; go][00][00:0001]
;                              |    |  |
;                              |    |  +-- line number, hexadecimal
;                              |    +----- file number
;                              +---------- directive number, 00 = none
;
;   The origin is here so that the include chain can be checked by eye:
;   without it there is no way to see that each file keeps its own line
;   numbering.
;
; Input: line_fields holds the split line, directive_number the directive
; number
; Output:	one line is written
; Modifies:	AF, BC, DE, HL

dump_line_fields:
		ld	hl,line_fields+FIELD_LABEL
		call	write_field
		ld	hl,line_fields+FIELD_OPERATION
		call	write_field
		ld	hl,line_fields+FIELD_OPERAND
		call	write_field
		ld	hl,line_fields+FIELD_COMMENT
		call	write_field

		ld	de,msg_field_open	; the directive number
		ld	a,1
		call	write_output
		ld	a,(directive_number)
		call	write_hex_byte
		ld	de,msg_field_close
		ld	a,1
		call	write_output

		ld	de,msg_field_open	; where the line came from
		ld	a,1
		call	write_output
		ld	a,(current_file)
		call	write_hex_byte
		ld	de,msg_field_colon
		ld	a,1
		call	write_output
		ld	hl,(current_line)
					; current_line is external here, so the
		push	hl		; two bytes are fetched together
		ld	a,h		; rather than as current_line+1
		call	write_hex_byte
		pop	hl
		ld	a,l
		call	write_hex_byte
		ld	de,msg_field_close
		ld	a,1
		call	write_output

		ld	de,msg_field_crlf
		ld	a,2
		jp	write_output

; write_field - write one field in brackets: "[", the text, "]".
;   A field of length 0 prints as "[]", because write_output writes nothing
;   when asked for nothing.
;
; Input:	HL -> a field entry: address (2 bytes), then length (1)
; Output:	the field is written
; Modifies:	AF, BC, DE, HL

write_field:	ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)		; A = the length, DE -> the text
		push	de
		push	af
		ld	de,msg_field_open
		ld	a,1
		call	write_output
		pop	af
		pop	de
		call	write_output	; the field itself
		ld	de,msg_field_close
		ld	a,1
		jp	write_output

; write_hex_byte - write A as two hexadecimal digits, wherever output goes.
;   print_decimal (msxdos.as) prints straight to the screen, which is no use
;   when the output is a file, so the field dump uses this instead.
;
; Input:	A = the byte
; Output:	two characters are written
; Modifies:	AF, BC, DE, HL

write_hex_byte:	push	af
		rrca			; rrca, not rra: rra would rotate the
		rrca			; carry flag in through the top
		rrca
		rrca
		call	write_hex_byte.nibble	; the high nibble
		ld	(hex_digits),a
		pop	af
		call	write_hex_byte.nibble	; the low one
		ld	(hex_digits+1),a
		ld	de,hex_digits
		ld	a,2
		jp	write_output
write_hex_byte.nibble:
		and	00fh
		add	a,"0"
		cp	"9"+1
		ret	c		; 0-9
		add	a,"A"-"9"-1	; A-F
		ret

; --- the output end

; open_output - decide where output goes and get it ready.
;
;   MSX-DOS2 gives the screen a file handle of its own, so /P needs no
;   separate printing path: everything goes through _WRITE either way.
;
; Input:	opt_screen, object_name (from parse_command_line)
; Output:	CY clear = output_handle is ready to be written to
;		CY set   = the output file could not be created
; Modifies:	AF, BC, DE, HL

open_output:	ld	a,STDOUT	; no listing file named: the text goes
		ld	(output_handle),a
					;   to the screen, and main.emit_line
		ld	a,(listing_name)	;   decides whether there is
		or	a		;   any
		ret	z		; CY is clear: STDOUT is 1
		ld	de,listing_name
		xor	a		; mode 0 = read and write
		ld	b,a		; attributes 0 = an ordinary file
		system	_CREATE		; -> A = error, B = the handle
		or	a
		scf
		ret	nz		; main.cannot_create says so. This
		ld	a,b		;   path unreachable; it is given
		ld	(output_handle),a	;   something to create again
		or	a
		ret

; close_output - close the output file. The screen's handle is not ours to
;   close, so leave it alone.
;
; Input:	nothing
; Output:	the file is closed
; Modifies:	AF, BC, DE, HL

close_output:	ld	a,(output_handle)
		cp	STDOUT
		ret	z
		ld	b,a
		system	_CLOSE
		ret

; same_name - are the two filenames the same as typed?
;
;   MSX-DOS upper-cases the command tail, so a plain comparison is enough
;   for the ordinary accident. It does not catch "test.as a:test.as": that
;   needs the paths MSX-DOS resolves them to, which is a later refinement.
;
; Input:	nothing (reads source_name and object_name)
; Output:	Z set = the two names are identical
; Modifies:	AF, DE, HL

same_name:	ld	hl,source_name
		ld	de,object_name
same_name.compare:
		ld	a,(de)
		cp	(hl)
		ret	nz		; they differ
		or	a
		ret	z		; both terminators: identical
		inc	hl
		inc	de
		jr	same_name.compare

; --- the ways out

; The include failure is the first message that says WHERE the trouble
; was, not just what it was. current_file and current_line still descuribe the 
; INCLUDE line itself, because nothing was pushed.

main.cannot_open_include:
		ld	de,msg_error_cannot_open
					; the same wording as a bad source
		call	print_dollar_string
					; file, so one message serves both
		ld	de,(line_fields+FIELD_OPERAND)
		call	print_zero_string_upper
					; open_include terminated it in place
		ld	de,msg_include_trail
		call	print_dollar_string
		ld	a,(current_file)
		call	get_filename
		call	print_zero_string_upper
		ld	de,msg_line_open
		call	print_dollar_string
		ld	hl,(current_line)
		call	print_decimal
		ld	de,msg_line_close
		call	print_dollar_string
		call	print_trail	; and the rest of the chain. The
					; failed include was never pushed, so
					; the top of the stack is the file
					; named above - which print_trail
					; skips, exactly as it does for
					; die_with_message
		jp	dos_exit

main.cannot_open:
		ld	de,msg_error_cannot_open
		call	print_dollar_string
		ld	de,source_name
		call	print_zero_string_upper
		ld	de,msg_error_newline
		call	print_dollar_string
		jp	dos_exit

main.cannot_create:
		ld	de,msg_error_cannot_create
		call	print_dollar_string
		ld	de,object_name
		call	print_zero_string_upper
		ld	de,msg_error_newline
		call	print_dollar_string
		jp	dos_exit

main.same_file:	ld	de,msg_same_file
		call	print_dollar_string
		jp	dos_exit

main.usage:	jp	print_usage	; the banner and the screen, in the
					;   module that owns the command line

main.version:	call	print_version_banner	; /V: the banner alone
		jp	dos_exit

main.need_mapper:
		ld	de,msg_need_mapper
		call	print_dollar_string
		jp	dos_exit

main.need_dos2:	ld	de,msg_need_dos2
					; 09h, NOT print_dollar_string:
					; print_dollar_string writes with
		system	_STROUT		;   _WRITE, which is a DOS 2 function,
					;   and this is the one message printed
					;   on a machine that has no DOS 2
		jp	dos_exit

		dseg


line_buffer:	defs	LINE_MAX+3	; one line, its terminator, and room
					; for the CR+LF write_line puts over it
source_line_length:
		defs	1		; how long that line was
line_fields:	defs	FIELD_BLOCK_SIZE	; what split_line made of it
directive_number:
		defs	1	; what find_directive made of its operation
hex_digits:	defs	2	; write_hex_byte builds its two digits here
called_macro:	defs	4		; far pointer: a macro being called
repeat_count:	defs	2		; main.rept: the repeat count, across
					;   the body collection
declare_routine:
		defs	2
			; main.name_list: declare_public or declare_external
end_seen:	defs	1		; 0FFh once an END line has been read
list_false_conditionals:
		defs	1		; 0 once .SFCOND has been seen: the
					;   lines inside a branch that was not
					;   taken stop appearing
					;   Written by the object writer;
					;   nothing reads it before that
irp_kind:	defs	1	; main.irp: MACRO_IS_IRP or MACRO_IS_IRPC
irp_iterations:	defs	2	; how many iterations build_item_block found
data_width:	defs	1		; main.db/main.dw: 1 or 2 bytes per
					;   expression
data_bytes:	defs	2		; the bytes a DB or DW line adds
item_is_string:	defs	1	; measure_data_item: the item was a string on
					;   its own
item_at:	defs	2	; where the item measure_data_item is measuring
					;   began - emit_data_item needs the
					;   text, and measure_data_item only
					;   leaves the end of it
item_length:	defs	1		; and how long it turned out to be

; These four have no "$" on the end: they go through write_output, which is
; told how many bytes to write and never looks for a terminator. Keeping
; them apart from the "$" messages makes a mix-up obvious.

msg_field_open:	defb	"["		; used with write_output, so no "$"
msg_field_close:
		defb	"]"
msg_field_colon:
		defb	":"
msg_field_crlf:	defb	CHR_CR,CHR_LF

msg_ended_at:	defb	"ended at $"
msg_heap_prefix:
		defb	"HEAP: $"
msg_heap_blocks:
		defb	" blocks.",CHR_CR,CHR_LF,"$"
msg_error_newline:
		defb	CHR_CR,CHR_LF,"$"
msg_error_cannot_open:
		defb	"ERROR: cannot open $"
msg_error_cannot_create:
		defb	"ERROR: cannot create $"
msg_include_trail:
		defb	CHR_CR,CHR_LF,"    included from $"
msg_line_open:	defb	"($"
msg_line_close:	defb	")",CHR_CR,CHR_LF,"$"
msg_same_file:	defb	"ERROR: the output file is the input file.",CHR_CR
		defb	CHR_LF,"$"
msg_need_dos2:	defb	"ERROR: Tatara needs MSX-DOS2 or Nextor.",CHR_CR,CHR_LF
		defb	"$"
msg_need_mapper:
		defb	"ERROR: Tatara needs a memory mapper.",CHR_CR
		defb	CHR_LF,"$"
