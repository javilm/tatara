; cond.inc - public interface of cond.as: conditional assembly.
;
; cond.as includes this file too, for the shared equates: it defines
; COND_INCLUDED first, which skips the external declarations below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	COND_INCLUDED
		extrn cond_init		; no conditionals open. Per PASS, like
					;   macro_table_init and expand_init
		extrn cond_line		; act on a line's conditional directive
					; in:  A  = the directive number
					;      IX -> the field block
					; out: CY set = the line produces
					;               nothing
		extrn cond_eof		; the end of the source: nothing may
					;   still be open
		extrn cond_label_assembled	; was the line just read being
					; assembled? A byte, written by
					; cond_skipping: 0FFh yes, 0 no.
					; main.next_line reads it after
					; cond_line has returned, to decide
					; whether a label on an IF, ELSE or
					; ENDIF line is defined - by then the
					; state it was decided by has already
					; changed
		extrn cond_depth	; how many conditionals are open. A
					; variable, not a routine: EXITM has to
					; unwind the ones its expansion opened,
					; and EXPANSION_COND_DEPTH is the depth
					; it started at
		endif

COND_MAX_DEPTH	equ	16	; how deeply conditionals may nest. M80 says
				; "any level"; ours costs a byte each and
				; needs a limit to guard the stack

; --- the state of one open conditional.
;
;     An IF met while we are already skipping is pushed as COND_DONE, never
;     COND_SKIP: neither of its branches may be taken, and no ELSE of its
;     may rescue it. That is what makes the innermost state enough to
;     answer "are we emitting?" without walking the stack.

COND_TAKE	equ	0	; this branch is being emitted
COND_SKIP	equ	1	; skipping, but an ELSE could still be taken
COND_DONE	equ	2	; a branch was taken already, or the whole IF
				;   is inside a skipped region: skip to ENDIF
COND_ELSE_SEEN	equ	080h	; bit 7: this level has already had its ELSE
