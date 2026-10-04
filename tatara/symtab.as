; symtab.as - the symbol table: a name to a value, a type and flags.
;
; It replaces the pass-0 stub that lived at the bottom of
; expr.as, and it is deliberately the same shape: symbol_lookup has
; been a variable since then precisely so that this swap would be one
; store and nothing else.
;
; ONE hash.as table, SYMBOL_BUCKETS buckets. Every record - the name bytes
; included - is in the mapper; only the descriptor is in ordinary RAM,
; because deref may move the window between any two calls but cannot
; move a descriptor the caller is holding.
;
; R1 (names up to 255 characters) therefore costs nothing here: hash.as
; already stores keys of 1..255 bytes, which is what the macro name
; table has been doing. The alternative the plan reserved -
; store a hash and a length, settle collisions by comparing against the
; source text - would also have needed the source line to still exist at
; look-up time, which inside a macro expansion it does not.

SYMTAB_INCLUDED	equ	1		; skips the externals in symtab.inc

		public	symbol_table_init
		public	set_symbol
		public	look_up_symbol
		public	found_flags
		public	define_symbol
		public	declare_public
		public	declare_external
		public	check_pass2_labels
		public	dump_symbols
		public	list_symbols
		public	segment_table_init
		public	segment_reset
		public	segment_directive
		public	group_directive
		public	require_placeable
		public	location_counter
		public	current_segment
		public	park_counter
		public	symbol_table	; all three are walked: the object
		public	segment_table	;   file's GRPDEF, SEGDEF, EXTDEF
		public	group_table	;   and PUBDEF records are what
		public	segment_count	;   these tables already hold
		public	group_count

		include	symtab.inc
		include	cmdline.inc	; opt_case: HT_CASE_SENSITIVE or
					;   HT_CASE_FOLD, from /C
		include	hash.inc
		include	alloc.inc	; before farptr.inc: derefp needs deref
		include	farptr.inc	; to have been declared
		include	errs.inc
		include	expr.inc	; SY_ABS, SY_CODE, SY_DATA
		include	ascii.inc	; CHR_TAB, in segment_directive's scan
		include	strutil.inc	; fold_to_upper, to read TRANSIENT
		include	srcline.inc
				; pass_number: define_symbol's two messages
		include	msxdos.inc
		; print_zero_string, print_decimal, _CONOUT - dump_symbols
		include	emit.inc
				; write_output, write_char, write_crlf: the
					;   page writes through the listing,
					;   not to the screen

		cseg

; symbol_table_init - an empty table, in the case mode the command line asked
; for.
;
;   CALLED ONCE, beside heap_init - not once per pass like macro_table_init and
;   expand_init. The symbol table is the one structure that has to survive
;   from pass 1 into pass 2; that is the exception recorded when pass
;   state was settled.
;
;   It reads opt_case, so parse_command_line must have run. tatara.as moves the
;   parse_command_line call above the inits for exactly this reason.
;
; Input:	nothing (opt_case)
; Output:	the table is empty
; 		next_external = 0: the first EXTRN gets index 0
; Modifies:	AF, BC, DE, HL

symbol_table_init:
		xor	a
		ld	(next_external),a	; no externals declared yet
		ld	ix,symbol_table
		ld	a,(opt_case)
		ld	b,SYMBOL_BUCKET_MASK
		jp	htinit

; set_symbol - define a symbol, or give an existing one a new value.
;
;   SET and DEFL redefine; a redefinition must land on the SAME record,
;   or the table grows by one every time round a loop and htfind keeps
;   answering with the first. So: htfind first, htadd only if it is not
;   there.
;
;   A NEW record's payload is uninitialised - hash.as says so plainly -
;   so the flags byte is cleared on the add path only. Not on the
;   redefine path: a symbol declared PUBLIC and then given a new value
;   by SET is still public.
;
; Input:	DE -> the name, B = its length
;		HL = the value
;		A  = the type (SY_ABS and the others)
; Output:	stored (error_out_of_memory does not return)
; Modifies:	AF, BC, DE, HL, IX

set_symbol:	ld	(wanted_value),hl
					; htfind clobbers all four of these
		ld	(wanted_name_at),de
		ld	(wanted_type),a
		ld	a,b
		ld	(wanted_name_length),a

		ld	ix,symbol_table
		ld	hl,symbol_payload
		call	htfind		; A is still the length
		jr	nc,set_symbol.store
					; there already: overwrite it in place

		ld	de,(wanted_name_at)	; htfind clobbered DE and A
		ld	a,(wanted_name_length)
		ld	bc,SYMBOL_SIZE
		ld	hl,symbol_payload
		call	htadd
		jp	c,error_out_of_memory

		derefp	symbol_payload	; new record: nothing has set the flags
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	(hl),0

set_symbol.store:
		derefp	symbol_payload	; HL -> the payload, mapped
		ld	de,(wanted_value)
		ld	(hl),e		; SYMBOL_VALUE
		inc	hl
		ld	(hl),d
		inc	hl
		ld	a,(wanted_type)
		ld	(hl),a		; SYMBOL_TYPE
		ret

; look_up_symbol - what is this name worth?
;
;   symbol_lookup points here. The contract is p0look's, unchanged, which is
;   why nothing in expr.as above symbol_lookup had to be touched.
;
; Input:	DE -> the name, B = its length
; Output:	CY set   = no such symbol
;		CY clear = HL is the value, A is the type
; Modifies:	AF, BC, DE, HL, IX

look_up_symbol:	ld	a,b
		or	a
		scf
		ret	z		; an empty name is not a symbol

		ld	ix,symbol_table
		ld	hl,symbol_payload
		call	htfind
		ret	c		; not found: the CY htfind set is the
					; answer

		derefp	symbol_payload
		ld	e,(hl)		; SYMBOL_VALUE
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)		; SYMBOL_TYPE
		inc	hl
		push	af
		ld	a,(hl)
			; SYMBOL_FLAGS, for define_symbol and read_symbol:
		ld	(found_flags),a	; one deref answers both questions
		pop	af
		ex	de,hl		; HL = the value
		or	a		; clears CY = found
		ret

; define_symbol - define a symbol, with the rules.
;
;   set_symbol is the raw store; this is the one every caller should use.
;   The rules it keeps:
;
;     a name with no value yet    - PUBLIC made the record: define it
;     EXTRN named it - another module defines it: error_already_defined one
;     side SET/DEFL, one not - error_already_defined, M80's M error both
;     SET/DEFL - redefine, as often as asked both fixed, same value - allowed:
;     this is pass 2 re-reading the line, and 2.6.11 allows it once both fixed,
;     different - pass 1: error_already_defined. Pass 2: error_phase, because
;     the SAME line answered differently the second time
;
;   AND ONE MARK, which check_pass2_labels reads at the end of pass 2: every
;   definition made while pass 2 runs sets SYMBOL_PASS2, so a label that
;   still lacks it is one the second reading never reached. THE EARLY
;   RETURN BELOW IS ON THAT PATH - "same value, nothing to do" is what
;   every unchanged label does on pass 2, and it has to mark before it
;   returns or every label in the program is reported.
;
; Input:	DE -> the name
; 		B  = its length
; 		HL = the value
; 		A  = the type (a segment index)
; 		C  = SYMBOL_VARIABLE for SET/DEFL, 0 for everything else
; Output:	defined (error_already_defined and error_phase do not return)
; Modifies:	AF, BC, DE, HL, IX

