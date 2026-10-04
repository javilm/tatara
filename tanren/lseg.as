; lseg.as - the link's groups and segments.
;
; Two hash tables in ordinary RAM with their records in the mapper,
; which is what symtab.as does and for the same reasons. A segment's
; key is its GROUP and its NAME, exactly as the assembler keys
; segment_table: two groups of one transient DSEG are then two records
; without a special case, which is what [R4] needs when the layout
; overlays them.
;
; THE TOTAL IS ALL THIS TABLE HOLDS. A module's base within the
; combined segment is not stored, because pass 2 reads the modules in
; the same order and a running fill level reproduces every base for
; nothing.

LSEG_INCLUDED	equ	1	; skips the externals in lseg.inc

		public	segments_init
		public	segments_new_module
		public	add_group
		public	add_segment
		public	segments_dump
		public	segments_set_case
		public	place_segments
		public	reset_segment_totals
		public	last_kind_end
		public	segment_own_base
		public	segment_by_index
		public	segment_record
		public	segment_module_base
		public	print_record_name
		public	name_record
		public	name_key_skip
		public	segdef_fields
		public	module_count

		include	lseg.inc
		include	lobj.inc
					; objfile_string_buffer,
					;   objfile_string_length
		include	lerrs.inc
					; error_too_many_segments,
					;   error_segment_differs,
					;   error_data_overlaps_code
		include	lcmd.inc	; /P: and /D:, which are the only
					;   things outside this module that
					;   decide where anything goes
		include	hash.inc
		include	alloc.inc	; derefp
		include	farptr.inc
		include	msxdos.inc	; print_zero_string, print_decimal
		include	strutil.inc	; build_hex_word, build_hex_byte
		include	ascii.inc

		cseg

; segments_init - both tables, empty. ONCE, before the first file.
;
; Input:	nothing
; Output:	the tables are ready
; Modifies:	AF, BC, DE, HL, IX

		; the DEFAULT, which stands until the first MODNAME says what
		;   the modules were assembled with
segments_init:	ld	a,HT_CASE_FOLD
		call	segments_set_case
		xor	a
		ld	(segment_count),a
		ld	(group_count),a
		ld	(module_count),a
		ret

; segments_set_case - the two tables' case mode.
;
;   SEPARATE BECAUSE IT IS DECIDED LATE. The mode comes from the
;   first module's MODNAME flags byte, which is read after segments_init
;   has run - so the tables are formatted twice, once with the
;   default and once for real. The second time costs nothing: no
;   record has been added yet, and htinit only empties buckets.
;
; Input:	A = HT_CASE_SENSITIVE or HT_CASE_FOLD
; Output:	both tables are empty and in that mode
; Modifies:	AF, BC, DE, HL, IX

segments_set_case:
		; KEPT: same_record_name folds as it compares when the link is
		;   insensitive
		ld	(segment_case_mode),a
		push	af
		ld	ix,segment_table
		ld	b,SEGMENT_BUCKETS-1
		call	htinit
		pop	af
		ld	ix,group_table
		ld	b,SEGMENT_BUCKETS-1
		call	htinit
		ret

; segments_new_module - a module is starting.
;
; Input:	nothing
; Output:	its maps are empty, module_count is one higher
; Modifies:	AF, HL

segments_new_module:
		xor	a
		ld	(module_segment_count),a
		ld	(module_group_count),a
		ld	hl,module_count
		inc	(hl)
		ret

; add_group - a GRPDEF record.
;
;    The name is in objfile_string_buffer, where objfile_read_string left it. A
;    group seen in two
;   modules is one group, so the table is asked first.
;
; Input:	objfile_string_buffer, objfile_string_length
; Output:	module_group_map gains this module's next group index
;		(error_too_many_segments does not return)
; Modifies:	AF, BC, DE, HL, IX

add_group:	ld	a,(module_group_count)
		cp	MODULE_GROUP_MAX
		jp	nc,error_too_many_segments
		ld	ix,group_table
		ld	de,objfile_string_buffer
		ld	a,(objfile_string_length)
		ld	hl,payload_pointer
		call	htfind
		jr	nc,add_group.known
		ld	ix,group_table	; a group nobody has named yet
		ld	de,objfile_string_buffer
		ld	a,(objfile_string_length)
		ld	bc,1		; its payload is its global id
		ld	hl,payload_pointer
		call	htadd
		jp	c,error_out_of_memory
		derefp	payload_pointer
		ld	a,(group_count)	; the id this group takes
		ld	(hl),a
		ld	hl,group_count
		inc	(hl)
		ld	a,(hl)
		dec	a		; back to the id just handed out
		jr	add_group.map_it
