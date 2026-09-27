; srcline.as - where source lines come from.
;
; A small stack of "line sources" in ordinary RAM. the entry on top is the
; one being read; when it runs out it is removed and the one underneath
; carries on where it left off. In this phase the only kind of source is a 
; file being read; macro expansions and repeat blocks are added later.

SRCLIB		equ	1		; skips the externals in scrline.inc

		public	srcinit
		public	pushfile
		public	pushmac
		public	popsrc
		public	srcdep
		public	srctop
		public	getfnam
		public	srcopen
		public	entaddr		; errs.as walks the stack with it to
					;   print the origin trail
		public	filelin
		public	getline
		public	curfile
		public	curline
		public	passno

		include	srcline.inc
		include	strutil.inc	; strabs, strdirl, strcomp
		include	msxdos.inc
		include	ascii.inc
		include	errs.inc
		include	expand.inc	; mexline: the next line of an expansion

		cseg

; srcinit - start with no line sources and no file names at all.
;
; Input:	nothing
; Output:	the stack and the name table are empty
; Modifies:	AF

srcinit:	xor	a
		ld	(srcdep),a
		ld	(nopen),a
		ld	(nfiles),a
		ld	(envread),a	; TATARA has not been looked up
		ld	(curfile),a
		ld	(curline),a
		ld	(curline+1),a
		ret

; entaddr - work out where the entry for stack level A lives.
;
;   entry = srcstk + A*16, which is four doublings and an add.
;
; Input:	A = level, 0 = the bottom of the stack
; Output:	HL -> the entry
; Modifies:	AF, DE, HL

entaddr:	ld	l,a
		ld	h,0
		add	hl,hl		; x2
		add	hl,hl		; x4
		add	hl,hl		; x8
		add	hl,hl		; x16 = LSSIZE
		ld	de,srcstk
		add	hl,de
		ret

; bufaddr - work out where file buffer number A lives.
;
;   buffer = srcbufs + A*512: A*2 in the high byte, 0 in the low byte.
;
;   Numbered by open files, not by stack level: macro expansions read from
;   mapper RAM and use no buffer at all.
;
; Input:	A = buffer number, 0 = the first
; Output:	DE -> the buffer
; Modified:	AF, DE, HL

bufaddr:	add	a,a		; x2 -> whoel 256-byte pages
		ld	d,a
		ld	e,0		; DE = A * 512 = A * CHUNK
		ld	hl,srcbufs
		add	hl,de
		ex	de,hl
		ret

; pushfile - open a file and make it the source lines now come from.
;
;   Nothing is read from disk here: the entry starts with an empty buffer
;   and the first read happens when a line is actually asked for.
;
; Input:	DE -> filename, zero-terminated
; Output:	CY clear = open and on top of the stack
;		CY set   = MSX-DOS wouldn't open it
;		(nesting too deep does not return - errdeep stops)
; Modifies:	AF, BC, DE, HL, IX

pushfile:	ld	a,(srcdep)
		cp	MAXSRC
		jp	nc,errdeep	; no room on the stack
		ld	a,(nopen)
		cp	MAXINC
		jp	nc,errfile	; no buffer for another open file
		ld	(pfname),de	; keep the name: BDOS may change DE
		ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error (0 = fine), B = handle
		or	a
		scf
		ret	nz		; could not open it
		ld	a,b
		ld	(pfhand),a	; the handle to read from
		ld	de,(pfname)
		call	addfnam		; -> A = the number this name got
		ld	(pffnum),a
		ld	de,(pfname)	; and WHICH DIRECTORY it came from,
		ld	a,(nopen)	;   for any INCLUDE inside it. Indexed
		call	srcdir		;   like the buffers, and nopen has
					;   not been stepped yet

		ld	a,(srcdep)
		call	entaddr		; HL -> the new entry
		ld	(srctop),hl
		push	hl
		pop	ix		; IX -< the entry, for the fields below
		ld	a,(nopen)
		call	bufaddr		; DE -> this file's buffer
		ld	(ix+LS_KIND),LSK_FILE
		ld	a,(pfhand)
		ld	(ix+LS_HAND),a
		ld	a,(pffnum)
		ld	(ix+LS_FILE),a
		ld	(ix+LS_LINE),0	; no line handed over yet
		ld	(ix+LS_LINE+1),0
		ld	(ix+LS_BUF),e	; this level's buffer
		ld	(ix+LS_BUF+1),d
		ld	(ix+LS_PTR),e	; read position = start of buffer
		ld	(ix+LS_PTR+1),d
		ld	(ix+LS_LEFT),0	; with nothing in it yet
		ld	(ix+LS_LEFT+1),0
		ld	(ix+LS_EOF),0	; and not finished

		ld	a,(nopen)	; one more file open, one more buffer
		inc	a		; in use
		ld	(nopen),a
		ld	a,(srcdep)
		inc	a
		ld	(srcdep),a
		or	a		; clears CY = success
		ret

