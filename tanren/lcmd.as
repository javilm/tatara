; lcmd.as - TANREN's command line.
;
; Deliberately simpler than cmdline.as and not a shared version of
; it: the two programs take different switches and print different
; screens. What moved OUT of here is the layer below that - the
; splitting of a command tail into words, and the reading of a
; response file instead - which is arglist.as, and which knows
; nothing about what a word means.
;
; SO THIS MODULE NO LONGER TOUCHES A CHARACTER OF THE COMMAND TAIL.
; It asks arglist.as for words and decides what each one is: a "/"
; makes it a switch, anything else makes it an object file. That test
; is the one it always made, and it is now the only one it makes.

LCMDLIB		equ	1	; skips the externals in lcmd.inc

		public	lcmparse
		public	objname
		public	outname
		public	lcmfrst
		public	lcmnext
		public	loptdump
		public	loptmap
		public	loptquiet
		public	loptver
		public	lopthelp
		public	loptout
		public	loptbin
		public	loptorg
		public	lorgadr
		public	loptdat
		public	ldatadr
		public	lcmodef
		public	lcmovch
		public	lcmbann
		public	lcmwarn
		public	lcmver
		public	lcmusage

		include	lcmd.inc
		include	arglist.inc	; argtail, argfrst, argnext,
					;   argcut
		include	lerrs.inc	; errlunk, errlover
		include	msxdos.inc	; _STROUT, dosexit
		include	ascii.inc	; CHR_CR, CHR_LF
		include	strutil.inc	; strupr, strdot, strext

LSLASH		equ	"/"

		cseg

; lcmparse - what the words on the command line mean.
;
;   argtail has already split them, expanded any @FILE, and put them
;   in the mapper. This walks them once: a switch is acted on, and
;   anything else is counted - because "was a filename given at all?"
;   is the only thing the caller needs to know here. lcmnext walks
;   the same list again, twice, to do the reading.
;
; Input:	nothing
; Output:	CY clear = at least one filename was given
;		CY set   = none was
; Modifies:	everything

lcmparse:	xor	a
		ld	(loptdump),a
		ld	(loptmap),a
		ld	(loptquiet),a
		ld	(loptver),a
		ld	(lopthelp),a
		ld	(loptout),a
		ld	(loptbin),a
		ld	(loptorg),a
		ld	(loptdat),a
		ld	(lcmnf),a
		ld	(objname),a
		ld	(outname),a
		call	argtail		; THE WHOLE COMMAND LINE, as words
		call	argfrst
lcmp.lp:	ld	de,objname	; the buffer it is going to use
		call	argnext		;   anyway
		jr	c,lcmp.end
		ld	a,(objname)
		cp	LSLASH
		jr	z,lcmp.opt
		ld	hl,lcmnf	; a filename: COUNTED, not kept.
		inc	(hl)		;   259 of them would wrap this
		jr	lcmp.lp		;   byte, and the list would run
lcmp.opt:	ld	de,objname	;   out first
		call	lcpopt
		jr	lcmp.lp
lcmp.end:	xor	a
		ld	(objname),a	; LEAVE IT EMPTY: lcmnext fills it
		ld	a,(lcmnf)	;   when the reading starts
		or	a
		scf
		ret	z
		or	a
		ret

; lcpopt - one option word.
;
;   IT TAKES A WHOLE WORD NOW. Every arm used to end in a jump to
;   lcpend, because each one had to step the tail pointer past the
;   rest of its own word before the caller could look for the next
;   one. There is no pointer any more, so every arm is a ret - and
;   the worry about the furthest arm being out of a jr's reach goes
;   with it.
;
; Input:	DE -> the word, which starts with "/"
; Output:	the flag is set (errlunk does not return)
; Modifies:	AF, BC, DE, HL

lcpopt:		inc	de
		ld	a,(de)
		or	a
		jp	z,errlunk	; a "/" with nothing after it
		call	strupr
		cp	"B"
		jr	z,lcpo.b
		cp	"D"
		jp	z,lcpo.d	; jp: /D: and /P: sit past the flag
					;   arms and past /O:, a hundred
					;   bytes and more from here
		cp	"M"
		jr	z,lcpo.m
		cp	"O"
		jr	z,lcpo.o
		cp	"P"
		jp	z,lcpo.p
		cp	"R"
		jr	z,lcpo.r
		cp	"Q"
		jr	z,lcpo.q
		cp	"V"
		jr	z,lcpo.v
		cp	"?"		; not a letter, so strupr left it
		jp	nz,errlunk
		ld	a,0ffh
		ld	(lopthelp),a
		ret
