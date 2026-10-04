; errs.as - error reporting.
;
; print a message and stop. These routines also
; print where the error happened, including the trail through any nested
; macro expansions.

ERRS_INCLUDED	equ	1		; skips the externals in errs.inc

		public	error_unknown_option
		public	error_too_many_filenames
		public	error_source_too_deep
		public	error_too_many_open
		public	error_too_many_sources
		public	error_line_too_long
		public	error_write_failed
		public	error_include_no_file
		public	error_env_too_long
		public	error_macro_not_closed
		public	error_endm_without_macro
		public	error_macro_no_name
		public	error_macro_name_long
		public	error_segment_name_long
		public	error_too_many_parameters
		public	error_out_of_memory
		public	error_macro_line_long
		public	error_local_too_late
		public	error_cond_unmatched
		public	error_cond_not_closed
		public	error_cond_too_deep
		public	error_undefined_symbol
		public	error_bad_expression
		public	error_exitm_outside
		public	error_bad_parameter_list
		public	error_phase
		public	error_pass2_label
		public	error_relocation
		public	error_bad_segment_line
		public	error_segment_differs
		public	error_bad_group_line
		public	error_group_needed
		public	error_bad_name_char
		public	error_index_half_name
		public	error_bad_control_line
		public	error_name_not_label
		public	print_trail	; not an error: the trail printer,
					;   which main.cannot_open_include
					;   needs too
		public	error_too_many_segments
		public	error_already_defined
		public	error_external_here
		public	error_bad_declaration
		public	error_public_undefined
		public	error_bad_data_operand
		public	error_not_a_form
		public	error_unknown_operation
		public	error_bad_page_length
		public	error_emitted_nothing
		public	error_too_many_bytes
		public	error_bad_displacement
		public	error_bad_rst
		public	error_bad_im
		public	error_jump_too_far
		public	error_bad_bit_number

		include	errs.inc
		include	msxdos.inc
		; object_delete: the object file goes with the error - 092
		include	objout.inc
		include	ascii.inc
		; the stack, current_file/current_line, entry_address
		include	srcline.inc
		include	mdt.inc		; the expansion record's fields
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been declared
		include	macros.inc
				; descriptor_name: what is this descriptor
					; called?

		cseg

; Every one of these is three bytes of setup and a jump. They are all
; jp and not jr DELIBERATELY: die_with_message sits below the whole group, so
; the distance from the first of them grows by six bytes every time a
; message is added, and it passed 127. Eight bytes buys a file
; that cannot break that way again - do not "optimise" them back.

; error_unknown_option - "unknown option". Does not return.
error_unknown_option:
		ld	de,msg_unknown_option
		jp	die_with_message

; error_too_many_filenames - "too many filenames." Does not return.
error_too_many_filenames:
		ld	de,msg_too_many_filenames
		jp	die_with_message

; error_source_too_deep - sources nested too deeply. Does not return.
error_source_too_deep:
		ld	de,msg_source_too_deep
		jp	die_with_message

; error_too_many_open - more files open at once than there are buffers. Does
; not return.
error_too_many_open:
		ld	de,msg_too_many_open
		jp	die_with_message

; error_line_too_long - a source line longer than LINE_MAX. Does not return.
error_line_too_long:
		ld	de,msg_line_too_long
		jp	die_with_message

; error_too_many_sources - more different source files than we can remember.
; Does not return.
error_too_many_sources:
		ld	de,msg_too_many_sources
		jp	die_with_message

; error_include_no_file - INCLUDE with no filename after it. Does not return.
error_include_no_file:
		ld	de,msg_include_no_file
		jp	die_with_message

; error_env_too_long - the TATARA environment variable is longer than
; ENV_VALUE_MAX, so _GENV has handed back a truncated value with no terminator.
; A search path that is quietly shorter than what was set is worse than none.
; Does not return.
error_env_too_long:
		ld	de,msg_env_too_long
		jp	die_with_message

; error_macro_not_closed - end of file with a macro definition still open.
; Called with A/HL = the MACRO line, not the end of the source: by the time
; this fires the stack is empty and current_line is useless. Does not return.
error_macro_not_closed:
		ld	de,msg_macro_not_closed
		jp	die_at_position

