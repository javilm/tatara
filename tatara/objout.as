; objout.as - the relocatable object file Tatara produces.
;
;   tatara-obj-spec.md draft 2 is the format, and this module writes
;   it. The first step was a valid empty module: the header, MODNAME
;   and END.
;
;   NOTHING IS BUFFERED, and plan.md's "second ~1 KB the data segment
;   has to find" is not needed. Every record's length is known before
;   its first byte goes out - a MODNAME is two bytes and a name, an END
;   is nothing, and the DATA record is emitted_count, which emitted_bytes
;   already holds. The data cost of this module is twenty bytes.
;
;   the records are the assembler's own tables written out, so this
;   module walks symbol_table, segment_table and group_table through hash.inc.
;   THE NAMES IN THEM ARE IN THE MAPPER: see write_mapped_name.
;
;   the are what the assembler emitted, and they are written WHILE
;   pass 2 runs rather than at the end of it. A DATA record's length is
;   not known until the run it describes ends, so the header goes out
;   with a placeholder and close_data_run seeks back for it - which means that
;   WHILE A RUN IS OPEN, NOTHING ELSE MAY BE WRITTEN TO THE FILE.
;
;   IF NO OUTPUT FILE WAS NAMED, object_wanted is zero and every entry point
;   returns at once. That is what lets the whole test suite, which runs
;   "tatara /p", go on writing nothing at all.

OBJOUT_INCLUDED	equ	1		; skips the externals in objout.inc

		public	object_open
		public	write_tables
		public	object_data
		public	object_fixup
		public	object_entry
		public	object_finish
		public	object_delete
		public	object_wanted

		include	objout.inc
		include	cmdline.inc	; object_name, source_name, opt_case
		include	msxdos.inc	; _CREATE, _WRITE, _CLOSE
		include	errs.inc
				; error_write_failed, error_public_undefined
		include	hash.inc	; HT_CASE_SENSITIVE, htnext,
					;   HT_KEY_LENGTH
		include	symtab.inc	; the three tables and their
					;   layouts, segment_count,
					;   group_count, park_counter
		include	alloc.inc	; deref, for derefp
		include	farptr.inc	; derefp, NULL_OFFSET
		include	emit.inc
		; emitted_count, emitted_bytes, line_address, line_segment,
					;   EMIT_MAX
		include	expr.inc
			; value_type, external_index, SY_ABS, SY_EXTERNAL

		cseg

object_magic:	defb	"TRO",01ah,OBJECT_VERSION

; object_open - create the object file and write its five-byte header.
;
;   The Ctrl-Z is deliberate (spec 9): TYPEing an object file prints
;   "TRO" and stops, instead of spraying the screen.
;
;   It runs at the START OF PASS 2, beside open_output and for the same
;   reason - a source that cannot be assembled must not truncate a file
;   the user already had.
;
; Input:	nothing (object_name)
; Output:	CY set = the file could not be created
; Modifies:	AF, BC, DE, HL

object_open:	xor	a
		; nothing is open, whatever happens
		ld	(object_wanted),a
		ld	(entry_given),a	; END named no address yet - pass 1
					;   may have said one, and pass 2
					;   will say it again
		ld	hl,NULL_OFFSET
		; and no fixups: an empty chain, and
		ld	(fixup_head+2),hl
		; a head block that is "full", so
		ld	a,FIXUPS_PER_BLOCK
		; the first fixup allocates one
		ld	(fixup_head_count),a
		xor	a
		ld	a,(object_name)
		or	a
		ret	z		; none named: CY is clear and every
					;   other entry point is a ret
		ld	de,object_name
		xor	a		; mode 0 = read and write
		ld	b,a		; attributes 0 = an ordinary file
		system	_CREATE		; -> A = error, B = the handle
		or	a
		scf
		ret	nz
		ld	a,b
		ld	(object_handle),a
		ld	a,0ffh
		ld	(object_wanted),a
		ld	de,object_magic
		ld	a,5
		call	write_bytes
		or	a		; CY clear: the file is open
		ret

; write_bytes - A bytes at DE, straight to the object file.
;
; Input:	DE -> the bytes
;		A  = how many
; Output:	they are written
; Modifies:	AF, BC, HL

write_bytes:	or	a
		ret	z		; nothing to write
		ld	l,a
		ld	h,0
		ld	a,(object_handle)
		ld	b,a
		system	_WRITE		; -> A = the error
		or	a
		ret	z
		jp	error_write_failed	; disk full, or write-protected