lcpo.b:		ld	a,0ffh
		ld	(loptbin),a
		ret
lcpo.r:		ld	a,0ffh		; the arm, under its new letter
		ld	(loptdump),a
		ret
lcpo.m:		ld	a,0ffh
		ld	(loptmap),a
		ret
lcpo.q:		ld	a,0ffh
		ld	(loptquiet),a
		ret
lcpo.v:		ld	a,0ffh
		ld	(loptver),a
		ret

; lcpo.o - /O:<file>, the only option that carries a value.
;
;   L80 writes /P: and /E:, and the colon is the convention this
;   keeps. The name is the rest of the same word, so there is nothing
;   to look ahead for - which is why it survived the move from a tail
;   pointer to a word unchanged in everything but how it copies.
;
; Input:	DE -> the "O" of the word
; Output:	outname, loptout (errlunk does not return)
; Modifies:	AF, DE, HL

lcpo.o:		inc	de		; past the "O"
		ld	a,(de)
		cp	":"
		jp	nz,errlunk
		inc	de
		ld	a,(de)
		or	a
		jp	z,errlunk	; "/O:" and nothing after it
		ld	h,d
		ld	l,e
		ld	de,outname
lcpo.cp:	ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,lcpo.ce
		inc	hl
		inc	de
		jr	lcpo.cp
lcpo.ce:	ld	a,0ffh
		ld	(loptout),a
		ret

; lcpo.d, lcpo.p - /D:<addr> and /P:<addr>, where the data and the
; code start.
;
;   /D WAS ONCE THE RECORD DUMP, before there was a linker to want
;   it for an address. L80's data origin is /D:, so the two would have
;   been told apart by a colon alone, and the decision was
;   was that "having /D and /D: is going to be confusing for many
;   people". The dump is /R now and these two are plain.
;
;   Both require the colon, so /D and /P alone are errlunk rather than
;   something silently ignored.
;
; Input:	DE -> the letter of the word
; Output:	ldatadr and loptdat, or lorgadr and loptorg
;		(errlunk does not return)
; Modifies:	AF, BC, DE, HL

lcpo.d:		call	lcpoadr
		ld	(ldatadr),hl
		ld	a,0ffh
		ld	(loptdat),a
		ret

lcpo.p:		call	lcpoadr
		ld	(lorgadr),hl
		ld	a,0ffh
		ld	(loptorg),a
		ret

; lcpoadr - the address after a letter and a colon.
;
; Input:	DE -> the letter
; Output:	HL = the address (errlunk does not return)
; Modifies:	AF, BC, DE, HL

lcpoadr:	inc	de
		ld	a,(de)
		cp	":"
		jp	nz,errlunk
		inc	de
		call	strhex
		jp	c,errlunk
		ret

; lcmfrst, lcmnext - the object filenames, one at a time.
;
;   THE SAME LIST THE OPTIONS CAME FROM, walked again. A word that
;   begins with "/" is a switch and is stepped over; everything else
;   is a filename and gets ".tro" if it has no extension.
;
;   Walked TWICE over a link, once per pass. That was designed for
;   when the list was the command tail itself and nothing had to be
;   stored; it is stored now, because a response file cannot be left
;   sitting at 0080h.
;
; Input:	nothing
; Output:	lcmnext: CY clear = objname holds the next one
;		         CY set   = there are no more
; Modifies:	AF, BC, DE, HL

lcmfrst:	jp	argfrst

lcmnext:	ld	de,objname
		call	argnext
		ret	c
		ld	a,(objname)
		cp	LSLASH
		jr	z,lcmnext	; a switch: step over it
		call	lcmext		; ".tro", unless it has one already
		call	lcmsrch		; and WHERE it is
		or	a		; CY clear: a name was found
		ret

; lcmext - a default extension of .tro, on objname.
;
; Input:	objname, ASCIIZ
; Output:	".tro" appended if it had no extension
; Modifies:	AF, BC, DE, HL

lcmext:		ld	de,objname
		ld	hl,msg_tro
		jp	strext