add_group.known:
		derefp	payload_pointer
		ld	a,(hl)
add_group.map_it:
		; module_group_map[module_group_count] = that id
		ld	hl,module_group_map
		ld	e,a
		ld	a,(module_group_count)
		ld	c,a
		ld	b,0
		add	hl,bc
		ld	(hl),e
		ld	hl,module_group_count
		inc	(hl)
		ret

; add_segment - a SEGDEF record.
;
;   FIND BEFORE ADD, ALWAYS. htadd does not check for duplicates and
;   says so; a second CODE added blindly would make two records of
;   that name with half the size each, and nothing would notice until
;   the image came out wrong.
;
; Input: segdef_fields = flags, group index, size; objfile_string_buffer,
; objfile_string_length
; Output:	the table holds it and module_segment_map points at it
;		(error_too_many_segments, error_segment_differs do not return)
; Modifies:	AF, BC, DE, HL, IX

add_segment:	ld	a,(module_segment_count)
		cp	MODULE_SEGMENT_MAX
		jp	nc,error_too_many_segments
		call	build_segment_key	; a group byte and the name
		ld	ix,segment_table
		ld	de,key_buffer
		ld	a,(key_length)
		ld	hl,payload_pointer
		call	htfind
		jr	nc,add_segment.known
		; a segment nobody has named yet
		ld	ix,segment_table
		ld	de,key_buffer
		ld	a,(key_length)
		ld	bc,SEGMENT_PAYLOAD_SIZE	; flags, size, base, placed
		ld	hl,payload_pointer
		call	htadd
		jp	c,error_out_of_memory
		derefp	payload_pointer
		ld	a,(segdef_fields)
		ld	(hl),a		; its flags, as the FILE wrote them
		inc	hl
		ld	(hl),0		; and nothing in it yet
		inc	hl
		ld	(hl),0
		inc	hl
		ld	(hl),0		; no base
		inc	hl
		ld	(hl),0
		inc	hl
		ld	(hl),0		; and not placed
		inc	hl
		; ITS ORDINAL: segments are placed in the order they first
		;   appear, and this is where that order is remembered - the
		;   table forgets it the moment the record is added
		ld	a,(segment_count)
		ld	(hl),a
		ld	hl,segment_count
		inc	(hl)
		jr	add_segment.accumulate
add_segment.known:
		derefp	payload_pointer
		; THE SAME SEGMENT MUST BE THE SAME KIND of segment in every
		;   module
		ld	a,(segdef_fields)
		cp	(hl)
		jp	nz,error_segment_differs
add_segment.accumulate:
		derefp	payload_pointer	; the running total, out of the
		inc	hl		;   mapper
		ld	c,(hl)
		inc	hl
		ld	b,(hl)		; IN BC, NOT DE: deref DESTROYS DE
					;   and keeps BC, and its comment
					;   says so. AND THE TOTAL SO FAR
					;   IS THIS MODULE'S BASE in the
					;   combined segment - it is
					;   stored beside the pointer,
					;   and a PUBDEF adds it to every
					;   offset
		ld	(segment_module_base),bc
		ld	hl,(segdef_fields+2)
		add	hl,bc
		ld	b,h
		ld	c,l
		derefp	payload_pointer
		inc	hl
		ld	(hl),c
		inc	hl
		ld	(hl),b

		; module_segment_map[module_segment_count]: the record, and
		;   then this module's base in it
		ld	a,(module_segment_count)
		call	segment_map_offset
		ld	de,module_segment_map
		add	hl,de
		ex	de,hl
		ld	hl,payload_pointer
		ld	bc,4
		ldir
		; DE is already past the pointer
		ld	hl,segment_module_base
		ld	bc,2
		ldir
		ld	hl,module_segment_count
		inc	(hl)
		ret

; segment_map_offset - where entry A sits inside
;   module_segment_map. Six bytes each: four of far pointer and two
;   of base. fixup_offset does the same arithmetic for
;   the same reason - six is not a shift.
;
; Input:	A = which entry
; Output:	HL = A * 6
; Modifies:	AF, DE, HL

