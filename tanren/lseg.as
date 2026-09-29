; lseg.as - the link's groups and segments.
;
; Two hash tables in ordinary RAM with their records in the mapper,
; which is what symtab.as does and for the same reasons. A segment's
; key is its GROUP and its NAME, exactly as the assembler keys
; segtab: two groups of one transient DSEG are then two records
; without a special case, which is what [R4] needs when the layout
; overlays them.
;
; THE TOTAL IS ALL THIS TABLE HOLDS. A module's base within the
; combined segment is not stored, because pass 2 reads the modules in
; the same order and a running fill level reproduces every base for
; nothing.

LSEGLIB		equ	1	; skips the externals in lseg.inc

		public	lsginit
		public	lsgmod
		public	lsgrp
		public	lsgseg
		public	lsgdump
		public	lsgcase
		public	lsglay
		public	lsgrst
		public	lsgend
		public	lsgbase
		public	lsgsm
		public	lsgptr
		public	lsgbas
		public	lsgnam
		public	lsnamp
		public	lsskp
		public	lsfld
		public	lmods

		include	lseg.inc
		include	lobj.inc	; lobbuf, lobsln
		include	lerrs.inc	; errlmseg, errlsflg, errlovlp
		include	lcmd.inc	; /P: and /D:, which are the only
					;   things outside this module that
					;   decide where anything goes
		include	hash.inc
		include	alloc.inc	; derefp
		include	farptr.inc
		include	msxdos.inc	; putsz, putdec
		include	strutil.inc	; numhex, numhex2
		include	ascii.inc

		cseg

; lsginit - both tables, empty. ONCE, before the first file.
;
; Input:	nothing
; Output:	the tables are ready
; Modifies:	AF, BC, DE, HL, IX

lsginit:	ld	a,HTCASEI	; the DEFAULT, which stands until
		call	lsgcase		;   the first MODNAME says what the
		xor	a		;   modules were assembled with
		ld	(lsnum),a
		ld	(lgnum),a
		ld	(lmods),a
		ret

; lsgcase - the two tables' case mode.
;
;   SEPARATE BECAUSE IT IS DECIDED LATE. The mode comes from the
;   first module's MODNAME flags byte, which is read after lsginit
;   has run - so the tables are formatted twice, once with the
;   default and once for real. The second time costs nothing: no
;   record has been added yet, and htinit only empties buckets.
;
; Input:	A = HTCASES or HTCASEI
; Output:	both tables are empty and in that mode
; Modifies:	AF, BC, DE, HL, IX

lsgcase:	ld	(lscas),a	; KEPT: lsgsame folds as it compares
		push	af		;   when the link is insensitive
		ld	ix,lsegtab
		ld	b,LSGBKTS-1
		call	htinit
		pop	af
		ld	ix,lgrptab
		ld	b,LSGBKTS-1
		call	htinit
		ret

; lsgmod - a module is starting.
;
; Input:	nothing
; Output:	its maps are empty, lmods is one higher
; Modifies:	AF, HL

lsgmod:		xor	a
		ld	(lsmn),a
		ld	(lgmn),a
		ld	hl,lmods
		inc	(hl)
		ret

; lsgrp - a GRPDEF record.
;
;   The name is in lobbuf, where lobstr left it. A group seen in two
;   modules is one group, so the table is asked first.
;
; Input:	lobbuf, lobsln
; Output:	lgmap gains this module's next group index
;		(errlmseg does not return)
; Modifies:	AF, BC, DE, HL, IX

lsgrp:		ld	a,(lgmn)
		cp	LMAXGRP
		jp	nc,errlmseg
		ld	ix,lgrptab
		ld	de,lobbuf
		ld	a,(lobsln)
		ld	hl,lspay
		call	htfind
		jr	nc,lsgr.have
		ld	ix,lgrptab	; a group nobody has named yet
		ld	de,lobbuf
		ld	a,(lobsln)
		ld	bc,1		; its payload is its global id
		ld	hl,lspay
		call	htadd
		jp	c,errlheap
		derefp	lspay
		ld	a,(lgnum)	; the id this group takes
		ld	(hl),a
		ld	hl,lgnum
		inc	(hl)
		ld	a,(hl)
		dec	a		; back to the id just handed out
		jr	lsgr.put
