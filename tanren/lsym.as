; lsym.as - the link's symbols, all of them in one table.
;
; A record is seven bytes: the flags, the value, and a far pointer to
; the segment the value is measured in. THE VALUE IS ALREADY
; RELATIVE TO THE COMBINED SEGMENT - segment_by_index hands over the module's
;  base and symbols_add_public adds it - so the layout adds one address per
;  symbol
; and never looks at a module again.

LSYM_INCLUDED		equ	1	; skips the externals in lsym.inc

		public	symbols_init
		public	symbols_set_case
		public	symbols_add_public
		public	symbols_add_external
		public	symbols_relocate
		public	symbols_value
		public	symbols_check
		public	symbols_set_module
		public	symbols_dump
		public	public_segment_offset

		include	lsym.inc
		include	lseg.inc
					; segment_by_index,
					;   segments_set_case,
					;   print_record_name,
					;   name_record, and SEGMENT_BASE
		include	lobj.inc
					; objfile_string_buffer,
					;   objfile_string_length
		include	lerrs.inc
		include	hash.inc
		include	alloc.inc	; derefp
		include	farptr.inc
		include	msxdos.inc	; print_zero_string
		include	strutil.inc	; build_hex_word
		include	ascii.inc

		cseg

; symbols_init - the table, empty, in the default mode.
;
; Input:	nothing
; Output:	the table is ready
; Modifies:	AF, BC, DE, HL, IX

symbols_init:	ld	a,HT_CASE_FOLD
		call	symbols_init.case
		xor	a
		ld	(case_mode_known),a
		ret

;  symbols_init.case - the table's case mode, for symbols_set_case to set again
;  once it
;   knows. htinit only empties buckets, and nothing has been added.
;
; Input:	A = HT_CASE_SENSITIVE or HT_CASE_FOLD
; Output:	the table is empty and in that mode
; Modifies:	AF, BC, DE, HL, IX

symbols_init.case:
		ld	ix,symbol_table
		ld	b,SYMBOL_BUCKETS-1
		jp	htinit

; symbols_set_case - MODNAME's flags byte.
;
;   BIT 0 SAYS THE MODULE WAS ASSEMBLED /C. The first module decides
;   the whole link's mode - it is the only moment the tables can
;   still be re-formatted - and a later module that disagrees is
;   refused, because a mixed link resolves some symbols and silently
;   fails to resolve others.
;
; Input:	A = the flags byte from MODNAME
; Output:	the mode is set, or checked
;		(error_case_mismatch does not return)
; Modifies:	AF, BC, DE, HL, IX

symbols_set_case:
		and	1		; HT_CASE_SENSITIVE is 0 and
					;   HT_CASE_FOLD is 1, so
		xor	1		;   the flag and the mode are
		ld	c,a		;   opposites: /C means SENSITIVE
		ld	a,(case_mode_known)
		or	a
		jr	nz,symbols_set_case.compare
		ld	a,0ffh		; the first module: it decides
		ld	(case_mode_known),a
		ld	a,c
		ld	(case_mode),a
		push	bc
		call	segments_set_case	; all three tables, before
		pop	bc		;   any of them holds a record
		ld	a,c
		jp	symbols_init.case
symbols_set_case.compare:
		ld	a,(case_mode)
		cp	c
		ret	z
		jp	error_case_mismatch

; symbols_set_module - a module is starting: keep its name.
;
;   ONE NAME AT A TIME, not one per symbol. D4: a duplicate public
;   names the module it was found in, and that is this one. Sixteen
;   characters is enough for a filename's basename, which is what
;   MODNAME holds, and a longer one is cut rather than refused.
;
; Input:	objfile_string_buffer, objfile_string_length
; Output:	module_name, zero-terminated
; Modifies:	AF, BC, DE, HL

symbols_set_module:
		ld	a,(objfile_string_length)
		cp	MODULE_NAME_MAX
		jr	c,symbols_set_module.fits
		ld	a,MODULE_NAME_MAX-1
symbols_set_module.fits:
		ld	c,a
		ld	b,0
		ld	hl,objfile_string_buffer
		ld	de,module_name
		ldir
		xor	a
		ld	(de),a
		ret

;   symbols_find - the record for the name in objfile_string_buffer, made if it
;   is
;  new.
;
; Input:	objfile_string_buffer, objfile_string_length
; Output:	record_pointer = its payload far pointer
;		CY set = it was new, and its flags are zero
;		(error_out_of_memory does not return)
; Modifies:	AF, BC, DE, HL, IX

