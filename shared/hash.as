; hash.as - generic hash table library over the mapper heap (alloc.as).
;
; Keys are byte strings (1-255 bytes). Payloads are opaque and caller-sized;
; the library never interprets them.
;
; Any number of tables per program: each table is a caller-owned DESCRIPTOR,
; passed to every routine in IX (IX is preserved by all routines):
;
;   +0 (HT_CASE) Case mode byte (HTCASES/HTCASEI). Indicates whether the 
;                table keys are case sensitive or insensitive (default: ins)
;   +1 (HT_MASK) Bucket mask = bucket count - 1 (count = power of 2, 2..256,
;                so the mask fits a byte: FFh, 7Fh, 3Fh, ...)
;   +2 (HT_TAB)  The bucket index: (mask+1) far pointers, 4 bytes each
;
; The caller allocates it to match: e.g.: "desc: defs 2+256*4" or 256 buckets,
; "defs 2+64*4" for 64.
;
; RULES: the descriptor must live in ordinary program RAM (never in the mapper
;        heap - it is read while page 2 is banked) and must not move (its
;        buckets hold live far pointers).
;
; Record in the heap: next farptr(4) + klen(1) + key(klen) + payload.
;
; Build phases:
; H1: skeleton - descriptors, htinit, the hash function. [done]
; H2: htadd + htfind. [done]
; H3: htdel, htclear, htnext (enumeration), htrepl. [done]
; H4: convert wc to this library (regression test). [done]
; H5: release pass - hash.inc, documentation, repo. [done]

HASHLIB		equ	1

		public	htinit
		public	hthash		; public mainly for tests/diagnostics
		public	htadd
		public	htfind
		public	htdel
		public	htclear
		public	htnext
		public	htrepl

		include	alloc.inc	; halloc + deref (records live in the
					; heap)
		include	farptr.inc
		include	hash.inc

		cseg

; htinit - format a descriptor as an empty table.
;
; Input:	IX = descriptor
;		A  = case mode (HTCASES/HTCASEI)
;		B  = bucket mask (bucket count - 1; count = power of 2)
; Output:	descriptor initialized, all buckets empty
; Modifies:	F, BC, DE, HL (IX, A preserved)

htinit:		ld	(ix+HT_CASE),a
		ld	(ix+HT_MASK),b
		ld	l,b		; HL = mask+1 = bucket count (2..256)
		ld	h,0
		inc	hl
		add	hl,hl		; HL = count*4 = index size in bytes
		add	hl,hl
		dec	hl		; fill length minus the seed byte
		ld	b,h
		ld	c,l		; BC = ldir count
		push	ix		; HL = IX + HT_TAB = first index byte
		pop	hl
		ld	de,HT_TAB
		add	hl,de
		ld	(hl),0ffh	; seed: fill the index with 0FFh, so
		push	hl		; every entry's offset reads FFFF=null
		pop	de		; (forward-copy fill: each byte copies
		inc	de		; into the next)
		ldir
		ret

; hthash - hash a key.
;
; The function:
;   acc = 0; per byte: acc = RLC(acc) XOR byte.
; The rotate mixes character POSITION into the value, so "ab" and "ba" hash
; differently.
; In case-insensitive mode each byte is folded a-z -> A-Z first, so the fold
; here and the compare in htfind (H2) agree - same name, same bucket.
;
; Returns the RAW 8-bit hash; the bucket number is hash AND (ix+HT_MASK),
; applied by the lookup routines (H2).
;
; Input:	IX = descriptor
;		DE = key address
;		A  = key length (1-255)
; Output:	A  = hash value (0-255)
; Modifies:	AF, BC, DE (IX preserved)

hthash:		ld	b,a		; B = bytes left
		ld	c,0		; C = hash accumulator
hthash.1:	ld	a,(de)
		call	htfold		; fold case if insensitive
		rlc	c		; rotate the accumulator...
		xor	c		; ...mix the byte in...
		ld	c,a		; ...and store back
		inc	de
		djnz	hthash.1
		ld	a,c
		ret

; htfold - fold A from a-z to A-Z when the table is case-insensitive.
;   Everything else (and everything, in sensitive mode) passes unchanged.
;
; Input:	IX = descriptor
;		A  = character
; Output:	A  = folded character
; Modifies:	AF

htfold:		bit	0,(ix+HT_CASE)	; bit leaves A alone
		ret	z		; sensitive -> unchanged
		cp	"a"
		ret	c		; below "a" -> unchanged
		cp	"z"+1
		ret	nc		; above "z" -> unchanged
		and	0dfh		; clear bit 5: a-z -> A-Z
		ret

