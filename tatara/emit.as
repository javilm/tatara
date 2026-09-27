; emit.as - the bytes an assembled line comes to.
;
;   MEASURING CAME FIRST: every handler returned a length and nothing
;   was ever evaluated. Emitting came after, and the length became how
;   bytes went through here - so a handler can no longer say three and
;   write four, which is a wrong program with no error message.
;
;   emitb is the sink. Everything below ends in a jp to it, and
;   an earlier design expected it to be replaced. IT DID NOT NEED
;   TO: MAXEMIT is 256, which is exactly the most a line can
;   emit, so emitbuf holds every byte of a line and the DATA record is
;   written from it at the end of the line. The sink is unchanged
;   and the listing and the object file read the same buffer.
;
;   Pass 1 goes through all of this too, emitting zeros where an
;   expression should be and throwing the result away. That is safe for
;   exactly one reason - no value changes any length - and it is what
;   lets one set of handlers serve both passes.

EMITLIB		equ	1		; skips the externals in emit.inc

		public	emitinit
		public	emitval
		public	lstline		; the driver's tail, made
		public	lstbody		;   callable - macdef lists the
		public	lston		;   lines it reads itself
		public	lsttset		; TITLE and SUBTTL, the page
		public	lsteject	;   break PAGE asks for, how long
		public	lstpset		;   a page is, and the title
		public	lsttitl		;   itself, which names the module
		public	lstinit		; the listing's per-pass
		public	lstend		;   reset, the last page, and the
		public	emitchr		;   one-character write a name
					;   out of the mapper needs
		public	lstcrlf		;   and the line ending those two
		public	emitsp		;   walks put between their lines,
					;   and the padding one of them owes
					;   a short name
		public	emitraw		; and the two routines that put
		public	emitln		;   bytes and lines out, which moved
		public	outhand		;   with it, and the handle they use
		public	emitb
		public	emitw
		public	emitx
		public	emitxw
		public	emithi
		public	emitpfx
		public	emitmore
		public	emitn
		public	emitbuf
		public	lstaddr		; they are written into a DATA
		public	lstseg		;   record: they are where the
					;   line's bytes belong
		public	lstmac		; and where the line
					;   itself came from
		public	lstcall		; the driver says when a line
					;   called a macro, for .SALL's "+"
		public	lstmode
		public	emitop
		public	emitd
		public	emitxs
		public	emitxws
		public	exsval
		public	emitjr

		include	emit.inc
		include	optab.inc	; opxtext, opdtext, opfix, opkind
		include	expr.inc	; evalexp, exty, SY_ABS
		include	errs.inc	; errrel
		include	strutil.inc	; numhex, numhex2
		include	srcline.inc	; passno, LSK_MACRO
		include	cmdline.inc	; optscrn, optlist, lstname: the
					;   three reasons to write text
		include	dos2func.inc	; _GDATE, for the header's date
		include	symtab.inc	; lstsyms and lstmacs: the last page
		include	macros.inc	;   is their tables, and they write it
		include	msxdos.inc	; _WRITE: emitraw and emitln moved
		include	ascii.inc	;   here, and CHR_CR/CHR_LF
					;   are what emitln puts over the
					;   terminator
		include	objout.inc	; objfix: emitxw is where a
					;   relocatable word is seen

		cseg

; emitinit - start a line: where it begins, and nothing emitted yet.
;
;   PER LINE. Every other init in the program is per pass or per run;
;   this one runs from main.loop once a line has been split, because
;   emitn is what the listing prints and what checks a
;   handler's claimed length against.
;
;   IT IS TOLD THE ADDRESS RATHER THAN FETCHING IT. locctr and curseg
;   live in symtab.as and the listing columns live here, so otherwise
;   one module would reach into the other's data. The verification
;   rule's answer to that is a small routine and not a new global, and
;   this is the routine: main.loop knows both already.
;
; Input:	HL = where the line begins
;		A  = its segment index
;		B  = non-zero if the line carries a label, which with
;		     the byte count decides whether the listing shows
;		     an address at all
; Output:	(lstaddr), (lstseg), (lstmac), (lstlab), (lstcall) = 0
;		and (emitn) = 0
; Modifies:	AF, HL

emitinit:	ld	(lstaddr),hl
		ld	(lstseg),a
		ld	a,b
		ld	(lstlab),a	; DID IT CARRY A LABEL? M80 shows an
		xor	a		;   address for a line with one, or
		ld	(lstcall),a	;   one that emitted - and nothing
					;   else. The driver sets lstcall
					;   after this, on the macro-call path
		ld	hl,(srctop)	; AND WHERE THE LINE CAME FROM, now,
		ld	a,(hl)		;   while it still says this line's
		ld	(lstmac),a	;   source. A macro call pushes its
		ld	hl,0		;   body before the call line is
		ld	(emitn),hl	;   listed, so asking later would
		ret			;   call a file line an expansion

; emitval - the address column shows a VALUE rather than a place.
;
;   EQU and DEFL name a value, and M80 puts it where the address would
;   go. It overwrites what emitinit recorded at the top of the line,
;   which is all this takes - and THE RELOCATION MARK FALLS OUT, since
;   that is built from the type: a space for an absolute value, "'" for
;   one relative to a segment, decided by nothing that is written here.
;
; Input:	HL = the value
;		A  = its type (exty)
; Output:	the listing's address column is that value
; Modifies:	nothing

emitval:	ld	(lstaddr),hl
		ld	(lstseg),a
		ret

; emitb - one byte on its way out. THE SINK.
;
;   Past MAXEMIT it keeps counting and stops storing. The count is what
;   locctr and the cross-check use, so it must never be capped; the
;   buffer is only what the listing prints, so losing its tail costs a
;   cosmetic column on a line nobody writes.
;
; Input:	A = the byte
; Output:	it is counted, and stored if there is room
; Modifies:	NOTHING - the pop af puts the flags back too, which
;		is worth having in a routine every encoder calls
;		between one half of an opcode and the other

