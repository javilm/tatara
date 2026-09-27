; tanren.as - TANREN, the Tatara linker. The driver.
;
; TWO PASSES OVER THE SAME LIST OF FILES. Pass 1 reads the inventory
; and the names, lays the segments out and gives every symbol an
; address; pass 2 reads the same files again and copies their content
; into the image, patching every word the assembler could not fill in.
; The command tail is the list, walked twice.
;
; THE DUMP IS HERE AND NOT IN lobj.as on purpose. lobj.as knows the
; file's shape; what to do with a record is the driver's business,
; and the tables replace this dump without
; touching the reader.

		include	lcmd.inc	; the command tail and the banner
		include	lobj.inc	; the reader
		include	lseg.inc	; and the tables it fills
		include	lsym.inc	; and the symbols
		include	limg.inc	; and the image they end up in
		include	farptr.inc	; derefp: the image is the first thing
					;   in this module to reach into
					;   the mapper itself
		include	lerrs.inc
		include	msxdos.inc	; dosver, putsz, putdec, dosexit
		include	strutil.inc	; numhex, numhex2
		include	alloc.inc	; heapinit: nothing allocates yet,
					;   but [R11] puts the image in the
					;   mapper and the tables
		include	ascii.inc

LMAXEXT		equ	512	; externals one module may declare.
				; tatara.as declares 182, which is the
				; most anything here has seen. THE MAP IS
				; IN THE MAPPER: 1 KB there costs nothing,
				; and 1 KB of ordinary RAM would be a
				; fifth of everything this program has
LXHIMAX		equ	2	; LMAXEXT / 256: the bound is tested on
				; the high byte, and 512 is 0200h

		cseg

main:		call	dosver		; CY set = not MSX-DOS2
		jp	c,main.dos1
		call	heapinit	; CY set = no mapper support
		jp	c,main.nomap

		call	lcmparse	; CY set = no filename
		push	af
		ld	a,(lopthelp)	; /? and /V answer and stop, with a
		or	a		;   filename or without one
		jp	nz,main.usage
		ld	a,(loptver)
		or	a
		jp	nz,main.ver
		pop	af
		jp	c,main.usage
		call	lcmbann
		call	lcmwarn		; 127 characters is all MSX-DOS
					;   gives, and it cuts a longer
					;   line in silence
		call	lcmodef		; the output file's name, and it
		call	lcmovch		;   may not be one of the inputs

		call	lsginit		; the tables, before the first file
		call	lsyinit
		ld	hl,0
		ld	(nrecs),hl
		call	lcmfrst

main.file:	call	lcmnext		; CY set = every file is read
		jr	c,main.all
		call	lsgmod		; this module's maps, empty
		ld	de,objname
		call	lobopen		; the header, or one of three
					;   errors that do not return

main.loop:	call	lobnext		; CY set = no more records
		jr	c,main.done
		ld	hl,(nrecs)
		inc	hl
		ld	(nrecs),hl
		call	lp1rec		; what pass 1 wants; printed if /D
		call	lobskip		; whatever lp1rec did not read -
					;   and ALL of it for a type we do
					;   not know, which is what the
					;   length field is for
		ld	a,(lobtyp)
		cp	OR_END		; THE MODULE ENDS HERE, and leaving
		jr	nz,main.loop	;   the loop on it is a DECISION: a
					;   library would be several modules
					;   in one file, and this is where
					;   the nesting level would go

main.done:	call	lobend		; CY set = something follows it
		ld	a,0
		adc	a,a
		ld	(trail),a
		call	lobclose
		jr	main.file