; lcmsrch - find the object file objname names.
;
;   IT CANNOT FAIL. If nothing opens, objname is left exactly as it
;   was and lobopen reports it, which is what happened before this
;   note existed - so there is no new error, no new contract, and
;   lobj.as and tanren.as are not touched at all.
;
;   THE FILE LIST'S DIRECTORY COMES FIRST, and not the current
;   directory: an object sitting beside the .lnk file that names it
;   must win over one of the same name in whatever directory the
;   linker was started from.
;
;   IT OPENS AND CLOSES to find out - three BDOS calls per object
;   instead of one, over nineteen objects and two passes. The
;   alternative is a search inside lobopen, which would have to know
;   about the word list and about the environment, and lobj.as knows
;   about neither.
;
; Input:	objname, with its extension
;		argfrf, from the word this name came from
; Output:	objname, with a directory in front of it if that is
;		where the file turned out to be
; Modifies:	everything

lcmsrch:	ld	de,objname
		call	strabs
		ret	c		; absolute: this or nothing
		ld	a,(argfrf)	; 1 - where the file list lives
		or	a
		jr	z,lcms.cur
		ld	hl,argrdir
		call	lcms.try
		ret	nc
lcms.cur:	ld	de,objname	; 2 - as typed
		call	lcms.op
		ret	nc
		call	lcmenv		; 3 - each entry of TANREN in turn
		ld	hl,lenvbuf
lcms.ev:	ld	a,(hl)
		or	a
		ret	z		; used up: objname is left as it was
		call	lcms.try
		ret	nc
		ld	a,(hl)		; HL is at the ";" or at the end
		or	a
		ret	z		; that was the last entry
		inc	hl		; past the ";"
		jr	lcms.ev

; lcms.try - one prefix: compose it with objname and see if it opens.
;
; Input:	HL -> the prefix, ended by 0 or ";"
; Output:	CY clear = it opened, and objname now says where
;		HL -> the prefix's terminator, either way
; Modifies:	everything

lcms.try:	ld	de,objname
		call	strcomp		; -> strbuf, HL at the terminator
		ld	(lcmsp),hl	; KEEP IT: the copy below needs HL, and
					;   ld (nn),hl leaves the flags alone
		jr	c,lcms.tno
		ld	de,strbuf
		call	lcms.op
		jr	c,lcms.tno
		ld	hl,strbuf	; it opened: this is the name now
		ld	de,objname
lcms.tcp:	ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,lcms.tok
		inc	hl
		inc	de
		jr	lcms.tcp
lcms.tok:	ld	hl,(lcmsp)
		or	a		; CY clear
		ret
lcms.tno:	ld	hl,(lcmsp)
		scf
		ret

; lcms.op - does this name open?
;
;   Opened and closed again, because the answer is wanted and the
;   handle is not: lobopen does the real open, with the magic check
;   that goes with it.
;
; Input:	DE -> the name, ASCIIZ
; Output:	CY set = MSX-DOS would not open it
; Modifies:	AF, BC

lcms.op:	ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error, B = handle
		or	a
		scf
		ret	nz
		system	_CLOSE		; B is still the handle, and
					;   p2safe preserves it
		or	a
		ret

; lcmenv - fetch TANREN's value, once.
;
;   ONCE, AND FAILURES COUNT AS DONE, so a link of nineteen objects
;   does not ask MSX-DOS nineteen times.
;
;   Under MSX-DOS 1 there are no environment variables, so the buffer
;   stays empty and the search has one place fewer to look.
;
;   _GENV TRUNCATES WITHOUT A TERMINATOR when the buffer is too small
;   and says ERR_ELONG. A search path quietly shorter than what was
;   set is worse than none, so that is an error.
;
; Input:	nothing
; Output:	lenvbuf holds the value, or is empty
; Modifies:	AF, BC, DE, HL

lcmenv:		ld	a,(lenvrd)
		or	a
		ret	nz		; asked once already
		ld	a,1
		ld	(lenvrd),a
		xor	a
		ld	(lenvbuf),a	; empty unless proved otherwise
		call	dosver
		ret	c		; MSX-DOS 1: there are none
		ld	hl,msg_lenvt
		ld	de,lenvbuf
		ld	b,LMAXENV
		system	_GENV
		or	a
		ret	z		; the value is in the buffer
		cp	ERR_ELONG
		jp	z,errlenv
		xor	a
		ld	(lenvbuf),a	; any other refusal: no path
		ret

msg_lenvt:	defb	"TANREN",0	; MSX-DOS upper-cases a variable's
					;   name when it is set and compares
					;   without case, so this spelling is
					;   the whole of it

