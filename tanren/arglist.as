; arglist.as - the words a program was asked to work on, and where
; they came from.
;
; ONE LIST, IN THE MAPPER. The command tail is split into words once;
; a word beginning with "@" is a file, whose words are split by the
; same code and appended in its place. After that nothing downstream
; knows which came from where - and the linker's two passes walk the
; same list twice, which is what the command tail once had to stay
; still for.
;
; NOTHING USED TO BE STORED, on the grounds that the tail sits at
; 0080h and walking it again is free. That was true and stopped being
; true here: a file would have to be re-opened and re-parsed for pass
; 2, interleaved with the tail in the same order, twice. The reversal
; is D3.
;
; NOTHING HERE KNOWS WHAT A WORD MEANS. That is lcmd.as's business,
; and this module would serve cmdline.as unchanged on the day the
; assembler wants it.

ARGLIST_INCLUDED	equ	1	; skips the externals in arglist.inc

		public	split_command_tail
		public	read_response_file
		public	arglist_add
		public	arglist_first
		public	arglist_next
		public	arglist_count
		public	tail_truncated
		public	response_file_name
		public	response_file_directory
		public	word_from_file

		include	arglist.inc
		include	lerrs.inc
					; error_out_of_memory,
					;   error_too_many_words,
					;   error_cannot_open_list,
					;   error_nested_file_list,
					;   error_two_file_lists
		include	alloc.inc	; halloc, deref
		include	farptr.inc	; derefp
		include	strutil.inc	; add_default_extension
		include	msxdos.inc	; _OPEN, _READ, _CLOSE

TAIL_LENGTH	equ	00080h		; command tail: the length byte
TAIL_TEXT	equ	00081h		; command tail: the text
TAIL_MAX	equ	127		; and all of it there can ever be.
					; MSX-DOS cuts a longer line HERE,
					; in silence, which is what [R10]
					; exists to answer

		cseg

; split_command_tail - the command tail, as words.
;
;   ONE PASS, ONE CHARACTER AT A TIME. A space or a tab ends the word
;   being built and anything else belongs to it, so the word
;   boundaries fall out rather than being searched for.
;
; Input:	nothing (0080h)
; Output:	the list holds every word, @FILEs expanded
;		(the four errors do not return)
; Modifies:	everything

split_command_tail:
		call	arglist_init
		xor	a
		ld	(response_file_open),a
		ld	(word_length),a
		ld	(tail_truncated),a
		ld	a,(TAIL_LENGTH)
		cp	TAIL_MAX
		jr	c,split_command_tail.word
		; AT THE LIMIT, so it may have been cut.
		;   print_truncation_warning says so
		ld	a,0ffh
		ld	(tail_truncated),a
split_command_tail.word:
		ld	hl,TAIL_TEXT
		ld	a,(TAIL_LENGTH)
		ld	b,a
split_command_tail.loop:
		ld	a,b
		or	a
		jp	z,word_finish	; the tail does not end with a
		ld	a,(hl)		;   space, so the last word has to
		inc	hl		;   be finished here
		dec	b
		cp	" "
		jr	z,split_command_tail.space
		cp	009h
		jr	z,split_command_tail.space
		push	hl
		push	bc
		call	word_add_char
		pop	bc
		pop	hl
		jr	split_command_tail.loop
split_command_tail.space:
		push	hl
		push	bc
		call	word_finish
		pop	bc
		pop	hl
		jr	split_command_tail.loop

; arglist_init - the block the words live in.
;
; Input:	nothing
; Output:	an empty list (error_out_of_memory does not return)
; Modifies:	AF, BC, DE, HL

arglist_init:	ld	bc,ARGLIST_BLOCK_SIZE
		ld	hl,list_block
		call	halloc
		jp	c,error_out_of_memory
		ld	hl,0
		ld	(list_used),hl
		ld	(arglist_count),hl
		ld	(walk_offset),hl
		; no response file has been read, and an empty range answers
		;   "no" to every word - see word_came_from_file
		ld	(response_first),hl
		ld	(response_last),hl
		xor	a
		ld	(word_from_file),a
		ld	(response_file_directory),a
		ret

