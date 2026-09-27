; alloc.as - Heap allocator over MSX-DOS2 memory-mapper RAM.
;
; General-purpose alloc/free (first-fit, coalescing) backed by 16KB mapper
; segments from ANY mapper in the system, addressed through 4-byte far
; pointers and a banking window in Z80 page 2.
;
; Public interface (see alloc.inc / README.md):
;
;	heapinit	initialise mapper access + empty heap (CY = no mapper)
;	halloc		allocate a block  (BC = bytes, HL -> result buffer)
;	hfree		free a block      (HL -> far pointer)
;	deref		make a far pointer addressable in page 2
;	p2restore	hand page 2 back to MSX-DOS
;	maptot		total mapper RAM, in 16K segments
;	hblocks		(a word) blocks handed out and not yet given back
;
; THE RULE: page 2 belongs to MSX-DOS whenever MSX-DOS runs. Call p2restore
; before EVERY BDOS call and before terminating the program.

		public	heapinit
		public	halloc
		public	hfree
		public	deref
		public	p2restore
		public	maptot
		public	hblocks

; For a description of HOKVLD and EXTBIO, refer to:
; MSX-Datapack Volume 2, chapter 7: MSX Extended BIOS Specification (p.566)

ENASLT		equ	00024h		; MSX-DOS jump vector to the BIOS ENASLT
HOKVLD		equ	0fb20h		; extended-BIOS "hook valid" flag
EXTBIO		equ	0ffcah		; extended-BIOS entry point

; heap block: [ size word ][ payload ][ size word ]
; size word : bits 0-14 = whole-block size (incl. both size words)
;             bit 15    = free flag

BLKHDR		equ	00000h		; header offset within a block
BLKPAY		equ	00002h		; payload start (what halloc returns /
					; hfree receives)
BLKNEXT		equ	00002h		; free block: next free far pointer
BLKPREV		equ	00006h		; free block: prev free far pointer
OVERHEAD	equ	4		; the two size words
MINBLK		equ	12		; 2 header + 4 next + 4 prev + 2 footer
FREEBIT		equ	08000h		; bit 15 of the size word = "free"
NULLOFF		equ	0ffffh		; far-pointer offset meaning "null" (no
					; real block has it)
SEGSIZE		equ	04000h		; 16KB
FENCE		equ	4		; fence is a used block with no payload
WIN		equ	08000h		; page-2 window base
BIGSZ		equ	SEGSIZE-FENCE-FENCE	; big free block size (3FF8h)

		cseg

; ======================================================================
; Initialisation
; ======================================================================

; heapinit - initialise the library: bring up mapper access and start with
; an empty heap. Call once, after confirming MSX-DOS2, before anything else.
;
; Input:	nothing
; Output:	CY set   = no mapper support (no extended BIOS)
;		CY clear = ready
; Modifies:	AF, BC, DE, HL (EXTBIO also destroys IX, IY, and the shadow
;		registers)

heapinit:	call	mapinit		; locate the DOS2 mapper routines
		ret	c		; no mapper support -> fail
		ld	hl,NULLOFF	; empty free list: offset FFFF = null
		ld	(freehd+2),hl	; (only the offset field marks null)
		ld	hl,0		; and nothing is on loan yet
		ld	(hblocks),hl
		ret			; CY still clear from mapinit

; mapinit (internal) - set up mapper access.
;
; Input:	nothing
; Output:	CY set   = no mapper support (no extended BIOS)
;		CY clear = ready (jump table copied, state saved)
; Modifies:	AF, BC, DE, HL (EXTBIO also destroys IX, IY, and the shadow
;		registers)

; For descriptions of the mapper support routines 0401h and 0402h, refer to:
; MSX-Datapack Volume 3, chapter 15: Mapper Support Routines (p.239)

mapinit:	; --- is the extended BIOS present?
		ld	a,(HOKVLD)	; A = hook-valid flag
		and	000000001b	; keep bit 0
		jr	nz,mapinit.1	; set -> extended BIOS is there
		scf			; not there -> fail
		ret