define_symbol:	ld	(wanted_value),hl
					; the same scratch set_symbol uses
		ld	(wanted_name_at),de
		ld	(wanted_type),a
		ld	a,b
		ld	(wanted_name_length),a
		ld	a,c
		ld	(wanted_flags),a

		call	refuse_index_half	; IXH, IXL, IYH and IYL are
					;   registers now, whatever M80 let
					;   them be
		call	look_up_symbol	; CY set = nothing by that name
		jr	c,define_symbol.store
		ld	(found_value),hl	; keep what it was worth
		ld	(found_type),a	;   and which segment it was in
		ld	a,(found_flags)
		and	SYMBOL_DEFINED
		jr	z,define_symbol.store
					; PUBLIC made it; this is its value
		ld	a,(found_flags)
		and	SYMBOL_EXTERNAL
		jp	nz,error_already_defined
					; EXTRN gave it to another module

		ld	a,(found_flags)	; fixed and variable do not mix
		and	SYMBOL_VARIABLE
		ld	c,a
		ld	a,(wanted_flags)
		and	SYMBOL_VARIABLE
		cp	c
		jp	nz,error_already_defined
		or	a
		jr	nz,define_symbol.store
					; both variable: SET may redefine

		ld	hl,(found_value)
					; both fixed: the same value is no
		ld	de,(wanted_value)	; redefinition at all
		or	a
		sbc	hl,de
		jr	nz,define_symbol.differs
		ld	a,(found_type)
		ld	hl,wanted_type
		cp	(hl)
		jr	z,define_symbol.mark_pass2
					; and the same segment: nothing to
					;   STORE. THE MARK STILL GOES ON:
					;   this is the path every unchanged
					;   label takes on pass 2
define_symbol.differs:
		ld	a,(pass_number)
		dec	a
		jp	z,error_already_defined
					; pass 1: the source says it twice
		jp	error_phase	; pass 2: the same line, two answers

define_symbol.store:
		ld	hl,(wanted_value)
		ld	de,(wanted_name_at)
		ld	a,(wanted_name_length)
		ld	b,a
		ld	a,(wanted_type)
		call	set_symbol
		derefp	symbol_payload	; the flags, on top of whatever the
		ld	de,SYMBOL_FLAGS	; record already carried
		add	hl,de
		ld	a,(wanted_flags)
		or	SYMBOL_DEFINED
		or	(hl)
		ld	(hl),a
		and	SYMBOL_IS_LABEL	; A LABEL, and only a label, keeps
		jr	z,define_symbol.mark_pass2
					;   the line it was written on: it
		inc	hl	;   is the only kind check_pass2_labels checks,
		ld	a,(current_file)
					;   and the only one whose position
		ld	(hl),a		;   an error would want. The window
		inc	hl		;   is still mapped - nothing has
		ld	de,(current_line)
					;   called BDOS since the flags went
		ld	(hl),e		;   in
		inc	hl
		ld	(hl),d

; define_symbol.mark_pass2 - "this symbol was defined on THIS reading of the
; source".
;
;   PASS 1 SETS NOTHING. The bit means pass 2, so leaving it clear on
;   the first reading is what lets check_pass2_labels be one walk after pass 2
;   rather than a walk to clear the bits before it and a walk to read
;   them after.
;
;   derefp again, and not the HL the caller is holding: both paths in
;   have the window mapped, but one of them arrived without touching
;   it, and a deref is cheaper than a rule about which.

define_symbol.mark_pass2:
		ld	a,(pass_number)
		cp	2
		ret	nz		; pass 1: the bit is pass 2's
		derefp	symbol_payload
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	a,(hl)
		or	SYMBOL_PASS2
		ld	(hl),a
		ret

; declare_public - mark one name PUBLIC, creating a record with no value if
;   nothing has defined it yet.
;
;   "public foo" at the top and "foo:" two hundred lines down is the
;   ordinary way to write it, which is what SYMBOL_DEFINED exists for.
;
; Input:	DE -> the name
; 		B  = its length
; Output:	the record carries SYMBOL_PUBLIC
; Modifies:	AF, BC, DE, HL, IX

declare_public:	ld	(wanted_name_at),de
		ld	a,b
		ld	(wanted_name_length),a
		call	refuse_index_half
					; a name that cannot be defined may
					;   not be declared either
		call	look_up_symbol	; CY set = make one
		jr	c,declare_public.new_record
		ld	a,(found_flags)
		and	SYMBOL_EXTERNAL
		jp	nz,error_already_defined
					; EXTRN claimed it first - 2.6.10
		derefp	symbol_payload	; it is there: just add the flag
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	a,(hl)
		or	SYMBOL_PUBLIC
		ld	(hl),a
		ret

declare_public.new_record:
		ld	de,(wanted_name_at)
				; a record with no value: SYMBOL_DEFINED
		ld	a,(wanted_name_length)
				; stays clear, so define_symbol will treat
		ld	b,a		; the first definition as one
		ld	hl,0
		ld	a,SY_ABS
		call	set_symbol
		derefp	symbol_payload
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	(hl),SYMBOL_PUBLIC
		ret

; declare_external - declare one name external, and give it the next index.
;
;   An external has no value, so SYMBOL_VALUE carries its INDEX: the
;   writes the EXTDEF records in that order, and a fixup naming an
;   external already has the number to write.
;
; Input:	DE -> the name
; 		B  = its length
; Output:	the record carries SYMBOL_EXTERNAL, SYMBOL_VALUE = its index
; Modifies:	AF, BC, DE, HL, IX

declare_external:
		ld	(wanted_name_at),de
		ld	a,b
		ld	(wanted_name_length),a
		call	refuse_index_half	; and this one matters most: an
					;   external named IXH would be
					;   written as a register instead
		call	look_up_symbol
		jr	c,declare_external.new_index

; refuse_index_half - may a symbol be called this?
;
;   IXH, IXL, IYH and IYL are registers from 104 onwards and were legal
;   M80 symbol names before it. A source that uses one as a label would
;   otherwise change its bytes in silence - "ld a,ixh" was an immediate
;   load and becomes DD 7C - so the name stops being available, like B
;   and HL have always been, and the change announces itself on the line
;   that causes it.
;
;   A CHARACTER TEST AND NOT A TABLE LOOKUP. Asking register_table which rows
;   are OPERAND_HALF would never restate the rule, and would make the symbol
;   table depend on the instruction table to learn that four names are
;   registers. They share a RULE, not an interface - 089's argument for
;   keeping three quote scanners - and this rule is a closed set the Z80
;   defines, three characters long, that cannot drift.
;
;   Registers fold case wherever they appear, so this does too: ixh is
;   refused under /C exactly as IXH is.
;
;   This is the whole of the refusal. PUBLIC, EXTRN, labels, EQU, SET
;   and DEFL are all of the ways a name can be introduced, and the three
;   routines above are all of the doors.
;
; Input:	DE -> the name
;		B  = its length
; Output:	returns, or error_index_half_name does not return
; Modifies:	AF - DE and B are kept, because every caller still wants
;		them

refuse_index_half:
		ld	a,b		; three characters, and no other
		cp	3		;   length can be one of the four
		ret	nz
		push	de
		ld	a,(de)
		call	fold_to_upper
		cp	"I"
		jr	nz,refuse_index_half.allow
		inc	de
		ld	a,(de)
		call	fold_to_upper
		cp	"X"
		jr	z,refuse_index_half.second
		cp	"Y"
		jr	nz,refuse_index_half.allow
refuse_index_half.second:
		inc	de
		ld	a,(de)
		call	fold_to_upper
		cp	"H"
		jr	z,refuse_index_half.refuse
		cp	"L"
		jr	nz,refuse_index_half.allow
refuse_index_half.refuse:
		pop	de
		jp	error_index_half_name
refuse_index_half.allow:
		pop	de
		ret
		ld	a,(found_flags)
		and	SYMBOL_EXTERNAL
		ret	nz		; already external: the source said
					; EXTRN twice, or pass 2 is reading
					; the same line again. Its index is
					; handed out and must not change
		ld	a,(found_flags)
		and	SYMBOL_DEFINED
		jp	nz,error_already_defined
					; this module defines it - 2.6.12

