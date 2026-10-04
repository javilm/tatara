; lerrs.as - TANREN's errors.
;
; Every one of them prints a line and terminates. The assembler's
; errs.as also prints where in the source the error was, because it
; has a line to point at.
;
; THIS MODULE USED TO SAY that the linker's errors need no such thing,
; because "the file's name is in the message the driver already
; printed". There is no such message: TANREN prints its banner and
; then nothing until the map. Five errors carried that premise for as
; long as it took someone to link two files and read the second one's
; error. Issue #26. The five that are raised while a file is open now
; print NAME: in front, the way the assembler prints FILE(line):, and
; the four raised after every file is closed do not - object_name is only
; true while one is open.

LERRS_INCLUDED	equ	1	; skips the externals in lerrs.inc

		public	error_cannot_open
		public	error_not_object_file
		public	error_wrong_version
		public	error_truncated
		public	error_unknown_option
		public	error_out_of_memory
		public	error_too_many_segments
		public	error_cannot_open_list
		public	error_nested_file_list
		public	error_two_file_lists
		public	error_too_many_words
		public	error_env_too_long
		public	error_cannot_create
		public	error_cannot_write
		public	error_output_is_input
		public	error_too_many_externals
		public	error_segment_differs
		public	error_data_overlaps_code
		public	error_image_too_big
		public	error_duplicate_public
		public	error_undefined_symbols
		public	error_case_mismatch

		include	lerrs.inc
		include	msxdos.inc	; _STROUT, print_zero_string, dos_exit
		include	lcmd.inc
					; object_name: error_cannot_open
					;   names the file it tried, which
					;   add_object_extension may have
					;   given an extension.
					;   output_name: error_cannot_create
					;   and error_output_is_input name
					;   that one for the same reason
		include	arglist.inc
					; response_file_name:
					;   error_cannot_open_list names
					;   the response file it tried, the
					;   way error_cannot_open names the
					;   object
		include	lobj.inc
					; objfile_string_buffer,
					;   objfile_string_length:
					;   error_segment_differs names the
					;   segment, and the SEGDEF's name
					;   is still in the record buffer
					;   where build_segment_key read it
		include	ascii.inc	; CHR_CR, CHR_LF

		cseg

error_cannot_open:
		; THE NAME IT ACTUALLY TRIED, which add_object_extension may
		;   have changed. Zero-terminated, not "$": a filename is
		;   interleaved with it and BDOS 09h cannot help with that
		call	print_error_prefix
		ld	de,msg_cannot_open
		call	print_zero_string
		ld	de,object_name
		call	print_zero_string_upper
		ld	de,msg_end_of_line
		call	print_zero_string
		jp	dos_exit
error_cannot_open_list:
		call	print_error_prefix	; AND THIS ONE: a response file
		ld	de,msg_cannot_open_list
		call	print_zero_string
					;   that will not open is almost
		ld	de,response_file_name	;   always a name typed wrong
		call	print_zero_string_upper
		ld	de,msg_end_of_line
		call	print_zero_string
		jp	dos_exit
error_cannot_create:
		; AND THIS NAME TOO: a path that does not exist is the likely
		;   cause, and the name is the clue
		call	print_error_prefix
		ld	de,msg_cannot_create
		call	print_zero_string
		ld	de,output_name
		call	print_zero_string_upper
		ld	de,msg_end_of_line
		call	print_zero_string
		jp	dos_exit
error_output_is_input:
		call	print_error_prefix
		ld	de,msg_output_file
		call	print_zero_string
		ld	de,output_name
		call	print_zero_string_upper
		ld	de,msg_is_also_input
		call	print_zero_string
		jp	dos_exit

; print_file_prefix - "NAME: ", the object file being read.
;
;   THE NAME GOES IN FRONT, which is why this costs so little: the
;   messages keep their text and their $ terminator. It is also the
;   format the assembler uses - FILE(line): ERROR: - so one habit
;   reads both tools.
;
; Input:	object_name
; Output:	the name and a colon
; Modifies:	AF, BC, DE, HL

