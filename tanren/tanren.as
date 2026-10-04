; tanren.as - TANREN, the Tatara linker. The driver.
;
; TWO PASSES OVER THE SAME LIST OF FILES. Pass 1 reads the inventory
; and the names, lays the segments out and gives every symbol an
; address; pass 2 reads the same files again and copies their content
; into the image, patching every word the assembler could not fill in.
; The command tail is the list, walked twice.
;
; THE DUMP IS HERE AND NOT IN lobj.as on purpose. lobj.as knows the
; file's shape; what to do with a record is the driver's business,
; and the tables replace this dump without
; touching the reader.

		include	lcmd.inc	; the command tail and the banner
		include	lobj.inc	; the reader
		include	lseg.inc	; and the tables it fills
		include	lsym.inc	; and the symbols
		include	limg.inc	; and the image they end up in
		include	farptr.inc	; derefp: the image is the first thing
					;   in this module to reach into
					;   the mapper itself
		include	lerrs.inc
		include	msxdos.inc
		; dos_version, print_zero_string, print_decimal, dos_exit
		include	strutil.inc	; build_hex_word, build_hex_byte
		include	alloc.inc	; heap_init: nothing allocates yet,
					;   but [R11] puts the image in the
					;   mapper and the tables
		include	ascii.inc

MODULE_EXTERNAL_MAX	equ	512	; externals one module may declare.
				; tatara.as declares 182, which is the
				; most anything here has seen. THE MAP IS
				; IN THE MAPPER: 1 KB there costs nothing,
				; and 1 KB of ordinary RAM would be a
				; fifth of everything this program has
MODULE_EXTERNAL_MAX_HIGH	equ	2
					; MODULE_EXTERNAL_MAX / 256: the
					; bound is tested on the high
					; byte, and 512 is 0200h

		cseg

main:		call	dos_version	; CY set = not MSX-DOS2
		jp	c,main.need_dos2
		call	heap_init	; CY set = no mapper support
		jp	c,main.need_mapper

		call	parse_command_line	; CY set = no filename
		push	af
		ld	a,(opt_help)	; /? and /V answer and stop, with a
		or	a		;   filename or without one
		jp	nz,main.usage
		ld	a,(opt_version)
		or	a
		jp	nz,main.version
		pop	af
		jp	c,main.usage
		call	print_banner
		; 127 characters is all MSX-DOS gives, and it cuts a longer
		;   line in silence
		call	print_truncation_warning
		; the output file's name, and it may not be one of the inputs
		call	default_output_name
		call	check_output_not_input

		call	segments_init	; the tables, before the first file
		call	symbols_init
		ld	hl,0
		ld	(record_count),hl
		; AND THE TRAILING-BYTES FLAG, which is ORed from here on and
		;   so has to start somewhere. It never needed this while it
		;   was stored once per module
		xor	a
		ld	(trailing_bytes),a
		call	objects_first

main.next_file:	call	objects_next	; CY set = every file is read
		jr	c,main.all_read
		call	segments_new_module	; this module's maps, empty
		ld	de,object_name
		call	objfile_open		; the header, or one of three
					;   errors that do not return

main.record:	call	objfile_next_record	; CY set = no more records
		jr	c,main.module_end
		ld	hl,(record_count)
		inc	hl
		ld	(record_count),hl
		call	pass1_record	; what pass 1 wants; printed if /D
					; whatever pass1_record did not read -
		call	objfile_skip_record
					;   and ALL of it for a type we do
					;   not know, which is what the
					;   length field is for
		ld	a,(objfile_record_type)
		cp	RECORD_END	; THE MODULE ENDS HERE, and leaving
		jr	nz,main.record	;   the loop on it is a DECISION: a
					;   library would be several modules
					;   in one file, and this is where
					;   the nesting level would go