segment_map_offset:
		ld	l,a
		ld	h,0
		ld	e,l
		ld	d,h
		add	hl,hl		; *2
		add	hl,de		; *3
		add	hl,hl		; *6
		ret

; segment_by_index - this module's segment index N: its record, and its base.
;
; Input:	A = the index the FILE used
; Output:	segment_record = the record's payload far pointer
;		segment_module_base = this module's base within that segment
;		(error_truncated does not return: an index this module never
;		declared can only come from a broken file)
; Modifies:	AF, BC, DE, HL

segment_by_index:
		ld	hl,module_segment_count
		cp	(hl)
		jp	nc,error_truncated
		call	segment_map_offset
		ld	de,module_segment_map
		add	hl,de
		ld	de,segment_record
		ld	bc,4
		ldir
		ld	de,segment_module_base
		ld	bc,2
		ldir
		derefp	segment_record	; AND THE SEGMENT'S OWN BASE, which
					; symbols_relocate adds to every symbol
		ld	de,SEGMENT_BASE
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(segment_own_base),de
		ret

; build_segment_key - the key a segment is stored under: one byte of group,
; then the name.
;
; Input: segdef_fields+1 = the module's group index, objfile_string_buffer,
; objfile_string_length
; Output:	key_buffer, key_length
; Modifies:	AF, BC, DE, HL

build_segment_key:
		ld	a,(segdef_fields+1)
		cp	0ffh
		; no group: FFh is the key's byte
		jr	z,build_segment_key.no_group
		ld	c,a		; otherwise the GLOBAL id, which is
		ld	b,0		;   what makes two modules' groups
		ld	hl,module_group_map	;   one group
		add	hl,bc
		ld	a,(hl)
build_segment_key.no_group:
		ld	(key_buffer),a
		ld	hl,objfile_string_buffer
		ld	de,key_buffer+1
		ld	a,(objfile_string_length)
		ld	c,a
		ld	b,0
		ldir
		ld	a,(objfile_string_length)
		inc	a		; the group byte counts
		ld	(key_length),a
		ret

; segments_dump - /M: what the reading found.
;
;   THE PAGE 2 RULE, per record: everything is read into ordinary RAM
;   before anything is printed, because printing hands page 2 back to
;   MSX-DOS and the records are in the mapper. dump_symbols and
;   write_mapped_name met this first.
;
; Input:	nothing
; Output:	the tables are printed
; Modifies:	everything

segments_dump:	ld	de,msg_modules
		call	print_zero_string
		ld	a,(module_count)
		ld	l,a
		ld	h,0
		call	print_decimal
		call	print_line_break

		ld	de,msg_groups
		call	print_zero_string
		xor	a		; A GROUP'S KEY IS ITS NAME, with
		ld	(name_key_skip),a	;   nothing in front of it
		call	table_walk_first
segments_dump.group:
		ld	ix,group_table
		ld	hl,outer_walk
		call	htnext
		jr	c,segments_dump.segments
		ld	de,msg_row_indent
		call	print_zero_string
		call	set_name_record
		call	print_record_name
		call	print_line_break
		jr	segments_dump.group

segments_dump.segments:
		ld	de,msg_segments
		call	print_zero_string
		ld	a,1		; a segment's key has its group byte
		ld	(name_key_skip),a	;   in front of the name
		; IN PLACEMENT ORDER, by the same two loops place_segments
		;   uses: a map printed in any other order is a map of a layout
		;   that did not happen. placing_kind IS BORROWED:
		;   place_segments has finished with it by the time
		;   main.all_read calls this, and it is left at 2 either way
		xor	a
		ld	(placing_kind),a
segments_dump.kind:
		xor	a
		ld	(wanted_ordinal),a
segments_dump.ordinal:
		ld	a,(wanted_ordinal)
		ld	hl,segment_count
		cp	(hl)
		; jp: the same columns that pushed segments_dump.ordinal past a
		;   jr's reach put the end of the loop past it too
		jp	nc,segments_dump.next_kind
		call	table_walk_first
