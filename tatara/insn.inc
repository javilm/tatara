; insn.inc - public interface of insn.as: the class handlers.
;
; insn.as includes this file too: it defines INSNLIB first, which skips
; the external declaration below.

		ifndef	INSNLIB

		extrn insnline		; if this line's operation is an
					; instruction, measure it and move
					; the location counter
					; in:  IX -> the line's field block
					; out: CY set = not an instruction,
					;          and nothing has changed
		endif
