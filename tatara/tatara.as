; tatara.as - Tatara: an M80-compatible macro assembler for MSX.
;
; The driver. It reads the command line, opens the source as a line
; source, and pulls lines through the stack until there are none left.
; A line may come from a file, from an INCLUDE opened in place, or from
; a macro body replayed out of mapper RAM, and getline does not say
; which.
;
; What this file acts on itself: INCLUDE, the conditional family,
; SET/DEFL, and the directives that measure and emit. Everything else
; is passed on to the listing, the object file, or both.
;
; /P assembles to the screen and /L writes a listing. /F prints each
; line's four fields in brackets, with its directive number, instead of
; the line itself.

;		.z80

		include	msxdos.inc
		include	cmdline.inc
		include	srcline.inc
		include	fields.inc
		include	dirtab.inc
		include	ascii.inc
		include	macros.inc
		include	mdt.inc		; MDK_REPT, for main.rept. Without
					;   this the assembler takes MDK_REPT
					;   for an undefined symbol, resolves
					;   it to 0000h - which is MDK_MACRO -
					;   and writes the .com anyway
		include	cond.inc
		include	expr.inc
		include	alloc.inc
		include	errs.inc
		include	expand.inc
		include	symtab.inc
		include	insn.inc
		include	emit.inc
		include	objout.inc	; objopen, objhead, objfin

		cseg

main:		call	dosver		; CY set = not MSX-DOS2
		jp	c,main.dos1

		call	heapinit	; CY set = no mapper support
		jp	c,main.nomap

		call	cmdparse	; CY set = no input filename
		push	af		; BEFORE the inits, not after: /C
					; decides the case mode, and macinit
					; and syminit hand it to htinit.
					; cmdparse needs nothing they provide
		ld	a,(opthelp)	; /? and /V ANSWER AND STOP, with a
		or	a		;   filename or without one - so they
		jp	nz,main.usage	;   come before the carry, which only
		ld	a,(optver)	;   says whether a source was named.
		or	a		;   Neither returns, so the pushed
		jp	nz,main.ver	;   flags are the program's last word
		pop	af
		jp	c,main.usage
		call	cmdbann		; and now the banner, unless /Q -
					;   before any other output, because
					;   it is what the program is
		call	syminit		; ONCE ONLY, like heapinit and for the
					; same reason: the symbol table is what
					; has to survive from pass 1 into pass
		call	seginit		; ONCE ONLY as well: a symbol holds
					; its segment's INDEX, so the
					; indices must not be handed out
					; again on pass 2
		call	macinit		; 2 and the macro name table's bucket
					; array, which is dseg space and
					; therefore garbage until it is
					; formatted. EMPTYING it between passes
					; is macrst's job, not this one's

		ld	a,(dstname)	; NO OUTPUT FILE IS NOT AN ERROR any
		or	a		;   more: it means "assemble it and
		jr	z,main.go	;   tell me what you find", which is
		call	samename	;   what all 165 tests ask for
		jp	z,main.same	; object over the input? refuse

main.go:	ld	a,1
		ld	(passno),a
		ld	a,STDOUT	; outopen does not run until the END of
		ld	(outhand),a	;   pass 1, so that a source that will
					;   not assemble cannot truncate the
					;   user's file. Until then anything
					;   written - the /F dump is the only
					;   thing - goes to the standard
					;   output, which is redirectable. An
					;   unset handle is not

; Each pass re-reads the source from the beginning, so everything that
; remembers where pass 0 had got to is reset here. The symbol table and
; the formatted macro table are NOT - that is the whole distinction, and
; it is why syminit and macinit sit above with heapinit.

main.pass:	call	srcinit		; no line sources yet
		ld	de,srcname
		call	pushfile	; CY set = could not open it
		jp	c,main.noopen
		call	macrst		; free the previous pass's definitions
		call	mexinit		; the ??nnnn counter back to zero, so
					; pass 2 generates the same names pass
		call	cndinit		; 1 did no conditionals open
		call	exinit		; exlook points at symlook
		call	segrst		; every counter 0, CSEG current
		xor	a
		ld	(endseen),a	; pass 2 must stop at the same END
		call	lstinit		; the listing on, .XALL, page 1: a
					;   .XLIST on pass 1 must not silence
					;   pass 2
		ld	a,0ffh		; and a branch not taken is listed
		ld	(lstfc),a	;   until .SFCOND says otherwise

; One line at a time: get it, understand it, then decide what becomes of
; it. Only the last of those three steps knows anything about output.

main.loop:	ld	a,(endseen)	; an END line ends the pass, and
		or	a		; with it the file that included
		jp	nz,main.done	; this one, and every file above

		ld	hl,linebuf
		call	getline		; CY set = no more lines, anywhere
		jp	c,main.done
		ld	(linelen),a	; splitln and dirlook both destroy A
		dec	a		; A FORM FEED ON A LINE OF ITS OWN
		jr	nz,main.nff	;   STARTS A PAGE, and A still holds
		ld	a,(linebuf)	;   the length. It must not reach
		cp	CHR_FF		;   splitln: nothing there ends a field
		jp	z,main.ff	;   on 0Ch, so it would become a label
					;   and be defined like any other -
					;   issue #17
main.nff:
		ld	hl,linebuf
		ld	ix,flds		; getline used IX for its own purposes
		call	splitln

		ld	a,(flds+FL_LABL)	; did it carry a label? With
		ld	b,a			;   the byte count that is what
		ld	hl,(locctr)	; where this line begins, and in
		ld	a,(curseg)	;   what, BEFORE anything moves the
		call	emitinit	;   counter - and nothing emitted yet
		ld	de,(flds+FL_OP)	; is the operation a directive?
		ld	a,(flds+FL_OPL)
		ld	b,a
		call	dirlook		; A = the number, 0 = it is not one
		ld	(dirnum),a

		ld	a,(passno)	; /F and /M are diagnostics of pass 0's
		dec	a		; work, and pass 0 now runs twice.
		jr	nz,main.nofld	; Dumping on pass 1 only says
		ld	a,(optflds)	; everything, once
		or	a
		call	nz,shofld	; /F: show what splitln made of it
main.nofld:

; A conditional directive, or a line inside a branch we are not taking?
; Either way it produces nothing and the rest of the driver never sees
; it - which is what keeps INCLUDE, MACRO and macro calls from happening
; inside a false branch. The /F dump above still shows the line, so that
; the skipping can be watched.

		ld	a,(dirnum)
		call	cndline		; CY set = this line produces nothing
		jr	nc,main.cnd0
		ld	a,(dirnum)	; IT PRODUCES NOTHING FOR ONE OF TWO
		cp	D_IF		;   REASONS, and the number says which:
		jr	c,main.cskp	;   the IF family is contiguous, which
		cp	D_ENDIF+1	;   is the same property cndline opens
		jr	nc,main.cskp	;   with

