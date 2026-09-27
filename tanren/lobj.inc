; lobj.inc - public interface of lobj.as: reading a .tro.
;
; lobj.as includes this file too: it defines LOBJLIB first, which
; skips the external declarations below.
;
; The format is tatara-obj-spec.md draft 2. objout.as writes it and
; this module reads it, and the only contract between them is that
; document - which is why the reader was checked against
; the writer and found DATA's content length stated as length-5 where
; it is length-3.

		ifndef	LOBJLIB

		extrn lobopen		; open the file named at DE and
					; check "TRO", the 1Ah and the
					; version byte
					; in:  DE -> ASCIIZ name
		extrn lobnext		; the next record's header
					; out: CY set = no more records
					;      lobtyp, lobleft set
		extrn lobpay		; A bytes of the open record's
					; payload
					; in:  A  = how many, 1 to 255
					;      DE -> where they go
		extrn lobstr		; one string - a length byte and
					; that many bytes - into lobbuf,
					; zero-terminated for putsz
		extrn lobskip		; whatever is left of the open
					; record. A FORWARD SEEK, not a
					; read: skipping tatara.tro's DATA
					; would move 6 KB for nothing
		extrn lobend		; after the last record: is that
					; the end of the file?
					; out: CY set = bytes follow
					;      lobgot = how many
		extrn lobclose		; close the file
		extrn lobtyp		; the open record's type,
		extrn lobleft		;   and how much of its payload
					;   has not been read (a WORD)
		extrn lobbuf		; where lobstr puts a name,
		extrn lobsln		;   and how long it is. BOTH are
					;   both: a name goes into a table's
					;   key, and a key is counted
		endif

LMAXSTR		equ	256	; THE BIGGEST THING A RECORD HOLDS WHOLE:
				; a string is at most 255 bytes, plus the
				; terminator lobstr adds. DATA is skipped
				; here and copied in chunks later, so it
				; never needs to be resident
TROVER		equ	002h	; the file version this linker reads

OR_MOD		equ	001h	; the record types, from the spec (11).
OR_GRP		equ	002h	;   The writer's copy is in objout.inc;
OR_SEG		equ	003h	;   they are repeated rather than shared
OR_PUB		equ	004h	;   because a reader and a writer of the
OR_EXT		equ	005h	;   same format are two programs, and the
OR_DATA		equ	006h	;   document is what keeps them honest
OR_RELOC	equ	007h
OR_ENT		equ	008h
OR_CMNT		equ	07fh
OR_END		equ	0ffh