emitb:		push	hl
		push	de
		push	af
		ld	hl,(emitn)
		ld	de,MAXEMIT
		or	a
		sbc	hl,de
		jr	nc,emitb.no	; full: count it and no more
		ld	hl,(emitn)
		ld	de,emitbuf
		add	hl,de
		pop	af
		ld	(hl),a
		push	af
emitb.no:	ld	hl,(emitn)
		inc	hl
		ld	(emitn),hl
		pop	af
		pop	de
		pop	hl
		ret

; emitw - a word, low byte first, which is the Z80's order and the one
;   every 16-bit operand and every DW uses.
;
; Input:	HL = the word
; Output:	two bytes out
; Modifies:	AF

emitw:		ld	a,l
		call	emitb
		ld	a,h
		jp	emitb

; emitx - the expression at DE, as ONE byte.
;
;   ON PASS 1 IT DOES NOT LOOK AT THE TEXT. It emits a zero and counts
;   it, because the length of a line never depends on what an expression
;   is worth and nothing reads pass 1's bytes. Evaluating here would
;   report an undefined symbol for "db later" - a forward reference,
;   which is the whole reason there are two passes. TESTS\EMFWD.AS.
;
; Input:	DE -> the text
;		A  = how long it is
; Output:	one byte out
; Modifies:	AF, BC, DE, HL

emitx:		ld	c,a		; the length, across the pass test
		ld	a,(passno)
		cp	2
		jr	z,emitx.go
		xor	a
		jp	emitb		; pass 1: a byte worth nothing
emitx.go:	ld	a,c
		call	evalexp
		ld	a,(exty)
		cp	SY_ABS
		jp	nz,errrel	; ONE byte cannot hold a value the
					;   linker still has to add to. M80
					;   refuses it too; "db low lab" is
					;   how you say what you meant
		ld	a,l
		jp	emitb

; emitxw - the same, as TWO bytes.
;
;   No test on the type here, and that is deliberate: two bytes CAN hold
;   a relocatable or external value, because what goes in the hole is
;   the addend and the linker adds the rest. The record that tells it to
;   is the object writer's; this leaves the right bytes in the right
;   and says so in emit-design.md 7.
;
; Input:	DE -> the text
;		A  = how long it is
; Output:	two bytes out
; Modifies:	AF, BC, DE, HL

emitxw:		ld	c,a
		ld	a,(passno)
		cp	2
		jr	z,emitxw.go
		ld	hl,0
		jp	emitw		; pass 1: two bytes worth nothing
emitxw.go:	ld	a,c
		call	evalexp
		push	hl		; the ADDEND goes in the hole. What
		ld	hl,(emitn)	;   has to be added to it is the
		ld	de,(lstaddr)	;   business, and it needs to know
		add	hl,de		;   where the hole is - which is
		call	objfix		;   exactly here, before the word
		pop	hl		;   goes out
		jp	emitw

; emitxs, emitxws - the expression the parser remembered, as one byte
;   or as two.
;
;   The wrappers that were expected with the first instruction
;   handler, over the emitx and emitxw that take their text in
;   registers. DB, DW and DC keep using those directly: dbwalk knows
;   where each item begins and ends at the moment it emits it, and
;   never needs a slot.
;
; Input:	nothing
; Output:	one byte / two
; Modifies:	AF, BC, DE, HL

emitxs:		call	opxtext
		jp	emitx

emitxws:	call	opxtext
		jp	emitxw

; exsval - the remembered expression's VALUE.
;
;   For an expression that goes into an OPCODE rather than a byte of
;   its own: RST's operand, IM's, and BIT's number.
;
;   ZERO ON PASS 1, without evaluating - and the zero is not arbitrary.
;   "rst 0" is an instruction, "im 0" is an instruction, and a
;   displacement of 0 is in range, so it passes every check the
;   will hand it. That is what lets "rst later" work with later
;   defined below: a placeholder that could FAIL a pass-2 check would
;   turn every forward reference into a false error, which is the
;   whole thing emitx was built to avoid.
;
; Input:	nothing
; Output:	HL = the value, or 0 on pass 1
; Modifies:	AF, BC, DE, HL

exsval:		ld	a,(passno)
		cp	2
		jr	z,exsv.go
		ld	hl,0
		ret
exsv.go:	call	opxtext
		jp	evalexp

; emitd - the displacement the last indexed operand carried, as one
;   SIGNED byte.
;
;   "(ix)" is "(ix+0)": the byte goes out whether the source wrote one
;   or not, because every indexed encoding has room for it. JP is the
;   one exception, and "jp (ix+5)" is refused rather than making this
;   routine care.
;
;   THE RANGE CHECK IS HERE and nowhere else, which is why it covers
;   every indexed instruction in the program from the first one that
;   encodes: they all reach their displacement through this routine.
;
; Input:	nothing
; Output:	one byte
; Modifies:	AF, BC, DE, HL

emitd:		call	opdtext
		or	a
		jr	nz,emitd.n
		xor	a
		jp	emitb		; none written: "(ix)" is "(ix+0)"
emitd.n:	ld	c,a		; the length, across the pass test
		ld	a,(passno)
		cp	2
		jr	z,emitd.go
		xor	a
		jp	emitb		; pass 1: a byte worth nothing
emitd.go:	ld	a,c
		call	evalexp
		ld	a,(exty)
		cp	SY_ABS
		jp	nz,errrel	; a displacement the linker would have
					;   to adjust is not a thing
		ld	a,h		; a signed byte is 0000-007F or
		or	a		;   FF80-FFFF and nothing else
		jr	z,emitd.p
		inc	a
		jp	nz,errdisp
		ld	a,l
		and	080h
		jp	z,errdisp
		jr	emitd.em
emitd.p:	ld	a,l
		and	080h
		jp	nz,errdisp
emitd.em:	ld	a,l
		jp	emitb