main.all:	call	lsglay		; every segment gets an address,
		call	lsyfix		;   and every symbol a final value
		ld	a,(loptmap)	; THE MAP BEFORE THE CHECK, so that
		or	a		;   a link which is about to fail
		push	af		;   still shows what it did find
		call	nz,lsgdump
		pop	af
		call	nz,lsydump
		call	lsychk		; every external nobody defined -
					;   all of them, and then it stops

		call	main.p2		; PASS 2: the content, the fixups
					;   and the file

		ld	a,(loptquiet)	; the summary, unless /Q
		or	a
		jp	nz,dosexit
		ld	a,(lmods)
		ld	l,a
		ld	h,0
		call	putdec
		ld	de,msg_mods2
		call	putsz
		ld	hl,(nrecs)
		call	putdec
		ld	de,msg_recs
		call	putsz
		ld	a,(trail)
		or	a
		ld	de,msg_eof
		jr	z,main.sum
		ld	de,msg_more
main.sum:	call	putsz
		ld	a,(imgany)	; AND WHAT WAS WRITTEN. The entry
		or	a		;   point is here and nowhere else:
		jp	z,main.non	;   MSX-DOS enters a .COM at 0100h
		ld	de,msg_wrote	;   whatever any file says, so this
		call	putsz		;   is the only place a wrong one
		ld	de,outname	;   could ever be seen
		call	putszu
		ld	de,msg_wcomm
		call	putsz
		ld	hl,(imglo)
		call	dmpw
		ld	de,msg_wdash
		call	putsz
		ld	hl,(imghi)
		call	dmpw
		ld	de,msg_wpar
		call	putsz
		ld	hl,(imghi)	; both ends are in the file
		ld	de,(imglo)
		or	a
		sbc	hl,de
		inc	hl
		call	putdec
		ld	de,msg_wbyte
		call	putsz
		ld	a,(loptbin)	; WORTH SAYING: the span above is
		or	a		;   the IMAGE's, and with /B the
		jr	z,main.went	;   file is seven bytes bigger
		ld	de,msg_wbld
		call	putsz
main.went:	ld	a,(lentgot)
		or	a
		jr	z,main.wcr
		ld	de,msg_wentr
		call	putsz
		ld	hl,(lentadr)
		call	dmpw
main.wcr:	ld	de,msg_wdot
		call	putsz
		jp	dosexit
main.non:	ld	de,msg_wnone
		call	putsz
		jp	dosexit

main.usage:	jp	lcmusage
main.ver:	call	lcmver
		jp	dosexit

main.dos1:	ld	de,msg_ldos1
		system	_STROUT
		jp	dosexit
main.nomap:	ld	de,msg_lnomp
		system	_STROUT
		jp	dosexit

; main.p2 - pass 2: every module again, and this time its content.
;
;   THE COMMAND TAIL IS WALKED A SECOND TIME, in the same order. That
;   is what lets the table get away with storing no per-module base:
;   lsgrst puts every segment's total back to zero and pass 2's SEGDEF
;   arm accumulates it again, so the total standing when a module's
;   SEGDEF arrives is that module's base - the same arithmetic that
;   produced it the first time.
;
;   Every object file is opened, read and closed again. Its header is
;   checked a second time, which costs one read and means a file
;   replaced between the passes is caught rather than half-copied.
;
; Input:	every segment placed, every symbol final
; Output:	the image is built and written
; Modifies:	everything

main.p2:	call	imginit
		ld	bc,LMAXEXT*2	; the externals' values, in the
		ld	hl,lxmap	;   mapper
		call	halloc
		jp	c,errlheap
		call	lsgrst		; every total back to zero
		xor	a
		ld	(lentgot),a
		call	lcmfrst
p2.file:	call	lcmnext
		jr	c,p2.all
		call	lsgmod		; this module's maps, empty again
		ld	hl,0
		ld	(lxn),hl	; and it has declared no externals
		ld	de,objname
		call	lobopen
p2.loop:	call	lobnext
		jr	c,p2.done
		call	lp2rec
		call	lobskip		; whatever lp2rec did not read
		ld	a,(lobtyp)
		cp	OR_END
		jr	nz,p2.loop
p2.done:	call	lobclose
		jr	p2.file