mapinit.1:	; --- fn 0401h: A = primary slot, HL = variable table
		; Returns:	A  = slot address of the primary slot
		;		HL = start address of the mapper variable table
		xor	a
		ld	de,00401h
		call	EXTBIO
		ld	(primslt),a
		ld	(varptr),hl

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
		ld	(p2orig),a

		ld	a,1		; p2restore is safe to run from now on
		ld	(mapready),a

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

; maptot - total mapper RAM, as a count of 16K segments
;
; Sums the "total segments" byte (+1) of every entry in the variable table.
; Uses the literal byte, so a full 4MB mapper counts as 255 (not 256). This
; matches what MSX-DOS2 can actually manage. Caller does HL*16 for KB.
;
; Input:	nothing (heapinit must have run first)
; Output:	HL = total number of 16K RAM segments
; Modifies:	AF, BC, DE, HL, IX

maptot:		ld	hl,0		; running total = 0
		ld	ix,(varptr)	; IX -> first mapper entry

maptot.1:	ld	a,(ix+0)	; +0 = slot address, 0 = end of table
		or	a
		ret	z		; end reached -> HL holds the total
		ld	c,(ix+1)	; +1 = this mapper's segment count
		ld	b,0		; BC = that count (0...255)
		add	hl,bc		; add into running total
		ld	de,8		; each entry is 8 bytes
		add	ix,de		; step into the next mapper
		jr	maptot.1

; allocseg (internal) - allocate one 16K segment from any mapper, primary
; first.
;
; Wraps ALL_SEG with strategy xxx=010: try the primary slot, then spill
; to other mappers automatically.
;
; Input:	nothing (heapinit must have run first)
; Output:	CY set   = no free segment in any mapper
;		CY clear = A = segment number, B = slot address it came from
; Modifies:	AF, BC (ALL_SEG may also disturb DE, HL)

; For a description on how ALL_SEG works, refer to:
; MSX-Datapack Volume 3, chapter 15: Mapper Support Routines (p.243)

allocseg:	call	p2restore	; ALL_SEG is a DOS service: sane
					; page 2 first
		ld	a,(primslt)	; A = primary mapper slot address
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
		ld	(fp_slot),a
		inc	hl
		ld	a,(hl)		; +1 segment
		ld	(fp_seg),a
		inc	hl
		ld	e,(hl)		; +2 offset low
		inc	hl
		ld	d,(hl)		; +3 offset high
		ld	(fp_off),de

		; Cache-valid check
		ld	a,(curvalid)	; is the cache meaningful yet?
		or	a
		jr	z,deref.full

		; Slot match check
		ld	a,(fp_slot)	; same slot as page 2?
		ld	hl,cur_slot
		cp	(hl)
		jr	nz,deref.full

		; Segment match check
		ld	a,(fp_seg)	; same segment too?
		ld	hl,cur_seg
		cp	(hl)
		jr	z,deref.addr

		; Same slot, new segment
		ld	a,(fp_seg)	; same slot, new segment -> set the
					; segment via DOS2 so its record of
					; page 2 stays true
		ld	(cur_seg),a
		call	PUT_P2
		jr	deref.addr

deref.full:	; Full remap
		ld	hl,08000h
		ld	a,(fp_slot)
		call	ENASLT
		ld	a,(fp_seg)
		call	PUT_P2		; segment via DOS2 (keeps its record)
		ld	a,(fp_slot)
		ld	(cur_slot),a
		ld	a,(fp_seg)
		ld	(cur_seg),a
		ld	a,1
		ld	(curvalid),a

deref.addr:	; Address computation
		ld	hl,(fp_off)
		ld	de,08000h
		add	hl,de
		pop	bc
		ret

; p2restore - hand page 2 back to MSX-DOS: restore the slot/segment DOS had
; at startup, and invalidate the deref cache so the next deref remaps.
;
; RULE: page 2 belongs to DOS whenever DOS runs. Call this before EVERY
; BDOS/DOS service call, and before returning to DOS.
;
; It is a no-op until heapinit has run (mapready guard): before that there
; is nothing to restore and the jump table is not filled yet.
;
; Input:	nothing
; Modifies:	AF, BC, DE, HL