lsgr.have:	derefp	lspay
		ld	a,(hl)
lsgr.put:	ld	hl,lgmap	; lgmap[lgmn] = that id
		ld	e,a
		ld	a,(lgmn)
		ld	c,a
		ld	b,0
		add	hl,bc
		ld	(hl),e
		ld	hl,lgmn
		inc	(hl)
		ret

; lsgseg - a SEGDEF record.
;
;   FIND BEFORE ADD, ALWAYS. htadd does not check for duplicates and
;   says so; a second CODE added blindly would make two records of
;   that name with half the size each, and nothing would notice until
;   the image came out wrong.
;
; Input:	lsfld = flags, group index, size; lobbuf, lobsln
; Output:	the table holds it and lsmap points at it
;		(errlmseg, errlsflg do not return)
; Modifies:	AF, BC, DE, HL, IX

lsgseg:		ld	a,(lsmn)
		cp	LMAXSEG
		jp	nc,errlmseg
		call	lsgkey		; the key: a group byte and the name
		ld	ix,lsegtab
		ld	de,lskey
		ld	a,(lskln)
		ld	hl,lspay
		call	htfind
		jr	nc,lsgs.have
		ld	ix,lsegtab	; a segment nobody has named yet
		ld	de,lskey
		ld	a,(lskln)
		ld	bc,SGPAY	; flags, size, base, placed
		ld	hl,lspay
		call	htadd
		jp	c,errlheap
		derefp	lspay
		ld	a,(lsfld)
		ld	(hl),a		; its flags, as the FILE wrote them
		inc	hl
		ld	(hl),0		; and nothing in it yet
		inc	hl
		ld	(hl),0
		inc	hl
		ld	(hl),0		; no base
		inc	hl
		ld	(hl),0
		inc	hl
		ld	(hl),0		; and not placed
		ld	hl,lsnum
		inc	(hl)
		jr	lsgs.add
lsgs.have:	derefp	lspay
		ld	a,(lsfld)	; THE SAME SEGMENT MUST BE THE SAME
		cp	(hl)		;   KIND of segment in every module
		jp	nz,errlsflg
lsgs.add:	derefp	lspay		; the running total, out of the
		inc	hl		;   mapper
		ld	c,(hl)
		inc	hl
		ld	b,(hl)		; IN BC, NOT DE: deref DESTROYS DE
		ld	(lsgbas),bc	;   and keeps BC, and its comment
					;   says so. AND THE TOTAL SO FAR IS
					;   THIS MODULE'S BASE in the
					;   combined segment - it is stored
					;   beside the pointer, and a PUBDEF
					;   adds it to every offset
		ld	hl,(lsfld+2)
		add	hl,bc
		ld	b,h
		ld	c,l
		derefp	lspay
		inc	hl
		ld	(hl),c
		inc	hl
		ld	(hl),b

		ld	a,(lsmn)	; lsmap[lsmn]: the record, and then
		call	lsgoff		;   this module's base in it
		ld	de,lsmap
		add	hl,de
		ex	de,hl
		ld	hl,lspay
		ld	bc,4
		ldir
		ld	hl,lsgbas	; DE is already past the pointer
		ld	bc,2
		ldir
		ld	hl,lsmn
		inc	(hl)
		ret

; lsgoff - where entry A sits inside lsmap. Six bytes each: four of
;   far pointer and two of base. objfoff does the same arithmetic for
;   the same reason - six is not a shift.
;
; Input:	A = which entry
; Output:	HL = A * 6
; Modifies:	AF, DE, HL

lsgoff:		ld	l,a
		ld	h,0
		ld	e,l
		ld	d,h
		add	hl,hl		; *2
		add	hl,de		; *3
		add	hl,hl		; *6
		ret

; lsgsm - this module's segment index N: its record, and its base.
;
; Input:	A = the index the FILE used
; Output:	lsgptr = the record's payload far pointer
;		lsgbas = this module's base within that segment
;		(errltrn does not return: an index this module never
;		declared can only come from a broken file)
; Modifies:	AF, BC, DE, HL