; emitjr - the expression the parser remembered, as a RELATIVE
;   displacement: one signed byte.
;
;   THE ONLY PLACE IN THE PROGRAM THAT SUBTRACTS ONE ADDRESS FROM
;   ANOTHER. The target is measured from the address AFTER the
;   instruction, and the opcode has already gone out when this is
;   called, so that address is lstaddr + emitn + 1: where the line
;   began, plus what it has emitted, plus the byte about to go out.
;   Nothing is passed in and locctr is not read.
;
;   A displacement between two CONTRIBUTIONS is not a number. The linker
;   places them independently, so the distance is unknown here, and
;   there is no relocation record that can fix up a displacement later -
;   two bytes can carry an addend, one relative byte cannot. The target
;   must be absolute or in the same contribution as the instruction,
;   which is exty against lstseg: SY_TYPE holds a segment's index and
;   lstseg is the same space.
;
;   PASS 1 EMITS A ZERO without reading the text, as emitx and emitd do.
;   No value changes a length, and zero is in range - which is what lets
;   "jr later" work with LATER defined below the line that jumps to it.
;
; Input:	nothing (the remembered expression, lstaddr, lstseg,
;		emitn)
; Output:	one byte
; Modifies:	AF, BC, DE, HL

emitjr:		ld	a,(passno)
		cp	2
		jr	z,emitjr.2
		xor	a
		jp	emitb		; pass 1: a byte worth nothing
emitjr.2:	call	opxtext		; DE -> the text, A = how long
		or	a
		jp	z,erroper	; a JR with nothing after it
		call	evalexp		; HL = the target
		ld	a,(exty)
		cp	SY_ABS
		jr	z,emitjr.k	; absolute: always subtractable
		ld	c,a
		ld	a,(lstseg)
		cp	c
		jp	nz,errrel	; another contribution: the distance
					;   is not known here and no record
					;   can fix a displacement later
emitjr.k:	ld	de,(lstaddr)	; where the NEXT instruction starts:
		push	hl		;   this line, plus what it has
		ld	hl,(emitn)	;   emitted, plus this byte
		inc	hl
		add	hl,de
		ex	de,hl
		pop	hl
		or	a
		sbc	hl,de		; the target, less that
		ld	a,h		; a signed byte is 0000-007F or
		or	a		;   FF80-FFFF and nothing else
		jr	z,emitjr.p
		inc	a
		jp	nz,errjr
		ld	a,l
		and	080h
		jp	z,errjr
		jr	emitjr.e
emitjr.p:	ld	a,l
		and	080h
		jp	nz,errjr
emitjr.e:	ld	a,l
		jp	emitb

; emitop - an opcode in the ORDINARY shape: the prefix an index
;   register forces goes out FIRST, the opcode next, the displacement
;   LAST.
;
;   This is what clsxtra becomes. clsxtra added those same bytes to a
;   LENGTH and had no opinion about their order, which is the whole
;   difference between measuring and emitting - and it is why one
;   routine can replace it at every site rather than every handler
;   restating the rule.
;
;   THE CB GROUP DOES NOT COME THROUGH HERE. Its order is prefix, CB,
;   displacement, opcode - the only place in the instruction set where
;   the operand byte precedes the opcode. The
;   two classes that cannot call this are exactly the two that are
;   different, which is the contrast being drawn.
;
; Input:	A = the opcode
; Output:	one to three bytes
; Modifies:	AF, BC, DE, HL

emitop:		ld	c,a
		ld	a,(opfix)
		or	a
		call	nz,emitb	; DD or FD, if the operand forced one
		ld	a,c
		call	emitb
		ld	a,(opkind)
		cp	OK_IDX
		ret	nz		; not indexed: nothing follows
		jp	emitd

; emithi - set bit 7 of the last byte emitted.
;
;   DC and nothing else: 2.6.5 says the last character of the string
;   carries the high bit, and it is the last one only once the whole
;   string has gone out. If the buffer truncated, the byte is not there
;   to set - which cannot happen for a DC, because a DC is ONE string
;   and a string is at most the operand field.
;
; Input:	nothing
; Output:	the last byte in emitbuf has bit 7 set
; Modifies:	AF, DE, HL

emithi:		ld	hl,(emitn)
		ld	a,h
		or	l
		ret	z		; nothing emitted: nothing to set
		ld	de,MAXEMIT+1
		or	a
		sbc	hl,de
		ret	nc		; past the buffer: not there to set
		ld	hl,(emitn)
		dec	hl
		ld	de,emitbuf
		add	hl,de
		ld	a,(hl)
		or	080h
		ld	(hl),a
		ret

; emitraw - write A bytes starting at DE, exactly as they are.
;   No terminator, no CR+LF. Asking for 0 bytes writes nothing at all,
;   which is what makes an empty field print as "[]".
;
; Input:	DE -> the bytes
;		A   = how many
; Output:	they are written
; Modifies:	AF, BC, DE, HL - EVERYTHING. MSX-DOS's _WRITE gives
;		back A and HL and keeps nothing else, DE included. This
;		line said "AF, BC, HL", and emitln believed it:
;		it kept its read pointer in DE across a write and read
;		the rest of every line out of whatever DOS left there

emitraw:	or	a
		ret	z		; nothing to write
		ld	l,a
		ld	h,0		; HL = how many bytes
		ld	a,(outhand)
		ld	b,a		; B = the handle
		system	_WRITE		; -> A = the error
		or	a
		ret	z
		jp	errwrit		; disk full, or write-protected

; emitln - write one line, followed by CR+LF, to wherever output goes.
;
;   The CR and LF are written over the line's own zero terminator, which
;   is why linebuf has two spare bytes at the end. One MSX-DOS call per
;   line, and never a request to write zero bytes.
;
; Input:	DE -> the line, zero-terminated
;		A = its length
; Output:	the line is written
; Modifies:	AF, BC, DE, HL

emitln:		ld	(elnleft),a	; how many characters are left
		ld	a,c
		ld	(elncol),a	;   and which column we are at
		ld	h,d		; AND WHERE TO READ, IN RAM: _WRITE
		ld	l,e		;   does not give DE back, so nothing
		ld	(elnptr),hl	;   may hold a pointer across a write