declare_external.new_index:
		ld	a,(next_external)	; its index
		cp	EXTERNAL_MAX
		jp	nc,error_too_many_segments
		ld	l,a
		inc	a
		ld	(next_external),a
		ld	h,0		; HL = the index, as the value
		ld	de,(wanted_name_at)
		ld	a,(wanted_name_length)
		ld	b,a
		ld	a,SY_ABS
		ld	c,SYMBOL_EXTERNAL
		jp	define_symbol

; check_pass2_labels - every label that pass 1 defined and pass 2 did not.
;
;   A GUARD KEYED ON A SYMBOL FIRES ONCE PER PROGRAM, not once per
;   pass: the symbol table survives between the two readings, so
;   "ifndef gcode_inc" is true the first time and false the second and
;   the block inside it is skipped. A label in there keeps its pass-1
;   value while its bytes are never emitted, so "call shared" assembles
;   to the right address and the routine it calls is not in the file.
;   Issue #12.
;
;   define_label's pass-2 agreement check cannot see this: error_phase fires on
;   a label that answers differently the second time, and this is a
;   label that does not answer at all.
;
;   M80 prints nothing here (2.6.26 of the manual documents the
;   asymmetry as expected behaviour) and writes the short program. This
;   is the third deliberate departure, after error_unknown_operation and the
;   second label, and for the same reason: a silent wrong answer costs more
;   than an incompatibility nobody relies on deliberately.
;
;   LABELS ONLY. A guarded include holding nothing but EQUs is skipped
;   on pass 2 in exactly the same way and NOTHING IS WRONG WITH IT -
;   the equates keep their pass-1 values and every reference resolves
;   to them. Reporting those would outlaw the one form of the idiom
;   that works, which is what SYMBOL_IS_LABEL is for.
;
;   SYMBOL_DEFINED and SYMBOL_EXTERNAL need no test. SYMBOL_IS_LABEL is set in
;   one place, define_label, which always defines - so SYMBOL_DEFINED always
;   rides with it - and a name cannot be a label and external both without
;   error_already_defined having fired on pass 1.
;
;   It borrows dump_walk and dump_payload from dump_symbols below. The two
;   never run at once: this one is the first thing main.finish does,
;   dump_symbols is several calls later, and if this one finds anything it does
;   not return.
;
; Input:	nothing (the table, SYMBOL_IS_LABEL and SYMBOL_PASS2)
; Output:	nothing, if every label was defined twice
;		(error_pass2_label does not return)
; Modifies:	everything

check_pass2_labels:
		xor	a
		ld	(dump_walk),a	; start the walk
		ld	hl,NULL_OFFSET
		ld	(dump_walk+3),hl
check_pass2_labels.next_record:
		ld	ix,symbol_table
		ld	hl,dump_walk
		call	htnext
		ret	c		; the whole table is clean
		call	dump_payload
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	a,(hl)
		and	SYMBOL_IS_LABEL+SYMBOL_PASS2
		cp	SYMBOL_IS_LABEL
		jr	nz,check_pass2_labels.next_record
					; not a label, or the second reading
					;   defined it too
		inc	hl	; SYMBOL_FILE and SYMBOL_LINE: the line the
		ld	a,(hl)		;   label itself was written on,
		inc	hl		;   which is where the error points -
		ld	e,(hl)		;   current_line is the END line by now
		inc	hl
		ld	d,(hl)
		ex	de,hl		; A = the file, HL = the line
		jp	error_pass2_label

; list_symbols - every symbol, in M80's columns, for the listing's last
;   page: four hex digits, the relocation mark, three spaces, and the
;   name in sixteen. Three to a line.
;
;   A SECOND WALK, not a reformatting of dump_symbols. That one is a
;   diagnostic and prints the flags and the segment index; this one is
;   M80's page and prints neither. Sharing them would mean a formatter
;   argument, which is more machinery than the eight lines it saves.
;
;   The name comes out of the mapper a character at a time, for the
;   reason dump_symbols's own header gives.
;
; Input:	nothing
; Output:	the symbols are written
; Modifies:	AF, BC, DE, HL, IX

list_symbols:	xor	a
		ld	(symbol_walk),a	; bucket 0...
		ld	hl,NULL_OFFSET
		ld	(symbol_walk+3),hl	; ...and no record yet
		xor	a
		ld	(list_column),a	; and none on this line

list_symbols.next_record:
		ld	ix,symbol_table
		ld	hl,symbol_walk
		call	htnext
		jr	c,list_symbols.done
		call	list_payload	; the value and the segment
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)
		ld	(list_segment),a

		inc	hl	; SYMBOL_FLAGS. AN EXTERNAL'S SYMBOL_VALUE IS
		ld	a,(hl)	;   ITS INDEX, not a value - declare_external
		and	SYMBOL_EXTERNAL	;   keeps it there because that is
		jr	z,list_symbols.segment
					;   where an external record's number
		ld	a,"*"		;   lives - so printing it gives 0000,
		ld	(list_mark),a	;   0001 and an empty mark, which
		ld	de,0		;   reads as an absolute symbol worth
		jr	list_symbols.number
					;   nothing. M80 prints the address of
					;   the LAST USE and a star; we have no
					;   such address (see 091) and print
					;   0000 with the star, which at least
					;   cannot be mistaken for a value
list_symbols.segment:
		ld	a,(list_segment)
		or	a
		ld	a," "
		jr	z,list_symbols.mark
		ld	a,"'"
list_symbols.mark:
		ld	(list_mark),a

list_symbols.number:
		push	de
		ld	de,list_buffer	; four digits, then the mark
		ld	h,d
		ld	l,e
		pop	de
		ex	de,hl
		call	build_hex_word
		ld	a,(list_mark)
list_symbols.store_mark:
		ld	(de),a
		ld	de,list_buffer
		ld	a,5
		call	write_output
		ld	a,3
		call	write_spaces

		ld	c,0		; the name, and how long it was
list_symbols.name_char:
		call	list_key
		ld	b,a
		ld	a,c
		cp	b
		jr	nc,list_symbols.pad
		ld	e,c
		ld	d,0
		add	hl,de
		ld	a,(hl)
		push	bc
		call	write_char
		pop	bc
		inc	c
		jr	list_symbols.name_char
list_symbols.pad:
		ld	a,16		; sixteen columns, whatever the name
		sub	c		;   came to
		jr	c,list_symbols.line_end
		call	write_spaces

list_symbols.line_end:
		ld	hl,list_column	; three to a line
		inc	(hl)
		ld	a,(hl)
		cp	3
		jp	c,list_symbols.next_record
		ld	(hl),0
		call	write_crlf
		jp	list_symbols.next_record

list_symbols.done:
		ld	a,(list_column)	; and a last line ending if the last
		or	a		;   line was not full
		ret	z
		jp	write_crlf

; list_key, list_payload - the record the walk is on, mapped. EVERY BDOS CALL
;   UNDOES THIS, which is why the name loop calls list_key again for each
;   character.

list_key:	derefp	symbol_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)
		inc	hl
		ret

list_payload:	call	list_key
		ld	e,a
		ld	d,0
		add	hl,de
		ret

; dump_symbols - print every symbol: /S.
;
;   In the hash table's order, which is neither alphabetical nor the
;   order of the source. Sorting would need somewhere to put the sorted
;   list, and a reader can scan twenty lines.
;
;   THE NAME IS PRINTED ONE CHARACTER AT A TIME, re-mapping the record
;   for each. The name is in the mapper, and every BDOS call hands page 2
;   back to MSX-DOS - so the mapping is gone after the first character.
;   The alternative is a buffer in ordinary RAM, and a dump that two
;   tests use does not deserve 33 bytes of it.
;
; Input:	nothing
; Output:	the table is printed
; Modifies:	AF, BC, DE, HL, IX

