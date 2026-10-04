; alloc.as - Heap allocator over MSX-DOS2 memory-mapper RAM.
;
; General-purpose alloc/free (first-fit, coalescing) backed by 16KB mapper
; segments from ANY mapper in the system, addressed through 4-byte far
; pointers and a banking window in Z80 page 2.
;
; Public interface (see alloc.inc / README.md):
;
;	heap_init	initialise mapper access + empty heap (CY = no mapper)
;	halloc		allocate a block  (BC = bytes, HL -> result buffer)
;	hfree		free a block      (HL -> far pointer)
;	deref		make a far pointer addressable in page 2
;	page2_restore	hand page 2 back to MSX-DOS
;	mapper_total	total mapper RAM, in 16K segments
;	blocks_out	(a word) blocks handed out and not yet given back
;
; THE RULE: page 2 belongs to MSX-DOS whenever MSX-DOS runs. Call page2_restore
; before EVERY BDOS call and before terminating the program.

		public	heap_init
		public	halloc
		public	hfree
		public	deref
		public	page2_restore
		public	mapper_total
		public	blocks_out

; For a description of HOKVLD and EXTBIO, refer to:
; MSX-Datapack Volume 2, chapter 7: MSX Extended BIOS Specification (p.566)

ENASLT		equ	00024h		; MSX-DOS jump vector to the BIOS ENASLT
HOKVLD		equ	0fb20h		; extended-BIOS "hook valid" flag
EXTBIO		equ	0ffcah		; extended-BIOS entry point

; heap block: [ size word ][ payload ][ size word ]
; size word : bits 0-14 = whole-block size (incl. both size words)
;             bit 15    = free flag

BLOCK_HEADER	equ	00000h		; header offset within a block
BLOCK_PAYLOAD	equ	00002h		; payload start (what halloc returns /
					; hfree receives)
BLOCK_NEXT_FREE	equ	00002h		; free block: next free far pointer
BLOCK_PREV_FREE	equ	00006h		; free block: prev free far pointer
BLOCK_OVERHEAD	equ	4		; the two size words
BLOCK_MIN_SIZE	equ	12		; 2 header + 4 next + 4 prev + 2 footer
BLOCK_FREE_FLAG	equ	08000h		; bit 15 of the size word = "free"
NULL_OFFSET	equ	0ffffh		; far-pointer offset meaning "null" (no
					; real block has it)
MAPPER_SEGMENT_SIZE	equ	04000h	; 16KB
FENCE_SIZE	equ	4		; fence is a used block with no payload
WINDOW_BASE	equ	08000h		; page-2 window base
				; big free block size (3FF8h)
WHOLE_SEGMENT_SIZE	equ	MAPPER_SEGMENT_SIZE-FENCE_SIZE-FENCE_SIZE

		cseg

; ======================================================================
; Initialisation
; ======================================================================

; heap_init - initialise the library: bring up mapper access and start with
; an empty heap. Call once, after confirming MSX-DOS2, before anything else.
;
; Input:	nothing
; Output:	CY set   = no mapper support (no extended BIOS)
;		CY clear = ready
; Modifies:	AF, BC, DE, HL (EXTBIO also destroys IX, IY, and the shadow
;		registers)

heap_init:	call	mapper_init	; locate the DOS2 mapper routines
		ret	c		; no mapper support -> fail
		ld	hl,NULL_OFFSET	; empty free list: offset FFFF = null
		ld	(free_list_head+2),hl	; only the offset marks null
		ld	hl,0		; and nothing is on loan yet
		ld	(blocks_out),hl
		ret			; CY still clear from mapper_init

; mapper_init (internal) - set up mapper access.
;
; Input:	nothing
; Output:	CY set   = no mapper support (no extended BIOS)
;		CY clear = ready (jump table copied, state saved)
; Modifies:	AF, BC, DE, HL (EXTBIO also destroys IX, IY, and the shadow
;		registers)

; For descriptions of the mapper support routines 0401h and 0402h, refer to:
; MSX-Datapack Volume 3, chapter 15: Mapper Support Routines (p.239)