; word_add_char - one character onto the word being built.
;
; Input:	A = the character
; Output:	it is in word_buffer (error_too_many_words does not return)
; Modifies:	AF, BC, DE, HL

word_add_char:	ld	c,a	; THE CHARACTER, AND NOT IN E: word_buffer's
		ld	a,(word_length)	;   address is about to go into DE,
		cp	ARGLIST_WORD_MAX-1	;   and E with it
		; a word longer than a path can be
		jp	nc,error_too_many_words
		ld	hl,word_buffer
		ld	e,a
		ld	d,0
		add	hl,de
		ld	(hl),c
		inc	a		; A is still word_length
		ld	(word_length),a
		ret

; word_finish - the word being built is finished.
;
;   IT FORGETS THE WORD BEFORE HANDING IT OVER, because word_store may
;   open a response file and that file's words are built in this same
;   buffer. word_store has taken what it needs by then.
;
; Input:	word_buffer, word_length
; Output:	the word is in the list, or was a file that has been
;		read
; Modifies:	everything

word_finish:	ld	a,(word_length)
		or	a
		ret	z		; two spaces in a row
		ld	l,a
		ld	h,0
		ld	de,word_buffer
		add	hl,de
		ld	(hl),0		; terminate it
		xor	a
		ld	(word_length),a
		jp	word_store

; word_store - what a finished word is.
;
; Input:	word_buffer, ASCIIZ
; Output:	it is in the list, or its file has been read
;		(error_nested_file_list, error_cannot_open_list do not return)
; Modifies:	everything

word_store:	ld	a,(word_buffer)
		cp	RESPONSE_FILE_CHAR
		jr	z,word_store.file
		ld	de,word_buffer
		jp	arglist_add
word_store.file:
		ld	a,(response_file_open)
		or	a
		; @ INSIDE a response file: refused
		jp	nz,error_nested_file_list
		; AND ONLY ONE ON THE COMMAND LINE. Two were accepted and read,
		;   and then the objects named in the FIRST were looked for in
		;   the SECOND's directory, because response_file_directory,
		;   response_first and response_last hold one file's answer -
		;   issue #23. 063 settled "one level, stated" for nesting;
		;   this is its sibling, and the same answer
		ld	a,(response_file_read)
		or	a
		jp	nz,error_two_file_lists
		ld	a,0ffh
		ld	(response_file_read),a
		ld	hl,word_buffer+1	; the name, without the @
		ld	de,response_file_name
word_store.copy:
		ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,word_store.done
		inc	hl
		inc	de
		jr	word_store.copy
word_store.done:
		ld	a,(response_file_name)
		or	a
		; "@" and nothing after it
		jp	z,error_cannot_open_list
		ld	de,response_file_name
		ld	hl,msg_lnk_extension
		call	add_default_extension	; ".lnk", unless it has one
		jp	read_response_file

; arglist_add - one word, into the list.
;
; Input:	DE -> the word, ASCIIZ
; Output:	the list holds it (error_too_many_words does not return)
; Modifies:	AF, BC, DE, HL

arglist_add:	ld	(add_source),de
		ex	de,hl
		ld	bc,0		; how long it is, terminator and all
arglist_add.copy:
		ld	a,(hl)
		inc	hl
		inc	bc
		or	a
		jr	nz,arglist_add.copy
		ld	(add_length),bc
		ld	hl,(list_used)	; would it pass the end?
		add	hl,bc
		ld	de,ARGLIST_BLOCK_SIZE
		ex	de,hl
		or	a
		sbc	hl,de
		jp	c,error_too_many_words
		ld	bc,(list_used)	; THE OFFSET IN BC, which survives
		derefp	list_block	;   the deref
		add	hl,bc
		ex	de,hl		; DE -> where it goes in the block
		ld	hl,(add_source)
		ld	bc,(add_length)
		ldir
		ld	hl,(list_used)
		ld	bc,(add_length)
		add	hl,bc
		ld	(list_used),hl
		ld	hl,(arglist_count)
		inc	hl
		ld	(arglist_count),hl
		ret