; htadd - add a NEW record for a key. No duplicate check: if the key already
; exists, htfind keeps returning the OLD record (the new one sits behind it
; in the chain) - call htfind first when duplicates matter.
; The payload is left uninitialized; the caller writes it via the returned
; far pointer. The key is stored AS GIVEN (folding happens at compare time),
; so the original spelling is preserved for enumeration.
;
; Input:	IX = descriptor
;		DE = key address
;		A  = key length (1-255)
;		BC = payload size
;		HL = 4-byte buffer for the payload farptr
; Output:	CY set   = out of heap memory
;		CY clear = buffer filled, record linked at its bucket's head
; Modifies:	AB, BC, DE, HL (IX preserved)

htadd:		ld	(htskey),de	; stash the parameters
		ld	(htsklen),a
		ld	(htspay),bc
		ld	(htsres),hl

		call	hthash		; A = hash (DE/A still hold key/len)
		and	(ix+HT_MASK)	; A = bucket number
		ld	l,a		; ht_bkt = IX + HT_TAB + bucket*4
		ld	h,0
		add	hl,hl
		add	hl,hl
		push	ix
		pop	de
		add	hl,de
		ld	de,HT_TAB
		add	hl,de
		ld	(htsbkt),hl

		ld	a,(htsklen)	; record size = HTHDR + klen + paysize
		ld	l,a
		ld	h,0
		ld	de,HTHDR
		add	hl,de
		ld	de,(htspay)
		add	hl,de
		ld	b,h
		ld	c,l
		ld	hl,htsnew
		call	halloc		; ht_new = the record's far pointer
		ret	c		; out of memory -> CY through

		derefp	htsnew		; HL -> record base (page 2)
		ex	de,hl		; record.next = current bucket head
		ld	hl,(htsbkt)	; (the bucket is low RAM - readable
		ld	bc,4		; while page 2 is banked)
		ldir			; DE -> record+4
		ld	a,(htsklen)	; +4: key length
		ld	(de),a
		inc	de		; DE -> record+5: the key bytes
		ld	hl,(htskey)
		ld	c,a
		ld	b,0
		ldir

		ld	hl,(htsbkt)	; bucket head = the new record
		ex	de,hl
		ld	hl,htsnew
		ld	bc,4
		ldir

		ld	a,(htsklen)	; result: advance the far pointer's
		ld	l,a		; offset past HTHDR + klen -> payload
		ld	h,0
		ld	de,HTHDR
		add	hl,de
		ld	de,(htsnew+2)
		add	hl,de
		ld	(htsnew+2),hl
		ld	hl,htsnew	; copy to the caller's buffer
		ld	de,(htsres)
		ld	bc,4
		ldir
		or	a		; CY clear = success
		ret

; htfind - look a key up.
;
; Input:	IX = descriptor
;		DE = key address
;		A  = key length (1-255)
;		HL = 4-byte buffer for the payload far pointer
; Output:	CY set   = not found
;		CY clear = buffer = payload far pointer
; Modifies:	AF, BC, DE, HL (IX preserved)

htfind:		ld	(htskey),de
		ld	(htsklen),a
		ld	(htsres),hl

		call	hthash
		and	(ix+HT_MASK)
		ld	l,a		; HL = IX + HT_TAB + bucket*4
		ld	h,0
		add	hl,hl
		add	hl,hl
		push	ix
		pop	de
		add	hl,de
		ld	de,HT_TAB
		add	hl,de
		fpsave	htscur		; cursor = bucket head
htfind.loop:	fpnull	htscur		; chain exhausted -> miss
		jr	z,htfind.miss
		derefp	htscur		; HL -> record base (page 2)
		push	hl
		ld	de,HT_KLEN	; length match first - rejects most
		add	hl,de		; non-matches on one compare
		ld	a,(htsklen)
		cp	(hl)
		pop	hl
		jr	nz,htfind.next
		push	hl
		ld	de,HT_KEY
		add	hl,de		; HL -> record key (page 2)
		ld	de,(htskey)	; DE -> probe key (low RAM)
		ld	a,(htsklen)
		ld	b,a