; error_endm_without_macro - an ENDM with no definition open. Does not return.
error_endm_without_macro:
		ld	de,msg_endm_without_macro
		jp	die_with_message

; error_macro_no_name - a MACRO line with no name in the label field. ONLY
; that: a name too long to keep went here too until 105, which is how a
; 64-character name came to be reported as a missing one. Does not return.
error_macro_no_name:
		ld	de,msg_macro_no_name
		jp	die_with_message

; error_macro_name_long - a macro name longer than MACRO_NAME_MAX. The number
; is in the message because the number is the whole of the complaint, and it is
; the number copy_macro_name enforces: MACRO_NAME_MAX characters, macro_name
; being MACRO_NAME_MAX+1 bytes so that the terminator has somewhere to go. Does
; not return.
error_macro_name_long:
		ld	de,msg_macro_name_long
		jp	die_with_message

; error_too_many_parameters - more formal parameters than we can count. Does
; not return.
error_too_many_parameters:
		ld	de,msg_too_many_parameters
		jp	die_with_message

; error_bad_parameter_list - a formal parameter list that does not parse. Two
; things reach it: an empty name, as in "poke macro addr,,val", and an IRP or
; IRPC whose operand has no comma, which names no dummy. Both used to print
; "too many macro parameters", which is a different complaint and sent the
; reader looking for a limit that was not the problem. Does not return.
error_bad_parameter_list:
		ld	de,msg_bad_parameter_list
		jp	die_with_message

; error_out_of_memory - the mapper ran out of memory. Does not return.
error_out_of_memory:
		ld	de,msg_out_of_memory
		jp	die_with_message

; error_macro_line_long - a macro body line that went past LINE_MAX: at
; definition time because parameter references became markers, or at expansion
; time because an argument was spliced in. Does not return.
error_macro_line_long:
		ld	de,msg_macro_line_long
		jp	die_with_message

; error_write_failed - the output file could not be written. Does not return.
error_write_failed:
		ld	de,msg_write_failed
		jp	die_with_message

; error_local_too_late - a LOCAL line after body lines have already been
; stored. The lines already stored have no marker for the name, so it would be
; substituted on some lines and not others. Does not return.
error_local_too_late:
		ld	de,msg_local_too_late
		jp	die_with_message

; error_cond_unmatched - an ELSE or ENDIF with no IF open, or a second ELSE for
; the same IF. One message for all three, because the line number will say
; which one it was and three messages is 120 bytes. Does not return.
error_cond_unmatched:
		ld	de,msg_cond_unmatched
		jp	die_with_message

; error_cond_not_closed - the source ended with a conditional still open. M80
; calls this "Unterminated conditional". Does not return.
error_cond_not_closed:
		ld	de,msg_cond_not_closed
		jp	die_at_position	; A/HL = the outermost conditional
					; still open, from cond_eof

; error_cond_too_deep - conditionals nested deeper than COND_MAX_DEPTH. M80
; allows any depth;
; ours costs a byte of ordinary RAM per level and needs a guard, or it
; writes past the end of cond_stack. Does not return.
error_cond_too_deep:
		ld	de,msg_cond_too_deep
		jp	die_with_message

; error_undefined_symbol - a name in an expression that nothing has defined.
; M80 calls this a V error; the manual requires an IF's operand to involve
; values "which were previously defined". Does not return.
error_undefined_symbol:
		ld	de,msg_undefined_symbol
		jp	die_with_message

; error_bad_expression - an expression that does not parse. Does not return.
error_bad_expression:
		ld	de,msg_bad_expression
		jp	die_with_message

; error_exitm_outside - EXITM where there is no expansion to leave. Does not
; return.
error_exitm_outside:
		ld	de,msg_exitm_outside
		jp	die_with_message

; error_phase - a label whose value on pass 2 disagrees with the value it
; had on pass 1. M80 calls this a P error. It means the two readings of
; the source assembled different programs, and everything after the
; label is wrong by the difference. The FILE(line) prefix names the
; label's own line. Does not return.
error_phase:	ld	de,msg_phase
		jp	die_with_message