; arglist_first, arglist_next - the list, one word at a time.
;
; Input:	arglist_next: DE -> where the word goes, ARGLIST_WORD_MAX bytes
; Output:	arglist_next: CY set = there are no more
; Modifies:	AF, BC, DE, HL

arglist_first:	ld	hl,0
		ld	(walk_offset),hl
		ret

; word_came_from_file - did the word at walk_offset come from a file?
;
;   THE RANGE IS ONE CONTIGUOUS SPAN, which is what makes this work
;   at all: ONE file list may be given and it may not name another,
;   so there is exactly one, its words are appended where the "@"
;   appeared, and nothing is ever inserted in front of them.
;
;   THE SECOND HALF OF THAT WAS MISSING UNTIL 093, and this comment
;   named only the nesting rule - which was true, and not enough. Two
;   lists on one command line overwrote response_file_directory,
;   response_first and response_last, and the first file's objects
;   were then looked for in the second file's directory. Issue #23.
;
;   With no response file read the range is 0 to 0, and every word is
;   "at or past its end", so the answer is always no.
;
; Input:	walk_offset, response_first, response_last
; Output:	word_from_file
; Modifies:	AF, DE, HL

word_came_from_file:
		ld	hl,(walk_offset)
		ld	de,(response_first)
		or	a
		sbc	hl,de
		jr	c,word_came_from_file.no	; before it starts
		ld	hl,(walk_offset)
		ld	de,(response_last)
		or	a
		sbc	hl,de
		jr	nc,word_came_from_file.no	; at or past its end
		ld	a,0ffh
		ld	(word_from_file),a
		ret
word_came_from_file.no:
		xor	a
		ld	(word_from_file),a
		ret

arglist_next:	ld	(walk_target),de
		ld	hl,(walk_offset)
		ld	de,(list_used)
		or	a
		sbc	hl,de
		jr	c,arglist_next.word
		scf
		ret			; the list is used up
arglist_next.word:
		; did this word come from the file?
		call	word_came_from_file
		ld	bc,(walk_offset)
		derefp	list_block
		add	hl,bc
		ld	de,(walk_target)
		ld	bc,0
arglist_next.copy:
		ld	a,(hl)		; OUT OF THE MAPPER AND INTO RAM
		ld	(de),a		;   with no BDOS call between, which
		inc	hl		;   is the rule every walk in this
		inc	de		;   program obeys
		inc	bc
		or	a
		jr	nz,arglist_next.copy
		ld	hl,(walk_offset)
		add	hl,bc
		ld	(walk_offset),hl
		or	a		; CY clear: there was one
		ret

; read_response_file - one response file's words, appended to the list.
;
;   THE NAME COMES IN THROUGH response_file_name AND NOT A REGISTER, so that
;   error_cannot_open_list can print the file it could not open.
;   error_cannot_open reads object_name for the same reason.
;
; Input:	response_file_name, ASCIIZ
; Output:	its words are in the list
;		(error_cannot_open_list does not return)
; Modifies:	everything

read_response_file:
		ld	de,response_file_name
		ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error, B = handle
		or	a
		jp	nz,error_cannot_open_list
		ld	a,b
		ld	(response_file_handle),a
		; WHERE THIS FILE LIVES, for the objects it names
		ld	de,response_file_name
		call	directory_length
		ld	hl,response_file_name
		ld	de,response_file_directory
		or	a
		jr	z,read_response_file.named
		ld	c,a
		ld	b,0
		ldir
read_response_file.named:
		xor	a
		ld	(de),a
		ld	hl,(list_used)	; and where its words begin
		ld	(response_first),hl
		ld	hl,0
		ld	(response_got),hl
		ld	(response_at),hl
		ld	a,0ffh
		ld	(response_file_open),a	; @ inside this one is an error
		xor	a
		ld	(word_length),a
read_response_file.loop:
		call	read_response_char
		jr	c,read_response_file.done
		cp	RESPONSE_COMMENT_CHAR
		jr	z,read_response_file.comment
		cp	" "
		jr	z,read_response_file.space
		cp	009h
		jr	z,read_response_file.space
		cp	00dh
		jr	z,read_response_file.space
		cp	00ah
		jr	z,read_response_file.space
		call	word_add_char
		jr	read_response_file.loop
