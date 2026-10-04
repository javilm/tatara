; lerrs.inc - public interface of lerrs.as: TANREN's errors.
;
; lerrs.as includes this file too: it defines LERRS_INCLUDED first, which
; skips the external declarations below.
;
; SEPARATE FROM errs.as ON PURPOSE. The assembler's error module is
; about 2.5 KB of messages about macros, conditionals and expressions,
; and the linker would carry every byte of it to print none of them.
; Nothing shared calls into either one - alloc.as, hash.as, msxdos.as
; and strutil.as all answer with carry and let the caller decide.
;
; NONE OF THESE RETURN.

		ifndef	LERRS_INCLUDED

		extrn error_cannot_open
					; the object file will not open
		extrn error_not_object_file
					; the first five bytes are not a
					; Tatara object file's
		extrn error_wrong_version
					; they are, but the version byte is
					; not one this linker knows
		extrn error_truncated
					; the file ends inside a record, or
					; a record claims a length the file
					; does not have
		extrn error_unknown_option
					; an option we do not know
		extrn error_out_of_memory
					; the mapper is full: a table
					; record would not fit
		extrn error_too_many_segments
					; more segments or groups in one
					; module than its maps hold
		extrn error_data_overlaps_code
					; /D: put the data on top of the
					; code
		extrn error_image_too_big
					; the image runs past FFFFh
		extrn error_duplicate_public
					; two modules define the same
					; public symbol
		extrn error_undefined_symbols
					; some external was never defined.
					;  The NAMES are printed by
					;  symbols_check before this is
					;  reached - all of them, which is
					;  the one place either program
					;  does not stop at the first
		extrn error_case_mismatch
					; a module assembled /C is being
					; linked with one that was not, or
					; the other way round. MODNAME's
					; flags byte is what says so
		extrn error_cannot_open_list
					; the response file will not
					; open, or "@" named nothing
		extrn error_nested_file_list
					; a response file holds an "@"
		extrn error_two_file_lists
					; a second "@FILE" on one command
					; line. One list, and it may not
					; name another: the objects named
					; in each are looked for in its own
					; directory, and only one of those
					; is remembered
		extrn error_too_many_words
					; more words, or a longer word,
					; than the list holds
		extrn error_env_too_long
					; the TANREN variable is too long
		extrn error_cannot_create
					; the output file cannot be
					; created
		extrn error_cannot_write
					; or cannot be written to
		extrn error_output_is_input
					; the output file is one of the
					; input files
		extrn error_too_many_externals
					; more externals in one module
					; than its map holds
		extrn error_segment_differs
					; a segment was declared with
					; different flags in another module -
					; the format document calls this a
					; link error
		endif
