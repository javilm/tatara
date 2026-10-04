; lcmd.as - TANREN's command line.
;
; Deliberately simpler than cmdline.as and not a shared version of
; it: the two programs take different switches and print different
; screens. What moved OUT of here is the layer below that - the
; splitting of a command tail into words, and the reading of a
; response file instead - which is arglist.as, and which knows
; nothing about what a word means.
;
; SO THIS MODULE NO LONGER TOUCHES A CHARACTER OF THE COMMAND TAIL.
; It asks arglist.as for words and decides what each one is: a "/"
; makes it a switch, anything else makes it an object file. That test
; is the one it always made, and it is now the only one it makes.

LCMD_INCLUDED	equ	1	; skips the externals in lcmd.inc

		public	parse_command_line
		public	object_name
		public	output_name
		public	objects_first
		public	objects_next
		public	opt_dump
		public	opt_map
		public	opt_quiet
		public	opt_version
		public	opt_help
		public	opt_output
		public	opt_bload
		public	opt_code_origin
		public	code_origin
		public	opt_data_origin
		public	data_origin
		public	default_output_name
		public	check_output_not_input
		public	print_banner
		public	print_truncation_warning
		public	print_version_banner
		public	print_usage

		include	lcmd.inc
		include	arglist.inc
					; split_command_tail,
					;   arglist_first, arglist_next,
					;   tail_truncated
		include	lerrs.inc
					; error_unknown_option,
					;   error_output_is_input
		include	msxdos.inc	; _STROUT, dos_exit
		include	ascii.inc	; CHR_CR, CHR_LF
		include	strutil.inc
			; fold_to_upper, find_extension, add_default_extension

SWITCH_CHAR	equ	"/"

		cseg

; parse_command_line - what the words on the command line mean.
;
;   split_command_tail has already split them, expanded any @FILE, and put them
;   in the mapper. This walks them once: a switch is acted on, and
;   anything else is counted - because "was a filename given at all?"
;   is the only thing the caller needs to know here. objects_next walks
;   the same list again, twice, to do the reading.
;
; Input:	nothing
; Output:	CY clear = at least one filename was given
;		CY set   = none was
; Modifies:	everything

parse_command_line:
		xor	a
		ld	(opt_dump),a
		ld	(opt_map),a
		ld	(opt_quiet),a
		ld	(opt_version),a
		ld	(opt_help),a
		ld	(opt_output),a
		ld	(opt_bload),a
		ld	(opt_code_origin),a
		ld	(opt_data_origin),a
		ld	(filename_count),a
		ld	(object_name),a
		ld	(output_name),a
		; THE WHOLE COMMAND LINE, as words
		call	split_command_tail
		call	arglist_first
parse_command_line.word:
		ld	de,object_name	; the buffer it is going to use
		call	arglist_next	;   anyway
		jr	c,parse_command_line.done
		ld	a,(object_name)
		cp	SWITCH_CHAR
		jr	z,parse_command_line.switch
		; a filename: COUNTED, not kept. 259 of them would wrap this
		;   byte, and the list would run out first
		ld	hl,filename_count
		inc	(hl)
		jr	parse_command_line.word
parse_command_line.switch:
		ld	de,object_name
		call	do_switch
		jr	parse_command_line.word
parse_command_line.done:
		xor	a
		ld	(object_name),a	; LEAVE IT EMPTY: objects_next fills it
		ld	a,(filename_count)	;   when the reading starts
		or	a
		scf
		ret	z
		or	a
		ret

; do_switch - one option word.
;
;   IT TAKES A WHOLE WORD NOW. Every arm used to end in a jump to
;   lcpend, because each one had to step the tail pointer past the
;   rest of its own word before the caller could look for the next
;   one. There is no pointer any more, so every arm is a ret - and
;   the worry about the furthest arm being out of a jr's reach goes
;   with it.
;
; Input:	DE -> the word, which starts with "/"
; Output:	the flag is set (error_unknown_option does not return)
; Modifies:	AF, BC, DE, HL