htfind.cmp:	ld	a,(de)		; fold BOTH sides, so neither the
		call	htfold		; stored case nor the probe case
		ld	c,a		; matters in insensitive mode
		ld	a,(hl)
		call	htfold
		cp	c
		jr	nz,htfind.no
		inc	hl
		inc	de
		djnz	htfind.cmp
		pop	hl		; MATCH (HL discarded - balance stack)
		ld	a,(htsklen)	; result: cursor's offset advanced
		ld	l,a		; past HTHDR + klen -> payload
		ld	h,0
		ld	de,HTHDR
		add	hl,de
		ld	de,(htscur+2)
		add	hl,de
		ld	(htscur+2),hl
		ld	hl,htscur
		ld	de,(htsres)
		ld	bc,4
		ldir
		or	a		; CY clear = found
		ret
htfind.no:	pop	hl
htfind.next:	derefp	htscur		; cursor = record.next: re-map (cache
		fpsave	htscur		; hit); HL -> +0 = the next link - 
					; fpsave copies it out BEFORE
					; anything can remap the window
		jr	htfind.loop
htfind.miss:	scf
		ret

; htdel - delete a key's record.
;
; Input:	IX = descriptor
;		DE = key address
;		A  = key length (1-255)
; Output:	CY set   = not found
;		CY clear = record unlinked and freed
; Modifies:	AF, BC, DE, HL (IX preserved)
;
; CAUTION: far pointers the caller stored for this record's payload are
; dangling after this. If the payload held far pointers to other heap
; blocks, free those FIRST - the library cannot know what payloads mean.

htdel:		ld	(htskey),de
		ld	(htsklen),a
		call	hthash
		and	(ix+HT_MASK)
		ld	l,a		; HL = IX + HT_TAB + bucket*4
		ld	h,0
		add	hl,hl
		add	hl,hl
		push	ix
		pop	de
		add	hl,de
		ld	de,HT_TAB
		add	hl,de
		ld	(htsbkt),hl	; the bucket entry's address
		fpsave	htscur		; cursor = bucket head
		ld	hl,NULLOFF	; predecessor = null = "the bucket"
		ld	(htsprv+2),hl
htdel.loop:	fpnull	htscur		; end of chain -> not found
		jp	z,htdel.miss
		derefp	htscur		; HL -> record base (page 2)
		push	hl
		ld	de,HT_KLEN
		add	hl,de
		ld	a,(htsklen)
		cp	(hl)
		pop	hl
		jp	nz,htdel.next
		push	hl
		ld	de,HT_KEY
		add	hl,de
		ld	de,(htskey)
		ld	a,(htsklen)
		ld	b,a
htdel.cmp:	ld	a,(de)		; folded compare, as in htfind
		call	htfold
		ld	c,a
		ld	a,(hl)
		call	htfold
		cp	c
		jr	nz,htdel.no
		inc	hl
		inc	de
		djnz	htdel.cmp
		pop	hl		; MATCH (discard saved base)
		derefp	htscur		; save the doomed record's next link
		fpsave	htsnxt		; (cache hit) HL -> +0 = next
		fpnull	htsprv		; who points at the record?
		jr	nz,htdel.mid
		ld	de,(htsbkt)	; head case: bucket (low RAM) = next
		ld	hl,htsnxt
		ld	bc,4
		ldir
		jr	htdel.free
htdel.mid:	derefp	htsprv		; mid-chain: prev.next (page 2) = next
		ex	de,hl		; HL -> prev record +0
		ld	hl,htsnxt	; (destination arrives in DE - no
		ld	bc,4		; macro)
		ldir
htdel.free:	ld	hl,htscur	; free the record: its far pointer IS
		call	hfree		; a heap payload pointer
		or	a		; CY clear = deleted
		ret
htdel.no:	pop	hl
htdel.next:	fpcopy	htsprv,htscur	; predecessor = current record
		derefp	htscur		; cursor = current.next: HL -> +0 =
		fpsave	htscur		; the next link, copied out safely
		jp	htdel.loop
htdel.miss:	scf
		ret

; htclear - free every record and leave the table empty (reusable without
; a new htinit).
; The htdel payload CAUTION applies to every record: free payload-referenced
; blocks first, e.g. by iterating with htnext before calling this.
;
; Input:	IX = descriptor
; Output:	all records freed, all buckets empty
; Modifies:	AF, BC, DE, HL (IX preserved)

htclear:	push	ix		; htsbkt = first bucket's address
		pop	hl
		ld	de,HT_TAB
		add	hl,de
		ld	(htsbkt),hl
		ld	l,(ix+HT_MASK)	; htsbcn = bucket count = mask+1
		ld	h,0
		inc	hl
		ld	(htsbcn),hl
htclear.bkt:	ld	hl,(htsbkt)	; HL = the bucket's address...
		fpsave	htscur		; ...cursor = this bucket's head
