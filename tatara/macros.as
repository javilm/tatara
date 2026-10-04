; macros.as - macro definitions: collecting them and storing them.
;
; The body goes into mapper RAM: a name table
; record pointing at a descriptor, and a chain of 2048-byte blocks
; holding one record per body line. The text is stored EXACTLY as read -
; turning parameter references into markers is the next note's job.
;
; The discipline this file introduces, and never breaks:
;
;   an address from deref is valid only until the next deref, halloc,
;   hfree, ht* call, page2_restore, or BDOS call.
;
; So anything needed after one of those is copied into ordinary RAM
; first. dump_macro below is built entirely around that rule.
;
; collect_macro is not re-entrant, and does not need to be: a MACRO line inside
; a body is text during collection, and only becomes a definition when
; the outer macro is expanded, long after this has finished.


MACROS_INCLUDED	equ	1		; skips the external in macros.inc

		public	macro_table_init
		public	macro_table_reset
		public	find_macro
		public	collect_macro
		public	collect_block
		public	orphan_descriptor
		public	descriptor_name
		public	dump_macro
		public	list_macros

		include	macros.inc
		include	srcline.inc
		include	fields.inc
		include	dirtab.inc
		include	mdt.inc
		include	msxdos.inc
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been cleared
		include	hash.inc
		include	ascii.inc

SEMICOLON	equ	03bh		; ;
QUOTE1		equ	027h		; '
QUOTE2		equ	022h		; "
CHR_AMPERSAND	equ	026h		; &

		include	errs.inc
		include	strutil.inc
				; fold_to_upper: names fold before hashing
		include	cmdline.inc
				; opt_case: the case mode macro_table_init
					;   hashes in
		include	emit.inc
				; list_body_line, write_char, write_crlf: M80
					;   lists the lines a
					;   definition is made of, and this
					;   module is the only thing that
					;   sees them
		include	expand.inc
				; free_descriptor: free a descriptor and its
					;   body chain

		cseg

; macro_table_init - format the macro name table as empty.
;
;   ONCE PER RUN, beside symbol_table_init and heap_init - NOT per pass. dseg
;   space holds whatever MSX-DOS left in it, so the bucket array has to be
;   written before anything walks it, and macro_table_reset walks it. Emptying
;   the table between passes is macro_table_reset's job.
;
; Input:	nothing (heap_init and parse_command_line must have run)
; Output:	the table is empty
; Modifies:	AF, BC, DE, HL, IX

macro_table_init:
		ld	ix,macro_table
		ld	a,(opt_case)	; /C reaches macro names as well as
		ld	b,MACRO_BUCKET_MASK	; symbols: both are names the
		jp	htinit	; programmer invents, and find_macro runs
					; on the same text, on the same line,
					; as a symbol look-up

; macro_table_reset - free every macro definition and leave the table empty.
;
;   ONCE PER PASS. Pass 2 must start with the table exactly as pass 1
;   found it. Keeping pass 1's definitions was considered and refused:
;   a macro CALLED before it is DEFINED would be plain text on pass 1
;   and an expansion on pass 2, so the same line would be sized one way
;   and emitted another - a phase error one layer below where the phase
;   check can see it.
;
;   TWO SWEEPS, AND THE ORDER IS WHAT MAKES IT SAFE. The first frees
;   what each record's PAYLOAD points at - the descriptor and its body
;   chain, which free_descriptor does in one call - and leaves the records
;   themselves alone, so htnext's position stays valid. htclear then
;   frees the records in one go. Freeing a record during the walk would
;   pull the ground out from under the iterator.
;
;   THE PAGE 2 RULE: the payload is copied into ordinary RAM before
;   free_descriptor is called, because free_descriptor derefs and would take
;   the mapping away from under the record being read.
;
;   Calling it before pass 1 as well costs nothing - htnext on an empty
;   table returns at once, and htclear on one does nothing - and uniform
;   beats conditional.
;
; Input:	nothing (macro_table_init must have run)
; Output:	every descriptor and body block freed, the table empty
; Modifies:	AF, BC, DE, HL, IX

macro_table_reset:
		xor	a		; start a walk: bucket 0, and the
		ld	(free_walk),a	; iterator's offset field null
		ld	hl,NULL_OFFSET
		ld	(free_walk+3),hl

macro_table_reset.next_record:
		ld	ix,macro_table
		ld	hl,free_walk
		call	htnext
		jr	c,macro_table_reset.clear	; no more records

		derefp	free_walk+1	; HL -> this record, mapped
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(hl)		; HT_KEY_LENGTH
		inc	hl		; HL -> HT_KEY
		ld	e,a
		ld	d,0
		add	hl,de		; HL -> the payload, NAME_DESCRIPTOR
		fpsave	descriptor_to_free
				; into ordinary RAM: free_descriptor derefs

		ld	hl,descriptor_to_free
		call	free_descriptor
		jr	macro_table_reset.next_record

macro_table_reset.clear:
		ld	ix,macro_table
		jp	htclear		; and now the records themselves

; find_macro - is this operation the name of a macro?
;
;   The name table's payload is a far pointer to the descriptor, not the
;   descriptor itself - which is what lets a macro be redefined while it
;   is expanding without pulling the ground out from under the running
;   replay (mdt-design.md 5).
;
; Input:	DE -> the operation text, B = its length
;		HL -> a 4-byte buffer for the answer
; Output:	CY clear = it is a macro; the buffer holds the descriptor's
;		           far pointer
;		CY set   = it is not
; Modifies:	AF, BC, DE, HL, IX

find_macro:	ld	a,b
		or	a
		scf
		ret	z		; no operation on this line at all
		push	hl		; where the answer goes. The stack
		ld	ix,macro_table	; is the cheapest place to keep it:
		ld	hl,record_payload
					; htfind is the only thing in the way
		ld	a,b		; and it leaves the stack alone
		call	htfind		; CY set = not in the table
		jr	c,find_macro.not_found
		derefp	record_payload	; HL -> the payload, mapped
		pop	de
		ld	bc,4
		ldir			; out of the heap, into the caller's
		or	a		; buffer. Clear CY = found
		ret

find_macro.not_found:
		pop	hl		; pop does not touch the flags, so
		ret			; the CY htfind set is still there

; collect_block - collect an unnamed body, for REPT, IRP and IRPC.
;
;   The same collector collect_macro uses, with a different prologue: no name
;   is taken and no name table entry is made, so nothing can ever look this
;   body up. It is reachable only through the expansion record the driver is
;   about to push, and it is freed when that record is.
;
;   It ends by jumping into collect_macro's own loop, which is why
;   collect_block sits directly above it. Everything from
;   collect_macro.next_line down is shared.
;
; Input:	HL -> a line buffer to use, LINE_MAX+3 bytes
;		A   = MACRO_KIND for this block
;		IX -> the field block, with FIELD_OPERAND_LENGTH already
;		     cut short at
;		      the dummy's comma. Read only when the kind is not
;		      MACRO_IS_REPT - a REPT has no dummy
; Output:	the body is stored; HL -> the descriptor's far pointer
;		(errors do not return)
; Modifies:	AF, BC, DE, HL, IX

