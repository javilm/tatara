; macros.inc - public interface of macros.as: macro definitions.
;
; macros.as includes this files too: it defines MACROS_INCLUDED first, which
; skips the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.

		ifndef	MACROS_INCLUDED
		extrn macro_table_init	; format the name table. ONCE PER RUN,
					; beside symbol_table_init: dseg space
					; is not written to the object file, so
					; the bucket array holds garbage until
					; this has run
		extrn macro_table_reset	; free every definition and empty the
					; table. ONCE PER PASS: pass 2 must start
					; where pass 1 did, or a macro called
					; before it is defined behaves differently
					; on the two passes
		extrn collect_macro	; collect one macro definition
					; in:  HL -> a line buffer to use
					; out: CY clear = collected, ENDM
					;                 consumed
		extrn collect_block	; collect an unnamed body: REPT, and
					; IRP and IRPC
					; in:  HL -> a line buffer
					;      A   = MACRO_KIND
					; out: HL -> the descriptor's far
					;            pointer
		extrn list_macros	; every macro's NAME, sixteen
					; columns each, for the listing's
					; last page. M80 lists the names
					; there and nothing else
		extrn dump_macro	; print the definition just stored, for
					; /M. Valid only immediately after
					; collect_macro returns
		extrn find_macro	; is this operation a macro's name?
					; in:  DE -> the text, B = its length
					;      HL -> a 4-byte buffer
					; out: CY clear = yes, and the buffer
					;                 holds the descriptor
		extrn descriptor_name	; the other direction: what is this
					; descriptor called? O(n) - it walks the
					; whole table - so errs.as is the only
					; caller, once, with the program about to
					; stop
					; in:  HL -> its 4-byte far pointer
					; out: CY clear = DE -> the name, zero-
					;                 terminated
					;      CY set   = nothing names it: it is
					;                 anonymous or orphaned,
					;                 and MACRO_KIND says
					;                 which
		endif
