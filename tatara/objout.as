; objout.as - the relocatable object file Tatara produces.
;
;   tatara-obj-spec.md draft 2 is the format, and this module writes
;   it. The first step was a valid empty module: the header, MODNAME
;   and END.
;
;   NOTHING IS BUFFERED, and plan.md's "second ~1 KB the data segment
;   has to find" is not needed. Every record's length is known before
;   its first byte goes out - a MODNAME is two bytes and a name, an END
;   is nothing, and the DATA record is emitn, which emitbuf already
;   holds. The data cost of this module is twenty bytes.
;
;   the records are the assembler's own tables written out, so this
;   module walks symtab, segtab and grptab through hash.inc. THE NAMES
;   IN THEM ARE IN THE MAPPER: see objnam.
;
;   the are what the assembler emitted, and they are written WHILE
;   pass 2 runs rather than at the end of it. A DATA record's length is
;   not known until the run it describes ends, so the header goes out
;   with a placeholder and objflsh seeks back for it - which means that
;   WHILE A RUN IS OPEN, NOTHING ELSE MAY BE WRITTEN TO THE FILE.
;
;   IF NO OUTPUT FILE WAS NAMED, objon is zero and every entry point
;   returns at once. That is what lets the whole test suite, which runs
;   "tatara /p", go on writing nothing at all.

OBJLIB		equ	1		; skips the externals in objout.inc

		public	objopen
		public	objhead
		public	objdata
		public	objfix
		public	objentr
		public	objfin
		public	objkill
		public	objon

		include	objout.inc
		include	cmdline.inc	; dstname, srcname, optcase
		include	msxdos.inc	; _CREATE, _WRITE, _CLOSE
		include	errs.inc	; errwrit, errpund
		include	hash.inc	; HTCASES, htnext, HT_KLEN
		include	symtab.inc	; the three tables and their
					;   layouts, segnum, grpnum, segpark
		include	alloc.inc	; deref, for derefp
		include	farptr.inc	; derefp, NULLOFF
		include	emit.inc	; emitn, emitbuf, lstaddr, lstseg,
					;   MAXEMIT
		include	expr.inc	; exty, exeidx, SY_ABS, SYTEXT

		cseg

objmagc:	defb	"TRO",01ah,OBJVER

; objopen - create the object file and write its five-byte header.
;
;   The Ctrl-Z is deliberate (spec 9): TYPEing an object file prints
;   "TRO" and stops, instead of spraying the screen.
;
;   It runs at the START OF PASS 2, beside outopen and for the same
;   reason - a source that cannot be assembled must not truncate a file
;   the user already had.
;
; Input:	nothing (dstname)
; Output:	CY set = the file could not be created
; Modifies:	AF, BC, DE, HL

objopen:	xor	a
		ld	(objon),a	; nothing is open, whatever happens
		ld	(objenon),a	; END named no address yet - pass 1
					;   may have said one, and pass 2
					;   will say it again
		ld	hl,NULLOFF
		ld	(objfhd+2),hl	; and no fixups: an empty chain, and
		ld	a,FIXPER	;   a head block that is "full", so
		ld	(objfn),a	;   the first fixup allocates one
		xor	a
		ld	a,(dstname)
		or	a
		ret	z		; none named: CY is clear and every
					;   other entry point is a ret
		ld	de,dstname
		xor	a		; mode 0 = read and write
		ld	b,a		; attributes 0 = an ordinary file
		system	_CREATE		; -> A = error, B = the handle
		or	a
		scf
		ret	nz
		ld	a,b
		ld	(objhand),a
		ld	a,0ffh
		ld	(objon),a
		ld	de,objmagc
		ld	a,5
		call	objwr
		or	a		; CY clear: the file is open
		ret

; objwr - A bytes at DE, straight to the object file.
;
; Input:	DE -> the bytes
;		A  = how many
; Output:	they are written
; Modifies:	AF, BC, HL

objwr:		or	a
		ret	z		; nothing to write
		ld	l,a
		ld	h,0
		ld	a,(objhand)
		ld	b,a
		system	_WRITE		; -> A = the error
		or	a
		ret	z
		jp	errwrit		; disk full, or write-protected

