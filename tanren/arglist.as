; arglist.as - the words a program was asked to work on, and where
; they came from.
;
; ONE LIST, IN THE MAPPER. The command tail is split into words once;
; a word beginning with "@" is a file, whose words are split by the
; same code and appended in its place. After that nothing downstream
; knows which came from where - and the linker's two passes walk the
; same list twice, which is what the command tail once had to stay
; still for.
;
; NOTHING USED TO BE STORED, on the grounds that the tail sits at
; 0080h and walking it again is free. That was true and stopped being
; true here: a file would have to be re-opened and re-parsed for pass
; 2, interleaved with the tail in the same order, twice. The reversal
; is D3.
;
; NOTHING HERE KNOWS WHAT A WORD MEANS. That is lcmd.as's business,
; and this module would serve cmdline.as unchanged on the day the
; assembler wants it.

ARGLIB		equ	1	; skips the externals in arglist.inc

		public	argtail
		public	argfile
		public	argadd
		public	argfrst
		public	argnext
		public	argn
		public	argcut
		public	argfn
		public	argrdir
		public	argfrf

		include	arglist.inc
		include	lerrs.inc	; errlheap, errlargs, errlrsp,
					;   errlnest
		include	alloc.inc	; halloc, deref
		include	farptr.inc	; derefp
		include	strutil.inc	; strext
		include	msxdos.inc	; _OPEN, _READ, _CLOSE

TAILLEN		equ	00080h		; command tail: the length byte
TAILTXT		equ	00081h		; command tail: the text
TAILMAX		equ	127		; and all of it there can ever be.
					; MSX-DOS cuts a longer line HERE,
					; in silence, which is what [R10]
					; exists to answer

		cseg

; argtail - the command tail, as words.
;
;   ONE PASS, ONE CHARACTER AT A TIME. A space or a tab ends the word
;   being built and anything else belongs to it, so the word
;   boundaries fall out rather than being searched for.
;
; Input:	nothing (0080h)
; Output:	the list holds every word, @FILEs expanded
;		(the four errors do not return)
; Modifies:	everything

argtail:	call	arginit
		xor	a
		ld	(argnest),a
		ld	(argwn),a
		ld	(argcut),a
		ld	a,(TAILLEN)
		cp	TAILMAX
		jr	c,argt.go
		ld	a,0ffh		; AT THE LIMIT, so it may have been
		ld	(argcut),a	;   cut. lcmwarn says so
argt.go:	ld	hl,TAILTXT
		ld	a,(TAILLEN)
		ld	b,a
argt.lp:	ld	a,b
		or	a
		jp	z,argwend	; the tail does not end with a
		ld	a,(hl)		;   space, so the last word has to
		inc	hl		;   be finished here
		dec	b
		cp	" "
		jr	z,argt.sp
		cp	009h
		jr	z,argt.sp
		push	hl
		push	bc
		call	argwput
		pop	bc
		pop	hl
		jr	argt.lp
argt.sp:	push	hl
		push	bc
		call	argwend
		pop	bc
		pop	hl
		jr	argt.lp

; arginit - the block the words live in.
;
; Input:	nothing
; Output:	an empty list (errlheap does not return)
; Modifies:	AF, BC, DE, HL

arginit:	ld	bc,ARGSIZE
		ld	hl,argptr
		call	halloc
		jp	c,errlheap
		ld	hl,0
		ld	(argused),hl
		ld	(argn),hl
		ld	(argpos),hl
		ld	(argrf),hl	; no response file has been read, and
		ld	(argrt),hl	;   an empty range answers "no" to
		xor	a		;   every word - see argfrom
		ld	(argfrf),a
		ld	(argrdir),a
		ret

; argwput - one character onto the word being built.
;
; Input:	A = the character
; Output:	it is in argw (errlargs does not return)
; Modifies:	AF, BC, DE, HL

argwput:	ld	c,a		; THE CHARACTER, AND NOT IN E: argw's
		ld	a,(argwn)	;   address is about to go into DE,
		cp	ARGMAX-1	;   and E with it
		jp	nc,errlargs	; a word longer than a path can be
		ld	hl,argw
		ld	e,a
		ld	d,0
		add	hl,de
		ld	(hl),c
		inc	a		; A is still argwn
		ld	(argwn),a
		ret

; argwend - the word being built is finished.
;
;   IT FORGETS THE WORD BEFORE HANDING IT OVER, because argwrd may
;   open a response file and that file's words are built in this same
;   buffer. argwrd has taken what it needs by then.
;
; Input:	argw, argwn
; Output:	the word is in the list, or was a file that has been
;		read
; Modifies:	everything

