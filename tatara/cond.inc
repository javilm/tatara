; cond.inc - public interface of cond.as: conditional assembly.
;
; cond.as includes this file too, for the shared equates: it defines
; CNDLIB first, which skips the external declarations below - a symbol
; cannot be declared external in the module that defines it as global.

		ifndef	CNDLIB
		extrn cndinit		; no conditionals open. Per PASS, like
					;   macinit and mexinit
		extrn cndline		; act on a line's conditional directive
					; in:  A  = the directive number
					;      IX -> the field block
					; out: CY set = the line produces
					;               nothing
		extrn cndeof		; the end of the source: nothing may
					;   still be open
		extrn cndlab		; was the line just read being
					; assembled? A byte, written by
					; cndskip: 0FFh yes, 0 no. main.loop
					; reads it after cndline has returned,
					; to decide whether a label on an IF,
					; ELSE or ENDIF line is defined - by
					; then the state it was decided by has
					; already changed
		extrn cnddep		; how many conditionals are open. A
					; variable, not a routine: EXITM has to
					; unwind the ones its expansion opened,
					; and MX_CDEP is the depth it started at
		endif

MAXCND		equ	16	; how deeply conditionals may nest. M80 says
				; "any level"; ours costs a byte each and
				; needs a limit to guard the stack

; --- the state of one open conditional.
;
;     An IF met while we are already skipping is pushed as CS_DONE, never
;     CS_SKIP: neither of its branches may be taken, and no ELSE of its
;     may rescue it. That is what makes the innermost state enough to
;     answer "are we emitting?" without walking the stack.

CS_TAKE		equ	0	; this branch is being emitted
CS_SKIP		equ	1	; skipping, but an ELSE could still be taken
CS_DONE		equ	2	; a branch was taken already, or the whole IF
				;   is inside a skipped region: skip to ENDIF
CS_ELSE		equ	080h	; bit 7: this level has already had its ELSE