; objrec - a record header: the type byte and the payload's length.
;
; Input:	A  = the record type
;		HL = how long the payload is
; Output:	three bytes are written
; Modifies:	AF, BC, DE, HL

objrec:		ld	(objhdr),a
		ld	(objhdr+1),hl
		ld	de,objhdr
		ld	a,3
		jp	objwr

; objstr - a counted string: one length byte, then that many bytes.
;
; Input:	DE -> the text
;		A  = how long it is, 1 to 255
; Output:	1+A bytes are written
; Modifies:	AF, BC, DE, HL

objstr:		push	af
		push	de
		call	objone		; the length
		pop	de
		pop	af
		jp	objwr		; and that many bytes

; objone - the byte in A, on its own. Four callers and counting: a
;   record that is mostly one-byte fields is what this format is.
;
; Input:	A = the byte
; Output:	it is written
; Modifies:	AF, BC, DE, HL

objone:		ld	(objbyt),a
		ld	de,objbyt
		ld	a,1
		jp	objwr

; objhead - the records the linker's first pass reads.
;
;   THE ORDER IS THE SPEC'S (10): an index may only be named after the
;   record that creates it. A SEGDEF names a group, a PUBDEF names a
;   segment, so groups come before segments and segments before both
;   symbol lists.
;
;   IT RUNS AT THE END OF PASS 1, from main.done. A SEGDEF carries the
;   segment's size, and segrst zeroes every size at the start of a
;   pass - by the time pass 2 begins, the numbers this needs are gone.
;
; Input:	nothing
; Output:	the records are written
; Modifies:	AF, BC, DE, HL

objhead:	ld	a,(objon)
		or	a
		ret	z
		call	segpark		; the current contribution's size
					;   is still live in locctr: until
					;   this runs its SG_SIZE is short
		call	objmod
		call	objgrps
		call	objsegs
		call	objexts
		jp	objpubs

; objmod - MODNAME: the flags byte and the module's name.
;
; Input:	nothing
; Output:	the record is written
; Modifies:	AF, BC, DE, HL

objmod:		call	objbase		; DE -> the module's name, A = how
		ld	l,a		;   long it is
		ld	h,0
		push	hl		; the length has to outlive objrec
					;   and objwr: both end in a BDOS
					;   call, and a BDOS call modifies BC
		inc	hl
		inc	hl		; the flags byte and the length byte
		push	de
		ld	a,OR_MOD
		call	objrec
		ld	a,(optcase)	; bit 0 says how SYMBOLS were
		cp	HTCASES		;   compared - not how the module
		ld	a,0		;   name happened to be typed
		jr	nz,objh.f
		inc	a
objh.f:		call	objone
		pop	de		; the name
		pop	hl		; and its length, untouched
		ld	a,l
		jp	objstr

; objgrps - a GRPDEF for every group, in the order of the numbers
;   seggrp handed out, because that order IS the file's group index.
;
; Input:	nothing (grpnum)
; Output:	the records are written
; Modifies:	AF, BC, DE, HL, IX

objgrps:	xor	a
		ld	(objidx),a
objg.lp:	ld	a,(grpnum)
		ld	hl,objidx
		cp	(hl)
		ret	z
		ld	ix,grptab
		ld	c,0		; a group record's payload IS its
		call	objseek		;   number
		ret	c
		call	objkey		; A = the name's length
		ld	l,a
		ld	h,0
		inc	hl		; and the length byte
		ld	a,OR_GRP
		call	objrec
		ld	c,0
		call	objnam
		ld	hl,objidx
		inc	(hl)
		jp	objg.lp

; objsegs - a SEGDEF for every segment but the ASEG, in index order for
;   the same reason.
;
;   INDEX 0 IS THE ASEG and gets no record: an absolute segment is not
;   one the linker places. Everything else is therefore one lower in
;   the file than it is here, which is what objpubs subtracts.
;
; Input:	nothing (segnum)
; Output:	the records are written
; Modifies:	AF, BC, DE, HL, IX

objsegs:	ld	a,1
		ld	(objidx),a