argwend:	ld	a,(argwn)
		or	a
		ret	z		; two spaces in a row
		ld	l,a
		ld	h,0
		ld	de,argw
		add	hl,de
		ld	(hl),0		; terminate it
		xor	a
		ld	(argwn),a
		jp	argwrd

; argwrd - what a finished word is.
;
; Input:	argw, ASCIIZ
; Output:	it is in the list, or its file has been read
;		(errlnest, errlrsp do not return)
; Modifies:	everything

argwrd:		ld	a,(argw)
		cp	ARGAT
		jr	z,argwr.f
		ld	de,argw
		jp	argadd
argwr.f:	ld	a,(argnest)
		or	a
		jp	nz,errlnest	; @ INSIDE a response file: refused
		ld	hl,argw+1	; the name, without the @
		ld	de,argfn
argwr.cp:	ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,argwr.e
		inc	hl
		inc	de
		jr	argwr.cp
argwr.e:	ld	a,(argfn)
		or	a
		jp	z,errlrsp	; "@" and nothing after it
		ld	de,argfn
		ld	hl,msg_lnk
		call	strext		; ".lnk", unless it has one
		jp	argfile

; argadd - one word, into the list.
;
; Input:	DE -> the word, ASCIIZ
; Output:	the list holds it (errlargs does not return)
; Modifies:	AF, BC, DE, HL

argadd:		ld	(argsrc),de
		ex	de,hl
		ld	bc,0		; how long it is, terminator and all
argad.l:	ld	a,(hl)
		inc	hl
		inc	bc
		or	a
		jr	nz,argad.l
		ld	(arglen),bc
		ld	hl,(argused)	; would it pass the end?
		add	hl,bc
		ld	de,ARGSIZE
		ex	de,hl
		or	a
		sbc	hl,de
		jp	c,errlargs
		ld	bc,(argused)	; THE OFFSET IN BC, which survives
		derefp	argptr		;   the deref
		add	hl,bc
		ex	de,hl		; DE -> where it goes in the block
		ld	hl,(argsrc)
		ld	bc,(arglen)
		ldir
		ld	hl,(argused)
		ld	bc,(arglen)
		add	hl,bc
		ld	(argused),hl
		ld	hl,(argn)
		inc	hl
		ld	(argn),hl
		ret

; argfrst, argnext - the list, one word at a time.
;
; Input:	argnext: DE -> where the word goes, ARGMAX bytes
; Output:	argnext: CY set = there are no more
; Modifies:	AF, BC, DE, HL

argfrst:	ld	hl,0
		ld	(argpos),hl
		ret

; argfrom - did the word at argpos come from the response file?
;
;   THE RANGE IS ONE CONTIGUOUS SPAN, which is what makes this work
;   at all: a response file may not name another one, so
;   there is exactly one, its words are appended where the "@"
;   appeared, and nothing is ever inserted in front of them.
;
;   With no response file read the range is 0 to 0, and every word is
;   "at or past its end", so the answer is always no.
;
; Input:	argpos, argrf, argrt
; Output:	argfrf
; Modifies:	AF, DE, HL

argfrom:	ld	hl,(argpos)
		ld	de,(argrf)
		or	a
		sbc	hl,de
		jr	c,argfr.no	; before it starts
		ld	hl,(argpos)
		ld	de,(argrt)
		or	a
		sbc	hl,de
		jr	nc,argfr.no	; at or past its end
		ld	a,0ffh
		ld	(argfrf),a
		ret
argfr.no:	xor	a
		ld	(argfrf),a
		ret

argnext:	ld	(argdst),de
		ld	hl,(argpos)
		ld	de,(argused)
		or	a
		sbc	hl,de
		jr	c,argnx.go
		scf
		ret			; the list is used up
argnx.go:	call	argfrom		; did this word come from the file?
		ld	bc,(argpos)
		derefp	argptr
		add	hl,bc
		ld	de,(argdst)
		ld	bc,0
argnx.cp:	ld	a,(hl)		; OUT OF THE MAPPER AND INTO RAM
		ld	(de),a		;   with no BDOS call between, which
		inc	hl		;   is the rule every walk in this
		inc	de		;   program obeys
		inc	bc
		or	a
		jr	nz,argnx.cp
		ld	hl,(argpos)
		add	hl,bc
		ld	(argpos),hl
		or	a		; CY clear: there was one
		ret