emitln.lp:	ld	a,(elnleft)
		or	a
		jr	z,emitln.eol
		ld	de,(elnptr)
		ld	a,(de)
		cp	CHR_TAB
		jr	z,emitln.tab

		ld	h,d		; a run of ordinary characters: how
		ld	l,e		;   far does it go? HL walks, DE
		ld	b,0		;   stays at its start, for the write
		ld	a,(elnleft)
		ld	c,a
emitln.rn:	ld	a,(hl)
		cp	CHR_TAB
		jr	z,emitln.rn2
		inc	hl
		inc	b
		dec	c
		jr	nz,emitln.rn
emitln.rn2:	ld	a,b
		ld	(elnrun),a	; emitraw keeps NOTHING: AF, BC, DE
		call	emitraw		;   and HL are all gone afterwards
		ld	a,(elnrun)
		ld	c,a
		ld	a,(elncol)	; the column and the count move on
		add	a,c		;   by the run
		ld	(elncol),a
		ld	a,(elnleft)
		sub	c
		ld	(elnleft),a
		ld	hl,(elnptr)	; and so does the read pointer
		ld	d,0
		ld	e,c
		add	hl,de
		ld	(elnptr),hl
		jr	emitln.lp

emitln.tab:	ld	hl,(elnptr)	; over the tab itself
		inc	hl
		ld	(elnptr),hl
		ld	hl,elnleft
		dec	(hl)
		ld	a,(elncol)
		ld	c,a		; where we are now
		or	7		; and the NEXT stop, which is a
		inc	a		;   different column even when we are
		ld	(elncol),a	;   already on one: a tab moves
		sub	c		; how many spaces that is, 1 to 8
		ld	de,elnsp
		call	emitraw
		jr	emitln.lp

emitln.eol:	ld	de,elncrlf	; AND THE LINE ENDS WITHOUT THE
		ld	a,2		;   BUFFER BEING TOUCHED. It used to
		jp	emitraw		;   take the CR and LF over the zero
					;   terminator, which is why linebuf
					;   has two spare bytes - and why
					;   macdef, which lists a line before
					;   splitln reads it, was handed one
					;   with no end

elncrlf:	defb	CHR_CR,CHR_LF
elnsp:		defb	"        "	; eight, the most a tab can need
lstffd:		defb	CHR_FF		; the page break itself
lstdash:	defb	"-"
lstsym0:	defb	"S"		; the last page's number
lstpgw:		defb	"PAGE    "	; and the four spaces after it
lstmacw:	defb	"Macros:"
lstsymw:	defb	"Symbols:"

; THE NAME IN THE HEADER IS OURS. M80 writes "MSX.M-80 2.00" there and
; Tatara writes this: the columns are M80's, the text is not, because a
; listing should say what made it.


lstmon:		defb	"Jan",0,"Feb",0,"Mar",0,"Apr",0
		defb	"May",0,"Jun",0,"Jul",0,"Aug",0
		defb	"Sep",0,"Oct",0,"Nov",0,"Dec",0

; lstline - list one source line, if anything is listening.
;
;   THE DRIVER'S TAIL, MADE CALLABLE. It was the end of main.emit until
;   it moved because macdef lists the lines it collects and
;   has to do it the same way: the modes, the three reasons to want
;   text, the columns, the continuation lines. One copy.
;
;   It tests passno itself, so a caller in the middle of pass 1 needs
;   no guard of its own.
;
; Input:	DE -> the text
;		A  = its length
; Output:	nothing, or a listing line
; Modifies:	AF, BC, DE, HL

lstline:	ld	(lstltx),de
		ld	(lstllen),a
		ld	a,(passno)
		cp	2
		ret	nz
		ld	a,(lston)	; .XLIST
		or	a
		ret	z
		ld	a,(lstmac)	; out of a macro? Then how much of
		cp	LSK_MACRO	;   the expansion shows is the mode
		jr	nz,lstl.go
		ld	a,(lstmode)
		cp	LST_SALL
		ret	z
		cp	LST_XALL
		jr	nz,lstl.go
		ld	hl,(emitn)	; .XALL: only the lines that emitted
		ld	a,h
		or	l
		ret	z
lstl.go:	ld	a,(optscrn)	; /P, /L, or a listing file to put it
		ld	hl,optlist	;   in: any of the three asks for the
		or	(hl)		;   text, and with none of them an
		ld	hl,lstname	;   assembly is silent but for its
		or	(hl)		;   errors and its summary line
		ret	z
		ld	a,(lstlleft)	; room on this page? The counter
		or	a		;   starts at zero, so the first line
		call	z,lstpage	;   of a listing writes a header and
		ld	hl,lstlleft	;   no form feed
		dec	(hl)
		ld	a,(optlist)	; /L: the address and the bytes go in
		or	a		;   front, and the source line follows
		ld	c,0		;   unchanged. WITHOUT a prefix the
		jr	z,lstl.txt	;   text starts at column zero
		call	emitpfx
		ld	c,a		; WITH one, it starts where the prefix
		push	bc		;   ends - and that is what the tab
		call	emitraw		;   stops are counted from
		pop	bc
lstl.txt:	ld	de,(lstltx)
		ld	a,(lstllen)
		call	emitln
		ld	a,(optlist)	; more than MAXSHOW bytes? They wrap,
		or	a		;   one column-wide line each, with no
		jr	z,lstl.done	;   source text
lstl.mor:	call	emitmore
		jr	c,lstl.done
		ld	c,0		; a built column, and no tabs in it
		call	emitln
		jr	lstl.mor

; The line is written. Did a PAGE directive on it ask for a break? Then
; it happens HERE, after the line and not before it: the directive
; belongs to the page it was written on. The next line finds lstlleft
; at zero and writes a header, exactly as the first line of a listing
; does.