p2.all:		ld	a,(loptbin)	; /B's header ALWAYS carries an
		or	a		;   execution address, and BSAVE's
		jr	z,p2.wr		;   own rule is that it is the
		ld	a,(lentgot)	;   START address when nothing
		or	a		;   named one. Settling it here
		jr	nz,p2.wr	;   means the summary line says
		ld	hl,(imglo)	;   what actually went into the
		ld	(lentadr),hl	;   header
		ld	a,0ffh
		ld	(lentgot),a
p2.wr:		ld	hl,(lentadr)
		ld	a,(loptbin)
		ld	de,outname
		jp	imgsave		; CY set = there was nothing to
					;   write, which imgany also says
					;   and the summary reads

; lp2rec - what pass 2 does with a record.
;
;   PUBDEF IS THE ONE RECORD IT DELIBERATELY DOES NOT READ. Pass 1
;   read it and every symbol already has its final value; reading it
;   again would report every public in the link as defined twice. The
;   absent arm is a decision and not an oversight, which is why this
;   comment exists.
;
;   MODNAME, GRPDEF and SEGDEF are read again so that this module's
;   group and segment indices mean something; EXTDEF so that its
;   external indices do; DATA and RELOC are the point of the pass.
;
; Input:	a record is open
; Output:	the image knows about it
; Modifies:	everything

lp2rec:		ld	a,(lobtyp)
		cp	OR_MOD
		jp	z,lp2.mod
		cp	OR_GRP
		jp	z,lp2.grp
		cp	OR_SEG
		jp	z,lp2.seg
		cp	OR_EXT
		jp	z,lp2.ext
		cp	OR_DATA
		jp	z,lp2.dat
		cp	OR_RELOC
		jp	z,lp2.rel
		cp	OR_ENT
		jp	z,lp2.ent
		ret			; PUBDEF, COMMENT, END, and any
					;   type this program does not know

lp2.mod:	ld	de,lobsln1	; the flags byte, unused here, and
		ld	a,1		;   the name, for the messages that
		call	lobpay		;   name a module
		call	lobstr
		jp	lsymod

lp2.grp:	call	lobstr
		jp	lsgrp

lp2.seg:	ld	de,lsfld	; flags, group, size
		ld	a,4
		call	lobpay
		call	lobstr
		jp	lsgseg

lp2.ext:	ld	hl,(lobleft)	; EXTDEF repeats until its length is
		ld	a,h		;   used up, and every name takes the
		or	l		;   next external index
		ret	z
		call	lobstr
		call	lsyval		; -> what it came to
		call	lxput
		jr	lp2.ext

; lp2.dat - a DATA record: its content, into the image.
;
; Input:	a DATA record is open
; Output:	its bytes are in the image
; Modifies:	everything

lp2.dat:	ld	de,lp2fld	; segment and offset
		ld	a,3
		call	lobpay
		ld	a,(lp2fld)
		ld	hl,(lp2fld+1)
		call	lp2addr
		ld	(lp2a),hl
lp2d.lp:	ld	hl,(lobleft)
		ld	a,h
		or	l
		ret	z
		ld	a,h		; 255 at a time: lobpay counts in a
		or	a		;   byte
		ld	a,0ffh
		jr	nz,lp2d.n	; ld does not touch the flags
		ld	a,l
lp2d.n:		ld	(lp2n),a
		ld	de,lobbuf	; THE NAME BUFFER: a DATA record has
		call	lobpay		;   no string in it, so it is free
		ld	a,(lp2n)
		ld	c,a
		ld	b,0
		ld	de,lobbuf
		ld	hl,(lp2a)
		call	imgwr
		ld	a,(lp2n)	; and on by that much
		ld	c,a
		ld	b,0
		ld	hl,(lp2a)
		add	hl,bc
		ld	(lp2a),hl
		jp	lp2d.lp

; lp2.rel - a RELOC record: every fixup in it, applied.
;
;   THE STORED WORD IS AN ADDEND, not a placeholder (spec 4): what
;   goes back is what was there plus the base or the value. An
;   external used with no addend stores 0000h, and adding to it is the
;   same operation.
;
; Input:	a RELOC record is open
; Output:	the image is patched
; Modifies:	everything