; srcopen - open an INCLUDEd file, looking in more than one place.
;
;   THE INCLUDING FILE'S DIRECTORY COMES FIRST, and not the current
;   directory. A B.INC sitting next to the file that asks for it must
;   win over an unrelated B.INC in whatever directory the assembler
;   happened to be started from. That is the fault - a second copy
;   somewhere the search order prefers - in a place where it would be
;   far quieter: the wrong file would assemble, and the complaint, if
;   any, would surface somewhere else entirely.
;
;   The current directory stays in the list, second, where it can only
;   be reached if the including file's own directory did not have the
;   file - so it can never shadow the right answer.
;
;   AN ABSOLUTE NAME IS OPENED AS TYPED AND NOWHERE ELSE. A name that
;   says which drive and which directory is not asking to be searched
;   for.
;
;   A candidate that would exceed DOSPATH is skipped and not an error:
;   it is one of several, and a later one may well open. If none does,
;   the caller's "cannot open" names the file and prints the trail.
;
; Input:	DE -> the name as written, ASCIIZ
; Output:	CY clear = open and on top of the stack
;		CY set   = not found in any of them
; Modifies:	AF, BC, DE, HL, IX

srcopen:	ld	(soname),de
		call	strabs		; strutil.as owns these now
		jr	nc,srco.rel
		ld	de,(soname)
		jp	pushfile	; absolute: this or nothing

srco.rel:	ld	a,(nopen)	; 1 - the including file's directory
		or	a
		jr	z,srco.cur	; nothing open: there is no includer
		dec	a		; the innermost OPEN FILE, which is
		call	sdaddr		;   not the top of the stack if a
					;   macro is expanding (D9)
		ld	de,(soname)
		call	strcomp
		jr	c,srco.cur	; too long to be worth trying
		ld	de,strbuf
		call	pushfile
		ret	nc

srco.cur:	ld	de,(soname)	; 2 - as typed: the current directory
		call	pushfile
		ret	nc

		call	srcenv		; 3 - each entry of TATARA in turn
		ld	hl,envbuf
srco.ev:	ld	a,(hl)
		or	a
		scf
		ret	z		; the list is used up: not found
		ld	de,(soname)
		call	strcomp		; -> HL at this entry's terminator
		jr	c,srco.evn	; too long: on to the next
		push	hl
		ld	de,strbuf
		call	pushfile
		pop	hl
		ret	nc
srco.evn:	ld	a,(hl)		; HL is at the ";" or at the end
		or	a
		scf
		ret	z		; that was the last entry
		inc	hl		; past the ";"
		jr	srco.ev

; srcdir - remember which directory an opening came from.
;
;   Called from pushfile with the open already done, so the name is one
;   MSX-DOS accepted and is therefore inside DOSPATH.
;
;   Everything up to and INCLUDING the last "\" or ":" is the
;   directory. A name with neither leaves an empty string, which
;   srccomp then treats as the current directory - which is exactly
;   what it means.
;
;   INDEXED BY nopen, like the read buffers and for the same reason:
;   popsrc closes files in the order they were opened, so the two are
;   one stack.
;
; Input:	DE -> the name that was opened, ASCIIZ
;		A   = nopen, before pushfile steps it
; Output:	incdirs slot A holds the directory
; Modifies:	AF, BC, DE, HL

srcdir:		push	de
		call	sdaddr		; HL -> the slot
		pop	de
		push	hl
		call	strdirl		; A = how much of it is directory
		pop	hl
		ex	de,hl		; HL -> the name, DE -> the slot
		or	a
		jr	z,sdir.end	; no separator: an empty directory
		ld	c,a
		ld	b,0
		ldir
sdir.end:	xor	a
		ld	(de),a
		ret

; sdaddr - address of open file A's directory (A * DOSPATH)
;
; Input:	A = which open file, 0 = the first
; Output:	HL -> its slot in incdirs
; Modifies:	AF, DE, HL

sdaddr:		ld	l,a
		ld	h,0
		add	hl,hl		; x2
		add	hl,hl		; x4
		add	hl,hl		; x8
		add	hl,hl		; x16
		add	hl,hl		; x32
		add	hl,hl		; x64 = DOSPATH
		ld	de,incdirs
		add	hl,de
		ret

