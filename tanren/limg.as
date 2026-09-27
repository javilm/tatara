; limg.as - the image TANREN is building, and the file it becomes.
;
; SIXTEEN BLOCKS OF 4 KB IN MAPPER RAM, indexed by the address they
; hold: the block is the address's top nibble and the offset is the
; rest of it. A block is created when something is first written into
; it, so a .COM of 8 KB costs two or three blocks and not sixteen.
;
; A NEW BLOCK IS ZEROED. A DS between two DATA runs, or the gap
; between 0100h and an absolute run at 4000h, has to come out of the
; file as zeros and not as whatever the heap last held there.
;
; EVERY BDOS CALL TAKES PAGE 2 BACK, so nothing goes to the file
; straight out of the mapper: a chunk is copied into ordinary RAM
; first and written from there. lsgdump and objnam met the same rule
; from the other side.

LIMGLIB		equ	1	; skips the externals in limg.inc

		public	imginit
		public	imgwr
		public	imgget
		public	imgput
		public	imgsave
		public	imglo
		public	imghi
		public	imgany

		include	limg.inc
		include	lobj.inc	; lobbuf: the buffer a NAME goes
					;   in, borrowed by imgsave, which
					;   runs when every object file is
					;   closed
		include	lerrs.inc	; errlheap, errlbig, errlout,
					;   errlwrt
		include	alloc.inc	; halloc, deref
		include	farptr.inc	; derefp, NULLOFF
		include	msxdos.inc	; _CREATE, _WRITE, _CLOSE

		cseg

; imginit - an empty image.
;
;   The extremes start the wrong way round on purpose: the first
;   write in either direction replaces them.
;
; Input:	nothing
; Output:	every block unallocated, nothing written
; Modifies:	AF, B, HL

imginit:	ld	hl,imgtab
		ld	b,IMGNBLK
imgi.lp:	inc	hl		; past the slot and the segment
		inc	hl
		ld	(hl),0ffh	; NULLOFF is 0FFFFh, so both bytes
		inc	hl		;   of the offset are FFh
		ld	(hl),0ffh
		inc	hl
		djnz	imgi.lp
		ld	hl,0ffffh
		ld	(imglo),hl
		ld	hl,0
		ld	(imghi),hl
		xor	a
		ld	(imgany),a
		ret

; imgmark - this address now holds content.
;
;   THE SPAN IS MEASURED AND NOT ASSUMED: an absolute module may put
;   content at 4000h in a link whose segments start at 0100h, and the
;   file has to span both.
;
; Input:	HL = the address
; Output:	imglo, imghi, imgany
; Modifies:	AF, DE

imgmark:	ld	a,0ffh
		ld	(imgany),a
		ld	de,(imglo)
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	nc,imgm.hi	; not below the lowest so far
		ld	(imglo),hl
imgm.hi:	ld	de,(imghi)
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		ret	c		; not above the highest
		ld	(imghi),hl
		ret

; imgfind - the far pointer of block A, in imgfp.
;
;   IT IS NOT CALLED imgblk: IMGBLK is the block size, SOLiD's as
;   folds case, and the two names would be one symbol. Two builds
;   were lost to exactly that.
;
;   imgalw is what separates a reader from a writer. imgwr and imgput
;   may create a block; imgget and imgsave may not, because reading an
;   address nobody wrote should not cost a mapper segment.
;
; Input:	A = which block, 0 to 15
;		imgalw = 0FFh if it may be created
; Output:	imgfp = its far pointer
;		CY set = there is no such block
;		(errlheap does not return)
; Modifies:	AF, DE, HL - NOT BC, which holds the offset

imgfind:	ld	(imgb),a
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl		; four bytes each
		ld	de,imgtab
		add	hl,de
		ld	(imgbp),hl	; where it lives, for imgnew
		ld	de,imgfp
		push	bc
		ld	bc,4
		ldir
		pop	bc
		ld	a,(imgfp+3)	; a real offset is 0 to 3FFFh, so a
		cp	0ffh		;   high byte of FFh can only be
		jr	nz,imgf.ok	;   NULLOFF
		ld	a,(imgalw)
		or	a
		scf
		ret	z		; not allowed to create one
		jp	imgnew