objs.lp:	ld	a,(segnum)
		ld	hl,objidx
		cp	(hl)
		ret	z
		ld	ix,segtab
		ld	c,SG_IDX
		call	objseek
		ret	c
		call	objpay		; the fields, out of the mapper
		ld	de,SG_SIZE	;   BEFORE anything is written
		add	hl,de
		ld	a,(hl)
		ld	(objsiz),a
		inc	hl
		ld	a,(hl)
		ld	(objsiz+1),a
		inc	hl
		ld	a,(hl)		; SG_FLAGS: the file defines two of
		and	SGF_DATA+SGF_TRAN	; them and reserves the rest
		ld	(objflg),a
		inc	hl
		ld	a,(hl)		; SG_GRP - and GRPNONE is the same
		ld	(objgrp),a	;   0FFh the file uses for "none"
		call	objkey		; A = the key: the group byte, then
		dec	a		;   the name
		ld	l,a
		ld	h,0
		ld	de,5		; flags, group, size, length byte
		add	hl,de
		ld	a,OR_SEG
		call	objrec
		ld	a,(objflg)
		call	objone
		ld	a,(objgrp)
		call	objone
		ld	de,objsiz
		ld	a,2
		call	objwr
		ld	c,1		; skip the key's group byte
		call	objnam
		ld	hl,objidx
		inc	(hl)
		jp	objs.lp

; objexts - an EXTDEF for every external, and the index the file gives
;   it written back into the symbol.
;
;   THE RENUMBERING IS THE POINT. The walk is in bucket order, not the
;   order EXTRN declared them, and the file numbers by record order -
;   so the two would disagree unless one of them moves. Rewriting
;   SY_VAL is safe HERE AND ONLY HERE: this runs at the end of pass 1,
;   and the first record that quotes an external index is the RELOC,
;   written in pass 2. It must not move.
;
; Input:	nothing
; Output:	the records are written, SY_VAL renumbered
; Modifies:	AF, BC, DE, HL, IX

objexts:	call	objfrst
		xor	a
		ld	(objidx),a	; the index the next name takes
objx.lp:	ld	ix,symtab
		ld	hl,objit
		call	htnext
		ret	c
		call	objpay
		ld	de,SY_FLAGS
		add	hl,de
		ld	a,(hl)
		and	SYF_EXT
		jp	z,objx.lp
		call	objkey
		ld	l,a
		ld	h,0
		inc	hl
		ld	a,OR_EXT
		call	objrec
		ld	c,0
		call	objnam
		call	objpay		; SY_VAL = the index it just took
		ld	a,(objidx)
		ld	(hl),a
		inc	hl
		ld	(hl),0		; MAXEXT keeps it inside one byte
		ld	hl,objidx
		inc	(hl)
		jp	objx.lp

; objpubs - a PUBDEF for every public symbol.
;
; Input:	nothing
; Output:	the records are written
;		(errpund does not return)
; Modifies:	AF, BC, DE, HL, IX

objpubs:	call	objfrst
objp.lp:	ld	ix,symtab
		ld	hl,objit
		call	htnext
		ret	c
		call	objpay
		ld	de,SY_FLAGS
		add	hl,de
		ld	a,(hl)
		ld	(objflg),a
		and	SYF_PUB
		jp	z,objp.lp
		ld	a,(objflg)
		and	SYF_DEF
		jp	z,errpund	; PUBLIC promised it and nothing in
					;   the module ever gave it a value
		call	objpay
		ld	a,(hl)		; SY_VAL: the offset
		ld	(objsiz),a
		inc	hl
		ld	a,(hl)
		ld	(objsiz+1),a
		inc	hl
		ld	a,(hl)		; SY_TYPE: its segment, as the FILE
		call	objfseg		;   numbers it
		ld	(objgrp),a
		call	objkey
		ld	l,a
		ld	h,0
		ld	de,4		; the segment, the offset, and the
		add	hl,de		;   length byte
		ld	a,OR_PUB
		call	objrec
		ld	a,(objgrp)
		call	objone
		ld	de,objsiz
		ld	a,2
		call	objwr
		ld	c,0
		call	objnam
		jp	objp.lp

; objfrst - a walk, back to the beginning.
;
; Input:	nothing
; Output:	objit is before the first record
; Modifies:	AF, HL

objfrst:	xor	a
		ld	(objit),a	; bucket 0...
		ld	hl,NULLOFF
		ld	(objit+3),hl	; ...and no record yet
		ret