do_switch:	inc	de
		ld	a,(de)
		or	a
		jp	z,error_unknown_option	; a "/" with nothing after it
		call	fold_to_upper
		cp	"B"
		jr	z,do_switch.bload
		cp	"D"
		; jp: /D: and /P: sit past the flag arms and past /O:, a
		;   hundred bytes and more from here
		jp	z,do_switch.data_origin
		cp	"M"
		jr	z,do_switch.map
		cp	"O"
		jr	z,do_switch.output
		cp	"P"
		jp	z,do_switch.code_origin
		cp	"R"
		jr	z,do_switch.dump
		cp	"Q"
		jr	z,do_switch.quiet
		cp	"V"
		jr	z,do_switch.version
		cp	"?"	; not a letter, so fold_to_upper left it
		jp	nz,error_unknown_option
		ld	a,0ffh
		ld	(opt_help),a
		ret
do_switch.bload:
		ld	a,0ffh
		ld	(opt_bload),a
		ret
do_switch.dump:	ld	a,0ffh		; the arm, under its new letter
		ld	(opt_dump),a
		ret
do_switch.map:	ld	a,0ffh
		ld	(opt_map),a
		ret
do_switch.quiet:
		ld	a,0ffh
		ld	(opt_quiet),a
		ret
do_switch.version:
		ld	a,0ffh
		ld	(opt_version),a
		ret

; do_switch.output - /O:<file>, the only option that carries a value.
;
;   L80 writes /P: and /E:, and the colon is the convention this
;   keeps. The name is the rest of the same word, so there is nothing
;   to look ahead for - which is why it survived the move from a tail
;   pointer to a word unchanged in everything but how it copies.
;
; Input:	DE -> the "O" of the word
; Output:	output_name, opt_output (error_unknown_option does not return)
; Modifies:	AF, DE, HL

do_switch.output:
		inc	de		; past the "O"
		ld	a,(de)
		cp	":"
		jp	nz,error_unknown_option
		inc	de
		ld	a,(de)
		or	a
		jp	z,error_unknown_option	; "/O:" and nothing after it
		ld	h,d
		ld	l,e
		ld	de,output_name
do_switch.output_copy:
		ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,do_switch.output_done
		inc	hl
		inc	de
		jr	do_switch.output_copy
do_switch.output_done:
		ld	a,0ffh
		ld	(opt_output),a
		ret

; do_switch.data_origin, do_switch.code_origin - /D:<addr> and
; /P:<addr>, where the data and the code start.
;
;   /D WAS ONCE THE RECORD DUMP, before there was a linker to want
;   it for an address. L80's data origin is /D:, so the two would have
;   been told apart by a colon alone, and the decision was that
;   "having /D and /D: is going to be confusing for many
;   people". The dump is /R now and these two are plain.
;
;   Both require the colon, so /D and /P alone are
;   error_unknown_option rather than something silently ignored.
;
; Input:	DE -> the letter of the word
; Output:	data_origin and opt_data_origin, or code_origin
;		and opt_code_origin
;		(error_unknown_option does not return)
; Modifies:	AF, BC, DE, HL

do_switch.data_origin:
		call	switch_address
		ld	(data_origin),hl
		ld	a,0ffh
		ld	(opt_data_origin),a
		ret

do_switch.code_origin:
		call	switch_address
		ld	(code_origin),hl
		ld	a,0ffh
		ld	(opt_code_origin),a
		ret

; switch_address - the address after a letter and a colon.
;
; Input:	DE -> the letter
; Output:	HL = the address (error_unknown_option does not return)
; Modifies:	AF, BC, DE, HL

switch_address:	inc	de
		ld	a,(de)
		cp	":"
		jp	nz,error_unknown_option
		inc	de
		call	parse_hex_number
		jp	c,error_unknown_option
		ret

