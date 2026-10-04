; dirtab.as - directive names to directive numbers.
;
; Everything above this module works with a number, not with text: the
; comparison happens once, here, and every later phase switches on the
; result.

DIRTAB_INCLUDED	equ	1	; skips the external in dirtab.inc

		public	find_directive

		include	dirtab.inc
		include	strutil.inc

		cseg

; find_directive - is this operation one of Tatara's directives?
;
;   The names are compared ignoring case, one character at a time, so no
;   upper-case copy of the line is made anywhere.
;
;   The table is walked from the top. About fifty entries, most of them
;   rejected on their length byte alone. A binary search would be faster
;   and longer, and on this machine memory is what is scarce, not time -
;   so the smallest code that answers the question wins.
;
; Input:	DE -> the operation text, NOT zero-terminated
;		B   = how many characters it has
; Output:	A     = the directive number, or DIRECTIVE_NONE (0)
;		Z set = not a directive
; Modifies:	AF, BC, DE, HL

find_directive:
		ld	hl,directive_table	; HL walks the table

find_directive.next:
		ld	a,(hl)		; this entry's length byte
		or	a
		ret	z		; the end marker: A = 0 = not found
		cp	b
		jr	z,find_directive.compare

find_directive.skip:
		ld	a,(hl)		; over length + name + number
		add	a,2
		add	a,l
		ld	l,a
		jr	nc,find_directive.next
		inc	h
		jr	find_directive.next

find_directive.compare:
		push	hl		; the entry, in case it does not match
		push	de		; and the operation text
		ld	c,b		; C = characters left to compare

find_directive.compare_char:
		inc	hl		; HL -> the next character of the name
		ld	a,(de)
		call	fold_to_upper	; fold to upper case: the table is
		cp	(hl)		;   stored in upper case
		jr	nz,find_directive.no_match
		inc	de
		dec	c
		jr	nz,find_directive.compare_char
		inc	hl		; past the last character of the name
		ld	a,(hl)		; the directive number lives there
		pop	de
		pop	hl
		or	a		; Z clear: no directive is numbered 0
		ret

find_directive.no_match:
		pop	de
		pop	hl
		jr	find_directive.skip

		dseg

; Variables for find_directive:
;
; directive_table	a length byte, the name in UPPER CASE, and the
;			number. A length byte of 0 ends it
;
; Several M80 directives have more than one spelling, and the aliases
; just carry the same number: IFT is IF, IFF is IFE, COND is IF.
;
; Three more M80 spellings are deliberately left out for now - MACLIB
; and $INCLUDE (both synonyms for INCLUDE) and ENDC (a synonym for
; ENDIF). They are real, and each is one line when they are wanted.

directive_table:
		defb	5,	"MACRO",	DIRECTIVE_MACRO
		defb	4,	"ENDM",		DIRECTIVE_ENDM
		defb	5,	"LOCAL",	DIRECTIVE_LOCAL
		defb	4,	"REPT",		DIRECTIVE_REPT
		defb	3,	"IRP",		DIRECTIVE_IRP
		defb	4,	"IRPC",		DIRECTIVE_IRPC
		defb	5,	"EXITM",	DIRECTIVE_EXITM
		defb	2,	"IF",		DIRECTIVE_IF
		defb	3,	"IFT",		DIRECTIVE_IF
		defb	4,	"COND",		DIRECTIVE_IF
		defb	3,	"IFE",		DIRECTIVE_IFE
		defb	3,	"IFF",		DIRECTIVE_IFE
		defb	5,	"IFDEF",	DIRECTIVE_IFDEF
		defb	6,	"IFNDEF",	DIRECTIVE_IFNDEF
		defb	3,	"IFB",		DIRECTIVE_IFB
		defb	4,	"IFNB",		DIRECTIVE_IFNB
		defb	5,	"IFIDN",	DIRECTIVE_IFIDN
		defb	5,	"IFDIF",	DIRECTIVE_IFDIF
		defb	3,	"IF1",		DIRECTIVE_IF1
		defb	3,	"IF2",		DIRECTIVE_IF2
		defb	4,	"ELSE",		DIRECTIVE_ELSE
		defb	5,	"ENDIF",	DIRECTIVE_ENDIF
		defb	7,	"INCLUDE",	DIRECTIVE_INCL
		defb	3,	"END",		DIRECTIVE_END
		defb	4,	"DEFL",		DIRECTIVE_SET
					; SET IS NOT IN THIS TABLE. In .Z80
					;   mode M80 has no SET pseudo-op at
					;   all: "foo set 5" is a fatal error
					;   there and "set 7,a" is the bit
					;   instruction. DEFL is the
					;   redefinable symbol, and the only
					;   one. After assuming the opposite
					;   and being told otherwise by M80
		defb	3,	"ORG",		DIRECTIVE_ORG
		defb	2,	"DS",		DIRECTIVE_DS
		defb	4,	"DEFS",		DIRECTIVE_DS
		defb	4,	"ASEG",		DIRECTIVE_ASEG
		defb	4,	"CSEG",		DIRECTIVE_CSEG
		defb	4,	"DSEG",		DIRECTIVE_DSEG
		defb	5,	"GROUP",	DIRECTIVE_GROUP
		defb	3,	"EQU",		DIRECTIVE_EQU
		defb	6,	"PUBLIC",	DIRECTIVE_PUBLIC
		defb	5,	"ENTRY",	DIRECTIVE_PUBLIC
		defb	5,	"EXTRN",	DIRECTIVE_EXTRN
		defb	3,	"EXT",		DIRECTIVE_EXTRN
		defb	2,	"DB",		DIRECTIVE_DB
		defb	4,	"DEFB",		DIRECTIVE_DB
		defb	4,	"DEFM",		DIRECTIVE_DB
		defb	2,	"DW",		DIRECTIVE_DW
		defb	4,	"DEFW",		DIRECTIVE_DW
		defb	2,	"DC",		DIRECTIVE_DC
		defb	5,	".LIST",	DIRECTIVE_LIST
		defb	6,	".XLIST",	DIRECTIVE_XLIST
		defb	5,	".LALL",	DIRECTIVE_LALL
		defb	5,	".SALL",	DIRECTIVE_SALL
		defb	5,	".XALL",	DIRECTIVE_XALL
		defb	7,	".LFCOND",	DIRECTIVE_LFCOND
		defb	7,	".SFCOND",	DIRECTIVE_SFCOND
		defb	7,	".TFCOND",	DIRECTIVE_TFCOND
		defb	5,	"TITLE",	DIRECTIVE_TITLE
		defb	6,	"SUBTTL",	DIRECTIVE_SUBTTL
		defb	4,	"PAGE",		DIRECTIVE_PAGE
		defb	6,	"*EJECT",	DIRECTIVE_PAGE
		defb	6,	"$EJECT",	DIRECTIVE_PAGE
		defb	0		; the end of the table
