; hash.as - generic hash table library over the mapper heap (alloc.as).
;
; Keys are byte strings (1-255 bytes). Payloads are opaque and caller-sized;
; the library never interprets them.
;
; Any number of tables per program: each table is a caller-owned DESCRIPTOR,
; passed to every routine in IX (IX is preserved by all routines):
;
;   +0 (HT_CASE) Case mode byte: HT_CASE_SENSITIVE or HT_CASE_FOLD.
;                Whether the table's keys are compared with case or
;                without it (default: without)
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
; H3: htdelete, htclear, htnext (enumeration), htreplace. [done]
; H4: convert wc to this library (regression test). [done]
; H5: release pass - hash.inc, documentation, repo. [done]

HASH_INCLUDED	equ	1

		public	htinit
		public	hthash		; public mainly for tests/diagnostics
		public	htadd
		public	htfind
		public	htdelete
		public	htclear
		public	htnext
		public	htreplace

		include	alloc.inc	; halloc + deref (records live in the
					; heap)
		include	farptr.inc
		include	hash.inc

		cseg

; htinit - format a descriptor as an empty table.
;
; Input:	IX = descriptor
;		A  = case mode (HT_CASE_SENSITIVE/HT_CASE_FOLD)
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
hthash.loop:	ld	a,(de)
		call	htfold		; fold case if insensitive
		rlc	c		; rotate the accumulator...
		xor	c		; ...mix the byte in...
		ld	c,a		; ...and store back
		inc	de
		djnz	hthash.loop
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

htadd:		ld	(probe_key),de	; stash the parameters
		ld	(probe_key_length),a
		ld	(add_payload_size),bc
		ld	(result_buffer),hl

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
		ld	(bucket_address),hl

		; record size = HT_HEADER_SIZE + klen + paysize
		ld	a,(probe_key_length)
		ld	l,a
		ld	h,0
		ld	de,HT_HEADER_SIZE
		add	hl,de
		ld	de,(add_payload_size)
		add	hl,de
		ld	b,h
		ld	c,l
		ld	hl,new_record
		call	halloc		; ht_new = the record's far pointer
		ret	c		; out of memory -> CY through

		derefp	new_record	; HL -> record base (page 2)
		ex	de,hl		; record.next = current bucket head
		ld	hl,(bucket_address)	; the bucket is low RAM,
		ld	bc,4		;   readable while page 2 is
					;   banked
		ldir			; DE -> record+4
		ld	a,(probe_key_length)	; +4: key length
		ld	(de),a
		inc	de		; DE -> record+5: the key bytes
		ld	hl,(probe_key)
		ld	c,a
		ld	b,0
		ldir

		ld	hl,(bucket_address)	; bucket head = the new record
		ex	de,hl
		ld	hl,new_record
		ld	bc,4
		ldir

		; result: advance the far pointer's offset past
		;   HT_HEADER_SIZE + klen, to the payload
		ld	a,(probe_key_length)
		ld	l,a
		ld	h,0
		ld	de,HT_HEADER_SIZE
		add	hl,de
		ld	de,(new_record+2)
		add	hl,de
		ld	(new_record+2),hl
		ld	hl,new_record	; copy to the caller's buffer
		ld	de,(result_buffer)
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

htfind:		ld	(probe_key),de
		ld	(probe_key_length),a
		ld	(result_buffer),hl

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
		fpsave	walk_cursor	; cursor = bucket head
htfind.loop:	fpnull	walk_cursor	; chain exhausted -> miss
		jr	z,htfind.miss
		derefp	walk_cursor	; HL -> record base (page 2)
		push	hl
		ld	de,HT_KEY_LENGTH	; length first: it rejects most
		add	hl,de		;   non-matches on one compare
		ld	a,(probe_key_length)
		cp	(hl)
		pop	hl
		jr	nz,htfind.next
		push	hl
		ld	de,HT_KEY
		add	hl,de		; HL -> record key (page 2)
		ld	de,(probe_key)	; DE -> probe key (low RAM)
		ld	a,(probe_key_length)
		ld	b,a
