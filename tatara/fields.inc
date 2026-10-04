; fields.inc - public interface of fields.as: cutting a source line into
; label / operation / operand / comment.
;
; fields.as includes this file too, for the shared equates: it defines
; FIELDS_INCLUDED first, which skips the external declarations below - a symbo
; cannot be declared external in the module that defines it as global.

		ifndef	FIELDS_INCLUDED
		extrn split_line	; cut one line into its four fields
					; in: HL -> the line, ASCIIZ
					;     IX -> a field block to fill
		endif

; --- one field block. Each field is an address into the caller's line
;     buffer and a length; a length of 0 means the field is not on this
;     line. Nothing is copied - the block describes the line, it does not
;     hold it, and it stops being true the moment the caller reads the
;     next line.
;
;     One byte is enough for every length because LINE_MAX is 255.

FIELD_LABEL	equ	0		; +0 label:     address
FIELD_LABEL_LENGTH	equ	2	; +2            length
FIELD_OPERATION	equ	3		; +3 operation: address
FIELD_OPERATION_LENGTH	equ	5	; +5            length
FIELD_OPERAND	equ	6		; +6 operand:   address
FIELD_OPERAND_LENGTH	equ	8	; +8            length
FIELD_COMMENT	equ	9		; +9 comment:   address, ";" included
FIELD_COMMENT_LENGTH	equ	11	; +11           length
FIELD_BLOCK_SIZE	equ	12	; size of one field block

