; expand.inc - public interface of expand.as: macro expansion.
;
; expand.as includes this file too: it defines EXPLIB first, which skips
; the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.

		ifndef	EXPLIB
		extrn mexinit		; the ??nnnn counter, once per pass
		extrn mexnew		; start expanding a macro: parse the
					; call's arguments, build the expansion
					; record, push it on the line source
					; stack
					; in:  HL -> the descriptor's far pointer
					;      DE -> the call's argument text
					;      A   = how many characters of it
					;      curfile/curline = where the call
					;                        was
					; out: CY clear = pushed, or the body was
					;                 empty and nothing was
		extrn mexrept		; the same for an unnamed body, replayed
					; n times
					; in:  HL -> the descriptor's far pointer
					;      BC = iterations
		extrn mxpitem		; build an IRP or IRPC item block, which
					; has to happen before the body is
					; collected: the items are in linebuf and
					; macrept reuses it for every body line
					; out: BC = iterations
		extrn mexitm		; EXITM: abandon the expansion on top of
					; the stack, including any rounds not yet
					; run, and unwind its conditionals
		extrn mexline		; the next line of the expansion on top
					; of the stack. getline dispatches here
					; when LS_KIND is LSK_MACRO
					; out: CY set = this source is finished
		extrn mxbfree		; free a descriptor and its body blocks
					; in:  HL -> its far pointer
		endif
