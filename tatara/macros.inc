; macros.inc - public interface of macros.as: macro definitions.
;
; macros.as includes this files too: it defines MACSLIB first, which skips
; the external declarations below - a symbol cannot be declared external in
; the module that defines it as global.

		ifndef	MACSLIB
		extrn macinit		; format the name table. ONCE PER RUN,
					; beside syminit: dseg space is not
					; written to the object file, so the
					; bucket array holds garbage until this
					; has run
		extrn macrst		; free every definition and empty the
					; table. ONCE PER PASS: pass 2 must start
					; where pass 1 did, or a macro called
					; before it is defined behaves differently
					; on the two passes
		extrn macdef		; collect one macro definition
					; in:  HL -> a line buffer to use
					; out: CY clear = collected, ENDM
					;                 consumed
		extrn macrept		; collect an unnamed body: REPT, and
					; IRP and IRPC
					; in:  HL -> a line buffer
					;      A   = MD_KIND
					; out: HL -> the descriptor's far
					;            pointer
		extrn lstmacs		; every macro's NAME, sixteen
					; columns each, for the listing's
					; last page. M80 lists the names
					; there and nothing else
		extrn macdump		; print the definition just stored,		; every macro's NAME, sixteen
					; columns each, for the listing's
					; last page. M80 lists the names
					; there and nothing else
					; for /M. Valid only immediately after
					; macdef returns
		extrn macfind		; is this operation a macro's name?
					; in:  DE -> the text, B = its length
					;      HL -> a 4-byte buffer
					; out: CY clear = yes, and the buffer
					;                 holds the descriptor
		extrn macname		; the other direction: what is this
					; descriptor called? O(n) - it walks the
					; whole table - so errs.as is the only
					; caller, once, with the program about to
					; stop
					; in:  HL -> its 4-byte far pointer
					; out: CY clear = DE -> the name, zero-
					;                 terminated
					;      CY set   = nothing names it: it is
					;                 anonymous or orphaned,
					;                 and MD_KIND says which
		endif