lstl.done:	ld	a,(lstpend)
		or	a
		ret	z
		xor	a
		ld	(lstpend),a
		ld	(lstlleft),a	; A SUBPAGE, not a main page: M80
		ret			;   answers 1-1, which PAGEDIR.AS
					;   asked it. Nothing moves the main
					;   number yet - a TITLE is what
					;   probably does, and no test says so

; lstinit - the listing, back to where a pass starts it.
;
;   PER PASS, from main.pass, for the same reason segrst and cndinit
;   are: a .XLIST on pass 1 must not silence pass 2. It also sets the
;   page number, which nothing else did - the first listing came out
;   headed PAGE 0.
;
; Input:	nothing
; Output:	listing on, .XALL, page 1, and a page break due
; Modifies:	AF

lstinit:	ld	a,0ffh
		ld	(lston),a
		ld	a,LST_XALL
		ld	(lstmode),a
		ld	a,1
		ld	(lstpage1),a
		xor	a
		ld	(lstsub),a
		ld	(lstlleft),a	; zero: the first line writes a
		ld	(lstsubt),a	;   header, and no form feed
		ld	(lstpend),a	; THE SUBTITLE AND NOT THE TITLE:
		ld	a,PAGELEN	;   M80 keeps a title from pass 1
		ld	(lstplen),a	;   and does not keep a subtitle,
		ret			;   which TITLLST.PRN shows

; lstpage - start a page: the form feed, the header, two blank lines.
;
;   M80'S COLUMNS, measured off its own LONGLST.PRN: eight spaces, the
;   name and version, three spaces, the date, seven spaces, "PAGE",
;   four spaces, the number. THE NAME IS OURS - the columns are M80's
;   and the text is not, because a listing should say what made it.
;
;   Written in pieces. The header is 49 characters and lstbuf is 40,
;   and a line does not need a buffer.
;
; Input:	nothing
; Output:	the page is started, lstlleft = PAGELEN
; Modifies:	AF, BC, DE, HL

lstpage:	xor	a
		ld	(lstpff),a
		ld	a,(lstsub)	; page 1 subpage 0 is the first page
		or	a		;   of all, and the only one with no
		jr	nz,lstp.ff	;   form feed in front of it
		ld	a,(lstpage1)
		dec	a
		jr	z,lstp.hdr
lstp.ff:	ld	a,2		; AND THE FORM FEED TAKES TWO COLUMNS
		ld	(lstpff),a	;   of the field below. Measured off
		ld	de,lstffd	;   five M80 headers, and it is why
		ld	a,1		;   M80's own paged headers sit two
		call	emitraw		;   to the left of its first one
lstp.hdr:	ld	a,(lsttitl)	; THE ONE VARIABLE FIELD: the title,
		or	a		;   TWO SPACES, and then on to the
		jr	z,lstp.not	;   next tab stop - staying put if
		ld	de,lsttitl+1	;   it is already on one, which is
		call	emitraw		;   why a title of 14 gives 16 and
lstp.not:	ld	hl,lstpff	;   one of 12 gives 16 as well.
		ld	a,(lsttitl)	;   AND THE FORM FEED'S TWO COLUMNS
		add	a,(hl)		;   COUNT TOWARD THAT STOP without
		add	a,2+7		;   being printed, so they go into
		and	0f8h		;   the sum and come back out of it
		sub	(hl)
		ld	hl,lsttitl
		sub	(hl)
		call	emitsp		; EMITSP AND NOT elnsp: the pad runs
					;   to nine and elnsp is eight long,
					;   so a title of fourteen wrote the
					;   two bytes after it into the header
		ld	de,vertxt	; "Tatara v1.0.0" - THE SAME BYTES
		ld	a,LSTNAMW	;   the banner prints, in a field as
		call	emitraw		;   wide as M80's own name and
					;   version. See vertxt in cmdline.as
		ld	de,elnsp
		ld	a,3
		call	emitraw
		call	lstdate		; DE -> nine bytes, dd-Mmm-yy
		ld	a,9
		call	emitraw
		ld	de,elnsp
		ld	a,7
		call	emitraw
		ld	de,lstpgw	; "PAGE" and four more spaces
		ld	a,8
		call	emitraw

		ld	a,(lstsub)	; the number: "S" for the last page,
		cp	0ffh		;   "n" for the first, "n-m" after
		jr	nz,lstp.num	;   that
		ld	de,lstsym0
		ld	a,1
		call	emitraw
		jr	lstp.eol
lstp.num:	ld	a,(lstpage1)
		ld	l,a
		ld	h,0
		ld	de,lstnbuf
		call	numdec		; A = how many digits
		ld	de,lstnbuf
		call	emitraw
		ld	a,(lstsub)
		or	a
		jr	z,lstp.eol
		ld	de,lstdash
		ld	a,1
		call	emitraw
		ld	a,(lstsub)
		ld	l,a
		ld	h,0
		ld	de,lstnbuf
		call	numdec
		ld	de,lstnbuf
		call	emitraw

lstp.eol:	call	lstcrlf		; the header's own line ending
		ld	a,(lstsubt)	; then the subtitle's line, which is
		or	a		;   blank unless a SUBTTL was in force
		jr	z,lstp.nos	;   when this page STARTED - so a
		ld	de,lstsubt+1	;   SUBTTL never shows on the page it
		call	emitraw		;   is written on
lstp.nos:	call	lstcrlf
		call	lstcrlf		;   and the blank one under that
		ld	a,(lstsub)	; the next overflow is a subpage on
		inc	a		;   from this one
		ld	(lstsub),a
		ld	a,(lstplen)
		ld	(lstlleft),a
		ret

; lstcrlf - one line ending.
;
; Input:	nothing
; Output:	two bytes
; Modifies:	AF, BC, DE, HL

lstcrlf:	ld	de,elncrlf
		ld	a,2
		jp	emitraw

