; LAYOUT.AS - where the bytes go.
;
; Three kinds of relocatable space, and the options that place them:
;
;   CSEG			code		TANREN /P:<addr>
;   DSEG			data		TANREN /D:<addr>
;   DSEG <name>,TRANSIENT	overlaid data	one GROUP at a time
;
; A SEGMENT MAY BE NAMED, and a named one keeps its own counter: two
; CSEG MUSIC lines in different files contribute to one segment.
;
; A TRANSIENT DSEG is space that is used by one part of a program at a
; time. Every GROUP in it starts at the same address, so the segment is
; as large as its largest group and not as large as their sum. Labels
; in two different groups cannot be subtracted from each other,
; because nothing says which of them is in memory.
;
; The absolute kind, ASEG, is in the BINARY and ROM examples - a fixed
; address in a .COM would make the file span everything from 0100h up
; to it.

BDOS		equ	0005h
_STROUT		equ	09h
_TERM0		equ	00h

		cseg

start:		ld	hl,runs		; a byte in the plain DSEG
		inc	(hl)
		ld	de,msg
		ld	c,_STROUT
		call	BDOS
		ld	c,_TERM0
		jp	BDOS

msg:		db	"Code here, data elsewhere.",13,10,"$"

		dseg			; the plain data segment: the
runs:		ds	1		;   linker puts it after the code
lastkey:	ds	1		;   unless /D: says where

		dseg	SCRATCH,TRANSIENT
		group	READING		; 66 bytes...
inbuf:		ds	64
inlen:		ds	2
		group	WRITING		; ...and 34, at the same address,
outbuf:		ds	32		;   so SCRATCH is 66 bytes and not
outlen:		ds	2		;   100

		end	start