; A directive of the IF family, on its own line. M80 lists those wherever
; they are - AND DEFINES A LABEL ON ONE when the line is being assembled.
; cndlab is that question answered before cndline changed the state, which
; is the only moment it can be answered: "lels: else" is defined because
; the branch ABOVE it was being taken, and "lend: endif" on the next line
; is not, because by then we are inside the skipped ELSE. Issue #15.
;
; emitskip is NOT called on the defining path. emitinit recorded the label
; before cndline ran, so the address column already holds what M80 prints
; there - 085's mechanism, used the other way up.

		ld	a,(cndlab)
		or	a
		jr	z,main.cfsk	; not being assembled: no label, and
		call	deflab		;   no address either
		jp	main.emit
main.cfsk:	call	emitskip
		jp	main.emit

main.cskp:	call	emitskip	; a line inside a branch we are not
		ld	a,(lstfc)	;   taking names no place: 085. And
		or	a		;   .LFCOND shows it while .SFCOND
		jp	nz,main.emit	;   does not - either way nothing on
		jp	main.loop	;   it is acted on
main.cnd0:

		ld	a,(dirnum)	; cndline used A
		cp	D_INCL
		jp	z,main.incl
		cp	D_MACRO
		jp	z,main.mac
		cp	D_REPT
		jp	z,main.rept
		cp	D_IRP
		jp	z,main.irp
		cp	D_IRPC
		jp	z,main.irpc
		cp	D_EXITM
		jp	z,main.exitm
		cp	D_ENDM
		jp	z,errendm	; nothing was open to close
		cp	D_SET
		jp	z,main.set	; a DEFL's label names its VALUE,
					;   not $. SET shared this number
					;
		cp	D_GROUP
		jp	z,main.grp	; a GROUP line takes no label at all
		cp	D_EQU
		jp	z,main.equ	; like SET, its label names the VALUE
		cp	D_PUBLIC	; THESE TWO DEFINE THEIR OWN LABEL,
		jp	z,main.pub	;   at main.nlst, and come through
		cp	D_EXTRN		;   here only because they share the
		jp	z,main.ext	;   routine that walks a name list.
					;   The comment that stood here said
					;   they "take no label either" and
					;   cited nothing: M80 defines a label
					;   on both, at the location counter.
					;   Issue #28, note 098
		cp	D_END
		jp	z,main.end

		call	deflab		; any other label takes the location
					; counter

		ld	a,(dirnum)
		cp	D_ORG
		jp	z,main.org
		cp	D_DS
		jp	z,main.ds
		cp	D_DB
		jp	z,main.db
		cp	D_DW
		jp	z,main.dw
		cp	D_DC
		jp	z,main.dc
		cp	D_LIST		; one of the five listing controls?
		jr	c,main.nlc	;   D_LIST to D_XALL, consecutive
		cp	D_XALL+1
		jp	c,main.lst
		cp	D_TFCOND+1
		jp	c,main.fc
		cp	D_TITLE		; TITLE and SUBTTL, consecutive
		jr	c,main.nlc
		cp	D_SUBTTL+1
		jp	c,main.titl
		cp	D_PAGE
		jp	z,main.page
main.nlc:	cp	D_ASEG		; ASEG, CSEG or DSEG?
		jr	c,main.nseg
		cp	D_DSEG+1
		jp	c,main.seg
main.nseg:	or	a
		jp	nz,main.emit	; some other directive: pass it on

; Not a directive. is the operation the name of a macro? The fields still
; describe this line - shofld only read them - so DE and B can be loaded
; from flds again, exactly as dirlook was given them.

		ld	de,(flds+FL_OP)
		ld	a,(flds+FL_OPL)
		ld	b,a
		ld	hl,mdfp
		call	macfind		; CY set = not a macro name
		jr	c,main.insn
		ld	de,(flds+FL_ARG)	; the call's arguments, still
		ld	a,(flds+FL_ARGL)	; describing this line
		ld	hl,mdfp		; macfind returned through HL
		call	mexnew		; its body is now the line source
		ld	a,0ffh		; .SALL flags this line, because it
		ld	(lstcall),a	;   is all the call will produce
		jp	main.emit	; AND THE CALL LINE IS LISTED, which
					;   M80 does and it did not.
					;   It emits nothing, so it shows an
					;   address and no bytes - and under
					;   .SALL it is all a call produces.
					;   emitinit already recorded that
					;   this line came from a file, so
					;   mexnew's push does not disguise it

; Not a directive and not a macro. An instruction moves the location
; counter and is passed on to the listing like any other line.
;
; Anything else is now an ERROR. All sixty-nine mnemonics have handlers
;, so "not in the table" finally means "not an instruction",
; and M80's own answer here - to assemble it as a DB (2.3.1), so that a
; mistyped "xro a" becomes one byte of data and breaks the program
; somewhere else - is the departure optable-design.md 8 decided
; against.
;
; The guard first. insnline says "no" to a line with no operation at
; all as well as to a word it does not know, and a label or a comment
; on its own is neither an error nor an instruction.

main.insn:	ld	a,(flds+FL_OPL)
		or	a
		jp	z,main.emit	; a label or a comment alone
		ld	ix,flds
		call	insnline
		jp	c,errnoop
		jp	main.emit

; A SET or DEFL line is acted on AND passed on: pass 0 needs the value so
; that a conditional can ask about it, and pass 1 needs the line so that
; the symbol exists for the rest of the program. Every other directive so
; far has been consumed; this is the first that is not, which is why the
; branch below ends by falling into main.emit. It used to get there by falling
; off its last line; main.equ went in between, so it jumps now.

main.set:	ld	a,(flds+FL_LABL)
		or	a
		jp	z,errxsyn	; DEFL with no name in front of it.
					;   SET reached here too and
					;   does not now - it is the bit
					;   instruction and nothing else
		call	labcol		; a name, not a label, as for EQU
		jp	z,errnlab
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		call	evalexp		; HL = the value
		ld	a,(exty)	; which the listing shows where an
		call	emitval		;   address would go, as for EQU
		ld	de,(flds+FL_LAB)
		ld	a,(flds+FL_LABL)
		ld	b,a
		ld	a,(exty)	; the value's own type: "here set $" is
		ld	c,SYF_VAR	; relative to the current segment. SET
		call	symdef		; and DEFL are the only variables
		jp	main.emit	; main.equ sits between this and the
					; emit now, so say it

; EQU is SET's opposite: one value, for good. M80 2.6.11 allows the same
; line to say it twice with the same value, which is what makes pass 2
; work without a special case here.

main.equ:	ld	a,(flds+FL_LABL)
		or	a
		jp	z,errxsyn	; EQU with no name in front of it
		call	labcol		; and a NAME is what it takes: a
		jp	z,errnlab	;   colon would make it a label,
					;   which is M80 2.3.1 and leaves
					;   the EQU nameless - error O
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		call	evalexp
		ld	a,(exty)
		cp	SYTEXT
		jp	z,errext	; "If <exp> is external, an error is
					; generated" - 2.6.11
		ld	a,(exty)	; the listing shows the VALUE where
		call	emitval		;   an address would go, which is
					;   where M80 puts it. HL still holds
					;   it: emitval modifies nothing
		ld	de,(flds+FL_LAB)
		ld	a,(flds+FL_LABL)
		ld	b,a
		ld	a,(exty)
		ld	c,0		; fixed: symdef keeps the rules
		call	symdef
		jp	main.emit