; argfile - one response file's words, appended to the list.
;
;   THE NAME COMES IN THROUGH argfn AND NOT A REGISTER, so that
;   errlrsp can print the file it could not open. errlopn reads
;   objname for the same reason.
;
; Input:	argfn, ASCIIZ
; Output:	its words are in the list (errlrsp does not return)
; Modifies:	everything

argfile:	ld	de,argfn
		ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error, B = handle
		or	a
		jp	nz,errlrsp
		ld	a,b
		ld	(arghand),a
		ld	de,argfn	; WHERE THIS FILE LIVES, for the
		call	strdirl		;   objects it names
		ld	hl,argfn
		ld	de,argrdir
		or	a
		jr	z,argf.nd
		ld	c,a
		ld	b,0
		ldir
argf.nd:	xor	a
		ld	(de),a
		ld	hl,(argused)	; and where its words begin
		ld	(argrf),hl
		ld	hl,0
		ld	(argbn),hl
		ld	(argbi),hl
		ld	a,0ffh
		ld	(argnest),a	; @ inside this one is an error
		xor	a
		ld	(argwn),a
argf.lp:	call	argch
		jr	c,argf.end
		cp	ARGCOM
		jr	z,argf.cmt
		cp	" "
		jr	z,argf.sp
		cp	009h
		jr	z,argf.sp
		cp	00dh
		jr	z,argf.sp
		cp	00ah
		jr	z,argf.sp
		call	argwput
		jr	argf.lp
argf.sp:	call	argwend
		jr	argf.lp
argf.cmt:	call	argwend		; a comment ends the word too
argf.cl:	call	argch		; and runs to the end of the line
		jr	c,argf.end
		cp	00ah
		jr	nz,argf.cl
		jr	argf.lp
argf.end:	call	argwend		; A FILE MAY NOT END WITH A NEWLINE
		ld	hl,(argused)	; and where its words end
		ld	(argrt),hl
		xor	a
		ld	(argnest),a
		ld	a,(arghand)
		ld	b,a
		system	_CLOSE
		ret

; argch - the next character of the response file.
;
; Input:	nothing
; Output:	A = the character
;		CY set = the file has ended
; Modifies:	AF, BC, DE, HL

argch:		ld	hl,(argbi)
		ld	de,(argbn)
		or	a
		sbc	hl,de
		jr	c,argch.got	; still some in the buffer
		ld	hl,ARGBUFS
		ld	de,argbuf
		ld	a,(arghand)
		ld	b,a
		system	_READ		; -> A = error, HL = bytes read
		ld	(argbn),hl
		ld	a,h
		or	l
		scf
		ret	z		; nothing came back: the end
		ld	hl,0
		ld	(argbi),hl
argch.got:	ld	hl,argbuf
		ld	bc,(argbi)
		add	hl,bc
		ld	a,(hl)
		cp	01ah		; THE STOPPER. Every file this
		scf			;   project writes ends with one,
		ret	z		;   and a response file will too
		ld	(argchr),a	; THE CHARACTER FIRST: argbi is
		ld	hl,(argbi)	;   about to move, and (hl) with it
		inc	hl
		ld	(argbi),hl
		ld	a,(argchr)
		or	a		; CY clear: a real character
		ret

		dseg

argptr:		defs	4	; the block the words live in
argused:	defs	2	; how much of it is used,
argn:		defs	2	;   and how many words that is
argpos:		defs	2	; argnext: how far the walk has got.
				;   NOT argat: ARGAT is the "@" and
				;   SOLiD folds case, so the two would
				;   be one symbol
argdst:		defs	2	;   and where it is putting them
argsrc:		defs	2	; argadd: the word, across the deref,
arglen:		defs	2	;   and how long it is
argw:		defs	ARGMAX	; the word being built,
argwn:		defs	1	;   and how much of it there is
argfn:		defs	ARGMAX	; the response file being read
argnest:	defs	1	; 0FFh while one is open,
arghand:	defs	1	;   and its handle
argbuf:		defs	ARGBUFS	; what has been read of it,
argbn:		defs	2	;   how much came back,
argbi:		defs	2	;   and how far through it we are
argchr:		defs	1	; one character, across that pointer
argcut:		defs	1	; 0FFh = the tail was 127 characters
argrdir:	defs	DOSPATH	; the directory the response file lives
				;   in, for the objects it names
argrf:		defs	2	; the range of list offsets its words
argrt:		defs	2	;   occupy - ONE contiguous span, because
				;   a file list may not name another
argfrf:		defs	1	; 0FFh = the word argnext just handed out
				;   started inside that range

msg_lnk:	defb	".lnk",0	; what a response file gets