; dump_symbols - the symbol table, grouped by segment. /S.
;
;   ONE COLUMN USED TO MEAN THREE THINGS. A symbol once printed
;   as "name = N seg I", and N was a literal for an absolute, an
;   OFFSET into this module's contribution for a segment-relative one,
;   and an external's INDEX IN THE EXTERNAL TABLE for an external.
;   Three meanings, nothing to tell them apart, in decimal, in
;   hash-bucket order.
;
;   Now the segment carries the meaning, which is what it is for: one
;   section per segment, its own line saying what it is and how big,
;   then its symbols in order of offset. Externals and symbols a
;   PUBLIC named but nothing defined have no address in this module,
;   so they go in sections with no address column at all.
;
;   NOT THE LISTING'S SYMBOL TABLE. emit.as writes that one in M80's
;   layout and cmpm80 compares it; the two walks have been separate
; and stay separate.
;
; Input:	nothing (segment_count)
; Output:	the table is printed
; Modifies:	everything

dump_symbols:	call	park_counter	; THE LAST CONTRIBUTION'S SIZE IS
					;   STILL LIVE IN location_counter.
					;   write_tables parks it - and returns
					;   at once when there is no object
					;   file, so under /P the last segment
					;   read 0000h. the own run found it
		xor	a
		ld	(dump_segment_index),a
dump_symbols.next_segment:
		ld	a,(segment_count)
		ld	hl,dump_segment_index
		cp	(hl)
		jr	z,dump_symbols.plain_sections	; every segment done
		call	segment_heading
		call	dump_segment_symbols
		ld	hl,dump_segment_index
		inc	(hl)
		jr	dump_symbols.next_segment

dump_symbols.plain_sections:
		ld	hl,msg_external_section	; the two with no address
		ld	(heading_text),hl
		ld	b,SYMBOL_EXTERNAL
		ld	c,SYMBOL_EXTERNAL
		call	dump_plain_section
		ld	hl,msg_undefined_section
		ld	(heading_text),hl
		ld	b,SYMBOL_EXTERNAL+SYMBOL_DEFINED
		ld	c,0
		jp	dump_plain_section

; segment_heading - one segment's heading line.
;
;   THE FIELDS COME OUT OF THE MAPPER FIRST. Printing hands page 2
;   back to MSX-DOS, so a record read after the first _STROUT is read
;   from whatever DOS has put there.
;
; Input:	dump_segment_index
; Output: the line, and dump_segment_size, dump_segment_flags and
; dump_segment_group
; Modifies:	everything

segment_heading:
		ld	ix,segment_table
		ld	c,SEGMENT_INDEX
		ld	a,(dump_segment_index)
		call	find_by_field
		ret	c		; no such index: cannot happen
		call	dump_payload
		ld	de,SEGMENT_SIZE
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(dump_segment_size),de
		inc	hl
		ld	a,(hl)
		ld	(dump_segment_flags),a
		inc	hl
		ld	a,(hl)
		ld	(dump_segment_group),a

		call	segment_name
				; IT ANSWERS IN is_reserved_name AND NOT IN A
		ld	de,msg_heading_dash
					;   FLAG: the _STROUT below would
		call	print_dollar_string	;   destroy one, and did
		ld	a,(dump_segment_flags)
		and	SEGMENT_IS_ABSOLUTE
		jr	nz,segment_heading.absolute
					; the ASEG is neither code nor data
		ld	a,(is_reserved_name)
		or	a
		jr	z,segment_heading.default
		ld	de,msg_named	; "named "
		call	print_dollar_string
		jr	segment_heading.kind
segment_heading.default:
		ld	de,msg_default	; "default "
		call	print_dollar_string
segment_heading.kind:
		ld	a,(dump_segment_flags)
		and	SEGMENT_IS_DATA
		ld	de,msg_code_segment
		jr	z,segment_heading.kind_word
		ld	de,msg_data_segment
segment_heading.kind_word:
		call	print_dollar_string
		jr	segment_heading.transient
segment_heading.absolute:
		ld	de,msg_absolute
		call	print_dollar_string

segment_heading.transient:
		ld	a,(dump_segment_flags)
		and	SEGMENT_IS_TRANSIENT
		jr	z,segment_heading.group
		ld	de,msg_transient
		call	print_dollar_string

segment_heading.group:
		ld	a,(dump_segment_group)
		cp	GROUP_NONE
		jr	z,segment_heading.size
		ld	de,msg_heading_group
		call	print_dollar_string
		ld	ix,group_table
		ld	c,0		; A GROUP RECORD'S PAYLOAD IS ITS
		ld	a,(dump_segment_group)
					;   NUMBER, with nothing in front of
					;   it - write_groups says so too. And
					;   its key is the bare name: only a
					;   SEGMENT's key carries a group byte
		call	find_by_field
		jr	c,segment_heading.size	; no such group: cannot happen
		call	dump_key
		ld	(key_length),a
		xor	a
		ld	(key_offset),a
		call	print_key_chars

segment_heading.size:
		ld	a,(dump_segment_flags)
					; ASEG has no size worth printing
		and	SEGMENT_IS_ABSOLUTE
		jr	nz,segment_heading.line_end
		ld	de,msg_heading_comma
		call	print_dollar_string
		ld	hl,(dump_segment_size)
		ld	de,hex_field
		call	build_hex_word
		ld	de,hex_field
		call	print_dollar_string
		ld	de,msg_heading_bytes
		call	print_dollar_string
segment_heading.line_end:
		ld	de,msg_dump_newline
		call	print_dollar_string
		ld	de,msg_dump_newline
		call	print_dollar_string
		ret

; segment_name - the segment's name.
;
;   THE KEY DECIDES, NOT THE INDEX. segment_table_init's three records are
;   keyed " A", " C" and " D" - a space and a letter, which segment_directive
;   cannot produce from a source line - but they are NOT always indices 0, 1
;   and 2: "group work" then "cseg" makes a second record keyed " C" with a
;   different group and an index of its own, and it is still the default code
;   segment.
;
;   The key's first byte is the group number; the name follows it.
;
; Input:	the iterator is on the record
; Output:	Z set = it was one of the three reserved names
; Modifies:	everything

segment_name:	call	dump_key
		dec	a		; without the group byte
		ld	(key_length),a
		ld	b,a
		inc	hl		; past it
		ld	a,b
		cp	2
		jr	nz,segment_name.own_name
					; only a two-byte name can be one
		ld	a,(hl)
		cp	" "
		jr	nz,segment_name.own_name
		inc	hl
		ld	a,(hl)
		ld	de,msg_aseg
		cp	"A"
		jr	z,segment_name.reserved
		ld	de,msg_cseg
		cp	"C"
		jr	z,segment_name.reserved
		ld	de,msg_dseg
		cp	"D"
		jr	nz,segment_name.own_name
segment_name.reserved:
		call	print_dollar_string
		xor	a
		ld	(is_reserved_name),a	; one of the three
		ret
segment_name.own_name:
		ld	a,1
		ld	(key_offset),a	; over the group byte
		call	print_key_chars
		ld	a,1
		ld	(is_reserved_name),a	; a name of its own
		ret

; find_by_field - the record in table IX whose byte at payload offset C holds
;   A. One walk, and the iterator is left on it.
;
;   Serves the segment table and the group table both, which is why it
;   takes the table and the field rather than knowing them.
;
; Input:	IX -> the table, C = the field, A = the value
; Output:	CY clear = dump_walk is on it
; Modifies:	everything

find_by_field:	ld	(wanted_field),a
		xor	a
		ld	(dump_walk),a
		ld	hl,NULL_OFFSET
		ld	(dump_walk+3),hl
find_by_field.next_record:
		push	bc
		ld	hl,dump_walk
		call	htnext	; IX SURVIVES IT, and survives dump_payload:
		pop	bc	;   find_by_index has relied on that since
		ret	c		;   and this is its shape
		push	bc
		call	dump_payload
		pop	bc
		ld	b,0
		add	hl,bc
		ld	a,(hl)
		ld	hl,wanted_field
		cp	(hl)
		jr	nz,find_by_field.next_record
		or	a		; found it: CY clear
		ret