; objects_first, objects_next - the object filenames, one at a time.
;
;   THE SAME LIST THE OPTIONS CAME FROM, walked again. A word that
;   begins with "/" is a switch and is stepped over; everything else
;   is a filename and gets ".tro" if it has no extension.
;
;   Walked TWICE over a link, once per pass. That was designed for
;   when the list was the command tail itself and nothing had to be
;   stored; it is stored now, because a response file cannot be left
;   sitting at 0080h.
;
; Input:	nothing
; Output:	objects_next: CY clear = object_name holds the next one
;		         CY set   = there are no more
; Modifies:	AF, BC, DE, HL

objects_first:	jp	arglist_first

objects_next:	ld	de,object_name
		call	arglist_next
		ret	c
		ld	a,(object_name)
		cp	SWITCH_CHAR
		jr	z,objects_next	; a switch: step over it
		call	add_object_extension	; ".tro", unless it has one
		call	find_object_file	; and WHERE it is
		or	a		; CY clear: a name was found
		ret

; add_object_extension - a default extension of .tro, on object_name.
;
; Input:	object_name, ASCIIZ
; Output:	".tro" appended if it had no extension
; Modifies:	AF, BC, DE, HL

add_object_extension:
		ld	de,object_name
		ld	hl,msg_tro_extension
		jp	add_default_extension

; find_object_file - find the object file object_name names.
;
;   IT CANNOT FAIL. If nothing opens, object_name is left exactly as it
;   was and objfile_open reports it, which is what happened before this
;   note existed - so there is no new error, no new contract, and
;   lobj.as and tanren.as are not touched at all.
;
;   THE FILE LIST'S DIRECTORY COMES FIRST, and not the current
;   directory: an object sitting beside the .lnk file that names it
;   must win over one of the same name in whatever directory the
;   linker was started from.
;
;   IT OPENS AND CLOSES to find out - three BDOS calls per object
;   instead of one, over nineteen objects and two passes. The
;   alternative is a search inside objfile_open, which would have to know
;   about the word list and about the environment, and lobj.as knows
;   about neither.
;
; Input:	object_name, with its extension
;		word_from_file, from the word this name came from
; Output:	object_name, with a directory in front of it if that is
;		where the file turned out to be
; Modifies:	everything

find_object_file:
		ld	de,object_name
		call	is_absolute_name
		ret	c		; absolute: this or nothing
		ld	a,(word_from_file)	; 1 - where the file list lives
		or	a
		jr	z,find_object_file.as_typed
		ld	hl,response_file_directory
		call	find_object_file.try_prefix
		ret	nc
find_object_file.as_typed:
		ld	de,object_name	; 2 - as typed
		call	find_object_file.opens
		ret	nc
		call	read_env_path	; 3 - each entry of TANREN in turn
		ld	hl,env_path
find_object_file.env_entry:
		ld	a,(hl)
		or	a
		ret	z	; used up: object_name is left as it was
		call	find_object_file.try_prefix
		ret	nc
		ld	a,(hl)		; HL is at the ";" or at the end
		or	a
		ret	z		; that was the last entry
		inc	hl		; past the ";"
		jr	find_object_file.env_entry

; find_object_file.try_prefix - one prefix: compose it with
;   object_name and see if it opens.
;
; Input:	HL -> the prefix, ended by 0 or ";"
; Output:	CY clear = it opened, and object_name now says where
;		HL -> the prefix's terminator, either way
; Modifies:	everything

find_object_file.try_prefix:
		ld	de,object_name
		call	compose_path	; -> path_buffer, HL at the terminator
		ld	(prefix_end),hl	; KEEP IT: the copy below needs HL, and
					;   ld (nn),hl leaves the flags alone
		jr	c,find_object_file.not_found
		ld	de,path_buffer
		call	find_object_file.opens
		jr	c,find_object_file.not_found
		ld	hl,path_buffer	; it opened: this is the name now
		ld	de,object_name