; PUBLIC/ENTRY and EXTRN/EXT take a list of names and nothing else. The
; walk is shared; which routine each name goes to is the only difference,
; and it goes in nlproc rather than being duplicated.

main.pub:	ld	hl,sympub
		jr	main.nlst
main.ext:	ld	hl,symext
main.nlst:	ld	(nlproc),hl
		call	deflab		; AFTER THE STORE, not before it:
					;   deflab destroys HL, and HL is how
					;   these two tell each other apart
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		ld	b,a

main.nl1:	call	main.nlws	; blanks in front of the name
		ld	a,b
		or	a
		jp	z,errdecl	; nothing there: "public ," or "public"
		push	de		; where this name starts
		ld	c,0
main.nl2:	ld	a,b
		or	a
		jr	z,main.nl3
		ld	a,(de)
		cp	" "
		jr	z,main.nl3
		cp	CHR_TAB
		jr	z,main.nl3
		cp	","
		jr	z,main.nl3
		inc	de
		inc	c
		dec	b
		jr	main.nl2

main.nl3:	pop	hl		; HL -> the name, C = its length
		ld	a,c
		or	a
		jp	z,errdecl
		push	de		; the scan, kept across the call
		push	bc
		ex	de,hl		; DE -> the name, B = its length
		ld	b,c
		ld	hl,(nlproc)
		call	main.nlgo	; sympub or symext
		pop	bc
		pop	de

		call	main.nlws	; a comma means another name follows
		ld	a,b
		or	a
		jp	z,main.emit
		ld	a,(de)
		cp	","
		jp	nz,errdecl
		inc	de
		dec	b
		jr	 main.nl1

main.nlgo:	jp	(hl)		; the call above is what returns here

main.nlws:	ld	a,b		; step DE over blanks and tabs
		or	a
		ret	z
		ld	a,(de)
		cp	" "
		jr	z,main.nlw2
		cp	CHR_TAB
		ret	nz
main.nlw2:	inc	de
		dec	 b
		jr	main.nlws

; END stops the assembly here, whatever is left in this file or in the
; one that included it. Its operand is the program's start address, and
; objentr keeps it until objfin can write the ENTRY record - which is
; after pass 2, because until then there is an unfinished DATA record
; in the file.

main.end:	call	deflab		; "lend2: end" defines lend2 as the
					;   counter, BEFORE the operand is
					;   looked at - deflab's own rule for
					;   ORG and DS. M80 lists 0103 there
		ld	a,(flds+FL_ARGL)
		or	a
		jr	z,main.end2
		ld	de,(flds+FL_ARG)
		call	evalexp
		ld	a,(exty)	; the ENTRY record needs a segment as
		call	objentr		;   well as an offset, and objfin is
					;   where it can be written
main.end2:	ld	a,0ffh
		ld	(endseen),a
		jp	main.emit

main.emit:	ld	a,(passno)
		cp	2
		jp	nz,main.loop	; pass 1 emits nothing at all: it is
					; there to find out what the symbols
		ld	hl,(emitn)	; PROVED: a line cannot emit more
		ld	de,MAXEMIT	;   than MAXEMIT, and the
		or	a		;   buffer is the object file's
		sbc	hl,de		;   content. The assertion moved
		jr	c,main.em0	;   here from objdata, which only runs
		jp	nz,errmemit	;   when a file is open - "tatara /p"
main.em0:	call	objdata		;   would have truncated in silence
					; THE OBJECT FILE FIRST. This makes
					;   everything below this return early
					;   when no listing was asked for, and
					;   an object file is normally written
					;   with no listing at all
		ld	a,(optflds)	; are worth with /F the dump has
		or	a		; replace the line, so there is nothing
					; to write
		jp	nz,main.loop
		ld	de,linebuf	; and the rest is lstline, which
		ld	a,(linelen)	;   macdef calls too: it moved
		call	lstline		;   into emit.as so that there is one
		jp	main.loop	;   copy of what a listing line is

; ORG and DS use the STRICT evaluator. Their operand decides where
; everything after them sits, so an unknown value is not a forward
; reference that pass 2 will fix - it is a source that cannot be
; assembled at all. Same reasoning as the REPT count.

main.org:	call	segwr		; a transient DSEG with no group
					;   open cannot be placed in
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		call	evalexp
		ld	a,(exty)	; absolute, or in the current segment's
		or	a		; own mode - M80 2.6.28.1. "dseg" then
		jr	z,main.org2	; "org 20" is data offset 20
		ld	b,a
		ld	a,(curseg)
		cp	b
		jp	nz,errrel	; a data address for the code counter
main.org2:	ld	(locctr),hl
		jp	main.emit

main.ds:	call	segwr		; as ORG above
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		call	evalabs		; a count of bytes: absolute only
		ld	de,(locctr)
		add	hl,de
		ld	(locctr),hl
		jp	main.emit

; DB, DW and DC in their SIZING role. This measures; the bytes
; themselves are the object writer's.
;
;   HOW MUCH ROOM AN ITEM TAKES DOES NOT DEPEND ON WHAT IT IS WORTH.
;   "db later" is one byte whether later is defined above, defined
;   below, or promised by another module. So nothing here calls the
;   evaluator, and a forward reference costs no machinery at all - the
;   first one in Tatara's life arrives for free.
;
;   The only thing that changes an item's size is whether it is a
;   STRING, and M80 2.6.4 decides that by what FOLLOWS the closing
;   quote: a comma or the end of the line means a string, one byte per
;   character; anything else means the quotes were a character constant
;   inside an expression. That is what makes "db 'AB'" two bytes and
;   "db 'AB' AND 0FFH" one, and it needs no lookahead past one
;   character.

main.db:	ld	a,1		; one byte per expression
		jr	main.dbgo
main.dw:	ld	a,2		; two
main.dbgo:	ld	(dbwide),a
		call	segwr		; as ORG and DS above
		call	dbwalk		; (dbtot) = what this line adds
		ld	hl,(dbtot)
main.dbad:	ld	de,(locctr)
		add	hl,de
		ld	(locctr),hl
		jp	main.emit

; DC takes ONE string and it may not be empty: a null string has no last
; character to set the high bit of, and 2.6.5 calls that an error.

main.dc:	call	segwr
		ld	a,1
		ld	(dbwide),a	; DC emits a byte per character,
					;   like a DB
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		ld	b,a
		call	main.nlws
		ld	(dbsrc),de	; where the string begins. dbwalk
		call	dbitem		;   does this for DB and DW; DC does
					;   not go through dbwalk at all
		ld	a,(dbstr)
		or	a
		jp	z,errdata	; not a string at all
		ld	a,h
		or	l
		jp	z,errdata	; a null string
		push	hl		; the count, for main.dbad
		push	de		; and DE, which main.nlws will move
		call	dbemit		; WHILE DE IS STILL JUST PAST THE
		call	emithi		;   ITEM - dbemit measures from dbsrc
		pop	de		;   to here, and main.nlws below would
		pop	hl		;   fold trailing spaces into it
		call	main.nlws
		ld	a,b
		or	a
		jp	nz,errdata	; one string, and nothing after it
		jr	main.dbad

