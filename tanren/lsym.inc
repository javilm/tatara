; lsym.inc - public interface of lsym.as: the link's symbols.
;
; ONE TABLE, NOT TWO. A public and an external are two statements
; about one symbol, so they share a record and a flags byte says
; which statements have been made. "What is missing?" is then a
; single walk looking for referenced-and-not-defined, rather than a
; comparison between two collections.

		ifndef	LSYM_INCLUDED

		extrn symbols_init		; the table, empty, in the
					; default case mode
		extrn symbols_set_case	; MODNAME's flags byte: the mode
					; on the first module, and the
					; mixture check on every one after
					; in:  A = the flags byte
					; (error_case_mismatch does not return)
		extrn symbols_add_public		; a PUBDEF entry
					;  in: public_segment_offset = segment,
					;  offset
					;      objfile_string_buffer = the name
					; (error_duplicate_public does not
					; return)
		extrn symbols_add_external		; an EXTDEF entry
					; in:  objfile_string_buffer = the name
		extrn symbols_relocate		; EVERY DEFINED, NON-ABSOLUTE
					; SYMBOL: its value plus its
					; segment's base, which is an
					; address. AFTER place_segments
		extrn symbols_value	; PASS 2: the final value of the
					; name in objfile_string_buffer.
					; Every EXTDEF name is in the
					; table by then
					; and symbols_relocate has made every
					; value an address
					;  in: objfile_string_buffer,
					;  objfile_string_length
					; out: HL = its value
		extrn symbols_check		; END OF PASS 1: name every
					; external nobody defined - ALL of
					; them - and stop if there were
					; any
					; (error_undefined_symbols does not
					; return)
		extrn symbols_set_module
					; a module is starting: keep its
					; name, for the messages that have
					; to say which module
					;  in: objfile_string_buffer,
					;  objfile_string_length
		extrn symbols_dump		; /M: the symbols
					; a PUBDEF's segment and offset,
		extrn public_segment_offset
					; read before its name
		endif

SYMBOL_DEFINED		equ	001h	; some module defines it
SYMBOL_REFERENCED		equ	002h	; some module wants it
SYMBOL_ABSOLUTE		equ	004h	; its value is an address already, and
				; the layout must NOT add a segment's base
SYMBOL_BUCKETS		equ	64	; buckets. tatara.as alone declares 182
				; externals, so this table is the biggest
				; of the three by an order of magnitude
					; flags, value (2), the segment (4)
SYMBOL_RECORD_SIZE		equ	7
					; the current module's name, kept for
					; the
MODULE_NAME_MAX		equ	16
				; messages that name one. Cut, not refused
