; limg.as - the image TANREN is building, and the file it becomes.
;
; SIXTEEN BLOCKS OF 4 KB IN MAPPER RAM, indexed by the address they
; hold: the block is the address's top nibble and the offset is the
; rest of it. A block is created when something is first written into
; it, so a .COM of 8 KB costs two or three blocks and not sixteen.
;
; A NEW BLOCK IS ZEROED. A DS between two DATA runs, or the gap
; between 0100h and an absolute run at 4000h, has to come out of the
; file as zeros and not as whatever the heap last held there.
;
; EVERY BDOS CALL TAKES PAGE 2 BACK, so nothing goes to the file
; straight out of the mapper: a chunk is copied into ordinary RAM
; first and written from there. segments_dump and write_mapped_name met the
; same rule from the other side.

LIMG_INCLUDED		equ	1	; skips the externals in limg.inc

		public	image_init
		public	image_write_run
		public	image_read_byte
		public	image_write_byte
		public	image_save
		public	image_low
		public	image_high
		public	image_any

		include	limg.inc
		include	lobj.inc
					; objfile_string_buffer: the buffer
					;   a NAME goes in, borrowed by
					;   image_save, which runs when
					;   every object file is closed
		include	lerrs.inc
					; error_out_of_memory,
					;   error_image_too_big,
					;   error_cannot_create,
					;   error_cannot_write
		include	alloc.inc	; halloc, deref
		include	farptr.inc	; derefp, NULL_OFFSET
		include	msxdos.inc	; _CREATE, _WRITE, _CLOSE

		cseg

; image_init - an empty image.
;
;   The extremes start the wrong way round on purpose: the first
;   write in either direction replaces them.
;
; Input:	nothing
; Output:	every block unallocated, nothing written
; Modifies:	AF, B, HL

image_init:	ld	hl,block_table
		ld	b,IMAGE_BLOCK_COUNT
image_init.loop:
		inc	hl		; past the slot and the segment
		inc	hl
		ld	(hl),0ffh	; NULL_OFFSET is 0FFFFh, so both bytes
		inc	hl		;   of the offset are FFh
		ld	(hl),0ffh
		inc	hl
		djnz	image_init.loop
		ld	hl,0ffffh
		ld	(image_low),hl
		ld	hl,0
		ld	(image_high),hl
		xor	a
		ld	(image_any),a
		ret

; image_mark - this address now holds content.
;
;   THE SPAN IS MEASURED AND NOT ASSUMED: an absolute module may put
;   content at 4000h in a link whose segments start at 0100h, and the
;   file has to span both.
;
; Input:	HL = the address
; Output:	image_low, image_high, image_any
; Modifies:	AF, DE

image_mark:	ld	a,0ffh
		ld	(image_any),a
		ld	de,(image_low)
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	nc,image_mark.high	; not below the lowest so far
		ld	(image_low),hl
image_mark.high:
		ld	de,(image_high)
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		ret	c		; not above the highest
		ld	(image_high),hl
		ret

; image_find_block - the far pointer of block A, in block_pointer.
;
;   IT IS NOT CALLED imgblk: IMAGE_BLOCK_SIZE is the block size, SOLiD's as
;   folds case, and the two names would be one symbol. Two builds
;   were lost to exactly that.
;
;    may_create_block is what separates a reader from a writer. image_write_run
;    and image_write_byte
;    may create a block; image_read_byte and image_save may not, because
;    reading an
;   address nobody wrote should not cost a mapper segment.
;
; Input:	A = which block, 0 to 15
;		may_create_block = 0FFh if it may be created
; Output:	block_pointer = its far pointer
;		CY set = there is no such block
;		(error_out_of_memory does not return)
; Modifies:	AF, DE, HL - NOT BC, which holds the offset

image_find_block:
		ld	(block_number),a
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl		; four bytes each
		ld	de,block_table
		add	hl,de
		ld	(block_slot),hl	; where it lives, for image_new_block
		ld	de,block_pointer
		push	bc
		ld	bc,4
		ldir
		pop	bc
					; a real offset is 0 to 3FFFh, so a
		ld	a,(block_pointer+3)
		cp	0ffh		;   high byte of FFh can only be
		jr	nz,image_find_block.found	;   NULL_OFFSET
		ld	a,(may_create_block)
		or	a
		scf
		ret	z		; not allowed to create one
		jp	image_new_block