; write_record_header - a record header: the type byte and the payload's
; length.
;
; Input:	A  = the record type
;		HL = how long the payload is
; Output:	three bytes are written
; Modifies:	AF, BC, DE, HL

write_record_header:
		ld	(record_header),a
		ld	(record_header+1),hl
		ld	de,record_header
		ld	a,3
		jp	write_bytes

; write_string - a counted string: one length byte, then that many bytes.
;
; Input:	DE -> the text
;		A  = how long it is, 1 to 255
; Output:	1+A bytes are written
; Modifies:	AF, BC, DE, HL

write_string:	push	af
		push	de
		call	write_byte	; the length
		pop	de
		pop	af
		jp	write_bytes	; and that many bytes

; write_byte - the byte in A, on its own. Four callers and counting: a
;   record that is mostly one-byte fields is what this format is.
;
; Input:	A = the byte
; Output:	it is written
; Modifies:	AF, BC, DE, HL

write_byte:	ld	(one_byte),a
		ld	de,one_byte
		ld	a,1
		jp	write_bytes

; write_tables - the records the linker's first pass reads.
;
;   THE ORDER IS THE SPEC'S (10): an index may only be named after the
;   record that creates it. A SEGDEF names a group, a PUBDEF names a
;   segment, so groups come before segments and segments before both
;   symbol lists.
;
;   IT RUNS AT THE END OF PASS 1, from main.pass_done. A SEGDEF carries the
;   segment's size, and segment_reset zeroes every size at the start of a
;   pass - by the time pass 2 begins, the numbers this needs are gone.
;
; Input:	nothing
; Output:	the records are written
; Modifies:	AF, BC, DE, HL

write_tables:	ld	a,(object_wanted)
		or	a
		ret	z
		call	park_counter	; the current contribution's size
					;   is still live in location_counter:
					;   until this runs its SEGMENT_SIZE is
					;   short
		call	write_modname
		call	write_groups
		call	write_segments
		call	write_externals
		jp	write_publics

; write_modname - MODNAME: the flags byte and the module's name.
;
; Input:	nothing
; Output:	the record is written
; Modifies:	AF, BC, DE, HL

write_modname:	call	module_name	; DE -> the module's name, A = how
		ld	l,a		;   long it is
		ld	h,0
		push	hl	; the length has to outlive write_record_header
					;   and write_bytes: both end in a BDOS
					;   call, and a BDOS call modifies BC
		inc	hl
		inc	hl		; the flags byte and the length byte
		push	de
		ld	a,RECORD_MODULE
		call	write_record_header
		ld	a,(opt_case)	; bit 0 says how SYMBOLS were
		cp	HT_CASE_SENSITIVE	;   compared, not how the
		ld	a,0		;   name happened to be typed
		jr	nz,write_modname.flags
		inc	a
write_modname.flags:
		call	write_byte
		pop	de		; the name
		pop	hl		; and its length, untouched
		ld	a,l
		jp	write_string

; write_groups - a GRPDEF for every group, in the order of the numbers
;   group_directive handed out, because that order IS the file's group index.
;
; Input:	nothing (group_count)
; Output:	the records are written
; Modifies:	AF, BC, DE, HL, IX

write_groups:	xor	a
		ld	(wanted_index),a
write_groups.loop:
		ld	a,(group_count)
		ld	hl,wanted_index
		cp	(hl)
		ret	z
		ld	ix,group_table
		ld	c,0		; a group record's payload IS its
		call	find_by_index	;   number
		ret	c
		call	map_record_key	; A = the name's length
		ld	l,a
		ld	h,0
		inc	hl		; and the length byte
		ld	a,RECORD_GROUP
		call	write_record_header
		ld	c,0
		call	write_mapped_name
		ld	hl,wanted_index
		inc	(hl)
		jp	write_groups.loop

; write_segments - a SEGDEF for every segment but the ASEG, in index order for
;   the same reason.
;
;   INDEX 0 IS THE ASEG and gets no record: an absolute segment is not
;   one the linker places. Everything else is therefore one lower in
;   the file than it is here, which is what write_publics subtracts.
;
; Input:	nothing (segment_count)
; Output:	the records are written
; Modifies:	AF, BC, DE, HL, IX

write_segments:	ld	a,1
		ld	(wanted_index),a