; error_pass2_label - a label that the FIRST reading of the source defined and
; the second did not: a conditional - an IFDEF or IFNDEF guard, all but
; always - was true on pass 1 and false on pass 2, so the block was
; skipped and its bytes were never emitted, while everything that
; referred to the label still points where pass 1 put it. M80 prints
; nothing and writes the short program; check_pass2_labels's comment says why
; we do not. Called with A/HL = the label's own line, like
; error_macro_not_closed: this fires at the end of pass 2, where current_line
; is the END line. Does not return.
error_pass2_label:
		ld	de,msg_pass2_label
		jp	die_at_position

; error_relocation - a relocatable value used where only an absolute one makes
; sense: multiplied, compared, HIGH/LOW, added to another relocatable,
; subtracted from one in a different segment, or given to DS, REPT or an
; ORG in another segment. The linker would have to know the segment's
; address to get the answer, and nobody does yet. M80 calls this an R
; error. Does not return.
error_relocation:
		ld	de,msg_relocation
		jp	die_with_message

; error_bad_segment_line - an ASEG, CSEG or DSEG line that does not parse: an
; operand on ASEG, TRANSIENT on a CSEG, or a word after the comma that is not
; TRANSIENT. THREE conditions, and the message names the three directives they
; can appear on. A name longer than SEGMENT_NAME_MAX was a fourth until 105 -
; and it can arrive from a GROUP line, which is how this message came to answer
; one. Does not return.
error_bad_segment_line:
		ld  de,msg_bad_segment_line
		jp  die_with_message

; error_segment_name_long - a segment or group name longer than
; SEGMENT_NAME_MAX. One message for both, because it is one limit: seg_key
; holds the group's number and then the name, and select_contribution and
; group_directive measure the same sixteen bytes. Does not return.
error_segment_name_long:
		ld	de,msg_segment_name_long
		jp	die_with_message

; error_segment_differs - the same segment name, declared differently: "cseg
; foo" and then "dseg foo", or with and without TRANSIENT. The linker calls
; that a mismatch too (tatara-obj-spec.md, SEGDEF). Does not return.
error_segment_differs:
		ld  de,msg_segment_differs
		jp  die_with_message

; error_bad_group_line - a GROUP line that cannot mean anything: outside a
; transient DSEG, without a name, or with a label in front of it. Does not
; return.
error_bad_group_line:
		ld  de,msg_bad_group_line
		jp  die_with_message

; error_name_not_label - EQU, DEFL or MACRO with a colon after the name. A
; colon makes the label field a location label (M80 2.3.1), and these three
; take a name - so the pseudo-op is left with nothing to name. M80 calls it an
; O error and does not open a macro it refuses. Does not return.
error_name_not_label:
		ld	de,msg_name_not_label
		jp	die_with_message

; error_bad_name_char - a label holding a character that a name may not hold.
; M80 answers these with a U and stops. Does not return.
error_bad_name_char:
		ld	de,msg_bad_name_char
		jp	die_with_message

; error_index_half_name - a symbol called IXH, IXL, IYH or IYL. They were legal
; M80 names and are registers from 104 onwards, and a source that used one as a
; label would otherwise change its bytes without saying so. Does not return.
error_index_half_name:
		ld	de,msg_index_half_name
		jp	die_with_message

; error_bad_control_line - a column-1 word beginning with * or $ that is not
; one of the two control lines we have. M80 has *EJECT and *TITLE (and $ for
; both); *TITLE is SUBTTL with a quoted operand inside brackets, which would
; have to be read before split_line cuts the line at the space in it - so the
; message names what there IS. Does not return.
error_bad_control_line:
		ld	de,msg_bad_control_line
		jp	die_with_message

; error_group_needed - a label, DS or ORG inside a transient DSEG before any
; GROUP line. Its variables would belong to no group, and a group is the only
; thing that says what may overlay what. Does not return.
error_group_needed:
		ld  de,msg_group_needed
		jp  die_with_message

; error_too_many_segments - more segments or groups than an index byte holds. A
; segment index is one byte because it rides in every symbol's SYMBOL_TYPE.
; Does not return.
error_too_many_segments:
		ld  de,msg_too_many_segments
		jp  die_with_message

; error_already_defined - a name defined twice: two labels, two EQUs with
; different values, an EQU and a SET, or a name that EXTRN gave to another
; module and this one defines. M80 calls it an M error. The pass-2 case is a
; phase error instead, because there the SAME line answered differently. Does
; not return.
error_already_defined:
		ld	de,msg_already_defined
		jp	die_with_message