mapper_init:	; --- is the extended BIOS present?
		ld	a,(HOKVLD)	; A = hook-valid flag
		and	000000001b	; keep bit 0
		jr	nz,mapper_init.present	; set -> extended BIOS is there
		scf			; not there -> fail
		ret
mapper_init.present:
		; --- fn 0401h: A = primary slot, HL = variable table
		; Returns:	A  = slot address of the primary slot
		;		HL = start address of the mapper variable table
		xor	a
		ld	de,00401h
		call	EXTBIO
		ld	(mapper_slot),a
		ld	(mapper_vars),hl

		; --- fn 0402h: HL = jump table start
		; Returns:	HL = start address of the jump table for the
		;		     mapper support routines
		xor	a
		ld	de,00402h
		call	EXTBIO
		ld	de,ALL_SEG	; copy 16 JP entries (48 bytes) into
					; our table
		ld	bc,48
		ldir

		; --- remember what DOS has in page 2
		call	GET_P2		; A = current page 2 segment
		ld	(page2_original),a

		ld	a,1	; page2_restore is safe to run from now on
		ld	(mapper_ready),a

		or	a		; CY clear = success
		ret

; Local copy of the MSX-DOS2 mapper support jump table, filled by mapinit.
; These are EXECUTED (each entry is a JP written at run time), so they stay
; in the code segment. Order and 3-byte spacing are fixed by the MSX-DOS2
; spec. Do not reorder, do not initialise.

ALL_SEG:	defs	3
FRE_SEG:	defs	3
RD_SEG:		defs	3
WR_SEG:		defs	3
CAL_SEG:	defs	3
CALLS:		defs	3
PUT_PH:		defs	3
GET_PH:		defs	3
PUT_P0:		defs	3
GET_P0:		defs	3
PUT_P1:		defs	3
GET_P1:		defs	3
PUT_P2:		defs	3
GET_P2:		defs	3
PUT_P3:		defs	3
GET_P3:		defs	3

; ======================================================================
; Mapper layer
; ======================================================================

; mapper_total - total mapper RAM, as a count of 16K segments
;
; Sums the "total segments" byte (+1) of every entry in the variable table.
; Uses the literal byte, so a full 4MB mapper counts as 255 (not 256). This
; matches what MSX-DOS2 can actually manage. Caller does HL*16 for KB.
;
; Input:	nothing (heap_init must have run first)
; Output:	HL = total number of 16K RAM segments
; Modifies:	AF, BC, DE, HL, IX

mapper_total:	ld	hl,0		; running total = 0
		ld	ix,(mapper_vars)	; IX -> first mapper entry

mapper_total.loop:
		ld	a,(ix+0)	; +0 = slot address, 0 = end of table
		or	a
		ret	z		; end reached -> HL holds the total
		ld	c,(ix+1)	; +1 = this mapper's segment count
		ld	b,0		; BC = that count (0...255)
		add	hl,bc		; add into running total
		ld	de,8		; each entry is 8 bytes
		add	ix,de		; step into the next mapper
		jr	mapper_total.loop

; allocate_segment (internal) - allocate one 16K segment from any
; mapper, primary first.
;
; Wraps ALL_SEG with strategy xxx=010: try the primary slot, then spill
; to other mappers automatically.
;
; Input:	nothing (heap_init must have run first)
; Output:	CY set   = no free segment in any mapper
;		CY clear = A = segment number, B = slot address it came from
; Modifies:	AF, BC (ALL_SEG may also disturb DE, HL)

; For a description on how ALL_SEG works, refer to:
; MSX-Datapack Volume 3, chapter 15: Mapper Support Routines (p.243)

allocate_segment:
		call	page2_restore	; ALL_SEG is a DOS service: sane
					; page 2 first
		ld	a,(mapper_slot)	; A = primary mapper slot address
		or	020h		; set strategy bits xxx=
		ld	b,a		; B = slot address + strategy
		xor	a		; A = 0 (allocate user segment)
		call	ALL_SEG		; CY on failure, else A=segment, B=slot
		ret

