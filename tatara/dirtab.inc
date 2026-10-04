; dirtab.inc - public interface of dirtab.as: directive names to numbers.
;
; dirtab.as includes this file too, for the numbers: it defines
; DIRTAB_INCLUDED first, which skips the external declaration below - a
; symbol cannot be declared external in the module that defines it as
; global.

		ifndef	DIRTAB_INCLUDED
		extrn find_directive	; is this operation a directive?
					; in:  DE -> the text
					;      B   = length
					; out: A     = the number, 0 = it's not
					;      Z set = not a directive
		endif

; --- the directive numbers. DIRECTIVE_NONE is 0 so that "not found" and "there
;     was no operation to look up" are the same answer.
;
;     Everything pass 0 has to recognise is here already, even though most
;     of these do nothing unitl the phase that needs them. The table is
;     data, and adding names later is cheaper than adding them twice.

DIRECTIVE_NONE	equ	0	; not a directive

DIRECTIVE_MACRO		equ	1	; name MACRO p1,p2
DIRECTIVE_ENDM		equ	2	; the end of a definition
DIRECTIVE_LOCAL		equ	3	; labels unique to one expansion
DIRECTIVE_REPT		equ	4	; repeat a block n times
DIRECTIVE_IRP		equ	5	; repeat a once per argument
DIRECTIVE_IRPC		equ	6	; repeat once per character
DIRECTIVE_EXITM		equ	7	; leave an expansion early

DIRECTIVE_IF		equ	8	; the conditional family
DIRECTIVE_IFE		equ	9	; ... true when the expression is zero
DIRECTIVE_IFDEF		equ	10
DIRECTIVE_IFNDEF	equ	11
DIRECTIVE_IFB		equ	12	; ... true when the argument is blank
DIRECTIVE_IFNB		equ	13
DIRECTIVE_IFIDN		equ	14	; ... true when the two are identical
DIRECTIVE_IFDIF		equ	15
DIRECTIVE_IF1		equ	16	; ... true on pass 1
DIRECTIVE_IF2		equ	17
DIRECTIVE_ELSE		equ	18
DIRECTIVE_ENDIF		equ	19

DIRECTIVE_INCL		equ	20	; read another file here
DIRECTIVE_END		equ	21	; the end of the source

DIRECTIVE_SET		equ	22	; name SET n, or DEFL - a symbol
				;   that may be redefined

DIRECTIVE_ORG		equ	23	; set the location counter
DIRECTIVE_DS		equ	24	; advance it by n bytes. DEFS is
				;   M80's own alias and shares the number
DIRECTIVE_ASEG		equ	25	; the absolute segment. ASEG,
DIRECTIVE_CSEG		equ	26	;   CSEG and DSEG MUST stay
DIRECTIVE_DSEG		equ	27	;   consecutive and in this order -
				;   the driver subtracts DIRECTIVE_ASEG
				;   to get SY_ABS, SY_CODE, SY_DATA
DIRECTIVE_GROUP		equ	28	; open a coexistence group
				;   inside a transient DSEG
DIRECTIVE_EQU		equ	29	; a name with a fixed value
DIRECTIVE_PUBLIC	equ	30	; offered to other modules.
				;   ENTRY is M80's own alias
DIRECTIVE_EXTRN		equ	31	; defined in another module.
				;   EXT is M80's own alias
DIRECTIVE_DB		equ	32	; bytes. DEFB and DEFM are
				;   M80's own aliases
DIRECTIVE_DW		equ	33	; words. DEFW is M80's alias
DIRECTIVE_DC		equ	34	; a string, with the last
DIRECTIVE_LIST		equ	35	; .LIST, the listing back on
DIRECTIVE_XLIST		equ	36	; .XLIST, and off
DIRECTIVE_LALL		equ	37	; .LALL, .SALL and .XALL MUST stay
DIRECTIVE_SALL		equ	38	;   consecutive and in this order: the
DIRECTIVE_XALL		equ	39	;   handler is "sub DIRECTIVE_LALL"
				;   and what is left is the mode. The
				;   same trick as DIRECTIVE_ASEG,
				;   DIRECTIVE_CSEG, DIRECTIVE_DSEG
DIRECTIVE_LFCOND	equ	40	; list the lines in a branch that
DIRECTIVE_SFCOND	equ	41	;   was not taken, or do not, or flip
DIRECTIVE_TFCOND	equ	42	;   whichever is in force. Consecutive,
				;   and DIRECTIVE_LIST to
				;   DIRECTIVE_TFCOND is now the
				;   whole listing-control range
				;   byte's high bit set
DIRECTIVE_TITLE		equ	43	; the header's left-hand field,
DIRECTIVE_SUBTTL	equ	44	;   and the line under it. CONSECUTIVE
				;   and in this order: main.title is
				;   "sub DIRECTIVE_TITLE" and what is left is
				;   which of the two
DIRECTIVE_PAGE		equ	45	; break the page, or say how long one
				;   is - PAGE and PAGE expr