lp2.rel:	ld	hl,(lobleft)	; six bytes an entry; fewer than six
		ld	de,6		;   left is a malformed record, and
		or	a		;   lobskip has the rest
		sbc	hl,de
		ret	c
		ld	de,lp2fld
		ld	a,6
		call	lobpay
		ld	a,(lp2fld+1)	; WHERE THE WORD SITS: the segment
		ld	hl,(lp2fld+2)	;   holding it, and the offset
		call	lp2addr		;   within this module's part of it
		ld	(lp2w),hl
		ld	a,(lp2fld)
		cp	1
		jr	z,lp2r.ext
		or	a
		jp	nz,errltrn	; a kind this linker does not know
		ld	a,(lp2fld+4)	; kind 00: the TARGET segment's
		cp	0ffh		;   base, and this module's base in
		jr	z,lp2r.zero	;   it - the addend is an offset
		ld	hl,0		;   into the contribution, exactly
		call	lp2addr		;   as a PUBDEF's is
		jr	lp2r.add
lp2r.zero:	ld	hl,0		; an absolute target: nothing to add
		jr	lp2r.add
lp2r.ext:	ld	hl,(lp2fld+4)	; kind 01: the resolved external
		call	lxget
lp2r.add:	ld	(lp2v),hl
		ld	hl,(lp2w)	; the addend, out of the image, low
		call	imgget		;   byte first
		ld	(lp2s),a
		ld	hl,(lp2w)
		inc	hl
		call	imgget
		ld	(lp2s+1),a
		ld	hl,(lp2s)
		ld	de,(lp2v)
		add	hl,de
		ld	(lp2s),hl
		ld	a,(lp2s)	; and back it goes
		ld	hl,(lp2w)
		call	imgput
		ld	a,(lp2s+1)
		ld	hl,(lp2w)
		inc	hl
		call	imgput
		jp	lp2.rel

; lp2.ent - an ENTRY record: the first one in the link wins.
;
; Input:	an ENTRY record is open
; Output:	lentadr, lentgot
; Modifies:	everything

lp2.ent:	ld	de,lp2fld
		ld	a,3
		call	lobpay
		ld	a,(lentgot)
		or	a
		ret	nz		; somebody named one already
		ld	a,(lp2fld)
		ld	hl,(lp2fld+1)
		call	lp2addr
		ld	(lentadr),hl
		ld	a,0ffh
		ld	(lentgot),a
		ret

; lp2addr - a segment index and an offset, as an address.
;
;   SEGMENT FFh IS AN ADDRESS ALREADY (spec 10), which is decision 8's
;   answer: absolute content is written where it says, and the linker
;   does not judge where that is.
;
;   Everything else is an offset into THIS MODULE'S CONTRIBUTION, so
;   the segment's base and the module's base within it are both added.
;   lsypub does the same arithmetic to a public's value, and for the
;   same reason.
;
; Input:	A  = the segment index
;		HL = the offset
; Output:	HL = the address
; Modifies:	AF, BC, DE, HL

lp2addr:	cp	0ffh
		ret	z		; absolute: the offset IS the
		ld	(lp2o),hl	;   address
		call	lsgsm		; -> lsgbase, lsgbas
		ld	hl,(lp2o)
		ld	de,(lsgbase)
		add	hl,de
		ld	de,(lsgbas)
		add	hl,de
		ret

; lxput - the next external's resolved value.
;
; Input:	HL = the value
; Output:	the map holds it, lxn is one higher
;		(errlmext does not return)
; Modifies:	AF, BC, DE, HL

lxput:		ld	a,(lxn+1)
		cp	LXHIMAX
		jp	nc,errlmext
		ld	(lxval),hl
		ld	hl,(lxn)
		add	hl,hl		; two bytes each
		ld	c,l
		ld	b,h
		derefp	lxmap		; BC survives it
		add	hl,bc
		ld	de,(lxval)	; AFTER the deref: it destroys DE
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	hl,(lxn)
		inc	hl
		ld	(lxn),hl
		ret