; dbwalk - measure a whole DB or DW operand.
;
; Input:	(dbwide) = 1 for DB, 2 for DW
; 		the operand, in flds
; Output:	(dbtot) = how many bytes the line adds
; 		errdata does not return
; Modifies:	AF, BC, DE, HL

dbwalk:		ld	hl,0
		ld	(dbtot),hl
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		ld	b,a
dbw.lp:		call	main.nlws
		ld	(dbsrc),de	; where this item begins: dbitem leaves
		call	dbitem		;   DE past it, and dbemit needs both
		ld	a,(dbstr)
		or	a
		jr	z,dbw.exp
		ld	a,(dbwide)	; a string standing on its own
		dec	a
		jr	z,dbw.add	; DB: one byte per character
		ld	a,h		; DW: one or two characters is a
		or	a		;   number, and fits the word. Three
		jp	nz,errdata	;   or more may not be used in an
		ld	a,l		;   expression at all - 2.6.4
		cp	3
		jp	nc,errdata
dbw.exp:	ld	a,(dbwide)	; an expression, or a short string in
		ld	l,a		;   a DW: the width, whatever it
		ld	h,0		;   turns out to be worth
dbw.add:	push	de
		push	bc		; B is the text left, not a count
		ex	de,hl
		ld	hl,(dbtot)
		add	hl,de
		ld	(dbtot),hl
		pop	bc
		pop	de
		push	bc
		call	dbemit		; Counting once stopped here. The
		pop	bc		;   count is still wanted - main.db
					;   moves locctr by it - but the bytes
					;   go out on the way past now
		call	main.nlws
		ld	a,b
		or	a
		ret	z		; the operand ends: the line is done
		ld	a,(de)
		cp	","
		jp	nz,errdata	; two items with nothing between
		inc	de
		dec	b
		jr	dbw.lp

; dbemit - emit the item dbitem has just measured.
;
;   dbsrc says where it began and DE says where it ended - on the comma,
;   or at the end of the operand - so the two together are its text.
;
;   A string in a DB or a DC is emitted character by character. Anything
;   else is an expression, INCLUDING a one or two character string in a
;   DW: "dw 'AB'" is the single value 4142h, exchar has always known it,
;   and M80 lists it as 4142 (CHARC.PRN). The two are not a special case
;   of each other and dbitem has already decided which this is.
;
; Input:	(dbsrc) -> the item, DE -> just past it
;		(dbstr) = 1 if it was a string on its own
;		(dbwide) = 1 for DB and DC, 2 for DW
; Output:	its bytes are emitted
; Modifies:	AF, BC, DE, HL

dbemit:		push	bc
		push	de
		push	hl
		ld	h,d
		ld	l,e		; HL -> just past the item
		ld	de,(dbsrc)	; DE -> its first character
		or	a
		sbc	hl,de		; HL = how many characters it has -
		ld	a,l		;   a line is 255 at most, so L is all
		ld	(dbelen),a	;   of it
		ld	a,(dbstr)
		or	a
		jr	z,dbem.x	; an expression
		ld	a,(dbwide)
		dec	a
		jr	nz,dbem.x	; a string in a DW is an expression too
		call	dbestr		; a DB or DC string: its characters
		jr	dbem.done
dbem.x:		ld	a,(dbwide)
		dec	a
		ld	a,(dbelen)	; ld a,(nn) leaves the flags alone
		jr	nz,dbem.w
		call	emitx		; DB or DC: one byte
		jr	dbem.done
dbem.w:		call	emitxw		; DW: two
dbem.done:	pop	hl
		pop	de
		pop	bc
		ret

; dbestr - emit the characters of a string in a DB or a DC, two
;   delimiters together counting as one.
;
;   This is dbqstr's walk with an emitb where its "inc hl" was, and it
;   is the FIFTH routine in the program to step over a quoted run.
;   Reading the other four side by side kept them apart:
;   they share a RULE, not an interface - four cursors, four products,
;   and splitln's is not a routine at all. The rule, once, so that the
;   sixth has something to copy:
;
;     a run ends at the next delimiter that is NOT followed by the same
;     delimiter again; two together are one character of the string
;
;   dbitem has already counted this item, so nothing here can run off
;   the end: the text it walks is the text dbqstr measured.
;
; Input:	(dbsrc) -> the opening delimiter
;		(dbelen) = how many characters the item has
; Output:	its characters are emitted
; Modifies:	AF, BC, DE, HL

dbestr:		ld	de,(dbsrc)
		ld	a,(de)
		ld	c,a		; C = the delimiter that opened it
		inc	de
		ld	a,(dbelen)
		dec	a
		ld	b,a		; B = characters left, the quote gone
dbe.lp:		ld	a,b
		or	a
		ret	z
		ld	a,(de)
		inc	de
		dec	b
		cp	c
		jr	nz,dbe.ch		; an ordinary character
		ld	a,b		; a delimiter: doubled, or the end?
		or	a
		ret	z		; the item ends: it closed here
		ld	a,(de)
		cp	c
		ret	nz		; something else follows: closed
		inc	de		; "" - one character, and on we go
		dec	b
		ld	a,c
dbe.ch:		call	emitb
		jr	dbe.lp

; dbitem - measure ONE item, and say which kind it was.
;
;   Either way it leaves DE on the comma that ends the item, or at the
;   end of the operand, because an expression is SKIPPED rather than
;   read. What it is worth is the emitter's business.
;
; Input:	DE -> the item's first character
; 		B  = characters left in the operand
; Output:	(dbstr) = 1 for a string on its own, 0 for an expression
; 		HL = its characters, when (dbstr) is 1
; 		DE -> the comma, or the end
; 		B  = characters left
; 		errdata does not return
; Modifies:	AF, BC, DE, HL

dbitem:		xor	a
		ld	(dbstr),a
		ld	h,a
		ld	l,a		; HL = 0: nothing counted yet
		ld	a,b
		or	a
		jp	z,errdata	; "db 1," - nothing after the comma
		ld	a,(de)
		cp	","
		jp	z,errdata	; "db 1,,2" - nothing between them
		call	dbisq
		jr	nz,dbi.exp	; no quote: an expression
		call	dbqstr		; HL = the run's characters
		call	main.nlws
		ld	a,b
		or	a
		jr	z,dbi.str	; the operand ends here: a string
		ld	a,(de)
		cp	","
		jr	nz,dbi.exp	; something else follows: the run was
					;   a character constant, and this
					;   item is an expression after all
dbi.str:	ld	a,1
		ld	(dbstr),a
		ret

dbi.exp:	ld	a,b
		or	a
		ret	z
		ld	a,(de)
		cp	","
		ret	z
		call	dbisq
		jr	nz,dbi.ex1
		call	dbqstr		; a quoted run inside an expression
		jr	dbi.exp		;   is stepped over whole, so a
					;   comma inside it does not end the
					;   item
dbi.ex1:	inc	de
		dec	b
		jr	dbi.exp

; dbqstr - step over one quoted run, counting its characters.
;
;   TWO DELIMITERS TOGETHER ARE ONE CHARACTER and do not close the run -
;   2.3.4's own rule, and the reason the count is not simply the
;   distance between the quotes. "I am ""great"" today" is eighteen
;   characters, not twenty, and every label below the line depends on
;   which number this routine gives.
;
; Input:	DE -> the opening quote
; 		B  = characters left in the operand
; 		HL = a running count
; Output:	DE -> past the closing quote
; 		B  = characters left
; 		HL = the count, plus this run's characters
; 		errdata does not return
; Modifies:	AF, BC, DE, HL