p2restore:	ld	a,(mapready)	; before heapinit there is nothing to do
		or	a
		ret	z
		ld	hl,08000h
		ld	a,(primslt)
		call	ENASLT		; page 2 slot -> primary mapper
		ld	a,(p2orig)
		call	PUT_P2		; page 2 segment -> original, via DOS2
		xor	a
		ld	(curvalid),a	; force the next deref to remap
		ret

; ======================================================================
; Heap layer
; ======================================================================

; newseg (internal) - grab a fresh mapper segment, format it: [fence | big
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

newseg:		call	allocseg	; A=segment, B=slot; CY set = OOM
		ret	c

		; build a far pointer to the big block's header (just past the
		; start fence)
		ld	(tmpfp+1),a	; +1 = segment
		ld	a,b
		ld	(tmpfp+0),a	; +0 = slot
		ld	hl,FENCE
		ld	(tmpfp+2),hl	; +2 = offset = FENCE (4)

		ld	hl,tmpfp	; map the new segment into page 2
		call	deref		; (write via absolute page-2 addresses
					; below)
		; --- start fence: used, size FENCE
		ld	hl,FENCE
		ld	(WIN),hl	; header
		ld	(WIN+2),hl	; footer

		; --- big free block: size BIGSZ
		ld	hl,BIGSZ+FREEBIT	; 03FF8h (size) + 08000h (bit)
		ld	(WIN+FENCE),hl		; header @ 08004h
		ld	(WIN+FENCE+BIGSZ-2),hl	; footer @ 0BFFAh

		; --- end fence: used, size FENCE
		ld	hl,FENCE
		ld	(WIN+SEGSIZE-FENCE),hl	; header @ 0BFFCh
		ld	(WIN+SEGSIZE-2),hl	; footer @ 0BFFEh

		; --- link the big block in at the head of the free list
		ld	hl,freehd		; big.next = current head
		ld	de,WIN+FENCE+BLKNEXT
		ld	bc,4
		ldir
		ld	hl,NULLOFF		; big.prev = null
		ld	(WIN+FENCE+BLKPREV+2),hl	; only the offset field
							; marks null

		ld	hl,(freehd+2)	; did a head already exist?
		ld	de,NULLOFF
		or	a
		sbc	hl,de
		jr	z,newseg.head	; old head was null -> nothing to fix

		ld	hl,freehd	; else point old head's prev at big blk
		call	deref		; map old head (remaps page 2, which is
					; fine because big blk is written)
		ld	de,BLKPREV
		add	hl,de
		ex	de,hl
		ld	hl,tmpfp
		ld	bc,4
		ldir

newseg.head:	ld	hl,tmpfp	; head = big block
		ld	de,freehd
		ld	bc,4
		ldir
		or	a		; CY clear = success
		ret

; flremove (internal) - remove a block from the doubly-linked free list.
;
; Input:	HL = pointer to the block's header far pointer (block
;		is on the list)
; Output:	block unlinked, freehd updated if it was the head
; Modifies:	AF, BC, DE, HL

flremove:	call	deref		; HL -> block header (input consumed)
		push	hl
		ld	de,BLKNEXT
		add	hl,de
		ld	de,frnext
		ld	bc,4
		ldir			; frnext = block.next
		pop	hl
		ld	de,BLKPREV
		add	hl,de
		ld	de,frprev
		ld	bc,4
		ldir			; frprev = block.prev

		; --- prev.next = frnext (or freehd = frnext if prev is null)
		ld	hl,(frprev+2)
		ld	de,NULLOFF
		or	a
		sbc	hl,de
		jr	z,flr.prevnull
		ld	hl,frprev	; prev is a real block, HL is *farptr
		call	deref		; HL -> prev header (remaps page 2)
		ld	de,BLKNEXT
		add	hl,de
		ex	de,hl		; DE -> prev.next
		ld	hl,frnext
		ld	bc,4
		ldir
		jr	flr.donext