image_find_block.found:
		or	a	; CY clear: block_pointer is good
		ret

; image_new_block - a block that has not existed until now.
;
; Input:	block_number, block_slot
; Output:	block_pointer, and block_table holds it too
;		(error_out_of_memory does not return)
; Modifies:	AF, DE, HL - not BC

image_new_block:
		push	bc
		ld	bc,IMAGE_BLOCK_SIZE
		ld	hl,block_pointer
		call	halloc
		jp	c,error_out_of_memory
		ld	hl,block_pointer; the table keeps it as well
		ld	de,(block_slot)
		ld	bc,4
		ldir
		derefp	block_pointer	; and it starts as zeros
		ld	d,h
		ld	e,l
		inc	de
		ld	(hl),0
		ld	bc,IMAGE_BLOCK_SIZE-1
		ldir
		pop	bc
		or	a		; CY clear
		ret

; image_map, image_map_allowed - the byte at HL, addressable in page 2.
;
;    image_map_allowed creates the block if it has to; image_map does not and
;    says
;   so with carry. BOTH ANSWER WITH HOW MUCH OF THE BLOCK FOLLOWS, so
;   a caller copying a run knows where it has to stop and map again: a
;   run may cross a 4 KB boundary and the two halves are in two mapper
;   segments.
;
; Input:	HL = the address
; Output:	HL = where that byte is in page 2
;		BC = bytes of this block from there on, 1 to 4096
;		CY set = no such block (image_map only; BC is still right)
; Modifies:	AF, BC, DE, HL

image_map_allowed:
		ld	a,0ffh
		jr	image_map.go
image_map:
		xor	a
image_map.go:	ld	(may_create_block),a
		ld	a,h
		and	IMAGE_OFFSET_MASK
		ld	b,a
		ld	c,l		; BC = the offset within the block
		ld	a,h		; and A = which block
		and	0f0h
		rrca
		rrca
		rrca
		rrca
		call	image_find_block
		jr	c,image_map.absent
		derefp	block_pointer	; BC SURVIVES A deref, which is why
		add	hl,bc		;   the offset is kept there
		push	hl
		ld	hl,IMAGE_BLOCK_SIZE
		or	a
		sbc	hl,bc		; and the rest of the block
		ld	b,h
		ld	c,l
		pop	hl
		or	a		; CY clear
		ret
					; no block, but the caller still
image_map.absent:
		ld	hl,IMAGE_BLOCK_SIZE
		or	a		;   needs the distance to the next
		sbc	hl,bc		;   one
		ld	b,h
		ld	c,l
		scf
		ret

; image_write_run - a run of content, into the image.
;
;   A BLOCK AT A TIME. A run of 200 bytes starting at 0FF0h is in two
;   mapper segments, and one ldir cannot reach both.
;
; Input:	HL = the address the run loads at
;		DE -> the bytes, in ordinary RAM
;		BC = how many
; Output:	they are in the image; image_low and image_high know
;		(error_image_too_big, error_out_of_memory do not return)
; Modifies:	everything

image_write_run:
		ld	(run_address),hl
		ld	(run_source),de
		ld	(run_left),bc
		ld	a,b
		or	c
		ret	z		; a run of no bytes
		dec	bc		; THE LAST BYTE, not the one after
		add	hl,bc		;   it: a run ending exactly at
		jp	c,error_image_too_big	;   FFFFh is legal and wrapping
		call	image_mark	;   past it is not
		ld	hl,(run_address)
		call	image_mark	; and the first one
image_write_run.loop:
		ld	hl,(run_left)
		ld	a,h
		or	l
		ret	z
		ld	hl,(run_address)
		call	image_map_allowed	; -> HL, and BC = room left
		ld	(run_target),hl
		ld	hl,(run_left)
		or	a
		sbc	hl,bc		; more than this block holds?
		jr	c,image_write_run.fits
		ld	h,b		; then fill it to the end
		ld	l,c
		jr	image_write_run.next
image_write_run.fits:
		ld	hl,(run_left)