lsgsm:		ld	hl,lsmn
		cp	(hl)
		jp	nc,errltrn
		call	lsgoff
		ld	de,lsmap
		add	hl,de
		ld	de,lsgptr
		ld	bc,4
		ldir
		ld	de,lsgbas
		ld	bc,2
		ldir
		derefp	lsgptr		; AND THE SEGMENT'S OWN BASE, which
		ld	de,SGP_BAS	;   lsyfix adds to every symbol
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(lsgbase),de
		ret

; lsgkey - the key a segment is stored under: one byte of group, then
;   the name.
;
; Input:	lsfld+1 = the module's group index, lobbuf, lobsln
; Output:	lskey, lskln
; Modifies:	AF, BC, DE, HL

lsgkey:		ld	a,(lsfld+1)
		cp	0ffh
		jr	z,lsgk.non	; no group: FFh is the key's byte
		ld	c,a		; otherwise the GLOBAL id, which is
		ld	b,0		;   what makes two modules' groups
		ld	hl,lgmap	;   one group
		add	hl,bc
		ld	a,(hl)
lsgk.non:	ld	(lskey),a
		ld	hl,lobbuf
		ld	de,lskey+1
		ld	a,(lobsln)
		ld	c,a
		ld	b,0
		ldir
		ld	a,(lobsln)
		inc	a		; the group byte counts
		ld	(lskln),a
		ret

; lsgdump - /M: what the reading found.
;
;   THE PAGE 2 RULE, per record: everything is read into ordinary RAM
;   before anything is printed, because printing hands page 2 back to
;   MSX-DOS and the records are in the mapper. symdump and objnam met
;   this first.
;
; Input:	nothing
; Output:	the tables are printed
; Modifies:	everything

lsgdump:	ld	de,msg_mods
		call	putsz
		ld	a,(lmods)
		ld	l,a
		ld	h,0
		call	putdec
		call	lsgcrlf

		ld	de,msg_grps
		call	putsz
		xor	a		; A GROUP'S KEY IS ITS NAME, with
		ld	(lsskp),a	;   nothing in front of it
		call	lsgfrst
lsgd.g:		ld	ix,lgrptab
		ld	hl,lsit
		call	htnext
		jr	c,lsgd.s
		ld	de,msg_ind
		call	putsz
		call	lsgnp
		call	lsgnam
		call	lsgcrlf
		jr	lsgd.g

lsgd.s:		ld	de,msg_segs
		call	putsz
		ld	a,1		; a segment's key has its group byte
		ld	(lsskp),a	;   in front of the name
		call	lsgfrst
lsgd.sl:	ld	ix,lsegtab
		ld	hl,lsit
		call	htnext
		ret	c
		call	lsgpay		; flags, group, total - all three
		ld	de,msg_ind	;   into RAM before a word is
		call	putsz		;   printed
		ld	de,msg_flg
		call	putsz
		ld	a,(lsdfl)
		call	lsgb
		ld	de,msg_grp
		call	putsz
		ld	a,(lsdgr)
		call	lsgb
		ld	de,msg_bas
		call	putsz
		ld	hl,(lsdbs)
		call	lsgw
		ld	de,msg_siz
		call	putsz
		ld	hl,(lsdsz)
		call	lsgw
		ld	de,msg_end
		call	putsz
		ld	hl,(lsdsz)	; the LAST byte, which a segment of
		ld	a,h		;   no bytes does not have
		or	l
		jr	z,lsgd.nosz
		dec	hl
		ld	de,(lsdbs)
		add	hl,de
		call	lsgw
		jr	lsgd.sp
lsgd.nosz:	ld	de,msg_noend
		call	putsz
lsgd.sp:	ld	de,msg_sp
		call	putsz
		call	lsgnp
		call	lsgnam
		call	lsgcrlf
		jp	lsgd.sl		; jp: the extra columns pushed this
					;   loop past a jr's reach

; lsgpay - the record lsit is on: its group byte and its payload, into
;   ordinary RAM.
;
; Input:	lsit is on a segment record
; Output:	lsdgr, lsdfl, lsdsz
; Modifies:	AF, BC, DE, HL