imgf.ok:	or	a		; CY clear: imgfp is good
		ret

; imgnew - a block that has not existed until now.
;
; Input:	imgb, imgbp
; Output:	imgfp, and imgtab holds it too
;		(errlheap does not return)
; Modifies:	AF, DE, HL - not BC

imgnew:		push	bc
		ld	bc,IMGBLK
		ld	hl,imgfp
		call	halloc
		jp	c,errlheap
		ld	hl,imgfp	; the table keeps it as well
		ld	de,(imgbp)
		ld	bc,4
		ldir
		derefp	imgfp		; and it starts as zeros
		ld	d,h
		ld	e,l
		inc	de
		ld	(hl),0
		ld	bc,IMGBLK-1
		ldir
		pop	bc
		or	a		; CY clear
		ret

; imgmap, imgmapa - the byte at HL, addressable in page 2.
;
;   imgmapa creates the block if it has to; imgmap does not and says
;   so with carry. BOTH ANSWER WITH HOW MUCH OF THE BLOCK FOLLOWS, so
;   a caller copying a run knows where it has to stop and map again: a
;   run may cross a 4 KB boundary and the two halves are in two mapper
;   segments.
;
; Input:	HL = the address
; Output:	HL = where that byte is in page 2
;		BC = bytes of this block from there on, 1 to 4096
;		CY set = no such block (imgmap only; BC is still right)
; Modifies:	AF, BC, DE, HL

imgmapa:	ld	a,0ffh
		jr	imgm.go
imgmap:		xor	a
imgm.go:	ld	(imgalw),a
		ld	a,h
		and	IMGOMSK
		ld	b,a
		ld	c,l		; BC = the offset within the block
		ld	a,h		; and A = which block
		and	0f0h
		rrca
		rrca
		rrca
		rrca
		call	imgfind
		jr	c,imgm.non
		derefp	imgfp		; BC SURVIVES A deref, which is why
		add	hl,bc		;   the offset is kept there
		push	hl
		ld	hl,IMGBLK
		or	a
		sbc	hl,bc		; and the rest of the block
		ld	b,h
		ld	c,l
		pop	hl
		or	a		; CY clear
		ret
imgm.non:	ld	hl,IMGBLK	; no block, but the caller still
		or	a		;   needs the distance to the next
		sbc	hl,bc		;   one
		ld	b,h
		ld	c,l
		scf
		ret

; imgwr - a run of content, into the image.
;
;   A BLOCK AT A TIME. A run of 200 bytes starting at 0FF0h is in two
;   mapper segments, and one ldir cannot reach both.
;
; Input:	HL = the address the run loads at
;		DE -> the bytes, in ordinary RAM
;		BC = how many
; Output:	they are in the image; imglo and imghi know
;		(errlbig, errlheap do not return)
; Modifies:	everything

imgwr:		ld	(imgwa),hl
		ld	(imgws),de
		ld	(imgwn),bc
		ld	a,b
		or	c
		ret	z		; a run of no bytes
		dec	bc		; THE LAST BYTE, not the one after
		add	hl,bc		;   it: a run ending exactly at
		jp	c,errlbig	;   FFFFh is legal and wrapping
		call	imgmark		;   past it is not
		ld	hl,(imgwa)
		call	imgmark		; and the first one
imgw.lp:	ld	hl,(imgwn)
		ld	a,h
		or	l
		ret	z
		ld	hl,(imgwa)
		call	imgmapa		; -> HL, and BC = room left
		ld	(imgwp),hl
		ld	hl,(imgwn)
		or	a
		sbc	hl,bc		; more than this block holds?
		jr	c,imgw.fits
		ld	h,b		; then fill it to the end
		ld	l,c
		jr	imgw.n
