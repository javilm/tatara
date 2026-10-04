; lobj.as - reading a Tatara object file, one record at a time.
;
; The file is read FORWARD ONLY. Both of the linker's passes are
; sequential, so nothing here seeks backwards and nothing buffers
; more than one field at a time - MSX-DOS does the buffering, and a
; record's fields are read as they are wanted.
;
; THE LENGTH FIELD IS WHAT MAKES THIS WORK. A record whose type this
; program does not know is skipped by its length without being
; understood, which is the property spec 5 is about and the dump in
; tanren.as demonstrates.

LOBJ_INCLUDED		equ	1	; skips the externals in lobj.inc

		public	objfile_open
		public	objfile_next_record
		public	objfile_read_payload
		public	objfile_read_string
		public	objfile_skip_record
		public	objfile_at_eof
		public	objfile_close
		public	objfile_record_type
		public	objfile_record_left
		public	objfile_string_buffer
		public	objfile_string_length
		public	objfile_bytes_read

		include	lobj.inc
		include	lerrs.inc
					; error_cannot_open,
					;   error_not_object_file,
					;   error_wrong_version,
					;   error_truncated
		include	msxdos.inc	; _OPEN, _READ, _SEEK, _CLOSE

		cseg

; read_bytes - HL bytes into DE: all of them, or carry.
;
;   MSX-DOS 2 answers a short read with the .EOF error AND the number
;   of bytes it did manage, so objfile_bytes_read is kept either way. The
;   difference between "nothing at all" and "one byte of a three-byte
;   header" is the difference between a file that ended and a file
;   that was cut, and objfile_next_record tells them apart by that count.
;
; Input:	HL = how many
;		DE -> where
; Output:	CY clear = all of them arrived
;		CY set   = fewer, or an error. objfile_bytes_read says how many
; Modifies:	AF, BC, DE, HL

read_bytes:
		ld	(bytes_wanted),hl
		ld	a,(file_handle)
		ld	b,a
		system	_READ		; -> A = error, HL = bytes read
					; BDOS gives the count either way
		ld	(objfile_bytes_read),hl
		or	a
		scf
		ret	nz
		ld	de,(bytes_wanted)
		or	a		; all of them?
		sbc	hl,de
		ret	z
		scf
		ret

; objfile_open - open the object file and check its header.
;
; Input:	DE -> the ASCIIZ filename
; Output:	the file is open (the three errors do not return)
; Modifies:	AF, BC, DE, HL

objfile_open:	ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error, B = handle
		or	a
		jp	nz,error_cannot_open
		ld	a,b
		ld	(file_handle),a
		ld	de,objfile_string_buffer
		ld	hl,5
		call	read_bytes
		jp	c,error_not_object_file	; a file too short to be one
		ld	a,(objfile_string_buffer)
		cp	"T"
		jp	nz,error_not_object_file
		ld	a,(objfile_string_buffer+1)
		cp	"R"
		jp	nz,error_not_object_file
		ld	a,(objfile_string_buffer+2)
		cp	"O"
		jp	nz,error_not_object_file
		ld	a,(objfile_string_buffer+3)
		cp	01ah		; the stopper, so TYPE prints "TRO"
		jp	nz,error_not_object_file	;   and stops
		ld	a,(objfile_string_buffer+4)
		cp	TRO_VERSION
		jp	nz,error_wrong_version	; a Tatara object, but not ours
		ret

; objfile_next_record - the next record's header.
;
; Input:	nothing
; Output: CY clear = objfile_record_type and objfile_record_left describe a
; record
;		CY set   = the file ended cleanly, after the last one
;		(error_truncated does not return)
; Modifies:	AF, BC, DE, HL

objfile_next_record:
		ld	de,objfile_string_buffer
		ld	hl,3
		call	read_bytes
		jr	nc,objfile_next_record.got
					; nothing at all is a clean end;
		ld	hl,(objfile_bytes_read)
		ld	a,h		;   one or two bytes is a header
		or	l		;   that was cut in half
		jp	nz,error_truncated
		scf
		ret
objfile_next_record.got:
		ld	a,(objfile_string_buffer)
		ld	(objfile_record_type),a
		ld	hl,(objfile_string_buffer+1)
		ld	(objfile_record_left),hl
		or	a		; CY clear: a record is open
		ret