; error_external_here - an external symbol where M80 2.4.3 does not allow one:
; multiplied or compared, two in one expression, or given to EQU, DS or
; ORG. An external is a promise to be kept by the linker, and the only
; arithmetic that survives being kept is adding or subtracting a plain
; number. Does not return.
error_external_here:
		ld	de,msg_external_here
		jp	die_with_message

; error_bad_declaration - a PUBLIC or EXTRN list that does not parse: an empty
; name, or a name longer than a symbol may be. Does not return.
error_bad_declaration:
		ld	de,msg_bad_declaration
		jp	die_with_message

; error_public_undefined - PUBLIC promised a symbol that nothing in this module
; ever defined. It fires at the END OF PASS 1, while the PUBDEF records are
; written, because that is the first moment the whole module is known. The
; alternative is an object file that offers a name it has no value for, and a
; link that fails one file away from the cause. M80 calls it a U error. Does
; not return.
error_public_undefined:
		ld	de,msg_public_undefined
		jp	die_with_message

; error_bad_data_operand - a DB, DW or DC operand that cannot be measured: an
; item with nothing in it, a line that ends inside a string, a string of three
; or more characters in a DW, or a DC that is not given exactly one non-empty
; string. It is deliberately NOT error_bad_expression: nothing about "dc ''" is
; a bad expression, and pass 1 does not read expressions at all. Does not
; return.
error_bad_data_operand:
		ld	de,msg_bad_data_operand
		jp	die_with_message

; error_not_a_form - the operands on this line are not a form this instruction
; has: "and bc", "adc ix,bc", or anything at all left over after a
; complete instruction. It says "form" rather than "operand" because the
; operands may each be perfectly good and still not go together - "ld
; (bc),hl" is two legal operands and no instruction. Does not return.
error_not_a_form:
		ld	de,msg_not_a_form
		jp	die_with_message

; error_unknown_operation - the operation on this line is not a directive, not
; a macro and not an instruction. A DELIBERATE DEPARTURE FROM M80: 2.3.1 of the
; manual says that an operation which is none of those is treated "as if it
; were a DB statement", so a mistyped "xro a" assembles as one byte of data
; there and the program breaks somewhere else entirely. Same judgement as the
; second-label error and for the same reason - a silent wrong answer costs more
; than an incompatibility nobody relies on deliberately. Does not return.
error_unknown_operation:
		ld	de,msg_unknown_operation
		jp	die_with_message

; error_bad_page_length - PAGE was given a length outside 10 to 255. M80 marks
; the line with an A and counts it as fatal, which PAGEDIR.AS shows, so the
; value is not quietly ignored. Does not return.

error_bad_page_length:
		ld	de,msg_bad_page_length
		jp	die_with_message

; error_emitted_nothing - a class handler returned without emitting anything.
; NO Z80 INSTRUCTION IS ZERO BYTES LONG, so this is a handler that took a path
; where it should have called emit_byte and did not - and without this check
; the symptom is every address below the line being wrong, in a file that
; assembled without a word.
;
; INTERNAL: it cannot be provoked from source, and no test can reach
; it. It is here for the mnemonic somebody adds in a year, which is
; exactly when nobody will be looking. Does not return.
error_emitted_nothing:
		ld	de,msg_emitted_nothing
		jp	die_with_message

; error_too_many_bytes - a line emitted more bytes than emitted_bytes keeps. It
; was decided the buffer could be one line's worth and no more, and proved that
; a line's worst case is "dw 1,1,1..." across a full operand field: 128 items,
; 256 bytes, which is EMIT_MAX exactly. That was safe while the buffer only fed
; the LISTING - past the end, a cosmetic column lost its tail. The buffer is
; what goes into the object file, so the same overflow would write a program
; with bytes missing from the middle. The proof still holds; this is the
; assertion that says so. Does not return.
error_too_many_bytes:
		ld	de,msg_too_many_bytes
		jp	die_with_message

; error_bad_displacement - an index displacement outside -128 to 127. The byte
; is SIGNED and there is nowhere else for the value to go. Every indexed
; instruction reaches its displacement through emit_displacement, so one test
; there covers all of them. Does not return.
error_bad_displacement:
		ld	de,msg_bad_displacement
		jp	die_with_message