; deref - make a far pointer's byte addressable in page 2.
;
; Input:	HL = pointer to a 4-byte far pointer:
;			+0    slot address
;			+1    segment number
;			+2..3 offset (0..03FFFh)
; Output:	HL = 08000h + offset (mapped and ready)
; Modifies:	AF, DE, HL
;
;       NOT BC: the full-remap path calls ENASLT, which the BIOS
;       documents as destroying every register. deref saves BC
;       so that a caller may hold a counter there across a call.
;       symdump.nm (symtab.as) is the first that does.

; For documentation on how to call ENASLT from MSX-DOS(2), refer to:
; MSX-Datapack Volume 1, chapter 3: MSX-DOS (p.397-399)

; For documentation of the meaning of port 0FEh, refer to:
; MSX-Datapack Volume 1, chapter 1: Hardware (p.6-8)

deref:		push	bc
		; Copy and unpack the far pointer
		ld	a,(hl)		; +0 slot
		ld	(deref_slot),a
		inc	hl
		ld	a,(hl)		; +1 segment
		ld	(deref_segment),a
		inc	hl
		ld	e,(hl)		; +2 offset low
		inc	hl
		ld	d,(hl)		; +3 offset high
		ld	(deref_offset),de

		; Cache-valid check
		ld	a,(window_valid)	; is the cache meaningful yet?
		or	a
		jr	z,deref.remap

		; Slot match check
		ld	a,(deref_slot)	; same slot as page 2?
		ld	hl,window_slot
		cp	(hl)
		jr	nz,deref.remap

		; Segment match check
		ld	a,(deref_segment)	; same segment too?
		ld	hl,window_segment
		cp	(hl)
		jr	z,deref.address

		; Same slot, new segment
		ld	a,(deref_segment)	; set the segment via DOS2 so
					; its record of page 2 stays
					; true
		ld	(window_segment),a
		call	PUT_P2
		jr	deref.address

deref.remap:	; Full remap
		ld	hl,08000h
		ld	a,(deref_slot)
		call	ENASLT
		ld	a,(deref_segment)
		call	PUT_P2		; segment via DOS2 (keeps its record)
		ld	a,(deref_slot)
		ld	(window_slot),a
		ld	a,(deref_segment)
		ld	(window_segment),a
		ld	a,1
		ld	(window_valid),a

deref.address:	; Address computation
		ld	hl,(deref_offset)
		ld	de,08000h
		add	hl,de
		pop	bc
		ret

; page2_restore - hand page 2 back to MSX-DOS: restore the slot/segment DOS had
; at startup, and invalidate the deref cache so the next deref remaps.
;
; RULE: page 2 belongs to DOS whenever DOS runs. Call this before EVERY
; BDOS/DOS service call, and before returning to DOS.
;
; It is a no-op until heap_init has run (mapper_ready guard): before that there
; is nothing to restore and the jump table is not filled yet.
;
; Input:	nothing
; Modifies:	AF, BC, DE, HL

page2_restore:	ld	a,(mapper_ready)	; before heap_init there is nothing to do
		or	a
		ret	z
		ld	hl,08000h
		ld	a,(mapper_slot)
		call	ENASLT		; page 2 slot -> primary mapper
		ld	a,(page2_original)
		call	PUT_P2		; page 2 segment -> original, via DOS2
		xor	a
		ld	(window_valid),a	; force the next deref to remap
		ret

; ======================================================================
; Heap layer
; ======================================================================

; new_segment (internal) - grab a fresh mapper segment, format it: [fence | big
; free block | fence], and put the big free block on the free list.
;
; After formatting, page 2 looks like:
;
; 08000h [start fence] size 4,     used <- stops backward coalescing
; 08004h [big free   ] size 3FF8h, free <- header here, payload holds next/prev
; 0BFFAh  (its footer)
; 0BFFCh [end fence  ] size 4,     used <- stops forward coalescing
;
; Input:	nothing
; Output:	CY set   = out of mapper memory
;		CY clear = a new free block is now available
; Modifies:	AF, BC, DE, HL