lsgpay:		derefp	lsit+1
		ld	de,HT_KEY
		add	hl,de
		ld	a,(hl)		; the key's first byte is the group
		ld	(lsdgr),a
		derefp	lsit+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)		; payload = HTHDR + the key, and the
		ld	c,a		;   key's length goes IN BC across
		ld	b,0		;   the deref below for the same
		derefp	lsit+1		;   reason
		add	hl,bc
		ld	bc,HTHDR
		add	hl,bc
		ld	a,(hl)
		ld	(lsdfl),a
		inc	hl
		ld	a,(hl)
		ld	(lsdsz),a
		inc	hl
		ld	a,(hl)
		ld	(lsdsz+1),a
		inc	hl
		ld	a,(hl)
		ld	(lsdbs),a
		inc	hl
		ld	a,(hl)
		ld	(lsdbs+1),a
		inc	hl
		ld	a,(hl)
		ld	(lsdset),a
		ret

; lsglay - every segment gets an address.
;
;   CODE FIRST, THEN DATA, because bit 0 of the flags byte is that
;   distinction and a .COM is contiguous from one address.
;
;   AND SAME-NAMED SEGMENTS OVERLAY. A group says its members
;   coexist; two groups of one segment say they do not, so every
;   record sharing a NAME gets the same base and the image gives up
;   the LARGEST of them. That is [R4], and the table was keyed by
;   group-and-name so that this walk would have something to find.
;
; Input:	nothing (the table, full)
; Output:	every record has a base, lsgend is the end
;		(errlbig does not return)
; Modifies:	everything

lsglay:		ld	hl,ORGCOM	; /P: moves it. [R11] wanted the
		ld	a,(loptorg)	;   image out of the TPA, and an
		or	a		;   image out of the TPA is only
		jr	z,lsgl.org	;   useful if it can be told where
		ld	hl,(lorgadr)	;   to load
lsgl.org:	ld	(lsgnext),hl
		ld	(lsgcst),hl	; where the code began, for lsgovl
		xor	a
		ld	(lslkind),a	; code first
lsgl.kind:	call	lsgfrst
lsgl.lp:	ld	ix,lsegtab
		ld	hl,lsit
		call	htnext
		jr	c,lsgl.kdone
		call	lsgpay		; flags, size, base, placed
		ld	a,(lsdset)
		or	a
		jr	nz,lsgl.lp	; another record of its name placed
					;   it already
		ld	a,(lsdfl)	; is it this pass's kind?
		and	1
		ld	hl,lslkind
		cp	(hl)
		jr	nz,lsgl.lp
		call	lsgkeep		; its name, into lslnam
		call	lsgmax		; -> HL = the largest of that name
		push	hl
		ld	hl,(lsgnext)
		call	lsgset		; that base, to every one of them
		pop	de
		ld	hl,(lsgnext)	; and the image gives up the largest
		add	hl,de
		jp	c,errlbig	; past FFFFh: it would wrap. A jp,
					;   because errlbig is EXTERNAL and a
					;   relative jump cannot reach what
					;   the assembler cannot measure
		ld	(lsgnext),hl
		jr	lsgl.lp
lsgl.kdone:	ld	hl,lslkind
		inc	(hl)
		ld	a,(hl)
		cp	2
		jr	nc,lsgl.done
		ld	hl,(lsgnext)	; the code is placed, and this is
		ld	(lsgced),hl	;   where it ended
		ld	a,(loptdat)	; /D: GIVEN? THE DATA STARTS THERE
		or	a		;   instead of carrying on from the
		jp	z,lsgl.kind	;   code, which is all this note
		ld	hl,(ldatadr)	;   does to the walk
		ld	(lsgnext),hl
		ld	(lsgdst),hl
		jp	lsgl.kind
lsgl.done:	ld	hl,(lsgnext)
		ld	(lsgend),hl
		jp	lsgovl

; lsgovl - /D: may have put the data on top of the code.
;
;   TWO SUBTRACTIONS. The spans overlap when the data starts before
;   the code ends AND the code starts before the data ends, which is
;   an OVERLAP and not an ORDERING: data below code is a real MSX
;   layout - /P:C000 /D:8000 puts the code in the top page and its
;   variables under it - and refusing that would be refusing the
;   arrangement the option exists for.
;
;   An empty kind cannot be sat on, and the two guards are there
;   because an empty span passes an overlap test that means nothing.
;
; Input:	lsgcst, lsgced, lsgdst, lsgend, loptdat
; Output:	nothing (errlovlp does not return)
; Modifies:	AF, DE, HL

