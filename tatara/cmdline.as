; cmdline.as - command tail parsing for Tatara.
;
; MSX-DOS leaves the command tail in memory and does nothing else with it:
;
;   0080h  one byte: how many characters of tail there are
;   0081h  the raw text as typed, including the space after the program name
;
; Splitting it into filenames and options is this module's job.
;
; Accepted forms:
;   TATARA TEST.AS OUT.TXT	expand TEST.AS into OUT.TXT
;   TATARA /P TEST.AS		expand TEST.AS to the screen
;   TATARA TEST.AS /P		the same - options may appear anywhere

CMDLIB		equ	1	; skips the externals in cmdline.inc

		public	cmdparse
		public	srcname
		public	dstname
		public	lstname
		public	optscrn
		public	optflds
		public	optmacs
		public	opthblk
		public	optsym
		public	optlist
		public	optcase
		public	optquiet	; /Q, /V and /?
		public	optver
		public	opthelp
		public	cmdbann		;   the banner three ways
		public	cmdver
		public	cmdusage
		public	vertxt		;   and the version, which the
					;   listing's page header writes

		include	cmdline.inc
		include	ascii.inc
		include	hash.inc	; HTCASES/HTCASEI, which optcase holds
		include	errs.inc
		include	strutil.inc
		include	msxdos.inc	; _STROUT and dosexit, for
					;   the banner and the usage screen
					;   from this module

TAILLEN		equ	00080h		; command tail: the length byte
TAILTXT		equ	00081h		; command tail: the text

SLASH		equ	"/"		; option introducer, MSX-DOS style

		cseg

; cmdparse - split the command tail into filenames and options.
;
; Input:	nothing (reads TAILLEN and TAILTXT directly)
; Output:	CY clear = usable
;		CY set   = no input filename given
;		srcname  = input filename, ASCIIZ
;		dstname  = object filename, ASCIIZ (empty if not given)
;		lstname  = listing filename, ASCIIZ (empty if not given)
;		optscrn  = 0FFh if /P was given, else 0
; Modifies:	AF, BC, DE, HL

cmdparse:	xor	a
		ld	(optscrn),a	; default: write to a file
		ld	(optsym),a	; default: no symbol dump
		ld	(optlist),a	; default: no address and byte columns
		ld	(optflds),a	; default: lines pass through whole
		ld	(optmacs),a	; default: no macro dump. This line was
		ld	(opthblk),a	; defs space is
					; not written to the object file, so
					; optmacs held whatever MSX-DOS left in
					; that byte. It read zero on every run,
					; which was luck and not a guarantee
		ld	(optquiet),a	; default: the banner is printed
		ld	(optver),a	; default: assemble, do not just say
		ld	(opthelp),a	;   what this is
		ld	a,HTCASEI	; default: case-INSENSITIVE symbols,
		ld	(optcase),a	; which is M80's behaviour (R2). Not
		xor	a		; xor a: the mode is a value and
		ld	(srcname),a	; HTCASEI is 1 and the three names
		ld	(dstname),a	;   all start empty
		ld	(lstname),a
		ld	c,a		; C = filenames seen so far
		ld	a,(TAILLEN)
		ld	b,a		; B = characters left in the tail
		ld	hl,TAILTXT	; HL = read pointer

cmdparse.word:	call	cpskipws	; step over spaces and tabs
		ld	a,b
		or	a
		jr	z,cmdparse.done	; tail exhausted
		ld	a,(hl)
		cp	SLASH
		jr	z,cmdparse.opt
		call	cpname		; a filename
		jr	cmdparse.word
cmdparse.opt:	call	cpopt		; an option
		jr	cmdparse.word

cmdparse.done:	ld	a,c
		or	a		; any filename at all? (also clears CY)
		ret	nz		; yes -> CY clear = success
		scf			; no  -> CY set   = nothing usable
		ret

; cpskipws - advance HL past spaces and tabs, keeping B in step.
;
; Input:	HL -> next character
;               B   = characters left
; Output:	HL, B advanced
;		B = 0 means the tail ran out
; Modifies:	AF, B, HL

cpskipws:	ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		cp	CHR_SPACE
		jr	z,cpskipws.adv
		cp	CHR_TAB
		ret	nz		; not whitespace -> done
cpskipws.adv:	inc	hl
		dec	b
		jr	cpskipws