segments_dump.scan:
		ld	ix,segment_table
		ld	hl,outer_walk
		call	htnext
		; jp: 122 bytes of printed record lie between here and
		;   segments_dump.next_ordinal, and all three exits clear the
		;   lot
		jp	c,segments_dump.next_ordinal
		call	read_outer_record	; flags, group, total
		ld	a,(rec_ordinal)
		ld	hl,wanted_ordinal
		cp	(hl)
		jr	nz,segments_dump.scan
		ld	a,(rec_flags)
		and	1
		ld	hl,placing_kind
		cp	(hl)
		jp	nz,segments_dump.next_ordinal
		; A TRANSIENT SEGMENT'S GROUPLESS RECORD HAS NOTHING TO SAY. It
		;   is the one made when DSEG TRANSIENT is first met, before a
		;   GROUP has said what it may overlay - and the assembler's
		;   require_placeable lets nothing in until one has, so it is
		;   always empty. Printed, it puts a row with no size and no
		;   end among the rows that have both.
		ld	a,(rec_flags)
		and	2
		jr	z,segments_dump.print
		ld	a,(rec_group)
		inc	a
		jr	nz,segments_dump.print
		ld	hl,(rec_size)
		ld	a,h
		or	l
		jp	z,segments_dump.next_ordinal
					;   THE SIZE IS TESTED ANYWAY, though
					;   require_placeable makes it dead: a
					;   map may drop a record only when it
					;   says nothing. Issue #25
segments_dump.print:
		ld	de,msg_row_indent	;   into RAM before a word is
		call	print_zero_string	;   printed
		ld	de,msg_flags
		call	print_zero_string
		ld	a,(rec_flags)
		call	print_byte
		ld	de,msg_group
		call	print_zero_string
		ld	a,(rec_group)
		call	print_byte
		ld	de,msg_base
		call	print_zero_string
		ld	hl,(rec_base)
		call	print_word
		ld	de,msg_size
		call	print_zero_string
		ld	hl,(rec_size)
		call	print_word
		ld	de,msg_end_field
		call	print_zero_string
		ld	hl,(rec_size)	; the LAST byte, which a segment of
		ld	a,h		;   no bytes does not have
		or	l
		jr	z,segments_dump.no_end
		dec	hl
		ld	de,(rec_base)
		add	hl,de
		call	print_word
		jr	segments_dump.gap
segments_dump.no_end:
		ld	de,msg_no_end
		call	print_zero_string
segments_dump.gap:
		ld	de,msg_gap
		call	print_zero_string
		call	set_name_record
		call	print_record_name
		call	print_line_break
segments_dump.next_ordinal:
		ld	hl,wanted_ordinal
		inc	(hl)
		; jp: the extra columns pushed this loop past a jr's reach
		jp	segments_dump.ordinal
segments_dump.next_kind:
		ld	hl,placing_kind	; code done, now the data - and then
		inc	(hl)		;   there is no third kind
		ld	a,(hl)
		cp	2
		jp	c,segments_dump.kind
		ret

; read_outer_record - the record outer_walk is on: its group byte and
;   its payload, into ordinary RAM.
;
; Input:	outer_walk is on a segment record
; Output:	rec_group, rec_flags, rec_size
; Modifies:	AF, BC, DE, HL

read_outer_record:
		derefp	outer_walk+1
		ld	de,HT_KEY
		add	hl,de
		ld	a,(hl)		; the key's first byte is the group
		ld	(rec_group),a
		derefp	outer_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)	; payload = HT_HEADER_SIZE + the key, and the
		ld	c,a		;   key's length goes IN BC across
		ld	b,0		;   the deref below for the same
		derefp	outer_walk+1	;   reason
		add	hl,bc
		ld	bc,HT_HEADER_SIZE
		add	hl,bc
		ld	a,(hl)
		ld	(rec_flags),a
		inc	hl
		ld	a,(hl)
		ld	(rec_size),a
		inc	hl
		ld	a,(hl)
		ld	(rec_size+1),a
		inc	hl
		ld	a,(hl)
		ld	(rec_base),a
		inc	hl
		ld	a,(hl)
		ld	(rec_base+1),a
		inc	hl
		ld	a,(hl)
		ld	(rec_placed),a
		inc	hl
		ld	a,(hl)
		ld	(rec_ordinal),a
		ret

; place_segments - every segment gets an address.
;
;   CODE FIRST, THEN DATA, because bit 0 of the flags byte is that
;   distinction and a .COM is contiguous from one address.
;
;   AND SAME-NAMED SEGMENTS OVERLAY. A group says its members
;   coexist; two groups of one segment say they do not, so every
;   record sharing a NAME gets the same base and the image gives up
;   the LARGEST of them. That is [R4], and the table was keyed by
;   group-and-name so that this walk would have something to find.
;
; Input:	nothing (the table, full)
; Output:	every record has a base, last_kind_end is the end
;		(error_image_too_big does not return)
; Modifies:	everything