; lcmodef - the output file's name, when /O: did not give one.
;
;   THE FIRST OBJECT FILE'S NAME WITH .com ON IT:
;   "Let's assume .com filename if none is specified." Whatever
;   extension it has comes off first, so "A:\X\MAIN.TRO" gives
;   "A:\X\MAIN.COM" - beside the object it was made from, which is
;   where a linker's output belongs.
;
;   IT TAKES THE NAME FROM THE LIST, with .tro already on it if the
;   user typed no extension, and that gives the same answer as taking
;   what was typed: "main" becomes "main.tro", loses ".tro", and
;   becomes "main.com". A separate copy of the first name was once
;   for this and no longer needs one.
;
; Input:	loptout, loptbin, the list
; Output:	outname
; Modifies:	everything

lcmodef:	ld	a,(loptout)
		or	a
		ret	nz		; /O: named one
		call	lcmfrst
		call	lcmnext
		ret	c		; no filenames at all
		ld	hl,objname
		ld	de,outname
lcmo.cp:	ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,lcmo.cut
		inc	hl
		inc	de
		jr	lcmo.cp
lcmo.cut:	ld	de,outname	; whatever extension it has comes
		call	strdot		;   off
		jr	c,lcmo.ext
		ld	(hl),0
lcmo.ext:	ld	de,outname	; and .com goes on - or .bin, if
		ld	hl,msg_com	;   /B was given, because a BLOAD
		ld	a,(loptbin)	;   header is what makes a file a
		or	a		;   .BIN and nothing else does
		jr	z,lcmo.go
		ld	hl,msg_bin
lcmo.go:	jp	strext

; lcmovch - the output file may not be one of the inputs.
;
;   The rule is "except when the output would overwrite one of
;   the input files". CHECKED BEFORE ANYTHING IS READ, because the
;   answer cannot change during the link and a link that is going to
;   refuse should refuse before it has printed a map.
;
;   Both names carry their extensions by then, so "tanren /o:a.com a"
;   is allowed - the input is A.TRO - and "tanren /o:a.tro a" is not.
;
; Input:	outname, and the list
; Output:	nothing (errlover does not return)
; Modifies:	AF, BC, DE, HL

lcmovch:	call	lcmfrst
lcmov.lp:	call	lcmnext
		ret	c
		ld	hl,objname
		ld	de,outname
		call	lcmsame
		jp	z,errlover
		jr	lcmov.lp

; lcmsame - two ASCIIZ filenames, compared without regard to case.
;
;   MSX-DOS does not care about the case of a filename, so neither may
;   this. PATHS ARE NOT RESOLVED: "A:\X\A.TRO" and "..\X\A.TRO" may be
;   one file and this will not notice, which is a limit and not a bug -
;   resolving a path means asking MSX-DOS, and the answer would be
;   worth having only if the linker also refused to read two inputs
;   that were one file.
;
; Input:	HL -> one name
;		DE -> the other
; Output:	Z set = the same name
; Modifies:	AF, BC, DE, HL

lcmsame:	ld	a,(de)
		call	strupr
		ld	c,a
		ld	a,(hl)
		call	strupr
		cp	c
		ret	nz
		or	a		; both ended together: the same
		ret	z
		inc	hl
		inc	de
		jr	lcmsame

; lcmbann - the banner, unless /Q said not to.
;
; Input:	nothing
; Output:	four lines, or none
; Modifies:	AF, DE

lcmbann:	ld	a,(loptquiet)
		or	a
		ret	nz

; lcmver - and the banner whatever was asked for.
;
; Input:	nothing
; Output:	four lines, the last of them blank
; Modifies:	AF, DE

lcmver:		ld	de,msg_lba1
		call	putstr
		ld	de,msg_lvnum
		call	putstr
		ld	de,msg_lba2
		call	putstr
		ret

; lcmwarn - the command line may have been cut.
;
;   MSX-DOS gives 127 characters and TRUNCATES A LONGER LINE WITHOUT
;   SAYING SO. That is the whole reason [R10] exists: the failure does
;   not arrive as "line too long", it arrives as an undefined symbol
;   from a module that was never named, and this project walked into
;   it twice while being built.
;
;   A tail of exactly 127 characters is one that MAY have been cut -
;   it may also be a line that happens to fit exactly, which is why
;   this is a warning and not an error.
;
;   IT PRINTS EVEN UNDER /Q, because a warning is closer to an error
;   than to a summary, and /Q asks for the banner and the summary to
;   go.
;
; Input:	argcut
; Output:	three lines, or none
; Modifies:	AF, DE