find_object_file.copy:
		ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,find_object_file.found
		inc	hl
		inc	de
		jr	find_object_file.copy
find_object_file.found:
		ld	hl,(prefix_end)
		or	a		; CY clear
		ret
find_object_file.not_found:
		ld	hl,(prefix_end)
		scf
		ret

; find_object_file.opens - does this name open?
;
;   Opened and closed again, because the answer is wanted and the
;   handle is not: objfile_open does the real open, with the magic check
;   that goes with it.
;
; Input:	DE -> the name, ASCIIZ
; Output:	CY set = MSX-DOS would not open it
; Modifies:	AF, BC

find_object_file.opens:
		ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error, B = handle
		or	a
		scf
		ret	nz
		system	_CLOSE		; B is still the handle, and
					;   page2_safe preserves it
		or	a
		ret

; read_env_path - fetch TANREN's value, once.
;
;   ONCE, AND FAILURES COUNT AS DONE, so a link of nineteen objects
;   does not ask MSX-DOS nineteen times.
;
;   Under MSX-DOS 1 there are no environment variables, so the buffer
;   stays empty and the search has one place fewer to look.
;
;   _GENV TRUNCATES WITHOUT A TERMINATOR when the buffer is too small
;   and says ERR_ELONG. A search path quietly shorter than what was
;   set is worse than none, so that is an error.
;
; Input:	nothing
; Output:	env_path holds the value, or is empty
; Modifies:	AF, BC, DE, HL

read_env_path:	ld	a,(env_read)
		or	a
		ret	nz		; asked once already
		ld	a,1
		ld	(env_read),a
		xor	a
		ld	(env_path),a	; empty unless proved otherwise
		call	dos_version
		ret	c		; MSX-DOS 1: there are none
		ld	hl,msg_env_name
		ld	de,env_path
		ld	b,ENV_VALUE_MAX
		system	_GENV
		or	a
		ret	z		; the value is in the buffer
		cp	ERR_ELONG
		jp	z,error_env_too_long
		xor	a
		ld	(env_path),a	; any other refusal: no path
		ret

msg_env_name:	defb	"TANREN",0	; MSX-DOS upper-cases a variable's
					;   name when it is set and compares
					;   without case, so this spelling is
					;   the whole of it

; default_output_name - the output file's name, when /O: did not give one.
;
;   THE FIRST OBJECT FILE'S NAME WITH .com ON IT:
;   "Let's assume .com filename if none is specified." Whatever
;   extension it has comes off first, so "A:\X\MAIN.TRO" gives
;   "A:\X\MAIN.COM" - beside the object it was made from, which is
;   where a linker's output belongs.
;
;   IT TAKES THE NAME FROM THE LIST, with .tro already on it if the
;   user typed no extension, and that gives the same answer as taking
;   what was typed: "main" becomes "main.tro", loses ".tro", and
;   becomes "main.com". A separate copy of the first name was once
;   for this and no longer needs one.
;
; Input:	opt_output, opt_bload, the list
; Output:	output_name
; Modifies:	everything

default_output_name:
		ld	a,(opt_output)
		or	a
		ret	nz		; /O: named one
		call	objects_first
		call	objects_next
		ret	c		; no filenames at all
		ld	hl,object_name
		ld	de,output_name
default_output_name.copy:
		ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,default_output_name.cut
		inc	hl
		inc	de
		jr	default_output_name.copy
default_output_name.cut:
		ld	de,output_name	; whatever extension it has comes
		call	find_extension	;   off
		jr	c,default_output_name.extension
		ld	(hl),0
default_output_name.extension:
		ld	de,output_name	; and .com goes on - or .bin, if
		ld	hl,msg_com_extension	;   /B was given, because a
		ld	a,(opt_bload)	;   BLOAD header is what makes a
		or	a		;   file a .BIN, and nothing else
		jr	z,default_output_name.append
		ld	hl,msg_bin_extension