place_segments:	ld	hl,COM_ORIGIN	; /P: moves it. [R11] wanted the
		ld	a,(opt_code_origin)	;   image out of the TPA, and
		or	a		;   an image out of the TPA is
		jr	z,place_segments.origin	;   only useful if it can be
		ld	hl,(code_origin)	;   told where to load
place_segments.origin:
		ld	(next_address),hl
		; where the code began, for check_data_overlap
		ld	(code_start),hl
		xor	a
		ld	(placing_kind),a	; code first
place_segments.kind:
		; ORDINAL BY ORDINAL, and not whatever htnext hands over: the
		;   table's order is the hash of the NAMES, so renaming a code
		;   segment could change which one landed at 0100h - and a .COM
		;   is entered there whatever any file says. Issue #24
		xor	a
		ld	(wanted_ordinal),a
place_segments.ordinal:
		ld	a,(wanted_ordinal)
		ld	hl,segment_count
		cp	(hl)
		jr	nc,place_segments.kind_done
		call	table_walk_first
place_segments.scan:
		ld	ix,segment_table
		ld	hl,outer_walk
		call	htnext
		; no record carries this ordinal
		jr	c,place_segments.next_ordinal
		; flags, size, base, placed, ordinal
		call	read_outer_record
		ld	a,(rec_ordinal)
		ld	hl,wanted_ordinal
		cp	(hl)
		jr	nz,place_segments.scan	; some other segment's
		ld	a,(rec_placed)
		or	a
		; another record of its name placed it already
		jr	nz,place_segments.next_ordinal
		ld	a,(rec_flags)	; is it this pass's kind?
		and	1
		ld	hl,placing_kind
		cp	(hl)
		; the other pass will take it, and that pass counts from 0
		;   again
		jr	nz,place_segments.next_ordinal
		call	keep_record_name	; its name, into placing_name
		call	largest_of_name	; -> HL = the largest of that name
		push	hl
		ld	hl,(next_address)
		call	place_all_of_name	; that base, to all of them
		pop	de
		; and the image gives up the largest
		ld	hl,(next_address)
		add	hl,de
		; past FFFFh: it would wrap. A jp, because error_image_too_big
		;   is EXTERNAL and a relative jump cannot reach what the
		;   assembler cannot measure
		jp	c,error_image_too_big
		ld	(next_address),hl
place_segments.next_ordinal:
		ld	hl,wanted_ordinal	; that ordinal is answered,
		inc	(hl)		;   it placed anything or not
		jr	place_segments.ordinal
place_segments.kind_done:
		ld	hl,placing_kind
		inc	(hl)
		ld	a,(hl)
		cp	2
		jr	nc,place_segments.done
		ld	hl,(next_address)	; the code is placed, and
		ld	(code_end),hl	;   this is where it ended
		ld	a,(opt_data_origin)	; /D: GIVEN? THE DATA STARTS
		or	a		;   THERE instead of carrying on
		jp	z,place_segments.kind	;   from the code, which is all
		ld	hl,(data_origin)	;   this note does to the walk
		ld	(next_address),hl
		ld	(data_start),hl
		jp	place_segments.kind
place_segments.done:
		ld	hl,(next_address)
		ld	(last_kind_end),hl
		jp	check_data_overlap

; check_data_overlap - /D: may have put the data on top of the code.
;
;   TWO SUBTRACTIONS. The spans overlap when the data starts before
;   the code ends AND the code starts before the data ends, which is
;   an OVERLAP and not an ORDERING: data below code is a real MSX
;   layout - /P:C000 /D:8000 puts the code in the top page and its
;   variables under it - and refusing that would be refusing the
;   arrangement the option exists for.
;
;   An empty kind cannot be sat on, and the two guards are there
;   because an empty span passes an overlap test that means nothing.
;
; Input:	code_start, code_end, data_start, last_kind_end,
;		opt_data_origin
; Output:	nothing (error_data_overlaps_code does not return)
; Modifies:	AF, DE, HL