symbols_find:	ld	ix,symbol_table
		ld	de,objfile_string_buffer
		ld	a,(objfile_string_length)
		ld	hl,record_pointer
		call	htfind
		ret	nc
		ld	ix,symbol_table
		ld	de,objfile_string_buffer
		ld	a,(objfile_string_length)
		ld	bc,SYMBOL_RECORD_SIZE
		ld	hl,record_pointer
		call	htadd
		jp	c,error_out_of_memory
		derefp	record_pointer
		ld	(hl),0		; nothing is known about it yet
		scf
		ret

; symbols_add_public - a PUBDEF entry.
;
;   THE VALUE IS MADE SEGMENT-RELATIVE HERE, while the module's base
;   is still in hand. That is the whole reason the table keeps the
;   base beside the record.
;
; Input: public_segment_offset = segment index, offset; objfile_string_buffer =
; the name
; Output:	the symbol is defined (error_duplicate_public does not return)
; Modifies:	everything

symbols_add_public:
		ld	a,(public_segment_offset)
		cp	0ffh
		jr	z,symbols_add_public.absolute
		; -> segment_record, segment_module_base, and the offset
		;   within its module
		call	segment_by_index
		ld	hl,(public_segment_offset+1)
		ld	de,(segment_module_base)
		add	hl,de		; and now within the whole segment
		ld	(symbol_record+1),hl
		ld	hl,segment_record	; which segment that is
		ld	de,symbol_record+3
		ld	bc,4
		ldir
		ld	a,SYMBOL_DEFINED
		jr	symbols_add_public.flags
symbols_add_public.absolute:
					; an absolute public: the value is
		ld	hl,(public_segment_offset+1)
		ld	(symbol_record+1),hl	;   an address already
		ld	a,SYMBOL_DEFINED+SYMBOL_ABSOLUTE
symbols_add_public.flags:
		ld	(symbol_record),a

		call	symbols_find
		derefp	record_pointer
		ld	a,(hl)
		ld	(previous_flags),a	; what was known before
		and	SYMBOL_DEFINED
		jp	nz,symbols_add_public.duplicate
					; KEEP SYMBOL_REFERENCED if somebody
					; had
		ld	a,(previous_flags)
		ld	hl,symbol_record	;   already asked for this name
		or	(hl)
		ld	(hl),a
		derefp	record_pointer
		ex	de,hl
		ld	hl,symbol_record
		ld	bc,SYMBOL_RECORD_SIZE
		ldir
		ret

symbols_add_public.duplicate:
					; the name and the module, before
		ld	de,msg_duplicate_indent
		call	print_zero_string
					;   the error, because the message
					;   itself names neither.
		ld	de,objfile_string_buffer
		call	print_zero_string	; AND THE NAME IS ALREADY HERE,
					;   zero-terminated by
					;   objfile_read_string.
					;   symbols_print_name prints the
					;   record a WALK is standing on,
					;   and no walk is in
					;   progress - it printed 255 bytes
					;   of whatever walk held
		ld	de,msg_duplicate_tail
		call	print_zero_string
		ld	de,module_name
		call	print_zero_string
		ld	de,msg_newline
		call	print_zero_string
		jp	error_duplicate_public

; symbols_add_external - an EXTDEF entry.
;
;   It says only that somebody wants the name. Everything else about
;   a symbol belongs to whichever module defines it.
;
; Input:	objfile_string_buffer = the name
; Output:	SYMBOL_REFERENCED is set
; Modifies:	everything

symbols_add_external:
		call	symbols_find
		derefp	record_pointer
		ld	a,(hl)
		or	SYMBOL_REFERENCED
		ld	(hl),a
		ret

; symbols_value - the final value of the name in objfile_string_buffer.
;
;   PASS 2 CALLS IT ONCE PER EXTDEF, to build the map a RELOC's
;   external index points into. By then symbols_check has stopped the program
;   if anything was undefined and symbols_relocate has turned every value into
;   an address, so there is nothing to check and nothing to add.
;
;   If the name were somehow new, symbols_find would make a record and this
;   would answer zero. It cannot happen; answering zero rather than
;   reading an uninitialised payload is what makes that true instead
;   of nearly true.
;
; Input:	objfile_string_buffer, objfile_string_length
; Output:	HL = its value
; Modifies:	everything