main.module_end:
		call	objfile_at_eof		; CY set = something follows it
		ld	a,0
		adc	a,a
		jr	z,main.close	; THIS MODULE'S OWN ANSWER, and it
					;   is read BEFORE the or below:
					;   afterwards A is the whole link's
					;   and the next module would be
					;   blamed for this one's bytes
		ld	hl,trailing_bytes	; OR, NOT STORE: the summary
		or	(hl)		;   speaks for every module read,
		ld	(hl),a		;   and it used to speak for the
					;   last one
		ld	a,(opt_quiet)	; AND WHICH MODULE. Not an error -
		or	a		;   spec 11 says a reader ignores
		jr	nz,main.close	;   what follows the END record -
		ld	de,object_name	;   so /Q silences it, and it is
		call	print_zero_string_upper
					;   said here rather than remembered
		ld	de,msg_bytes_after_end	;   because object_name is true
		call	print_zero_string	;   now and will not be later.
					;   Issue #27
main.close:	call	objfile_close
		jr	main.next_file

main.all_read:	call	place_segments	; every segment gets an address,
					;   and every symbol a final value
		call	symbols_relocate
		ld	a,(opt_map)	; THE MAP BEFORE THE CHECK, so that
		or	a		;   a link which is about to fail
		push	af		;   still shows what it did find
		call	nz,segments_dump
		pop	af
		call	nz,symbols_dump
		call	symbols_check	; every external nobody defined -
					;   all of them, and then it stops

		call	pass_two	; PASS 2: the content, the fixups
					;   and the file

		; AND BEFORE THE /Q TEST, because /Q hides the summary and a
		;   build file is exactly where a program entered in the wrong
		;   place would go unnoticed
		call	check_entry_point

		ld	a,(opt_quiet)	; the summary, unless /Q
		or	a
		jp	nz,dos_exit
		ld	a,(module_count)
		ld	l,a
		ld	h,0
		call	print_decimal
		ld	de,msg_modules_read
		call	print_zero_string
		ld	hl,(record_count)
		call	print_decimal
		ld	de,msg_records
		call	print_zero_string
		ld	a,(trailing_bytes)
		or	a
		ld	de,msg_ends_at_eof
		jr	z,main.summary_ending
		ld	de,msg_and_bytes_after
main.summary_ending:
		call	print_zero_string
		ld	a,(image_any)	; AND WHAT WAS WRITTEN. The entry
		or	a		;   point is here and nowhere else:
		jp	z,main.wrote_nothing	;   MSX-DOS enters a .COM at
		ld	de,msg_wrote	;   0100h whatever any file says,
		call	print_zero_string	;   so this is the only place a
		ld	de,output_name	;   wrong one could ever be seen
		call	print_zero_string_upper
		ld	de,msg_comma
		call	print_zero_string
		ld	hl,(image_low)
		call	print_hex_word
		ld	de,msg_dash
		call	print_zero_string
		ld	hl,(image_high)
		call	print_hex_word
		ld	de,msg_open_paren
		call	print_zero_string
		ld	hl,(image_high)	; both ends are in the file
		ld	de,(image_low)
		or	a
		sbc	hl,de
		inc	hl
		call	print_decimal
		ld	de,msg_bytes
		call	print_zero_string
		ld	a,(opt_bload)	; WORTH SAYING: the span above is
		or	a		;   the IMAGE's, and with /B the
		jr	z,main.wrote_entry	;   file is seven bytes bigger
		ld	de,msg_bload_header
		call	print_zero_string
main.wrote_entry:
		ld	a,(entry_given)
		or	a
		jr	z,main.wrote_stop
		ld	de,msg_entry_is
		call	print_zero_string
		ld	hl,(entry_address)
		call	print_hex_word
main.wrote_stop:
		ld	de,msg_full_stop
		call	print_zero_string
		jp	dos_exit
main.wrote_nothing:
		ld	de,msg_nothing_written
		call	print_zero_string
		jp	dos_exit

; check_entry_point - the entry point is not the first byte of the image.
;
;   MSX-DOS LOADS A .COM AT ITS START ADDRESS AND JUMPS THERE. The
;   address END named reaches the object file and the Wrote line and
;   nothing else ever reads it, so a program whose first bytes are a
;   message runs the message. examples/dirs did exactly that: 104
;   bytes of text, start at 0168h, and a machine that froze.
;
;   NOT UNDER /B: a BLOAD header carries an execution address and
;   BASIC jumps to it, so there the entry point means what it says.
;
;   AGAINST image_low AND NOT AGAINST 0100h, which are the same test for
;   a real .COM and differ only where the literal would be wrong:
;   with /P:, where the image was moved on purpose.
;
;   094 refused this warning because the segment order was not the
;   user's to control. 094 made it theirs, which is what turned noise
;   into advice.
;
; Input:	image_any, opt_bload, entry_given, entry_address,
;		image_low, output_name
; Output:	one line, or nothing at all
; Modifies:	AF, BC, DE, HL