check_data_overlap:
		ld	a,(opt_data_origin)
		or	a
		ret	z		; data follows code: it cannot
		ld	hl,(code_end)
		ld	de,(code_start)
		or	a
		sbc	hl,de
		ret	z		; no code at all
		ld	hl,(last_kind_end)
		ld	de,(data_start)
		or	a
		sbc	hl,de
		ret	z		; no data at all
		ld	hl,(data_start)	; does the data start before the
		ld	de,(code_end)	;   code ends?
		or	a
		sbc	hl,de
		ret	nc
		ld	hl,(code_start)	; and the code before the data
		ld	de,(last_kind_end)	;   ends?
		or	a
		sbc	hl,de
		ret	nc
		jp	error_data_overlaps_code

; reset_segment_totals - every segment's running total, back to zero.
;
;   FOR PASS 2, AND ONLY THE TOTAL. The base place_segments worked out stays,
;   and so does the "placed" flag, because nothing is laid out a
;   second time. What pass 2 needs is for add_segment's accumulation to
;   start again from nothing, so that the total standing when a
;   module's SEGDEF arrives is that module's base - exactly as it was
;   in pass 1, because the modules arrive in the same order.
;
;   module_count goes back to zero for the same reason: pass 2 counts them
;   again and arrives at the same number, so the summary line is
;   still right.
;
;   IT WALKS WITH THE SECOND ITERATOR. Nothing else is walking when
;   this runs, and inner_payload is already the routine that turns that
;   iterator into a payload pointer.
;
; Input:	nothing (the table, laid out)
; Output:	every total is zero
; Modifies:	everything

reset_segment_totals:
		xor	a
		ld	(module_count),a
		call	start_inner_walk
reset_segment_totals.loop:
		ld	ix,segment_table
		ld	hl,inner_walk
		call	htnext
		ret	c
		call	inner_payload	; HL -> its payload
		ld	de,SEGMENT_SIZE
		add	hl,de
		ld	(hl),0
		inc	hl
		ld	(hl),0
		jr	reset_segment_totals.loop

; keep_record_name - the name of the record outer_walk is on, into
;   ordinary RAM.
;
;   The key is a group byte and then the name, so the name is one
;   shorter than the key and one byte further in.
;
; Input:	outer_walk is on a record
; Output:	placing_name, placing_name_length
; Modifies:	AF, BC, DE, HL

keep_record_name:
		derefp	outer_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)
		dec	a		; less the group byte
		ld	(placing_name_length),a
		ld	c,a
		ld	b,0
		inc	hl		; HT_KEY: the group byte
		inc	hl		;   and now the name
		ld	de,placing_name
		ldir
		ret

; same_record_name - is the record inner_walk is on one of placing_name's?
;
;   FOLDED IF THE LINK IS CASE-INSENSITIVE, which is the default.
;   Otherwise SCRATCH in one group and scratch in another would be
;   laid end to end instead of overlaid, and [R4] would silently not
;   happen.
;
; Input:	inner_walk is on a record; placing_name, placing_name_length
; Output:	Z set = the same name
; Modifies:	AF, BC, DE, HL

same_record_name:
		derefp	inner_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)
		dec	a
		ld	c,a
		ld	a,(placing_name_length)
		cp	c
		ret	nz		; different lengths, different names
		or	a
		ret	z		; both empty: the same, vacuously
		inc	hl
		inc	hl		; past the group byte, to the name
		ld	de,placing_name
		ld	b,c
same_record_name.loop:
		ld	a,(de)
		ld	c,a
		ld	a,(segment_case_mode)
		cp	HT_CASE_FOLD
		jr	nz,same_record_name.compare
		ld	a,c		; fold both, the way the table
		call	fold_to_upper	;   hashed them
		ld	c,a
		ld	a,(hl)
		call	fold_to_upper
		cp	c
		jr	same_record_name.next
same_record_name.compare:
		ld	a,(hl)
		cp	c
same_record_name.next:
		ret	nz
		inc	hl
		inc	de
		djnz	same_record_name.loop
		xor	a		; Z: every byte matched
		ret

; largest_of_name - the largest size among the records of placing_name.
;
; Input:	placing_name, placing_name_length
; Output:	HL = that size
; Modifies:	everything but outer_walk

largest_of_name:
		ld	hl,0
		ld	(placing_largest),hl
		call	start_inner_walk
largest_of_name.loop:
		ld	ix,segment_table
		ld	hl,inner_walk
		call	htnext
		jr	nc,largest_of_name.match
		; THE WALK IS OVER, AND THIS IS THE ANSWER. htnext leaves HL
		;   its own, so returning without this loaded handed
		;   place_segments a number that made every segment land on
		;   COM_ORIGIN
		ld	hl,(placing_largest)
		ret