htfind.compare:	ld	a,(de)		; fold BOTH sides, so neither the
		call	htfold		; stored case nor the probe case
		ld	c,a		; matters in insensitive mode
		ld	a,(hl)
		call	htfold
		cp	c
		jr	nz,htfind.differs
		inc	hl
		inc	de
		djnz	htfind.compare
		pop	hl		; MATCH (HL discarded - balance stack)
		; result: the cursor's offset advanced past
		;   HT_HEADER_SIZE + klen, to the payload
		ld	a,(probe_key_length)
		ld	l,a
		ld	h,0
		ld	de,HT_HEADER_SIZE
		add	hl,de
		ld	de,(walk_cursor+2)
		add	hl,de
		ld	(walk_cursor+2),hl
		ld	hl,walk_cursor
		ld	de,(result_buffer)
		ld	bc,4
		ldir
		or	a		; CY clear = found
		ret
htfind.differs:	pop	hl
htfind.next:	derefp	walk_cursor	; cursor = record.next: re-map (cache
		fpsave	walk_cursor	; hit); HL -> +0 = the next link - 
					; fpsave copies it out BEFORE
					; anything can remap the window
		jr	htfind.loop
htfind.miss:	scf
		ret

; htdelete - delete a key's record.
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

htdelete:	ld	(probe_key),de
		ld	(probe_key_length),a
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
		ld	(bucket_address),hl	; the bucket entry's address
		fpsave	walk_cursor	; cursor = bucket head
		ld	hl,NULL_OFFSET	; predecessor = null = "the bucket"
		ld	(previous_record+2),hl
htdelete.loop:	fpnull	walk_cursor	; end of chain -> not found
		jp	z,htdelete.miss
		derefp	walk_cursor	; HL -> record base (page 2)
		push	hl
		ld	de,HT_KEY_LENGTH
		add	hl,de
		ld	a,(probe_key_length)
		cp	(hl)
		pop	hl
		jp	nz,htdelete.next
		push	hl
		ld	de,HT_KEY
		add	hl,de
		ld	de,(probe_key)
		ld	a,(probe_key_length)
		ld	b,a
htdelete.compare:
		ld	a,(de)		; folded compare, as in htfind
		call	htfold
		ld	c,a
		ld	a,(hl)
		call	htfold
		cp	c
		jr	nz,htdelete.differs
		inc	hl
		inc	de
		djnz	htdelete.compare
		pop	hl		; MATCH (discard saved base)
		derefp	walk_cursor	; save the doomed record's next link
		fpsave	saved_next	; (cache hit) HL -> +0 = next
		fpnull	previous_record	; who points at the record?
		jr	nz,htdelete.unlink
		; head case: the bucket (low RAM) takes next
		ld	de,(bucket_address)
		ld	hl,saved_next
		ld	bc,4
		ldir
		jr	htdelete.release
htdelete.unlink:
		derefp	previous_record	; mid-chain: prev.next (page 2) = next
		ex	de,hl		; HL -> prev record +0
		ld	hl,saved_next	; (destination arrives in DE - no
		ld	bc,4		; macro)
		ldir
htdelete.release:
		ld	hl,walk_cursor	; free the record: its far pointer IS
		call	hfree		; a heap payload pointer
		or	a		; CY clear = deleted
		ret
htdelete.differs:
		pop	hl
htdelete.next:			; predecessor = current record
		fpcopy	previous_record,walk_cursor
		derefp	walk_cursor	; cursor = current.next: HL -> +0 =
		fpsave	walk_cursor	; the next link, copied out safely
		jp	htdelete.loop
htdelete.miss:	scf
		ret

; htclear - free every record and leave the table empty (reusable without
; a new htinit).
; The htdelete payload CAUTION applies to every record: free payload-referenced
; blocks first, e.g. by iterating with htnext before calling this.
;
; Input:	IX = descriptor
; Output:	all records freed, all buckets empty
; Modifies:	AF, BC, DE, HL (IX preserved)

htclear:	push	ix	; bucket_address = first bucket's address
		pop	hl
		ld	de,HT_TAB
		add	hl,de
		ld	(bucket_address),hl
		ld	l,(ix+HT_MASK)	; bucket count = mask+1
		ld	h,0
		inc	hl
		ld	(bucket_counter),hl
htclear.bucket:	ld	hl,(bucket_address)	; HL = the bucket's address...
		fpsave	walk_cursor	; ...cursor = this bucket's head