new_segment:
		call	allocate_segment	; A=segment, B=slot; CY = OOM
		ret	c

		; build a far pointer to the big block's header (just past the
		; start fence)
		ld	(new_block+1),a	; +1 = segment
		ld	a,b
		ld	(new_block+0),a	; +0 = slot
		ld	hl,FENCE_SIZE
		ld	(new_block+2),hl	; +2 = offset = FENCE_SIZE (4)

		ld	hl,new_block	; map the new segment into page 2
		call	deref		; (write via absolute page-2 addresses
					; below)
		; --- start fence: used, size FENCE_SIZE
		ld	hl,FENCE_SIZE
		ld	(WINDOW_BASE),hl	; header
		ld	(WINDOW_BASE+2),hl	; footer

		; --- big free block: size WHOLE_SEGMENT_SIZE
		; 03FF8h (size) + 08000h (bit)
		ld	hl,WHOLE_SEGMENT_SIZE+BLOCK_FREE_FLAG
		ld	(WINDOW_BASE+FENCE_SIZE),hl	; header @ 08004h
		; footer @ 0BFFAh
		ld	(WINDOW_BASE+FENCE_SIZE+WHOLE_SEGMENT_SIZE-2),hl

		; --- end fence: used, size FENCE_SIZE
		ld	hl,FENCE_SIZE
		; header @ 0BFFCh, footer @ 0BFFEh
		ld	(WINDOW_BASE+MAPPER_SEGMENT_SIZE-FENCE_SIZE),hl
		ld	(WINDOW_BASE+MAPPER_SEGMENT_SIZE-2),hl

		; --- link the big block in at the head of the free list
		ld	hl,free_list_head	; big.next = current head
		ld	de,WINDOW_BASE+FENCE_SIZE+BLOCK_NEXT_FREE
		ld	bc,4
		ldir
		ld	hl,NULL_OFFSET		; big.prev = null
		; only the offset field marks null
		ld	(WINDOW_BASE+FENCE_SIZE+BLOCK_PREV_FREE+2),hl

		ld	hl,(free_list_head+2)	; did a head already exist?
		ld	de,NULL_OFFSET
		or	a
		sbc	hl,de
		jr	z,new_segment.header	; null head: nothing to fix

		ld	hl,free_list_head	; else point old head's prev at
		call	deref		;   the big block. This remaps
					;   page 2, which is
					; fine because big blk is written)
		ld	de,BLOCK_PREV_FREE
		add	hl,de
		ex	de,hl
		ld	hl,new_block
		ld	bc,4
		ldir

new_segment.header:
		ld	hl,new_block	; head = big block
		ld	de,free_list_head
		ld	bc,4
		ldir
		or	a		; CY clear = success
		ret

; free_list_remove (internal) - remove a block from the doubly-linked
; free list.
;
; Input:	HL = pointer to the block's header far pointer (block
;		is on the list)
; Output:	block unlinked, free_list_head updated if it was the head
; Modifies:	AF, BC, DE, HL

free_list_remove:
		call	deref		; HL -> block header (input consumed)
		push	hl
		ld	de,BLOCK_NEXT_FREE
		add	hl,de
		ld	de,remove_next
		ld	bc,4
		ldir			; remove_next = block.next
		pop	hl
		ld	de,BLOCK_PREV_FREE
		add	hl,de
		ld	de,remove_prev
		ld	bc,4
		ldir			; remove_prev = block.prev

		; --- prev.next = remove_next, or free_list_head = remove_next
		;     when prev is null
		ld	hl,(remove_prev+2)
		ld	de,NULL_OFFSET
		or	a
		sbc	hl,de
		jr	z,free_list_remove.at_head
		ld	hl,remove_prev	; prev is a real block, HL is *farptr
		call	deref		; HL -> prev header (remaps page 2)
		ld	de,BLOCK_NEXT_FREE
		add	hl,de
		ex	de,hl		; DE -> prev.next
		ld	hl,remove_next
		ld	bc,4
		ldir
		jr	free_list_remove.fix_next
free_list_remove.at_head:
		ld	hl,remove_next	; block was the head
		ld	de,free_list_head
		ld	bc,4
		ldir			; free_list_head = remove_next

		; --- next.prev = remove_prev (skip if next is null)
free_list_remove.fix_next:
		ld	hl,(remove_next+2)
		ld	de,NULL_OFFSET
		or	a
		sbc	hl,de
		ret	z		; next is null -> done
		ld	hl,remove_next
		call	deref		; HL -> next header
		ld	de,BLOCK_PREV_FREE
		add	hl,de
		ex	de,hl		; DE -> next.prev
		ld	hl,remove_prev
		ld	bc,4
		ldir
		ret