default_output_name.append:
		jp	add_default_extension

; check_output_not_input - the output file may not be one of the inputs.
;
;   The rule is "except when the output would overwrite one of
;   the input files". CHECKED BEFORE ANYTHING IS READ, because the
;   answer cannot change during the link and a link that is going to
;   refuse should refuse before it has printed a map.
;
;   Both names carry their extensions by then, so "tanren /o:a.com a"
;   is allowed - the input is A.TRO - and "tanren /o:a.tro a" is not.
;
; Input:	output_name, and the list
; Output:	nothing (error_output_is_input does not return)
; Modifies:	AF, BC, DE, HL

check_output_not_input:
		call	objects_first
check_output_not_input.loop:
		call	objects_next
		ret	c
		ld	hl,object_name
		ld	de,output_name
		call	same_filename
		jp	z,error_output_is_input
		jr	check_output_not_input.loop

; same_filename - two ASCIIZ filenames, compared without regard to case.
;
;   MSX-DOS does not care about the case of a filename, so neither may
;   this. PATHS ARE NOT RESOLVED: "A:\X\A.TRO" and "..\X\A.TRO" may be
;   one file and this will not notice, which is a limit and not a bug -
;   resolving a path means asking MSX-DOS, and the answer would be
;   worth having only if the linker also refused to read two inputs
;   that were one file.
;
; Input:	HL -> one name
;		DE -> the other
; Output:	Z set = the same name
; Modifies:	AF, BC, DE, HL

same_filename:	ld	a,(de)
		call	fold_to_upper
		ld	c,a
		ld	a,(hl)
		call	fold_to_upper
		cp	c
		ret	nz
		or	a		; both ended together: the same
		ret	z
		inc	hl
		inc	de
		jr	same_filename

; print_banner - the banner, unless /Q said not to.
;
; Input:	nothing
; Output:	four lines, or none
; Modifies:	AF, DE

print_banner:	ld	a,(opt_quiet)
		or	a
		ret	nz

; print_version_banner - and the banner whatever was asked for.
;
; Input:	nothing
; Output:	four lines, the last of them blank
; Modifies:	AF, DE

print_version_banner:
		ld	de,msg_banner_head
		call	print_dollar_string
		ld	de,msg_version
		call	print_dollar_string
		ld	de,msg_banner_tail
		call	print_dollar_string
		ret

; print_truncation_warning - the command line may have been cut.
;
;   MSX-DOS gives 127 characters and TRUNCATES A LONGER LINE WITHOUT
;   SAYING SO. That is the whole reason [R10] exists: the failure does
;   not arrive as "line too long", it arrives as an undefined symbol
;   from a module that was never named, and this project walked into
;   it twice while being built.
;
;   A tail of exactly 127 characters is one that MAY have been cut -
;   it may also be a line that happens to fit exactly, which is why
;   this is a warning and not an error.
;
;   IT PRINTS EVEN UNDER /Q, because a warning is closer to an error
;   than to a summary, and /Q asks for the banner and the summary to
;   go.
;
; Input:	tail_truncated
; Output:	three lines, or none
; Modifies:	AF, DE

print_truncation_warning:
		ld	a,(tail_truncated)
		or	a
		ret	z
		ld	de,msg_truncated_warning
		call	print_dollar_string
		ret

; print_usage - the banner and the usage screen, and stop.
;
;   /Q does not silence it: asking for the screen and asking for
;   silence at once is a contradiction.
;
; Input:	nothing
; Output:	does not return

print_usage:	call	print_version_banner
		ld	de,msg_usage_screen
		call	print_dollar_string
		jp	dos_exit

; THE VERSION IS WRITTEN ONCE. cmdline.as puts two labels together so
; that the listing's page header can have "Tatara v1.2.0" as thirteen
; bytes; the linker has no listing and needs only the number, so
; msg_version stands alone between the two halves of the banner.