symbols_value:
		call	symbols_find
		jr	c,symbols_value.new
		derefp	record_pointer
		inc	hl
		ld	c,(hl)		; IN BC: nothing else is free of
		inc	hl		;   the deref above
		ld	b,(hl)
		ld	h,b
		ld	l,c
		ret
symbols_value.new:
		ld	hl,0
		ret

; symbols_relocate - every symbol's value becomes an address.
;
;   AFTER place_segments, and only for symbols that are defined and not
;   absolute: an undefined symbol's segment pointer means nothing,
;   and an absolute one is an address already. SYMBOL_ABSOLUTE exists so
;   that this routine cannot forget.
;
; Input:	nothing (the table, and every segment placed)
; Output:	every defined value is final
; Modifies:	everything

symbols_relocate:
		call	symbols_first_bucket
symbols_relocate.loop:
		ld	ix,symbol_table
		ld	hl,symbol_walk
		call	htnext
		ret	c
		call	symbols_dump_flag
		ld	a,(record_flags)
		and	SYMBOL_DEFINED
		jr	z,symbols_relocate.loop	; nobody defined it
		ld	a,(record_flags)
		and	SYMBOL_ABSOLUTE
					; it is an address already
		jr	nz,symbols_relocate.loop
		call	symbols_payload		; HL -> its payload
		ld	de,3
		add	hl,de
					; its segment, out of the mapper
		ld	de,symbol_segment
		ld	bc,4
		ldir
		derefp	symbol_segment		; and that segment's base
		ld	de,SEGMENT_BASE
		add	hl,de
		ld	c,(hl)
		inc	hl
		ld	b,(hl)		; IN BC: the deref below destroys DE
		ld	hl,(record_value)
		add	hl,bc
		ld	(record_value),hl
		call	symbols_payload
		inc	hl
		ld	a,(record_value)
		ld	(hl),a
		inc	hl
		ld	a,(record_value+1)
		ld	(hl),a
		jp	symbols_relocate.loop

; symbols_payload - the payload of the record symbol_walk is on.
;
; Input:	symbol_walk is on a record
; Output:	HL -> the payload
; Modifies:	AF, BC, DE, HL

symbols_payload:
		derefp	symbol_walk+1
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)
		ld	c,a		; IN BC across the deref
		ld	b,0
		derefp	symbol_walk+1
		add	hl,bc
		ld	bc,HT_HEADER_SIZE
		add	hl,bc
		ret

; symbols_check - END OF PASS 1: every external nobody defined.
;
;   ALL OF THEM, and then the error. Every other error in both
;   programs stops at the first; this one does not, because a
;   fifty-module link missing three symbols would otherwise take
;   three runs to learn three names. The departure is deliberate.
;
; Input:	nothing
; Output:	nothing, or the names and error_undefined_symbols,
;		which does not return
; Modifies:	everything

symbols_check:
		xor	a
		ld	(undefined_count),a
		call	symbols_first_bucket
symbols_check.loop:
		ld	ix,symbol_table
		ld	hl,symbol_walk
		call	htnext
		jr	c,symbols_check.done
		call	symbols_dump_flag	; its flags, out of the mapper
		ld	a,(record_flags)
		and	SYMBOL_REFERENCED
		jr	z,symbols_check.loop
		ld	a,(record_flags)
		and	SYMBOL_DEFINED
		jr	nz,symbols_check.loop
					; the first one prints a heading
		ld	a,(undefined_count)
		or	a
		jr	nz,symbols_check.name
		ld	de,msg_never_defined
		call	print_zero_string
symbols_check.name:
		ld	de,msg_indent
		call	print_zero_string
		call	symbols_print_name
		ld	de,msg_newline
		call	print_zero_string
		ld	hl,undefined_count
		inc	(hl)
		jr	symbols_check.loop
symbols_check.done:
		ld	a,(undefined_count)
		or	a
		ret	z
		jp	error_undefined_symbols

; symbols_dump - /M: the symbols.
;
; Input:	nothing
; Output:	one line each
; Modifies:	everything

symbols_dump:	ld	de,msg_symbols
		call	print_zero_string
		call	symbols_first_bucket
