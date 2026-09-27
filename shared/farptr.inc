; farptr.inc - far-pointer idiom macros (alloc.as / hash.as libraries).
;
; A far pointer is 4 bytes: slot(1) + segment(1) + offset(2, 0-3FFFh),
; offset FFFFh = null. Far pointers live in ordinary RAM, never in the heap.
;
; Macros expand INLINE at every use - glue only, logic stays in routines.
; derefp needs deref: include alloc.inc before using it.

NULLOFF		equ	0ffffh	; far-pointer offset meaning "null"

; fpcopy dst,src - copy the far pointer at src to dst (both low RAM).
; NOTE the argument order: destination first, like ld.
; Clobbers:	BC, DE, HL, F

fpcopy		macro	dst,src
		ld	hl,src
		ld	de,dst
		ld	bc,4
		ldir
		endm

; fpsave dst - copy the far pointer at (HL) to dst. For pulling a link
; out of a mapped record when HL already points at it (e.g. after deref).
; Clobbers:	BC, DE, HL, F

fpsave		macro	dst
		ld	de,dst
		ld	bc,4
		ldir
		endm

; fpnull fp - test the far pointer at fp: Z set = null.
; Clobbers:	DE, HL, F

fpnull		macro	fp
		ld	hl,(fp+2)
		ld	de,NULLOFF
		or	a
		sbc	hl,de
		endm 

; derefp fp - map the far pointer at fp: HL -> its bytes in page 2.
; Clobbers:	what deref clobbers (AF, BC, DE, HL)

derefp		macro	fp
		ld	hl,fp
		call	deref
		endm
