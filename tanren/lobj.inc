; lobj.inc - public interface of lobj.as: reading a .tro.
;
; lobj.as includes this file too: it defines LOBJ_INCLUDED first, which
; skips the external declarations below.
;
; The format is tatara-obj-spec.md draft 2. objout.as writes it and
; this module reads it, and the only contract between them is that
; document - which is why the reader was checked against
; the writer and found DATA's content length stated as length-5 where
; it is length-3.

		ifndef	LOBJ_INCLUDED

; objfile_open		open the file named at DE and check "TRO",
;			the 1Ah and the version byte.
;			In:  DE -> ASCIIZ name
;
; objfile_next_record	the next record's header.
;			Out: CY set = no more records;
;			     objfile_record_type and
;			     objfile_record_left are set
;
; objfile_read_payload	A bytes of the open record's payload.
;			In:  A  = how many, 1 to 255
;			     DE -> where they go
;
; objfile_read_string	one string - a length byte and that many
;			bytes - into objfile_string_buffer,
;			zero-terminated for print_zero_string
;
; objfile_skip_record	whatever is left of the open record. A
;			FORWARD SEEK, not a read: skipping
;			tatara.tro's DATA would move 6 KB for
;			nothing
;
; objfile_at_eof		after the last record: is that the end of
;			the file?
;			Out: CY set = bytes follow;
;			     objfile_bytes_read = how many
;
; objfile_close		close the file
;
; objfile_record_type	the open record's type, and how much of its
; objfile_record_left	payload has not been read (a WORD)
;
; objfile_string_buffer	where objfile_read_string puts a name, and
; objfile_string_length	how long it is. BOTH are both: a name goes
;			into a table's key, and a key is counted


		extrn objfile_open
		extrn objfile_next_record
		extrn objfile_read_payload
		extrn objfile_read_string
		extrn objfile_skip_record
		extrn objfile_at_eof
		extrn objfile_close
		extrn objfile_record_type
		extrn objfile_record_left
		extrn objfile_string_buffer
		extrn objfile_string_length
		endif

					; THE BIGGEST THING A RECORD HOLDS
					; WHOLE:
OBJFILE_STRING_SIZE		equ	256
				; a string is at most 255 bytes, plus the
				;  terminator objfile_read_string adds. DATA is
				;  skipped
				; here and copied in chunks later, so it
				; never needs to be resident
TRO_VERSION		equ	002h	; the file version this linker reads

RECORD_MODULE		equ	001h	; the record types, from the spec (11).
RECORD_GROUP		equ	002h	;   The writer's copy is in objout.inc;
					; they are repeated rather than shared
RECORD_SEGMENT		equ	003h
					; because a reader and a writer of the
RECORD_PUBLIC		equ	004h
					; same format are two programs, and the
RECORD_EXTERNAL		equ	005h
RECORD_DATA		equ	006h	;   document is what keeps them honest
RECORD_RELOC	equ	007h
RECORD_ENTRY		equ	008h
RECORD_COMMENT		equ	07fh
RECORD_END		equ	0ffh
