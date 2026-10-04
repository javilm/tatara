; expand.inc - public interface of expand.as: macro expansion.
;
; expand.as includes this file too: it defines EXPAND_INCLUDED first, which
; skips the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.

		ifndef	EXPAND_INCLUDED
		extrn expand_init	; the ??nnnn counter, once per pass
		extrn expand_start	; start expanding a macro: parse the
					; call's arguments, build the expansion
					; record, push it on the line source
					; stack
					; in:  HL -> the descriptor's far pointer
					;      DE -> the call's argument text
					;      A   = how many characters of it
					;      current_file/current_line =
					;      where the call was out: CY clear
					;      = pushed, or the body was empty
					;      and nothing was
		extrn expand_start_repeat
				; the same for an unnamed body, replayed
					; n times
					; in:  HL -> the descriptor's far pointer
					;      BC = iterations
		extrn build_item_block
				; build an IRP or IRPC item block, which
					; has to happen before the body is
					; collected: the items are in
					; line_buffer and collect_block reuses
					; it for every body line out: BC =
					; iterations
		extrn expand_exit
				; EXITM: abandon the expansion on top of
					; the stack, including any rounds not yet
					; run, and unwind its conditionals
		extrn expand_line	; the next line of the expansion on top
					; of the stack. next_source_line
					; dispatches here when SOURCE_KIND is
					; SOURCE_IS_MACRO out: CY set = this
					; source is finished
		extrn free_descriptor	; free a descriptor and its body blocks
					; in:  HL -> its far pointer
		endif