dbqstr:		ld	a,(de)
		ld	c,a		; C = the quote that opened it
		inc	de
		dec	b
dbq.lp:		ld	a,b
		or	a
		jp	z,errdata	; the line ended inside a string
		ld	a,(de)
		inc	de
		dec	b
		cp	c
		jr	nz,dbq.ch	; an ordinary character
		ld	a,b		; a delimiter: doubled, or the end?
		or	a
		ret	z		; the operand ends: it closed here
		ld	a,(de)
		cp	c
		ret	nz		; something else follows: closed
		inc	de		; "" - one character, and on we go
		dec	b
dbq.ch:		inc	hl
		jr	dbq.lp

; dbisq - is the character in A a string delimiter?
;
; Input:    A = a character
; Output:   Z set = it is a quote, either sort
; Modifies: AF

dbisq:		cp	QUOTE1
		ret	z
		cp	QUOTE2
		ret

; ASEG, CSEG and DSEG are numbered in the order of SY_ABS, SY_CODE and
; SY_DATA, so the segment's type is the directive's number minus
; D_ASEG. The line is passed on, like ORG's.

main.seg:	sub	D_ASEG		; 0 ASEG, 1 CSEG, 2 DSEG
		ld	de,(flds+FL_ARG)
		ld	hl,flds+FL_ARGL
		ld	b,(hl)
		call	segdir		; the name and TRANSIENT are its
		jp	main.emit	;   problem, not the driver's

; A GROUP line opens a coexistence group inside the current transient
; DSEG. It comes through before deflab, so a label in front of it is
; caught rather than quietly given the counter.

main.grp:	ld	a,(flds+FL_LABL)
		or	a
		jp	nz,errgrp
		ld	de,(flds+FL_ARG)
		ld	hl,flds+FL_ARGL
		ld	b,(hl)
		call	seggrp
		jp	main.emit

COLON		equ	03ah	; ":" - named rather than written, the
				;   habit fields.as keeps for the
				;   characters it tests

; labcol - the character that follows the label's name.
;
;   NOTHING IS RECORDED WHEN THE LINE IS SPLIT, and nothing needs to
;   be: splitln steps over the colons but leaves FL_LAB and FL_LABL
;   pointing into the line buffer, so what was written after the name
;   is still there to read.
;
;   A LINE WITH NO LABEL ANSWERS "no colon", which is what both
;   callers want. That is why the empty case returns 1 and not 0 -
;   the flags have to say NZ, and 0 would say the opposite.
;
; Input:	flds describes the line
; Output:	Z set = a colon follows the name, "name:" or "name::"
;		NZ    = no label at all, or a name with no colon
;		HL -> that character, when there is a label
; Modifies:	AF, DE, HL

labcol:		ld	a,(flds+FL_LABL)
		or	a
		jr	nz,labcol.have
		inc	a		; no label: 1 is not a colon, and
		ret			;   INC leaves NZ to say so
labcol.have:	ld	e,a
		ld	d,0
		ld	hl,(flds+FL_LAB)
		add	hl,de		; the character after the name
		ld	a,(hl)
		cp	COLON
		ret

; labpub - "name::" declares name PUBLIC.
;
;   M80 2.3.1: "If it is followed by two colons, it is declared as
;   PUBLIC", and "FOO:: RET" is equivalent to "PUBLIC FOO" then
;   "FOO: RET".
;
;   BEFORE THE SYMBOL IS DEFINED. sympub creates a record with
;   SYF_DEF clear so that the definition which follows counts as the
;   first one - the path "public foo" at the top of a file and "foo:"
;   two hundred lines down has always taken.
;
;   Both passes run it. On pass 2 the record is already there and
;   sympub ORs a flag that is already set.
;
; Input:	flds describes the line
; Output:	the name carries SYF_PUB if two colons followed it
; Modifies:	AF, BC, DE, HL, IX

labpub:		call	labcol
		ret	nz		; no label, or no colon at all
		inc	hl
		ld	a,(hl)
		cp	COLON
		ret	nz		; "name:" - the ordinary label
		ld	a,(flds+FL_LABL)
		ld	b,a		; where sympub wants it
		ld	de,(flds+FL_LAB)
		jp	sympub		; "name::"

; deflab - a label in the label field takes the location counter.
;
;   BEFORE ORG and DS act, which looks wrong and is right: "here: ds 4"
;   makes here the address OF the space, not the address after it, and
;   "here: org 100h" gives here the value the counter had BEFORE the
;   ORG. M80 does both.
;
;   On pass 2 the value must agree with what pass 1 recorded. If it does
;   not, the two readings assembled different programs and everything
;   after this label is wrong by the difference - errphase.
;
; Input:	flds describes the line, locctr, passno
; Output:	the symbol is defined
; Modifies:	AF, BC, DE, HL, IX

deflab:		ld	a,(flds+FL_LABL)
		or	a
		ret	z		; no label on this line
		call	labpub		; "name::", before the definition
		call	segwr		; a variable in a transient DSEG
					;   must be inside a GROUP
		ld	a,(flds+FL_LABL)
		ld	b,a
		ld	de,(flds+FL_LAB)
		ld	hl,(locctr)
		ld	a,(curseg)	; relative to the current segment
		ld	c,SYF_LBL	; a label is FIXED - SYF_VAR is what
					;   makes a symbol variable and this
					;   is not it - and it is a LABEL,
					;   which is what symp2 checks and
					;   what SY_FILE and SY_LINE are kept
					;   for. So symdef does
		jp	symdef		; the multiply-defined check AND the
					; pass-2 agreement check that used to
					; be written out here

; An INCLUDE line is consumed here and never written out. From the next
; time round the loop, getline is reading the file it opened.

main.incl:	call	deflab		; THE INCLUDING LINE'S COUNTER, before
					;   a byte of the included file exists.
					;   M80 cannot be asked - it will not
					;   run an include at all - so this
					;   follows the rule the other eight
					;   rows were measured against. 088,
					;   and decisions-pending until now
		call	doincl		; CY set = could not open it
		jp	c,main.noinc
		jp	main.loop

; A macro definition is consumed whole - the MACRO line, the body and the
; ENDM - and none of it is written out. macdef borrows linebuf, so the
; contents of flds are rubbish by the time it returns.

; .LIST, .XLIST, .LALL, .SALL and .XALL. The last three are consecutive
; and in that order, so the mode is what is left after subtracting.
;
; WHETHER A CONTROL LINE LISTS ITSELF IS PROVISIONAL: .XLIST eats its
; own line here and the other four keep theirs. MACLIST.AS puts M80's
; answer in RESULTS.TXT.

main.lst:	ld	a,(dirnum)
		cp	D_LIST
		jr	nz,main.lst1
		ld	a,0ffh		; .LIST: text again, starting here
		ld	(lston),a
		jp	main.emit