check_entry_point:
		ld	a,(image_any)	; nothing written, nothing entered
		or	a
		ret	z
		ld	a,(opt_bload)
		or	a
		ret	nz		; the header carries it
		ld	a,(entry_given)
		or	a
		ret	z		; no module named one
		ld	hl,(entry_address)
		ld	de,(image_low)
		or	a
		sbc	hl,de
		ret	z		; the first byte, which is right
		ld	de,msg_warning
		call	print_zero_string
		ld	de,output_name
		call	print_zero_string_upper
		ld	de,msg_is_entered_at
		call	print_zero_string
		ld	hl,(image_low)
		call	print_hex_word
		ld	de,msg_not_at
		call	print_zero_string
		ld	hl,(entry_address)
		call	print_hex_word
		ld	de,msg_full_stop	; the Wrote line's full stop
		jp	print_zero_string	;   and newline, which is this
					;   one too

main.usage:	jp	print_usage
main.version:	call	print_version_banner
		jp	dos_exit

main.need_dos2:
		ld	de,msg_need_dos2
					; 09h, NOT print_dollar_string - see
		system	_STROUT		;   tatara.as main.need_dos2 for why
		jp	dos_exit
main.need_mapper:
		ld	de,msg_need_mapper
		call	print_dollar_string
		jp	dos_exit

; pass_two - pass 2: every module again, and this time its content.
;
;   THE COMMAND TAIL IS WALKED A SECOND TIME, in the same order. That
;   is what lets the table get away with storing no per-module base:
;   reset_segment_totals puts every segment's total back to zero and
;   pass 2's SEGDEF arm accumulates it again, so the total standing
;   when a module's
;   SEGDEF arrives is that module's base - the same arithmetic that
;   produced it the first time.
;
;   Every object file is opened, read and closed again. Its header is
;   checked a second time, which costs one read and means a file
;   replaced between the passes is caught rather than half-copied.
;
; Input:	every segment placed, every symbol final
; Output:	the image is built and written
; Modifies:	everything

pass_two:	call	image_init
		; the externals' values, in the mapper
		ld	bc,MODULE_EXTERNAL_MAX*2
		ld	hl,external_map
		call	halloc
		jp	c,error_out_of_memory
		call	reset_segment_totals	; every total back to zero
		xor	a
		ld	(entry_given),a
		call	objects_first
pass_two.next_file:
		call	objects_next
		jr	c,pass_two.all_read
		call	segments_new_module	; this module's maps, empty
		ld	hl,0
		; and it has declared no externals
		ld	(external_count),hl
		ld	de,object_name
		call	objfile_open
pass_two.record:
		call	objfile_next_record
		jr	c,pass_two.close
		call	pass2_record
		; whatever pass2_record did not read
		call	objfile_skip_record
		ld	a,(objfile_record_type)
		cp	RECORD_END
		jr	nz,pass_two.record
pass_two.close:	call	objfile_close
		jr	pass_two.next_file
pass_two.all_read:
		ld	a,(opt_bload)	; /B's header ALWAYS carries an
		or	a		;   execution address, and BSAVE's
		jr	z,pass_two.write	;   own rule is that it is the
		ld	a,(entry_given)	;   START address when nothing
		or	a		;   named one. Settling it here
		jr	nz,pass_two.write	;   means the summary line says
		ld	hl,(image_low)	;   what actually went into the
		ld	(entry_address),hl	;   header
		ld	a,0ffh
		ld	(entry_given),a
pass_two.write:	ld	hl,(entry_address)
		ld	a,(opt_bload)
		ld	de,output_name
		jp	image_save		; CY set = there was nothing to
					;   write, which image_any also says
					;   and the summary reads