; objfile_read_payload - A bytes of the open record's payload.
;
;   TWO CHECKS, and they catch different lies. read_bytes catches a file
;   that is shorter than the record says; the subtraction catches a
;   record that says less than its fields need.
;
; Input:	A  = how many, 1 to 255
;		DE -> where they go
; Output:	they are there, and objfile_record_left is that much smaller
;		(error_truncated does not return)
; Modifies:	AF, BC, DE, HL

objfile_read_payload:
		ld	l,a
		ld	h,0
		ld	(payload_count),hl
		call	read_bytes		; DE is already where they go
		jp	c,error_truncated
		ld	hl,(objfile_record_left)
		ld	de,(payload_count)
		or	a
		sbc	hl,de
		jp	c,error_truncated
		ld	(objfile_record_left),hl
		ret

; objfile_read_string - one string: a length byte, then that many bytes.
;
;   Zero-terminated in objfile_string_buffer, because everything that prints a
;   name here goes through print_zero_string. A length of 0 is forbidden by the
;   format (spec 8), so it is a broken file and not an empty name.
;
; Input:	nothing
; Output: objfile_string_buffer holds it, objfile_string_length is its length
; Modifies:	AF, BC, DE, HL

objfile_read_string:
		ld	de,objfile_string_length
		ld	a,1
		call	objfile_read_payload
		ld	a,(objfile_string_length)
		or	a
		jp	z,error_truncated
		ld	de,objfile_string_buffer
		call	objfile_read_payload		; A is still the length
		ld	hl,objfile_string_buffer
		ld	a,(objfile_string_length)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	(hl),0
		ret

; objfile_skip_record - whatever is left of the open record.
;
;   A FORWARD SEEK. "Sequential, no backward seeking" forbids going
;   back, not going on, and reading tatara.tro's DATA records into a
;   buffer to throw them away would move six kilobytes for nothing.
;
; Input:	nothing
; Output:	the record is consumed (error_truncated does not return)
; Modifies:	AF, BC, DE, HL

objfile_skip_record:
		ld	hl,(objfile_record_left)
		ld	a,h
		or	l
		ret	z		; nothing left: END is like this
					; DE:HL = how far, DE THE HIGH WORD.
		ld	hl,(objfile_record_left)
		ld	de,0		;   The other way round asks for a
					;   seek of 12 * 65536, which MSX-DOS
					;   grants by stopping at the end of
					;   the file - no error, and the next
					;   read says the records ran out
		ld	a,(file_handle)
		ld	b,a
		ld	a,1		; 1 = from where we are
		system	_SEEK
		or	a
		jp	nz,error_truncated
		ld	hl,0
		ld	(objfile_record_left),hl
		ret

; objfile_at_eof - after the last record, is that the end of the file?
;
;   One byte is asked for. Getting it means something follows the END
;   record, which is legal (spec 11 says a reader ignores it) but
;   worth saying out loud, because for Tatara's own writer it would
;   mean a length that did not add up.
;
; Input:	nothing
; Output:	CY clear = the file ends exactly here
;		CY set   = at least one byte follows
; Modifies:	AF, BC, DE, HL

objfile_at_eof:
		ld	de,objfile_string_buffer
		ld	hl,1
		call	read_bytes
		ccf			; read_bytes's carry means NOTHING was
		ret			;   there, which is the good answer

; objfile_close - done with the file.
;
; Input:	nothing
; Output:	the handle is closed
; Modifies:	AF, BC

objfile_close:	ld	a,(file_handle)
		ld	b,a
		system	_CLOSE
		ret

		dseg

file_handle:	defs	1	; MSX-DOS's handle for the object file
objfile_record_type:
		defs	1	; the open record's type
					; and how much of its payload is unread
objfile_record_left:
		defs	2
bytes_wanted:	defs	2	; read_bytes: how many bytes were asked for,
objfile_bytes_read:
		defs	2	;   and how many came back
					; objfile_read_payload: this call's
					; count
payload_count:
		defs	2
					; objfile_read_string: the length byte
					; it just read
objfile_string_length:
		defs	1
					; and the string itself, terminated
objfile_string_buffer:
		defs	OBJFILE_STRING_SIZE