largest_of_name.match:
		call	same_record_name
		jr	nz,largest_of_name.loop
		call	read_inner_size	; its size, out of the mapper
		ld	hl,(inner_size)
		ld	de,(placing_largest)
		or	a
		sbc	hl,de
		jr	c,largest_of_name.loop	; smaller: keep what we had
		ld	hl,(inner_size)
		ld	(placing_largest),hl
		jr	largest_of_name.loop

; place_all_of_name - that base, and "placed", to every record of placing_name.
;
; Input:	HL = the base
;		placing_name, placing_name_length
; Output:	they are all placed
; Modifies:	everything but outer_walk

place_all_of_name:
		ld	(placing_base),hl
		call	start_inner_walk
place_all_of_name.loop:
		ld	ix,segment_table
		ld	hl,inner_walk
		call	htnext
		ret	c
		call	same_record_name
		jr	nz,place_all_of_name.loop
		call	inner_payload	; HL -> its payload
		ld	de,SEGMENT_BASE
		add	hl,de
		ld	de,(placing_base)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),1		; SEGMENT_PLACED
		jr	place_all_of_name.loop

; inner_payload, read_inner_size - the record inner_walk is on: its
;   payload, and its size out of it. read_outer_record does the same
;   for outer_walk, and the two iterators exist because the outer walk
;   is still standing on a record while these two run.
;
; Input:	inner_walk is on a record
; Output:	inner_payload: HL -> the payload
;		read_inner_size: inner_size
; Modifies:	AF, BC, DE, HL

inner_payload:	derefp	inner_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)
		ld	c,a		; IN BC across the deref: deref
		ld	b,0		;   destroys DE and keeps BC
		derefp	inner_walk+1
		add	hl,bc
		ld	bc,HT_HEADER_SIZE
		add	hl,bc
		ret

read_inner_size:
		call	inner_payload
		ld	de,SEGMENT_SIZE
		add	hl,de
		ld	a,(hl)
		ld	(inner_size),a
		inc	hl
		ld	a,(hl)
		ld	(inner_size+1),a
		ret

start_inner_walk:
		xor	a
		ld	(inner_walk),a
		ld	hl,NULL_OFFSET
		ld	(inner_walk+3),hl
		ret

; print_record_name - the name of the record outer_walk is on, printed.
;
;   ONE CHARACTER AT A TIME, mapping the record again for each: every
;   BDOS call takes page 2 back. write_mapped_name answered this the same way.
;   A segment's key has a group byte in front of its name; a group's
;   does not, so the skip is 1 or 0 and the caller has already said
;   which by choosing the table.
;
; Input:	outer_walk is on a record, name_key_skip = key bytes
;		before the name
; Output:	the name is printed
; Modifies:	everything

print_record_name:
		derefp	name_record
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)
		ld	hl,name_key_skip
		sub	(hl)
		ld	(name_length),a
		xor	a
		ld	(name_at),a
print_record_name.loop:
		ld	a,(name_at)
		ld	hl,name_length
		cp	(hl)
		ret	z
		derefp	name_record
		ld	de,HT_KEY
		add	hl,de
		ld	a,(name_key_skip)
		ld	e,a
		ld	a,(name_at)
		add	a,e
		ld	e,a
		ld	d,0
		add	hl,de
		ld	a,(hl)
		ld	(name_char),a	; OUT OF THE MAPPER FIRST, then the
		ld	a,(name_char)	;   call - and through the system
		ld	e,a		;   macro, so page2_safe runs. A BDOS
		call	print_char	;   call written by hand here would
		ld	hl,name_at	;   be the bug this loop exists for
		inc	(hl)
		jr	print_record_name.loop

; table_walk_first - a walk, back to the beginning. walk_first, for this
; module's tables.

; set_name_record - name_record = the record this walk is on.
;
; Input:	outer_walk
; Output:	name_record
; Modifies:	BC, DE, HL

set_name_record:
		ld	hl,outer_walk+1
		ld	de,name_record
		ld	bc,4
		ldir
		ret

table_walk_first:
		xor	a
		ld	(outer_walk),a
		ld	hl,NULL_OFFSET
		ld	(outer_walk+3),hl
		ret

print_line_break:
		ld	de,msg_line_break
		jp	print_zero_string