imgw.fits:	ld	hl,(imgwn)
imgw.n:		ld	(imgwc),hl
		ld	b,h
		ld	c,l
		ld	de,(imgwp)
		ld	hl,(imgws)
		ldir			; ordinary RAM -> the mapper
		ld	(imgws),hl
		ld	bc,(imgwc)	; and everything moves on by it
		ld	hl,(imgwa)
		add	hl,bc
		ld	(imgwa),hl
		ld	hl,(imgwn)
		or	a
		sbc	hl,bc
		ld	(imgwn),hl
		jp	imgw.lp		; jp: the loop is longer than a jr

; imgget - one byte out of the image.
;
; Input:	HL = its address
; Output:	A = the byte, or 0 where nothing was ever written
; Modifies:	AF, BC, DE, HL

imgget:		call	imgmap
		ld	a,0		; ld does not touch the carry
		ret	c
		ld	a,(hl)
		ret

; imgput - one byte into it.
;
; Input:	A  = the byte
;		HL = its address
; Output:	it is there
; Modifies:	AF, BC, DE, HL

imgput:		ld	(imgbyt),a
		call	imgmark
		call	imgmapa
		ld	a,(imgbyt)
		ld	(hl),a
		ret

; imgsave - the image, to a file.
;
;   FROM imglo TO imghi INCLUSIVE and nothing outside it: the space a
;   DS reserved after the last byte of content is not in the file,
;   which is what every loader expects and what L80 does too.
;
;   RAW BYTES, OR SEVEN IN FRONT OF THEM. /B changes nothing about the
;   image: the header's three words are the two this module measured
;   and one the caller hands over.
;
; Input:	DE -> the ASCIIZ filename
;		A  = 0 for raw bytes, anything else for a BLOAD header
;		HL = the execution address that header carries
; Output:	CY set = nothing was written, and no file was made
;		(errlout, errlwrt do not return)
; Modifies:	everything

imgsave:	ld	(imghdr),a	; BOTH ARGUMENTS FIRST: the rest of
		ld	(imgexe),hl	;   this routine wants A and HL for
		ld	a,(imgany)	;   its own purposes
		or	a
		scf
		ret	z		; a link with no content in it
		xor	a		; mode 0 = read and write
		ld	b,a		; attributes 0 = an ordinary file
		system	_CREATE		; -> A = error, B = the handle
		or	a
		jp	nz,errlout
		ld	a,b
		ld	(imghand),a
		ld	a,(imghdr)	; the seven bytes, BEFORE any
		or	a		;   content
		call	nz,imgbld
		ld	hl,(imglo)
		ld	(imgsa),hl
		ld	hl,(imghi)	; both ends are in the file, so the
		ld	de,(imglo)	;   count is the span plus one
		or	a
		sbc	hl,de
		inc	hl
		ld	(imgsn),hl
imgs.lp:	ld	hl,(imgsn)
		ld	a,h
		or	l
		jr	z,imgs.end
		ld	a,h		; more than 255 left?
		or	a
		jr	z,imgs.part	; no: HL is the last chunk
		ld	hl,IMGCHNK
imgs.part:	ld	(imgsc),hl
		call	imgfill		; those bytes, into lobbuf
		ld	hl,(imgsc)
		ld	de,lobbuf
		ld	a,(imghand)
		ld	b,a
		system	_WRITE		; -> A = error
		or	a
		jp	nz,errlwrt
		ld	bc,(imgsc)
		ld	hl,(imgsa)
		add	hl,bc
		ld	(imgsa),hl
		ld	hl,(imgsn)
		or	a
		sbc	hl,bc
		ld	(imgsn),hl
		jp	imgs.lp
imgs.end:	ld	a,(imghand)
		ld	b,a
		system	_CLOSE
		or	a		; CY clear: it was written
		ret

; imgbld - the seven-byte BLOAD header.
;
;   FEh, the start address, THE ADDRESS OF THE LAST BYTE - not the one
;   after it - and the execution address: MSX BASIC's BSAVE format,
;   which is what BLOAD reads and what makes a file a .BIN. imghi is
;   already the last byte, so the inclusive end this format is usually
;   got wrong on costs nothing here.
;
;   A file of no bytes never reaches this, because imgsave returns
;   before it creates anything.
;
; Input:	the file is open
;		imgexe = the execution address
; Output:	seven bytes are written (errlwrt does not return)
; Modifies:	AF, BC, DE, HL