flr.prevnull:	ld	hl,frnext	; block was the head
		ld	de,freehd
		ld	bc,4
		ldir			; freehd = frnext

		; --- next.prev = frprev (skip if next is null)
flr.donext:	ld	hl,(frnext+2)
		ld	de,NULLOFF
		or	a
		sbc	hl,de
		ret	z		; next is null -> done
		ld	hl,frnext
		call	deref		; HL -> next header
		ld	de,BLKPREV
		add	hl,de
		ex	de,hl		; DE -> next.prev
		ld	hl,frprev
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

halloc:		ld	(req_buf),hl	; where the result goes
		ld	hl,OVERHEAD
		add	hl,bc		; need = payload + header + footer
		ld	de,MINBLK
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	nc,halloc.need1	; need >= MINBLK -> keep
		ld	hl,MINBLK	; else round up (must fit links if
					; freed)
halloc.need1:	ld	(req_need),hl
		ld	de,BIGSZ+1	; larger than any segment can hold?
		or	a
		sbc	hl,de
		jp	nc,halloc.fail	; need > BIGSZ -> impossible

halloc.search:	ld	hl,freehd	; start at the head
		ld	de,hcur
		ld	bc,4
		ldir
halloc.scan:	ld	hl,(hcur+2)	; end of list?
		ld	de,NULLOFF
		or	a
		sbc	hl,de
		jr	z,halloc.grow	; nothing fit -> get a new segment
		ld	hl,hcur
		call	deref		; HL -> this block's header
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = raw size word
		res	7,d		; drop the free bit -> DE = size
		ld	hl,(req_need)
		ex	de,hl		; HL = size, DE = need
		or	a
		sbc	hl,de		; size - need
		jr	nc,halloc.found	; size >= need -> take this one
		ld	hl,hcur		; else advance: hcur = hcur.next
		call	deref
		ld	de,BLKNEXT
		add	hl,de
		ld	de,hcur
		ld	bc,4
		ldir
		jr	halloc.scan

halloc.grow:	call	newseg
		ret	c		; still no memory -> fail (CY already
					; set)
		jr	halloc.search

halloc.found:	ld	hl,hcur		; hblk = the found block
		ld	de,hblk
		ld	bc,4
		ldir
		ld	hl,hblk
		call	deref
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		res	7,d
		ld	(hsize),de	; hsize = block size
		ld	hl,(hsize)
		ld	de,(req_need)
		or	a
		sbc	hl,de
		ld	(hrem),hl	; rem = size - need
		ld	de,MINBLK
		or	a
		sbc	hl,de		; rem - MINBLK
		jr	nc,halloc.split	; leftover usable -> split

; --- take the whole block
halloc.whole:	ld	hl,hblk		; unlink it from the free list
		call	flremove
		ld	hl,hblk		; clear the free bit in header...
		call	deref
		inc	hl
		res	7,(hl)
		ld	hl,hblk		; ...and in footer (at header+size-1)
		call	deref
		ld	de,(hsize)
		add	hl,de
		dec	hl
		res	7,(hl)
		ld	hl,hblk		; haptr = hblk (allocated = whole blk)
		ld	de,haptr
		ld	bc,4
		ldir
		jr	halloc.done

; --- split: shrink free block to rem, carve allocated block off the back
halloc.split:	ld	hl,hblk		; free block header = rem, free
		call	deref
		ld	de,(hrem)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a
		ld	hl,hblk		; free block footer @ header+rem-2
		call	deref
		ld	de,(hrem)
		add	hl,de
		dec	hl
		dec	hl
		ld	de,(hrem)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a
		ld	hl,hblk		; allocated block header @ header+rem,
					; size=need, used
		call	deref
		ld	de,(hrem)
		add	hl,de
		push	hl
		ld	de,(req_need)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		ld	(hl),a
		pop	hl		; allocated footer @ +need -2
		ld	de,(req_need)
		add	hl,de
		dec	hl
		dec	hl
		ld	de,(req_need)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		ld	(hl),a
		ld	a,(hblk+0)	; haptr = hblk, offset += rem
		ld	(haptr+0),a
		ld	a,(hblk+1)
		ld	(haptr+1),a
		ld	hl,(hblk+2)
		ld	de,(hrem)
		add	hl,de
		ld	(haptr+2),hl

