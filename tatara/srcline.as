; srcline.as - where source lines come from.
;
; A small stack of "line sources" in ordinary RAM. the entry on top is the
; one being read; when it runs out it is removed and the one underneath
; carries on where it left off. In this phase the only kind of source is a 
; file being read; macro expansions and repeat blocks are added later.

SRCLINE_INCLUDED	equ	1	; skips the externals in scrline.inc

		public	source_init
		public	push_file
		public	push_macro
		public	pop_source
		public	source_depth
		public	source_top
		public	get_filename
		public	source_open
		public	entry_address	; errs.as walks the stack with it to
					;   print the origin trail
		public	file_line
		public	next_source_line
		public	current_file
		public	current_line
		public	pass_number

		include	srcline.inc
		include	strutil.inc
			; is_absolute_name, directory_length, compose_path
		include	msxdos.inc
		include	ascii.inc
		include	errs.inc
		include	expand.inc
				; expand_line: the next line of an expansion

		cseg

; source_init - start with no line sources and no file names at all.
;
; Input:	nothing
; Output:	the stack and the name table are empty
; Modifies:	AF

source_init:	xor	a
		ld	(source_depth),a
		ld	(files_open),a
		ld	(names_used),a
		ld	(env_read),a	; TATARA has not been looked up
		ld	(current_file),a
		ld	(current_line),a
		ld	(current_line+1),a
		ret

; entry_address - work out where the entry for stack level A lives.
;
;   entry = source_stack + A*16, which is four doublings and an add.
;
; Input:	A = level, 0 = the bottom of the stack
; Output:	HL -> the entry
; Modifies:	AF, DE, HL

entry_address:	ld	l,a
		ld	h,0
		add	hl,hl		; x2
		add	hl,hl		; x4
		add	hl,hl		; x8
		add	hl,hl		; x16 = SOURCE_ENTRY_SIZE
		ld	de,source_stack
		add	hl,de
		ret

; buffer_address - work out where file buffer number A lives.
;
;   buffer = file_buffers + A*512: A*2 in the high byte, 0 in the low byte.
;
;   Numbered by open files, not by stack level: macro expansions read from
;   mapper RAM and use no buffer at all.
;
; Input:	A = buffer number, 0 = the first
; Output:	DE -> the buffer
; Modified:	AF, DE, HL

buffer_address:	add	a,a		; x2 -> whoel 256-byte pages
		ld	d,a
		ld	e,0		; DE = A * 512 = A * FILE_CHUNK_SIZE
		ld	hl,file_buffers
		add	hl,de
		ex	de,hl
		ret

; push_file - open a file and make it the source lines now come from.
;
;   Nothing is read from disk here: the entry starts with an empty buffer
;   and the first read happens when a line is actually asked for.
;
; Input:	DE -> filename, zero-terminated
; Output:	CY clear = open and on top of the stack
;		CY set   = MSX-DOS wouldn't open it
;		(nesting too deep does not return - error_source_too_deep
;		stops)
; Modifies:	AF, BC, DE, HL, IX

