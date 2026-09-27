; fields.inc - public interface of fields.as: cutting a source line into
; label / operation / operand / comment.
;
; fields.as includes this file too, for the shared equates: it defines
; FLDLIB first, which skips the external declarations below - a symbo
; cannot be declared external in the module that defines it as global.

		ifndef	FLDLIB
		extrn splitln		; cut one line into its four fields
					; in: HL -> the line, ASCIIZ
					;     IX -> a field block to fill
		endif

; --- one field block. Each field is an address into the caller's line
;     buffer and a length; a length of 0 means the field is not on this
;     line. Nothing is copied - the block describes the line, it does not
;     hold it, and it stops being true the moment the caller reads the
;     next line.
;
;     One byte is enough for every length because MAXLINE is 255.

FL_LAB		equ	0		; +0 label:     address
FL_LABL		equ	2		; +2            length
FL_OP		equ	3		; +3 operation: address
FL_OPL		equ	5		; +5            length
FL_ARG		equ	6		; +6 operand:   address
FL_ARGL		equ	8		; +8            length
FL_CMT		equ	9		; +9 comment:   address, ";" included
FL_CMTL		equ	11		; +11           length
FLSIZE		equ	12		; size of one field block