; error_bad_rst - an RST operand that is not one of 0, 8, 10h, 18h, 20h, 28h,
; 30h, 38h. The operand IS the opcode - 0C7h + n - so anything else
; would encode as some other instruction entirely. Does not return.
error_bad_rst:	ld	de,msg_bad_rst
		jp	die_with_message

; error_bad_im - an IM operand that is not 0, 1 or 2. The three encode as
; 46h, 56h and 5Eh, which is not an arithmetic progression, so there
; is nothing to extend it to. Does not return.
error_bad_im:	ld	de,msg_bad_im
		jp	die_with_message

; error_jump_too_far - a JR or DJNZ displacement that does not fit a signed
; byte. The target is more than 127 bytes forward or 128 back OF THE ADDRESS
; AFTER THE INSTRUCTION, and JR has no long form to fall back on: M80 says so
; too, rather than quietly assembling a JP. Does not return.
error_jump_too_far:
		ld	de,msg_jump_too_far
		jp	die_with_message

; error_bad_bit_number - a bit number that is not 0 to 7. The number is part of
; the opcode - 40h + 8*b - so an eighth bit would encode as some other
; instruction entirely, exactly as RST's operand does. Does not return.
error_bad_bit_number:
		ld	de,msg_bad_bit_number
		jp	die_with_message

; die_with_message - print the $-terminated message in DE, with where it
; happened and how we got there, and terminate.
;
;   die_at_position is the same with the position given rather than taken from
;   current_file/current_line. Two errors need it: a definition and a
;   conditional that are never closed both fire at the end of the source, by
;   which time current_line points at the last line of the file rather than at
;   the line that opened the thing.
;
;   A line of 0 means no position is known - a command-line error,
;   before any file is open. Line numbers are 1-based, so 0 is free to
;   mean it.
;
; Input:	DE -> message
;		die_at_position also: A = file number, HL = line
; Output:	does not return
; Modifies:	everything

die_with_message:
		ld	a,(current_file)
		ld	hl,(current_line)

die_at_position:
		ld	(error_file),a
		ld	(error_line),hl
		ld	(error_message),de

		ld	hl,(error_line)	; anything open at all?
		ld	a,h
		or	l
		jr	z,die_with_message.message
					; no: the message on its own

		ld	a,(error_file)	; FILE(line):
		call	get_filename
		call	print_zero_string_upper
		ld	de,msg_open_paren
		call	print_zero_string
		ld	hl,(error_line)
		call	print_decimal
		ld	de,msg_close_colon
		call	print_zero_string

die_with_message.message:
		ld	de,msg_error_prefix
					; THE ONE COPY. Sixty-four messages
		call	print_zero_string
					;   carried these seven bytes each
		ld	de,(error_message)	;
		call	print_dollar_string
		call	print_trail
		call	object_delete	; AND THE OBJECT FILE GOES WITH IT.
					;   It was created at the start of
					;   pass 2 and is part written; a
					;   half-built object with the right
					;   name is the one thing here that
					;   another program will read. Issue
					;   #22, and object_delete's own
					;   comment for why a file this run did
					;   not create is safe
		jp	dos_exit

; print_trail - print how we got here: one line per macro expansion on the
;   line source stack, innermost first.
;
;   The stack IS the origin chain. A source is pushed when it starts
;   and popped only when it runs out, so at this instant every level
;   that led to the error is still there, in order.
;
;   A FILE LEVEL PRINTS WHEN THE LEVEL ABOVE IT IS ANOTHER FILE LEVEL.
;   When a macro sits above it, that macro has already named this file
;   and this line as its call site, and saying it twice helps nobody -
;   which is what the old rule said, correctly, about that one case and
;   wrongly about every other. An include is not a call and nothing else
;   prints one, so a chain of includes needs these lines or it is
;   invisible.
;
;   The topmost level needs no test: trail_above_kind starts as
;   SOURCE_IS_MACRO, so a file there says nothing, and die_with_message has
;   already named it.
;
;   THE PAGE 2 RULE, per level: read the record, read MACRO_KIND, and get
;   the name - all into ordinary RAM - and only then print anything.
;   Printing goes through _CONOUT and _STROUT, which hand page 2 back
;   to MSX-DOS.
;
; Input:	nothing
; Output:	the trail is printed
; Modifies:	everything

		; nothing sits above the topmost
