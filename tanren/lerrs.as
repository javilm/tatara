; lerrs.as - TANREN's errors.
;
; Every one of them prints a line and terminates. The assembler's
; errs.as also prints where in the source the error was, because it
; has a line to point at; the linker's errors are about a FILE, and
; the file's name is in the message the driver already printed, so
; there is nothing to add. That is the whole difference, and it is
; why this module is forty lines and errs.as is six hundred.

LERRLIB		equ	1	; skips the externals in lerrs.inc

		public	errlopn
		public	errlmag
		public	errlver
		public	errltrn
		public	errlunk
		public	errlheap
		public	errlmseg
		public	errlrsp
		public	errlnest
		public	errlargs
		public	errlenv
		public	errlout
		public	errlwrt
		public	errlover
		public	errlmext
		public	errlsflg
		public	errlovlp
		public	errlbig
		public	errlydup
		public	errlyunr
		public	errlymix

		include	lerrs.inc
		include	msxdos.inc	; _STROUT, putsz, dosexit
		include	lcmd.inc	; objname: errlopn names the file
					;   it tried, which lcmext may have
					;   given an extension. outname:
					;   errlout and errlover name that
					;   one for the same reason
		include	arglist.inc	; argfn: errlrsp names the
					;   response file it tried, the
					;   way errlopn names the object
		include	ascii.inc	; CHR_CR, CHR_LF

		cseg

errlopn:	call	errlpfx		; THE NAME IT ACTUALLY TRIED, which
		ld	de,msg_lopn
		call	putsz		;   lcmext may have changed. Zero-
		ld	de,objname	;   terminated, not "$": a filename
		call	putsz		;   is interleaved with it and BDOS
		ld	de,msg_lcrl	;   09h cannot help with that
		call	putsz
		jp	dosexit
errlrsp:	call	errlpfx		; AND THIS ONE: a response file
		ld	de,msg_lrsp
		call	putsz		;   that will not open is almost
		ld	de,argfn	;   always a name typed wrong
		call	putszu
		ld	de,msg_lcrl
		call	putsz
		jp	dosexit
errlout:	call	errlpfx		; AND THIS NAME TOO: a path that
		ld	de,msg_lout
		call	putsz		;   does not exist is the likely
		ld	de,outname	;   cause, and the name is the
		call	putszu		;   clue
		ld	de,msg_lcrl
		call	putsz
		jp	dosexit
errlover:	call	errlpfx
		ld	de,msg_lovr1
		call	putsz
		ld	de,outname
		call	putszu
		ld	de,msg_lovr2
		call	putsz
		jp	dosexit
errlmag:	ld	de,msg_lmag
		jr	errldie
errlver:	ld	de,msg_lver
		jr	errldie
errltrn:	ld	de,msg_ltrn
		jr	errldie
errlunk:	ld	de,msg_lunk
		jr	errldie
errlheap:	ld	de,msg_lheap
		jr	errldie
errlenv:	ld	de,msg_lenv	; the TANREN variable is longer than
		jr	errldie		;   LMAXENV, so _GENV has handed back a
					;   truncated value with no terminator
errlmseg:	ld	de,msg_lmseg
		jr	errldie
errlwrt:	ld	de,msg_lwrt
		jr	errldie
errlnest:	ld	de,msg_lnest
		jr	errldie
errlargs:	ld	de,msg_largs
		jr	errldie
errlmext:	ld	de,msg_lmext
		jr	errldie
errlbig:	ld	de,msg_lbig
		jr	errldie
errlovlp:	ld	de,msg_lovlp
		jr	errldie
errlydup:	ld	de,msg_lydup
		jr	errldie
errlyunr:	ld	de,msg_lyunr
		jr	errldie
errlymix:	ld	de,msg_lymix
		jr	errldie
errlsflg:	ld	de,msg_lsflg

; errldie - print the $-terminated message in DE and terminate.
;
; Input:	DE -> the message
; Output:	does not return

errldie:	push	de		; THE ONE COPY, for the sixteen
		call	errlpfx		;   errors that come through here
		pop	de
		call	putstr
		jp	dosexit

; errlpfx - "ERROR: ", for the four that print a filename and so
;   cannot come through errldie.
;
; Input:	nothing
; Output:	seven characters
; Modifies:	AF, BC, DE, HL

errlpfx:	ld	de,msg_lerr
		jp	putsz

		dseg

msg_lerr:	defb	"ERROR: ",0	; printed by errldie and errlpfx
msg_lopn:	defb	"cannot open ",0
msg_lcrl:	defb	CHR_CR,CHR_LF,0
msg_lmag:	defb	"not a Tatara object file.",CHR_CR
		defb	CHR_LF,"$"
msg_lver:	defb	"this object file was made by another"
		defb	" version.",CHR_CR,CHR_LF,"$"
msg_ltrn:	defb	"the object file ends inside a record."
		defb	CHR_CR,CHR_LF,"$"
msg_lunk:	defb	"unknown option.",CHR_CR,CHR_LF,"$"
msg_lheap:	defb	"out of mapper memory.",CHR_CR
		defb	CHR_LF,"$"
msg_lenv:	defb	"the TANREN variable is too long.",CHR_CR
		defb	CHR_LF,"$"
msg_lrsp:	defb	"cannot open the file list ",0
msg_lnest:	defb	"a file list may not name another"
		defb	" one.",CHR_CR,CHR_LF,"$"
msg_largs:	defb	"too many words on the command line"
		defb	" or in the file list.",CHR_CR,CHR_LF,"$"
msg_lout:	defb	"cannot create ",0
msg_lovr1:	defb	"the output file ",0
msg_lovr2:	defb	" is also an input file.",CHR_CR,CHR_LF,0
msg_lwrt:	defb	"cannot write the output file - the"
		defb	" disk may be full.",CHR_CR,CHR_LF,"$"
msg_lmext:	defb	"too many external symbols in one"
		defb	" module.",CHR_CR,CHR_LF,"$"
msg_lmseg:	defb	"too many segments or groups in one"
		defb	" module.",CHR_CR,CHR_LF,"$"
msg_lsflg:	defb	"this segment was declared differently"
		defb	" in another module.",CHR_CR,CHR_LF,"$"
msg_lovlp:	defb	"/D: would put the data on top of"
		defb	" the code.",CHR_CR,CHR_LF,"$"
msg_lbig:	defb	"the linked image would run past"
		defb	" FFFFh.",CHR_CR,CHR_LF,"$"
msg_lydup:	defb	"that public symbol is already"
		defb	" defined.",CHR_CR,CHR_LF,"$"
msg_lyunr:	defb	"the symbols above were never"
		defb	" defined.",CHR_CR,CHR_LF,"$"
msg_lymix:	defb	"one module was assembled /C and"
		defb	" another was not.",CHR_CR,CHR_LF,"$"