push_file:	ld	a,(source_depth)
		cp	SOURCE_STACK_MAX
		jp	nc,error_source_too_deep	; no room on the stack
		ld	a,(files_open)
		cp	OPEN_FILE_MAX
		jp	nc,error_too_many_open
					; no buffer for another open file
		ld	(push_name),de	; keep the name: BDOS may change DE
		ld	a,1		; open mode 1 = read only
		system	_OPEN		; -> A = error (0 = fine), B = handle
		or	a
		scf
		ret	nz		; could not open it
		ld	a,b
		ld	(push_handle),a	; the handle to read from
		ld	de,(push_name)
		call	add_filename	; -> A = the number this name got
		ld	(push_file_number),a
		ld	de,(push_name)	; and WHICH DIRECTORY it came from,
		ld	a,(files_open)	;   for any INCLUDE inside it. Indexed
		; like the buffers, and files_open has
		call	remember_source_directory
					;   not been stepped yet

		ld	a,(source_depth)
		call	entry_address	; HL -> the new entry
		ld	(source_top),hl
		push	hl
		pop	ix		; IX -< the entry, for the fields below
		ld	a,(files_open)
		call	buffer_address	; DE -> this file's buffer
		ld	(ix+SOURCE_KIND),SOURCE_IS_FILE
		ld	a,(push_handle)
		ld	(ix+SOURCE_HANDLE),a
		ld	a,(push_file_number)
		ld	(ix+SOURCE_FILE_NUMBER),a
		ld	(ix+SOURCE_LINE),0	; no line handed over yet
		ld	(ix+SOURCE_LINE+1),0
		ld	(ix+SOURCE_BUFFER),e	; this level's buffer
		ld	(ix+SOURCE_BUFFER+1),d
		; read position = start of buffer
		ld	(ix+SOURCE_READ_AT),e
		ld	(ix+SOURCE_READ_AT+1),d
		ld	(ix+SOURCE_LEFT),0	; with nothing in it yet
		ld	(ix+SOURCE_LEFT+1),0
		ld	(ix+SOURCE_EOF),0	; and not finished

		ld	a,(files_open)	; one more file open, one more buffer
		inc	a		; in use
		ld	(files_open),a
		ld	a,(source_depth)
		inc	a
		ld	(source_depth),a
		or	a		; clears CY = success
		ret

; source_open - open an INCLUDEd file, looking in more than one place.
;
;   THE INCLUDING FILE'S DIRECTORY COMES FIRST, and not the current
;   directory. A B.INC sitting next to the file that asks for it must
;   win over an unrelated B.INC in whatever directory the assembler
;   happened to be started from. That is the fault - a second copy
;   somewhere the search order prefers - in a place where it would be
;   far quieter: the wrong file would assemble, and the complaint, if
;   any, would surface somewhere else entirely.
;
;   The current directory stays in the list, second, where it can only
;   be reached if the including file's own directory did not have the
;   file - so it can never shadow the right answer.
;
;   AN ABSOLUTE NAME IS OPENED AS TYPED AND NOWHERE ELSE. A name that
;   says which drive and which directory is not asking to be searched
;   for.
;
;   A candidate that would exceed DOS_PATH_MAX is skipped and not an error:
;   it is one of several, and a later one may well open. If none does,
;   the caller's "cannot open" names the file and prints the trail.
;
; Input:	DE -> the name as written, ASCIIZ
; Output:	CY clear = open and on top of the stack
;		CY set   = not found in any of them
; Modifies:	AF, BC, DE, HL, IX

source_open:	ld	(open_name),de
		call	is_absolute_name	; strutil.as owns these now
		jr	nc,source_open.relative
		ld	de,(open_name)
		jp	push_file	; absolute: this or nothing

source_open.relative:
		ld	a,(files_open)	; 1 - the including file's directory
		or	a
		; nothing open: there is no includer
		jr	z,source_open.current
		dec	a		; the innermost OPEN FILE, which is
		; not the top of the stack if a
		call	source_directory_address
					;   macro is expanding (D9)
		ld	de,(open_name)
		call	compose_path
		jr	c,source_open.current	; too long to be worth trying
		ld	de,path_buffer
		call	push_file
		ret	nc

source_open.current:
		ld	de,(open_name)	; 2 - as typed: the current directory
		call	push_file
		ret	nc

		call	read_env_path	; 3 - each entry of TATARA in turn
		ld	hl,env_path
source_open.env:
		ld	a,(hl)
		or	a
		scf
		ret	z		; the list is used up: not found
		ld	de,(open_name)
		call	compose_path	; -> HL at this entry's terminator
		jr	c,source_open.env_next	; too long: on to the next
		push	hl
		ld	de,path_buffer
		call	push_file
		pop	hl
		ret	nc
source_open.env_next:
		ld	a,(hl)		; HL is at the ";" or at the end
		or	a
		scf
		ret	z		; that was the last entry
		inc	hl		; past the ";"
		jr	source_open.env