read_response_file.space:
		call	word_finish
		jr	read_response_file.loop
read_response_file.comment:
		call	word_finish	; a comment ends the word too
read_response_file.close:
		call	read_response_char	; and runs to end of line
		jr	c,read_response_file.done
		cp	00ah
		jr	nz,read_response_file.close
		jr	read_response_file.loop
read_response_file.done:
		call	word_finish	; A FILE MAY NOT END WITH A NEWLINE
		ld	hl,(list_used)	; and where its words end
		ld	(response_last),hl
		xor	a
		ld	(response_file_open),a
		ld	a,(response_file_handle)
		ld	b,a
		system	_CLOSE
		ret

; read_response_char - the next character of the response file.
;
; Input:	nothing
; Output:	A = the character
;		CY set = the file has ended
; Modifies:	AF, BC, DE, HL

read_response_char:
		ld	hl,(response_at)
		ld	de,(response_got)
		or	a
		sbc	hl,de
		; still some in the buffer
		jr	c,read_response_char.got
		ld	hl,RESPONSE_CHUNK_SIZE
		ld	de,response_buffer
		ld	a,(response_file_handle)
		ld	b,a
		system	_READ		; -> A = error, HL = bytes read
		ld	(response_got),hl
		ld	a,h
		or	l
		scf
		ret	z		; nothing came back: the end
		ld	hl,0
		ld	(response_at),hl
read_response_char.got:
		ld	hl,response_buffer
		ld	bc,(response_at)
		add	hl,bc
		ld	a,(hl)
		cp	01ah		; THE STOPPER. Every file this
		scf			;   project writes ends with one,
		ret	z		;   and a response file will too
		; THE CHARACTER FIRST: response_at is about to move, and (hl)
		;   with it
		ld	(response_char),a
		ld	hl,(response_at)
		inc	hl
		ld	(response_at),hl
		ld	a,(response_char)
		or	a		; CY clear: a real character
		ret

		dseg

list_block:	defs	4	; the block the words live in
list_used:	defs	2	; how much of it is used,
arglist_count:	defs	2	;   and how many words that is
walk_offset:	defs	2	; arglist_next: how far the walk has got.
				;   NOT argat: RESPONSE_FILE_CHAR is the
				;   "@" and SOLiD folds case, so the two
				;   would be one symbol
walk_target:	defs	2	;   and where it is putting them
add_source:	defs	2	; arglist_add: the word, across the deref,
add_length:	defs	2	;   and how long it is
word_buffer:	defs	ARGLIST_WORD_MAX	; the word being built,
word_length:	defs	1	;   and how much of it there is
response_file_name:
		defs	ARGLIST_WORD_MAX	; the response file being read
response_file_open:
		defs	1	; 0FFh while one is open,
response_file_handle:
		defs	1	;   and its handle
response_file_read:
		defs	1	; 0FFh once one has been READ, which is
				;   not the same thing: response_file_open
				;   is clear again afterwards. A BYTE AND
				;   NOT A TEST OF response_last, because a
				;   file holding only comments leaves
				;   response_first and response_last equal -
				;   and equal to zero, if the @ came first
response_buffer:
		defs	RESPONSE_CHUNK_SIZE	; what has been read of it,
response_got:	defs	2	;   how much came back,
response_at:	defs	2	;   and how far through it we are
response_char:	defs	1	; one character, across that pointer
tail_truncated:	defs	1	; 0FFh = the tail was 127 characters
response_file_directory:
		defs	DOS_PATH_MAX	; the directory the response file lives
				;   in, for the objects it names
response_first:	defs	2	; the range of list offsets its words
response_last:	defs	2	;   occupy - ONE contiguous span, because
				;   a file list may not name another
word_from_file:	defs	1	; 0FFh = the word arglist_next just handed out
				;   started inside that range

msg_lnk_extension:
		defb	".lnk",0	; what a response file gets