; print_key_chars - key_length characters of the current record's key, from
; key_offset.
;
;   THE KEY IS MAPPED AGAIN FOR EVERY CHARACTER, and the count lives in
;   RAM rather than a register for the same reason: _CONOUT is a BDOS
;   call and page 2 goes back to MSX-DOS with it.
;
; Input:	key_offset, key_length, the iterator on a record
; Output:	they are printed
; Modifies:	everything

print_key_chars:
		ld	a,(key_length)
		or	a
		ret	z
print_key_chars.next_char:
		call	dump_key
		ld	a,(key_offset)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	e,(hl)
		call	print_char
		ld	hl,key_offset
		inc	(hl)
		ld	hl,key_length
		dec	(hl)
		jr	nz,print_key_chars.next_char
		ret

; dump_segment_symbols - one segment's symbols, in order of offset.
;
; Input:	dump_segment_index
; Output:	they are printed, or "(no symbols)"
; Modifies:	everything

dump_segment_symbols:
		ld	hl,0
		ld	(offset_wanted),hl
		xor	a
		ld	(ordinal_wanted),a
		ld	(segment_had_symbols),a
dump_segment_symbols.next:
		call	print_and_scan
		jr	nc,dump_segment_symbols.printed	; it printed one
		ld	a,(next_offset_found)
		or	a
		jr	z,dump_segment_symbols.done
		ld	hl,(next_offset)	; on to the next offset
		ld	(offset_wanted),hl
		xor	a
		ld	(ordinal_wanted),a
		jr	dump_segment_symbols.next
dump_segment_symbols.printed:
		ld	hl,ordinal_wanted	; another at the same offset?
		inc	(hl)
		jr	dump_segment_symbols.next
dump_segment_symbols.done:
		ld	a,(segment_had_symbols)
		or	a
		jr	nz,dump_segment_symbols.newline
		ld	de,msg_no_symbols
		call	print_dollar_string
dump_segment_symbols.newline:
		ld	de,msg_dump_newline
		call	print_dollar_string
		ret

; print_and_scan - ONE walk of the symbol table, doing two jobs at once.
;
;   It prints the record at (offset_wanted, ordinal_wanted) if there is one,
;   and it finds the smallest offset strictly above offset_wanted for when
;   there is not. Both in the same pass, because the pass is the expensive
;   part.
;
;   THE ORDINAL IS THE TIE-BREAK, and it is why no buffer is needed.
;   Two labels at one address must not print each other forever; the
;   obvious cure is to remember the last NAME, which costs 256 bytes
;   because [R1] allows 255 characters. But the walk is deterministic
;   and nothing changes the table while it runs, so "the third record
;   with this offset, in walk order" is a thing that can be counted to.
;
; Input:	dump_segment_index, offset_wanted, ordinal_wanted
; Output:	CY clear = a line was printed
;		next_offset, next_offset_found = the next offset up, if any
; Modifies:	everything

print_and_scan:	xor	a
		ld	(ordinal_seen),a
		ld	(next_offset_found),a
		ld	(line_printed),a
		ld	(dump_walk),a	; start the walk
		ld	hl,NULL_OFFSET
		ld	(dump_walk+3),hl
print_and_scan.next_record:
		ld	ix,symbol_table
		ld	hl,dump_walk
		call	htnext
		jr	c,print_and_scan.done
		call	dump_payload
		ld	e,(hl)		; SYMBOL_VALUE
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)		; SYMBOL_TYPE
		inc	hl
		ld	b,(hl)		; SYMBOL_FLAGS
		ld	hl,dump_segment_index
		cp	(hl)
		jr	nz,print_and_scan.next_record	; another segment's
		ld	a,b
		and	SYMBOL_EXTERNAL
		jr	nz,print_and_scan.next_record
					; has a section of its own
		ld	a,b
		and	SYMBOL_DEFINED
		jr	z,print_and_scan.next_record	;   and so has this one
		ld	a,b
		ld	(dump_flags),a

		ld	hl,(offset_wanted)
					; DE = SYMBOL_VALUE, HL = offset_wanted
		or	a
		sbc	hl,de
		jr	z,print_and_scan.same_offset
		jr	c,print_and_scan.above	; offset_wanted < SYMBOL_VALUE
		jr	print_and_scan.next_record
					; below: already printed

print_and_scan.same_offset:
		ld	a,(ordinal_seen)
					; the ordinal_wanted-th at this offset
		ld	hl,ordinal_wanted
		cp	(hl)
		jr	nz,print_and_scan.count_it
		ld	a,(line_printed)
		or	a
		jr	nz,print_and_scan.count_it	; one per pass
		call	dump_symbol_line
		ld	a,0ffh
		ld	(line_printed),a
		ld	(segment_had_symbols),a
print_and_scan.count_it:
		ld	hl,ordinal_seen
		inc	(hl)
		jr	print_and_scan.next_record

print_and_scan.above:
		ld	a,(next_offset_found)
					; the smallest one above offset_wanted
		or	a
		jr	z,print_and_scan.take
		ld	hl,(next_offset)
		or	a
		sbc	hl,de
		jr	c,print_and_scan.next_record
					; next_offset is already smaller
		jr	z,print_and_scan.next_record
print_and_scan.take:
		ld	(next_offset),de
		ld	a,0ffh
		ld	(next_offset_found),a
		jr	print_and_scan.next_record

print_and_scan.done:
		ld	a,(line_printed)
		or	a
		scf
		ret	z		; nothing printed
		or	a		; CY clear: one was
		ret

; dump_symbol_line - one symbol: its offset, its type and its name.
;
;   The four hex digits go into the four bytes in front of "h  $", so
;   the whole column is one _STROUT and there is no arithmetic.
;
; Input:	offset_wanted, dump_flags, the iterator on the record
; Output:	one line
; Modifies:	everything

dump_symbol_line:
		ld	hl,(offset_wanted)
		ld	de,hex_field
		call	build_hex_word
		ld	de,hex_field
		call	print_dollar_string
		ld	de,msg_type_gap	; the two spaces a HEADING must not
		call	print_dollar_string
					;   have: it wants "0003h bytes"
		ld	a,(dump_flags)
		and	SYMBOL_PUBLIC+SYMBOL_VARIABLE
		ld	de,msg_type_local
		jr	z,dump_symbol_line.print_type
		cp	SYMBOL_PUBLIC
		ld	de,msg_type_public
		jr	z,dump_symbol_line.print_type
		cp	SYMBOL_VARIABLE
		ld	de,msg_type_variable
		jr	z,dump_symbol_line.print_type
		ld	de,msg_type_public_var
dump_symbol_line.print_type:
		call	print_dollar_string
		call	dump_key
		ld	(key_length),a
		xor	a
		ld	(key_offset),a
		call	print_key_chars
		ld	de,msg_dump_newline
		call	print_dollar_string
		ret

; dump_plain_section - a section with no address column: the externals, and the
;   symbols a PUBLIC named that nothing defined.
;
;   THE HEADING IS PRINTED ON THE FIRST MATCH, so a module with no
;   externals gets no empty section.
;
; Input:	B = the mask, C = what it must equal
;		heading_text -> the heading
; Output:	the section, or nothing at all
; Modifies:	everything

dump_plain_section:
		ld	a,b
		ld	(wanted_mask),a
		ld	a,c
		ld	(wanted_field),a
		xor	a
		ld	(line_printed),a
		ld	(dump_walk),a
		ld	hl,NULL_OFFSET
		ld	(dump_walk+3),hl
dump_plain_section.next_record:
		ld	ix,symbol_table
		ld	hl,dump_walk
		call	htnext
		jr	nc,dump_plain_section.this_record
		ld	a,(line_printed)
					; a blank line after the section, and
		or	a		;   only if there was a section
		ret	z
		ld	de,msg_dump_newline
		call	print_dollar_string
		ret