main.lst1:	cp	D_XLIST
		jr	nz,main.lst2
		xor	a		; .XLIST: none, and this line is the
		ld	(lston),a	;   first one it eats
		jp	main.loop
main.lst2:	sub	D_LALL		; 0, 1 or 2 - LST_LALL, LST_SALL,
		ld	(lstmode),a	;   LST_XALL, in that order
		jp	main.emit

; .LFCOND, .SFCOND and .TFCOND: whether the lines inside a branch that
; was not taken appear in the listing.
;
; .TFCOND FLIPS WHAT IS IN FORCE, which is an approximation - M80's
; wording is about flipping the default. FCOND.AS asks M80 what the
; default is; nothing yet asks what .TFCOND does to it.

main.fc:	ld	a,(dirnum)
		cp	D_LFCOND
		jr	nz,main.fc1
		ld	a,0ffh
		jr	main.fc3
main.fc1:	cp	D_SFCOND
		jr	nz,main.fc2
		xor	a
		jr	main.fc3
main.fc2:	ld	a,(lstfc)	; .TFCOND: the other one
		cpl
main.fc3:	ld	(lstfc),a
		jp	main.emit

; TITLE, SUBTTL and PAGE.
;
; A TITLE SURVIVES THE PASS AND A SUBTTL DOES NOT. That is not a
; choice: M80's own TITLLST.PRN has a title from source line 3 heading
; page 1 of the listing, and a subtitle from line 4 appearing nowhere
; at all. lstinit clears one buffer and leaves the other.
;
; Both are stored in both passes. The second store writes what the
; first one did.

main.titl:	ld	a,(dirnum)	; D_TITLE and D_SUBTTL are one apart
		sub	D_TITLE		;   and lsttset takes 0 or 1
		ld	c,a
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		call	lsttset
		jp	main.emit

; PAGE alone breaks the page; PAGE with an operand says how long a
; page is. The break happens after this line - see lsteject.

main.page:	ld	a,(flds+FL_ARGL)
		or	a
		jr	z,main.pag1
		ld	de,(flds+FL_ARG)
		call	evalexp		; HL = the count, and absolute:
		call	lstpset		;   a page length in pass 1
main.pag1:	call	lsteject	; WITH AN OPERAND OR WITHOUT: M80
		jp	main.emit	;   breaks the page either way, which
					;   PAGEDIR.AS showed and the manual
					;   does not say

main.mac:	call	labcol		; a name, not a label - and BEFORE
		jp	z,errnlab	;   macdef, so the macro is never
					;   opened. M80 does the same: its
					;   ENDM then gets an error of its
					;   own, for closing nothing
		ld	de,linebuf	; M80 lists the MACRO line and every
		ld	a,(linelen)	;   line of the body. macdef lists
		call	lstbody		;   the body as it reads it; this is
		ld	hl,linebuf	;   the one line it never sees
		ld	ix,flds
		call	macdef
		ld	a,(passno)	; pass 1 only, as with /F above
		dec	a
		jp	nz,main.loop	; a jp: main.loop is 180-odd bytes back
		ld	a,(optmacs)
		or	a
		call	nz,macdump	; /M: read it back out and print it
		jp	main.loop

; A REPT is a macro without a name, expanded on the spot. The count has
; to be worked out BEFORE the body is collected: macdef's loop overwrites
; mdflds, and flds describes the REPT line only until the next getline.

main.rept:	call	deflab		; "lrpt: rept 2" names the place the
					;   first round will start at, which
					;   is where M80 puts it
		ld	de,(flds+FL_ARG)
		ld	a,(flds+FL_ARGL)
		call	evalabs		; HL = how many times: absolute only
		ld	(reptn),hl
		ld	de,linebuf	; the REPT line, for the same reason
		ld	a,(linelen)	;   the MACRO line above
		call	lstbody
		ld	hl,linebuf	; no IX: macrept takes no name and no
		ld	a,MDK_REPT	; parameters, so it never looks at the
		call	macrept		; field block. the IRP will, and can
					; pass it then
					; HL -> the descriptor's far pointer
		ld	bc,(reptn)
		call	mexrept		; its body is now the line source
		jp	main.loop	; the REPT line is not written out

; IRP and IRPC are a REPT with a parameter. The operand is "dummy,items",
; so the comma has to be found first: the left half becomes parameter 0
; and the right half becomes the item list.
;
; The item block is built BEFORE the body is collected, because the items
; are in linebuf and macrept is about to reuse linebuf for every body line
; it reads. Cutting FL_ARGL short at the comma is what makes mdforms read
; one name and stop.

main.irpc:	ld	a,MDK_IRPC
		jr	main.irp1
main.irp:	ld	a,MDK_IRP
main.irp1:	ld	(irpk),a
		call	deflab		; as REPT above, and for both of them:
					;   main.irp1 is below the two entry
					;   points and above the dummy scan,
					;   which reads flds again anyway

		ld	hl,(flds+FL_ARG)	; find the dummy's comma
		ld	a,(flds+FL_ARGL)
		ld	b,a
		ld	c,0		; C = characters before it
main.irp2:	ld	a,b
		or	a
		jp	z,errplst	; no comma: there is no dummy, so the
					; operand is not a parameter list
		ld	a,(hl)
		cp	","
		jr	z,main.irp3
		inc	hl
		dec	b
		inc	c
		jr	main.irp2

main.irp3:	inc	hl		; over the comma: HL -> the items,
		dec	b		; B = how many characters of them
		ld	a,c
		ld	(flds+FL_ARGL),a	; the operand is now the dummy

		ld	a,b		; one level of <> comes off if it is
		or	a		; there. IRPC's are optional and IRP's
		jr	z,main.irp4	; are required, so taking them off the
		ld	a,(hl)		; same way costs nothing and accepts
		cp	"<"		; both
		jr	nz,main.irp4
		inc	hl
		dec	b
		jr	z,main.irp4	; "<" and nothing else
		push	hl		; is the last character the ">"?
		ld	e,b
		ld	d,0
		add	hl,de
		dec	hl
		ld	a,(hl)
		pop	hl
		cp	">"
		jr	nz,main.irp4
		dec	b		; yes: leave it out

main.irp4:	ex	de,hl		; DE -> the items, A = how many,
		ld	a,b		; C = which of the two kinds
		ld	hl,irpk
		ld	c,(hl)
		call	mxpitem		; the block, while linebuf still holds
		ld	(irpn),bc	; the text. BC = iterations

		ld	de,linebuf	; the IRP or IRPC line itself, before
		ld	a,(linelen)	;   its body
		call	lstbody
		ld	hl,linebuf	; collect the body, with the dummy as
		ld	ix,flds		; parameter 0
		ld	a,(irpk)
		call	macrept		; HL -> the descriptor's far pointer

		ld	bc,(irpn)
		call	mexrept		; its body is now the line source
		jp	main.loop	; the IRP line is not written out

; EXITM abandons the expansion on top of the stack, including any rounds
; of a REPT that have not run yet, and unwinds every conditional that
; expansion had opened. The line itself is not written out.
;
; It sits after the cndline call above, like every other directive, so an
; EXITM inside a branch that is not being taken is swallowed rather than
; obeyed.