print_file_prefix:
		ld	de,object_name	; UPPER CASE, like every other name
		call	print_zero_string_upper
					;   TANREN prints and like the source
					;   file in the assembler's errors
		ld	de,msg_colon
		jp	print_zero_string

; die_naming_file - that prefix, then the ordinary error line. ONLY FOR THE
;   ERRORS RAISED WHILE A FILE IS OPEN: object_name holds the last name
;   tried, and after the reading is done that is not the file at
;   fault.
;
; Input:	DE -> the $-terminated message
; Output:	does not return

die_naming_file:
		push	de
		call	print_file_prefix
		pop	de
		; jp: error_segment_differs and print_counted_name went in
		;   between, and die_with_message is 128 bytes away - one past
		;   a jr's reach
		jp	die_with_message

error_not_object_file:
		ld	de,msg_not_object_file
		jr	die_naming_file
error_wrong_version:
		ld	de,msg_wrong_version
		jr	die_naming_file
error_truncated:
		ld	de,msg_truncated
		jr	die_naming_file
error_unknown_option:
		ld	de,msg_unknown_option
		jr	die_with_message
error_out_of_memory:
		ld	de,msg_out_of_memory
		jr	die_with_message
error_env_too_long:
		; the TANREN variable is longer than ENV_VALUE_MAX, so _GENV
		;   has handed back a truncated value with no terminator
		ld	de,msg_env_too_long
		jr	die_with_message
error_too_many_segments:
		ld	de,msg_too_many_segments
		jr	die_naming_file	; one module's segments, and a
					;   module is a file
error_cannot_write:
		ld	de,msg_cannot_write
		jr	die_with_message
error_nested_file_list:
		ld	de,msg_nested_file_list
		jr	die_with_message
error_two_file_lists:
		ld	de,msg_two_file_lists
		jr	die_with_message
error_too_many_words:
		ld	de,msg_too_many_words
		jr	die_with_message
error_too_many_externals:
		ld	de,msg_too_many_externals
		jr	die_with_message
error_image_too_big:
		ld	de,msg_image_too_big
		jr	die_with_message
error_data_overlaps_code:
		ld	de,msg_data_overlaps_code
		jr	die_with_message
error_duplicate_public:
		ld	de,msg_duplicate_public
		jr	die_with_message
error_undefined_symbols:
		ld	de,msg_undefined_symbols
		jr	die_with_message
error_case_mismatch:
		ld	de,msg_case_mismatch
		jr	die_with_message
; error_segment_differs - two files disagree about one segment, and
;   the user needs to know about WHICH ONE. The name is still in
;   objfile_string_buffer: build_segment_key read it from there a few
;   instructions ago. The record htfind found is no use for it -
;   payload_pointer points at the PAYLOAD, not at the record, so
;   print_record_name cannot be aimed at it, and lseg.as is left
;   alone.
;
;   The OTHER module is not named. Nothing remembers it: see 096.

error_segment_differs:
		call	print_file_prefix
		call	print_error_prefix
		ld	de,msg_segment
		call	print_zero_string
		call	print_counted_name
		ld	de,msg_declared_differently
		call	print_zero_string
		jp	dos_exit

; print_counted_name - objfile_string_length bytes of
;   objfile_string_buffer: a name as the FILE wrote it, which is
;   counted and not terminated.
;
; Input:	objfile_string_buffer, objfile_string_length
; Output:	the name is printed
; Modifies:	AF, BC, DE, HL

print_counted_name:
		ld	a,(objfile_string_length)
		or	a
		ret	z		; no name: print nothing rather
		ld	b,a		;   than 256 characters
		ld	hl,objfile_string_buffer