; halloc - allocate a block from the heap (first-fit)
;
; Input:	BC = requested payload bytes
;		HL = pointer to a 4-byte buffer to receive the payload far
;		pointer
; Output:	CY set   = out of memory
;		CY clear = buffer holds the far pointer
; Modifies:	AF, BC, DE, HL

halloc:		ld	(alloc_buffer),hl	; where the result goes
		ld	hl,BLOCK_OVERHEAD
		add	hl,bc		; need = payload + header + footer
		ld	de,BLOCK_MIN_SIZE
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	nc,halloc.have_need	; >= BLOCK_MIN_SIZE: keep
		ld	hl,BLOCK_MIN_SIZE	; else round up, so the links
					; fit when it is freed
halloc.have_need:
		ld	(alloc_need),hl
		; larger than any segment can hold?
		ld	de,WHOLE_SEGMENT_SIZE+1
		or	a
		sbc	hl,de
		jp	nc,halloc.fail	; bigger than a segment

halloc.search:	ld	hl,free_list_head	; start at the head
		ld	de,alloc_cursor
		ld	bc,4
		ldir
halloc.scan:	ld	hl,(alloc_cursor+2)	; end of list?
		ld	de,NULL_OFFSET
		or	a
		sbc	hl,de
		jr	z,halloc.grow	; nothing fit -> get a new segment
		ld	hl,alloc_cursor
		call	deref		; HL -> this block's header
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = raw size word
		res	7,d		; drop the free bit -> DE = size
		ld	hl,(alloc_need)
		ex	de,hl		; HL = size, DE = need
		or	a
		sbc	hl,de		; size - need
		jr	nc,halloc.found	; size >= need -> take this one
		ld	hl,alloc_cursor	; else advance it to .next
		call	deref
		ld	de,BLOCK_NEXT_FREE
		add	hl,de
		ld	de,alloc_cursor
		ld	bc,4
		ldir
		jr	halloc.scan

halloc.grow:	call	new_segment
		ret	c		; still no memory -> fail (CY already
					; set)
		jr	halloc.search

halloc.found:	ld	hl,alloc_cursor	; alloc_block = the found block
		ld	de,alloc_block
		ld	bc,4
		ldir
		ld	hl,alloc_block
		call	deref
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		res	7,d
		ld	(alloc_block_size),de	; alloc_block_size = block size
		ld	hl,(alloc_block_size)
		ld	de,(alloc_need)
		or	a
		sbc	hl,de
		ld	(alloc_remainder),hl	; rem = size - need
		ld	de,BLOCK_MIN_SIZE
		or	a
		sbc	hl,de		; rem - BLOCK_MIN_SIZE
		jr	nc,halloc.split	; leftover usable -> split

; --- take the whole block
halloc.take_whole:
		ld	hl,alloc_block	; unlink it from the free list
		call	free_list_remove
		ld	hl,alloc_block	; clear the free bit in header...
		call	deref
		inc	hl
		res	7,(hl)
		ld	hl,alloc_block	; ...and in footer (at header+size-1)
		call	deref
		ld	de,(alloc_block_size)
		add	hl,de
		dec	hl
		res	7,(hl)
		; alloc_result = alloc_block: the whole block is handed out
		ld	hl,alloc_block
		ld	de,alloc_result
		ld	bc,4
		ldir
		jr	halloc.done

; --- split: shrink free block to rem, carve allocated block off the back
halloc.split:	ld	hl,alloc_block	; free block header = rem, free
		call	deref
		ld	de,(alloc_remainder)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a
		ld	hl,alloc_block	; free block footer @ header+rem-2
		call	deref
		ld	de,(alloc_remainder)
		add	hl,de
		dec	hl
		dec	hl
		ld	de,(alloc_remainder)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a
		ld	hl,alloc_block	; allocated block header @ header+rem,
					; size=need, used
		call	deref
		ld	de,(alloc_remainder)
		add	hl,de
		push	hl
		ld	de,(alloc_need)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		ld	(hl),a
		pop	hl		; allocated footer @ +need -2
		ld	de,(alloc_need)
		add	hl,de
		dec	hl
		dec	hl
		ld	de,(alloc_need)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		ld	(hl),a
		; alloc_result = alloc_block, offset += the remainder
		ld	a,(alloc_block+0)
		ld	(alloc_result+0),a
		ld	a,(alloc_block+1)
		ld	(alloc_result+1),a
		ld	hl,(alloc_block+2)
		ld	de,(alloc_remainder)
		add	hl,de
		ld	(alloc_result+2),hl