lcmwarn:	ld	a,(argcut)
		or	a
		ret	z
		ld	de,msg_lcut
		call	putstr
		ret

; lcmusage - the banner and the usage screen, and stop.
;
;   /Q does not silence it: asking for the screen and asking for
;   silence at once is a contradiction.
;
; Input:	nothing
; Output:	does not return

lcmusage:	call	lcmver
		ld	de,msg_luse
		call	putstr
		jp	dosexit

; THE VERSION IS WRITTEN ONCE. cmdline.as puts two labels together so
; that the listing's page header can have "Tatara v1.1.7" as thirteen
; bytes; the linker has no listing and needs only the number, so
; msg_lvnum stands alone between the two halves of the banner.

msg_lvnum:	defb	"1.1.7","$"
msg_tro:	defb	".tro",0	; what lcmext appends,
msg_com:	defb	".com",0	;   what lcmodef does, and
msg_bin:	defb	".bin",0	;   what it does instead with /B

msg_lba1:	defb	"Tatara MSX Linker v$"
msg_lba2:	defb	CHR_CR,CHR_LF
		defb	"Copyright (C) 2026 Javier Lavandeira"
		defb	CHR_CR,CHR_LF
		defb	"https://tatara.tools"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF,"$"

msg_lcut:	defb	"WARNING: the command line is 127"
		defb	" characters, which is all",CHR_CR,CHR_LF
		defb	"MSX-DOS gives - anything past it was dropped"
		defb	" in silence.",CHR_CR,CHR_LF
		defb	"Use @<file> if a module is missing."
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF,"$"

msg_luse:	defb	"Usage:  TANREN [options] <object|@list>"
		defb	" [more...]",CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"Options:  /B Write a BLOAD header on the"
		defb	" output file",CHR_CR,CHR_LF
		defb	"          /D:<addr> Start the data segments"
		defb	" at <addr>",CHR_CR,CHR_LF
		defb	"          /M Print the segment and group tables"
		defb	CHR_CR,CHR_LF
		defb	"          /O:<file> Write the image to"
		defb	" <file>",CHR_CR,CHR_LF
		defb	"          /P:<addr> Start the code segments"
		defb	" at <addr>",CHR_CR,CHR_LF
		defb	"          /Q Omit the banner above and the"
		defb	" summary line",CHR_CR,CHR_LF
		defb	"          /R Print every record in the object"
		defb	" files",CHR_CR,CHR_LF
		defb	"          /V Print the program version"
		defb	CHR_CR,CHR_LF
		defb	"          /? Print this screen"
		defb	CHR_CR,CHR_LF,CHR_CR,CHR_LF
		defb	"<object>  : A .tro file; .tro is assumed when"
		defb	" you leave it off.",CHR_CR,CHR_LF
		defb	"@<list>   : A file of the same words; ; is a"
		defb	" comment, .lnk",CHR_CR,CHR_LF
		defb	"            is assumed.",CHR_CR,CHR_LF
		defb	"<addr>    : One to four hex digits, as in"
		defb	" /P:4000.",CHR_CR,CHR_LF
		defb	"<file>    : The output. Default: the first"
		defb	" object with .com",CHR_CR,CHR_LF
		defb	"            (.bin with /B). It may not be an"
		defb	" input file.",CHR_CR,CHR_LF,"$"

		dseg

objname:	defs	LMAXPATH+4	; the object file - AND ROOM FOR
					;   lcmext's four characters, which a
					;   name using the whole command tail
					;   would otherwise run past
outname:	defs	LMAXPATH+4	; the file the image is written
					;   to, with room for lcmodef's
					;   four characters
lcmnf:		defs	1		; how many words were not switches
lcmsp:		defs	2		; lcms.try: the prefix's terminator,
					;   across the copy into objname
lenvrd:		defs	1		; 0 = TANREN has not been looked up
lenvbuf:	defs	LMAXENV		; its value, read once
loptdump:	defs	1		; 0FFh = /D given
loptmap:	defs	1		; 0FFh = /M given
loptquiet:	defs	1		; 0FFh = /Q given
loptver:	defs	1		; 0FFh = /V given
lopthelp:	defs	1		; 0FFh = /? given
loptout:	defs	1		; 0FFh = /O: given
loptbin:	defs	1		; 0FFh = /B given
loptorg:	defs	1		; 0FFh = /P: given, and
lorgadr:	defs	2		;   where it said the code starts
loptdat:	defs	1		; 0FFh = /D: given, and
ldatadr:	defs	2		;   where it said the data starts