print_trail:	ld	a,SOURCE_IS_MACRO
		ld	(trail_above_kind),a
					;   level, and a file there is the
					;   one die_with_message has already
					;   named
		ld	a,(source_depth)
		or	a
		ret	z		; nothing stacked: no trail

print_trail.level:
		dec	a
		ld	(trail_index),a
		call	entry_address	; HL -> that entry
		push	hl
		pop	ix
		ld	a,(ix+SOURCE_KIND)
		ld	(trail_this_kind),a	; kept: printing destroys IX
		cp	SOURCE_IS_MACRO
		jr	nz,print_trail.file_level

		push	ix		; the record: which descriptor, and
		pop	hl		; where the call was
		ld	de,SOURCE_EXPANSION
		add	hl,de
		call	deref
		ld	de,EXPANSION_DESCRIPTOR
		add	hl,de
		fpsave	trail_descriptor
					; fpsave leaves HL at EXPANSION_BLOCK
		ld	de,EXPANSION_CALL_FILE-EXPANSION_BLOCK
		add	hl,de
		ld	a,(hl)
		ld	(trail_call_file),a	; EXPANSION_CALL_FILE
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(trail_call_line),de	; EXPANSION_CALL_LINE

		derefp	trail_descriptor
					; MACRO_KIND, while we still can
		ld	a,(hl)
		ld	(trail_macro_kind),a

		ld	hl,trail_descriptor
					; and the name, before anything is
		call	descriptor_name	; printed. CY clear = DE -> the name
		jr	nc,print_trail.print_macro

		ld	de,msg_repeat_block	; no name: which sort is it?
		ld	a,(trail_macro_kind)
		or	a
		jr	nz,print_trail.print_macro
					; not MACRO_IS_MACRO: a repeat block
		ld	de,msg_redefined_macro
					; a macro, but nothing names it now

print_trail.print_macro:
		push	de
		ld	de,msg_in
		call	print_zero_string
		pop	de
		call	print_zero_string
		ld	de,msg_called_from
		call	print_zero_string
		ld	a,(trail_call_file)
		call	get_filename
		call	print_zero_string_upper
		ld	de,msg_open_paren
		call	print_zero_string
		ld	hl,(trail_call_line)
		call	print_decimal
		ld	de,msg_close_eol
		call	print_zero_string
		jr	print_trail.next_level
					; NOT a fall-through: the file branch
					;   sits between this and
					;   print_trail.next_level, and a macro
					;   level must not reach it

; A file level. SOURCE_FILE_NUMBER and SOURCE_LINE are bytes of the entry
; itself, in ordinary RAM, so there is no page 2 rule to keep here - only the
; macro path needs one, for the far pointer at SOURCE_EXPANSION.

print_trail.file_level:
		ld	a,(trail_above_kind)
		or	a
		jr	nz,print_trail.next_level
					; a macro above has already named
					;   this file and this line
		ld	a,(ix+SOURCE_FILE_NUMBER)
		ld	(trail_call_file),a
		; the line it last handed over, which
		ld	l,(ix+SOURCE_LINE)
		ld	h,(ix+SOURCE_LINE+1); is the INCLUDE that suspended it
		ld	(trail_call_line),hl
		ld	de,msg_included_from
		call	print_zero_string
		ld	a,(trail_call_file)
		call	get_filename
		call	print_zero_string_upper
		ld	de,msg_open_paren
		call	print_zero_string
		ld	hl,(trail_call_line)
		call	print_decimal
		ld	de,msg_close_eol
		call	print_zero_string

print_trail.next_level:
		ld	a,(trail_this_kind)
					; the level below asks what this one
		ld	(trail_above_kind),a	;   was
		ld	a,(trail_index)
		or	a
		jp	nz,print_trail.level
					; a jp, not a jr: the loop body prints
					; a whole trail line and is far past
					; 127 bytes
		ret

		dseg

; The seven below are ZERO-terminated, not $-terminated, because they
; go through print_zero_string rather than _STROUT: they are interleaved with
; filenames and numbers that BDOS 09h cannot help with. The msg_*
; error texts keep the "$". macro_name, which descriptor_name fills, is
; zero-terminated for the same reason.