; objseek - the record in table IX whose payload byte at offset C is
;   (objidx).
;
;   THE WALK IS RESTARTED FOR EVERY INDEX. htnext hands records back in
;   bucket order and a SEGDEF's position in the file is its index, so
;   one or the other has to be a walk per index - and a table of three
;   to ten records is the cheaper one to walk twice. An index-ordered
;   list would cost four bytes of resident RAM per segment to save a
;   few hundred microseconds, once.
;
; Input:	IX = the table's descriptor
;		C  = the byte's offset inside the payload
;		(objidx) = the index wanted
; Output:	CY clear = objit is on it
;		CY set   = no record has it
; Modifies:	AF, BC, DE, HL

objseek:	call	objfrst
objsk.lp:	push	bc
		ld	hl,objit
		call	htnext		; CY set = that was the last one
		pop	bc
		ret	c
		push	bc
		call	objpay
		pop	bc
		ld	b,0
		add	hl,bc
		ld	a,(hl)
		ld	hl,objidx
		cp	(hl)
		jr	nz,objsk.lp
		or	a		; found it, and objit is on it
		ret

; objkey - the record objit is on, mapped.
;
;   EVERY BDOS CALL UNDOES THIS. MSX-DOS takes page 2 back for itself,
;   so a pointer returned here is worth nothing after the next write
;   and objnam calls it again for every character.
;
; Input:	objit is on a record
; Output:	HL -> the key, A = the key's length
; Modifies:	AF, BC, DE, HL

objkey:		derefp	objit+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)
		inc	hl
		ret

; objpay - the same record's payload.
;
; Input:	objit is on a record
; Output:	HL -> the payload, A = the key's length
; Modifies:	AF, BC, DE, HL

objpay:		call	objkey
		ld	e,a
		ld	d,0
		add	hl,de
		ret

