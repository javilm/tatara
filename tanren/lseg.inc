; lseg.inc - public interface of lseg.as: the segments and groups of
; every module in the link.
;
; EACH MODULE NUMBERS ITS OWN. A SEGDEF's index is that module's, and
; its DATA and RELOC records quote it, so while a module is open the
; linker keeps a map from its indices to the real records - and
; throws the map away when the module closes. That map is the only
; per-module state there is.

		ifndef	LSEGLIB

		extrn lsginit		; both tables empty, counters
					; zero. ONCE, before the first
					; file is opened
		extrn lsgmod		; a module is starting: its maps
					; are empty again, and lmods goes
					; up
		extrn lsgrp		; a GRPDEF: the name is in lobbuf
					; and its length in lobsln
		extrn lsgseg		; a SEGDEF: lsfld holds flags,
					; group and size; the name is in
					; lobbuf
					; (errlmseg, errlsflg do not
					; return)
		extrn lsgdump		; /M: the modules, the groups and
					; the segments
		extrn lsgcase		; the two tables' case mode.
					; sets it from the first module's
					; MODNAME flags, because that is
					; when it becomes known
					; in:  A = HTCASES or HTCASEI
		extrn lsglay		; EVERY SEGMENT GETS AN ADDRESS:
					; code first, then data, from
					; ORGCOM, with same-named segments
					; in different groups OVERLAID -
					; one base, and the largest of
					; them taken from the image
					; (errlbig does not return)
		extrn lsgrst		; PASS 2: every segment's total
					; back to zero, so that lsgseg
					; accumulates it a second time
					; and reproduces each module's
					; base. No per-module base is
					; base, and this is the debt it
					; promised to pay
		extrn lsgend		; where the image ends, after
					; lsglay
		extrn lsgbase		; the base of the segment lsgsm
					; was asked about
		extrn lsgsm		; this module's segment index N
					; in:  A = the index the FILE used
					; out: lsgptr, lsgbas
		extrn lsgptr		; that segment's record (a far
					; pointer), and
		extrn lsgbas		;   this module's base within it
		extrn lsgnam		; the name of the record lsnamp
					; points at, printed a character
					; at a time out of the mapper
		extrn lsnamp		; which record that is: THREE
					; walks share this printer now
		extrn lsskp		; and how many key bytes come
					; before the name - 1 for a
					; segment, 0 for a group or a
					; symbol
		extrn lsfld		; a SEGDEF's fixed fields, read
					; before the name: flags, group,
					; size (4 bytes)
		extrn lmods		; how many modules have been read
		endif

ORGCOM		equ	00100h	; where an MSX-DOS .COM starts. A switch
				; moves it - [R11] wants a
				; 64 KB .ROM, which is a different START
				; and not a different mechanism
SGPAY		equ	6	; a segment record's payload: the flags
				; byte as the FILE wrote it, the size, the
				; base, and whether it has been placed.
				; THE PLACED FLAG IS NOT A SPARE BIT of
				; the flags byte: errlsflg compares that
				; byte across modules, and our own bit in
				; it would make two modules disagree about
				; a segment they agree on
SGP_FLG		equ	0	; and where each one sits
SGP_SIZ		equ	1
SGP_BAS		equ	3
SGP_SET		equ	5
LMAXSEG		equ	16	; segments one module may contribute to.
				; The map holds a far pointer each, so this
				; is 64 bytes of ordinary RAM
LMAXGRP		equ	16	; and groups it may define: one byte each
LSGBKTS		equ	16	; buckets in each table (a power of two)