; remember_source_directory - remember which directory an opening came from.
;
;   Called from push_file with the open already done, so the name is one
;   MSX-DOS accepted and is therefore inside DOS_PATH_MAX.
;
;   Everything up to and INCLUDING the last "\" or ":" is the
;   directory. A name with neither leaves an empty string, which
;   compose_path then treats as the current directory - which is exactly
;   what it means.
;
;   INDEXED BY files_open, like the read buffers and for the same reason:
;   pop_source closes files in the order they were opened, so the two are
;   one stack.
;
; Input:	DE -> the name that was opened, ASCIIZ
;		A   = files_open, before push_file steps it
; Output:	include_dirs slot A holds the directory
; Modifies:	AF, BC, DE, HL

remember_source_directory:
		push	de
		call	source_directory_address	; HL -> the slot
		pop	de
		push	hl
		call	directory_length
					; A = how much of it is directory
		pop	hl
		ex	de,hl		; HL -> the name, DE -> the slot
		or	a
		; no separator: an empty directory
		jr	z,remember_source_directory.done
		ld	c,a
		ld	b,0
		ldir
remember_source_directory.done:
		xor	a
		ld	(de),a
		ret

; source_directory_address - address of open file A's directory (A *
; DOS_PATH_MAX)
;
; Input:	A = which open file, 0 = the first
; Output:	HL -> its slot in include_dirs
; Modifies:	AF, DE, HL

source_directory_address:
		ld	l,a
		ld	h,0
		add	hl,hl		; x2
		add	hl,hl		; x4
		add	hl,hl		; x8
		add	hl,hl		; x16
		add	hl,hl		; x32
		add	hl,hl		; x64 = DOS_PATH_MAX
		ld	de,include_dirs
		add	hl,de
		ret

; read_env_path - fetch TATARA's value, once.
;
;   ONCE, AND FAILURES COUNT AS DONE. An assembly with forty includes
;   must not ask MSX-DOS forty times, and a machine with no such
;   variable must not be asked at all after the first time.
;
;   Under MSX-DOS 1 there are no environment variables, so the buffer
;   stays empty and the search simply has one place fewer to look - a
;   subdirectory layout still works there, as long as the includes are
;   written relative to the including file.
;
;   _GENV TRUNCATES WITHOUT A TERMINATOR when the buffer is too small,
;   and says ERR_ELONG. A search path that is quietly shorter than what
;   was set is worse than no search path, so that is an error.
;
; Input:	nothing
; Output:	env_path holds the value, or is empty
; Modifies:	AF, BC, DE, HL

read_env_path:	ld	a,(env_read)
		or	a
		ret	nz		; asked once already
		ld	a,1
		ld	(env_read),a
		xor	a
		ld	(env_path),a	; empty unless proved otherwise
		call	dos_version
		ret	c		; MSX-DOS 1: there are none
		ld	hl,msg_env_name
		ld	de,env_path
		ld	b,ENV_VALUE_MAX
		system	_GENV
		or	a
		ret	z		; the value is in the buffer
		cp	ERR_ELONG
		jp	z,error_env_too_long
		xor	a
		ld	(env_path),a	; any other refusal: no path
		ret

msg_env_name:	defb	"TATARA",0	; MSX-DOS upper-cases a variable's
					;   name when it is set and compares
					;   without case, so this spelling is
					;   the whole of it

; push_macro - make a macro expansion the source lines now come from.
;
;   Note what is NOT here: no file is opened, and files_open is not touched.
;   An expansion reads from mapper RAM and needs no buffer, which is why
;   the buffers are indexed by how many FILES are open rather than by
;   deep the stack is.
;
; Input:	HL -> the expansion record's far pointer
; 		A   = the file the definition came from (MACRO_DEF_FILE)
; Output:	CY clear = it is on top of the stack
;		(too deep does not return - error_source_too_deep stops)
; Modifies:	AF, BC, DE, HL, IX