; --- return the payload far pointer
halloc.done:	ld	hl,(haptr+2)	; header -> payload: offset += 2
		ld	de,BLKPAY
		add	hl,de
		ld	(haptr+2),hl
		ld	hl,haptr
		ld	de,(req_buf)
		ld	bc,4
		ldir
		ld	hl,(hblocks)	; one more block is out on loan. Only
		inc	hl		; this path counts it: halloc.fail below
		ld	(hblocks),hl	; returns having allocated nothing
		or	a		; CY clear = success
		ret

halloc.fail:	scf
		ret

; fladd (internal) - insert a block at the head of the free list.
;
; Input:	HL = pointer to the block's header far pointer
; Modifies:	AF, BC, DE, HL

fladd:		ld	de,fablk	; fablk = the block's far pointer
		ld	bc,4
		ldir
		ld	hl,fablk	; block.next = current head
		call	deref
		ld	de,BLKNEXT
		add	hl,de
		ex	de,hl
		ld	hl,freehd
		ld	bc,4
		ldir
		ld	hl,fablk	; block.prev = null
		call	deref
		ld	de,BLKPREV+2
		add	hl,de
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		ld	hl,(freehd+2)	; does a head already exist?
		ld	de,NULLOFF
		or	a
		sbc	hl,de
		jr	z,fladd.sethead
		ld	hl,freehd	; old head.prev = fablk
		call	deref
		ld	de,BLKPREV
		add	hl,de
		ex	de,hl
		ld	hl,fablk
		ld	bc,4
		ldir
fladd.sethead:	ld	hl,fablk	; head = fablk
		ld	de,freehd
		ld	bc,4
		ldir
		ret

; hfree - return a block to the heap, coalescing with free neighbors.
;
; Input:	HL = pointer to a 4-byte far pointer (a payload pointer)
; Modifies:	AF, BC, DE, HL

hfree:		ld	de,hfblk	; hfblk = caller's far ptr (payload)
		ld	bc,4
		ldir
		ld	hl,(hblocks)	; one fewer on loan. AFTER the ldir
		dec	hl		; above, not before: HL was the
		ld	(hblocks),hl	; caller's argument until then
		ld	hl,(hfblk+2)	; payload -> header: offset -= BLKPAY
		ld	de,BLKPAY
		or	a
		sbc	hl,de
		ld	(hfblk+2),hl

		ld	hl,hfblk	; read the block's size
		call	deref
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		res	7,d
		ld	(hfsize),de

; --- coalesce forward: neighbor at header + size
		ld	a,(hfblk+0)	; hfnext = hfblk with offset += size
		ld	(hfnext+0),a
		ld	a,(hfblk+1)
		ld	(hfnext+1),a
		ld	hl,(hfblk+2)
		ld	de,(hfsize)
		add	hl,de
		ld	(hfnext+2),hl
		ld	hl,hfnext	; read neighbor's size word
		call	deref
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		bit	7,d		; free?
		jr	z,hfree.fwddone	; no (used/fence) -> stop
		res	7,d
		ld	(hftmp),de	; neighbor size
		ld	hl,hfnext
		call	flremove	; unlink it from the free list
		ld	hl,(hfsize)	; grow our block over it
		ld	de,(hftmp)
		add	hl,de
		ld	(hfsize),hl
hfree.fwddone:

; --- coalesce backward: neighbor's footer is at header - 2
		ld	hl,hfblk
		call	deref
		dec	hl
		dec	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = prev footer's size word
		bit	7,d
		jr	z,hfree.bwddone
		res	7,d
		ld	(hftmp),de	; prev size
		ld	a,(hfblk+0)	; hfprev = hfblk with offset -= prev sz
		ld	(hfprev+0),a
		ld	a,(hfblk+1)
		ld	(hfprev+1),a
		ld	hl,(hfblk+2)
		ld	de,(hftmp)
		or	a
		sbc	hl,de
		ld	(hfprev+2),hl
		ld	hl,hfprev
		call	flremove	; unlink prev
		ld	hl,(hfsize)	; grow: total size += prev size
		ld	de,(hftmp)
		add	hl,de
		ld	(hfsize),hl
		ld	hl,hfprev	; the merged block now starts at prev
		ld	de,hfblk
		ld	bc,4
		ldir
hfree.bwddone:

; --- write the merged block's header and footer as free
		ld	hl,hfblk
		call	deref
		ld	de,(hfsize)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a		; header = size | free
		ld	hl,hfblk
		call	deref
		ld	de,(hfsize)
		add	hl,de
		dec	hl
		dec	hl
		ld	de,(hfsize)
		ld	a,e
		ld	(hl),a
		inc	hl
		ld	a,d
		or	080h
		ld	(hl),a		; footer = size | free

; --- and put it on the free list
		ld	hl,hfblk
		call	fladd
		ret

; ======================================================================
; Variables
; ======================================================================
; Transient variables are OVERLAID to save memory: several labels can name
; the same storage when their owners can never be active at the same time.
; The safety argument, per region:
;   - deref scratch: deref is called by everything else, so it gets its own
;     region and shares with nobody.
;   - helper pool: newseg, flremove and fladd never call one another, so at
;     most one of their scratch frames is live at any moment.
;   - top-level frame: halloc and hfree are the only entry points into the
;     heap and cannot both be mid-call (the library is not reentrant), so
;     their frames overlay. The helper pool must NOT be folded in here:
;     hfree calls flremove while hfprev is still live.

		dseg

; --- permanent state (set by heapinit/mapinit, live for the whole run)
primslt:	defs	1	; primary mapper slot address
varptr:		defs	2	; -> mapper variable table (in page 3)
p2orig:		defs	1	; segment DOS2 had in page 2 at init
mapready:	defb	0	; 1 once mapinit has completed
curvalid:	defb	0	; 0 = window cache invalid (force full map)
cur_slot:	defs	1	; slot currently selected in page 2
cur_seg:	defs	1	; segment currently in page 2
hblocks:	defs	2	; blocks handed out by halloc and not yet given
				; back to hfree. The allocator itself never
				; reads it: it is here so a caller can compare
				; the count across two runs that should be
				; equivalent, and see a leak. heapinit zeroes it

freehd:		defs	4	; far pointer: head of the free list

; --- transient: deref scratch (own region - deref runs inside everything)
fp_slot:	defs	1	; deref: unpacked far pointer: slot
fp_seg:		defs	1	; deref: segment
fp_off:		defs	2	; deref: offset

; --- transient: helper pool (newseg | flremove | fladd - never nested)
tmpfp:				; newseg: far ptr to new segment's big block
fablk:				; fladd: block being inserted
frnext:		defs	4	; flremove: saved 'next' link
frprev:		defs	4	; flremove: saved 'prev' link

; --- transient: top-level frame (halloc | hfree - never both active)
req_need:			; halloc: whole-block size needed
hfsize:		defs	2	; hfree: size of the (merged) block
req_buf:			; halloc: caller's result-buffer address
hftmp:		defs	2	; hfree: neighbor's size
hcur:				; halloc: free-list scan cursor
hfblk:		defs	4	; hfree: block being freed (header)
hblk:				; halloc: chosen free block (header)
hfnext:		defs	4	; hfree: forward physical neighbor
haptr:				; halloc: block handed out (header)
hfprev:		defs	4	; hfree: backward physical neighbor
hsize:		defs	2	; halloc: chosen block's size
hrem:		defs	2	; halloc: leftover after the split