; pass2_record - what pass 2 does with a record.
;
;   PUBDEF IS THE ONE RECORD IT DELIBERATELY DOES NOT READ. Pass 1
;   read it and every symbol already has its final value; reading it
;   again would report every public in the link as defined twice. The
;   absent arm is a decision and not an oversight, which is why this
;   comment exists.
;
;   MODNAME, GRPDEF and SEGDEF are read again so that this module's
;   group and segment indices mean something; EXTDEF so that its
;   external indices do; DATA and RELOC are the point of the pass.
;
; Input:	a record is open
; Output:	the image knows about it
; Modifies:	everything

pass2_record:	ld	a,(objfile_record_type)
		cp	RECORD_MODULE
		jp	z,pass2_record.module
		cp	RECORD_GROUP
		jp	z,pass2_record.group
		cp	RECORD_SEGMENT
		jp	z,pass2_record.segment
		cp	RECORD_EXTERNAL
		jp	z,pass2_record.external
		cp	RECORD_DATA
		jp	z,pass2_record.data
		cp	RECORD_RELOC
		jp	z,pass2_record.reloc
		cp	RECORD_ENTRY
		jp	z,pass2_record.entry
		ret			; PUBDEF, COMMENT, END, and any
					;   type this program does not know

pass2_record.module:
		ld	de,module_flags	; the flags byte, unused here, and
		ld	a,1		;   the name, for the messages that
		call	objfile_read_payload		;   name a module
		call	objfile_read_string
		jp	symbols_set_module

pass2_record.group:
		call	objfile_read_string
		jp	add_group

pass2_record.segment:
		ld	de,segdef_fields	; flags, group, size
		ld	a,4
		call	objfile_read_payload
		call	objfile_read_string
		jp	add_segment

					; EXTDEF repeats until its length is
pass2_record.external:
		ld	hl,(objfile_record_left)
		ld	a,h		;   used up, and every name takes the
		or	l		;   next external index
		ret	z
		call	objfile_read_string
		call	symbols_value		; -> what it came to
		call	external_add
		jr	pass2_record.external

; pass2_record.data - a DATA record: its content, into the image.
;
; Input:	a DATA record is open
; Output:	its bytes are in the image
; Modifies:	everything

pass2_record.data:
		ld	de,pass2_fields	; segment and offset
		ld	a,3
		call	objfile_read_payload
		ld	a,(pass2_fields)
		ld	hl,(pass2_fields+1)
		call	address_in_segment
		ld	(data_address),hl
pass2_record.data_run:
		ld	hl,(objfile_record_left)
		ld	a,h
		or	l
		ret	z
					; 255 at a time: objfile_read_payload
					; counts in a
		ld	a,h
		or	a		;   byte
		ld	a,0ffh
		; ld does not touch the flags
		jr	nz,pass2_record.data_count
		ld	a,l
pass2_record.data_count:
		ld	(data_count),a
					; THE NAME BUFFER: a DATA record has
		ld	de,objfile_string_buffer
					;   no string in it, so it is free
		call	objfile_read_payload
		ld	a,(data_count)
		ld	c,a
		ld	b,0
		ld	de,objfile_string_buffer
		ld	hl,(data_address)
		call	image_write_run
		ld	a,(data_count)	; and on by that much
		ld	c,a
		ld	b,0
		ld	hl,(data_address)
		add	hl,bc
		ld	(data_address),hl
		jp	pass2_record.data_run

; pass2_record.reloc - a RELOC record: every fixup in it, applied.
;
;   THE STORED WORD IS AN ADDEND, not a placeholder (spec 4): what
;   goes back is what was there plus the base or the value. An
;   external used with no addend stores 0000h, and adding to it is the
;   same operation.
;
; Input:	a RELOC record is open
; Output:	the image is patched
; Modifies:	everything

					; six bytes an entry; fewer than six
pass2_record.reloc:
		ld	hl,(objfile_record_left)
		ld	de,6		;   left is a malformed record, and
		or	a		;   objfile_skip_record has the rest
		sbc	hl,de
		ret	c
		ld	de,pass2_fields
		ld	a,6
		call	objfile_read_payload
		; WHERE THE WORD SITS: the segment holding it, and the offset
		;   within this module's part of it
		ld	a,(pass2_fields+1)
		ld	hl,(pass2_fields+2)
		call	address_in_segment
		ld	(fixup_address),hl
		ld	a,(pass2_fields)
		cp	1
		jr	z,pass2_record.external_target
		or	a
		; a kind this linker does not know
		jp	nz,error_truncated
		; kind 00: the TARGET segment's base, and this module's base in
		;   it - the addend is an offset into the contribution, exactly
		;   as a PUBDEF's is
		ld	a,(pass2_fields+4)
		cp	0ffh
		jr	z,pass2_record.absolute_target
		ld	hl,0
		call	address_in_segment
		jr	pass2_record.patch