; srcenv - fetch TATARA's value, once.
;
;   ONCE, AND FAILURES COUNT AS DONE. An assembly with forty includes
;   must not ask MSX-DOS forty times, and a machine with no such
;   variable must not be asked at all after the first time.
;
;   Under MSX-DOS 1 there are no environment variables, so the buffer
;   stays empty and the search simply has one place fewer to look - a
;   subdirectory layout still works there, as long as the includes are
;   written relative to the including file.
;
;   _GENV TRUNCATES WITHOUT A TERMINATOR when the buffer is too small,
;   and says ERR_ELONG. A search path that is quietly shorter than what
;   was set is worse than no search path, so that is an error.
;
; Input:	nothing
; Output:	envbuf holds the value, or is empty
; Modifies:	AF, BC, DE, HL

srcenv:		ld	a,(envread)
		or	a
		ret	nz		; asked once already
		ld	a,1
		ld	(envread),a
		xor	a
		ld	(envbuf),a	; empty unless proved otherwise
		call	dosver
		ret	c		; MSX-DOS 1: there are none
		ld	hl,msg_envt
		ld	de,envbuf
		ld	b,MAXENV
		system	_GENV
		or	a
		ret	z		; the value is in the buffer
		cp	ERR_ELONG
		jp	z,errenvl
		xor	a
		ld	(envbuf),a	; any other refusal: no path
		ret

msg_envt:	defb	"TATARA",0	; MSX-DOS upper-cases a variable's
					;   name when it is set and compares
					;   without case, so this spelling is
					;   the whole of it

; pushmac - make a macro expansion the source lines now come from.
;
;   Note what is NOT here: no file is opened, and nopen is not touched.
;   An expansion reads from mapper RAM and needs no buffer, which is why
;   the buffers are indexed by how many FILES are open rather than by
;   deep the stack is.
;
; Input:	HL -> the expansion record's far pointer
; 		A   = the file the definition came from (MD_DEFFIL)
; Output:	CY clear = it is on top of the stack
;		(too deep does not return - errdeep stops)
; Modifies:	AF, BC, DE, HL, IX

pushmac:	ld	(pmfp),hl
		ld	(pmfil),a
		ld	a,(srcdep)
		cp	MAXSRC
		jp	nc,errdeep	; almost always runaway recursion

		ld	a,(srcdep)
		call	entaddr		; HL -> the new entry
		ld	(srctop),hl
		push	hl
		pop	ix
		ld	(ix+LS_KIND),LSK_MACRO
		ld	a,(pmfil)
		ld	(ix+LS_FILE),a	; where the DEFINITION came from
		ld	(ix+LS_LINE),0	; no body line delivered yet
		ld	(ix+LS_LINE+1),0
		ld	(ix+LS_EOF),0

		push	ix		; the far pointer goes in LS_MX
		pop	de
		ld	hl,LS_MX
		add	hl,de
		ex	de,hl		; DE -> LS_MX in the entry
		ld	hl,(pmfp)
		ld	bc,4
		ldir

		ld	a,(srcdep)
		inc	a
		ld	(srcdep),a
		or	a		; clears CY = pushed
		ret

; popsrc - remove the top line source, closing its file if it had one.
;
; Input:	nothing
; Output:	srcdep and srctop updated
; Modifies:	AF, BC, DE, HL, IX

popsrc:		ld	a,(srcdep)
		or	a
		ret	z		; nothing stacked - nothing to do
		dec	a
		ld	(srcdep),a
		call	entaddr		; HL -> the entry being removed
		push	hl
		pop	ix
		ld	a,(ix+LS_KIND)
		cp	LSK_FILE
		jr	nz,popsrc.upd	; other kinds have no file to close
		ld	b,(ix+LS_HAND)
		system	_CLOSE
		ld	a,(nopen)	; its buffer is free again. Files are
		dec	a		; always closed in the reverse order
		ld	(nopen),a	; they were opened, so this is enough
popsrc.upd:	ld	a,(srcdep)
		or	a
		ret	z		; the stack is empty now
		dec	a
		call	entaddr		; HL -> the entry underneath
		ld	(srctop),hl
		ret

; addfnam - remember a file name so messages can print it, and give it a
;   number. The same file opened twice gets two numbers on purpose: that
;   keeps the two openings apart in an error trail.
;
; Input:	DE -> filename, zero-terminated
; Output:	A = the number given to this name
; Modifies:	AF, BC, DE, HL