print_byte:	ld	de,hex_buffer	; a byte, two hex digits
		call	build_hex_byte
		ld	hl,hex_buffer+2
		ld	(hl),0
		ld	de,hex_buffer
		jp	print_zero_string

print_word:	ld	de,hex_buffer	; and a word, four
		call	build_hex_word
		ld	hl,hex_buffer+4
		ld	(hl),0
		ld	de,hex_buffer
		jp	print_zero_string

		dseg

				; the descriptors: ordinary RAM,
				;   records in the mapper
segment_table:	defs	2+SEGMENT_BUCKETS*4
group_table:	defs	2+SEGMENT_BUCKETS*4
segment_count:	defs	1	; how many segments the link has,
group_count:	defs	1	;   how many groups, and
module_count:	defs	1	;   how many modules have been read
module_segment_count:
		defs	1	; THIS MODULE's segments so far,
module_group_count:
		defs	1	;   and its groups
				; its segment index -> the record,
				;   AND this module's base in that
				;   segment: four bytes and two
module_segment_map:
		defs	MODULE_SEGMENT_MAX*6
segment_record:	defs	4	; segment_by_index: which segment,
segment_module_base:
		defs	2	;   and where this module starts in it
name_record:	defs	4	; the record print_record_name prints
				;   from - set by whichever walk is
				;   calling
				; its group index -> the global id
module_group_map:
		defs	MODULE_GROUP_MAX
segdef_fields:	defs	4	; a SEGDEF's flags, group and size
key_buffer:	defs	1+256	; the key being looked up: a group byte
key_length:	defs	1	;   and a name, and how long that is
payload_pointer:
		defs	4	; the far pointer htfind and htadd fill
outer_walk:	defs	5	; segments_dump's walk: the bucket, then the
				;   far pointer htnext keeps
name_key_skip:	defs	1	; print_record_name: key bytes before the name,
name_length:	defs	1	;   how long the name is,
name_at:	defs	1	;   and which character it is on
name_char:	defs	1	;   one character, out of the mapper
rec_group:	defs	1	; segments_dump: one record, in ordinary RAM
rec_flags:	defs	1
rec_size:	defs	2
rec_base:	defs	2
rec_placed:	defs	1
rec_ordinal:	defs	1	;   and its ordinal, for the two walks
				;   that go in placement order
inner_walk:	defs	5	; THE SECOND WALK: largest_of_name and
				;   place_all_of_name run while the
				;   outer walk is still standing on a
				;   record
inner_size:	defs	2	; and that walk's size, out of the mapper
placing_name:	defs	256	; the name being placed, and how long
placing_name_length:
		defs	1	;   it is
placing_largest:
		defs	2	; the largest size found under it
placing_base:	defs	2	; the base being handed out
placing_kind:	defs	1	; 0 while the code segments are placed,
				;   1 for the data ones
wanted_ordinal:	defs	1	; the ordinal place_segments and
				;   segments_dump are looking for.
				;   THE LOOP IS OVER
				;   ORDINALS and the table is searched for
				;   each, which costs a walk per segment
				;   and needs no sort and no second table
				;   - the layout has been O(n squared) by
				;   choice since 061 D4
next_address:	defs	2	; the next free address
last_kind_end:	defs	2	; where the LAST KIND finished - which
				; with /D: putting the data below the
				; code is not where the image ends.
				; Nothing reads it; the image's real
				; extent is the image_low and image_high,
				; measured from what was written
code_start:	defs	2	; check_data_overlap: where the code began,
code_end:	defs	2	;   where it ended, and
data_start:	defs	2	;   where the data began
segment_own_base:
		defs	2	; segment_by_index: that segment's
				;   own base
segment_case_mode:
		defs	1	; HT_CASE_SENSITIVE or HT_CASE_FOLD,
				;   for same_record_name
hex_buffer:	defs	5	; build_hex_word's answer, zero-terminated

msg_modules:	defb	"Modules: ",0
msg_groups:	defb	"Groups:",CHR_CR,CHR_LF,0
msg_segments:	defb	"Segments:",CHR_CR,CHR_LF,0
msg_row_indent:	defb	"  ",0
msg_flags:	defb	"flags ",0
msg_group:	defb	" group ",0
msg_base:	defb	" base ",0
msg_size:	defb	" size ",0
msg_end_field:	defb	" end ",0
msg_no_end:	defb	"-----",0
msg_gap:	defb	" ",0
msg_line_break:	defb	CHR_CR,CHR_LF,0