collect_block:	ld	(block_kind),a
		ld	(borrowed_buffer),hl
		ld	a,(current_file)
			; where this block opened, for error_macro_not_closed:
		ld	(body_file),a
			; collect_macro.next_line is shared, and it reports the
		ld	hl,(current_line)
					; line that opened the body, so a REPT
		ld	(body_line),hl
				; must fill these in exactly as MACRO does
		xor	a
		ld	(pool_names),a	; the name pool starts empty, exactly
		ld	(parameter_count),a
					; as it does for a named macro: a
		ld	(local_name_count),a
					; LOCAL line inside the body still
		ld	(pool_used),a	; works, and the dummy goes here
		ld	(body_line_stored),a
		ld	(macro_name_length),a	; no name at all

		ld	a,(block_kind)	; a REPT has no dummy; IRP and IRPC
		cp	MACRO_IS_REPT	; have exactly one, and the caller has
		jr	z,collect_block.no_dummy
					; already cut the operand short at its
		call	split_parameters
				; comma, so split_parameters reads one name and
		ld	a,(pool_names)	; stops
		ld	(parameter_count),a

collect_block.no_dummy:
		call	new_descriptor	; the descriptor

		derefp	descriptor_at	; mark what kind of block this is:
		ld	a,(block_kind)
				; free_expansion reads it to decide whether
		ld	(hl),a		; the body outlives the expansion

		ld	hl,1
		ld	(open_bodies),hl
					; the REPT line we were called for
		jp	collect_macro.next_line
					; and now it is an ordinary collection

; descriptor_name - what is this descriptor called?
;
;   The name table maps name -> descriptor. This is the other direction,
;   which hashing cannot answer: we hold a descriptor and want its name.
;   So it walks every record and compares payloads, and when one matches,
;   the name is in that same record - HT_KEY_LENGTH bytes at HT_KEY.
;
;   O(n) in a structure built to be O(1), which would be indefensible
;   anywhere else. It runs once, from die_with_message, with the program about
;   to terminate: the scan is over before the BDOS call that prints the line.
;   Storing the name in every descriptor instead would cost a far pointer and a
;   heap block per macro, carried all run, to make a once-per-run lookup fast.
;
;   Not found means the descriptor is anonymous (a REPT, IRP or IRPC
;   body, which never went in the table) or orphaned (redefined, so the
;   name now means something else). The caller says which,
;   from MACRO_KIND.
;
;   The name is copied into macro_name, which copy_macro_name uses while
;   collecting a definition. That is free here: nothing will read it again.
;
; Input:	HL -> a 4-byte far pointer to the descriptor
; Output:	CY clear = found; DE -> the name, zero-terminated, and
;		           macro_name_length is its length
;		CY set   = no name reaches this descriptor
;		(the name is built in macro_name, which copy_macro_name uses
;		while
;		 collecting - free here, since nothing reads it again)
; Modifies:	AF, BC, DE, HL, IX

descriptor_name:
		ld	de,wanted_descriptor
					; the descriptor we are looking for
		ld	bc,4
		ldir

		xor	a		; start a walk: bucket 0, and the
		ld	(name_walk),a	; iterator's offset field null
		ld	hl,NULL_OFFSET
		ld	(name_walk+3),hl

descriptor_name.next_record:
		ld	ix,macro_table
		ld	hl,name_walk
		call	htnext
		ret	c		; no more records: not found

		derefp	name_walk+1	; HL -> this record, mapped. Nothing
		ld	de,HT_KEY_LENGTH	; below derefs again, so it
		add	hl,de		; mapped to the end of the comparison
		ld	a,(hl)		; HT_KEY_LENGTH
		ld	(record_key_length),a
		inc	hl		; HL -> HT_KEY
		push	hl		; keep it: the name is here
		ld	e,a
		ld	d,0
		add	hl,de		; HL -> the payload, NAME_DESCRIPTOR
		ld	de,wanted_descriptor
					; the four bytes must match exactly
		ld	b,4
descriptor_name.compare:
		ld	a,(de)
		cp	(hl)
		jr	nz,descriptor_name.no_match
		inc	hl
		inc	de
		djnz	descriptor_name.compare

		pop	hl		; a match: HL -> the key
		ld	de,macro_name
		ld	a,(record_key_length)
		ld	(macro_name_length),a
		ld	c,a
		ld	b,0
		ldir
		ex	de,hl
		ld	(hl),0	; zero-terminated, for print_zero_string
		ld	de,macro_name
				; and hand it back, so that errs.as does
		or	a		; not have to know where it lives
		ret

descriptor_name.no_match:
		pop	hl
		jr	descriptor_name.next_record

; collect_macro - collect one macro definition and store it.
;
;   The MACRO line has already been read and split by the caller. Its
;   name and parameter list are copied out FIRST, because the field block
;   points into the line buffer that the first next_source_line below
;   overwrites.
;
; Input:	HL -> a line buffer to use, LINE_MAX+3 bytes
;		IX -> the field block describing the MACRO line
; Output:	CY clear = collected, and the ENDM consumed
;		(errors do not return)
; Modifies:	AB, BC, DE, HL, IX

collect_macro:	ld	(borrowed_buffer),hl	; the caller's buffer, borrowed
		ld	a,(current_file)
					; where this definition starts, for
		ld	(body_file),a
			; error_macro_not_closed: it fires at the end of the
		ld	hl,(current_line)
				; source, by which time current_line points
		ld	(body_line),hl	; at the last line of the file
		ld	hl,(borrowed_buffer)
		call	copy_macro_name	; the name, out of that bufefr
		xor	a
		ld	(pool_names),a	; the name pool starts empty. LOCAL
		ld	(parameter_count),a
					; lines add to this same pool later,
		ld	(local_name_count),a	; after the parameters
		ld	(pool_used),a
		ld	(body_line_stored),a
					; and no body line is stored yet
		call	split_parameters	; how many parameters
		ld	a,(pool_names)
		ld	(parameter_count),a
					; everything so far is a parameter
		call	new_descriptor	; the descriptor
		call	bind_macro_name	; the name table entry
		ld	hl,1
		ld	(open_bodies),hl
					; the MACRO line we were called for

