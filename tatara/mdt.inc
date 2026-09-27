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

MN_MD		equ	0		; +0 far pointer to the descriptor (4)
MNSIZE		equ	4		; payload size handed to htadd

MNBUCKS		equ	16		; buckets: a power of two. 66 bytes of
MNMASK		equ	MNBUCKS-1	; ordinary RAM; see the note

; --- MD, the macro descriptor

MD_KIND		equ	0	; +0  MDK_MACRO / REPT / IRP / IRPC (1)
MD_FLAGS	equ	1	; +1  MDF_* bits (1)
MD_NPARM	equ	2	; +2  formal parameters (1)
MD_NLOCL	equ	3	; +3  LOCAL names (1)
MD_USES		equ	4	; +4  expansion running (1)
MD_DEFFIL	equ	5	; +5  file the definition came from (1)
MD_DEFLIN	equ	6	; +6  line of the MACRO line (2)
MD_NLINES	equ	8	; +8  body lines stored (2)
MD_BODY		equ	10	; +10 far pointer to the first block (4)
MD_LAST		equ	14	; +14 far pointer to the last block (4)
				;     in the layout, not maintained
MD_PNAM		equ	18	; +18 far pointer to the formal names (4)
				;     null until the diagnostics need them
MDSIZE		equ	22

MDK_MACRO	equ	0
MDK_REPT	equ	1
MDK_IRP		equ	2
MDK_IRPC	equ	3

MDF_ORPH	equ	1	; bit0: no longer reachable by name
MDF_INEXP	equ	2	; bit1: collected during an expansion

; --- one body block

MB_NEXT		equ	0	; +0 far pointer to the next block (4)
MB_USED		equ	4	; +4 offset of the first free byte (2)
MB_DATA		equ	6	; +6 the line records start here
MBBLK		equ	2048	; payload bytes asked of halloc

; --- one stored body line. A record never straddles two blocks.

ML_LEN		equ	0	; +0 length of the text, 0-255 (1)
ML_LINE		equ	1	; +1 the source line it came from (2)
ML_TEXT		equ	3	; +3 the text itself
MLHDR		equ	3	; the three bytes before the text

; --- prescan markers. A stored body line contains a two-byte marker
;     wherever a parameter was named: the marker byte, then the index.
;
;     01h and 02h are safe because filelin (srcline.as) accepts TAB and
;     bytes from 20h upwards and nothing else, so no line the programmer
;     typed can contain one.

MP_PARM		equ	001h	; next byte = parameter index, 0-based
MP_LOCL		equ	002h	; next byte = LOCAL name index

; --- the parameter names, kept in ordinary RAM while one
;     definition is collected. Not stored in the heap: expansion never
;     needs them, only the prescan and (later) the diagnostics do.

MDPARMX		equ	16	; most parameters we accept
MDPARSZ		equ	128	; bytes for their names, length-prefixed

; --- limits kept in ordinary RAM while a definition is collected

MDNAMSZ		equ	64	; longest macro name we remember

; --- MX, the expansion record: one per replay in progress. Allocated
;     when a macro is called, freed when its body runs out. the line
;     source entry holds a far pointer to it.
;
;     There is no parent pointer. The origin chain R5 needs is the line
;     source stack itself: a source is popped only when it runs out, so
;     at the moment an error fires every level that led to it is still
;     stacked. errtrl (errs.as) walks it. MX_PAR was reserved here for a
;     linked list and never filled in; it was deleted rather than
;     start maintaining it.

MX_MD		equ	0	; +0 far ptr to the descriptor (4)
MX_BLK		equ	4	; +4 far ptr to the body block we are in (4)
MX_OFF		equ	8	; +8 offset in it of the NEXT record (2)
MX_LINE		equ	10	; +10 body line just delivered (2)
MX_CFIL		equ	12	; +12 file the call was in (1)
MX_CLIN		equ	13	; +13 line the call was on (2)
MX_ARGV		equ	15	; +15 far pointer to the arguments (4)
MX_NARG		equ	19	; +19 arguments supplied (1)
MX_LBASE	equ	20	; +20 first ??nnnn of this expansion (2) [p. 6]
MX_ITER		equ	22	; +22 iterations left (2)                [p. 8]
MX_ITEM		equ	24	; +24 IRP/IRPC position (2)              [p. 8]
MX_CDEP		equ	26	; +26 conditionals open when this started
				;     (1). EXITM unwinds to it: a body that
				;     is abandoned takes its unclosed IFs
				;     with it                            [p. 9]
MXSIZE		equ	27

; --- MA, the argument vector: one block per expansion that was called
;     with an operand. Freed with the expansion record.
;
;     The offset table is always MDPARMX entries long, used or not. That
;     wastes at most 30 bytes in a short-lived block, and it is what lets
;     the parser work in one pass: the strings begin at a known offset,
;     so each one is written as it is read, before the count is known.

MA_CNT		equ	0	; +0 how many arguments were supplied (1)
MA_TAB		equ	1	; +1 offset table, MDPARMX words. Each is the
				;    offset from the block's start of a
				;    lengh-prefixed string
MA_TEXT		equ	MA_TAB+MDPARMX*2	; +33 the strings start here
MAOVER		equ	MA_TEXT+MDPARMX		; the fixed part of a block:
				; header, table, and one length byte per
				; argument. The text can only be shorter
				; than the operand it came from, so
				; MAOVER + the operand's length always fits