msg_version:	defb	"1.2.0","$"
msg_tro_extension:
		defb	".tro",0	; what add_object_extension appends,
msg_com_extension:
		defb	".com",0	;   what default_output_name does, and
msg_bin_extension:
		defb	".bin",0	;   what it does instead with /B

msg_banner_head:
		defb	"Tatara MSX Linker v$"
msg_banner_tail:
		defb	CHR_CR,CHR_LF
		defb	"Copyright (C) 2026 Javier Lavandeira"
		defb	CHR_CR,CHR_LF
		defb	"https://tatara.tools"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF,"$"

msg_truncated_warning:
		defb	"WARNING: the command line is 127"
		defb	" characters, which is all",CHR_CR,CHR_LF
		defb	"MSX-DOS gives - anything past it was dropped"
		defb	" in silence.",CHR_CR,CHR_LF
		defb	"Use @<file> if a module is missing."
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF,"$"

msg_usage_screen:
		defb	"Usage:  TANREN [options] <object|@list>"
		defb	" [more...]",CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"Options:  /B Write a BLOAD header on the"
		defb	" output file",CHR_CR,CHR_LF
		defb	"          /D:<addr> Start the data segments"
		defb	" at <addr>",CHR_CR,CHR_LF
		defb	"          /M Print the segment and group tables"
		defb	CHR_CR,CHR_LF
		defb	"          /O:<file> Write the image to"
		defb	" <file>",CHR_CR,CHR_LF
		defb	"          /P:<addr> Start the code segments"
		defb	" at <addr>",CHR_CR,CHR_LF
		defb	"          /Q Omit the banner above and the"
		defb	" summary line",CHR_CR,CHR_LF
		defb	"          /R Print every record in the object"
		defb	" files",CHR_CR,CHR_LF
		defb	"          /V Print the program version"
		defb	CHR_CR,CHR_LF
		defb	"          /? Print this screen"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"<object>  : A .tro file; .tro is assumed when"
		defb	" you leave it off.",CHR_CR,CHR_LF
		defb	"@<list>   : A file of the same words; ; is a"
		defb	" comment, .lnk",CHR_CR,CHR_LF
		defb	"            is assumed.",CHR_CR,CHR_LF
		defb	"<addr>    : One to four hex digits, as in"
		defb	" /P:4000.",CHR_CR,CHR_LF
		defb	"<file>    : The output. Default: the first"
		defb	" object with .com",CHR_CR,CHR_LF
		defb	"            (.bin with /B). It may not be an"
		defb	" input file.",CHR_CR,CHR_LF,"$"

		dseg

object_name:	defs	PATH_MAX+4	; the object file - AND ROOM FOR
					;   add_object_extension's four
					;   characters, which a name using
					;   the whole command tail would
					;   otherwise run past
output_name:	defs	PATH_MAX+4	; the file the image is written
					;   to, with room for
					;   default_output_name's four
					;   characters
filename_count:	defs	1		; how many words were not switches
prefix_end:	defs	2		; find_object_file.try_prefix: the
					;   prefix's terminator, across the
					;   copy into object_name
env_read:	defs	1		; 0 = TANREN has not been looked up
env_path:	defs	ENV_VALUE_MAX	; its value, read once
opt_dump:	defs	1		; 0FFh = /R given
opt_map:	defs	1		; 0FFh = /M given
opt_quiet:	defs	1		; 0FFh = /Q given
opt_version:	defs	1		; 0FFh = /V given
opt_help:	defs	1		; 0FFh = /? given
opt_output:	defs	1		; 0FFh = /O: given
opt_bload:	defs	1		; 0FFh = /B given
opt_code_origin:
		defs	1		; 0FFh = /P: given, and
code_origin:	defs	2		;   where it said the code starts
opt_data_origin:
		defs	1		; 0FFh = /D: given, and
data_origin:	defs	2		;   where it said the data starts