addfnam:	ld	a,(nfiles)
		cp	MAXFILE
		jp	nc,errfnum	; more names than the table holds
		push	af
		call	fnaddr		; HL -> this number's slot
		ex	de,hl		; DE -> the slot, HL -> the name
		ld	bc,MAXFNAM
addfnam.cp:	ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,addfnam.end	; copied the terminator too
		inc	hl
		inc	de
		dec	bc
		ld	a,b
		or	c
		jr	nz,addfnam.cp
		dec	de
		xor	a
		ld	(de),a		; too long: force a terminator back in
addfnam.end:	pop	af		; A = the number this name got
		push	af
		inc	a
		ld	(nfiles),a
		pop	af
		ret

; getfnam - find the name that goes with a file number.
;
; Input:	A = file number
; Output:	DE -> the name, zero-terminated
; Modifies:	AF, HL

getfnam:	call	fnaddr
		ex	de,hl
		ret

; fnaddr - address of file number A in the name table (A * MAXFNAM)
;
; Input:	A = file number
; Output:	HL -> that number's slot
; Modifies:	AF, DE, HL

fnaddr:		ld	l,a
		ld	h,0
		add	hl,hl		; x2
		add	hl,hl		; x4
		add	hl,hl		; x8
		add	hl,hl		; x16
		add	hl,hl		; x32 = MAXFNAM. ONE SHIFT PER
					;   DOUBLING, so this chain and the
					;   equate move together or the table
					;   tears
		push	de
		ld	de,fnamtab
		add	hl,de
		pop	de
		ret

; filerf - refill this file's buffer from disk.
;
;   Nothing else in the module talks to MSX-DOS.
;
; Input:	IX -> a line source entry of the file kind
; Output:	CY clear = the buffer holds fresh bytes
;		CY set   = nothing more to read; the entry is marked
;                          finished
; Modifies:	AF, BC, DE, HL

filerf:		ld	b,(ix+LS_HAND)
		ld	e,(ix+LS_BUF)
		ld	d,(ix+LS_BUF+1)
		ld	hl,CHUNK
		system	_READ		; -> A = error, HL = bytes read
		or	a
		jr	nz,filerf.no	; any error, end of file included
		ld	a,h
		or	l
		jr	z,filerf.no	; zero bytes = end of file
		ld	(ix+LS_LEFT),l	; this much is now unread
		ld	(ix+LS_LEFT+1),h
		ld	a,(ix+LS_BUF)	; and we start at the beginning
		ld	(ix+LS_PTR),a
		ld	a,(ix+LS_BUF+1)
		ld	(ix+LS_PTR+1),a
		or	a		; clears CY = fresh bytes available
		ret
filerf.no:	ld	(ix+LS_EOF),1
		ld	(ix+LS_LEFT),0
		ld	(ix+LS_LEFT+1),0
		scf
		ret

; filech - take the next byte of this file, refilling if needed.
;
;   BC and DE are preserved because filelin keeps the line length in B
;   and the write position in DE, and a refill uses both.
;
; Input:	IX -> a line source entry of the file kind
; Output:	CY clear = A is the next byte
;		CY set   = there are no more bytes
; Modifies:	AF, HL

filech:		ld	a,(ix+LS_EOF)
		or	a
		scf
		ret	nz		; already finished
		ld	l,(ix+LS_LEFT)
		ld	h,(ix+LS_LEFT+1)
		ld	a,h
		or	l
		jr	nz,filech.get	; still something in the buffer
		push	bc
		push	de
		call	filerf		; empty -> go and get more
		pop	de
		pop	bc
		ret	c		; nothing more anywhere
filech.get:	ld	l,(ix+LS_PTR)
		ld	h,(ix+LS_PTR+1)
		ld	a,(hl)		; the byte we came for
		inc	hl
		ld	(ix+LS_PTR),l
		ld	(ix+LS_PTR+1),h
		ld	l,(ix+LS_LEFT)
		ld	h,(ix+LS_LEFT+1)
		dec	hl
		ld	(ix+LS_LEFT),l
		ld	(ix+LS_LEFT+1),h
		or	a		; clears CY; A keeps the byte
		ret

; filelin - collect the next line from a file source.
;
;   CR is ignored and LF ends the line, so CF+LF fiels and files with
;   lone LFs both work. A last line with no line ending at all is still
;   handed over.
;
; Input:	IX -> a line source entry of the file kind
;		HL -> where to put the line
; Output:	CY clear = line stored, zero-terminated, A = its length,
;		           and the entry's line number has gone up by one
;		CY set   = this file has no more lines
; Modifies:	AF, BC, DE, HL

