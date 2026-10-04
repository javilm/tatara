; lseg.inc - public interface of lseg.as: the segments and groups of
; every module in the link.
;
; EACH MODULE NUMBERS ITS OWN. A SEGDEF's index is that module's, and
; its DATA and RELOC records quote it, so while a module is open the
; linker keeps a map from its indices to the real records - and
; throws the map away when the module closes. That map is the only
; per-module state there is.

		ifndef	LSEG_INCLUDED

		extrn segments_init	; both tables empty, counters
					; zero. ONCE, before the first
					; file is opened
		extrn segments_new_module
					; a module is starting: its maps
					; are empty again, and
					; module_count goes up
		extrn add_group
					; a GRPDEF: the name is in
					; objfile_string_buffer and its
					; length in objfile_string_length
		extrn add_segment	; a SEGDEF: segdef_fields holds flags,
					; group and size; the name is in
					; objfile_string_buffer
					; (error_too_many_segments,
					; error_segment_differs do not
					; return)
		extrn segments_dump	; /M: the modules, the groups and
					; the segments
		extrn segments_set_case	; the two tables' case mode.
					; sets it from the first module's
					; MODNAME flags, because that is
					; when it becomes known
					; in:  A = HT_CASE_SENSITIVE or
					;      HT_CASE_FOLD
		extrn place_segments	; EVERY SEGMENT GETS AN ADDRESS:
					; code first, then data, from
					; COM_ORIGIN, with same-named segments
					; in different groups OVERLAID -
					; one base, and the largest of
					; them taken from the image
					; (error_image_too_big does not return)
		extrn reset_segment_totals	; PASS 2: every segment's total
					; back to zero, so that add_segment
					; accumulates it a second time
					; and reproduces each module's
					; base. No per-module base is
					; stored, and this is the debt it
					; promised to pay
		extrn last_kind_end	; where the LAST KIND finished.
					; NOT where the image ends: with
					; /D: putting the data below the
					; code it is the end of the code.
					; Nothing reads it; the image's
					; real extent is image_low and
					; image_high, measured from what
					; was written
		extrn segment_own_base	; the base of the segment
					; segment_by_index was asked about
		extrn segment_by_index	; this module's segment index N
					; in:  A = the index the FILE used
					; out: segment_record,
					;      segment_module_base
		extrn segment_record	; that segment's record (a far
					; pointer), and
		extrn segment_module_base
					;   this module's base within it
		extrn print_record_name	; the name of the record name_record
					; points at, printed a character
					; at a time out of the mapper
		extrn name_record	; which record that is: THREE
					; walks share this printer now
		extrn name_key_skip	; and how many key bytes come
					; before the name - 1 for a
					; segment, 0 for a group or a
					; symbol
		extrn segdef_fields	; a SEGDEF's fixed fields, read
					; before the name: flags, group,
					; size (4 bytes)
		extrn module_count	; how many modules have been read
		endif

COM_ORIGIN	equ	00100h	; where an MSX-DOS .COM starts. A switch
				; moves it - [R11] wants a
				; 64 KB .ROM, which is a different START
				; and not a different mechanism
SEGMENT_PAYLOAD_SIZE	equ	7	; a segment record's payload: the flags
				; byte as the FILE wrote it, the size, the
				; base, whether it has been placed, and
				; ITS ORDINAL - which segment this was,
				; counting from 0 in the order the link
				; first meets them, which is the order
				; they are placed in. The assembler writes
				; SEGDEFs in index order and makes the
				; classic segments before it reads a line,
				; so arrival order puts the default CSEG
				; and DSEG first without the linker
				; needing a rule for them. 094
				; THE PLACED FLAG IS NOT A SPARE BIT of
				; the flags byte: error_segment_differs
				; compares that byte across modules, and
				; our own bit in
				; it would make two modules disagree about
				; a segment they agree on
SEGMENT_FLAGS	equ	0	; and where each one sits
SEGMENT_SIZE	equ	1
SEGMENT_BASE	equ	3
SEGMENT_PLACED	equ	5
SEGMENT_ORDINAL	equ	6	; 094's byte. NOTHING USES THIS ONE: the
				; three routines that touch the payload walk
				; it with inc hl. It is here because the four
				; above map the record, and a map with a hole
				; in it reads as an oversight
MODULE_SEGMENT_MAX	equ	16	; segments one module may
					; contribute to. The map holds a
					; far pointer each, so this is 64
					; bytes of ordinary RAM
MODULE_GROUP_MAX	equ	16	; and groups it may define: one
					; byte each
SEGMENT_BUCKETS	equ	16	; buckets in each table (a power of two)