pass2_record.absolute_target:
		ld	hl,0		; an absolute target: nothing to add
		jr	pass2_record.patch
pass2_record.external_target:
		; kind 01: the resolved external
		ld	hl,(pass2_fields+4)
		call	external_by_index
pass2_record.patch:
		ld	(fixup_addend),hl
		ld	hl,(fixup_address)	; the addend, out of the image,
		call	image_read_byte		;   low byte first
		ld	(fixup_word),a
		ld	hl,(fixup_address)
		inc	hl
		call	image_read_byte
		ld	(fixup_word+1),a
		ld	hl,(fixup_word)
		ld	de,(fixup_addend)
		add	hl,de
		ld	(fixup_word),hl
		ld	a,(fixup_word)	; and back it goes
		ld	hl,(fixup_address)
		call	image_write_byte
		ld	a,(fixup_word+1)
		ld	hl,(fixup_address)
		inc	hl
		call	image_write_byte
		jp	pass2_record.reloc

; pass2_record.entry - an ENTRY record: the first one in the link wins.
;
; Input:	an ENTRY record is open
; Output:	entry_address, entry_given
; Modifies:	everything

pass2_record.entry:
		ld	de,pass2_fields
		ld	a,3
		call	objfile_read_payload
		ld	a,(entry_given)
		or	a
		ret	nz		; somebody named one already
		ld	a,(pass2_fields)
		ld	hl,(pass2_fields+1)
		call	address_in_segment
		ld	(entry_address),hl
		ld	a,0ffh
		ld	(entry_given),a
		ret

; address_in_segment - a segment index and an offset, as an address.
;
;   SEGMENT FFh IS AN ADDRESS ALREADY (spec 10), which is decision 8's
;   answer: absolute content is written where it says, and the linker
;   does not judge where that is.
;
;   Everything else is an offset into THIS MODULE'S CONTRIBUTION, so
;   the segment's base and the module's base within it are both added.
;    symbols_add_public does the same arithmetic to a public's value, and for
;    the
;   same reason.
;
; Input:	A  = the segment index
;		HL = the offset
; Output:	HL = the address
; Modifies:	AF, BC, DE, HL

address_in_segment:
		cp	0ffh
		ret	z		; absolute: the offset IS the
		ld	(address_offset),hl	;   address
		; -> segment_own_base, segment_module_base
		call	segment_by_index
		ld	hl,(address_offset)
		ld	de,(segment_own_base)
		add	hl,de
		ld	de,(segment_module_base)
		add	hl,de
		ret

; external_add - the next external's resolved value.
;
; Input:	HL = the value
; Output:	the map holds it, external_count is one higher
;		(error_too_many_externals does not return)
; Modifies:	AF, BC, DE, HL

external_add:	ld	a,(external_count+1)
		cp	MODULE_EXTERNAL_MAX_HIGH
		jp	nc,error_too_many_externals
		ld	(external_value),hl
		ld	hl,(external_count)
		add	hl,hl		; two bytes each
		ld	c,l
		ld	b,h
		derefp	external_map	; BC survives it
		add	hl,bc
		; AFTER the deref: it destroys DE
		ld	de,(external_value)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	hl,(external_count)
		inc	hl
		ld	(external_count),hl
		ret

; external_by_index - the value of external index HL.
;
; Input:	HL = the index
; Output:	HL = its value
;		(error_truncated does not return)
; Modifies:	AF, BC, DE, HL

external_by_index:
		ld	de,(external_count)	; an index this module never
		or	a		;   declared can only come from a
		sbc	hl,de		;   broken file
		jp	nc,error_truncated
		add	hl,de		; back to the index
		add	hl,hl
		ld	c,l
		ld	b,h
		derefp	external_map
		add	hl,bc
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl
		ret

