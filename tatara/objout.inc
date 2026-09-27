; objout.inc - public interface of objout.as: the relocatable object
; file Tatara produces.
;
; objout.as includes this file too: it defines OBJLIB first, which
; skips the external declarations below - a symbol cannot be declared
; external in the module that defines it as global.
;
; The format is tatara-obj-spec.md, draft 2. Nothing here reads an
; object file: that is the linker's, in Part 5, and the only contract
; between the two is that document.

		ifndef	OBJLIB

		extrn objopen		; create the object file named on
					; the command line and write its
					; header. DOES NOTHING AT ALL if
					; no output file was named
					; out: CY set = could not create
		extrn objhead		; the records the linker's first
					; pass reads: MODNAME, GRPDEF,
					; SEGDEF, EXTDEF and PUBDEF, in
					; that order. CALLED AT THE END OF
					; PASS 1 - it writes segment sizes,
					; and segrst clears those
		extrn objdata		; the bytes the current line
					; emitted, into the open DATA
					; run - starting one, or closing
					; it and starting another, if
					; this line does not carry on
					; where the last one stopped.
					; EVERY LINE OF PASS 2, before
					; anything about listings
		extrn objfix		; remember a fixup for the word
					; that is about to go out, if it
					; needs one. Called from emitxw,
					; which is the only place a word
					; comes from an expression
					; in: HL = its offset within its
					;          segment
					;     (exty, exeidx, lstseg)
		extrn objentr		; remember what END was given, for
					; the ENTRY record objfin writes -
					; a record cannot be written here,
					; because pass 2 has a DATA run
					; open
					; in: HL = the value
					;     A  = exty
		extrn objfin		; the last run, the fixups, the
					; entry point, the END record, and
					; close
		extrn objon		; A BYTE: 0 = no object file was
					; named, and the three above are
					; each a single ret
		endif

; --- the record types, from the spec (11). All of them are here from
;     the start so that a later note adds a writer rather than an
;     equate, and so that this list can be read against the document.

OR_MOD		equ	001h	; MODNAME - flags and the module's name
OR_GRP		equ	002h	; GRPDEF  - a group
OR_SEG		equ	003h	; SEGDEF  - a segment contribution
OR_PUB		equ	004h	; PUBDEF  - a symbol we define
OR_EXT		equ	005h	; EXTDEF  - a symbol we need
OR_DATA		equ	006h	; DATA    - the module's content
OR_RELOC	equ	007h	; RELOC   - fixups into that content
OR_ENT		equ	008h	; ENTRY   - where the program starts
OR_CMNT		equ	07fh	; COMMENT - ignored by any reader
OR_END		equ	0ffh	; END     - the last record

OBJVER		equ	002h	; the version byte in the header

; --- the fixup table. It lives in the MAPPER, because a module
;     the size of tatara.as makes a few thousand fixups and ordinary
;     RAM has none to spare. One block is a far pointer to the next,
;     a count, and that many entries - and an entry is laid out as the
;     spec's RELOC entry, so writing a record is a copy.

FIXPER		equ	128	; entries in a block. The count is a byte
FIXSIZE		equ	5+FIXPER*6	; and the block is this many

FIX_NXT		equ	0	; +0 the next block (4)
FIX_N		equ	4	; +4 how many entries it holds (1)
FIX_E		equ	5	; +5 the entries, six bytes each