lsgovl:		ld	a,(loptdat)
		or	a
		ret	z		; data follows code: it cannot
		ld	hl,(lsgced)
		ld	de,(lsgcst)
		or	a
		sbc	hl,de
		ret	z		; no code at all
		ld	hl,(lsgend)
		ld	de,(lsgdst)
		or	a
		sbc	hl,de
		ret	z		; no data at all
		ld	hl,(lsgdst)	; does the data start before the
		ld	de,(lsgced)	;   code ends?
		or	a
		sbc	hl,de
		ret	nc
		ld	hl,(lsgcst)	; and the code before the data
		ld	de,(lsgend)	;   ends?
		or	a
		sbc	hl,de
		ret	nc
		jp	errlovlp

; lsgrst - every segment's running total, back to zero.
;
;   FOR PASS 2, AND ONLY THE TOTAL. The base lsglay worked out stays,
;   and so does the "placed" flag, because nothing is laid out a
;   second time. What pass 2 needs is for lsgseg's accumulation to
;   start again from nothing, so that the total standing when a
;   module's SEGDEF arrives is that module's base - exactly as it was
;   in pass 1, because the modules arrive in the same order.
;
;   lmods goes back to zero for the same reason: pass 2 counts them
;   again and arrives at the same number, so the summary line is
;   still right.
;
;   IT WALKS WITH THE SECOND ITERATOR. Nothing else is walking when
;   this runs, and lsgpl2 is already the routine that turns that
;   iterator into a payload pointer.
;
; Input:	nothing (the table, laid out)
; Output:	every total is zero
; Modifies:	everything

lsgrst:		xor	a
		ld	(lmods),a
		call	lsgfrst2
lsgrs.lp:	ld	ix,lsegtab
		ld	hl,lsit2
		call	htnext
		ret	c
		call	lsgpl2		; HL -> its payload
		ld	de,SGP_SIZ
		add	hl,de
		ld	(hl),0
		inc	hl
		ld	(hl),0
		jr	lsgrs.lp

; lsgkeep - the name of the record lsit is on, into ordinary RAM.
;
;   The key is a group byte and then the name, so the name is one
;   shorter than the key and one byte further in.
;
; Input:	lsit is on a record
; Output:	lslnam, lslkln
; Modifies:	AF, BC, DE, HL

lsgkeep:	derefp	lsit+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)
		dec	a		; less the group byte
		ld	(lslkln),a
		ld	c,a
		ld	b,0
		inc	hl		; HT_KEY: the group byte
		inc	hl		;   and now the name
		ld	de,lslnam
		ldir
		ret

; lsgsame - is the record lsit2 is on one of lslnam's?
;
;   FOLDED IF THE LINK IS CASE-INSENSITIVE, which is the default.
;   Otherwise SCRATCH in one group and scratch in another would be
;   laid end to end instead of overlaid, and [R4] would silently not
;   happen.
;
; Input:	lsit2 is on a record; lslnam, lslkln
; Output:	Z set = the same name
; Modifies:	AF, BC, DE, HL

lsgsame:	derefp	lsit2+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)
		dec	a
		ld	c,a
		ld	a,(lslkln)
		cp	c
		ret	nz		; different lengths, different names
		or	a
		ret	z		; both empty: the same, vacuously
		inc	hl
		inc	hl		; past the group byte, to the name
		ld	de,lslnam
		ld	b,c
lsgsm.lp:	ld	a,(de)
		ld	c,a
		ld	a,(lscas)
		cp	HTCASEI
		jr	nz,lsgsm.cmp
		ld	a,c		; fold both, the way the table
		call	strupr		;   hashed them
		ld	c,a
		ld	a,(hl)
		call	strupr
		cp	c
		jr	lsgsm.nx
lsgsm.cmp:	ld	a,(hl)
		cp	c
lsgsm.nx:	ret	nz
		inc	hl
		inc	de
		djnz	lsgsm.lp
		xor	a		; Z: every byte matched
		ret

; lsgmax - the largest size among the records of lslnam.
;
; Input:	lslnam, lslkln
; Output:	HL = that size
; Modifies:	everything but lsit