imgbld:		ld	a,0feh		; "this is a machine code file"
		ld	(imgbuf),a
		ld	hl,(imglo)
		ld	(imgbuf+1),hl
		ld	hl,(imghi)
		ld	(imgbuf+3),hl
		ld	hl,(imgexe)
		ld	(imgbuf+5),hl
		ld	hl,7
		ld	de,imgbuf
		ld	a,(imghand)
		ld	b,a
		system	_WRITE		; -> A = error
		or	a
		jp	nz,errlwrt
		ret

; imgfill - the next chunk of the image, into lobbuf.
;
;   ZEROS FIRST, then whatever blocks exist are copied over them: a
;   chunk may cross a block nobody ever wrote to, and the file needs
;   zeros there rather than a hole.
;
; Input:	imgsa = from where
;		imgsc = how many, 1 to 256
; Output:	lobbuf holds them
; Modifies:	everything

imgfill:	ld	hl,lobbuf
		ld	(hl),0
		ld	d,h
		ld	e,l
		inc	de
		ld	bc,IMGCHNK-1
		ldir
		ld	hl,0
		ld	(imgfa),hl	; how far into the chunk we are
imgf.lp:	ld	hl,(imgfa)
		ld	de,(imgsc)
		or	a
		sbc	hl,de
		ret	nc		; the chunk is full
		ld	hl,(imgsa)
		ld	de,(imgfa)
		add	hl,de		; the address this byte holds
		call	imgmap
		push	af		; CY: there is no block there
		ld	(imgfp2),hl
		ld	hl,(imgsc)
		ld	de,(imgfa)
		or	a
		sbc	hl,de		; what is left of the chunk
		or	a
		sbc	hl,bc		; less than the rest of the block?
		jr	c,imgf.rest
		ld	h,b
		ld	l,c
		jr	imgf.n
imgf.rest:	ld	hl,(imgsc)
		ld	de,(imgfa)
		or	a
		sbc	hl,de
imgf.n:		ld	(imgfc),hl
		pop	af
		jr	c,imgf.skip	; no block: the zeros stand
		ld	hl,lobbuf
		ld	de,(imgfa)
		add	hl,de
		ex	de,hl		; DE -> where in the buffer
		ld	hl,(imgfp2)	; HL -> the mapper
		ld	bc,(imgfc)
		ldir
imgf.skip:	ld	hl,(imgfa)
		ld	bc,(imgfc)
		add	hl,bc
		ld	(imgfa),hl
		jp	imgf.lp

		dseg

imgtab:		defs	IMGNBLK*4	; the blocks, by which 4 KB of the
					;   address space they hold
imgfp:		defs	4	; one of them, on its way to deref
imgbp:		defs	2	; and where in imgtab it lives
imgb:		defs	1	; which block it is
imgalw:		defs	1	; 0FFh = this caller may create one
imglo:		defs	2	; the lowest address written,
imghi:		defs	2	;   the highest, and
imgany:		defs	1	;   whether anything was at all
imgbyt:		defs	1	; imgput: the byte, across the mapping
imgwa:		defs	2	; imgwr: where the run goes,
imgws:		defs	2	;   where it comes from,
imgwn:		defs	2	;   how much is still to go,
imgwc:		defs	2	;   this chunk of it,
imgwp:		defs	2	;   and where that chunk lands
imghdr:		defs	1	; imgsave: 0 = raw bytes, anything else
imgexe:		defs	2	;   = a BLOAD header, and the execution
				;   address it carries
imgbuf:		defs	7	; imgbld: those seven bytes
imghand:	defs	1	; imgsave: the output file's handle,
imgsa:		defs	2	;   the address it is up to,
imgsn:		defs	2	;   how many bytes are left, and
imgsc:		defs	2	;   this chunk's size
imgfa:		defs	2	; imgfill: how far into the chunk,
imgfc:		defs	2	;   this piece of it, and
imgfp2:		defs	2	;   where in page 2 that piece is