main.exitm:	call	deflab		; FIRST: mexitm does not return when
		call	mexitm		;   no expansion is open, and the
		jp	main.loop	;   label is M80's whether or not
					;   this one is the stray kind

; A form feed. The page breaks BEFORE the line is listed - the opposite
; of PAGE, whose note lsteject leaves is read after - and then the line
; itself is listed with a length of zero, which is M80's empty line at
; the top of the new page. lstbody is the routine that lists text with
; no address column, and zero characters of text is an empty line.
;
; Nothing else happens to it: no fields, no label, no bytes, and the
; object file never hears of it.

main.ff:	call	lstff
		ld	de,linebuf
		xor	a
		call	lstbody
		jp	main.loop

; getline has already closed and removed every source, so there is nothing
; left to pop here. Report what was done, on the screen either way.
	
main.done:	call	cndeof		; an IF left open at the end of the
					; source is an error, not a shrug
		ld	a,(passno)
		cp	2
		jr	z,main.fin

		ld	a,2		; round again. The object file is
		ld	(passno),a	; created only NOW: making it before
		call	outopen		; the source has been read once would
		call	objopen		; truncate a file the user already had
		jp	c,main.nocrea	; on a source that cannot be
		call	objhead		; assembled at all
		jp	main.pass

main.fin:	call	symp2		; a label pass 1 defined and pass 2
					;   did not. BEFORE objfin: an object
					;   file short of a routine should not
					;   be finished and closed
		call	objfin
		call	lstend		; the listing's last page: Macros:
		call	outclose	;   and Symbols:, then the file
		ld	a,(optsym)	; /S: the symbol table, before the
		or	a		; summary line, so the summary is
		call	nz,symdump	; still the last thing on the screen
		ld	a,(optquiet)	; /Q: no summary line either. It is
		or	a		;   a report and not output, and a
		jr	nz,main.fin2	;   batch file wants neither
		ld	de,msg_endat	; "ended at FILE(line)", in the
		call	putstr		;   notation the errors use. NOT
		ld	a,(curfile)	;   "N lines": the number is where
		call	getfnam		;   END was, and END inside an
		call	putszu		;   include ends every file above
		ld	de,msg_lpar	;   it, so the file named here is
		call	putstr		;   where the assembly stopped and
		ld	hl,(curline)	;   not always the one you typed
		call	putdec
		ld	de,msg_rpar
		call	putstr
main.fin2:
		ld	a,(opthblk)
		or	a
		call	nz,main.heap
		jp	dosexit

; /H - how many heap blocks are still allocated. NOT zero in a correct
; run: every macro's descriptor and body are still there, and should be.
; The number is only useful compared against another run - see HEAP1.AS
; and HEAP2.AS in the tests, which differ only in how many times the same
; macro is expanded and print the same figure.
;
; THAT HOLDS ONLY FOR A MACRO THAT DEFINES NO SYMBOLS, which is what
; those two are: a REPT of "db a,b" and no LOCAL. hash.as calls halloc
; once per record, so EVERY SYMBOL IS A BLOCK, and a LOCAL name becomes
; one symbol per expansion - ??0000, ??0001, ??0002 - which live to the
; end of the assembly because pass 2, forward references and the
; listing's last page all need them. Three expansions of a macro with a
; LOCAL therefore leave two more blocks than one expansion does, and
; nothing is leaking. Issue #19, which is why this paragraph exists.

main.heap:	ld	de,msg_hbk1
		call	putstr
		ld	hl,(hblocks)
		call	putdec
		ld	de,msg_hbk2
		call	putstr
		ret

; --- INCLUDE

; doincl - act on an INCLUDE line: open the named file and make it the
;   source that lines now come from.
;
;   The name is zero-terminated where it lies, on top of whatever followed
;   it in the line buffer. That is safe because an INCLUDE line is never
;   written out, and the buffer is overwritten by the next line anyway -
;   so no buffer of its own is needed for the name. pushfile copies the
;   name into the file-name table before it returns, which is what makes
;   this survive the next getline.
;
;   srcopen AND NOT pushfile: the name is looked for in the
;   including file's directory, then the current directory, then the
;   TATARA path. The top-level source still goes straight to pushfile,
;   because a file the user typed is not searched for.
;
; Input:	flds holds the split line
; Output:	CY clear = the file is open and on top of the stack
;		CY set   = MSX-DOS would not open it
;		(no filename at all does not return - errincl stops)
; Modifies:	AF, BC, DE, HL, IX

doincl:		ld	a,(flds+FL_ARGL)
		or	a
		jp	z,errincl	; INCLUDE with nothing after it
		ld	hl,(flds+FL_ARG)
		ld	e,a
		ld	d,0
		add	hl,de		; HL -> just past the last character
		ld	(hl),0		; terminate the name where it lies
		ld	de,(flds+FL_ARG)
		jp	srcopen		; CY set = found in none of the
					;   places it looks

; --- the /F dump: what splitln made of this line

; shofld - one line of the dump: the four fields in brackers, then the
;   directive number, then where the line came from.
;
;     [start][ld][hl,msg][; go][00][00:0001]
;                              |    |  |
;                              |    |  +-- line number, hexadecimal
;                              |    +----- file number
;                              +---------- directive number, 00 = none
;
;   The origin is here so that the include chain can be checked by eye:
;   without it there is no way to see that each file keeps its own line
;   numbering.
;
; Input:	flds holds the split line, dirnum the directive number
; Output:	one line is written
; Modifies:	AF, BC, DE, HL

shofld:		ld	hl,flds+FL_LAB
		call	putfld
		ld	hl,flds+FL_OP
		call	putfld
		ld	hl,flds+FL_ARG
		call	putfld
		ld	hl,flds+FL_CMT
		call	putfld

		ld	de,msg_ob	; the directive number
		ld	a,1
		call	emitraw
		ld	a,(dirnum)
		call	puthex
		ld	de,msg_cb
		ld	a,1
		call	emitraw

		ld	de,msg_ob	; where the line came from
		ld	a,1
		call	emitraw
		ld	a,(curfile)
		call	puthex
		ld	de,msg_col
		ld	a,1
		call	emitraw
		ld	hl,(curline)	; curline is external here, so the
		push	hl		; two bytes are fetched together
		ld	a,h		; rather than as curline+1
		call	puthex
		pop	hl
		ld	a,l
		call	puthex
		ld	de,msg_cb
		ld	a,1
		call	emitraw

		ld	de,msg_crlf
		ld	a,2
		jp	emitraw

; putfld - write one field in brackets: "[", the text, "]".
;   A field of length 0 prints as "[]", because emitraw writes nothing
;   when asked for nothing.
;
; Input:	HL -> a field entry: address (2 bytes), then length (1)
; Output:	the field is written
; Modifies:	AF, BC, DE, HL

putfld:		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)		; A = the length, DE -> the text
		push	de
		push	af
		ld	de,msg_ob
		ld	a,1
		call	emitraw
		pop	af
		pop	de
		call	emitraw		; the field itself
		ld	de,msg_cb
		ld	a,1
		jp	emitraw

; puthex - write A as two hexadecimal digits, wherever output goes.
;   putdec (msxdos.as) prints straight to the screen, which is no use when
;   the output is a file, so the field dump uses this instead.
;
; Input:	A = the byte
; Output:	two characters are written
; Modifies:	AF, BC, DE, HL