collect_macro.next_line:
		ld	hl,(borrowed_buffer)
		call	next_source_line
					; CY set = the file ran out first
		ld	c,a
			; ITS LENGTH, before error_macro_not_closed's setup
					;   takes A. ld c,a leaves the flags
					;   alone, like the two lines below
		ld	a,(body_file)
			; the MACRO line, for error_macro_not_closed. Neither
		ld	hl,(body_line)	; of these touches the flags, so the CY
		jp	c,error_macro_not_closed
					; from next_source_line survives them
		ld	de,(borrowed_buffer)
					; M80 LISTS A DEFINITION'S LINES, and
		ld	a,c		;   this loop is the only thing that
		call	list_body_line
				;   sees them. Before prescan_line, because
					;   what gets stored is the prescanned
					;   form and the listing wants what the
					;   file said
		ld	hl,(borrowed_buffer)
		ld	ix,body_fields
				; next_source_line used IX for its own purposes
		call	split_line
		ld	de,(body_fields+FIELD_OPERATION)
		ld	a,(body_fields+FIELD_OPERATION_LENGTH)
		ld	b,a
		call	find_directive		; A = the directive number

		cp	DIRECTIVE_ENDM
		jr	z,collect_macro.endm
		cp	DIRECTIVE_LOCAL
		jr	z,collect_macro.local_line

		call	collect_macro.opens_body
					; does this line open another body?
		jr	nz,collect_macro.store	; no: it is just text
		ld	hl,(open_bodies)
		inc	hl		; yes: one level deeper
		ld	(open_bodies),hl

collect_macro.store:
		ld	a,1
		ld	(body_line_stored),a
					; from here on a LOCAL line is late
		ld	hl,(borrowed_buffer)
					; prescan the line, then store what
		call	prescan_line	; the prescan produced - not the
		ld	hl,scanned_line	; line as it was read
		ld	a,(scanned_length)
		call	append_body_line
		jp	collect_macro.next_line

collect_macro.endm:
		ld	hl,(open_bodies)
		dec	hl
		ld	(open_bodies),hl
		ld	a,h
		or	l
		jr	z,collect_macro.done
		jr	collect_macro.store
					; a nested ENDM: body text, store it

collect_macro.done:
		call	store_local_count
				; MACRO_LOCAL_COUNT, now that no more LOCAL
		ld	a,(body_file)	; lines can arrive.
		ld	(current_file),a
				; Put the position back to the line that
		ld	hl,(body_line)	; OPENED the body. Collecting it moved
		ld	(current_line),hl
				; current_line to the ENDM, and expand_start
				; reads
					; current_file/current_line as the call
					; site - so a REPT would name its ENDM
					; instead of its REPT line, off by the
					; length of the body. The next
					; next_source_line overwrites both
					; anyway, so it costs a named macro
					; nothing
		ld	hl,descriptor_at
				; HL -> the descriptor, for collect_block's
		or	a	; caller; collect_macro's caller ignores it.
		ret			; or a clears CY = collected

; A LOCAL line is ours only while we are collecting our OWN body. At depth
; two or more it belongs to the macro being defined inside ours, and is
; stored as text like everything else there.

collect_macro.local_line:
		ld	hl,(open_bodies)
		dec	hl
		ld	a,h
		or	l
		jp	nz,collect_macro.store	; not ours: body text
		call	add_local_names
		jp	collect_macro.next_line	; ours: the line is consumed

; collect_macro.opens_body - does this directive open a body that needs its own
; ENDM?
;
; Input:	A = directive number
; Output:	Z set = yes, it opens a body
; Modifies:	F

collect_macro.opens_body:
		cp	DIRECTIVE_MACRO
		ret	z
		cp	DIRECTIVE_REPT
		ret	z
		cp	DIRECTIVE_IRP
		ret	z
		cp	DIRECTIVE_IRPC
		ret

; copy_macro_name - copy the macro's name out of the line bufefr
;
;   The name is the label field of the MACRO line, and that field points
;   into the buffer collect_macro is about to reuse. A zero terminator is added
;   so the dump can print it with print_zero_string; the length is kept
;   separately because htadd and htfind want it in A.
;
; Input:	IX -> the MACRO line's field block
; Output:	macro_name holds the name, macro_name_length its length
; Modifies:	AF, BC, DE, HL

copy_macro_name:
		ld	a,(ix+FIELD_LABEL_LENGTH)
		or	a
		jp	z,error_macro_no_name	; nothing in the label field
		; MACRO_NAME_MAX characters is legal: macro_name
		cp	MACRO_NAME_MAX+1
		; is MACRO_NAME_MAX+1 bytes, the name and its terminator.
		;   symtab.as spells this test the same way for
		;   SEGMENT_NAME_MAX, and this one said cp MACRO_NAME_MAX until
		;   105 - so 64 was refused by a limit that is 64
		jp	nc,error_macro_name_long
		ld	(macro_name_length),a
		ld	c,a
		ld	b,0
		ld	l,(ix+FIELD_LABEL)
		ld	h,(ix+FIELD_LABEL+1)
		ld	de,macro_name
		ldir
		xor	a
		ld	(de),a		; terminate it, for printing
		ret

; split_parameters - split the MACRO line/s operand into the parameter
;   names, and keep them in ordinary RAM for the prescan.
;
;   Stored one after another as a length byte and that many characters,
;   with parameter_count counting them. They live only while this definition is
;   being collected - nothing above needs them afterwards.
;
;   Called twice: once for the MACRO line's parameters, and again for each
;   LOCAL line. It appends; clearing the pool is collect_macro's job.
;
; Input:	IX -> the MACRO line's field block
; Output:	parameter_count, name_pool
; Modifies:	AF, BC, DE, HL

split_parameters:
		ld	a,(ix+FIELD_OPERAND_LENGTH)
		or	a
		ret	z		; no parameters at all
		ld	c,a		; C = characters left in the operand
		ld	l,(ix+FIELD_OPERAND)
		ld	h,(ix+FIELD_OPERAND+1)
		ld	de,name_pool	; DE -> where the next name goes. It
		ld	a,(pool_used)	; APPENDS: a LOCAL line's names land
		add	a,e		; after the parameters already in the
		ld	e,a	; pool, and pool_used is exactly how many
		ld	a,0		; bytes those took
		adc	a,d
		ld	d,a

split_parameters.next_name:
		call	skip_operand_blanks	; step over spaces and tabs
		ld	a,c
		or	a
		ret	z		; nothing but blanks left
		call	reserve_pool_byte	; room for the length byte?
		ld	(pool_length_at),de
					; where it goes, once we know it
		inc	de
		ld	b,0		; B = characters in this name

split_parameters.name_char:
		ld	a,c
		or	a
		jr	z,split_parameters.name_end	; the operand ran out
		ld	a,(hl)
		cp	","
		jr	z,split_parameters.name_end
		call	is_blank
		jr	z,split_parameters.name_end
		call	reserve_pool_byte	; room for one more character?
		ld	a,(hl)
		ld	(de),a
		inc	de
		inc	hl
		dec	c
		inc	b
		jr	split_parameters.name_char