image_write_run.next:
		ld	(run_chunk),hl
		ld	b,h
		ld	c,l
		ld	de,(run_target)
		ld	hl,(run_source)
		ldir			; ordinary RAM -> the mapper
		ld	(run_source),hl
		ld	bc,(run_chunk)	; and everything moves on by it
		ld	hl,(run_address)
		add	hl,bc
		ld	(run_address),hl
		ld	hl,(run_left)
		or	a
		sbc	hl,bc
		ld	(run_left),hl
					; jp: the loop is longer than a jr
		jp	image_write_run.loop

; image_read_byte - one byte out of the image.
;
; Input:	HL = its address
; Output:	A = the byte, or 0 where nothing was ever written
; Modifies:	AF, BC, DE, HL

image_read_byte:
		call	image_map
		ld	a,0		; ld does not touch the carry
		ret	c
		ld	a,(hl)
		ret

; image_write_byte - one byte into it.
;
; Input:	A  = the byte
;		HL = its address
; Output:	it is there
; Modifies:	AF, BC, DE, HL

image_write_byte:
		ld	(byte_to_write),a
		call	image_mark
		call	image_map_allowed
		ld	a,(byte_to_write)
		ld	(hl),a
		ret

; image_save - the image, to a file.
;
;   FROM image_low TO image_high INCLUSIVE and nothing outside it: the space a
;   DS reserved after the last byte of content is not in the file,
;   which is what every loader expects and what L80 does too.
;
;   RAW BYTES, OR SEVEN IN FRONT OF THEM. /B changes nothing about the
;   image: the header's three words are the two this module measured
;   and one the caller hands over.
;
; Input:	DE -> the ASCIIZ filename
;		A  = 0 for raw bytes, anything else for a BLOAD header
;		HL = the execution address that header carries
; Output:	CY set = nothing was written, and no file was made
;		(error_cannot_create, error_cannot_write do not return)
; Modifies:	everything

image_save:	ld	(save_header),a	; BOTH ARGUMENTS FIRST: the rest of
		ld	(save_entry),hl	;   this routine wants A and HL for
		ld	a,(image_any)	;   its own purposes
		or	a
		scf
		ret	z		; a link with no content in it
		xor	a		; mode 0 = read and write
		ld	b,a		; attributes 0 = an ordinary file
		system	_CREATE		; -> A = error, B = the handle
		or	a
		jp	nz,error_cannot_create
		ld	a,b
		ld	(save_handle),a
		ld	a,(save_header)	; the seven bytes, BEFORE any
		or	a		;   content
		call	nz,image_bload_header
		ld	hl,(image_low)
		ld	(save_address),hl
		ld	hl,(image_high)	; both ends are in the file, so the
		ld	de,(image_low)	;   count is the span plus one
		or	a
		sbc	hl,de
		inc	hl
		ld	(save_left),hl
image_save.loop:
		ld	hl,(save_left)
		ld	a,h
		or	l
		jr	z,image_save.done
		ld	a,h		; more than 255 left?
		or	a
		jr	z,image_save.partial	; no: HL is the last chunk
		ld	hl,IMAGE_CHUNK_SIZE
image_save.partial:
		ld	(save_chunk),hl
					; those bytes, into
					; objfile_string_buffer
		call	image_next_chunk
		ld	hl,(save_chunk)
		ld	de,objfile_string_buffer
		ld	a,(save_handle)
		ld	b,a
		system	_WRITE		; -> A = error
		or	a
		jp	nz,error_cannot_write
		ld	bc,(save_chunk)
		ld	hl,(save_address)
		add	hl,bc
		ld	(save_address),hl
		ld	hl,(save_left)
		or	a
		sbc	hl,bc
		ld	(save_left),hl
		jp	image_save.loop
image_save.done:
		ld	a,(save_handle)
		ld	b,a
		system	_CLOSE
		or	a		; CY clear: it was written
		ret

; image_bload_header - the seven-byte BLOAD header.
;
;   FEh, the start address, THE ADDRESS OF THE LAST BYTE - not the one
;   after it - and the execution address: MSX BASIC's BSAVE format,
;   which is what BLOAD reads and what makes a file a .BIN. image_high is
;   already the last byte, so the inclusive end this format is usually
;   got wrong on costs nothing here.
;
;   A file of no bytes never reaches this, because image_save returns
;   before it creates anything.
;
; Input:	the file is open
;		save_entry = the execution address
; Output:	seven bytes are written (error_cannot_write does not return)
; Modifies:	AF, BC, DE, HL