; lsttset - remember a TITLE or a SUBTTL.
;
;   The buffer is a length byte and then the text, which is the shape
;   objbase wants and one byte cheaper than a separate count.
;
; Input:	DE -> the text
;		A  = its length
;		C  = 0 for the title, 1 for the subtitle
; Output:	the buffer holds it, cut to MAXTITL
; Modifies:	AF, BC, DE, HL

lsttset:	ld	b,a		; which of the two buffers
		ld	hl,lsttitl
		ld	a,c
		or	a
		jr	z,lstt.go
		ld	hl,lstsubt
lstt.go:	ld	a,b		; and how much of the text fits
		cp	MAXTITL+1
		jr	c,lstt.len
		ld	a,MAXTITL
lstt.len:	ld	(hl),a
		or	a
		ret	z		; "title" with nothing after it
		ld	c,a
		ld	b,0
		inc	hl
		ex	de,hl		; HL -> the text, DE -> the buffer
		ldir
		ret

; lsteject - the PAGE directive.
;
;   IT DOES NOT BREAK THE PAGE. It leaves a note, and lstl.done reads
;   it after the PAGE line itself has been listed - the directive
;   belongs to the page it was written on.
;
; Input:	nothing
; Output:	the note is left
; Modifies:	AF

lsteject:	ld	a,0ffh
		ld	(lstpend),a
		ret

; lstpset - PAGE expr: how long a page is.
;
;   M80 takes 10 to 255 and marks anything else as a fatal error,
;   which is what PAGEDIR.AS asked it. THE COUNT IS THE WHOLE PAGE,
;   four of whose lines are furniture: "page 12" gives eight lines of
;   text, measured.
;
; Input:	HL = the count
; Output:	lstplen (errpage does not return)
; Modifies:	AF

lstpset:	ld	a,h
		or	a
		jp	nz,errpage
		ld	a,l
		cp	10
		jp	c,errpage
		sub	4		; THE COUNT IS THE WHOLE PAGE and
		ld	(lstplen),a	;   lstplen is its body: the form
		ret			;   feed, the header and the two
					;   blank lines are the other four

; lstdate - the date, dd-Mmm-yy, fetched once.
;
;   It cannot change during an assembly, so the first header asks
;   MSX-DOS and every later one writes the same nine bytes.
;
; Input:	nothing
; Output:	DE -> nine characters
; Modifies:	AF, BC, DE, HL

lstdate:	ld	a,(lstdgot)
		or	a
		jr	nz,lstd.have
		system	_GDATE		; -> HL = year, D = month, E = day
		ld	a,d		; ALL THREE INTO RAM FIRST. Everything
		ld	(lstdmon),a	;   below wants DE or HL for its own
		ld	a,e		;   purposes, and the first "ld de,"
		ld	(lstdday),a	;   would take the month with it
		ld	(lstdyr),hl

		ld	a,(lstdday)	; the day, two digits
		ld	de,lstdbuf
		call	lst2dig
		ld	a,"-"
		ld	(lstdbuf+2),a
		ld	(lstdbuf+6),a

		ld	hl,(lstdyr)	; the year's last two digits: MSX-DOS
		ld	de,1900		;   answers 1980 to 2079, so take
		or	a		;   1900 off and then hundreds until
		sbc	hl,de		;   what is left is under one
lstd.c1:	ld	a,h
		or	a
		jr	nz,lstd.c2
		ld	a,l
		cp	100
		jr	c,lstd.yr
lstd.c2:	ld	de,100
		or	a
		sbc	hl,de
		jr	lstd.c1
lstd.yr:	ld	a,l
		ld	de,lstdbuf+7
		call	lst2dig

		ld	a,(lstdmon)	; the month's name, three letters
		dec	a		;   out of the table
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl		; three would need a multiply, so
		ld	de,lstmon	;   the table is four bytes an entry
		add	hl,de		;   and the fourth is never written
		ld	de,lstdbuf+3
		ld	bc,3
		ldir
		ld	a,0ffh
		ld	(lstdgot),a
lstd.have:	ld	de,lstdbuf
		ret

; lst2dig - A as two decimal digits at DE.
;
; Input:	A = 0 to 99
;		DE -> where
; Output:	two bytes written, DE unchanged
; Modifies:	AF, BC, HL

lst2dig:	ld	h,d
		ld	l,e
		ld	b,"0"-1
lst2d.t:	inc	b		; tens by subtraction: no divide, and
		sub	10		;   the number is under 100
		jr	nc,lst2d.t
		add	a,10
		ld	(hl),b
		inc	hl
		add	a,"0"
		ld	(hl),a
		ret

; lstend - the last page: Macros: and Symbols:, M80's layout.
;
;   CALLED FROM main.fin, before outclose. ONLY WHEN A LISTING FILE
;   WAS NAMED - not for /P. M80 puts this page in its .PRN because the
;   .PRN is the listing; Tatara keeps the screen clean and says so.
;
; Input:	nothing
; Output:	the page, or nothing
; Modifies:	AF, BC, DE, HL, IX

lstend:		ld	a,(lstname)	; A LISTING FILE, NOT /P: a .prn is a
		or	a		;   document and the symbols belong in
		ret	z		;   it, where screen output is watched
					;   going past and would be worse for
					;   ending in a form feed and a dump
		xor	a		; AND NO SUBTITLE: M80's own S page
		ld	(lstsubt),a	;   has none, whatever was in force
		ld	a,0ffh		; the number is "S", and lstpage
		ld	(lstsub),a	;   writes the form feed before it
		call	lstpage
		ld	de,lstmacw	; "Macros:"
		ld	a,7
		call	emitraw
		call	lstcrlf
		call	lstmacs
		call	lstcrlf		; one blank, with macros or without
		ld	de,lstsymw	; "Symbols:"
		ld	a,8
		call	emitraw
		call	lstcrlf
		jp	lstsyms

; emitsp - A spaces, wherever the listing goes.
;
;   The eight-space run emitln expands a tab with, reused: any count
;   is that run written until it has been enough. It exists because
;   lstsyms pads a name to sixteen columns and elnsp is this module's,
;   not something to hand out.
;
; Input:	A = how many, 0 to 255
; Output:	they are written
; Modifies:	AF, BC, DE, HL