split_parameters.name_end:
		push	hl		; fill in the length byte
		ld	hl,(pool_length_at)
		ld	(hl),b
		pop	hl
		ld	a,b
		or	a
		jp	z,error_bad_parameter_list
					; an empty name, as in "addr,,val"

		ld	a,(pool_names)
		inc	a
		cp	PARM_MAX+1
		jp	nc,error_too_many_parameters	; too many parameters
		ld	(pool_names),a

		call	skip_operand_blanks	; is another one coming?
		ld	a,c
		or	a
		ret	z		; the operand is finished
		ld	a,(hl)
		cp	","
		ret	nz		; something unexpected: stop here
		inc	hl
		dec	c
		jp	split_parameters.next_name

; add_local_names - a LOCAL line: add its names to the pool the parameters are
;   already in.
;
;   It calls split_parameters, which is the same job: split an operand at
;   commas into length-prefixed names and append them. split_parameters no
;   longer clears the pool - collect_macro does that once - which is what makes
;   calling it a second time safe.
;
; Input:	body_fields describes the LOCAL line
; Output:	the names are in the pool, local_name_count = how many
;		(a LOCAL after body lines does not return -
;		error_local_too_late stops)
; Modifies:	AF, BC, DE, HL, IX

add_local_names:
		ld	a,(body_line_stored)
		or	a
		jp	nz,error_local_too_late
					; body lines are already stored: the
					; name would be a marker on some and
					; plain text on others
		ld	ix,body_fields
		call	split_parameters
		ld	a,(pool_names)
				; whatever split_parameters just added to the
		ld	hl,parameter_count	; pool is a LOCAL
		sub	(hl)
		ld	(local_name_count),a
		ret

; store_local_count - write the LOCAL count into the descriptor.
;
;   Not done when the descriptor is created: at that moment the LOCAL
;   lines have not been read yet. Done once, when the body is closed.
;
; Input:	descriptor_at, local_name_count
; Output:	MACRO_LOCAL_COUNT is set
; Modifies:	AF, BC, DE, HL

store_local_count:
		derefp	descriptor_at
		ld	de,MACRO_LOCAL_COUNT
		add	hl,de
		ld	a,(local_name_count)
		ld	(hl),a
		ret

; reserve_pool_byte - is there romo for one more byte in the name pool?
;
;   Counting the bytes is simpler than comparing pointers, and it does
;   not care where name_pool happens to sit in memory.
;
; Input:	nothing
; Output:	the pool has one more byte in it
;		(a full pool does not return - error_too_many_parameters stops)
; Modifies:	AF

reserve_pool_byte:
		ld	a,(pool_used)
		inc	a
		cp	PARM_NAMES_SIZE+1
		jp	nc,error_too_many_parameters
		ld	(pool_used),a
		ret

; skip_operand_blanks - step HL over spaces and tabs, counting them off C.
;
; Input:	HL -> somewhere in the operand
;		C   = characters left
; Output:	HL, C past any run of spaces and tabs
; Modifies:	AF, C, HL

skip_operand_blanks:
		ld	a,c
		or	a
		ret	z
		ld	a,(hl)
		call	is_blank
		ret	nz
		inc	hl
		dec	c
		jr	skip_operand_blanks

; is_blank - is the character in A a space or a tab?
;
; Input:	A = character
; Output:	Z set = yes
; Modifies:	F only

is_blank:	cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret

; prescan_line - prescan one body line: every reference to a parameter
;   becomes a two-byte marker, so that replaying the line never has to
;   compare a name against anything.
;
;   Three pieces of state, all in ordinary RAM because this routine is
;   long enough that keeping them in registers would be a puzzle:
;
;     open_quote   which quote character we are inside, 0 = none
;     force_next  the last character was "&", so the next identifier is
;              substituted even inside a string
;     scanned_length   how much has been produced so far
;
; Input:	HL -> the line, zero-terminated
; Output:	scanned_line = the prescanned line, zero-terminated
;		scanned_length  = its length
; Modifies:	AF, BC, DE, HL

prescan_line:	ld	de,scanned_line	; DE = where the next byte goes
		xor	a
		ld	(scanned_length),a
		ld	(open_quote),a	; not inside a string
		ld	(force_next),a	; no "&" seen

prescan_line.next_char:
		ld	a,(hl)
		or	a
		jp	z,prescan_line.done	; the line is finished

		cp	CHR_AMPERSAND
		jp	z,prescan_line.ampersand

		ld	a,(open_quote)
		or	a
		jp	nz,prescan_line.in_string
					; inside a string: different rules

; --- outside a string

		ld	a,(hl)
		cp	SEMICOLON
		jp	z,prescan_line.comment
		cp	QUOTE1
		jr	z,prescan_line.open_quote
		cp	QUOTE2
		jr	z,prescan_line.open_quote
		call	starts_identifier	; does it start an identifier?
		jp	z,prescan_line.identifier
		jp	prescan_line.store_char

prescan_line.open_quote:
		ld	(open_quote),a	; remember which quote opened it
		jp	prescan_line.store_char

; --- the "&" is a concatenation operator: it is consumed, never stored,
;     and it forces the next identifier to be substituted even inside a
;     string.

;     One "&" is spent per expansion level: a single one is consumed here
;     and forces the next identifier, while "&&" stores ONE of them as
;     ordinary text for the next level in to spend.
;
;     The manual describes only the single-level case and never mentions
;     "&&" at all (books/m80l80.txt 2.7.9), so this follows the MASM
;     family. It is strictly additive: "&" behaves exactly as it did, and
;     "&&" previously did nothing useful.
;
;     Note which case needs which. A nested definition whose LABEL is
;     built from the OUTER macro's parameter wants a single "&" -
;     "poke&sfx macro addr" - because that concatenation happens at the
;     outer level. "&&" is only for concatenation against the INNER
;     macro's own parameters.

prescan_line.ampersand:
		inc	hl		; the "&" is consumed either way
		ld	a,(hl)
		cp	CHR_AMPERSAND
		jr	z,prescan_line.double_ampersand
		ld	a,1		; a single "&": force the next
		ld	(force_next),a	; identifier, even inside a string
		jp	prescan_line.next_char

prescan_line.double_ampersand:
		inc	hl		; "&&": one of them survives into the
		ld	a,CHR_AMPERSAND
				; stored line as data. force_next is NOT
		call	scan_put_char	; set - this "&" is not spent here
		jp	prescan_line.next_char

; --- inside a string. Only the matching quote closes it, and only an
;     "&"-marked reference is substituted (the M80 rule).

prescan_line.in_string:
		ld	b,a		; B = the quote we are inside
		ld	a,(hl)
		cp	b
		jr	nz,prescan_line.in_string_char
		xor	a
		ld	(open_quote),a	; the string closes here
		jp	prescan_line.store_char
