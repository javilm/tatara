; objout.inc - public interface of objout.as: the relocatable object
; file Tatara produces.
;
; objout.as includes this file too: it defines OBJOUT_INCLUDED first, which
; skips the external declarations below - a symbol cannot be declared
; external in the module that defines it as global.
;
; The format is tatara-obj-spec.md, draft 2. Nothing here reads an
; object file: that is the linker's, in Part 5, and the only contract
; between the two is that document.

		ifndef	OBJOUT_INCLUDED

		extrn object_open	; create the object file named on
					; the command line and write its
					; header. DOES NOTHING AT ALL if
					; no output file was named
					; out: CY set = could not create
		extrn write_tables	; the records the linker's first
					; pass reads: MODNAME, GRPDEF,
					; SEGDEF, EXTDEF and PUBDEF, in
					; that order. CALLED AT THE END OF
					; PASS 1 - it writes segment sizes,
					; and segment_reset clears those
		extrn object_data	; the bytes the current line
					; emitted, into the open DATA
					; run - starting one, or closing
					; it and starting another, if
					; this line does not carry on
					; where the last one stopped.
					; EVERY LINE OF PASS 2, before
					; anything about listings
		extrn object_fixup	; remember a fixup for the word
					; that is about to go out, if it
					; needs one. Called from
					; emit_expr_word, which is the only
					; place a word comes from an expression
					; in: HL = its offset within its
					; segment (value_type, external_index,
					; line_segment)
		extrn object_entry	; remember what END was given, for
					; the ENTRY record object_finish writes
					; - a record cannot be written here,
					; because pass 2 has a DATA run open
					; in: HL = the value A = value_type
		extrn object_finish	; the last run, the fixups, the
					; entry point, the END record, and
					; close
		extrn object_delete	; close the object file and DELETE
					; it, if this run created one. For
					; die_with_message: an error on pass 2
					; must not leave a partial object with
					; the right name and a current
					; timestamp. Does nothing when
					; object_wanted is 0, which is what
					; keeps it from removing a file an
					; earlier run left
		extrn object_wanted	; A BYTE: 0 = no object file was
					; named, and the three above are
					; each a single ret
		endif

; --- the record types, from the spec (11). All of them are here from
;     the start so that a later note adds a writer rather than an
;     equate, and so that this list can be read against the document.

RECORD_MODULE	equ	001h	; MODNAME - flags and the module's name
RECORD_GROUP	equ	002h	; GRPDEF  - a group
RECORD_SEGMENT	equ	003h	; SEGDEF  - a segment contribution
RECORD_PUBLIC	equ	004h	; PUBDEF  - a symbol we define
RECORD_EXTERNAL	equ	005h	; EXTDEF  - a symbol we need
RECORD_DATA	equ	006h	; DATA    - the module's content
RECORD_RELOC	equ	007h	; RELOC   - fixups into that content
RECORD_ENTRY	equ	008h	; ENTRY   - where the program starts
RECORD_COMMENT	equ	07fh	; COMMENT - ignored by any reader
RECORD_END	equ	0ffh	; END     - the last record

OBJECT_VERSION	equ	002h	; the version byte in the header

; --- the fixup table. It lives in the MAPPER, because a module
;     the size of tatara.as makes a few thousand fixups and ordinary
;     RAM has none to spare. One block is a far pointer to the next,
;     a count, and that many entries - and an entry is laid out as the
;     spec's RELOC entry, so writing a record is a copy.

		; entries in a block. The count is a byte
FIXUPS_PER_BLOCK	equ	128
		; and the block is this many
FIXUP_BLOCK_SIZE	equ	5+FIXUPS_PER_BLOCK*6

FIXUP_NEXT	equ	0	; +0 the next block (4)
FIXUP_COUNT	equ	4	; +4 how many entries it holds (1)
FIXUP_ENTRIES	equ	5	; +5 the entries, six bytes each