msg_open_paren:	defb	"(",0
msg_close_colon:
		defb	"): ",0
msg_close_eol:	defb	")",CHR_CR,CHR_LF,0
msg_in:		defb	"    in ",0
msg_called_from:
		defb	", called from ",0
msg_included_from:
		defb	"    included from ",0
msg_repeat_block:
		defb	"a repeat block",0
msg_redefined_macro:
		defb	"a redefined macro",0

error_file:	defs	1	; die_with_message: where the error was
error_line:	defs	2	;   (a line of 0 = nowhere yet)
error_message:	defs	2	; the message, across the position printing
trail_index:	defs	1	; print_trail: which stack entry
trail_descriptor:
		defs	4	; far pointer: this level's descriptor
trail_call_file:
		defs	1	; print_trail: where this level was called from
trail_call_line:
		defs	2
trail_macro_kind:
		defs	1
			; print_trail: MACRO_KIND, for the unnamed cases
trail_this_kind:
		defs	1	; print_trail: this level's SOURCE_KIND
trail_above_kind:
		defs	1
			; print_trail: the level above this one's, which
				;   is what decides whether a file level
				;   prints at all

msg_error_prefix:
		defb	"ERROR: ",0
				; printed by die_with_message.message, so no
				;   message below says it
msg_unknown_option:
		defb	"unknown option.",CHR_CR,CHR_LF,"$"
msg_too_many_filenames:
		defb	"too many filenames.",CHR_CR,CHR_LF,"$"
msg_source_too_deep:
		defb	"sources nested too deeply.",CHR_CR
		defb	CHR_LF,"$"
msg_too_many_open:
		defb	"too many source files open at once.",CHR_CR
		defb	CHR_LF,"$"
msg_line_too_long:
		defb	"source line too long.",CHR_CR,CHR_LF,"$"
msg_too_many_sources:
		defb	"too many different source files.",CHR_CR
		defb	CHR_LF,"$"
msg_write_failed:
		defb	"cannot write to the output file.",CHR_CR
		defb	CHR_LF,"$"
msg_include_no_file:
		defb	"INCLUDE without a filename.",CHR_CR
		defb	CHR_LF,"$"
msg_env_too_long:
		defb	"the TATARA variable is too long.",CHR_CR
		defb	CHR_LF,"$"
msg_macro_not_closed:
		defb	"macro definition not closed by ENDM.",CHR_CR
		defb	CHR_LF,"$"
msg_endm_without_macro:
		defb	"ENDM without a macro definition.",CHR_CR
		defb	CHR_LF,"$"
msg_macro_no_name:
		defb	"MACRO without a name.",CHR_CR,CHR_LF,"$"
msg_macro_name_long:
		defb	"a macro name may be at most 64"
		defb	" characters.",CHR_CR,CHR_LF,"$"
msg_segment_name_long:
		defb	"a segment or group name may be at most"
		defb	" 16 characters.",CHR_CR,CHR_LF,"$"
msg_too_many_parameters:
		defb	"too many macro parameters.",CHR_CR,CHR_LF,"$"
msg_bad_parameter_list:
		defb	"bad macro parameter list.",CHR_CR,CHR_LF,"$"
msg_out_of_memory:
		defb	"out of mapper memory.",CHR_CR,CHR_LF,"$"
msg_macro_line_long:
		defb	"macro line too long.",CHR_CR
		defb	CHR_LF,"$"
msg_local_too_late:
		defb	"LOCAL must come before the macro body.",CHR_CR
		defb	CHR_LF,"$"
msg_cond_unmatched:
		defb	"ELSE or ENDIF without a matching IF.",CHR_CR
		defb	CHR_LF,"$"
msg_cond_not_closed:
		defb	"conditional not closed by ENDIF.",CHR_CR
		defb	CHR_LF,"$"
msg_cond_too_deep:
		defb	"conditionals nested too deeply.",CHR_CR
		defb	CHR_LF,"$"
msg_undefined_symbol:
		defb	"undefined symbol in an expression.",CHR_CR
		defb	CHR_LF,"$"
msg_bad_expression:
		defb	"bad expression.",CHR_CR
		defb	CHR_LF,"$"