prescan_line.in_string_char:
		ld	a,(force_next)
		or	a
		jp	z,prescan_line.store_char
					; not forced: literal text
		ld	a,(hl)
		call	starts_identifier
		jp	z,prescan_line.identifier
		jp	prescan_line.store_char

; --- an identifier. It is copied into the output FIRST and looked up
;     there; if it turns out to be a parameter, the output is wound back
;     over it and the marker written instead. The saves a buffer to
;     collect it in, and costs nothing in the common case.

prescan_line.identifier:
		xor	a
		ld	(force_next),a	; the force applies to this one only
		ld	(identifier_at),de
					; where the name begins in the output
		ld	b,0		; B = how long it is
prescan_line.identifier_char:
		ld	a,(hl)
		call	is_identifier_char
		jr	nz,prescan_line.identifier_end
		call	scan_put_char
		inc	hl
		inc	b
		jr	prescan_line.identifier_char

prescan_line.identifier_end:
		ld	a,(hl)		; an "&" right after also ends the
		cp	CHR_AMPERSAND	; identifier, and is consumed
		jr	nz,prescan_line.identifier_look_up
		inc	hl
		ld	a,(hl)		; ...unless it is "&&", which is left
		cp	CHR_AMPERSAND
			; whole for prescan_line.ampersand. It must not be
		jr	nz,prescan_line.identifier_look_up
				; stored here: find_pool_name below may wind
		dec	hl		; the output back over this name, and
					; anything written first would go with
					; it. Putting HL back on the first "&"
					; defers the pair until after the
					; lookup has resolved

prescan_line.identifier_look_up:
		push	hl
		push	de	; find_pool_name walks the table with DE,
		ld	hl,(identifier_at)	; which is our output pointer
		call	find_pool_name	; CY set = not a parameter
		pop	de
		pop	hl
		jp	c,prescan_line.next_char
					; not one: it is already copied

		ld	c,a		; C = its index in the combined list
		ld	de,(identifier_at)
					; wind the output back over the name
		ld	a,(scanned_length)
		sub	b
		ld	(scanned_length),a

		ld	a,(parameter_count)
				; below parameter_count it is a parameter; at
		ld	b,a		; or above it, a LOCAL, renumbered
		ld	a,c		; from zero
		cp	b
		jr	c,prescan_line.parameter_mark
		sub	b
		ld	c,a
		ld	a,MARK_LOCAL
		jr	prescan_line.write_mark
prescan_line.parameter_mark:
		ld	a,MARK_PARAMETER
prescan_line.write_mark:
		call	scan_put_char
		ld	a,c
		call	scan_put_char
		jp	prescan_line.next_char

; --- a comment, outside a string. ";;" is definition-time commentary
;     and is dropped; ";" is stored so the listing can show it. Nothing
;     after either is prescanned.

prescan_line.comment:
		inc	hl
		ld	a,(hl)
		cp	SEMICOLON
		jr	z,prescan_line.done
					; ";;" - the rest of the line goes
		dec	hl
prescan_line.copy_rest:
		ld	a,(hl)
		or	a
		jr	z,prescan_line.done
		call	scan_put_char
		inc	hl
		jr	prescan_line.copy_rest

; --- store the character at (HL) and step over it

prescan_line.store_char:
		xor	a
		ld	(force_next),a	; an "&" only reaches the next thing
		ld	a,(hl)
		call	scan_put_char
		inc	hl
		jp	prescan_line.next_char

prescan_line.done:
		xor	a
		ld	(de),a		; terminate the prescanned line
		ret

; scan_put_char - add the character in A to the prescanned line.
;
;   Two bytes can replace a one-character name, so the line may grow;
;   the length is checked before every byte rather than afterwards.
;
; Input:	A   = the character
;		DE -> where it goes
; Output:	stored, DE and scanned_length advanced
;		(a line that grew too long does not return -
;		error_macro_line_long stops)
; Modifies:	AF, DE

scan_put_char:	push	af
		ld	a,(scanned_length)
		cp	LINE_MAX
		jp	nc,error_macro_line_long
		inc	a
		ld	(scanned_length),a
		pop	af
		ld	(de),a
		inc	de
		ret

; find_pool_name - is this identifier one of the names?
;
;   COMPARED IGNORING CASE, AND M80 WAS ASKED: PCASE.AS declares the
;   dummy as "Xx", writes "db XX" in the body, and M80 assembles 07 with
;   no error. So this is right, and it stays right in both modes - a
;   dummy parameter is a NAME.
;
;   "Like every other name M80 matches" is what this comment used to
;   say, and /C made that false: symbols, macro names, segment and group
;   names follow the command line, while these and the directive,
;   mnemonic and register tables do not (R2). The distinction that
;   survives is names against text - see args_are_same in cond.as, which
;   compares text and was folding it until 089.
;
;   The index is "how many parameters there are" minus "how many are left
;   to try", so no separate counter is carried round the loop.
;
; Input:	HL -> the identifier
; 		B   = its length
; Output:	CY clear = yes, A = its index in the combined list
;		CY set   = no
; Modifies:	AF, C, DE

find_pool_name:	ld	a,(pool_names)
		or	a
		scf
		ret	z		; no parameters at all
		ld	c,a		; C = names left to try
		ld	de,name_pool	; DE -> the entry being tried

find_pool_name.next_name:
		ld	a,(de)		; its length
		cp	b
		jr	nz,find_pool_name.next_entry
					; different length: cannot match

		push	hl
		push	de
		push	bc
		ld	c,b		; C = characters to compare
		inc	de		; DE -> the name itself
find_pool_name.compare_char:
		ld	a,(de)
		call	fold_to_upper
		ld	b,a
		ld	a,(hl)
		call	fold_to_upper
		cp	b
		jr	nz,find_pool_name.no_match
		inc	hl
		inc	de
		dec	c
		jr	nz,find_pool_name.compare_char

		pop	bc		; matched. B = length, C = names left
		pop	de
		pop	hl
		ld	a,(pool_names)
		sub	c	; pool_names >= c, so this clears CY too
		ret

find_pool_name.no_match:
		pop	bc
		pop	de
		pop	hl
find_pool_name.next_entry:
		ld	a,(de)		; step over this entry: the length
		add	a,1		; byte and the name
		add	a,e
		ld	e,a
		jr	nc,find_pool_name.step
		inc	d
find_pool_name.step:
		dec	c
		jr	nz,find_pool_name.next_name
		scf			; every name tried: not a parameter
		ret

; is_identifier_char - may this character appear in an identifier?
; starts_identifier - may it START one? The same set, without the digits.
;
;   M80's set is the letters, the digits, and ? @ . _ $
;
; Input:	A = character
; Output:	Z set = yes
; Modifies:	F only

