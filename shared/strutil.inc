; strutil.inc - public interface of strutil.as: small string helpers.
;
; strutil.as includes this file too: it defines STRUTIL_INCLUDED
; first, which skips
; the external declaration below - a symbol cannot be declared external in
; the module that defines it as global.

		ifndef	STRUTIL_INCLUDED
		extrn is_absolute_name	; is this name absolute - a leading
					; separator, or a drive letter?
					; in:  DE -> an ASCIIZ name
					; out: CY set = it is
		extrn directory_length	; how much of a name is the directory
					; part: up to and INCLUDING the last
					; separator, or none at all
					; in:  DE -> an ASCIIZ name
					; out: A = how many bytes, 0 = none
		extrn compose_path	; prefix + separator + name, into
					; path_buffer. The prefix ends at a
					; zero OR
					; a semicolon, so one entry of a
					; ";"-separated path list is a prefix
					; without being copied out of it first
					; in:  HL -> the prefix
					;      DE -> the name, ASCIIZ
					; out: CY clear = path_buffer holds it
					;      HL -> the prefix's terminator,
					;      either way
		extrn path_buffer
				; where compose_path puts it. ONE buffer:
					; every caller opens it at once and
					; none of them keeps it
		extrn fold_to_upper	; fold the character in A from a-z to
					; A-Z; anything else passes through
					; unchanged
					; in:  A = character
					; out: A = folded character
		extrn find_extension	; where a filename's extension
					; starts: the last dot after the
					; last separator
					; in:  DE -> an ASCIIZ name
					; out: CY clear = HL -> the dot
					;      CY set   = it has none, and
					;      HL -> the terminator
		extrn add_default_extension
					; a default extension, on a name
					; that has none
					; in:  DE -> the name, ASCIIZ
					;      HL -> a dot, three
					;      characters and a zero
		extrn parse_hex_number	; one to four hex digits, as a
					; number. A LINKER OPTION IS NOT
					; AN EXPRESSION: no suffix, no
					; decimal, and a fifth digit is
					; not an address
					; in:  DE -> the digits, ASCIIZ
					; out: CY clear = HL is it
					;      CY set   = it is not one
		extrn build_decimal	; HL in decimal, no leading zeros,
					; into a buffer
					; in:  HL = the number
					;      DE -> a buffer, 5 bytes
					; out: A  = how many digits, 1 to 5,
					;           written at its start
		extrn build_hex_word	; HL as FOUR hex digits, no leading
					; zeros suppressed - a listing column
					; that changes width cannot be read
					; down
					; in:  HL = the number
					;      DE -> where
					; out: DE has moved on by four
		extrn build_hex_byte	; A as TWO
					; in:  A  = the number
					;      DE -> where
					; out: DE has moved on by two
		endif

DOS_PATH_MAX	equ	64	; longest drive/path/file, and a terminator.
				;   MSX-DOS 2 returns .PLONG for "longer than
				;   63 characters", so this is the machine's
				;   number and not a choice - which is why it
				;   is not cmdline.inc's PATH_MAX, a different
				;   128 measuring the command tail. ALSO A
				;   POWER OF TWO: source_directory_address
				;   shifts. Moved here from srcline.inc, when
				;   the linker started composing paths too