; cpwend - advance HL past the rest of the current word.
;
;   Used after an option letter, so that "/PXYZ" does not confuse the
;   next round of the main loop.
;
; Input:	HL -> inside a word
;		B   = characters left
; Output:	HL -> the whitespace ending the word, or B = 0
; Modifies:	AF, B, HL

cpendw:		ld	a,b
		or	a
		ret	z
		ld	a,(hl)
		cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret	z
		inc	hl
		dec	b
		jr	cpendw

; cpopt - handle one option word. Never returns on a bad option: errunk
;   prints the message and terminates.
;
; Input:	HL -> the "/"
;		B   = characters left
; Output:	optscrn or optflds updated
;		HL, B past the word
; Modifies:	AF, B, DE, HL

cpopt:		inc	hl		; step over the "/"
		dec	b
		ld	a,b
		or	a
		jp	z,errunk	; a "/" with nothing after it
		ld	a,(hl)
		call	strupr
		cp	"P"
		jr	z,cpopt.p
		cp	"F"
		jr	z,cpopt.f
		cp	"M"
		jr	z,cpopt.m
		cp	"C"
		jr	z,cpopt.c
		cp	"H"
		jr	z,cpopt.h
		cp	"L"
		jr	z,cpopt.l
		cp	"S"
		jr	z,cpopt.s
		cp	"Q"
		jr	z,cpopt.q
		cp	"V"
		jr	z,cpopt.v
		cp	"?"		; NOT a letter, so strupr left it
		jp	nz,errunk	;   alone and this test is exact
		ld	a,0ffh
		ld	(opthelp),a
		jp	cpendw
cpopt.s:	ld	a,0ffh
		ld	(optsym),a
		jp	cpendw
cpopt.q:	ld	a,0ffh
		ld	(optquiet),a
		jp	cpendw
cpopt.v:	ld	a,0ffh
		ld	(optver),a
		jp	cpendw
cpopt.l:	ld	a,0ffh	; /L: the address and the bytes in
		ld	(optlist),a	;   front of every line, M80's shape.
		jp	cpendw		;   A switch and not the default
					;   because 140 tests read the output
					;   and a few depend on its shape -
					;   whether a real
					;   listing becomes the default
cpopt.h:	ld	a,0ffh
		ld	(opthblk),a
		jp	cpendw
cpopt.c:	ld	a,HTCASES	; /C: symbols and macro names are
		ld	(optcase),a	; case-SENSITIVE. Not directives,
		jp	cpendw		; mnemonics or registers - R2 says those
					; are insensitive in both modes
cpopt.m:	ld	a,0ffh
		ld	(optmacs),a
		jp	cpendw
cpopt.f:	ld	a,0ffh
		ld	(optflds),a
		jp	cpendw		; skip anything else in this word
cpopt.p:	ld	a,0ffh
		ld	(optscrn),a
		jp	cpendw

; cmdbann - the banner, unless /Q said not to.
;
; Input:	nothing
; Output:	four lines, or none
; Modifies:	AF, DE

cmdbann:	ld	a,(optquiet)
		or	a
		ret	nz

; cmdver - and the banner whatever was asked for. IN THREE PIECES,
;   because the version number in the middle is a label of its own -
;   see vertxt below for why.
;
; Input:	nothing
; Output:	four lines, the last of them blank
; Modifies:	AF, DE

cmdver:		ld	de,msg_ban1
		call	putstr
		ld	de,msg_vnum
		call	putstr
		ld	de,msg_ban2
		call	putstr
		ret

; cmdusage - the banner and the usage screen, and stop.
;
;   TWENTY-TWO LINES, which is what fits: the command that was typed
;   takes the first row of a 24-row screen and the prompt takes the
;   last, so nothing scrolls away. Every line is inside 79 columns.
;
;   /Q DOES NOT SILENCE THIS. Asking for the screen and asking for
;   silence at once is a contradiction, and the screen is the answer.
;
; Input:	nothing
; Output:	the screen, and the program ends
; Modifies:	does not return

cmdusage:	call	cmdver
		ld	de,msg_usage
		call	putstr
		jp	dosexit

; cpname - copy the word at HL into the next free filename slow.
;
;   No length check is needed: the whole command tail is at most 127
;   characters, so a single filename cannot overflow MAXPATH.
;   A third filename is an error - errmany prints and terminates.
;
; Input:	HL -> first character of the word
;		B   = characters left
;		C   = filenames seen so far
; Output:	the name stored ASCIIZ
;		C incremented
;		HL and B past the word
; Modifies:	AB, BC, DE, HL