lsgmax:		ld	hl,0
		ld	(lslmax),hl
		call	lsgfrst2
lsgmx.lp:	ld	ix,lsegtab
		ld	hl,lsit2
		call	htnext
		jr	nc,lsgmx.go
		ld	hl,(lslmax)	; THE WALK IS OVER, AND THIS IS THE
		ret			;   ANSWER. htnext leaves HL its own,
					;   so returning without this loaded
					;   handed lsglay a number that made
					;   every segment land on ORGCOM
lsgmx.go:	call	lsgsame
		jr	nz,lsgmx.lp
		call	lsgpay2		; its size, out of the mapper
		ld	hl,(lsdsz2)
		ld	de,(lslmax)
		or	a
		sbc	hl,de
		jr	c,lsgmx.lp	; smaller: keep what we had
		ld	hl,(lsdsz2)
		ld	(lslmax),hl
		jr	lsgmx.lp

; lsgset - that base, and "placed", to every record of lslnam.
;
; Input:	HL = the base
;		lslnam, lslkln
; Output:	they are all placed
; Modifies:	everything but lsit

lsgset:		ld	(lslbase),hl
		call	lsgfrst2
lsgst.lp:	ld	ix,lsegtab
		ld	hl,lsit2
		call	htnext
		ret	c
		call	lsgsame
		jr	nz,lsgst.lp
		call	lsgpl2		; HL -> its payload
		ld	de,SGP_BAS
		add	hl,de
		ld	de,(lslbase)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),1		; SGP_SET
		jr	lsgst.lp

; lsgpl2, lsgpay2 - the record lsit2 is on: its payload, and its
;   size out of it. lsgpay does the same for lsit, and the two
;   iterators exist because the outer walk is still standing on a
;   record while these two run.
;
; Input:	lsit2 is on a record
; Output:	lsgpl2: HL -> the payload
;		lsgpay2: lsdsz2
; Modifies:	AF, BC, DE, HL

lsgpl2:		derefp	lsit2+1
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)
		ld	c,a		; IN BC across the deref: deref
		ld	b,0		;   destroys DE and keeps BC
		derefp	lsit2+1
		add	hl,bc
		ld	bc,HTHDR
		add	hl,bc
		ret

lsgpay2:	call	lsgpl2
		ld	de,SGP_SIZ
		add	hl,de
		ld	a,(hl)
		ld	(lsdsz2),a
		inc	hl
		ld	a,(hl)
		ld	(lsdsz2+1),a
		ret

lsgfrst2:	xor	a
		ld	(lsit2),a
		ld	hl,NULLOFF
		ld	(lsit2+3),hl
		ret

; lsgnam - the name of the record lsit is on, printed.
;
;   ONE CHARACTER AT A TIME, mapping the record again for each: every
;   BDOS call takes page 2 back. objnam answered this the same way.
;   A segment's key has a group byte in front of its name; a group's
;   does not, so the skip is 1 or 0 and the caller has already said
;   which by choosing the table.
;
; Input:	lsit is on a record, lsskp = key bytes before the name
; Output:	the name is printed
; Modifies:	everything

lsgnam:		derefp	lsnamp
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(hl)
		ld	hl,lsskp
		sub	(hl)
		ld	(lsnln),a
		xor	a
		ld	(lsnat),a
lsgn.lp:	ld	a,(lsnat)
		ld	hl,lsnln
		cp	(hl)
		ret	z
		derefp	lsnamp
		ld	de,HT_KEY
		add	hl,de
		ld	a,(lsskp)
		ld	e,a
		ld	a,(lsnat)
		add	a,e
		ld	e,a
		ld	d,0
		add	hl,de
		ld	a,(hl)
		ld	(lsnch),a	; OUT OF THE MAPPER FIRST, then the
		ld	a,(lsnch)	;   call - and through the system
		ld	e,a		;   macro, so p2safe runs. A BDOS
		call	putch		;   call written by hand here would
		ld	hl,lsnat	;   be the bug this loop exists for
		inc	(hl)
		jr	lsgn.lp

; lsgfrst - a walk, back to the beginning. objfrst, for this module's
;   tables.