dump_plain_section.this_record:
		call	dump_payload
		ld	de,SYMBOL_FLAGS
		add	hl,de
		ld	a,(hl)
		ld	hl,wanted_mask
		and	(hl)
		ld	hl,wanted_field
		cp	(hl)
		jr	nz,dump_plain_section.next_record
		ld	a,(line_printed)
		or	a
		jr	nz,dump_plain_section.print_name
		ld	a,0ffh
		ld	(line_printed),a
		ld	de,(heading_text)
		call	print_dollar_string
		ld	de,msg_dump_newline
		call	print_dollar_string
		ld	de,msg_dump_newline
		call	print_dollar_string
dump_plain_section.print_name:
		ld	de,msg_name_indent
		call	print_dollar_string
		call	dump_key
		ld	(key_length),a
		xor	a
		ld	(key_offset),a
		call	print_key_chars
		ld	de,msg_dump_newline
		call	print_dollar_string
		jp	dump_plain_section.next_record
					; jp AND NOT jr: the section heading
					;   at the top of the loop put this
					;   past 127 bytes

; dump_key - map the record the walk is on: HL -> its name, A = how long.
; dump_payload - the same, but HL -> its payload.
;
;   EVERY BDOS CALL UNDOES THIS, which is why every caller above calls
;   them again rather than keeping what they returned.

dump_key:	derefp	dump_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)		; the key's length
		inc	hl
		ret

dump_payload:	call	dump_key
		ld	e,a
		ld	d,0
		add	hl,de		; over the name, to the payload
		ret

; print_char_keeping_bc - one character, BC kept.

print_char_keeping_bc:
		push	bc
		call	print_char
		pop	bc
		ret

; --- dump_symbols's fragments.

msg_aseg:	defb	"ASEG$"
msg_cseg:	defb	"CSEG$"
msg_dseg:	defb	"DSEG$"
msg_heading_dash:
		defb	" - $"
msg_default:	defb	"default $"
msg_named:	defb	"named $"
msg_code_segment:
		defb	"code segment$"
msg_data_segment:
		defb	"data segment$"
msg_transient:	defb	", transient$"
msg_heading_group:
		defb	", group $"
msg_absolute:	defb	"absolute$"
msg_type_gap:	defb	"  $"
msg_heading_comma:
		defb	", $"
msg_heading_bytes:
		defb	" bytes$"
msg_no_symbols:	defb	"(no symbols)",CHR_CR,CHR_LF,"$"
msg_external_section:
		defb	"EXTERNAL - resolved by the linker$"
msg_undefined_section:
		defb	"UNDEFINED - named by PUBLIC, never defined$"
; --- the type column. ELEVEN characters, not ten: "public var" is ten
;     exactly and left the name with nowhere to start. It also puts
;     these names at column 18, where msg_name_indent has always put the
;     address-less sections' names.

msg_name_indent:
		defb	"                  $"
msg_type_local:	defb	"           $"
msg_type_public:
		defb	"public     $"
msg_type_variable:
		defb	"var        $"
msg_type_public_var:
		defb	"public var $"
msg_dump_newline:
		defb	CHR_CR,CHR_LF,"$"

; --- the segments
;
;   A SEGMENT is a named pool of storage that the linker concatenates
;   across modules. What the assembler counts is not a segment but a
;   (segment, GROUP) CONTRIBUTION, because that is what one SEGDEF
;   record describes: a name, flags, one group, one size.
;
;   Two contributions with the same name and group are laid end to end,
;   here and across modules: they coexist. With different groups they
;   both start at 0 and overlay, and the segment is as large as its
;   largest group. That is [R4]'s transient DSEG, and it is why a label
;   may only be subtracted from a label in the SAME contribution.
;
;   One hash.as table holds the records, in the mapper, keyed by the
;   group's number followed by the name - so the two groups of one
;   transient DSEG are two keys and two counters, for free. Ordinary RAM
;   holds the bucket arrays, the key, and the far pointer to whichever
;   record is current.
;
;   The classic ASEG, CSEG and DSEG are records like any other, created
;   by segment_table_init under the names " A", " C" and " D". Each holds a
;   space, and segment_directive ends a name at the first blank, so no source
;   can name them.

; segment_table_init - both tables, and the three classic segments.
;
;   CALLED ONCE, beside symbol_table_init and heapinit. NOT per pass: a symbol
;   stored on pass 1 holds a segment index, so the indices have to mean
;   the same thing on pass 2. segment_reset empties the counters instead.
;
;   It reads opt_case, so parse_command_line must have run - the same reason
;   symbol_table_init sits where it does.
;
; Input:	nothing (opt_case)
; Output:	the tables exist
;		indices 0, 1 and 2 are ASEG, CSEG and DSEG
; Modifies:	AF, BC, DE, HL, IX

segment_table_init:
		ld	ix,segment_table
		ld	a,(opt_case)
		ld	b,SEGMENT_BUCKET_MASK
		call	htinit
		ld	ix,group_table
		ld	a,(opt_case)
		ld	b,GROUP_BUCKET_MASK
		call	htinit

		xor	a
		ld	(segment_count),a	; the next index to hand out
		ld	(group_count),a
		ld	hl,NULL_OFFSET	; nothing is current yet, so the
		ld	(current_record+2),hl
				;   first select_contribution parks nothing

		ld	hl,name_aseg	; index 0: ASEG
		ld	a,SEGMENT_IS_ABSOLUTE
		call	segment_table_init.classic
		ld	hl,name_cseg	; index 1: the classic CSEG
		xor	a
		call	segment_table_init.classic
		ld	hl,name_dseg	; index 2: the classic DSEG
		ld	a,SEGMENT_IS_DATA

segment_table_init.classic:
		ld	(seg_flags),a
		ld	(seg_name_at),hl
		ld	a,2		; every reserved name is two bytes
		ld	(seg_name_length),a
		ld	a,GROUP_NONE
		ld	(seg_group),a
		jp	select_contribution

; segment_reset - every counter and size to zero, the classic CSEG current.
;
;   Per PASS. It walks the table rather than emptying it: the records
;   and their indices must survive, only the counting starts again.
;
; Input:    nothing
; Output:   as above
; Modifies: AF, BC, DE, HL, IX

segment_reset:	ld	hl,NULL_OFFSET
				; nothing is current: select_contribution must
		ld	(current_record+2),hl
					;   not park pass 1's counter into
					;   a record we are about to clear
		xor	a
		ld	(seg_walk),a	; start the walk: bucket 0...
		ld	hl,NULL_OFFSET
		ld	(seg_walk+3),hl	; ...and no record yet

segment_reset.next_record:
		ld	ix,segment_table
		ld	hl,seg_walk
		call	htnext		; CY set = that was the last one
		jr	c,segment_reset.done
		derefp	seg_walk+1	; HL -> the record
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)		; the key's length...
		inc	hl
		ld	e,a
		ld	d,0
		add	hl,de		; ...steps over the key
		ld	b,4	; SEGMENT_COUNTER and SEGMENT_SIZE, four bytes
segment_reset.zero:
		ld	(hl),0
		inc	hl
		djnz	segment_reset.zero
		jr	segment_reset.next_record

segment_reset.done:
		ld	hl,name_cseg	; M80 starts every module in CSEG
		ld	(seg_name_at),hl
		ld	a,2
		ld	(seg_name_length),a
		xor	a
		ld	(seg_flags),a
		ld	a,GROUP_NONE
		ld	(seg_group),a
		jp	select_contribution

; segment_directive - an ASEG, CSEG or DSEG line.
;
;   The operand is a name, optionally followed by ",TRANSIENT". The name
;   is everything up to the first blank, tab or comma, so no character
;   set has to be defined for it. No name at all means the classic
;   unnamed segment of that kind.
;
;   A fresh mention opens no group: inside a transient DSEG a GROUP line
;   has to come before anything is placed, which is what require_placeable
;   checks.
;
; Input:	A  = 0 for ASEG, 1 for CSEG, 2 for DSEG
;		DE -> the operand field
;		B  = its length
; Output:	that segment is current
; 		(a bad line does not return - error_bad_segment_line stops)
; Modifies:	AF, BC, DE, HL, IX