cpname:		ld	a,c
		or	a
		jr	nz,cpname.two
		ld	de,srcname	; first filename
		jr	cpname.copy
cpname.two:	cp	1
		jr	nz,cpname.three
		ld	de,dstname	; second: the OBJECT file
		jr	cpname.copy
cpname.three:	cp	2
		jp	nz,errmany	; a fourth is an error
		ld	de,lstname	; third: the LISTING
cpname.copy:	ld	a,b
		or	a
		jr	z,cpname.end	; tail ran out
		ld	a,(hl)
		cp	CHR_SPACE
		jr	z,cpname.end
		cp	CHR_TAB
		jr	z,cpname.end
		ld	(de),a
		inc	hl
		inc	de
		dec	b
		jr	cpname.copy
cpname.end:	xor	a
		ld	(de),a		; ASCIIZ terminator, for _OPEN
		inc	c		; one more filename seen
		ret

; THE VERSION IS WRITTEN ONCE, and these two labels are adjacent on
; purpose. vertxt is the thirteen bytes the listing's page header
; wants - "Tatara v" is eight and "1.1.7" is five - because msg_vnum
; follows it in memory. msg_vnum on its own is the number with a "$"
; behind it, which is what cmdver prints between the two halves of
; the banner.
;
; THIRTEEN IS M80'S WIDTH: "MSX.M-80 2.00" is thirteen characters and
; every column of the page header after it was measured from there.
; A two-digit major version would be fourteen and would move them
; all, so LSTNAMW and these two labels have to be changed together.

vertxt:		defb	"Tatara v"
msg_vnum:	defb	"1.1.7","$"

msg_ban1:	defb	"Tatara MSX Macro-Assembler v$"
msg_ban2:	defb	CHR_CR,CHR_LF
		defb	"Copyright (C) 2026 Javier Lavandeira"
		defb	CHR_CR,CHR_LF
		defb	"https://tatara.tools"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF,"$"

msg_usage:	defb	"Usage:  TATARA [options] <source> [output]"
		defb	CHR_CR,CHR_LF
		defb	"        TATARA /P [options] <source> [output]"
		defb	CHR_CR,CHR_LF
		defb	"        TATARA /L [options] <source> <output>"
		defb	" <listing>",CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"Options:  /P Assemble to the screen"
		defb	CHR_CR,CHR_LF
		defb	"          /L Write a listing file, named third"
		defb	" on the line",CHR_CR,CHR_LF
		defb	"          /S Print the symbol table when the"
		defb	" assembly ends",CHR_CR,CHR_LF
		defb	"          /C Make symbol and macro names"
		defb	" case-sensitive",CHR_CR,CHR_LF
		defb	"          /F Print the fields of each line, for"
		defb	" diagnosis",CHR_CR,CHR_LF
		defb	"          /M Print every macro definition, for"
		defb	" diagnosis",CHR_CR,CHR_LF
		defb	"          /H Print how many heap blocks are"
		defb	" still in use",CHR_CR,CHR_LF
		defb	"          /Q Omit the banner above and the"
		defb	" summary line",CHR_CR,CHR_LF
		defb	"          /V Print the program version"
		defb	CHR_CR,CHR_LF
		defb	"          /? Print this screen"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"<source>  : The file to assemble, M80 syntax"
		defb	" (.as, .asm or .z80)",CHR_CR,CHR_LF
		defb	"<output>  : The relocatable object it produces,"
		defb	" usually .tro",CHR_CR,CHR_LF
		defb	"<listing> : The listing file, usually .lst or"
		defb	" .prn",CHR_CR,CHR_LF,"$"

		dseg

srcname:	defs	MAXPATH		; input filename
dstname:	defs	MAXPATH		; output filename ("" = none given)
lstname:	defs	MAXPATH		; listing filename ("" = none), the
					;   third on the command line
optscrn:	defs	1		; 0FFh = /P given
optflds:	defs	1		; 0FFh = /F given
optmacs:	defs	1		; 0FFh = /M given
opthblk:	defs	1		; 0FFh = /H given
optsym:		defs	1		; 0FFh = /S given
optlist:	defs	1		; 0FFh = /L given
optquiet:	defs	1		; 0FFh = /Q given
optver:		defs	1		; 0FFh = /V given
opthelp:	defs	1		; 0FFh = /? given
optcase:	defs	1		; HTCASES or HTCASEI. Fixed for the
					; run: changing it part-way would mean
					; rehashing every populated table, and
					; R2 wants one mode across a whole
					; link job