; lsgnp - lsnamp = the record this walk is on.
;
; Input:	lsit
; Output:	lsnamp
; Modifies:	BC, DE, HL

lsgnp:		ld	hl,lsit+1
		ld	de,lsnamp
		ld	bc,4
		ldir
		ret

lsgfrst:	xor	a
		ld	(lsit),a
		ld	hl,NULLOFF
		ld	(lsit+3),hl
		ret

lsgcrlf:	ld	de,msg_crlf2
		jp	putsz

lsgb:		ld	de,lsghex	; a byte, two hex digits
		call	numhex2
		ld	hl,lsghex+2
		ld	(hl),0
		ld	de,lsghex
		jp	putsz

lsgw:		ld	de,lsghex	; and a word, four
		call	numhex
		ld	hl,lsghex+4
		ld	(hl),0
		ld	de,lsghex
		jp	putsz

		dseg

lsegtab:	defs	2+LSGBKTS*4	; the descriptors: ordinary RAM,
lgrptab:	defs	2+LSGBKTS*4	;   records in the mapper
lsnum:		defs	1	; how many segments the link has,
lgnum:		defs	1	;   how many groups, and
lmods:		defs	1	;   how many modules have been read
lsmn:		defs	1	; THIS MODULE's segments so far,
lgmn:		defs	1	;   and its groups
lsmap:		defs	LMAXSEG*6	; its segment index -> the record,
					;   AND this module's base in that
					;   segment: four bytes and two
lsgptr:		defs	4	; lsgsm's answer: which segment,
lsgbas:		defs	2	;   and where this module starts in it
lsnamp:		defs	4	; the record lsgnam is printing from -
				;   set by whichever walk is calling
lgmap:		defs	LMAXGRP		; its group index -> the global id
lsfld:		defs	4	; a SEGDEF's flags, group and size
lskey:		defs	1+256	; the key being looked up: a group byte
lskln:		defs	1	;   and a name, and how long that is
lspay:		defs	4	; the far pointer htfind and htadd fill
lsit:		defs	5	; lsgdump's walk: the bucket, then the
				;   far pointer htnext keeps
lsskp:		defs	1	; lsgnam: key bytes before the name,
lsnln:		defs	1	;   how long the name is,
lsnat:		defs	1	;   and which character it is on
lsnch:		defs	1	;   one character, out of the mapper
lsdgr:		defs	1	; lsgdump: one record, in ordinary RAM
lsdfl:		defs	1
lsdsz:		defs	2
lsdbs:		defs	2
lsdset:		defs	1
lsit2:		defs	5	; THE SECOND WALK: lsgmax and lsgset run
				;   while the outer walk is still standing
				;   on a record
lsdsz2:		defs	2	; and that walk's size, out of the mapper
lslnam:		defs	256	; the name being placed, and how long
lslkln:		defs	1	;   it is
lslmax:		defs	2	; the largest size found under it
lslbase:	defs	2	; the base being handed out
lslkind:	defs	1	; 0 while the code segments are placed,
				;   1 for the data ones
lsgnext:	defs	2	; the next free address
lsgend:		defs	2	; where the LAST KIND finished - which
				; with /D: putting the data below the
				; code is not where the image ends.
				; Nothing reads it; the image's real
				; extent is the imglo and imghi,
				; measured from what was written
lsgcst:		defs	2	; lsgovl: where the code began,
lsgced:		defs	2	;   where it ended, and
lsgdst:		defs	2	;   where the data began
lsgbase:	defs	2	; lsgsm's answer: that segment's own base
lscas:		defs	1	; HTCASES or HTCASEI, for lsgsame
lsghex:		defs	5	; numhex's answer, zero-terminated

msg_mods:	defb	"Modules: ",0
msg_grps:	defb	"Groups:",CHR_CR,CHR_LF,0
msg_segs:	defb	"Segments:",CHR_CR,CHR_LF,0
msg_ind:	defb	"  ",0
msg_flg:	defb	"flags ",0
msg_grp:	defb	" group ",0
msg_bas:	defb	" base ",0
msg_siz:	defb	" size ",0
msg_end:	defb	" end ",0
msg_noend:	defb	"-----",0
msg_sp:		defb	" ",0
msg_crlf2:	defb	CHR_CR,CHR_LF,0