msg_exitm_outside:
		defb	"EXITM outside a macro or repeat block.",CHR_CR
		defb	CHR_LF,"$"
msg_phase:	defb	"phase error - this label had a different"
		defb	" value on pass 1.",CHR_CR,CHR_LF,"$"
msg_pass2_label:
		defb	"this label was defined on pass 1 and not"
		defb	" on pass 2 - a conditional skipped it."
		defb	CHR_CR,CHR_LF,"$"
msg_relocation:	defb	"relocation error - a segment-relative"
		defb	" value is not allowed here.",CHR_CR,CHR_LF,"$"
msg_bad_segment_line:
		defb	"bad ASEG, CSEG or DSEG line.",CHR_CR
		defb	CHR_LF,"$"
msg_segment_differs:
		defb	"this segment was declared differently"
		defb	" before.",CHR_CR,CHR_LF,"$"
msg_bad_group_line:
		defb	"GROUP needs a name, no label, and a"
		defb	" transient DSEG.",CHR_CR,CHR_LF,"$"
msg_bad_control_line:
		defb	"only *EJECT and its dollar spelling are"
		defb	" control lines.",CHR_CR,CHR_LF,"$"
					; NO "$" IN THE TEXT: die_with_message
					; prints with BDOS 09h and would stop
					; at one, which is how 099 lost half of
					; its message
msg_index_half_name:
		defb	"IXH, IXL, IYH and IYL are registers,"
		defb	" not names.",CHR_CR,CHR_LF,"$"
msg_bad_name_char:
		defb	"a name may hold only letters, digits,"
		defb	" ? @ . _ and the dollar sign.",CHR_CR
		defb	CHR_LF,"$"
				; NOT a "$" in the text: die_with_message
					;   prints with BDOS 09h and would stop
					;   there. It was written with one
					;   and lost half the line
msg_name_not_label:
		defb	"EQU, DEFL and MACRO take a name, not a"
		defb	" label.",CHR_CR,CHR_LF,"$"
msg_group_needed:
		defb	"this transient DSEG needs a GROUP"
		defb	" first.",CHR_CR,CHR_LF,"$"
msg_too_many_segments:
		defb	"too many segments, groups or"
		defb	" externals.",CHR_CR,CHR_LF,"$"
msg_already_defined:
		defb	"this name already has a value.",CHR_CR
		defb	CHR_LF,"$"
msg_external_here:
		defb	"an external symbol may not be used"
		defb	" here.",CHR_CR,CHR_LF,"$"
msg_bad_declaration:
		defb	"bad PUBLIC or EXTRN list.",CHR_CR
		defb	CHR_LF,"$"
msg_public_undefined:
		defb	"a PUBLIC name was never defined."
		defb	CHR_CR,CHR_LF,"$"
msg_bad_data_operand:
		defb	"bad DB, DW or DC operand.",CHR_CR
		defb	CHR_LF,"$"
msg_not_a_form:	defb	"not a form this instruction has."
		defb	CHR_CR,CHR_LF,"$"
msg_unknown_operation:
		defb	"not a directive, a macro or an"
		defb	" instruction.",CHR_CR,CHR_LF,"$"
msg_bad_page_length:
		defb	"a PAGE length must be 10 to 255."
		defb	CHR_CR,CHR_LF,"$"
msg_emitted_nothing:
		defb	"internal - an instruction emitted"
		defb	" nothing.",CHR_CR,CHR_LF,"$"
msg_too_many_bytes:
		defb	"internal - this line emitted more"
		defb	" bytes than fit.",CHR_CR,CHR_LF,"$"
msg_bad_displacement:
		defb	"an index displacement must be -128"
		defb	" to 127.",CHR_CR,CHR_LF,"$"
msg_bad_rst:		defb	"RST takes 0, 8, 10h and so on to"
		defb	" 38h.",CHR_CR,CHR_LF,"$"
msg_bad_im:	defb	"IM takes 0, 1 or 2.",CHR_CR,CHR_LF
		defb	"$"
msg_jump_too_far:
		defb	"a JR or DJNZ can only reach -128"
		defb	" to 127.",CHR_CR,CHR_LF,"$"
msg_bad_bit_number:	defb	"a bit number must be 0 to 7."
		defb	CHR_CR,CHR_LF,"$"