; lxget - the value of external index HL.
;
; Input:	HL = the index
; Output:	HL = its value
;		(errltrn does not return)
; Modifies:	AF, BC, DE, HL

lxget:		ld	de,(lxn)	; an index this module never
		or	a		;   declared can only come from a
		sbc	hl,de		;   broken file
		jp	nc,errltrn
		add	hl,de		; back to the index
		add	hl,hl
		ld	c,l
		ld	b,h
		derefp	lxmap
		add	hl,bc
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl
		ret

; dmprec - one record, decoded as far as its type is known.
;
;   Each arm reads the fields it understands and leaves the rest to
;   main.loop's lobskip. An unknown type reads nothing at all, which
;   is exactly the behaviour spec 5 promises and the reason the
;   length is in the file.
;
; Input:	lobtyp, lobleft
; Output:	one or more lines
; Modifies:	everything

; lp1rec - what pass 1 does with a record.
;
;   ONE ROUTINE READS IT. A record's fields can be read once, and
;   GRPDEF and SEGDEF have to be read whether or not /D was given -
;   so those two are here, and printing is a VIEW of what they read.
;   Everything else is still only read in order to be printed.
;
; Input:	a record is open
; Output:	the tables know about it; it is printed if /D
; Modifies:	everything

lp1rec:		ld	a,(lobtyp)
		cp	OR_MOD
		jr	z,lp1.mod
		cp	OR_GRP
		jp	z,lp1.grp	; jp, NOT jr: three arms in
		cp	OR_SEG		;   front of these two and pushed
		jp	z,lp1.seg	;   both past 127 bytes
		cp	OR_PUB
		jp	z,lp1.pub
		cp	OR_EXT
		jp	z,lp1.ext
		ld	a,(loptdump)	; a type pass 1 does not want:
		or	a		;   dmprec if it is to be seen,
		ret	z		;   and lobskip has it otherwise
		jp	dmprec

lp1.mod:	ld	de,lobsln1	; the flags byte: WHICH CASE MODE
		ld	a,1		;   this module was assembled in
		call	lobpay
		call	lobstr		; and its name
		call	lsymod		; kept, for the messages that name
					;   a module
		ld	a,(lobsln1)
		call	lsycase		; the mode on the first module, the
					;   mixture check on the rest
		ld	a,(loptdump)
		or	a
		ret	z
		ld	de,msg_mod
		call	putsz
		ld	a,(lobsln1)
		call	dmpb
		call	dmpsp
		ld	de,lobbuf
		call	putsz
		jp	dmp.crlf

lp1.pub:	ld	hl,(lobleft)	; PUBDEF REPEATS until its length
		ld	a,h		;   is used up
		or	l
		ret	z
		ld	de,lsfld2	; segment, offset
		ld	a,3
		call	lobpay
		call	lobstr		; and the name
		call	lsypub
		ld	a,(loptdump)
		or	a
		jr	z,lp1.pub
		ld	de,msg_pub
		call	putsz
		ld	a,(lsfld2)
		call	dmpb
		ld	de,msg_offw
		call	putsz
		ld	hl,(lsfld2+1)
		call	dmpw
		call	dmpsp
		ld	de,lobbuf
		call	putsz
		call	dmp.crlf
		jr	lp1.pub

lp1.ext:	ld	hl,(lobleft)	; EXTDEF repeats too
		ld	a,h
		or	l
		ret	z
		call	lobstr
		call	lsyext
		ld	a,(loptdump)
		or	a
		jr	z,lp1.ext
		ld	de,msg_ext
		call	putsz
		ld	de,lobbuf
		call	putsz
		call	dmp.crlf
		jr	lp1.ext

lp1.grp:	call	lobstr		; the name, into lobbuf
		call	lsgrp
		ld	a,(loptdump)
		or	a
		ret	z
		ld	de,msg_grpr
		call	putsz
		ld	de,lobbuf
		call	putsz
		jp	dmp.crlf

