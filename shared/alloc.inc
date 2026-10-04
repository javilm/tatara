; alloc.inc - external declarations for the mapper heap library (alloc.as).
;
; Include this from any module that uses the library:
;
;	include	alloc.inc
;
; and link the library after your program:  ld myprog=myprog,alloc

	extrn	heap_init		; init mapper access + empty heap
					;   out: CY set = no mapper support
	extrn	halloc			; allocate a block
					;   in:  BC = payload bytes (1-16372)
					;        HL -> 4-byte result buffer
					;   out: CY set = out of memory
	extrn	hfree			; free a block
					;   in:  HL -> far pointer from halloc
	extrn	deref			; make a far pointer addressable
					;   in:  HL -> 4-byte far pointer
					;   out: HL = address in page 2
	extrn	page2_restore		; hand page 2 back to MSX-DOS
					;   call before EVERY BDOS call and
					;   before terminating!
	extrn	mapper_total		; total mapper RAM
					;   out: HL = number of 16K segments
	extrn	blocks_out		; A WORD, not a routine: blocks handed
					;   out by halloc and not yet given back
					;   to hfree. The library never reads it;
					;   compare it across two runs that
					;   should be equivalent to find a leak