symbols_dump.loop:
		ld	ix,symbol_table
		ld	hl,symbol_walk
		call	htnext
		ret	c
					; flags and value, into RAM first
		call	symbols_dump_flag
		ld	de,msg_indent
		call	print_zero_string
		ld	a,(record_flags)
		and	SYMBOL_DEFINED
		ld	de,msg_defined
		jr	nz,symbols_dump.defined
		ld	de,msg_absent
symbols_dump.defined:
		call	print_zero_string
		ld	a,(record_flags)
		and	SYMBOL_REFERENCED
		ld	de,msg_referenced
		jr	nz,symbols_dump.referenced
		ld	de,msg_absent
symbols_dump.referenced:
		call	print_zero_string
		ld	de,msg_space
		call	print_zero_string
					; NO VALUE FOR A SYMBOL NOBODY HAS
		ld	a,(record_flags)
		and	SYMBOL_DEFINED	;   DEFINED: the bytes in the record
		ld	de,msg_no_value	;   are whatever htadd left there,
					;   and printing them suggests they
		jr	z,symbols_dump.value
		ld	hl,(record_value)	;   mean something
		ld	de,hex_text
		call	build_hex_word
		ld	hl,hex_text+4
		ld	(hl),0
		ld	de,hex_text
symbols_dump.value:
		call	print_zero_string
		ld	de,msg_space
		call	print_zero_string
		call	symbols_print_name
		ld	de,msg_newline
		call	print_zero_string
		jp	symbols_dump.loop	; jp for the same reason

; symbols_dump_flag - the record symbol_walk is on: its flags and value,
;   in ordinary RAM before anything is printed. The page 2 rule, again.
;
; Input:	symbol_walk is on a record
; Output:	record_flags, record_value
; Modifies:	AF, BC, DE, HL

symbols_dump_flag:
		call	symbols_payload
		ld	a,(hl)
		ld	(record_flags),a
		inc	hl
		ld	a,(hl)
		ld	(record_value),a
		inc	hl
		ld	a,(hl)
		ld	(record_value+1),a
		ret

; symbols_print_name - this symbol's name, through lseg.as's printer.
;
;   A symbol's key is its name with nothing in front of it, so the
;   skip is zero.
;
; Input:	symbol_walk is on a record
; Output:	the name is printed
; Modifies:	everything

symbols_print_name:
		ld	hl,symbol_walk+1
		ld	de,name_record
		ld	bc,4
		ldir
		xor	a
		ld	(name_key_skip),a
		jp	print_record_name

symbols_first_bucket:
		xor	a
		ld	(symbol_walk),a
		ld	hl,NULL_OFFSET
		ld	(symbol_walk+3),hl
		ret

		dseg

symbol_table:	defs	2+SYMBOL_BUCKETS*4	; the descriptor: 258 bytes of
					;   ordinary RAM, records in the
					;   mapper
public_segment_offset:
		defs	3	; a PUBDEF's segment and offset
					; one record, built before it is stored
symbol_record:		defs	SYMBOL_RECORD_SIZE
previous_flags:
		defs	1	; the flags it had before
record_pointer:
		defs	4	; htfind and htadd's answer
symbol_walk:		defs	5	; a walk: the bucket, then htnext's
record_flags:
		defs	1	; one record, in ordinary RAM
record_value:
		defs	2
undefined_count:
		defs	1	; how many externals went undefined
case_mode_known:
		defs	1	; 0 until the first MODNAME has spoken
case_mode:
		defs	1	;   and then HT_CASE_SENSITIVE or HT_CASE_FOLD
hex_text:
		defs	5	; build_hex_word's answer, zero-terminated
symbol_segment:
					; symbols_relocate: the symbol's
					; segment, out of
		defs	4
				;   the mapper before it is dereffed
module_name:	defs	MODULE_NAME_MAX	; THE MODULE BEING READ, for the
				;   messages that name one

msg_symbols:	defb	"Symbols:",CHR_CR,CHR_LF,0
msg_indent:	defb	"  ",0
msg_defined:	defb	"D",0
msg_referenced:	defb	"R",0
msg_absent:	defb	"-",0
msg_space:	defb	" ",0
msg_newline:	defb	CHR_CR,CHR_LF,0
msg_never_defined:
		defb	"Never defined:",CHR_CR,CHR_LF,0
msg_no_value:	defb	"----",0
msg_duplicate_indent:
		defb	"  ",0
msg_duplicate_tail:
		defb	" is defined again in module ",0