lp1.seg:	ld	de,lsfld	; flags, group, size
		ld	a,4
		call	lobpay
		call	lobstr		; and the name
		call	lsgseg
		ld	a,(loptdump)
		or	a
		ret	z
		ld	de,msg_segr
		call	putsz
		ld	a,(lsfld)
		call	dmpb
		ld	de,msg_grpw
		call	putsz
		ld	a,(lsfld+1)
		call	dmpb
		ld	de,msg_sizw
		call	putsz
		ld	hl,(lsfld+2)
		call	dmpw
		call	dmpsp
		ld	de,lobbuf
		call	putsz
		jp	dmp.crlf

dmprec:		ld	a,(lobtyp)
		cp	OR_DATA
		jp	z,dmp.dat
		cp	OR_RELOC
		jp	z,dmp.rel
		cp	OR_ENT
		jp	z,dmp.ent
		cp	OR_END
		jp	z,dmp.end
		ld	de,msg_unkn	; a type this program does not know
		call	putsz
		ld	a,(lobtyp)
		call	dmpb
		jr	dmp.crlf

dmp.crlf:	ld	de,msg_lcrlf
		jp	putsz

; PUBDEF and EXTDEF hold as many entries as their length allows, so
; both loop on lobleft and print a line each.

; DATA prints its header and THE FIRST EIGHT BYTES. All of them would
; be six thousand bytes of hex for tatara.tro, and the header is what
; a reader of this dump is checking.

dmp.dat:	ld	de,msg_dat
		call	putsz
		ld	de,dmpfld	; segment, offset
		ld	a,3
		call	lobpay
		ld	a,(dmpfld)
		call	dmpb
		ld	de,msg_offw
		call	putsz
		ld	hl,(dmpfld+1)
		call	dmpw
		ld	de,msg_lenw
		call	putsz
		ld	hl,(lobleft)	; WHAT IS LEFT IS THE CONTENT: the
		call	dmpw		;   payload was segment, offset and
		call	dmpsp		;   this, which is why the content
					;   is length-3 and not length-5
		ld	hl,(lobleft)
		ld	a,h
		or	a
		jr	nz,dmp.d8	; more than 255: eight of them
		ld	a,l
		cp	9
		jr	c,dmp.dn	; fewer than eight: all of them
dmp.d8:		ld	a,8
dmp.dn:		or	a
		jp	z,dmp.crlf	; a run of no bytes at all
		ld	(dmpn),a
dmp.dlp:	ld	de,dmpone
		ld	a,1
		call	lobpay
		ld	a,(dmpone)
		call	dmpb
		call	dmpsp
		ld	hl,dmpn
		dec	(hl)
		jr	nz,dmp.dlp
		jp	dmp.crlf

; RELOC prints how many fixups it holds. Six bytes an entry, and the
; division is a subtraction loop because six is not a power of two -
; a table of fixups is tens of entries, not thousands.

dmp.rel:	ld	de,msg_rel
		call	putsz
		ld	hl,(lobleft)
		ld	de,6
		ld	c,0
dmp.rlp:	ld	a,h
		or	l
		jr	z,dmp.rn
		or	a
		sbc	hl,de
		jr	c,dmp.rn	; not a multiple of six: the record
		inc	c		;   is malformed, but do not spin
		jr	dmp.rlp
dmp.rn:		ld	l,c
		ld	h,0
		call	putdec
		ld	de,msg_fixw
		call	putsz
		jp	dmp.crlf

dmp.ent:	ld	de,msg_ent
		call	putsz
		ld	de,dmpfld	; segment, offset
		ld	a,3
		call	lobpay
		ld	a,(dmpfld)
		call	dmpb
		ld	de,msg_offw
		call	putsz
		ld	hl,(dmpfld+1)
		call	dmpw
		jp	dmp.crlf

dmp.end:	ld	de,msg_end
		call	putsz
		jp	dmp.crlf
; dmpstr - the next string field, printed.
;
; Input:	a record is open and the next field is a string
; Output:	the name is printed
; Modifies:	everything