; pass1_record - what pass 1 does with a record.
;
;   ONE ROUTINE READS IT. A record's fields can be read once, and
;   GRPDEF and SEGDEF have to be read whether or not /D was given -
;   so those two are here, and printing is a VIEW of what they read.
;   Everything else is still only read in order to be printed.
;
; Input:	a record is open
; Output:	the tables know about it; it is printed if /D
; Modifies:	everything

pass1_record:	ld	a,(objfile_record_type)
		cp	RECORD_MODULE
		jr	z,pass1_record.module
		cp	RECORD_GROUP
		jp	z,pass1_record.group	; jp, NOT jr: three arms in
		cp	RECORD_SEGMENT	;   front of these two and pushed
		jp	z,pass1_record.segment	;   both past 127 bytes
		cp	RECORD_PUBLIC
		jp	z,pass1_record.public
		cp	RECORD_EXTERNAL
		jp	z,pass1_record.external
		ld	a,(opt_dump)	; a type pass 1 does not want:
		or	a		;   dump_record if it is to be seen,
		ret	z	;   and objfile_skip_record has it otherwise
		jp	dump_record

pass1_record.module:
		ld	de,module_flags	; the flags byte: WHICH CASE MODE
		ld	a,1		;   this module was assembled in
		call	objfile_read_payload
		call	objfile_read_string		; and its name
					; kept, for the messages that name
		call	symbols_set_module
					;   a module
		ld	a,(module_flags)
					; the mode on the first module, the
		call	symbols_set_case
					;   mixture check on the rest
		ld	a,(opt_dump)
		or	a
		ret	z
		ld	de,msg_modname
		call	print_zero_string
		ld	a,(module_flags)
		call	print_hex_byte
		call	print_space
		ld	de,objfile_string_buffer
		call	print_zero_string
		jp	print_newline

					; PUBDEF REPEATS until its length
pass1_record.public:
		ld	hl,(objfile_record_left)
		ld	a,h		;   is used up
		or	l
		ret	z
		ld	de,public_segment_offset	; segment, offset
		ld	a,3
		call	objfile_read_payload
		call	objfile_read_string		; and the name
		call	symbols_add_public
		ld	a,(opt_dump)
		or	a
		jr	z,pass1_record.public
		ld	de,msg_pubdef
		call	print_zero_string
		ld	a,(public_segment_offset)
		call	print_hex_byte
		ld	de,msg_field_offset
		call	print_zero_string
		ld	hl,(public_segment_offset+1)
		call	print_hex_word
		call	print_space
		ld	de,objfile_string_buffer
		call	print_zero_string
		call	print_newline
		jr	pass1_record.public

pass1_record.external:
		ld	hl,(objfile_record_left)	; EXTDEF repeats too
		ld	a,h
		or	l
		ret	z
		call	objfile_read_string
		call	symbols_add_external
		ld	a,(opt_dump)
		or	a
		jr	z,pass1_record.external
		ld	de,msg_extdef
		call	print_zero_string
		ld	de,objfile_string_buffer
		call	print_zero_string
		call	print_newline
		jr	pass1_record.external

					; the name, into objfile_string_buffer
pass1_record.group:
		call	objfile_read_string
		call	add_group
		ld	a,(opt_dump)
		or	a
		ret	z
		ld	de,msg_grpdef
		call	print_zero_string
		ld	de,objfile_string_buffer
		call	print_zero_string
		jp	print_newline

pass1_record.segment:
		ld	de,segdef_fields	; flags, group, size
		ld	a,4
		call	objfile_read_payload
		call	objfile_read_string		; and the name
		call	add_segment
		ld	a,(opt_dump)
		or	a
		ret	z
		ld	de,msg_segdef
		call	print_zero_string
		ld	a,(segdef_fields)
		call	print_hex_byte
		ld	de,msg_field_group
		call	print_zero_string
		ld	a,(segdef_fields+1)
		call	print_hex_byte
		ld	de,msg_field_size
		call	print_zero_string
		ld	hl,(segdef_fields+2)
		call	print_hex_word
		call	print_space
		ld	de,objfile_string_buffer
		call	print_zero_string
		jp	print_newline