; --- return the payload far pointer
halloc.done:			; header -> payload: offset += 2
		ld	hl,(alloc_result+2)
		ld	de,BLOCK_PAYLOAD
		add	hl,de
		ld	(alloc_result+2),hl
		ld	hl,alloc_result
		ld	de,(alloc_buffer)
		ld	bc,4
		ldir
		ld	hl,(blocks_out)	; one more block is out on loan. Only
		inc	hl		; this path counts it: halloc.fail below
		ld	(blocks_out),hl	; returns having allocated nothing
		or	a		; CY clear = success
		ret

halloc.fail:	scf
		ret

; free_list_add (internal) - insert a block at the head of the free list.
;
; Input:	HL = pointer to the block's header far pointer
; Modifies:	AF, BC, DE, HL

free_list_add:	ld	de,add_block	; add_block = the block's far pointer
		ld	bc,4
		ldir
		ld	hl,add_block	; block.next = current head
		call	deref
		ld	de,BLOCK_NEXT_FREE
		add	hl,de
		ex	de,hl
		ld	hl,free_list_head
		ld	bc,4
		ldir
		ld	hl,add_block	; block.prev = null
		call	deref
		ld	de,BLOCK_PREV_FREE+2
		add	hl,de
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		ld	hl,(free_list_head+2)	; does a head already exist?
		ld	de,NULL_OFFSET
		or	a
		sbc	hl,de
		jr	z,free_list_add.as_head
		ld	hl,free_list_head	; old head.prev = add_block
		call	deref
		ld	de,BLOCK_PREV_FREE
		add	hl,de
		ex	de,hl
		ld	hl,add_block
		ld	bc,4
		ldir
free_list_add.as_head:
		ld	hl,add_block	; head = add_block
		ld	de,free_list_head
		ld	bc,4
		ldir
		ret

; hfree - return a block to the heap, coalescing with free neighbors.
;
; Input:	HL = pointer to a 4-byte far pointer (a payload pointer)
; Modifies:	AF, BC, DE, HL

hfree:		ld	de,free_block	; the caller's far ptr (payload)
		ld	bc,4
		ldir
		ld	hl,(blocks_out)	; one fewer on loan. AFTER the ldir
		dec	hl		; above, not before: HL was the
		ld	(blocks_out),hl	; caller's argument until then
		; payload -> header: offset -= BLOCK_PAYLOAD
		ld	hl,(free_block+2)
		ld	de,BLOCK_PAYLOAD
		or	a
		sbc	hl,de
		ld	(free_block+2),hl

		ld	hl,free_block	; read the block's size
		call	deref
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		res	7,d
		ld	(free_size),de

; --- coalesce forward: neighbor at header + size
		; free_next_block = free_block, offset += size
		ld	a,(free_block+0)
		ld	(free_next_block+0),a
		ld	a,(free_block+1)
		ld	(free_next_block+1),a
		ld	hl,(free_block+2)
		ld	de,(free_size)
		add	hl,de
		ld	(free_next_block+2),hl
		ld	hl,free_next_block	; read neighbor's size word
		call	deref
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		bit	7,d		; free?
		jr	z,hfree.forward_done	; no (used/fence) -> stop
		res	7,d
		ld	(free_neighbour_size),de	; neighbor size
		ld	hl,free_next_block
		call	free_list_remove	; unlink it from the free list
		ld	hl,(free_size)	; grow our block over it
		ld	de,(free_neighbour_size)
		add	hl,de
		ld	(free_size),hl
hfree.forward_done:

; --- coalesce backward: neighbor's footer is at header - 2
		ld	hl,free_block
		call	deref
		dec	hl
		dec	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = prev footer's size word
		bit	7,d
		jr	z,hfree.backward_done
		res	7,d
		ld	(free_neighbour_size),de	; prev size
		; free_prev_block = free_block, offset -= the previous size
		ld	a,(free_block+0)
		ld	(free_prev_block+0),a
		ld	a,(free_block+1)
		ld	(free_prev_block+1),a
		ld	hl,(free_block+2)
		ld	de,(free_neighbour_size)
		or	a
		sbc	hl,de
		ld	(free_prev_block+2),hl
		ld	hl,free_prev_block
		call	free_list_remove	; unlink prev
		ld	hl,(free_size)	; grow: total size += prev size
		ld	de,(free_neighbour_size)
		add	hl,de
		ld	(free_size),hl
		ld	hl,free_prev_block	; the merge starts at prev
		ld	de,free_block
		ld	bc,4
		ldir
hfree.backward_done:

; --- write the merged block's header and footer as free
		ld	hl,free_block
		call	deref
		ld	de,(free_size)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a		; header = size | free
		ld	hl,free_block
		call	deref
		ld	de,(free_size)
		add	hl,de
		dec	hl
		dec	hl
		ld	de,(free_size)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a		; footer = size | free

; --- and put it on the free list
		ld	hl,free_block
		call	free_list_add
		ret

; ======================================================================
; Variables
; ======================================================================
; Transient variables are OVERLAID to save memory: several labels can name
; the same storage when their owners can never be active at the same time.
; The safety argument, per region:
;   - deref scratch: deref is called by everything else, so it gets its own
;     region and shares with nobody.
;   - helper pool: new_segment, free_list_remove and free_list_add
;     never call one another, so at most one of their scratch frames
;     is live at any moment.
;   - top-level frame: halloc and hfree are the only entry points into the
;     heap and cannot both be mid-call (the library is not reentrant), so
;     their frames overlay. The helper pool must NOT be folded in here:
;     hfree calls free_list_remove while free_prev_block is still live.

		dseg

; --- permanent state (set by heap_init/mapper_init, live for the whole run)
mapper_slot:	defs	1	; primary mapper slot address
mapper_vars:	defs	2	; -> mapper variable table (in page 3)
page2_original:	defs	1	; segment DOS2 had in page 2 at init
mapper_ready:	defb	0	; 1 once mapper_init has completed
window_valid:	defb	0	; 0 = window cache invalid (force full map)
window_slot:	defs	1	; slot currently selected in page 2
window_segment:	defs	1	; segment currently in page 2
blocks_out:	defs	2	; blocks handed out by halloc and not yet given
				; back to hfree. The allocator itself never
				; reads it: it is here so a caller can compare
				; the count across two runs that should be
				; equivalent, and see a leak. heap_init zeroes it

free_list_head:	defs	4	; far pointer: head of the free list

; --- transient: deref scratch (own region - deref runs inside everything)
deref_slot:	defs	1	; deref: unpacked far pointer: slot
deref_segment:	defs	1	; deref: segment
deref_offset:	defs	2	; deref: offset

; --- transient: helper pool - never nested
;     (new_segment | free_list_remove | free_list_add)
new_block:	; new_segment: far ptr to new segment's big block
add_block:			; free_list_add: block being inserted
remove_next:	defs	4	; free_list_remove: saved 'next' link
remove_prev:	defs	4	; free_list_remove: saved 'prev' link

; --- transient: top-level frame (halloc | hfree - never both active)
alloc_need:			; halloc: whole-block size needed
free_size:	defs	2	; hfree: size of the (merged) block
alloc_buffer:			; halloc: caller's result-buffer address
free_neighbour_size:
		defs	2	; hfree: neighbor's size
alloc_cursor:			; halloc: free-list scan cursor
free_block:	defs	4	; hfree: block being freed (header)
alloc_block:			; halloc: chosen free block (header)
free_next_block:
		defs	4	; hfree: forward physical neighbor
alloc_result:			; halloc: block handed out (header)
free_prev_block:
		defs	4	; hfree: backward physical neighbor
alloc_block_size:
		defs	2	; halloc: chosen block's size
alloc_remainder:
		defs	2	; halloc: leftover after the split