is_identifier_char:
		cp	"0"
		jr	c,starts_identifier
					; below "0": try the rest of the set
		cp	"9"+1
		jr	c,identifier_yes	; a digit
starts_identifier:
		cp	"A"
		jr	c,starts_identifier.punctuation
		cp	"Z"+1
		jr	c,identifier_yes
		cp	"a"
		jr	c,starts_identifier.punctuation
		cp	"z"+1
		jr	c,identifier_yes
starts_identifier.punctuation:
		cp	"?"
		ret	z
		cp	"@"
		ret	z
		cp	"."
		ret	z
		cp	"_"
		ret	z
		cp	"$"
		ret
identifier_yes:	cp	a		; whatever A holds, this sets Z
		ret


; new_descriptor - allocate the descriptor and fill in what is known now.
;
;   The three far pointers in it start null - which is offset FFFFh, not
;   four zero bytes: zeros would be a perfectly good pointer to segment
;   0, and would be followed.
;
; Input: parameter_count, and the current origin in current_file/current_line
; Output:	descriptor_at holds the descriptor far pointer
; Modifies:	AF, BC, DE, HL

new_descriptor:	ld	bc,MACRO_DESCRIPTOR_SIZE
		ld	hl,descriptor_at
		call	halloc
		jp	c,error_out_of_memory
		derefp	descriptor_at	; HL -> the descriptor, mapped
		ld	(hl),MACRO_IS_MACRO	; MACRO_KIND
		inc	hl
		ld	(hl),0		; MACRO_FLAGS
		inc	hl
		ld	a,(parameter_count)
		ld	(hl),a		; MACRO_PARM_COUNT
		inc	hl
		ld	(hl),0		; MACRO_LOCAL_COUNT
		inc	hl
		ld	(hl),0		; MACRO_USES
		inc	hl
		ld	a,(current_file)
		ld	(hl),a		; MACRO_DEF_FILE
		inc	hl
		ld	de,(current_line)
		ld	(hl),e		; MACRO_DEF_LINE
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),0		; MACRO_LINE_COUNT
		inc	hl
		ld	(hl),0
		inc	hl
		; MACRO_BODY, MACRO_LAST_BLOCK and MACRO_PARM_NAMES,
		ld	b,12
		ld	a,0ffh		; all null
new_descriptor.null_pointers:
		ld	(hl),a
		inc	hl
		djnz	new_descriptor.null_pointers

		ld	hl,last_block	; no body block yet
		ld	b,4
		ld	a,0ffh
new_descriptor.null_last:
		ld	(hl),a
		inc	hl
		djnz	new_descriptor.null_last
		; "the block is full", so the first
		ld	hl,BODY_BLOCK_SIZE
		ld	(block_used),hl	; line stored allocates one
		ret

; bind_macro_name - make the name table point at this descriptor.
;
;   A redefinition overwrites the four-byte pointer in the record that is
;   already there, and walks away from the old descriptor and its body.
;   That is correct - the new definition wins from the next invocation -
;   but it LEAKS. Freeing the old one safely needs hte use count, because
;   an expansion may be reading the old body at this very moment; that is
;
; Input:	macro_name/macro_name_length, descriptor_at
; Output:	the table points at descriptor_at
; Modifies:	AF, BC, DE, HL, IX

bind_macro_name:
		ld	ix,macro_table
		ld	de,macro_name
		ld	a,(macro_name_length)
		ld	hl,record_payload
		call	htfind		; CY set = this name is new
		jr	c,bind_macro_name.add

		derefp	record_payload	; a redefinition. Keep the OLD
		fpsave	old_descriptor	; descriptor's pointer BEFORE the new
					; one goes over it: the payload is four
					; bytes and that write is what destroys
					; the only reference to it. These two
					; steps cannot be reordered
		call	bind_macro_name.store
					; the name now means the new one
		jp	orphan_descriptor
					; and the old one is nobody's by name

bind_macro_name.add:
		ld	de,macro_name	; htfind clobbered DE and A
		ld	a,(macro_name_length)
		ld	bc,NAME_ENTRY_SIZE
		ld	hl,record_payload
		call	htadd
		jp	c,error_out_of_memory

bind_macro_name.store:
		derefp	record_payload	; HL -> the payload, mapped
		ex	de,hl		; DE -> where the pointer goes
		ld	hl,descriptor_at	; from ordinary RAM
		ld	bc,4
		ldir
		ret

; orphan_descriptor - the descriptor in old_descriptor is no longer reachable
; by name.
;
;   Half of the freeing rule; the other half is in free_expansion (expand.as).
;   A descriptor goes back to the heap when nothing is reading it AND
;   nothing can reach it by name, and whichever of those two becomes true
;   second is what frees it. This is the "by name" side.
;
;   The common case is that MACRO_USES is 0 and it is freed right here. The
;   interesting case is a macro that redefines itself from inside its own
;   body: the count is at least 1, this returns having done nothing but
;   set a bit, and the replay carries on reading a body that no name
;   points at any more (mdt-design.md 5).
;
; Input:	old_descriptor = the displaced descriptor's far pointer
; Output:	MACRO_ORPHANED set, and freed if nothing is reading it
; Modifies:	AF, BC, DE, HL

orphan_descriptor:
		derefp	old_descriptor
		ld	de,MACRO_FLAGS
		add	hl,de
		set	0,(hl)	; MACRO_ORPHANED - no name reaches it now
		ld	de,MACRO_USES-MACRO_FLAGS
		add	hl,de
		ld	a,(hl)
		or	a
		ret	nz		; an expansion is still reading it.
					; Its free_expansion will free it

		ld	hl,old_descriptor	; nothing is: it goes now
		jp	free_descriptor

; append_body_line - append one body line to the block chain.
;
; Input:	HL -> the text
;		A   = its length
;		current_line = the line it came from
; Output:	the record is stored, MACRO_LINE_COUNT incremented
; Modifies:	AF, BC, DE, HL

append_body_line:
		ld	(line_text_at),hl
		ld	(line_text_length),a

		ld	hl,(block_used)	; would the record run past the end?
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,LINE_HEADER_SIZE
		add	hl,de
		ld	de,BODY_BLOCK_SIZE
		or	a
		sbc	hl,de
		jr	c,append_body_line.fits	; it ends before the block does
		call	new_body_block	; no room: chain a new block on

append_body_line.fits:
		derefp	last_block	; HL -> the block, mapped
		ld	de,(block_used)
		add	hl,de		; HL -> where this record goes
		ld	a,(line_text_length)
		ld	(hl),a		; LINE_LENGTH
		inc	hl
		ld	de,(current_line)
		ld	(hl),e		; LINE_NUMBER
		inc	hl
		ld	(hl),d
		inc	hl		; HL -> LINE_TEXT
		ex	de,hl		; DE -> its place in the block
		ld	a,(line_text_length)
		or	a
		jr	z,append_body_line.no_text
					; an empty line stores no text
		ld	c,a
		ld	b,0
		ld	hl,(line_text_at)
		ldir

		; used = used + LINE_HEADER_SIZE + length