; dump_record - one record, decoded as far as its type is known.
;
;   Each arm reads the fields it understands and leaves the rest to
;   main.record's objfile_skip_record. An unknown type reads nothing at
;   all, which is exactly the behaviour spec 5 promises and the reason
;   the length is in the file.
;
; Input:	objfile_record_type, objfile_record_left
; Output:	one or more lines
; Modifies:	everything

dump_record:	ld	a,(objfile_record_type)
		cp	RECORD_DATA
		jp	z,dump_record.data
		cp	RECORD_RELOC
		jp	z,dump_record.reloc
		cp	RECORD_ENTRY
		jp	z,dump_record.entry
		cp	RECORD_END
		jp	z,dump_record.end
		; a type this program does not know
		ld	de,msg_unknown_record
		call	print_zero_string
		ld	a,(objfile_record_type)
		call	print_hex_byte
		jr	print_newline

print_newline:	ld	de,msg_line_end
		jp	print_zero_string

; PUBDEF and EXTDEF hold as many entries as their length allows, so
; both loop on objfile_record_left and print a line each.

; DATA prints its header and THE FIRST EIGHT BYTES. All of them would
; be six thousand bytes of hex for tatara.tro, and the header is what
; a reader of this dump is checking.

dump_record.data:
		ld	de,msg_data_record
		call	print_zero_string
		ld	de,dump_fields	; segment, offset
		ld	a,3
		call	objfile_read_payload
		ld	a,(dump_fields)
		call	print_hex_byte
		ld	de,msg_field_offset
		call	print_zero_string
		ld	hl,(dump_fields+1)
		call	print_hex_word
		ld	de,msg_field_len
		call	print_zero_string
					; WHAT IS LEFT IS THE CONTENT: the
		ld	hl,(objfile_record_left)
		call	print_hex_word	;   payload was segment, offset and
		call	print_space	;   this, which is why the content
					;   is length-3 and not length-5
		ld	hl,(objfile_record_left)
		ld	a,h
		or	a
		jr	nz,dump_record.eight	; more than 255: eight of them
		ld	a,l
		cp	9
		; fewer than eight: all of them
		jr	c,dump_record.data_count
dump_record.eight:
		ld	a,8
dump_record.data_count:
		or	a
		jp	z,print_newline	; a run of no bytes at all
		ld	(bytes_left),a
dump_record.data_byte:
		ld	de,data_byte
		ld	a,1
		call	objfile_read_payload
		ld	a,(data_byte)
		call	print_hex_byte
		call	print_space
		ld	hl,bytes_left
		dec	(hl)
		jr	nz,dump_record.data_byte
		jp	print_newline

; RELOC prints how many fixups it holds. Six bytes an entry, and the
; division is a subtraction loop because six is not a power of two -
; a table of fixups is tens of entries, not thousands.

dump_record.reloc:
		ld	de,msg_reloc
		call	print_zero_string
		ld	hl,(objfile_record_left)
		ld	de,6
		ld	c,0
dump_record.count_loop:
		ld	a,h
		or	l
		jr	z,dump_record.count_done
		or	a
		sbc	hl,de
		; not a multiple of six: the record is malformed, but do not
		;   spin
		jr	c,dump_record.count_done
		inc	c
		jr	dump_record.count_loop
dump_record.count_done:
		ld	l,c
		ld	h,0
		call	print_decimal
		ld	de,msg_field_fixups
		call	print_zero_string
		jp	print_newline

dump_record.entry:
		ld	de,msg_entry
		call	print_zero_string
		ld	de,dump_fields	; segment, offset
		ld	a,3
		call	objfile_read_payload
		ld	a,(dump_fields)
		call	print_hex_byte
		ld	de,msg_field_offset
		call	print_zero_string
		ld	hl,(dump_fields+1)
		call	print_hex_word
		jp	print_newline

dump_record.end:
		ld	de,msg_end_record
		call	print_zero_string
		jp	print_newline

; print_string_field - the next string field, printed.
;
; Input:	a record is open and the next field is a string
; Output:	the name is printed
; Modifies:	everything

print_string_field:
		call	objfile_read_string
		ld	de,objfile_string_buffer
		jp	print_zero_string

; print_hex_byte, print_hex_word - a byte and a word, in hex, and one space.
;
; Input:	A, or HL
; Output:	two or four digits
; Modifies:	everything