puthex:		push	af
		rrca			; rrca, not rra: rra would rotate the
		rrca			; carry flag in through the top
		rrca
		rrca
		call	puthex.n	; the high nibble
		ld	(hexbuf),a
		pop	af
		call	puthex.n	; the low one
		ld	(hexbuf+1),a
		ld	de,hexbuf
		ld	a,2
		jp	emitraw
puthex.n:	and	00fh
		add	a,"0"
		cp	"9"+1
		ret	c		; 0-9
		add	a,"A"-"9"-1	; A-F
		ret

; --- the output end

; outopen - decide where output goes and get it ready.
;
;   MSX-DOS2 gives the screen a file handle of its own, so /P needs no
;   separate printing path: everything goes through _WRITE either way.
;
; Input:	optscrn, dstname (from cmdparse)
; Output:	CY clear = outhand is ready to be written to
;		CY set   = the output file could not be created
; Modifies:	AF, BC, DE, HL

outopen:	ld	a,STDOUT	; no listing file named: the text goes
		ld	(outhand),a	;   to the screen, and main.emit
		ld	a,(lstname)	;   decides whether there is any
		or	a
		ret	z		; CY is clear: STDOUT is 1
		ld	de,lstname
		xor	a		; mode 0 = read and write
		ld	b,a		; attributes 0 = an ordinary file
		system	_CREATE		; -> A = error, B = the handle
		or	a
		scf
		ret	nz		; main.nocrea says so. This
		ld	a,b		;   path unreachable; it is given
		ld	(outhand),a	;   something to create again
		or	a
		ret

; outclose - close the output file. The screen's handle is not ours to
;   close, so leave it alone.
;
; Input:	nothing
; Output:	the file is closed
; Modifies:	AF, BC, DE, HL

outclose:	ld	a,(outhand)
		cp	STDOUT
		ret	z
		ld	b,a
		system	_CLOSE
		ret

; samename - are the two filenames the asme as typed?
;
;   MSX-DOS upper-cases the command tail, so a plain comparison is enough
;   for the ordinary accident. It does not catch "test.as a:test.as": that
;   needs the patsh MSX-DOS resolves them to, which is a later refinement.
;
; Input:	nothing (reads srcname and dstname)
; Output:	Z set = the two names are identical
; Modifies:	AF, DE, HL

samename:	ld	hl,srcname
		ld	de,dstname
samename.cp:	ld	a,(de)
		cp	(hl)
		ret	nz		; they differ
		or	a
		ret	z		; both terminators: identical
		inc	hl
		inc	de
		jr	samename.cp

; --- the ways out

; The include failure is the first message that says WHERE the trouble
; was, not just what it was. curfile and curline still descuribe the 
; INCLUDE line itself, because nothing was pushed.

main.noinc:	ld	de,msg_noopn	; the same wording as a bad source
		call	putstr		; file, so one message serves both
		ld	de,(flds+FL_ARG)
		call	putszu		; doincl terminated it in place
		ld	de,msg_from
		call	putstr
		ld	a,(curfile)
		call	getfnam
		call	putszu
		ld	de,msg_lpar
		call	putstr
		ld	hl,(curline)
		call	putdec
		ld	de,msg_rpar
		call	putstr
		call	errtrl		; and the rest of the chain. The
					; failed include was never pushed, so
					; the top of the stack is the file
					; named above - which errtrl skips,
					; exactly as it does for errdie
		jp	dosexit

main.noopen:	ld	de,msg_noopn
		call	putstr
		ld	de,srcname
		call	putszu
		ld	de,msg_nl
		call	putstr
		jp	dosexit

main.nocrea:	ld	de,msg_nocre
		call	putstr
		ld	de,dstname
		call	putszu
		ld	de,msg_nl
		call	putstr
		jp	dosexit

main.same:	ld	de,msg_same
		call	putstr
		jp	dosexit

main.usage:	jp	cmdusage	; the banner and the screen, in the
					;   module that owns the command line

main.ver:	call	cmdver		; /V: the banner alone
		jp	dosexit

main.nomap:	ld	de,msg_nomap
		call	putstr
		jp	dosexit

main.dos1:	ld	de,msg_dos1	; 09h, NOT putstr: putstr writes with
		system	_STROUT		;   _WRITE, which is a DOS 2 function,
					;   and this is the one message printed
					;   on a machine that has no DOS 2
		jp	dosexit

		dseg


linebuf:	defs	MAXLINE+3	; one line, its terminator, and room
					; for the CR+LF emitln puts over it
linelen:	defs	1		; how long that line was
flds:		defs	FLSIZE		; what splitln made of that line
dirnum:		defs	1		; what dirlook made of its operation
hexbuf:		defs	2		; puthex builds its two digits here
mdfp:		defs	4		; far pointer: a macro being called
reptn:		defs	2		; main.rept: the repeat count, across
					;   the body collection
nlproc:		defs	2		; main.nlst: sympub or symext
endseen:	defs	1		; 0FFh once an END line has been read
lstfc:		defs	1		; 0 once .SFCOND has been seen: the
					;   lines inside a branch that was not
					;   taken stop appearing
					;   Written by the object writer;
					;   nothing reads it before that
irpk:		defs	1		; main.irp: MDK_IRP or MDK_IRPC
irpn:		defs	2		; how many iterations mxpitem found
dbwide:		defs	1		; main.db/main.dw: 1 or 2 bytes per
					;   expression
dbtot:		defs	2		; the bytes a DB or DW line adds
dbstr:		defs	1		; dbitem: the item was a string on
					;   its own
dbsrc:		defs	2		; where the item dbitem is measuring
					;   began - dbemit needs the text, and
					;   dbitem only leaves the end of it
dbelen:		defs	1		; and how long it turned out to be

; These four have no "$" on the end: they go through emitraw, which is
; told how many bytes to write and never looks for a terminator. Keeping
; them apart from the "$" messages makes a mix-up obvious.

msg_ob:		defb	"["		; used with emitraw, so no "$"
msg_cb:		defb	"]"
msg_col:	defb	":"
msg_crlf:	defb	CHR_CR,CHR_LF

msg_endat:	defb	"ended at $"
msg_hbk1:	defb	"HEAP: $"
msg_hbk2:	defb	" blocks.",CHR_CR,CHR_LF,"$"
msg_nl:		defb	CHR_CR,CHR_LF,"$"
msg_noopn:	defb	"ERROR: cannot open $"
msg_nocre:	defb	"ERROR: cannot create $"
msg_from:	defb	CHR_CR,CHR_LF,"    included from $"
msg_lpar:	defb	"($"
msg_rpar:	defb	")",CHR_CR,CHR_LF,"$"
msg_same:	defb	"ERROR: the output file is the input file.",CHR_CR
		defb	CHR_LF,"$"
msg_dos1:	defb	"ERROR: Tatara needs MSX-DOS2 or Nextor.",CHR_CR,CHR_LF
		defb	"$"
msg_nomap:	defb	"ERROR: Tatara needs a memory mapper.",CHR_CR
		defb	CHR_LF,"$"
