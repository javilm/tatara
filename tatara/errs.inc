; errs.inc - public interface of errs.as: the error messages.
;
; errs.as includes this file too: it defines ERRS_INCLUDED first, which skips
; the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.
;
; EVERY ONE OF THESE PRINTS AND TERMINATES. None of them returns, so a
; caller reaches one with jp or jr and never has to think about what
; comes back. The one exception is print_trail at the foot of the file,
; which is a printer rather than an error and does come back.
;
; This file exists because the SOLID assembler resolves an undeclared
; symbol to 0000h and writes the .com anyway. A module's export list is
; therefore the only thing between a mistyped name and a program that
; links cleanly and calls address zero. Seven modules used to keep their
; own hand-picked lists of these names; now there is one list, here.

		ifndef	ERRS_INCLUDED

; --- the command line, before any file is open. These print the message
;     with no FILE(line) prefix, because there is no position yet.

		extrn error_unknown_option	; unknown option
		extrn error_too_many_filenames	; too many filenames

; --- files and lines

		extrn error_source_too_deep	; sources nested too deeply
		extrn error_too_many_open
					; too many source files open at once
		extrn error_too_many_sources
					; too many different source files
		extrn error_line_too_long	; source line too long
		extrn error_write_failed
					; cannot write to the output file
		extrn error_include_no_file	; INCLUDE without a filename
		extrn error_env_too_long
					; the TATARA variable is too long

; --- macro definitions and expansions

		extrn error_macro_not_closed
					; definition not closed by ENDM.
					; in: A = file, HL = the MACRO or REPT
					;     line - it fires at the end of the
					;     source, so current_line is
					;     useless
		extrn error_endm_without_macro	; ENDM without a definition
		extrn error_macro_no_name
					; MACRO without a name, and only
					; that
		extrn error_macro_name_long
				; a macro name longer than MACRO_NAME_MAX
		extrn error_segment_name_long
					; a segment or group name longer
					; than SEGMENT_NAME_MAX
		extrn error_too_many_parameters
					; more formal params than we can count
		extrn error_bad_parameter_list
					; a parameter list that does not parse
		extrn error_local_too_late
					; LOCAL after the body has started
		extrn error_macro_line_long
					; a macro line that went past LINE_MAX
		extrn error_exitm_outside
					; EXITM outside a macro or repeat block
		extrn error_phase	; a label whose val on pass 2 disagrees
					; with pass 1's. M80 calls it a P error
		extrn error_pass2_label	; a label pass 1 defined and pass 2
					; did not: a conditional skipped it
					; the second time
					; in:  A = its file number,
					;      HL = its line

; --- conditionals

		extrn error_cond_unmatched
					; ELSE or ENDIF without a matching IF
		extrn error_cond_not_closed
					; conditional not closed by ENDIF.
					; in: A = file, HL = the outermost one
					;     still open, from cond_eof
		extrn error_cond_too_deep
					; conditionals nested too deeply

; --- expressions, and the heap

		extrn error_undefined_symbol
					; undefined symbol in an expression
		extrn error_bad_expression	; bad expression
		extrn error_relocation	; a segment-relative value where the
					; operaetion needs an absolute one, or
					; two segments that do not combine.
					; M80 calls it an R error
		extrn error_out_of_memory	; out of mapper memory

; --- segments

		extrn error_bad_segment_line	; a bad ASEG/CSEG/DSEG line
		extrn error_segment_differs
					; this segment name was declared
					; with different flags before
		extrn error_bad_group_line
					; GROUP outside a transient DSEG,
					; or with no name, or with a label
		extrn error_group_needed
					; a transient DSEG with no GROUP
					; open yet
		extrn error_bad_name_char
					; a label holding a character that
					; is not a name character
		extrn error_index_half_name
					; a symbol called IXH, IXL, IYH or
					; IYL, which are registers now
		extrn error_bad_control_line
					; a column-1 word beginning with *
					; or $ that is not *EJECT or $EJECT
		extrn error_name_not_label
					; EQU, DEFL or MACRO with a colon
					; after the name, which makes it a
					; label - M80 2.3.1
		extrn error_too_many_segments
					; more segments or group than an
					; index byte can hold

; --- symbols declared

		extrn error_already_defined	; this name already has a value
		extrn error_external_here
					; an external symbol where the rules
					; do not allow one
		extrn error_bad_declaration
					; a PUBLIC or EXTRN list that does
					; not parse
		extrn error_public_undefined
					; PUBLIC named a symbol and nothing
					; in this module ever defined it
					;

; --- the data directives

		extrn error_bad_data_operand	; a DB, DW or DC operand that
					; cannot be measured

; --- instructions

		extrn error_not_a_form	; the operands are not a form this
					; instruction has
		extrn error_bad_page_length
					; PAGE was given a length outside
					; 10 to 255
		extrn error_unknown_operation
					; the operation is not a directive, a
					; macro or an instruction either

; --- emitting

		extrn error_too_many_bytes
					; INTERNAL: a line emitted more bytes
					; than emitted_bytes keeps, which was
					; proved cannot happen and is checked
					; anyway, the buffer having become the
					; object file's content
		extrn error_emitted_nothing
					; INTERNAL: a handler returned without
					; emitting anything, which no Z80
					; instruction does. The other half of
					; it - the length and the bytes
					; disagreeing - stopped being possible
					;
		extrn error_bad_displacement	; an index displacement outside
					; -128 to 127
		extrn error_bad_rst	; an RST operand that is not 8n below
					; 40h
		extrn error_bad_im	; an IM operand that is not 0, 1 or 2
		extrn error_jump_too_far
					; a JR or DJNZ displacement that does
					; not fit a signed byte
		extrn error_bad_bit_number
					; a bit number that is not 0 to 7

; --- and one that is NOT an error, and DOES return.

		extrn print_trail	; print how we got to the line that
					; failed: one line per level of the
					; source stack, innermost first.
					; die_with_message calls it, and so
					; does main.cannot_open_include, which
					; prints its own first line and wants
					; the rest of the chain under it

		endif