filelin:	ex	de,hl		; DE = where the line goes
		ld	b,0		; B = characters colllected so far
filelin.ch:	call	filech
		jr	c,filelin.eof
		cp	CHR_SUB		; Ctrl-Z: the file ends here
		jr	z,filelin.z
		cp	CHR_CR
		jr	z,filelin.ch	; ignored; LF is what ends a line
		cp	CHR_LF
		jr	z,filelin.end
		ld	c,a		; keep the character
		ld	a,b
		cp	MAXLINE
		jp	nc,errlong	; no room for it: report and stop
		ld	a,c
		ld	(de),a
		inc	de
		inc	b
		jr	filelin.ch

filelin.z:	ld	(ix+LS_EOF),1	; nothing after Ctrl-Z counts
filelin.eof:	ld	a,b
		or	a
		jr	nz,filelin.end	; a last line with no LF: hand it over
		scf			; nothing collected: the file is done
		ret

filelin.end:	xor	a
		ld	(de),a		; terminate the line
		ld	l,(ix+LS_LINE)	; one more line handed over
		ld	h,(ix+LS_LINE+1)
		inc	hl
		ld	(ix+LS_LINE),l
		ld	(ix+LS_LINE+1),h
		ld	a,b		; A = length
		or	a		; clears CY = a line is there
		ret

; getline - the next source line, from whatever is on top of the stack.
;
;   When a source runs out it is removed here and the one underneath is
;   asked instead, so the caller never sees the join. Only files exist in
;   here; the call to filelin becomes a dispatch on the
;   entry's LS_KIND.
;
; Input:	HL -> where to put the line
; Output:	CY clear = line stored, zero-terminated, A = its length,
;			curfile and curline say where it came from
;		CY set   = no more lines from any source
; Modifies:	AF, BC, DE, HL, IX

getline:	push	hl		; the line buff, kept safe from popsrc
getline.try:	ld	a,(srcdep)
		or	a
		jr	z,getline.no	; nothing stacked: no more lines
		ld	ix,(srctop)
		pop	hl
		push	hl		; HL -> the line buffer again

		ld	a,(ix+LS_KIND)	; which sort of source is this?
		cp	LSK_FILE
		jr	nz,getline.mac
		call	filelin
		jr	getline.got
getline.mac:	call	mexline
getline.got:	jr	c,getline.pop	; this source has nothing left

		ld	b,a		; keep the length out of the way
		ld	a,(ix+LS_FILE)	; note where this line came from
		ld	(curfile),a
		ld	a,(ix+LS_LINE)
		ld	(curline),a
		ld	a,(ix+LS_LINE+1)
		ld	(curline+1),a
		pop	hl
		ld	a,b		; A = the length again
		or	a		; claers CY = a line is there
		ret

getline.pop:	call	popsrc		; done with it: close and remove
		jr	getline.try	; carry on with the one underneath

getline.no:	pop	hl
		scf			; CY set = nothing anywhere
		ret

		dseg

srcdep:		defs	1	; how many sources are stacked
srctop:		defs	2	; address of the top entry
curfile:	defs	1	; file number of the line just handed over
curline:	defs	2	; line number of the line just handed over
passno:		defs	1	; which pass is running, 1 or 2. The driver owns
				; its value; cndtest reads it for IF1/IF2 and
				; the line loop for whether to emit. NOT reset
				; by srcinit, which runs once per pass and
				; would undo it
nopen:		defs	1	; how many files are open (= buffers used)
nfiles:		defs	1	; names used in the table so far

pfname:		defs	2	; pushfile: the name it was given
pfhand:		defs	1	; pushfile: the handle MSX-DOS returned
pffnum:		defs	1	; pushfile: the number for that name

pmfp:		defs	2	; pushmac: the far pointer it was given
pmfil:		defs	1	; pushmac: the definition's file number

soname:		defs	2	; srcopen: the name it was given
envread:	defs	1	; 0 = TATARA has not been looked up yet

srcstk:		defs	MAXSRC*LSSIZE	; the stack itself
fnamtab:	defs	MAXFILE*MAXFNAM	; file names, for messages
srcbufs:	defs	MAXINC*CHUNK	; one buffer per OPEN FILE
incdirs:	defs	MAXINC*DOSPATH	; the directory each OPEN FILE came
					;   from, indexed exactly like srcbufs
envbuf:		defs	MAXENV		; TATARA's value, read once
					; (the candidate being tried is
					;  strutil.as's strbuf)