write_segments.loop:
		ld	a,(segment_count)
		ld	hl,wanted_index
		cp	(hl)
		ret	z
		ld	ix,segment_table
		ld	c,SEGMENT_INDEX
		call	find_by_index
		ret	c
		call	map_record_payload	; the fields, out of the mapper
		ld	de,SEGMENT_SIZE	;   BEFORE anything is written
		add	hl,de
		ld	a,(hl)
		ld	(record_size),a
		inc	hl
		ld	a,(hl)
		ld	(record_size+1),a
		inc	hl
		ld	a,(hl)	; SEGMENT_FLAGS: the file defines two of
		and	SEGMENT_IS_DATA+SEGMENT_IS_TRANSIENT
					; them and reserves the rest
		ld	(record_flags),a
		inc	hl
		ld	a,(hl)	; SEGMENT_GROUP - and GROUP_NONE is the same
		; 0FFh the file uses for "none"
		ld	(record_group_byte),a
		call	map_record_key	; A = the key: the group byte, then
		dec	a		;   the name
		ld	l,a
		ld	h,0
		ld	de,5		; flags, group, size, length byte
		add	hl,de
		ld	a,RECORD_SEGMENT
		call	write_record_header
		ld	a,(record_flags)
		call	write_byte
		ld	a,(record_group_byte)
		call	write_byte
		ld	de,record_size
		ld	a,2
		call	write_bytes
		ld	c,1		; skip the key's group byte
		call	write_mapped_name
		ld	hl,wanted_index
		inc	(hl)
		jp	write_segments.loop

; write_externals - an EXTDEF for every external, and the index the file gives
;   it written back into the symbol.
;
;   THE RENUMBERING IS THE POINT. The walk is in bucket order, not the
;   order EXTRN declared them, and the file numbers by record order -
;   so the two would disagree unless one of them moves. Rewriting
;   SYMBOL_VALUE is safe HERE AND ONLY HERE: this runs at the end of pass 1,
;   and the first record that quotes an external index is the RELOC,
;   written in pass 2. It must not move.
;
; Input:	nothing
; Output:	the records are written, SYMBOL_VALUE renumbered
; Modifies:	AF, BC, DE, HL, IX

write_externals:
		call	walk_first
		xor	a
		ld	(wanted_index),a	; the index the next name takes
write_externals.loop:
		ld	ix,symbol_table
		ld	hl,table_walk
		call	htnext
		ret	c
		call	map_record_payload
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	a,(hl)
		and	SYMBOL_EXTERNAL
		jp	z,write_externals.loop
		call	map_record_key
		ld	l,a
		ld	h,0
		inc	hl
		ld	a,RECORD_EXTERNAL
		call	write_record_header
		ld	c,0
		call	write_mapped_name
		; SYMBOL_VALUE = the index it just took
		call	map_record_payload
		ld	a,(wanted_index)
		ld	(hl),a
		inc	hl
		ld	(hl),0		; EXTERNAL_MAX keeps it inside one byte
		ld	hl,wanted_index
		inc	(hl)
		jp	write_externals.loop

; write_publics - a PUBDEF for every public symbol.
;
; Input:	nothing
; Output:	the records are written
;		(error_public_undefined does not return)
; Modifies:	AF, BC, DE, HL, IX

write_publics:	call	walk_first
write_publics.loop:
		ld	ix,symbol_table
		ld	hl,table_walk
		call	htnext
		ret	c
		call	map_record_payload
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	a,(hl)
		ld	(record_flags),a
		and	SYMBOL_PUBLIC
		jp	z,write_publics.loop
		ld	a,(record_flags)
		and	SYMBOL_DEFINED
		jp	z,error_public_undefined
					; PUBLIC promised it and nothing in
					;   the module ever gave it a value
		call	map_record_payload
		ld	a,(hl)		; SYMBOL_VALUE: the offset
		ld	(record_size),a
		inc	hl
		ld	a,(hl)
		ld	(record_size+1),a
		inc	hl
		ld	a,(hl)		; SYMBOL_TYPE: its segment, as the FILE
		call	file_segment_index	;   numbers it
		ld	(record_group_byte),a
		call	map_record_key
		ld	l,a
		ld	h,0
		ld	de,4		; the segment, the offset, and the
		add	hl,de		;   length byte
		ld	a,RECORD_PUBLIC
		call	write_record_header
		ld	a,(record_group_byte)
		call	write_byte
		ld	de,record_size
		ld	a,2
		call	write_bytes
		ld	c,0
		call	write_mapped_name
		jp	write_publics.loop

; walk_first - a walk, back to the beginning.
;
; Input:	nothing
; Output:	table_walk is before the first record
; Modifies:	AF, HL

walk_first:	xor	a
		ld	(table_walk),a	; bucket 0...
		ld	hl,NULL_OFFSET
		ld	(table_walk+3),hl	; ...and no record yet
		ret