push_macro:	ld	(push_expansion),hl
		ld	(push_expansion_file),a
		ld	a,(source_depth)
		cp	SOURCE_STACK_MAX
		jp	nc,error_source_too_deep
					; almost always runaway recursion

		ld	a,(source_depth)
		call	entry_address	; HL -> the new entry
		ld	(source_top),hl
		push	hl
		pop	ix
		ld	(ix+SOURCE_KIND),SOURCE_IS_MACRO
		ld	a,(push_expansion_file)
		; where the DEFINITION came from
		ld	(ix+SOURCE_FILE_NUMBER),a
		ld	(ix+SOURCE_LINE),0	; no body line delivered yet
		ld	(ix+SOURCE_LINE+1),0
		ld	(ix+SOURCE_EOF),0

		push	ix	; the far pointer goes in SOURCE_EXPANSION
		pop	de
		ld	hl,SOURCE_EXPANSION
		add	hl,de
		ex	de,hl		; DE -> SOURCE_EXPANSION in the entry
		ld	hl,(push_expansion)
		ld	bc,4
		ldir

		ld	a,(source_depth)
		inc	a
		ld	(source_depth),a
		or	a		; clears CY = pushed
		ret

; pop_source - remove the top line source, closing its file if it had one.
;
; Input:	nothing
; Output:	source_depth and source_top updated
; Modifies:	AF, BC, DE, HL, IX

pop_source:	ld	a,(source_depth)
		or	a
		ret	z		; nothing stacked - nothing to do
		dec	a
		ld	(source_depth),a
		call	entry_address	; HL -> the entry being removed
		push	hl
		pop	ix
		ld	a,(ix+SOURCE_KIND)
		cp	SOURCE_IS_FILE
		; other kinds have no file to close
		jr	nz,pop_source.update
		ld	b,(ix+SOURCE_HANDLE)
		system	_CLOSE
		ld	a,(files_open)	; its buffer is free again. Files are
		dec	a		; always closed in the reverse order
		ld	(files_open),a	; they were opened, so this is enough
pop_source.update:
		ld	a,(source_depth)
		or	a
		ret	z		; the stack is empty now
		dec	a
		call	entry_address	; HL -> the entry underneath
		ld	(source_top),hl
		ret

; add_filename - remember a file name so messages can print it, and give it a
;   number. The same file opened twice gets two numbers on purpose: that
;   keeps the two openings apart in an error trail.
;
; Input:	DE -> filename, zero-terminated
; Output:	A = the number given to this name
; Modifies:	AF, BC, DE, HL

add_filename:	ld	a,(names_used)
		cp	FILE_NAMES_MAX
		jp	nc,error_too_many_sources
					; more names than the table holds
		push	af
		call	filename_address	; HL -> this number's slot
		ex	de,hl		; DE -> the slot, HL -> the name
		ld	bc,FILE_NAME_MAX
add_filename.copy:
		ld	a,(hl)
		ld	(de),a
		or	a
		jr	z,add_filename.done	; copied the terminator too
		inc	hl
		inc	de
		dec	bc
		ld	a,b
		or	c
		jr	nz,add_filename.copy
		dec	de
		xor	a
		ld	(de),a		; too long: force a terminator back in
add_filename.done:
		pop	af		; A = the number this name got
		push	af
		inc	a
		ld	(names_used),a
		pop	af
		ret

; get_filename - find the name that goes with a file number.
;
; Input:	A = file number
; Output:	DE -> the name, zero-terminated
; Modifies:	AF, HL

get_filename:	call	filename_address
		ex	de,hl
		ret

; filename_address - address of file number A in the name table (A *
; FILE_NAME_MAX)
;
; Input:	A = file number
; Output:	HL -> that number's slot
; Modifies:	AF, DE, HL

filename_address:
		ld	l,a
		ld	h,0
		add	hl,hl		; x2
		add	hl,hl		; x4
		add	hl,hl		; x8
		add	hl,hl		; x16
		add	hl,hl		; x32 = FILE_NAME_MAX. ONE SHIFT PER
					;   DOUBLING, so this chain and the
					;   equate move together or the table
					;   tears
		push	de
		ld	de,filename_table
		add	hl,de
		pop	de
		ret