print_hex_byte:	ld	de,hex_digits
		call	build_hex_byte
		ld	de,hex_digits
		ld	hl,hex_digits+2
		ld	(hl),0
		jp	print_zero_string

print_hex_word:	ld	de,hex_digits
		call	build_hex_word
		ld	hl,hex_digits+4
		ld	(hl),0
		ld	de,hex_digits
		jp	print_zero_string

print_space:	ld	de,msg_one_space
		jp	print_zero_string

		dseg

record_count:	defs	2	; how many records have been read
external_map:	defs	4	; PASS 2: every external this module
				;   declared, by index, and what it came
				;   to. A word each, IN THE MAPPER
external_count:	defs	2	; how many it has declared so far
external_value:	defs	2	; one value, across a deref
pass2_fields:	defs	6	; the fixed fields of the record being
				;   read: DATA's and ENTRY's three, and
				;   RELOC's six
data_address:	defs	2	; pass2_record.data: where this run is going
data_count:	defs	1	;   and how much of it comes next
address_offset:	defs	2	; address_in_segment: the offset,
				;   across segment_by_index
fixup_address:	defs	2	; pass2_record.reloc: the word being patched,
fixup_addend:	defs	2	;   what is being added to it, and
fixup_word:	defs	2	;   the word itself
entry_given:	defs	1	; 0FFh once some module has named an
entry_address:	defs	2	;   entry point, and what it came to
trailing_bytes:	defs	1	; non-zero = bytes follow the last one
module_flags:	defs	1	; a one-byte field, before it is printed
dump_fields:	defs	4	; the fixed fields of the record being
				;   dumped: the longest is SEGDEF's four
data_byte:	defs	1	; one DATA byte, on its way to the screen
bytes_left:	defs	1	;   and how many are still to come
hex_digits:	defs	5	; build_hex_word's answer, zero-terminated

msg_records:	defb	" records, ",0
msg_wrote:	defb	"Wrote ",0
msg_comma:	defb	", ",0
msg_dash:	defb	"-",0
msg_open_paren:	defb	" (",0
msg_bytes:	defb	" bytes)",0
msg_bload_header:
		defb	", BLOAD header",0
msg_entry_is:	defb	", entry ",0
msg_full_stop:	defb	".",CHR_CR,CHR_LF,0
msg_warning:	defb	"WARNING: ",0	; check_entry_point, which says both
msg_is_entered_at:
		defb	" is entered at ",0 ;   addresses because /Q may
msg_not_at:	defb	", not at ",0	;   have hidden the summary
msg_nothing_written:
		defb	"Nothing to write: no module has any"
		defb	" content.",CHR_CR,CHR_LF,0
msg_bytes_after_end:
		defb	": bytes follow the END record.",CHR_CR
		defb	CHR_LF,0
msg_ends_at_eof:
		defb	"ends at EOF.",CHR_CR,CHR_LF,0
msg_and_bytes_after:
		defb	"AND BYTES AFTER THEM.",CHR_CR,CHR_LF,0
msg_line_end:	defb	CHR_CR,CHR_LF,0
msg_one_space:	defb	" ",0
msg_modname:	defb	"MODNAME  flags ",0
msg_grpdef:	defb	"GRPDEF   ",0
msg_segdef:	defb	"SEGDEF   flags ",0
msg_modules_read:
		defb	" modules, ",0
msg_pubdef:	defb	"PUBDEF   seg ",0
msg_extdef:	defb	"EXTDEF   ",0
msg_data_record:
		defb	"DATA     seg ",0
msg_reloc:	defb	"RELOC    ",0
msg_entry:	defb	"ENTRY    seg ",0
msg_end_record:	defb	"END",0
msg_field_group:
		defb	" group ",0
msg_field_size:	defb	" size ",0
msg_field_offset:
		defb	" offset ",0
msg_field_len:	defb	" len ",0
msg_field_fixups:
		defb	" fixups",0
msg_unknown_record:
		defb	"(unknown record type ",0
msg_need_dos2:	defb	"ERROR: Tanren needs MSX-DOS2 or Nextor."
		defb	CHR_CR,CHR_LF,"$"
msg_need_mapper:
		defb	"ERROR: Tanren needs a memory mapper.",CHR_CR
		defb	CHR_LF,"$"