; find_by_index - the record in table IX whose payload byte at offset C is
;   (wanted_index).
;
;   THE WALK IS RESTARTED FOR EVERY INDEX. htnext hands records back in
;   bucket order and a SEGDEF's position in the file is its index, so
;   one or the other has to be a walk per index - and a table of three
;   to ten records is the cheaper one to walk twice. An index-ordered
;   list would cost four bytes of resident RAM per segment to save a
;   few hundred microseconds, once.
;
; Input:	IX = the table's descriptor
;		C  = the byte's offset inside the payload
;		(wanted_index) = the index wanted
; Output:	CY clear = table_walk is on it
;		CY set   = no record has it
; Modifies:	AF, BC, DE, HL

find_by_index:	call	walk_first
find_by_index.loop:
		push	bc
		ld	hl,table_walk
		call	htnext		; CY set = that was the last one
		pop	bc
		ret	c
		push	bc
		call	map_record_payload
		pop	bc
		ld	b,0
		add	hl,bc
		ld	a,(hl)
		ld	hl,wanted_index
		cp	(hl)
		jr	nz,find_by_index.loop
		or	a		; found it, and table_walk is on it
		ret

; map_record_key - the record table_walk is on, mapped.
;
;   EVERY BDOS CALL UNDOES THIS. MSX-DOS takes page 2 back for itself,
;   so a pointer returned here is worth nothing after the next write
;   and write_mapped_name calls it again for every character.
;
; Input:	table_walk is on a record
; Output:	HL -> the key, A = the key's length
; Modifies:	AF, BC, DE, HL

map_record_key:	derefp	table_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)
		inc	hl
		ret

; map_record_payload - the same record's payload.
;
; Input:	table_walk is on a record
; Output:	HL -> the payload, A = the key's length
; Modifies:	AF, BC, DE, HL

map_record_payload:
		call	map_record_key
		ld	e,a
		ld	d,0
		add	hl,de
		ret