; file_refill - refill this file's buffer from disk.
;
;   Nothing else in the module talks to MSX-DOS.
;
; Input:	IX -> a line source entry of the file kind
; Output:	CY clear = the buffer holds fresh bytes
;		CY set   = nothing more to read; the entry is marked
;                          finished
; Modifies:	AF, BC, DE, HL

file_refill:	ld	b,(ix+SOURCE_HANDLE)
		ld	e,(ix+SOURCE_BUFFER)
		ld	d,(ix+SOURCE_BUFFER+1)
		ld	hl,FILE_CHUNK_SIZE
		system	_READ		; -> A = error, HL = bytes read
		or	a
		; any error, end of file included
		jr	nz,file_refill.empty
		ld	a,h
		or	l
		jr	z,file_refill.empty	; zero bytes = end of file
		ld	(ix+SOURCE_LEFT),l	; this much is now unread
		ld	(ix+SOURCE_LEFT+1),h
		ld	a,(ix+SOURCE_BUFFER)	; and we start at the beginning
		ld	(ix+SOURCE_READ_AT),a
		ld	a,(ix+SOURCE_BUFFER+1)
		ld	(ix+SOURCE_READ_AT+1),a
		or	a		; clears CY = fresh bytes available
		ret
file_refill.empty:
		ld	(ix+SOURCE_EOF),1
		ld	(ix+SOURCE_LEFT),0
		ld	(ix+SOURCE_LEFT+1),0
		scf
		ret

; file_char - take the next byte of this file, refilling if needed.
;
;   BC and DE are preserved because file_line keeps the line length in B
;   and the write position in DE, and a refill uses both.
;
; Input:	IX -> a line source entry of the file kind
; Output:	CY clear = A is the next byte
;		CY set   = there are no more bytes
; Modifies:	AF, HL

file_char:	ld	a,(ix+SOURCE_EOF)
		or	a
		scf
		ret	nz		; already finished
		ld	l,(ix+SOURCE_LEFT)
		ld	h,(ix+SOURCE_LEFT+1)
		ld	a,h
		or	l
		jr	nz,file_char.take	; still something in the buffer
		push	bc
		push	de
		call	file_refill	; empty -> go and get more
		pop	de
		pop	bc
		ret	c		; nothing more anywhere
file_char.take:	ld	l,(ix+SOURCE_READ_AT)
		ld	h,(ix+SOURCE_READ_AT+1)
		ld	a,(hl)		; the byte we came for
		inc	hl
		ld	(ix+SOURCE_READ_AT),l
		ld	(ix+SOURCE_READ_AT+1),h
		ld	l,(ix+SOURCE_LEFT)
		ld	h,(ix+SOURCE_LEFT+1)
		dec	hl
		ld	(ix+SOURCE_LEFT),l
		ld	(ix+SOURCE_LEFT+1),h
		or	a		; clears CY; A keeps the byte
		ret

; file_line - collect the next line from a file source.
;
;   CR is ignored and LF ends the line, so CF+LF fiels and files with
;   lone LFs both work. A last line with no line ending at all is still
;   handed over.
;
; Input:	IX -> a line source entry of the file kind
;		HL -> where to put the line
; Output:	CY clear = line stored, zero-terminated, A = its length,
;		           and the entry's line number has gone up by one
;		CY set   = this file has no more lines
; Modifies:	AF, BC, DE, HL

file_line:	ex	de,hl		; DE = where the line goes
		ld	b,0		; B = characters colllected so far
file_line.char:	call	file_char
		jr	c,file_line.eof
		cp	CHR_SUB		; Ctrl-Z: the file ends here
		jr	z,file_line.blank
		cp	CHR_CR
		; ignored; LF is what ends a line
		jr	z,file_line.char
		cp	CHR_LF
		jr	z,file_line.done
		ld	c,a		; keep the character
		ld	a,b
		cp	LINE_MAX
		jp	nc,error_line_too_long
					; no room for it: report and stop
		ld	a,c
		ld	(de),a
		inc	de
		inc	b
		jr	file_line.char

file_line.blank:
		ld	(ix+SOURCE_EOF),1	; nothing after Ctrl-Z counts