append_body_line.no_text:
		ld	hl,(block_used)
		ld	a,(line_text_length)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,LINE_HEADER_SIZE
		add	hl,de
		ld	(block_used),hl

		derefp	last_block	; write it into the block as well
		ld	de,(block_used)	; deref clobbers DE, so the value is
		ld	bc,BODY_USED	; fetched AFTER it, not befrore
		add	hl,bc
		ld	(hl),e
		inc	hl
		ld	(hl),d

		derefp	descriptor_at	; add one more body line
		ld	de,MACRO_LINE_COUNT
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	de
		ld	(hl),d
		dec	hl
		ld	(hl),e
		ret

; new_body_block - allocate a body block and chain it on the end.
;
; Input:	descriptor_at, last_block (null if this is the first block)
; Output:	last_block points at the new block, block_used = BODY_DATA
; Modifies:	AF, BC, DE, HL

new_body_block:	ld	bc,BODY_BLOCK_SIZE
		ld	hl,body_block_at
		call	halloc
		jp	c,error_out_of_memory

		derefp	body_block_at	; the new block: no next, empty
		ld	b,4
		ld	a,0ffh
new_body_block.null_next:
		ld	(hl),a
		inc	hl
		djnz	new_body_block.null_next
		ld	de,BODY_DATA
		ld	(hl),e		; BODY_USED = BODY_DATA
		inc	hl
		ld	(hl),d

		fpnull	last_block
		jr	z,new_body_block.first

		derefp	last_block	; HL -> the old last block, whose
		ex	de,hl		; BODY_NEXT is at offset 0
		ld	hl,body_block_at
		ld	bc,4
		ldir
		jr	new_body_block.set_last

new_body_block.first:
		derefp	descriptor_at	; the first block goes in MACRO_BODY
		ld	de,MACRO_BODY
		add	hl,de
		ex	de,hl
		ld	hl,body_block_at
		ld	bc,4
		ldir

new_body_block.set_last:
		fpcopy	last_block,body_block_at
		ld	hl,BODY_DATA
		ld	(block_used),hl
		ret

; dump_macro - read the definition just stored back out and print it.
;
;   Called by the main program when /M was given. It lives here because
;   it knows the shape of the tables, but WHEN to call it is the main
;   program's business - this module has no reason to know what letters
;   were on the command line.
;
;   Only valid immediately after collect_macro returns: it reads the collection
;   variables, which the next definition overwrites.
;
;   This is the shape the replay engine has, so it is
;   worth reading closely. The block is mapped again on EVERY trip round
;   the inner loop, because printing class BDOS, and BDOS takes page 2
;   back. Each record is copied into ordinary RAM before a single
;   character of it is printed.
;
;   The dump goes to the screen, never to the output file: it is a
;   diagnostic, not translated source.
;
; Input: descriptor_at, macro_name, and the borrowed line buffer in
; borrowed_buffer
; Output:	the definition in printed
; Modified:	AF, BC, DE, HL

;   Everything wanted from the descriptor is read out first, in one
;   mapping, and only then printed. That is the pattern, not an
;   optimisation: the first _STROUT below would take page 2 away.

; list_macros - every macro's name, sixteen columns each, one to a line,
;   for the listing's last page. M80 lists the names there and nothing
;   else - the bodies are /M's business.
;
;   macro_table_reset's walk, without the freeing.
;
; Input:	nothing
; Output:	the names are written
; Modifies:	AF, BC, DE, HL, IX

list_macros:	xor	a
		ld	(list_walk),a
		ld	hl,NULL_OFFSET
		ld	(list_walk+3),hl
list_macros.next_record:
		ld	ix,macro_table
		ld	hl,list_walk
		call	htnext
		ret	c
		ld	c,0
list_macros.name_char:
		derefp	list_walk+1	; the record again: a name lives in
		ld	de,HT_KEY_LENGTH	;   the mapper and every write
		add	hl,de		;   page 2 away
		ld	a,(hl)
		inc	hl
		ld	b,a
		ld	a,c
		cp	b
		jr	nc,list_macros.line_end
		ld	e,c
		ld	d,0
		add	hl,de
		ld	a,(hl)
		push	bc
		call	write_char
		pop	bc
		inc	c
		jr	list_macros.name_char
list_macros.line_end:
		call	write_crlf
		jr	list_macros.next_record

dump_macro:	derefp	descriptor_at
		ld	de,MACRO_LOCAL_COUNT
		add	hl,de
		ld	a,(hl)		; MACRO_LOCAL_COUNT
		ld	(dump_local_count),a
		inc	hl		; over MACRO_USES
		inc	hl
		ld	a,(hl)		; MACRO_DEF_FILE
		ld	(dump_file),a
		inc	hl
		ld	e,(hl)		; MACRO_DEF_LINE
		inc	hl
		ld	d,(hl)
		ld	(dump_origin),de
		inc	hl
		ld	e,(hl)		; MACRO_LINE_COUNT
		inc	hl
		ld	d,(hl)
		ld	(dump_line_count),de
		inc	hl		; HL -> MACRO_BODY
		fpsave	dump_block	; the first block, into ordinary RAM

		ld	de,msg_macro
		call	print_dollar_string
		ld	de,macro_name
		call	print_zero_string
		ld	de,msg_colon
		call	print_dollar_string
		ld	a,(parameter_count)
		ld	l,a
		ld	h,0
		call	print_decimal
		ld	de,msg_parameters
		call	print_dollar_string
		ld	a,(dump_local_count)
		ld	l,a
		ld	h,0
		call	print_decimal
		ld	de,msg_locals
		call	print_dollar_string
		ld	hl,(dump_line_count)
		call	print_decimal
		ld	de,msg_lines
		call	print_dollar_string
		ld	a,(dump_file)
		call	get_filename
		call	print_zero_string_upper	; a filename: upper case
		ld	de,msg_open_bracket
		call	print_dollar_string
		ld	hl,(dump_origin)
		call	print_decimal
		ld	de,msg_close_bracket_eol
		call	print_dollar_string

dump_macro.block:
		fpnull	dump_block
		ret	z		; no more blocks: done
		derefp	dump_block
		ld	de,BODY_USED
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(dump_block_end),de	; how far this block is filled
		ld	hl,BODY_DATA
		ld	(dump_offset),hl

dump_macro.record:
		ld	hl,(dump_offset)
		ld	de,(dump_block_end)
		or	a
		sbc	hl,de
		jr	nc,dump_macro.next_block
					; this block is finished
		call	dump_macro.line
		jr	dump_macro.record