htclear.chain:	fpnull	walk_cursor	; chain done?
		jr	z,htclear.next_bucket
		derefp	walk_cursor	; save next BEFORE freeing: HL -> +0
		fpsave	saved_next
		ld	hl,walk_cursor
		call	hfree
		fpcopy	walk_cursor,saved_next	; cursor = next
		jr	htclear.chain
htclear.next_bucket:
		ld	hl,(bucket_address)	; null the bucket (4 x 0FFh)
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		inc	hl
		ld	(hl),0ffh
		ld	hl,(bucket_address)	; next bucket
		ld	de,4
		add	hl,de
		ld	(bucket_address),hl
		ld	hl,(bucket_counter)
		dec	hl
		ld	(bucket_counter),hl
		ld	a,h
		or	l
		jp	nz,htclear.bucket
		ret

; htnext - enumerate the records, one per call, in bucket order.
;
; The iterator is 5 caller-owned bytes:
;   +0     bucket number
;   +1..+4 far pointer to the current record
; START a walk with: +0 = 0 and the offset field (+3..+4) = FFFFh.
; After each CY-clear return, +1..+4 is the next record's far pointer - parse
; it with HT_KEY_LENGTH/HT_KEY/HT_HEADER_SIZE. Do not add or delete
; between the calls of one walk.
;
; Input:	IX = descriptor
;		HL = iterator address
; Output:	CY set   = no more records
;		CY clear = iterator updated
; Modifies:	AF, BC, DE, HL (IX preserved)

htnext:				; remember the iterator's address
		ld	(result_buffer),hl
		push	hl
		inc	hl		; HL -> its far pointer...
		fpsave	walk_cursor	; ...copied to scratch
		pop	hl
		ld	a,(hl)		; current bucket number
		ld	(bucket_counter),a
		fpnull	walk_cursor	; null fp -> scan for a non-empty
		jr	z,htnext.scan	; bucket, starting at this one
		derefp	walk_cursor	; follow the current record's next:
		fpsave	walk_cursor	; HL -> +0, copied out safly
		fpnull	walk_cursor	; chain continues -> answer found
		jr	nz,htnext.got
		ld	a,(bucket_counter)	; chain ended: next bucket
		cp	(ix+HT_MASK)
		jr	z,htnext.done
		inc	a
		ld	(bucket_counter),a
htnext.scan:	ld	a,(bucket_counter)	; HL = IX + HT_TAB + bucket*4
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		push	ix
		pop	de
		add	hl,de
		ld	de,HT_TAB
		add	hl,de
		fpsave	walk_cursor	; this bucket's head -> scratch
		fpnull	walk_cursor
		jr	nz,htnext.got	; non-empty -> answer found
		ld	a,(bucket_counter)	; empty -> next bucket or done
		cp	(ix+HT_MASK)
		jr	z,htnext.done
		inc	a
		ld	(bucket_counter),a
		jr	htnext.scan
htnext.got:			; write bucket + far pointer back
		ld	hl,(result_buffer)
		ld	a,(bucket_counter)
		ld	(hl),a
		inc	hl
		ex	de,hl
		ld	hl,walk_cursor
		ld	bc,4
		ldir
		or	a		; CY clear = a record is delivered
		ret
htnext.done:	scf
		ret

; htreplace - delete any existing record for the key, and add a new
; one.
; "Not present" is not an error - htreplace then behaves as htadd.
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

htreplace:	push	hl	; htdelete consumes DE/A and the scratch,
		push	bc	; so hold the htadd parameters on the
		push	de	; stack across it
		push	af
		call	htdelete	; CY (not found deliberately ignored)
		pop	af
		pop	de
		pop	bc
		pop	hl
		jp	htadd	; tail call - htadd's result is ours

; --- scratch area

		dseg

probe_key:	defs	2		; probe/new key address
probe_key_length:
		defs	1		; its length
add_payload_size:
		defs	2		; htadd: payload size
result_buffer:	defs	2		; caller's result-buffer address
bucket_address:	defs	2		; address of the hashed bucket
walk_cursor:	defs	4		; walk cursor (far pointer)
new_record:	defs	4		; new record (far pointer)
previous_record:
		defs	4		; htdelete: predecessor record (offset
					; FFFF = the bucket is the predecessor)
saved_next:	defs	4		; saved 'next' of a record being freed
bucket_counter:	defs	2		; bucket counter (htclear/htnext)
