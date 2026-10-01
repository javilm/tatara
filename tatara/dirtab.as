; dirtab.as - directive names to directive numbers.
;
; Everything above this module works with a number, not with text: the
; comparison happens once, here, and every later phase switches on the
; result.

DIRLIB		equ	1		; skips the external in dirtab.inc

		public	dirlook

		include	dirtab.inc
		include	strutil.inc

		cseg

; dirlook - is this operation one of Tatara's directives?
;
;   The names are compared ignoring case, one character at a time, so no
;   upper-case copy of the line is made anywhere.
;
;   The table is walked from the top. About twenty-five entries, most of
;   them rejected on their length byte alone. A binary search would be 
;   faster and longer, and on this machine memory is what is scarce, not
;   time - so the smallest code that answers the question wins.
;
; Input:	DE -> the operaetion text, NOT zero-terminated
;		B   = how many characters it has
; Output:	A     = the directive number, or D_NONE (0)
;		Z set = not a directive
; Modifies:	AF, BC, DE, HL

dirlook:	ld	hl,dirtab	; HL walks the table
dirlook.ent:	ld	a,(hl)		; this entry's length byte
		or	a
		ret	z		; the end marker: A = 0 = D_NONE
		cp	b
		jr	z,dirlook.try	; same length: worth comparing
dirlook.next:	ld	a,(hl)		; step over length + name + number
		add	a,2
		add	a,l
		ld	l,a
		jr	nc,dirlook.ent
		inc	h
		jr	dirlook.ent

dirlook.try:	push	hl		; the entry, in case it does not match
		push	de		; and the operation text
		ld	c,b		; C = characters left to compare
dirlook.ch:	inc	hl		; HL -> the next character of the name
		ld	a,(de)
		call	strupr		; fold to upper case: the table is
		cp	(hl)		; stored in upper case
		jr	nz,dirlook.no
		inc	de
		dec	c
		jr	nz,dirlook.ch
		inc	hl		; past the last character of the name
		ld	a,(hl)		; the directive number lives there
		pop	de
		pop	hl
		or	a		; Z clear: no directive is numbered 0
		ret

dirlook.no:	pop	de
		pop	hl
		jr	dirlook.next

		dseg

; The table: a length byte, the name in UPPER CASE, and the number.
; A length byte of 0 ends it.
;
; Several M80 directives have more than one spelling, and the aliases just
; carry the same number: IFT is IF, IFF is IFE, COND is IF.
;
; Three more M80 spellings are deliverately left out for now - MACLIB and
; $INCLUDE (both synonyms for INCLUDE) and ENDC (a synonym for ENDIF).
; They are real, and each is one line when they are wanted.

dirtab:		defb	5,	"MACRO",	D_MACRO
		defb	4,	"ENDM",		D_ENDM
		defb	5,	"LOCAL",	D_LOCAL
		defb	4,	"REPT",		D_REPT
		defb	3,	"IRP",		D_IRP
		defb	4,	"IRPC",		D_IRPC
		defb	5,	"EXITM",	D_EXITM
		defb	2,	"IF",		D_IF
		defb	3,	"IFT",		D_IF
		defb	4,	"COND",		D_IF
		defb	3,	"IFE",		D_IFE
		defb	3,	"IFF",		D_IFE
		defb	5,	"IFDEF",	D_IFDEF
		defb	6,	"IFNDEF",	D_IFNDEF
		defb	3,	"IFB",		D_IFB
		defb	4,	"IFNB",		D_IFNB
		defb	5,	"IFIDN",	D_IFIDN
		defb	5,	"IFDIF",	D_IFDIF
		defb	3,	"IF1",		D_IF1
		defb	3,	"IF2",		D_IF2
		defb	4,	"ELSE",		D_ELSE
		defb	5,	"ENDIF",	D_ENDIF
		defb	7,	"INCLUDE",	D_INCL
		defb	3,	"END",		D_END
		defb	4,	"DEFL",		D_SET
					; SET IS NOT IN THIS TABLE. In .Z80
					;   mode M80 has no SET pseudo-op at
					;   all: "foo set 5" is a fatal error
					;   there and "set 7,a" is the bit
					;   instruction. DEFL is the
					;   redefinable symbol, and the only
					;   one. After assuming the
					;   opposite and being told otherwise
					;   by M80
		defb	3,	"ORG",		D_ORG
		defb	2,	"DS",		D_DS
		defb	4,	"DEFS",		D_DS
		defb	4,	"ASEG",		D_ASEG
		defb	4,	"CSEG",		D_CSEG
		defb	4,	"DSEG",		D_DSEG
		defb	5,	"GROUP",	D_GROUP
		defb	3,	"EQU",		D_EQU
		defb	6,	"PUBLIC",	D_PUBLIC
		defb	5,	"ENTRY",	D_PUBLIC
		defb	5,	"EXTRN",	D_EXTRN
		defb	3,	"EXT",		D_EXTRN
		defb	2,	"DB",		D_DB
		defb	4,	"DEFB",		D_DB
		defb	4,	"DEFM",		D_DB
		defb	2,	"DW",		D_DW
		defb	4,	"DEFW",		D_DW
		defb	2,	"DC",		D_DC
		defb	5,	".LIST",	D_LIST
		defb	6,	".XLIST",	D_XLIST
		defb	5,	".LALL",	D_LALL
		defb	5,	".SALL",	D_SALL
		defb	5,	".XALL",	D_XALL
		defb	7,	".LFCOND",	D_LFCOND
		defb	7,	".SFCOND",	D_SFCOND
		defb	7,	".TFCOND",	D_TFCOND
		defb	5,	"TITLE",	D_TITLE
		defb	6,	"SUBTTL",	D_SUBTTL
		defb	4,	"PAGE",		D_PAGE
		defb	6,	"*EJECT",	D_PAGE
		defb	6,	"$EJECT",	D_PAGE
		defb	0		; the end of the table
