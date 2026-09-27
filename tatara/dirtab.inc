; dirtab.inc - public interface of dirtab.as: directive names to numbers.
;
; dirtab.as includes this file too, for the numbers: it defines DIRLIB
; first, which skips the external declaration below - a symbol cannot be
; declared external in the module that defines it as global.

		ifndef	DIRLIB
		extrn dirlook		; is this operation a directive?
					; in:  DE -> the text
					;      B   = length
					; out: A     = the number, 0 = it's not
					;      Z set = not a directive
		endif

; --- the directive numbers. D_NONE is 0 so that "not found" and "there
;     was no operation to look up" are the same answer.
;
;     Everything pass 0 has to recognise is here already, even though most
;     of these do nothing unitl the phase that needs them. The table is
;     data, and adding names later is cheaper than adding them twice.

D_NONE		equ	0	; not a directive

D_MACRO		equ	1	; name MACRO p1,p2
D_ENDM		equ	2	; the end of a definition
D_LOCAL		equ	3	; labels unique to one expansion
D_REPT		equ	4	; repeat a block n times
D_IRP		equ	5	; repeat a once per argument
D_IRPC		equ	6	; repeat once per character
D_EXITM		equ	7	; leave an expansion early

D_IF		equ	8	; the conditional family
D_IFE		equ	9	; ... true when the expression is zero
D_IFDEF		equ	10
D_IFNDEF	equ	11
D_IFB		equ	12	; ... true when the argument is blank
D_IFNB		equ	13
D_IFIDN		equ	14	; ... true when two arguments are identical
D_IFDIF		equ	15
D_IF1		equ	16	; ... true on pass 1
D_IF2		equ	17
D_ELSE		equ	18
D_ENDIF		equ	19

D_INCL		equ	20	; read another file here
D_END		equ	21	; the end of the source

D_SET		equ	22	; name SET n, or DEFL - a symbol
				;   that may be redefined

D_ORG		equ	23	; set the location counter
D_DS		equ	24	; advance it by n bytes. DEFS is
				;   M80's own alias and shares the number
D_ASEG		equ	25	; the absolute segment. ASEG,
D_CSEG		equ	26	;   CSEG and DSEG MUST stay consecutive and
D_DSEG		equ	27	;   in this order - the driver subtracts
				;   D_ASEG to get SY_ABS, SY_CODE, SY_DATA
D_GROUP		equ	28	; open a coexistence group
				;   inside a transient DSEG
D_EQU		equ	29	; a name with a fixed value
D_PUBLIC	equ	30	; offered to other modules.
				;   ENTRY is M80's own alias
D_EXTRN		equ	31	; defined in another module.
				;   EXT is M80's own alias
D_DB		equ	32	; bytes. DEFB and DEFM are
				;   M80's own aliases
D_DW		equ	33	; words. DEFW is M80's alias
D_DC		equ	34	; a string, with the last
D_LIST		equ	35	; .LIST, the listing back on
D_XLIST		equ	36	; .XLIST, and off
D_LALL		equ	37	; .LALL, .SALL and .XALL MUST stay
D_SALL		equ	38	;   consecutive and in this order: the
D_XALL		equ	39	;   handler is "sub D_LALL" and what is
				;   left is the mode. Same trick as
				;   D_ASEG/D_CSEG/D_DSEG
D_LFCOND	equ	40	; list the lines in a branch that
D_SFCOND	equ	41	;   was not taken, or do not, or flip
D_TFCOND	equ	42	;   whichever is in force. Consecutive,
				;   and D_LIST to D_TFCOND is now the
				;   whole listing-control range
				;   byte's high bit set
D_TITLE		equ	43	; the header's left-hand field,
D_SUBTTL	equ	44	;   and the line under it. CONSECUTIVE
				;   and in this order: main.titl is
				;   "sub D_TITLE" and what is left is
				;   which of the two
D_PAGE		equ	45	; break the page, or say how long one
				;   is - PAGE and PAGE expr
