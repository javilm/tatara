; mdt.inc - the shapes of the macro tables, in mapper RAM.
;
; Four structures, described in mdt-design.md:
;
;   the name table	one hash.as table, name -> a pointer to a descriptor
;   the descriptor	the definition's cover page, 22 bytes
;   the body blocks	a chain of 2048-byte blocks holding the stored lines
;   the expansion	the bookmark for a replay in progress
;
; Nothing here is a Z80 address: everything below the name table lives in
; mapper RAM and is reached through a far pointer.

; --- the name table's payload: just a pointer to the descriptor.
;
;     The descripotr is NOT stored in the record itself, so that a
;     redefinition can repoint it without freeing anything that a running
;     expansion may still be reading.

NAME_DESCRIPTOR	equ	0		; +0 far pointer to the descriptor (4)
NAME_ENTRY_SIZE	equ	4		; payload size handed to htadd

MACRO_BUCKETS	equ	16		; buckets: a power of two. 66 bytes of
MACRO_BUCKET_MASK	equ	MACRO_BUCKETS-1	; ordinary RAM; see the note

; --- MD, the macro descriptor

MACRO_KIND	equ	0	; +0  MACRO_IS_MACRO / REPT / IRP / IRPC (1)
MACRO_FLAGS	equ	1	; +1  MACRO_ORPHANED / _IN_EXPANSION (1)
MACRO_PARM_COUNT	equ	2	; +2  formal parameters (1)
MACRO_LOCAL_COUNT	equ	3	; +3  LOCAL names (1)
MACRO_USES	equ	4	; +4  expansion running (1)
MACRO_DEF_FILE	equ	5	; +5  file the definition came from (1)
MACRO_DEF_LINE	equ	6	; +6  line of the MACRO line (2)
MACRO_LINE_COUNT	equ	8	; +8  body lines stored (2)
MACRO_BODY	equ	10	; +10 far pointer to the first block (4)
MACRO_LAST_BLOCK	equ	14	; +14 far pointer to the last block (4)
				;     in the layout, not maintained
		; +18 far pointer to the formal names (4), null until the
		;     diagnostics need them
MACRO_PARM_NAMES	equ	18
MACRO_DESCRIPTOR_SIZE	equ	22

MACRO_IS_MACRO	equ	0
MACRO_IS_REPT	equ	1
MACRO_IS_IRP	equ	2
MACRO_IS_IRPC	equ	3

MACRO_ORPHANED	equ	1	; bit0: no longer reachable by name
MACRO_IN_EXPANSION	equ	2	; bit1: collected during an expansion

; --- one body block

BODY_NEXT	equ	0	; +0 far pointer to the next block (4)
BODY_USED	equ	4	; +4 offset of the first free byte (2)
BODY_DATA	equ	6	; +6 the line records start here
BODY_BLOCK_SIZE	equ	2048	; payload bytes asked of halloc

; --- one stored body line. A record never straddles two blocks.

LINE_LENGTH	equ	0	; +0 length of the text, 0-255 (1)
LINE_NUMBER	equ	1	; +1 the source line it came from (2)
LINE_TEXT	equ	3	; +3 the text itself
LINE_HEADER_SIZE	equ	3	; the three bytes before the text

; --- prescan markers. A stored body line contains a two-byte marker
;     wherever a parameter was named: the marker byte, then the index.
;
;     01h and 02h are safe because file_line (srcline.as) accepts TAB and
;     bytes from 20h upwards and nothing else, so no line the programmer
;     typed can contain one.

MARK_PARAMETER	equ	001h	; next byte = parameter index, 0-based
MARK_LOCAL	equ	002h	; next byte = LOCAL name index

; --- the parameter names, kept in ordinary RAM while one
;     definition is collected. Not stored in the heap: expansion never
;     needs them, only the prescan and (later) the diagnostics do.

PARM_MAX	equ	16	; most parameters we accept
PARM_NAMES_SIZE	equ	128	; bytes for their names, length-prefixed

; --- limits kept in ordinary RAM while a definition is collected

MACRO_NAME_MAX	equ	64	; longest macro name we remember

; --- MX, the expansion record: one per replay in progress. Allocated
;     when a macro is called, freed when its body runs out. the line
;     source entry holds a far pointer to it.
;
;     There is no parent pointer. The origin chain R5 needs is the line
;     source stack itself: a source is popped only when it runs out, so
;     at the moment an error fires every level that led to it is still
;     stacked. print_trail (errs.as) walks it. MX_PAR was reserved here for a
;     linked list and never filled in; it was deleted rather than
;     start maintaining it.

EXPANSION_DESCRIPTOR	equ	0	; +0 far ptr to the descriptor (4)
EXPANSION_BLOCK	equ	4	; +4 far ptr to the body block we are in (4)
		; +8 offset in it of the NEXT record (2)
EXPANSION_OFFSET	equ	8
EXPANSION_LINE	equ	10	; +10 body line just delivered (2)
EXPANSION_CALL_FILE	equ	12	; +12 file the call was in (1)
EXPANSION_CALL_LINE	equ	13	; +13 line the call was on (2)
EXPANSION_ARGS	equ	15	; +15 far pointer to the arguments (4)
EXPANSION_ARG_COUNT	equ	19	; +19 arguments supplied (1)
		; +20 first ??nnnn of this expansion (2) [p. 6]
EXPANSION_LABEL_BASE	equ	20
		; +22 iterations left (2) [p. 8]
EXPANSION_ITERATIONS	equ	22
EXPANSION_ITEM	equ	24	; +24 IRP/IRPC position (2)              [p. 8]
		; +26 conditionals open when this started
EXPANSION_COND_DEPTH	equ	26
				;     (1). EXITM unwinds to it: a body that
				;     is abandoned takes its unclosed IFs
				;     with it                            [p. 9]
EXPANSION_SIZE	equ	27

; --- MA, the argument vector: one block per expansion that was called
;     with an operand. Freed with the expansion record.
;
;     The offset table is always PARM_MAX entries long, used or not. That
;     wastes at most 30 bytes in a short-lived block, and it is what lets
;     the parser work in one pass: the strings begin at a known offset,
;     so each one is written as it is read, before the count is known.

ARGS_COUNT	equ	0	; +0 how many arguments were supplied (1)
ARGS_TABLE	equ	1	; +1 offset table, PARM_MAX words. Each is the
				;    offset from the block's start of a
				;    lengh-prefixed string
ARGS_TEXT	equ	ARGS_TABLE+PARM_MAX*2	; +33 the strings start here
ARGS_OVERHEAD	equ	ARGS_TEXT+PARM_MAX	; the fixed part of a block:
				; header, table, and one length byte per
				; argument. The text can only be shorter
				; than the operand it came from, so
				; ARGS_OVERHEAD + the operand's length always
				; fits