image_bload_header:
		ld	a,0feh	; "this is a machine code file"
		ld	(header_bytes),a
		ld	hl,(image_low)
		ld	(header_bytes+1),hl
		ld	hl,(image_high)
		ld	(header_bytes+3),hl
		ld	hl,(save_entry)
		ld	(header_bytes+5),hl
		ld	hl,7
		ld	de,header_bytes
		ld	a,(save_handle)
		ld	b,a
		system	_WRITE		; -> A = error
		or	a
		jp	nz,error_cannot_write
		ret

; image_next_chunk - the next chunk of the image, into objfile_string_buffer.
;
;   ZEROS FIRST, then whatever blocks exist are copied over them: a
;   chunk may cross a block nobody ever wrote to, and the file needs
;   zeros there rather than a hole.
;
; Input:	save_address = from where
;		save_chunk = how many, 1 to 256
; Output:	objfile_string_buffer holds them
; Modifies:	everything

image_next_chunk:
		ld	hl,objfile_string_buffer
		ld	(hl),0
		ld	d,h
		ld	e,l
		inc	de
		ld	bc,IMAGE_CHUNK_SIZE-1
		ldir
		ld	hl,0
		ld	(chunk_done),hl	; how far into the chunk we are
image_next_chunk.loop:
		ld	hl,(chunk_done)
		ld	de,(save_chunk)
		or	a
		sbc	hl,de
		ret	nc		; the chunk is full
		ld	hl,(save_address)
		ld	de,(chunk_done)
		add	hl,de		; the address this byte holds
		call	image_map
		push	af		; CY: there is no block there
		ld	(chunk_window),hl
		ld	hl,(save_chunk)
		ld	de,(chunk_done)
		or	a
		sbc	hl,de		; what is left of the chunk
		or	a
		sbc	hl,bc		; less than the rest of the block?
		jr	c,image_next_chunk.rest
		ld	h,b
		ld	l,c
		jr	image_next_chunk.next
image_next_chunk.rest:
		ld	hl,(save_chunk)
		ld	de,(chunk_done)
		or	a
		sbc	hl,de
image_next_chunk.next:
		ld	(chunk_piece),hl
		pop	af
		jr	c,image_next_chunk.skip	; no block: the zeros stand
		ld	hl,objfile_string_buffer
		ld	de,(chunk_done)
		add	hl,de
		ex	de,hl		; DE -> where in the buffer
		ld	hl,(chunk_window)	; HL -> the mapper
		ld	bc,(chunk_piece)
		ldir
image_next_chunk.skip:
		ld	hl,(chunk_done)
		ld	bc,(chunk_piece)
		add	hl,bc
		ld	(chunk_done),hl
		jp	image_next_chunk.loop

		dseg

					; the blocks, by which 4 KB of the
block_table:
		defs	IMAGE_BLOCK_COUNT*4
					;   address space they hold
block_pointer:
		defs	4	; one of them, on its way to deref
block_slot:
		defs	2	; and where in block_table it lives
block_number:
		defs	1	; which block it is
					; 0FFh = this caller may create one
may_create_block:
		defs	1
image_low:
		defs	2	; the lowest address written,
image_high:
		defs	2	;   the highest, and
image_any:
		defs	1	;   whether anything was at all
					; image_write_byte: the byte, across
					; the mapping
byte_to_write:
		defs	1
run_address:
		defs	2	; image_write_run: where the run goes,
run_source:
		defs	2	;   where it comes from,
run_left:
		defs	2	;   how much is still to go,
run_chunk:
		defs	2	;   this chunk of it,
run_target:
		defs	2	;   and where that chunk lands
					; image_save: 0 = raw bytes, anything
					; else
save_header:
		defs	1
save_entry:
		defs	2	;   = a BLOAD header, and the execution
				;   address it carries
header_bytes:
		defs	7	; image_bload_header: those seven bytes
save_handle:	defs	1	; image_save: the output file's handle,
save_address:
		defs	2	;   the address it is up to,
save_left:
		defs	2	;   how many bytes are left, and
save_chunk:
		defs	2	;   this chunk's size
					; image_next_chunk: how far into the
					; chunk,
chunk_done:
		defs	2
chunk_piece:
		defs	2	;   this piece of it, and
chunk_window:
		defs	2	;   where in page 2 that piece is