emitsp:		or	a
		ret	z
emitsp.lp:	cp	9
		jr	c,emitsp.la
		push	af
		ld	de,elnsp
		ld	a,8
		call	emitraw
		pop	af
		sub	8
		jr	nz,emitsp.lp
		ret
emitsp.la:	ld	de,elnsp
		jp	emitraw

; emitchr - one character, wherever the listing goes.
;
;   A name lives in the mapper and cannot be handed to _WRITE, so the
;   walks that print one re-map the record and send a character at a
;   time. symdump has done this; this is the same thing
;   writing to the listing rather than to the screen.
;
; Input:	A = the character
; Output:	it is written
; Modifies:	AF, BC, DE, HL

emitchr:	ld	(elnchr),a
		ld	de,elnchr
		ld	a,1
		jp	emitraw

; lstbody - the same, for a line the driver never sees.
;
;   A MACRO, REPT, IRP or IRPC line, or a line of a body: macdef reads
;   those itself and the driver's loop never gets them. NO LABEL AND NO
;   ADDRESS - "byte" in "byte macro n" sits in the label field and
;   names nowhere, and M80 leaves the column blank. the rule does the
;   rest once the flag is off.
;
; Input:	DE -> the text
;		A  = its length
; Output:	nothing, or a listing line
; Modifies:	AF, BC, DE, HL

lstbody:	ld	c,a		; the length: emitinit leaves BC alone
		ld	b,0		; no label, so no address column
		ld	hl,0
		xor	a		; and no segment: nothing shows either
		call	emitinit	;   way, and emitn goes to zero
		ld	a,c
		jp	lstline		; the line's zero terminator went
					;   back here, because emitln wrote
					;   CR+LF over it. Now it writes those
					;   two bytes on their own and the
					;   buffer is not touched at all

; emitpfx - build the listing's two columns for the FIRST eight bytes.
;
;   The column is "  ", four hex digits, the relocation mark, three
;   spaces, then three characters a byte. A line that emitted more than
;   eight WRAPS: emitmore below builds the next eight, and the caller
;   keeps asking until it says there are none left.
;
; Input:	nothing (lstaddr, lstseg, emitn, emitbuf)
; Output:	DE -> the text
;		A  = how long it is
; Modifies:	AF, BC, DE, HL

emitpfx:	ld	hl,0
		ld	(lstnext),hl	; this line's bytes start at zero
		jr	epf.go

; emitmore - the same column for the next eight bytes of the same line.
;
;   A "+" was printed here and stopped, on the grounds that the listing
;   would wrap them. Nothing emitted more than eight bytes on one line
;   until tatara.as assembled its own message tables - and a listing
;   that silently drops bytes is worse than no listing, because the
;   only reason to read one is to check what was generated.
;
;   Each answer is a whole listing line: a real address of its own,
;   the same relocation mark, and no source text, because it is still
;   one source line.
;
; Input:	nothing (lstnext)
; Output:	CY set   = there were none left, and nothing was built
;		CY clear = DE -> the text, A = how long it is
; Modifies:	AF, BC, DE, HL

emitmore:	call	epf.kept	; how many bytes there are to show
		ld	bc,(lstnext)
		or	a
		sbc	hl,bc		; still some past the ones shown?
		jr	nz,epf.go
		scf
		ret			; no: this line is finished

epf.go:		ld	de,lstbuf
		ld	a,(lstlab)	; A LABEL OR BYTES, OR NO ADDRESS AT
		or	a		;   ALL. M80 leaves the column blank
		jr	nz,epf.addr	;   on a comment, on END, on a
		ld	hl,(emitn)	;   listing control - on any line that
		ld	a,h		;   neither names a place nor puts
		or	l		;   anything in one
		jr	nz,epf.addr
		ld	b,10		; the whole column: 2 + 4 + 1 + 3
		call	epf.sp
		jr	epf.bytes

epf.addr:	ld	b,2
		call	epf.sp
		ld	hl,(lstaddr)	; THIS chunk's address: where the line
		ld	bc,(lstnext)	;   began, plus the bytes already shown
		add	hl,bc
		call	numhex		; four digits, DE moves on
		ld	a,(lstseg)
		or	a		; SY_ABS is 0 and must stay 0
		ld	a," "
		jr	z,epf.abs
		ld	a,"'"		; M80's mark for an address the
epf.abs:	ld	(de),a		;   linker has still to place
		inc	de
		ld	b,3
		call	epf.sp

epf.bytes:

		call	epf.kept	; how many are left to show: what is
		ld	bc,(lstnext)	;   in the buffer, less what is done
		or	a
		sbc	hl,bc
		ld	bc,MAXSHOW	; a column holds MAXSHOW of them, and
		or	a		;   this chunk shows that many or all
		sbc	hl,bc		;   that remain, whichever is fewer
		jr	nc,epf.eight
		add	hl,bc
		ld	b,h
		ld	c,l
epf.eight:	push	bc		; how many, for lstnext below
		push	de		; DE is the OUTPUT cursor throughout
		ld	hl,(lstnext)
		ld	de,emitbuf
		add	hl,de		; HL -> this chunk's first byte
		pop	de
epf.byte:	ld	a,b
		or	c
		jr	z,epf.adv
		ld	a,(hl)
		inc	hl
		call	numhex2
		ld	a," "
		ld	(de),a
		inc	de
		dec	bc
		jr	epf.byte

epf.adv:	pop	bc		; how many this chunk showed
		ld	hl,(lstnext)
		add	hl,bc
		ld	(lstnext),hl	; where the next one starts

; A "+" was printed here when a line emitted more than MAXEMIT, meaning
; "there were more bytes than the buffer kept". That became an error
; instead - errmemit - because the buffer IS the object file's
; content, and a lost tail is a wrong program rather than a short
; column. So the branch is gone, and the character is free for the
; meaning M80 gives it below.