; write_mapped_name - a counted string whose bytes are in the MAPPER.
;
;   The name cannot be handed to write_bytes as a buffer: page 2 belongs to
;   MSX-DOS during the write, and what _WRITE would read is whatever
;   DOS has mapped there. dump_symbols met this first and answered it the
;   same way - map the record again for each character. One BDOS call
;   per character, into a sector buffer, a few hundred times in an
;   assembly.
;
;   The alternative is a resident buffer, and its size would quietly
;   become the longest name a module may export. There is no such limit
;   today and this note does not introduce one.
;
; Input:	table_walk is on the record
;		C  = key bytes in front of the name: 0 for a symbol or
;		     a group, 1 for a segment, whose key is the group
;		     byte and then the name
; Output:	1 + (the key's length - C) bytes are written
; Modifies:	AF, BC, DE, HL

write_mapped_name:
		ld	a,c
		ld	(name_key_skip),a
		call	map_record_key	; A = the whole key's length
		ld	hl,name_key_skip
		sub	(hl)
		ld	(name_length),a
		call	write_byte	; the length byte
		xor	a
		ld	(name_at),a	; which character we are on
write_mapped_name.loop:
		ld	a,(name_at)
		ld	hl,name_length
		cp	(hl)
		ret	z
		call	map_record_key	; the record again: see above
		ld	a,(name_key_skip)
		ld	e,a
		ld	a,(name_at)
		add	a,e
		ld	e,a
		ld	d,0
		add	hl,de
		ld	a,(hl)
		call	write_byte
		ld	hl,name_at
		inc	(hl)
		jr	write_mapped_name.loop

; file_segment_index - a segment index as the FILE numbers it.
;
;   Internally the ASEG is 0, the classic CSEG 1, the classic DSEG 2.
;   The ASEG gets no SEGDEF, so the file is one behind - and an
;   absolute value is FFh, which is the file's way of saying "this is
;   an address, do not relocate it".
;
; Input:	A = the index this program uses
; Output:	A = the index the file uses
; Modifies:	AF

file_segment_index:
		or	a
		jr	z,file_segment_index.absolute
		dec	a
		ret
file_segment_index.absolute:
		ld	a,0ffh		; the ASEG: an address, not an
		ret			;   offset into anything

; write_word - the word in HL, low byte first, which is the format's order
;   and the Z80's.
;
; Input:	HL = the word
; Output:	two bytes are written
; Modifies:	AF, BC, DE, HL

write_word:	ld	(record_size),hl
		ld	de,record_size
		ld	a,2
		jp	write_bytes

; remember_position - where the file pointer is now, kept for seek_remembered.
;
;   Seeking zero bytes from where we are is how MSX-DOS is asked.
;
; Input:	nothing
; Output:	run_length_at
; Modifies:	AF, BC, DE, HL

remember_position:
		ld	hl,0
		ld	de,0
		ld	a,(object_handle)
		ld	b,a
		ld	a,1		; 1 = from here, and +0 asks rather
		system	_SEEK		;   than moves
		or	a
		jp	nz,error_write_failed
		ld	(run_length_at),de
		ld	(run_length_at+2),hl
		ret

; seek_remembered, seek_end - to the length field the run left behind, and back
; to the end of the file afterwards.
;
; Input:	run_length_at (seek_remembered)
; Output:	the pointer has moved
; Modifies:	AF, BC, DE, HL

seek_remembered:
		ld	hl,(run_length_at+2)
		ld	de,(run_length_at)
		ld	a,(object_handle)
		ld	b,a
		xor	a		; 0 = from the beginning
		system	_SEEK
		or	a
		jp	nz,error_write_failed
		ret

seek_end:	ld	hl,0
		ld	de,0
		ld	a,(object_handle)
		ld	b,a
		ld	a,2		; 2 = from the end, which is where
		system	_SEEK		;   the next record goes
		or	a
		jp	nz,error_write_failed
		ret

; open_data_run - open a DATA run: everything but its length.
;
;   The length goes out as a placeholder and close_data_run comes back for it,
;   because a run's length is not known until the run ends. remember_position
;   is called AFTER the type byte, so what it remembers is exactly where the
;   length field sits.
;
; Input:	A  = the segment, as the file numbers it
;		HL = where the run starts, within that segment
; Output:	the header is written and the run is open
; Modifies:	AF, BC, DE, HL

open_data_run:	ld	(run_segment),a
		ld	(run_start),hl
		ld	(run_next),hl
		ld	a,RECORD_DATA
		call	write_byte
		; where the length will have to go
		call	remember_position
		ld	hl,0
		call	write_word	; and a placeholder to hold its place
		ld	a,(run_segment)
		call	write_byte
		ld	hl,(run_start)
		call	write_word
		ld	a,0ffh
		ld	(run_open),a
		ret

; close_data_run - close the open run, if there is one.
;
; Input:	nothing
; Output:	the record's length is written and the pointer is back
;		at the end of the file
; Modifies:	AF, BC, DE, HL

close_data_run:	ld	a,(run_open)
		or	a
		ret	z
		xor	a
		ld	(run_open),a
		ld	hl,(run_next)	; the payload is the segment byte,
		ld	de,(run_start)	;   the offset, and everything
		or	a		;   between where the run started and
		sbc	hl,de		;   where it stopped
		ld	de,3
		add	hl,de
		push	hl
		call	seek_remembered
		pop	hl
		call	write_word
		jp	seek_end

; object_data - the bytes this line emitted.
;
;   CALLED FOR EVERY LINE OF PASS 2, from main.emit_line, and before
;   main.emit_line's tests: it returns early when neither /P nor /L
;   was given, and the object file is written when neither was.
;
;   A line that emits nothing does nothing here. A run is not broken by
;   a comment or a CSEG line; it is broken by the next line that emits
;   somewhere other than where the run stopped, which is one test and
;   covers ORG, DS, a segment change, and whatever is invented later.
;
; Input: nothing (emitted_count, emitted_bytes, line_address, line_segment)
; Output:	the bytes are in the file
; Modifies:	AF, BC, DE, HL

object_data:	ld	a,(object_wanted)
		or	a
		ret	z
		ld	hl,(emitted_count)
		ld	a,h
		or	l
		ret	z		; nothing emitted: nothing to say
		ld	a,(run_open)	; the EMIT_MAX assertion moved to
					;   main.emit_line: it belongs where it
					;   runs whether or not a file is open
		or	a
		jr	z,object_data.open
		ld	a,(line_segment)
					; the same segment as the open run,
		; and no gap since it stopped?
		call	file_segment_index
		ld	hl,run_segment
		cp	(hl)
		jr	nz,object_data.restart
		ld	hl,(line_address)
		ld	de,(run_next)
		or	a
		sbc	hl,de
		jr	z,object_data.write	; then it carries on
object_data.restart:
		call	close_data_run
object_data.open:
		ld	a,(line_segment)
		call	file_segment_index
		ld	hl,(line_address)
		call	open_data_run
object_data.write:
		ld	de,emitted_bytes
		ld	hl,(emitted_count)
		ld	a,h
		or	a
		jr	z,object_data.byte	; the worst line is 256 bytes,
		ld	a,128		;   one more than write_bytes takes, so
		call	write_bytes	;   it goes out in halves
		ld	de,emitted_bytes+128
		ld	a,128
		call	write_bytes
		jr	object_data.advance
object_data.byte:
		ld	a,l
		call	write_bytes
object_data.advance:
		ld	hl,(run_next)
		ld	de,(emitted_count)
		add	hl,de
		ld	(run_next),hl
		ret

; object_fixup - remember that the word about to go out has a hole in it.
;
;   CALLED FROM emit_expr_word, which is the only routine that turns an
;   expression into a word - every 16-bit operand, every DW. value_type is
;   still the type of the value it just evaluated, which is what says
;   whether there is a hole at all.
;
;   The entry is built in ordinary RAM and copied into the table,
;   because the table is in the mapper.
;
; Input:	HL = the word's offset within its segment
;		(value_type, external_index, line_segment)
; Output:	an entry, if the value needs one
; Modifies:	AF, BC, DE, HL

object_fixup:	ld	a,(object_wanted)
		or	a
		ret	z
		ld	a,(value_type)
		or	a
		ret	z		; SY_ABS: a plain number, no hole
		ld	(fixup_entry+2),hl	; where the hole is
		cp	SY_EXTERNAL
		jr	z,object_fixup.external
		call	file_segment_index	; a segment: the target is that
		ld	l,a		;   segment, as the FILE numbers it
		ld	h,0
		ld	(fixup_entry+4),hl
		xor	a		; kind 0: add the segment's base
		jr	object_fixup.store
object_fixup.external:
		ld	hl,(external_index)
					; an external: the target is its
		; index, and the index is a WORD
		ld	(fixup_entry+4),hl
		ld	a,1		; kind 1: add the import's value
object_fixup.store:
		ld	(fixup_entry),a
		ld	a,(line_segment)	; whose content holds the hole
		call	file_segment_index
		ld	(fixup_entry+1),a
		jr	fixup_add

; fixup_add - the entry in fixup_entry, into the table.
;
; Input:	fixup_entry
; Output:	it is in the head block
; Modifies:	AF, BC, DE, HL

fixup_add:	ld	a,(fixup_head_count)
		cp	FIXUPS_PER_BLOCK
		call	nc,fixup_new_block	; full, or there is none yet
		ld	a,(fixup_head_count)	; FIXUP_ENTRIES + n*6
		call	fixup_offset
		push	hl
		derefp	fixup_head
		pop	de
		add	hl,de
		ex	de,hl
		ld	hl,fixup_entry
		ld	bc,6
		ldir
		ld	a,(fixup_head_count)
		inc	a
		ld	(fixup_head_count),a
		derefp	fixup_head	; the count lives in the block as
		ld	de,FIXUP_COUNT	;   well, because write_relocs reads it
		add	hl,de	;   there and fixup_head_count will have moved
		ld	a,(fixup_head_count)	;   on to another block by then
		ld	(hl),a
		ret

; fixup_offset - where entry A sits inside a block.
;
; Input:	A = which entry
; Output:	HL = FIXUP_ENTRIES + A*6
; Modifies:	AF, DE, HL

fixup_offset:	ld	l,a
		ld	h,0
		ld	e,l
		ld	d,h
		add	hl,hl		; *2
		add	hl,de		; *3
		add	hl,hl		; *6
		ld	de,FIXUP_ENTRIES
		add	hl,de
		ret

; fixup_new_block - another block, at the head of the chain.
;
;   The newest block is the head, so write_relocs walks the blocks newest
;   first. A reader takes RELOC entries in any order (spec 06h), so
;   nothing has to be reversed.
;
; Input:	nothing
; Output:	an empty head block (error_out_of_memory does not return)
; Modifies:	AF, BC, DE, HL

fixup_new_block:
		ld	bc,FIXUP_BLOCK_SIZE
		ld	hl,fixup_new
		call	halloc
		jp	c,error_out_of_memory
		derefp	fixup_new	; its FIXUP_NEXT is the old head
		ex	de,hl
		ld	hl,fixup_head
		ld	bc,4
		ldir
		fpcopy	fixup_head,fixup_new	; and it becomes the head
		xor	a
		ld	(fixup_head_count),a
		ret

; write_relocs - one RELOC record per block.
;
;   The count is in the block, so the record's length is known before
;   its first byte and nothing has to be counted or seeked. Each entry
;   is copied into ordinary RAM before it is written: page 2 belongs to
;   MSX-DOS during a BDOS call, which is the hazard write_mapped_name met
;   first.
;
; Input:	nothing
; Output:	the records are written
; Modifies:	AF, BC, DE, HL

write_relocs:	fpcopy	fixup_walk,fixup_head
write_relocs.loop:
		fpnull	fixup_walk
		ret	z		; the chain's end
		derefp	fixup_walk
		ld	de,FIXUP_COUNT
		add	hl,de
		ld	a,(hl)
		ld	(fixup_block_count),a
		or	a
		jr	z,write_relocs.next_block
		call	fixup_offset	; count*6, and FIXUP_ENTRIES over
		ld	de,FIXUP_ENTRIES	;   again - the payload is the
		or	a		;   entries alone
		sbc	hl,de
		ld	a,RECORD_RELOC
		call	write_record_header
		xor	a
		ld	(fixup_at),a
write_relocs.entry:
		ld	a,(fixup_at)
		ld	hl,fixup_block_count
		cp	(hl)
		jr	z,write_relocs.next_block
		ld	a,(fixup_at)
		call	fixup_offset
		push	hl
		derefp	fixup_walk
		pop	de
		add	hl,de
		ld	de,fixup_entry	; out of the mapper before writing
		ld	bc,6
		ldir
		ld	de,fixup_entry
		ld	a,6
		call	write_bytes
		ld	hl,fixup_at
		inc	(hl)
		jr	write_relocs.entry
write_relocs.next_block:
		derefp	fixup_walk	; HL is at FIXUP_NEXT, which is where
		fpsave	fixup_walk	;   the next block is
		jr	write_relocs.loop

; object_entry - remember what END was given.
;
;   CALLED FROM main.end, IN BOTH PASSES. A record cannot be written
;   there: pass 2 has a DATA run open and its length is still a
;   placeholder. object_open clears this between the passes, so pass 1's
;   answer never reaches the file.
;
; Input:	HL = the value END's operand came to
;		A  = value_type
; Output:	remembered (error_external_here does not return)
; Modifies:	AF, BC, DE, HL

object_entry:	ld	(entry_offset),hl
		cp	SY_EXTERNAL	; the record has a segment and an
		jp	z,error_external_here	;   offset and no external form
		call	file_segment_index
		ld	(entry_segment),a
		ld	a,0ffh
		ld	(entry_given),a
		ret

; write_entry - and write it, if there was one.
;
; Input:	nothing
; Output:	the record, or nothing at all
; Modifies:	AF, BC, DE, HL

write_entry:	ld	a,(entry_given)
		or	a
		ret	z
		ld	hl,3
		ld	a,RECORD_ENTRY
		call	write_record_header
		ld	a,(entry_segment)
		call	write_byte
		ld	hl,(entry_offset)
		jp	write_word

; object_finish - the last run, the fixups, the entry point, the END record,
;   and close the file.
;
;   Anything after END is ignored by a reader (spec 11), so nothing
;   here has to pad or truncate.
;
; Input:	nothing
; Output:	the file is closed
; Modifies:	AF, BC, DE, HL

object_finish:	ld	a,(object_wanted)
		or	a
		ret	z
		call	close_data_run	; the last run has no line after it
		call	write_relocs	; NOW the fixups can go out: the
		call	write_entry	;   placeholder has been filled in
		ld	hl,0
		ld	a,RECORD_END
		call	write_record_header
		ld	a,(object_handle)
		ld	b,a
		system	_CLOSE
		ret

; object_delete - close the object file and delete it.
;
;   CALLED FROM die_with_message, and from nowhere else. object_open creates
;   the file at the start of pass 2 - deliberately, so that a source which
;   fails on pass 1 cannot truncate a file the user already had - and an error
;   on pass 2 therefore leaves one with the right name, the current timestamp
;   and part of the content. Nothing about it says it is rubbish, and the file
;   it replaced is gone. Issue #22.
;
;   object_wanted IS THE WHOLE OF THE CARE HERE. die_with_message also fires on
;   pass 1, on a command-line error, under /P and when _CREATE itself failed,
;   and in every one of those a file of this name may be the user's from an
;   earlier run. Deleting it would turn an error into data loss, which is a
;   worse fault than the one this routine fixes. object_open clears
;   object_wanted before anything can go wrong and sets it only once _CREATE
;   has handed back a handle, so it says "this run made a file", which is
;   exactly the question.
;
;   The handle is closed before the delete rather than after, or not at
;   all: deleting a file that is still open is a question about MSX-DOS
;   2's internals nobody needs answered.
;
; Input:	nothing (object_wanted, object_handle, object_name)
; Output:	no object file of this run's making is left on disk
; Modifies:	AF, BC, DE, HL

object_delete:	ld	a,(object_wanted)
		or	a
		ret	z		; none created this run
		xor	a
		; it is going, so nothing may write
		ld	(object_wanted),a
		ld	a,(object_handle)	;   to it either
		ld	b,a
		system	_CLOSE
		ld	de,object_name
		system	_DELETE
		ret

; module_name - the module's name: the TITLE's first six characters, or
;   the source file's name with the path and the extension taken off,
;   so "A:\SRC\TATARA.AS" is "TATARA".
;
;   The name is whatever was typed. MSX-DOS 2 hands the command tail
;   over unchanged - it does NOT upper-case it - so "tatara.as" gives
;   "tatara" and "TATARA.AS" gives "TATARA", and the spec stores names
;   verbatim either way. The linker compares MODNAME without regard to
;   case for that reason. How SYMBOLS were compared is a separate
;   question, and MODNAME's flags byte is what answers it.
;
; Input:	nothing (source_name)
; Output:	DE -> the name
;		A  = how long it is
; Modifies:	AF, BC, DE, HL

module_name:	ld	a,(title_text)	; M80's rule: the module is named by
		or	a		;   NAME, or by the first six
		; characters of the title when
		jr	z,module_name.from_file
		cp	7		;   there is no NAME. NAME itself
		; is one row of directive_table,
		jr	c,module_name.from_title
		ld	a,6		;   whenever it is wanted
module_name.from_title:
		ld	de,title_text+1
		ret
module_name.from_file:
		ld	hl,source_name
		ld	d,h
		ld	e,l		; the start, until a separator moves
module_name.separator:
		ld	a,(hl)		;   it along
		or	a
		jr	z,module_name.measure
		inc	hl
		cp	":"
		jr	z,module_name.restart
		cp	05ch		; the backslash, by its code: written
		; as a character it would sit
		jr	nz,module_name.separator
module_name.restart:
		ld	d,h		;   awkwardly in this file
		ld	e,l
		jr	module_name.separator
module_name.measure:
		ld	h,d
		ld	l,e
		ld	c,0
module_name.scan:
		ld	a,(hl)
		or	a
		jr	z,module_name.done
		cp	"."		; the extension is not part of it
		jr	z,module_name.done
		inc	hl
		inc	c
		jr	module_name.scan
module_name.done:
		ld	a,c
		ret

		dseg

object_wanted:	defs	1	; 0 = no object file was named, and every
				;   entry point is a single ret
object_handle:	defs	1	; MSX-DOS's handle for it
record_header:	defs	3	; a record header, built to be written
one_byte:	defs	1	; one byte, the same
table_walk:	defs	5	; a walk over a hash table: the bucket,
				;   then the far pointer htnext keeps
wanted_index:	defs	1	; the index find_by_index is looking for, and
				;   the one the next EXTDEF will take
		; write_mapped_name: key bytes in front of the name,
name_key_skip:	defs	1
name_length:	defs	1	;   the name's length,
name_at:	defs	1	;   and which character it is on
record_flags:	defs	1	; a record's flags, out of the mapper
record_group_byte:
		defs	1	;   its group, or a symbol's segment
record_size:	defs	2	;   and its size, or a symbol's value,
				;   or a DATA record's length
run_open:	defs	1	; 0 = no DATA run is open
run_segment:	defs	1	; the open run's segment, as the FILE
				;   numbers it
run_start:	defs	2	; where it started, within that segment
run_next:	defs	2	; where its next byte has to go, if the
				;   run is to carry on
run_length_at:	defs	4	; and where its length field sits in the
				;   file: the low word, then the high one,
				;   the order _SEEK wants them in
fixup_head:	defs	4	; the fixup chain's head, which is its
				;   NEWEST block
fixup_walk:	defs	4	; write_relocs: which block the walk is on
fixup_new:	defs	4	; fixup_new_block: what halloc answered
fixup_head_count:
		defs	1	; entries in the head block. It starts at
				;   FIXUPS_PER_BLOCK so the first fixup
				;   allocates
fixup_block_count:
		defs	1	; write_relocs: the block's count,
fixup_at:	defs	1	;   and which entry it is on
fixup_entry:	defs	6	; ONE ENTRY, in ordinary RAM: the table is
				;   in the mapper and a BDOS call cannot
				;   read it there
entry_given:	defs	1	; 0 = END named no address
entry_segment:	defs	1	; its segment, as the FILE numbers it
entry_offset:	defs	2	;   and its offset