segment_directive:
		ld	(seg_kind),a
		call	skip_segment_blanks	; over any blanks in front
		push	de		; where the name starts
		ld	c,0		; how long it is

segment_directive.name:
		ld	a,b
		or	a
		jr	z,segment_directive.named
		ld	a,(de)
		cp	" "
		jr	z,segment_directive.named
		cp	CHR_TAB
		jr	z,segment_directive.named
		cp	","
		jr	z,segment_directive.named
		inc	de
		inc	c
		dec	b
		jr	segment_directive.name
segment_directive.named:
		pop	hl		; HL -> the name, C = its length
		ld	(seg_name_at),hl
		ld	a,c
		ld	(seg_name_length),a

		ld	a,(seg_kind)	; ASEG takes no operand at all
		or	a
		jr	nz,segment_directive.code
		ld	a,c
		or	a
		jp	nz,error_bad_segment_line
		ld	hl,name_aseg	; and it has a name of its own
		ld	(seg_name_at),hl
		ld	a,2
		ld	(seg_name_length),a
		ld	a,SEGMENT_IS_ABSOLUTE
		jr	segment_directive.flags

segment_directive.code:
		ld	a,c		; CSEG or DSEG with no name: the
		or	a		;   classic one, under its own name
		jr	nz,segment_directive.kind
		ld	hl,name_cseg
		ld	a,(seg_kind)
		dec	a
		jr	z,segment_directive.code_name
		ld	hl,name_dseg
segment_directive.code_name:
		ld	(seg_name_at),hl
		ld	a,2
		ld	(seg_name_length),a

segment_directive.kind:
		ld	a,(seg_kind)	; 1 = CSEG, 2 = DSEG
		dec	a
		ld	a,0		; ld does not touch the flags, so
		jr	z,segment_directive.flags
					;   the dec above still decides
		ld	a,SEGMENT_IS_DATA
segment_directive.flags:
		ld	(seg_flags),a

		call	skip_segment_blanks	; anything after the name?
		ld	a,b
		or	a
		jr	z,segment_directive.done
		ld	a,(de)
		cp	","
		jp	nz,error_bad_segment_line
		inc	de
		dec	b
		call	skip_segment_blanks
		ld	a,b		; the only word allowed there is
		cp	9		;   TRANSIENT, nine characters
		jp	c,error_bad_segment_line
		ld	hl,word_transient
		ld	c,9
segment_directive.transient:
		ld	a,(de)
		call	fold_to_upper
		cp	(hl)
		jp	nz,error_bad_segment_line
		inc	de
		inc	hl
		dec	b
		dec	c
		jr	nz,segment_directive.transient
		call	skip_segment_blanks
		ld	a,b		; and nothing after it
		or	a
		jp	nz,error_bad_segment_line
		ld	a,(seg_flags)	; TRANSIENT is for a DSEG only
		and	SEGMENT_IS_DATA
		jp	z,error_bad_segment_line
		ld	a,(seg_flags)
		or	SEGMENT_IS_TRANSIENT
		ld	(seg_flags),a

segment_directive.done:
		ld	a,GROUP_NONE	; a fresh mention opens no group
		ld	(seg_group),a
		jp	select_contribution

; group_directive - a GROUP line: open a coexistence group inside the current
;   transient DSEG.
;
;   The group's number is global to the program, so the same name in two
;   modules is one group and their variables are laid end to end. A
;   different group of the same DSEG starts again at 0 and overlays it.
;
; Input:	DE -> the operand field
; 		B  = its length
; Output:	the (segment, group) contribution is current
; 		(a bad line does not return - error_bad_group_line stops)
; Modifies:	AF, BC, DE, HL, IX

group_directive:
		ld	a,(seg_flags)	; only inside a transient DSEG
		and	SEGMENT_IS_TRANSIENT
		jp	z,error_bad_group_line
		call	skip_segment_blanks
		ld	a,b		; the name is the rest of the
		or	a		;   operand, blanks trimmed
		jp	z,error_bad_group_line
		cp	SEGMENT_NAME_MAX+1
		jp	nc,error_segment_name_long
			; and NOT error_bad_segment_line, whose message names
					;   ASEG, CSEG and DSEG - three
					;   directives, and this is a GROUP
					;   line

		ld	ix,group_table	; its number, or the next free one
		ld	a,b
		ld	hl,seg_payload
		push	de
		push	bc
		call	htfind		; CY set = a new group
		pop	bc
		pop	de
		jr	nc,group_directive.existing

		ld	a,b
		ld	bc,1		; the payload is its number
		ld	hl,seg_payload
		call	htadd
		jp	c,error_out_of_memory
		ld	a,(group_count)
		cp	SEGMENT_MAX
		jp	nc,error_too_many_segments
		ld	(seg_group),a	; the number this name now has.
		inc	a		;   In RAM, not in B: derefp goes
		ld	(group_count),a	;   through deref, which clobbers BC
		derefp	seg_payload
		ld	a,(seg_group)
		ld	(hl),a
		jr	group_directive.select

group_directive.existing:
		derefp	seg_payload
		ld	a,(hl)
		ld	(seg_group),a

group_directive.select:
		ld	hl,seg_key+1	; the same segment, the new group.
		ld	(seg_name_at),hl
			;   select_contribution left the current name in
					;   seg_key, where nothing moves it
		ld	a,(seg_key_length)
		dec	a		; the key is the group byte + name
		ld	(seg_name_length),a
		jp	select_contribution

; select_contribution - make a (segment, group) contribution current, creating
; its record the first time it is named.
;
; Input:	seg_name_at -> the name
; 		seg_name_length = its length, 1..SGNMAX
; 		seg_flags = SEGMENT_IS_DATA / SEGMENT_IS_TRANSIENT /
; 		SEGMENT_IS_ABSOLUTE
; 		seg_group  = the group's number, GROUP_NONE if none
; Output: location_counter, current_segment and current_record describe it
; 		seg_name_at points at the copy inside seg_key
; 		(error_bad_segment_line, error_segment_differs,
; 		error_too_many_segments and error_out_of_memory do not
; 		return)
; Modifies:	AF, BC, DE, HL, IX

select_contribution:
		ld	a,(seg_name_length)
		cp	SEGMENT_NAME_MAX+1
		jp	nc,error_segment_name_long
					; longer than the key can hold, and
					;   the message says so rather than
					;   calling the line unparseable
		ld	c,a
		ld	b,0
		ld	a,(seg_group)
		ld	(seg_key),a	; the key is the group's number...
		ld	hl,(seg_name_at)
		ld	de,seg_key+1
		ld	a,c
		or	a
		jr	z,select_contribution.key_done
					; ldir with BC = 0 copies 65536
		ldir			; ...and then the name
select_contribution.key_done:
		ld	a,(seg_name_length)
		inc	a
		ld	(seg_key_length),a
		ld	hl,seg_key+1	; from here the current name is
		ld	(seg_name_at),hl
					;   this copy, which nothing moves

		call	park_counter	; the counter we are leaving

		ld	ix,segment_table
		ld	de,seg_key
		ld	a,(seg_key_length)
		ld	hl,seg_payload
		call	htfind		; CY set = its first mention
		jr	nc,select_contribution.existing

		ld	de,seg_key
		ld	a,(seg_key_length)
		ld	bc,SEGMENT_RECORD_SIZE
		ld	hl,seg_payload
		call	htadd
		jp	c,error_out_of_memory
		ld	a,(segment_count)	; the index it will answer to.
		cp	SEGMENT_MAX	;   Kept in RAM, not in B: derefp
		jp	nc,error_too_many_segments
					;   goes through deref, and deref
		ld	(seg_index),a	;   clobbers BC
		inc	a
		ld	(segment_count),a
		derefp	seg_payload	; a new record: fill it in
		ld	(hl),0		; SEGMENT_COUNTER
		inc	hl
		ld	(hl),0
		inc	hl
		ld	(hl),0		; SEGMENT_SIZE
		inc	hl
		ld	(hl),0
		inc	hl
		ld	a,(seg_flags)
		ld	(hl),a		; SEGMENT_FLAGS
		inc	hl
		ld	a,(seg_key)
		ld	(hl),a		; SEGMENT_GROUP: the key's first byte
		inc	hl
		ld	a,(seg_index)
		ld	(hl),a		; SEGMENT_INDEX
		jr	select_contribution.use