epf.pad:	ld	hl,lstbuf+LSTWIDE
		or	a
		sbc	hl,de		; HL = how many spaces are owed
		jr	z,epf.mac
		jr	c,epf.mac	; already past: no padding
		ld	b,l		; LSTWIDE is well under 256
		call	epf.sp

; M80 flags a line that came out of a macro expansion. The top line
; source says whether this one did - a file cannot expand anything -
; and the column is the last space before the source text.
;
; THE COLUMN IS M80'S, measured off its listing of MACPLUS.AS: 26, a
; column of its own rather than the last space before the source.

epf.mac:	ld	a,(lstmac)	; where THIS line came from, from
		cp	LSK_MACRO	;   emitinit - not where the stack
					;   has got to by now
		jr	z,epf.plus
		ld	a,(lstcall)	; a call line under .SALL: M80 flags
		or	a		;   it, because it is standing in for
		jr	z,epf.end	;   an expansion nobody asked to see.
		ld	a,(lstmode)	;   Under .LALL and .XALL it does not
		cp	LST_SALL
		jr	nz,epf.end
epf.plus:
		ld	hl,lstbuf+LSTPLUS
		ld	(hl),"+"
epf.end:	ld	hl,lstbuf
		ex	de,hl		; DE -> lstbuf, HL = the cursor
		or	a
		sbc	hl,de		; HL = how long it came to
		ld	a,l
		or	a		; CY CLEAR: something was built
		ret

; epf.kept - how many of this line's bytes are actually in emitbuf.
;
;   emitn counts every byte the line emitted; emitbuf holds the first
;   MAXEMIT of them. The listing can only show what was kept.
;
; Input:	nothing
; Output:	HL = the smaller of emitn and MAXEMIT
; Modifies:	AF, BC, HL

epf.kept:	ld	hl,(emitn)
		ld	bc,MAXEMIT
		or	a
		sbc	hl,bc
		jr	c,epf.kpt1	; fewer than the buffer holds: all
		ld	hl,MAXEMIT	;   of them. Otherwise MAXEMIT is
		ret			;   every one there is
epf.kpt1:	add	hl,bc		; put emitn back
		ret

; epf.sp - B spaces at DE.
;
; Input:	B = how many, DE -> where
; Output:	DE has moved on
; Modifies:	AF, B, DE

epf.sp:		ld	a," "
		ld	(de),a
		inc	de
		djnz	epf.sp
		ret

		dseg

emitn:		defs	2	; how many bytes this line emitted. A
				;   WORD: a DW can pass 255
emitbuf:	defs	MAXEMIT	; the first MAXEMIT of them - for the
				;   listing now, and for the
				;   object record later
lstbuf:		defs	LSTWIDE+8
				; the two columns, built per line. The
				;   slack is the "+" and the room a
				;   MAXSHOW-byte line needs past LSTWIDE
lstaddr:	defs	2	; where this line began, before anything
				;   moved locctr
lstmac:		defs	1	; and the LS_KIND of the source it came
				;   from, for the "+" and for .SALL/.XALL
lstlab:		defs	1	; non-zero if it carried a label, which
				;   with emitn decides the address column
lstcall:	defs	1	; non-zero if it called a macro. Only
				;   .SALL reads it
outhand:	defs	1	; where emitraw and emitln write: the
				;   listing file, or STDOUT. outopen sets
				;   it, outclose reads it, and they stay
				;   with the driver - the file is its
lston:		defs	1	; 0 once .XLIST has been seen, and 0FFh
				;   again after .LIST. It moved here with
				;   lstline, which is what reads it
lstltx:		defs	2	; lstline's line: where it is,
lstllen:	defs	1	;   and how long
elnleft:	defs	1	; emitln: characters still to write,
elncol:		defs	1	;   which column it has reached,
elnrun:		defs	1	;   and how long the run it just wrote
elnptr:		defs	2	;   was, and WHERE IT IS READING - which
				;   cannot live in DE across a _WRITE
elnchr:		defs	1	; emitchr's one byte
lstlleft:	defs	1	; lines still to go on this page. ZERO to
				;   start with, so the first line of a
				;   listing writes a header
lstpage1:	defs	1	; the main page number, which the PAGE
				;   directive moves on
lstpend:	defs	1	; non-zero = a PAGE directive is waiting
				;   for its line to be listed
lstpff:		defs	1	; 2 if this page opened with a form feed,
				;   which costs the title's field two
				;   columns, and 0 if it did not
lstplen:	defs	1	; lines on a page: PAGELEN until a
				;   PAGE expr says otherwise
lsttitl:	defs	1+MAXTITL	; the title: a length byte, then
				;   the text. NOT cleared between the
				;   passes, which is how a title on
				;   source line 3 heads page 1
lstsubt:	defs	1+MAXTITL	; the subtitle, the same shape -
				;   and cleared per pass, and again
				;   before the S page
lstsub:		defs	1	; and the subpage: 0 on the first page,
				;   1 on the next, 0FFh on the last
lstnbuf:	defs	5	; numdec's answer
lstdbuf:	defs	9	; the date, dd-Mmm-yy
lstdday:	defs	1	; the day, the month and the year, out
lstdmon:	defs	1	;   of DE and HL before anything else
lstdyr:		defs	2	;   is allowed to use them
lstdgot:	defs	1	; 0 until MSX-DOS has been asked
				;   was - emitraw keeps none of them
lstmode:	defs	1	; LST_LALL, LST_SALL or LST_XALL: how much
				;   of an expansion the listing shows. THE
				;   DRIVER WRITES IT, from .LALL/.SALL/.XALL,
				;   and both it and epf.mac read it - so it
				;   lives with the listing rather than with
				;   the driver
lstnext:	defs	2	; the byte emitmore shows next. A WORD:
				;   MAXEMIT is 256 and this reaches it
lstseg:		defs	1	;   and in which contribution, which is
				;   what decides the apostrophe