; objnam - a counted string whose bytes are in the MAPPER.
;
;   The name cannot be handed to objwr as a buffer: page 2 belongs to
;   MSX-DOS during the write, and what _WRITE would read is whatever
;   DOS has mapped there. symdump met this first and answered it the
;   same way - map the record again for each character. One BDOS call
;   per character, into a sector buffer, a few hundred times in an
;   assembly.
;
;   The alternative is a resident buffer, and its size would quietly
;   become the longest name a module may export. There is no such limit
;   today and this note does not introduce one.
;
; Input:	objit is on the record
;		C  = key bytes in front of the name: 0 for a symbol or
;		     a group, 1 for a segment, whose key is the group
;		     byte and then the name
; Output:	1 + (the key's length - C) bytes are written
; Modifies:	AF, BC, DE, HL

objnam:		ld	a,c
		ld	(objskp),a
		call	objkey		; A = the whole key's length
		ld	hl,objskp
		sub	(hl)
		ld	(objnln),a
		call	objone		; the length byte
		xor	a
		ld	(objnat),a	; which character we are on
objn.lp:	ld	a,(objnat)
		ld	hl,objnln
		cp	(hl)
		ret	z
		call	objkey		; the record again: see above
		ld	a,(objskp)
		ld	e,a
		ld	a,(objnat)
		add	a,e
		ld	e,a
		ld	d,0
		add	hl,de
		ld	a,(hl)
		call	objone
		ld	hl,objnat
		inc	(hl)
		jr	objn.lp

; objfseg - a segment index as the FILE numbers it.
;
;   Internally the ASEG is 0, the classic CSEG 1, the classic DSEG 2.
;   The ASEG gets no SEGDEF, so the file is one behind - and an
;   absolute value is FFh, which is the file's way of saying "this is
;   an address, do not relocate it".
;
; Input:	A = the index this program uses
; Output:	A = the index the file uses
; Modifies:	AF

objfseg:	or	a
		jr	z,objf.abs
		dec	a
		ret
objf.abs:	ld	a,0ffh		; the ASEG: an address, not an
		ret			;   offset into anything

; objwd - the word in HL, low byte first, which is the format's order
;   and the Z80's.
;
; Input:	HL = the word
; Output:	two bytes are written
; Modifies:	AF, BC, DE, HL

objwd:		ld	(objsiz),hl
		ld	de,objsiz
		ld	a,2
		jp	objwr

; objpos - where the file pointer is now, kept for objgo.
;
;   Seeking zero bytes from where we are is how MSX-DOS is asked.
;
; Input:	nothing
; Output:	objrps
; Modifies:	AF, BC, DE, HL

objpos:		ld	hl,0
		ld	de,0
		ld	a,(objhand)
		ld	b,a
		ld	a,1		; 1 = from here, and +0 asks rather
		system	_SEEK		;   than moves
		or	a
		jp	nz,errwrit
		ld	(objrps),de
		ld	(objrps+2),hl
		ret

; objgo, objend - to the length field the run left behind, and back to
;   the end of the file afterwards.
;
; Input:	objrps (objgo)
; Output:	the pointer has moved
; Modifies:	AF, BC, DE, HL

objgo:		ld	hl,(objrps+2)
		ld	de,(objrps)
		ld	a,(objhand)
		ld	b,a
		xor	a		; 0 = from the beginning
		system	_SEEK
		or	a
		jp	nz,errwrit
		ret

objend:		ld	hl,0
		ld	de,0
		ld	a,(objhand)
		ld	b,a
		ld	a,2		; 2 = from the end, which is where
		system	_SEEK		;   the next record goes
		or	a
		jp	nz,errwrit
		ret

; objrun - open a DATA run: everything but its length.
;
;   The length goes out as a placeholder and objflsh comes back for it,
;   because a run's length is not known until the run ends. objpos is
;   called AFTER the type byte, so what it remembers is exactly where
;   the length field sits.
;
; Input:	A  = the segment, as the file numbers it
;		HL = where the run starts, within that segment
; Output:	the header is written and the run is open
; Modifies:	AF, BC, DE, HL

objrun:		ld	(objrsg),a
		ld	(objrof),hl
		ld	(objrnx),hl
		ld	a,OR_DATA
		call	objone
		call	objpos		; where the length will have to go
		ld	hl,0
		call	objwd		; and a placeholder to hold its place
		ld	a,(objrsg)
		call	objone
		ld	hl,(objrof)
		call	objwd
		ld	a,0ffh
		ld	(objropn),a
		ret

; objflsh - close the open run, if there is one.
;
; Input:	nothing
; Output:	the record's length is written and the pointer is back
;		at the end of the file
; Modifies:	AF, BC, DE, HL

objflsh:	ld	a,(objropn)
		or	a
		ret	z
		xor	a
		ld	(objropn),a
		ld	hl,(objrnx)	; the payload is the segment byte,
		ld	de,(objrof)	;   the offset, and everything
		or	a		;   between where the run started and
		sbc	hl,de		;   where it stopped
		ld	de,3
		add	hl,de
		push	hl
		call	objgo
		pop	hl
		call	objwd
		jp	objend

; objdata - the bytes this line emitted.
;
;   CALLED FOR EVERY LINE OF PASS 2, from main.emit, and before
;   main.emit's tests: it returns early when neither /P nor /L
;   was given, and the object file is written when neither was.
;
;   A line that emits nothing does nothing here. A run is not broken by
;   a comment or a CSEG line; it is broken by the next line that emits
;   somewhere other than where the run stopped, which is one test and
;   covers ORG, DS, a segment change, and whatever is invented later.
;
; Input:	nothing (emitn, emitbuf, lstaddr, lstseg)
; Output:	the bytes are in the file
; Modifies:	AF, BC, DE, HL

objdata:	ld	a,(objon)
		or	a
		ret	z
		ld	hl,(emitn)
		ld	a,h
		or	l
		ret	z		; nothing emitted: nothing to say
		ld	a,(objropn)	; the MAXEMIT assertion moved to
					;   main.emit: it belongs where it
					;   runs whether or not a file is open
		or	a
		jr	z,objd.new
		ld	a,(lstseg)	; the same segment as the open run,
		call	objfseg		;   and no gap since it stopped?
		ld	hl,objrsg
		cp	(hl)
		jr	nz,objd.brk
		ld	hl,(lstaddr)
		ld	de,(objrnx)
		or	a
		sbc	hl,de
		jr	z,objd.put	; then it carries on
objd.brk:	call	objflsh
objd.new:	ld	a,(lstseg)
		call	objfseg
		ld	hl,(lstaddr)
		call	objrun
objd.put:	ld	de,emitbuf
		ld	hl,(emitn)
		ld	a,h
		or	a
		jr	z,objd.one	; the worst line is 256 bytes,
		ld	a,128		;   one more than objwr takes, so
		call	objwr		;   it goes out in halves
		ld	de,emitbuf+128
		ld	a,128
		call	objwr
		jr	objd.adv
objd.one:	ld	a,l
		call	objwr
objd.adv:	ld	hl,(objrnx)
		ld	de,(emitn)
		add	hl,de
		ld	(objrnx),hl
		ret

; objfix - remember that the word about to go out has a hole in it.
;
;   CALLED FROM emitxw, which is the only routine that turns an
;   expression into a word - every 16-bit operand, every DW. exty is
;   still the type of the value it just evaluated, which is what says
;   whether there is a hole at all.
;
;   The entry is built in ordinary RAM and copied into the table,
;   because the table is in the mapper.
;
; Input:	HL = the word's offset within its segment
;		(exty, exeidx, lstseg)
; Output:	an entry, if the value needs one
; Modifies:	AF, BC, DE, HL

objfix:		ld	a,(objon)
		or	a
		ret	z
		ld	a,(exty)
		or	a
		ret	z		; SY_ABS: a plain number, no hole
		ld	(objfx+2),hl	; where the hole is
		cp	SYTEXT
		jr	z,objf.ext
		call	objfseg		; a segment: the target is that
		ld	l,a		;   segment, as the FILE numbers it
		ld	h,0
		ld	(objfx+4),hl
		xor	a		; kind 0: add the segment's base
		jr	objf.put
objf.ext:	ld	hl,(exeidx)	; an external: the target is its
		ld	(objfx+4),hl	;   index, and the index is a WORD
		ld	a,1		; kind 1: add the import's value
objf.put:	ld	(objfx),a
		ld	a,(lstseg)	; whose content holds the hole
		call	objfseg
		ld	(objfx+1),a
		jr	objfadd

; objfadd - the entry in objfx, into the table.
;
; Input:	objfx
; Output:	it is in the head block
; Modifies:	AF, BC, DE, HL

objfadd:	ld	a,(objfn)
		cp	FIXPER
		call	nc,objfnew	; full, or there is none yet
		ld	a,(objfn)	; FIX_E + n*6
		call	objfoff
		push	hl
		derefp	objfhd
		pop	de
		add	hl,de
		ex	de,hl
		ld	hl,objfx
		ld	bc,6
		ldir
		ld	a,(objfn)
		inc	a
		ld	(objfn),a
		derefp	objfhd		; the count lives in the block as
		ld	de,FIX_N	;   well, because objrels reads it
		add	hl,de		;   there and objfn will have moved
		ld	a,(objfn)	;   on to another block by then
		ld	(hl),a
		ret

; objfoff - where entry A sits inside a block.
;
; Input:	A = which entry
; Output:	HL = FIX_E + A*6
; Modifies:	AF, DE, HL

objfoff:	ld	l,a
		ld	h,0
		ld	e,l
		ld	d,h
		add	hl,hl		; *2
		add	hl,de		; *3
		add	hl,hl		; *6
		ld	de,FIX_E
		add	hl,de
		ret

; objfnew - another block, at the head of the chain.
;
;   The newest block is the head, so objrels walks the blocks newest
;   first. A reader takes RELOC entries in any order (spec 06h), so
;   nothing has to be reversed.
;
; Input:	nothing
; Output:	an empty head block (errheap does not return)
; Modifies:	AF, BC, DE, HL

objfnew:	ld	bc,FIXSIZE
		ld	hl,objftm
		call	halloc
		jp	c,errheap
		derefp	objftm		; its FIX_NXT is the old head
		ex	de,hl
		ld	hl,objfhd
		ld	bc,4
		ldir
		fpcopy	objfhd,objftm	; and it becomes the head
		xor	a
		ld	(objfn),a
		ret

; objrels - one RELOC record per block.
;
;   The count is in the block, so the record's length is known before
;   its first byte and nothing has to be counted or seeked. Each entry
;   is copied into ordinary RAM before it is written: page 2 belongs to
;   MSX-DOS during a BDOS call, which is the hazard objnam met first.
;
; Input:	nothing
; Output:	the records are written
; Modifies:	AF, BC, DE, HL

objrels:	fpcopy	objfit,objfhd
objr.lp:	fpnull	objfit
		ret	z		; the chain's end
		derefp	objfit
		ld	de,FIX_N
		add	hl,de
		ld	a,(hl)
		ld	(objfc),a
		or	a
		jr	z,objr.nxt
		call	objfoff		; count*6, and FIX_E over
		ld	de,FIX_E	;   again - the payload is the
		or	a		;   entries alone
		sbc	hl,de
		ld	a,OR_RELOC
		call	objrec
		xor	a
		ld	(objfi),a
objr.e:		ld	a,(objfi)
		ld	hl,objfc
		cp	(hl)
		jr	z,objr.nxt
		ld	a,(objfi)
		call	objfoff
		push	hl
		derefp	objfit
		pop	de
		add	hl,de
		ld	de,objfx	; out of the mapper before writing
		ld	bc,6
		ldir
		ld	de,objfx
		ld	a,6
		call	objwr
		ld	hl,objfi
		inc	(hl)
		jr	objr.e
objr.nxt:	derefp	objfit		; HL is at FIX_NXT, which is where
		fpsave	objfit		;   the next block is
		jr	objr.lp

; objentr - remember what END was given.
;
;   CALLED FROM main.end, IN BOTH PASSES. A record cannot be written
;   there: pass 2 has a DATA run open and its length is still a
;   placeholder. objopen clears this between the passes, so pass 1's
;   answer never reaches the file.
;
; Input:	HL = the value END's operand came to
;		A  = exty
; Output:	remembered (errext does not return)
; Modifies:	AF, BC, DE, HL

objentr:	ld	(objenv),hl
		cp	SYTEXT		; the record has a segment and an
		jp	z,errext	;   offset and no external form
		call	objfseg
		ld	(objens),a
		ld	a,0ffh
		ld	(objenon),a
		ret

; objentw - and write it, if there was one.
;
; Input:	nothing
; Output:	the record, or nothing at all
; Modifies:	AF, BC, DE, HL

objentw:	ld	a,(objenon)
		or	a
		ret	z
		ld	hl,3
		ld	a,OR_ENT
		call	objrec
		ld	a,(objens)
		call	objone
		ld	hl,(objenv)
		jp	objwd

; objfin - the last run, the fixups, the entry point, the END record,
;   and close the file.
;
;   Anything after END is ignored by a reader (spec 11), so nothing
;   here has to pad or truncate.
;
; Input:	nothing
; Output:	the file is closed
; Modifies:	AF, BC, DE, HL

objfin:		ld	a,(objon)
		or	a
		ret	z
		call	objflsh		; the last run has no line after it
		call	objrels		; NOW the fixups can go out: the
		call	objentw		;   placeholder has been filled in
		ld	hl,0
		ld	a,OR_END
		call	objrec
		ld	a,(objhand)
		ld	b,a
		system	_CLOSE
		ret

; objkill - close the object file and delete it.
;
;   CALLED FROM errdie, and from nowhere else. objopen creates the file
;   at the start of pass 2 - deliberately, so that a source which fails
;   on pass 1 cannot truncate a file the user already had - and an error
;   on pass 2 therefore leaves one with the right name, the current
;   timestamp and part of the content. Nothing about it says it is
;   rubbish, and the file it replaced is gone. Issue #22.
;
;   objon IS THE WHOLE OF THE CARE HERE. errdie also fires on pass 1, on
;   a command-line error, under /P and when _CREATE itself failed, and in
;   every one of those a file of this name may be the user's from an
;   earlier run. Deleting it would turn an error into data loss, which is
;   a worse fault than the one this routine fixes. objopen clears objon
;   before anything can go wrong and sets it only once _CREATE has handed
;   back a handle, so it says "this run made a file", which is exactly
;   the question.
;
;   The handle is closed before the delete rather than after, or not at
;   all: deleting a file that is still open is a question about MSX-DOS
;   2's internals nobody needs answered.
;
; Input:	nothing (objon, objhand, dstname)
; Output:	no object file of this run's making is left on disk
; Modifies:	AF, BC, DE, HL

objkill:	ld	a,(objon)
		or	a
		ret	z		; none created this run
		xor	a
		ld	(objon),a	; it is going, so nothing may write
		ld	a,(objhand)	;   to it either
		ld	b,a
		system	_CLOSE
		ld	de,dstname
		system	_DELETE
		ret

; objbase - the module's name: the TITLE's first six characters, or
;   the source file's name with the path and the extension taken off,
;   so "A:\SRC\TATARA.AS" is "TATARA".
;
;   The name is whatever was typed. MSX-DOS 2 hands the command tail
;   over unchanged - it does NOT upper-case it - so "tatara.as" gives
;   "tatara" and "TATARA.AS" gives "TATARA", and the spec stores names
;   verbatim either way. The linker compares MODNAME without regard to
;   case for that reason. How SYMBOLS were compared is a separate
;   question, and MODNAME's flags byte is what answers it.
;
; Input:	nothing (srcname)
; Output:	DE -> the name
;		A  = how long it is
; Modifies:	AF, BC, DE, HL

objbase:	ld	a,(lsttitl)	; M80's rule: the module is named by
		or	a		;   NAME, or by the first six
		jr	z,objb.file	;   characters of the title when
		cp	7		;   there is no NAME. NAME itself is
		jr	c,objb.ttl	;   one row of dirtab, whenever it is
		ld	a,6		;   wanted
objb.ttl:	ld	de,lsttitl+1
		ret
objb.file:	ld	hl,srcname
		ld	d,h
		ld	e,l		; the start, until a separator moves
objb.sep:	ld	a,(hl)		;   it along
		or	a
		jr	z,objb.len
		inc	hl
		cp	":"
		jr	z,objb.new
		cp	05ch		; the backslash, by its code: written
		jr	nz,objb.sep	;   as a character it would sit
objb.new:	ld	d,h		;   awkwardly in this file
		ld	e,l
		jr	objb.sep
objb.len:	ld	h,d
		ld	l,e
		ld	c,0
objb.ch:	ld	a,(hl)
		or	a
		jr	z,objb.end
		cp	"."		; the extension is not part of it
		jr	z,objb.end
		inc	hl
		inc	c
		jr	objb.ch
objb.end:	ld	a,c
		ret

		dseg

objon:		defs	1	; 0 = no object file was named, and every
				;   entry point is a single ret
objhand:	defs	1	; MSX-DOS's handle for it
objhdr:		defs	3	; a record header, built to be written
objbyt:		defs	1	; one byte, the same
objit:		defs	5	; a walk over a hash table: the bucket,
				;   then the far pointer htnext keeps
objidx:		defs	1	; the index objseek is looking for, and
				;   the one the next EXTDEF will take
objskp:		defs	1	; objnam: key bytes in front of the name,
objnln:		defs	1	;   the name's length,
objnat:		defs	1	;   and which character it is on
objflg:		defs	1	; a record's flags, out of the mapper
objgrp:		defs	1	;   its group, or a symbol's segment
objsiz:		defs	2	;   and its size, or a symbol's value,
				;   or a DATA record's length
objropn:	defs	1	; 0 = no DATA run is open
objrsg:		defs	1	; the open run's segment, as the FILE
				;   numbers it
objrof:		defs	2	; where it started, within that segment
objrnx:		defs	2	; where its next byte has to go, if the
				;   run is to carry on
objrps:		defs	4	; and where its length field sits in the
				;   file: the low word, then the high one,
				;   the order _SEEK wants them in
objfhd:		defs	4	; the fixup chain's head, which is its
				;   NEWEST block
objfit:		defs	4	; objrels: which block the walk is on
objftm:		defs	4	; objfnew: what halloc answered
objfn:		defs	1	; entries in the head block. It starts at
				;   FIXPER so the first fixup allocates
objfc:		defs	1	; objrels: the block's count,
objfi:		defs	1	;   and which entry it is on
objfx:		defs	6	; ONE ENTRY, in ordinary RAM: the table is
				;   in the mapper and a BDOS call cannot
				;   read it there
objenon:	defs	1	; 0 = END named no address
objens:		defs	1	; its segment, as the FILE numbers it
objenv:		defs	2	;   and its offset