dmpstr:		call	lobstr
		ld	de,lobbuf
		jp	putsz

; dmpb, dmpw - a byte and a word, in hex, and one space.
;
; Input:	A, or HL
; Output:	two or four digits
; Modifies:	everything

dmpb:		ld	de,dmphex
		call	numhex2
		ld	de,dmphex
		ld	hl,dmphex+2
		ld	(hl),0
		jp	putsz

dmpw:		ld	de,dmphex
		call	numhex
		ld	hl,dmphex+4
		ld	(hl),0
		ld	de,dmphex
		jp	putsz

dmpsp:		ld	de,msg_lsp
		jp	putsz

		dseg

nrecs:		defs	2	; how many records have been read
lxmap:		defs	4	; PASS 2: every external this module
				;   declared, by index, and what it came
				;   to. A word each, IN THE MAPPER
lxn:		defs	2	; how many it has declared so far
lxval:		defs	2	; one value, across a deref
lp2fld:		defs	6	; the fixed fields of the record being
				;   read: DATA's and ENTRY's three, and
				;   RELOC's six
lp2a:		defs	2	; lp2.dat: where this run is going
lp2n:		defs	1	;   and how much of it comes next
lp2o:		defs	2	; lp2addr: the offset, across lsgsm
lp2w:		defs	2	; lp2.rel: the word being patched,
lp2v:		defs	2	;   what is being added to it, and
lp2s:		defs	2	;   the word itself
lentgot:	defs	1	; 0FFh once some module has named an
lentadr:	defs	2	;   entry point, and what it came to
trail:		defs	1	; non-zero = bytes follow the last one
lobsln1:	defs	1	; a one-byte field, before it is printed
dmpfld:		defs	4	; the fixed fields of the record being
				;   dumped: the longest is SEGDEF's four
dmpone:		defs	1	; one DATA byte, on its way to the screen
dmpn:		defs	1	;   and how many are still to come
dmphex:		defs	5	; numhex's answer, zero-terminated

msg_recs:	defb	" records, ",0
msg_wrote:	defb	"Wrote ",0
msg_wcomm:	defb	", ",0
msg_wdash:	defb	"-",0
msg_wpar:	defb	" (",0
msg_wbyte:	defb	" bytes)",0
msg_wbld:	defb	", BLOAD header",0
msg_wentr:	defb	", entry ",0
msg_wdot:	defb	".",CHR_CR,CHR_LF,0
msg_wnone:	defb	"Nothing to write: no module has any"
		defb	" content.",CHR_CR,CHR_LF,0
msg_eof:	defb	"ends at EOF.",CHR_CR,CHR_LF,0
msg_more:	defb	"AND BYTES AFTER THEM.",CHR_CR,CHR_LF,0
msg_lcrlf:	defb	CHR_CR,CHR_LF,0
msg_lsp:	defb	" ",0
msg_mod:	defb	"MODNAME  flags ",0
msg_grpr:	defb	"GRPDEF   ",0
msg_segr:	defb	"SEGDEF   flags ",0
msg_mods2:	defb	" modules, ",0
msg_pub:	defb	"PUBDEF   seg ",0
msg_ext:	defb	"EXTDEF   ",0
msg_dat:	defb	"DATA     seg ",0
msg_rel:	defb	"RELOC    ",0
msg_ent:	defb	"ENTRY    seg ",0
msg_end:	defb	"END",0
msg_grpw:	defb	" group ",0
msg_sizw:	defb	" size ",0
msg_offw:	defb	" offset ",0
msg_lenw:	defb	" len ",0
msg_fixw:	defb	" fixups",0
msg_unkn:	defb	"(unknown record type ",0
msg_ldos1:	defb	"ERROR: Tanren needs MSX-DOS2 or Nextor."
		defb	CHR_CR,CHR_LF,"$"
msg_lnomp:	defb	"ERROR: Tanren needs a memory mapper.",CHR_CR
		defb	CHR_LF,"$"