dump_macro.next_block:
		derefp	dump_block	; BODY_NEXT is at offset 0, and it
		fpsave	dump_block	; replaces the pointer we just used
		jr	dump_macro.block

; dump_macro.line - copy one record out of the heap and print it.

dump_macro.line:
		derefp	dump_block
		ld	de,(dump_offset)
		add	hl,de		; HL -> the record
		ld	a,(hl)
		ld	(dump_text_length),a	; LINE_LENGTH
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(dump_line_number),de	; LINE_NUMBER
		inc	hl		; HL -> the text
		ld	de,(borrowed_buffer)	; the borrowed line buffer
		ld	a,(dump_text_length)
		or	a
		jr	z,dump_macro.line_empty
		ld	c,a
		ld	b,0
		ldir			; out of the heap, into ordinary RAM
dump_macro.line_empty:
		ex	de,hl
		ld	(hl),0		; terminate it

; Everything wanted is now in ordinary RAM, so page 2 may go.

		ld	de,msg_two_spaces
		call	print_dollar_string
		ld	hl,(dump_line_number)
		call	print_decimal
		ld	de,msg_bar
		call	print_dollar_string
		ld	de,(borrowed_buffer)
		call	print_body_line	; markers show as <n>
		ld	de,msg_newline
		call	print_dollar_string

		ld	hl,(dump_offset)	; step over the record
		ld	a,(dump_text_length)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	de,LINE_HEADER_SIZE
		add	hl,de
		ld	(dump_offset),hl
		ret

; print_body_line - print a stored body line, showing parameter markers as <n>.
;
;   A marker is two bytes that would print as control characters, so the
;   dump has to expand them or show nothing useful.
;
; Input:	DE -> the line, zero-terminated
; Output:	printed
; Modifies:	AF, BC, DE, HL

print_body_line:
		ld	a,(de)
		or	a
		ret	z
		cp	MARK_PARAMETER
		jr	z,print_body_line.parameter
		cp	MARK_LOCAL
		jr	z,print_body_line.local
		push	de
		ld	e,a
		call	print_char
		pop	de
		inc	de
		jr	print_body_line

print_body_line.parameter:
		ld	hl,msg_mark_open	; a parameter prints as <n>
		jr	print_body_line.index
print_body_line.local:
		ld	hl,msg_mark_local	; a LOCAL prints as <Ln>
print_body_line.index:
		ld	(mark_bracket),hl

print_body_line.mark:
		inc	de		; the index follows the marker byte
		ld	a,(de)
		ld	(mark_index),a
		push	de
		ld	de,(mark_bracket)
		call	print_dollar_string
		ld	a,(mark_index)
		ld	l,a
		ld	h,0
		call	print_decimal
		ld	de,msg_mark_close
		call	print_dollar_string
		pop	de
		inc	de
		jr	print_body_line

 		dseg

; --- while a definition is being collected

borrowed_buffer:
		defs	2		; the line buffer the called lent us
block_kind:	defs	1	; collect_block: MACRO_IS_REPT, IRP or IRPC
old_descriptor:	defs	4		; far pointer: a descriptor the name
					;   table has just stopped naming
body_file:	defs	1
			; collect_macro and collect_block: the line that
body_line:	defs	2	;   opened the body, for error_macro_not_closed
wanted_descriptor:
		defs	4	; descriptor_name: the descriptor being named
name_walk:	defs	5		; descriptor_name: htnext's iterator
record_key_length:
		defs	1	; descriptor_name: this record's key length
list_walk:	defs	5	; list_macros's walk over the same table
free_walk:	defs	5
			; macro_table_reset: htnext's iterator. NOT shared with
descriptor_to_free:
		defs	4
			;   descriptor_name's - nine bytes is a cheap price
					;   for two walks that cannot interfere, and
					;   what a shared precondition
					;   costs when it is undocumented
open_bodies:	defs	2		; opened bodies not yet closed
body_fields:	defs	FIELD_BLOCK_SIZE	; the body line being looked at
		; the macro's name, zero-terminated
macro_name:	defs	MACRO_NAME_MAX+1
macro_name_length:
		defs	1		; and its length, for htadd/htfind
parameter_count:
		defs	1		; how many parameters
name_pool:	defs	PARM_NAMES_SIZE	; their names, length-prefixed
pool_used:	defs	1		; bytes of that pool in use
pool_length_at:	defs	2	; split_parameters: where a length byte goes
local_name_count:
		defs	1		; how many LOCAL names
pool_names:	defs	1	; parameters + LOCALs, for find_pool_name
body_line_stored:
		defs	1		; a body line has been stored, so a
					;   LOCAL line would now be too late
dump_local_count:
		defs	1		; dump_macro: the LOCAL count
mark_bracket:	defs	2
			; print_body_line: which bracket this marker uses

scanned_line:	defs	LINE_MAX+1	; the prescanned line
scanned_length:	defs	1		; how long it is
open_quote:	defs	1		; the quote we are inside, 0 = none
force_next:	defs	1		; the last character was "&"
identifier_at:	defs	2	; where an identifier begins in scanned_line

mark_index:	defs	1	; print_body_line: the index being printed

descriptor_at:	defs	4		; far pointer: the descriptor
record_payload:	defs	4		; far pointer: its name table payload
last_block:	defs	4		; far pointer: the last body block
body_block_at:	defs	4		; far pointer: a block being allocated
block_used:	defs	2		; first free byte in the last block
line_text_at:	defs	2		; append_body_line: the text to store
line_text_length:
		defs	1		; append_body_line: how long it is

; --- while a definition is being dumped

dump_block:	defs	4		; far pointer: the block being read
dump_offset:	defs	2		; offset of the next record in it
dump_block_end:	defs	2		; how far that block is filled
dump_text_length:
		defs	1		; the record's text length
dump_line_number:
		defs	2		; the record's source line number
dump_line_count:
		defs	2		; the body's line count
dump_file:	defs	1		; the file the definition came from
dump_origin:	defs	2		; the line the MACRO line was on

; --- the macro name table itself. hash.as requires the descriptor to be
;     in ordinary RAM, never in the heap: it is read while a record is
;     mapped into page 2.

macro_table:	defs	2+MACRO_BUCKETS*4

msg_macro:	defb	"MACRO $"
msg_colon:	defb	": $"
msg_parameters:	defb	" parameters, $"
msg_lines:	defb	" lines, $"
msg_open_bracket:
		defb	"($"
msg_close_bracket_eol:
		defb	")",CHR_CR,CHR_LF,"$"
msg_two_spaces:	defb	"  $"
msg_bar:	defb	" | $"
msg_newline:	defb	CHR_CR,CHR_LF,"$"
msg_mark_open:	defb	"<$"
msg_mark_close:	defb	">$"
msg_locals:	defb	" locals, $"
msg_mark_local:	defb	"<L$"