print_counted_name.loop:
		push	bc
		push	hl
		ld	e,(hl)
		call	print_char
		pop	hl
		pop	bc
		inc	hl
		djnz	print_counted_name.loop
		ret

; die_with_message - print the $-terminated message in DE and terminate.
;
; Input:	DE -> the message
; Output:	does not return

die_with_message:
		; THE ONE COPY, for the sixteen errors that come through here
		push	de
		call	print_error_prefix
		pop	de
		call	print_dollar_string
		jp	dos_exit

; print_error_prefix - "ERROR: ", for the four that print a filename and so
;   cannot come through die_with_message.
;
; Input:	nothing
; Output:	seven characters
; Modifies:	AF, BC, DE, HL

print_error_prefix:
		ld	de,msg_error
		jp	print_zero_string

		dseg

				; printed by die_with_message and
				;   print_error_prefix
msg_error:	defb	"ERROR: ",0
msg_colon:	defb	": ",0	; and by print_file_prefix, after the name
msg_cannot_open:
		defb	"cannot open ",0
msg_end_of_line:
		defb	CHR_CR,CHR_LF,0
msg_not_object_file:
		defb	"not a Tatara object file.",CHR_CR
		defb	CHR_LF,"$"
msg_wrong_version:
		defb	"this object file was made by another"
		defb	" version.",CHR_CR,CHR_LF,"$"
msg_truncated:	defb	"the object file ends inside a record."
		defb	CHR_CR,CHR_LF,"$"
msg_unknown_option:
		defb	"unknown option.",CHR_CR,CHR_LF,"$"
msg_out_of_memory:
		defb	"out of mapper memory.",CHR_CR
		defb	CHR_LF,"$"
msg_env_too_long:
		defb	"the TANREN variable is too long.",CHR_CR
		defb	CHR_LF,"$"
msg_cannot_open_list:
		defb	"cannot open the file list ",0
msg_nested_file_list:
		defb	"a file list may not name another"
		defb	" one.",CHR_CR,CHR_LF,"$"
msg_two_file_lists:
		defb	"only one file list may be given.",CHR_CR
		defb	CHR_LF,"$"
msg_too_many_words:
		defb	"too many words on the command line"
		defb	" or in the file list.",CHR_CR,CHR_LF,"$"
msg_cannot_create:
		defb	"cannot create ",0
msg_output_file:
		defb	"the output file ",0
msg_is_also_input:
		defb	" is also an input file.",CHR_CR,CHR_LF,0
msg_cannot_write:
		defb	"cannot write the output file - the"
		defb	" disk may be full.",CHR_CR,CHR_LF,"$"
msg_too_many_externals:
		defb	"too many external symbols in one"
		defb	" module.",CHR_CR,CHR_LF,"$"
msg_too_many_segments:
		defb	"too many segments or groups in one"
		defb	" module.",CHR_CR,CHR_LF,"$"
				; print_counted_name puts the name
				;   between these two.
				;   ZERO-TERMINATED, both of them:
				;   error_segment_differs prints
				;   them with print_zero_string, because a name
				;   is interleaved and BDOS 09h
				;   cannot help with that
msg_segment:	defb	"segment ",0
msg_declared_differently:
		defb	" is declared differently.",CHR_CR
		defb	CHR_LF,0
msg_data_overlaps_code:
		defb	"/D: would put the data on top of"
		defb	" the code.",CHR_CR,CHR_LF,"$"
msg_image_too_big:
		defb	"the linked image would run past"
		defb	" FFFFh.",CHR_CR,CHR_LF,"$"
msg_duplicate_public:
		defb	"that public symbol is already"
		defb	" defined.",CHR_CR,CHR_LF,"$"
msg_undefined_symbols:
		defb	"the symbols above were never"
		defb	" defined.",CHR_CR,CHR_LF,"$"
msg_case_mismatch:
		defb	"one module was assembled /C and"
		defb	" another was not.",CHR_CR,CHR_LF,"$"