htclear.chn:	fpnull	htscur		; chain done?
		jr	z,htclear.nxb
		derefp	htscur		; save next BEFORE freeing: HL -> +0
		fpsave	htsnxt
		ld	hl,htscur
		call	hfree
		fpcopy	htscur,htsnxt	; cursor = next
		jr	htclear.chn
htclear.nxb:	ld	hl,(htsbkt)	; null the bucket (4 x 0FFh)
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		ld	hl,(htsbkt)	; next bucket
		ld	de,4
		add	hl,de
		ld	(htsbkt),hl
		ld	hl,(htsbcn)
		dec	hl
		ld	(htsbcn),hl
		ld	a,h
		or	l
		jp	nz,htclear.bkt
		ret

; htnext - enumerate the records, one per call, in bucket order.
;
; The iterator is 5 caller-owned bytes:
;   +0     bucket number
;   +1..+4 far pointer to the current record
; START a walk with: +0 = 0 and the offset field (+3..+4) = FFFFh.
; After each CY-clear return, +1..+4 is the next record's far pointer - parse
; it with HT_KLEN/HT_KEY/HTHDR. Do not add or delete between calls of one walk.
;
; Input:	IX = descriptor
;		HL = iterator address
; Output:	CY set   = no more records
;		CY clear = iterator updated
; Modifies:	AF, BC, DE, HL (IX preserved)

htnext:		ld	(htsres),hl	; remember the iterator's address
		push	hl
		inc	hl		; HL -> its far pointer...
		fpsave	htscur		; ...copied to scratch
		pop	hl
		ld	a,(hl)		; current bucket number
		ld	(htsbcn),a
		fpnull	htscur		; null fp -> scan for a non-empty
		jr	z,htnext.sc1	; bucket, starting at this one
		derefp	htscur		; follow the current record's next:
		fpsave	htscur		; HL -> +0, copied out safly
		fpnull	htscur		; chain continues -> answer found
		jr	nz,htnext.got
		ld	a,(htsbcn)	; chain ended -> next bucket (if any)
		cp	(ix+HT_MASK)
		jr	z,htnext.done
		inc	a
		ld	(htsbcn),a
htnext.sc1:	ld	a,(htsbcn)	; HL = IX + HT_TAB + bucket*4
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		push	ix
		pop	de
		add	hl,de
		ld	de,HT_TAB
		add	hl,de
		fpsave	htscur		; this bucket's head -> scratch
		fpnull	htscur
		jr	nz,htnext.got	; non-empty -> answer found
		ld	a,(htsbcn)	; empty -> next bucket or done
		cp	(ix+HT_MASK)
		jr	z,htnext.done
		inc	a
		ld	(htsbcn),a
		jr	htnext.sc1
htnext.got:	ld	hl,(htsres)	; write bucket + far pointer back
		ld	a,(htsbcn)
		ld	(hl),a
		inc	hl
		ex	de,hl
		ld	hl,htscur
		ld	bc,4
		ldir
		or	a		; CY clear = a record is delivered
		ret
htnext.done:	scf
		ret

; htrepl - replace: delete any existing record for the key, and add a new one.
; "Not present" is not an error - htrepl then behaves as htadd.
; Far pointers stored for the OLD payload are dangling afterwards.
;
; Input:	IX = descriptor
;		DE = key
;		A  = klen
;		BC = new payload size
;		HL = 4-byte buffer for the new payload far pointer
; Output:	CY set   = out of heap memory
;		CY clear = buffer filled
; Modifies:	AF, BC, DE, HL (IX preserved)

htrepl:		push	hl	; htdel consumes DE/A and the scratch,
		push	bc	; so hold the htadd parameters on the
		push	de	; stack across it
		push	af
		call	htdel	; CY (not found deliberately ignored)
		pop	af
		pop	de
		pop	bc
		pop	hl
		jp	htadd	; tail call - htadd's result is ours

; --- scratch area

		dseg

htskey:		defs	2		; probe/new key address
htsklen:	defs	1		; its length
htspay:		defs	2		; htadd: payload size
htsres:		defs	2		; caller's result-buffer address
htsbkt:		defs	2		; address of the hashed bucket
htscur:		defs	4		; walk cursor (far pointer)
htsnew:		defs	4		; new record (far pointer)
htsprv:		defs	4		; htdel: predecessor record (offset
					; FFFF = the bucket is the predecessor)
htsnxt:		defs	4		; saved 'next' of a record being freed
htsbcn:		defs	2		; bucket counter (htclear/htnext)