select_contribution.existing:
		derefp	seg_payload	; it exists: it must be the same
		ld	de,SEGMENT_FLAGS
					;   kind of segment as last time
		add	hl,de
		ld	a,(seg_flags)
		cp	(hl)
		jp	nz,error_segment_differs

select_contribution.use:
		derefp	seg_payload
		ld	e,(hl)	; SEGMENT_COUNTER: the counter goes live
		inc	hl
		ld	d,(hl)
		ld	(location_counter),de
		ld	de,SEGMENT_INDEX-1	; HL is at SEGMENT_COUNTER+1
		add	hl,de
		ld	a,(hl)		; SEGMENT_INDEX
		ld	(current_segment),a
		fpcopy	current_record,seg_payload
					; where park_counter will write back
		ret

; park_counter - write the live counter back into the record it came from,
;   and keep the high-water mark.
;
;   The size is a high-water mark rather than a count because ORG can
;   move the counter backwards. It is what the SEGDEF record will carry
;   in the object file.
;
; Input:	location_counter, current_record
; Output:	that record's SEGMENT_COUNTER and SEGMENT_SIZE are up to date
; Modifies:	AF, BC, DE, HL

park_counter:	ld	hl,(current_record+2)	; null = nothing is current yet
		ld	de,NULL_OFFSET
		or	a
		sbc	hl,de
		ret	z
		derefp	current_record
		ld	de,(location_counter)
		ld	(hl),e		; SEGMENT_COUNTER
		inc	hl
		ld	(hl),d
		inc	hl
		ld	c,(hl)		; SEGMENT_SIZE
		inc	hl
		ld	b,(hl)
		ld	h,d		; HL = the counter
		ld	l,e
		or	a
		sbc	hl,bc		; counter - size
		ret	c		; the size is still the larger
		derefp	current_record	; a new high-water mark
		ld	bc,SEGMENT_SIZE
		add	hl,bc
		ld	de,(location_counter)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ret

; require_placeable - may a label or the location counter be placed here?
;
;   Inside a transient DSEG nothing may, until a GROUP line has said
;   what it is allowed to overlay. Called by define_label, ORG, DS, the data
;   directives and every instruction.
;
; Input:	seg_flags, seg_group
; Output:	returns, or error_group_needed stops
; Modifies:	AF

require_placeable:
		ld	a,(seg_flags)
		and	SEGMENT_IS_TRANSIENT
		ret	z		; an ordinary segment: anything goes
		ld	a,(seg_group)
		inc	a		; GROUP_NONE + 1 = 0
		ret	nz
		jp	error_group_needed

; skip_segment_blanks - step DE over blanks and tabs, B counting down what is
; left.
;
; Input:	DE -> the text
; 		B  = how much of it is left
; Output:	DE and B at the first character that is not a blank
; Modifies:	AF, B, DE

skip_segment_blanks:
		ld	a,b
		or	a
		ret	z
		ld	a,(de)
		cp	" "
		jr	z,skip_segment_blanks.step
		cp	CHR_TAB
		ret	nz
skip_segment_blanks.step:
		inc	de
		dec	b
		jr	skip_segment_blanks

; --- the reserved names. Each holds a space, which segment_directive can never
;     put in a name, so no source can reach these three segments by
;     name - only through ASEG, CSEG and DSEG themselves.

name_aseg:	defb	" A"
name_cseg:	defb	" C"
name_dseg:	defb	" D"
word_transient:	defb	"TRANSIENT"

		dseg

wanted_name_at:	defs	2	; set_symbol: the name it was given
wanted_name_length:
		defs	1	;   and its length
wanted_value:	defs	2	;   and the value to store
wanted_type:	defs	1	;   and the type
symbol_payload:	defs	4	; far pointer to a record's payload
found_flags:	defs	1	; look_up_symbol: the flags it found
wanted_flags:	defs	1
			; define_symbol: the flags the caller asked for,
				;   and dump_symbols: the flags it is printing
found_value:	defs	2	; define_symbol: what the symbol was worth
found_type:	defs	1	;   and its segment, for dump_symbols too
dump_walk:	defs	5	; dump_symbols's walk over the table
dump_segment_index:
		defs	1	; the segment index being dumped
dump_segment_size:
		defs	2	; that segment's fields, out of the mapper
dump_segment_flags:
		defs	1	;   BEFORE the first _STROUT takes page 2
dump_segment_group:
		defs	1	;   back to MSX-DOS
key_offset:	defs	1	; print_key_chars's walk: where it is,
key_length:	defs	1	;   and how much is left
offset_wanted:	defs	2	; the offset being printed,
ordinal_wanted:	defs	1	;   and how many at it are done
ordinal_seen:	defs	1	; how many at it this pass has seen
next_offset:	defs	2	; the smallest offset above offset_wanted,
next_offset_found:
		defs	1	;   and whether there was one
line_printed:	defs	1	; this pass printed a line
segment_had_symbols:
		defs	1	; this segment printed any
dump_flags:	defs	1	; the record's SYMBOL_FLAGS, for the type
wanted_mask:	defs	1	; dump_plain_section's test,
wanted_field:	defs	1	;   and find_by_field's value
heading_text:	defs	2	; dump_plain_section's heading
is_reserved_name:
		defs	1	; segment_name's answer: 0 = ASEG, CSEG or DSEG
hex_field:	defs	4
			; build_hex_word writes the digits HERE, and the
		defb	"h$"	;   "h" is in place. The two spaces after
				;   it on a symbol line are dump_symbol_line's,
				;   so that a heading can say "0003h bytes"
symbol_walk:	defs	5	; and list_symbols's, over the same one
list_buffer:	defs	5	; four digits and the relocation mark
list_segment:	defs	1	; which segment this symbol is in
list_mark:	defs	1	; the character after its four digits:
				;   " " absolute, "'" relocatable, "*"
				;   external - and the last of those is
				;   why this is a byte and not a test
				;   made twice
list_column:	defs	1	; how many are on this line, 0 to 2
next_external:	defs	1	; the next external index to hand out
symbol_table:	defs	2+SYMBOL_BUCKETS*4

location_counter:
		defs	2	; the live location counter: the current
				;   contribution's
current_segment:
		defs	1	; that contribution's index
current_record:	defs	4	; and where its record is, for park_counter
seg_name_at:	defs	2	; select_contribution's inputs: the name,
seg_name_length:
		defs	1	;   its length,
seg_flags:	defs	1	;   the flags, and afterwards the current
				;   segment's flags
seg_group:	defs	1	;   the group, and afterwards the current
                		;   group's number
seg_kind:	defs	1	; segment_directive: 0 ASEG, 1 CSEG, 2 DSEG
seg_index:	defs	1
			; select_contribution: the index it is handing out
seg_key:	defs	1+SEGMENT_NAME_MAX
					; the key: the group's number, the name
seg_key_length:	defs	1	;   and its length
seg_payload:	defs	4	; far pointer to a record's payload
seg_walk:	defs	5	; segment_reset's walk over the table
segment_count:	defs	1	; the next segment index to hand out
group_count:	defs	1	; the next group number
segment_table:	defs	2+SEGMENT_BUCKETS*4
group_table:	defs	2+GROUP_BUCKETS*4