file_line.eof:	ld	a,b
		or	a
		; a last line with no LF: hand it over
		jr	nz,file_line.done
		scf			; nothing collected: the file is done
		ret

file_line.done:	xor	a
		ld	(de),a		; terminate the line
		ld	l,(ix+SOURCE_LINE)	; one more line handed over
		ld	h,(ix+SOURCE_LINE+1)
		inc	hl
		ld	(ix+SOURCE_LINE),l
		ld	(ix+SOURCE_LINE+1),h
		ld	a,b		; A = length
		or	a		; clears CY = a line is there
		ret

; next_source_line - the next source line, from whatever is on top of the
; stack.
;
;   When a source runs out it is removed here and the one underneath is
;   asked instead, so the caller never sees the join. Only files exist in
;   here; the call to file_line becomes a dispatch on the
;   entry's SOURCE_KIND.
;
; Input:	HL -> where to put the line
; Output:	CY clear = line stored, zero-terminated, A = its length,
;			current_file and current_line say where it came from
;		CY set   = no more lines from any source
; Modifies:	AF, BC, DE, HL, IX

next_source_line:
		push	hl	; the line buff, kept safe from pop_source
next_source_line.top:
		ld	a,(source_depth)
		or	a
		jr	z,next_source_line.none
					; nothing stacked: no more lines
		ld	ix,(source_top)
		pop	hl
		push	hl		; HL -> the line buffer again

		ld	a,(ix+SOURCE_KIND)	; which sort of source is this?
		cp	SOURCE_IS_FILE
		jr	nz,next_source_line.expansion
		call	file_line
		jr	next_source_line.got
next_source_line.expansion:
		call	expand_line
next_source_line.got:
		jr	c,next_source_line.pop	; this source has nothing left

		ld	b,a		; keep the length out of the way
		; note where this line came from
		ld	a,(ix+SOURCE_FILE_NUMBER)
		ld	(current_file),a
		ld	a,(ix+SOURCE_LINE)
		ld	(current_line),a
		ld	a,(ix+SOURCE_LINE+1)
		ld	(current_line+1),a
		pop	hl
		ld	a,b		; A = the length again
		or	a		; claers CY = a line is there
		ret

next_source_line.pop:
		call	pop_source	; done with it: close and remove
		jr	next_source_line.top
					; carry on with the one underneath

next_source_line.none:
		pop	hl
		scf			; CY set = nothing anywhere
		ret

		dseg

source_depth:	defs	1	; how many sources are stacked
source_top:	defs	2	; address of the top entry
current_file:	defs	1	; file number of the line just handed over
current_line:	defs	2	; line number of the line just handed over
pass_number:	defs	1
			; which pass is running, 1 or 2. The driver owns
				; its value; cond_true reads it for IF1/IF2 and
				; the line loop for whether to emit. NOT reset
				; by source_init, which runs once per pass and
				; would undo it
files_open:	defs	1	; how many files are open (= buffers used)
names_used:	defs	1	; names used in the table so far

push_name:	defs	2	; push_file: the name it was given
push_handle:	defs	1	; push_file: the handle MSX-DOS returned
push_file_number:
		defs	1	; push_file: the number for that name

push_expansion:	defs	2	; push_macro: the far pointer it was given
push_expansion_file:
		defs	1	; push_macro: the definition's file number

open_name:	defs	2	; source_open: the name it was given
env_read:	defs	1	; 0 = TATARA has not been looked up yet

		; the stack itself
source_stack:	defs	SOURCE_STACK_MAX*SOURCE_ENTRY_SIZE
		; file names, for messages
filename_table:	defs	FILE_NAMES_MAX*FILE_NAME_MAX
		; one buffer per OPEN FILE
file_buffers:	defs	OPEN_FILE_MAX*FILE_CHUNK_SIZE
include_dirs:	defs	OPEN_FILE_MAX*DOS_PATH_MAX
				; the directory each OPEN FILE came
					;   from, indexed exactly like
					;   file_buffers
env_path:	defs	ENV_VALUE_MAX	; TATARA's value, read once
					; (the candidate being tried is
					;  strutil.as's path_buffer)

