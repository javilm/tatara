; errs.as - error reporting.
;
; print a message and stop. These routines also
; print where the error happened, including the trail through any nested
; macro expansions.

ERRSLIB		equ	1		; skips the externals in errs.inc

		public	errunk
		public	errmany
		public	errdeep
		public	errfile
		public	errfnum
		public	errlong
		public	errwrit
		public	errincl
		public	errenvl
		public	errnoend
		public	errendm
		public	errmnam
		public	errparm
		public	errheap
		public	errblen
		public	errlocl
		public	errcond
		public	errncnd
		public	errcdep
		public	errxund
		public	errxsyn
		public	errexit
		public	errplst
		public	errphase
		public	errp2lab
		public	errrel
		public	errseg
		public	errsflg
		public	errgrp
		public	errngrp
		public	errnlab
		public	errtrl		; not an error: the trail printer,
					;   which main.noinc needs too
		public	errmseg
		public	errmdef
		public	errext
		public	errdecl
		public	errpund
		public	errdata
		public	erroper
		public	errnoop
		public	errpage
		public	errbytes
		public	errmemit
		public	errdisp
		public	errrst
		public	errim
		public	errjr
		public	errbit

		include	errs.inc
		include	msxdos.inc
		include	ascii.inc
		include	srcline.inc	; the stack, curfile/curline, entaddr
		include	mdt.inc		; the expansion record's fields
		include	alloc.inc	; before farptr.inc: derefp needs
		include	farptr.inc	; deref to have been declared
		include	macros.inc	; macname: what is this descriptor
					; called?

		cseg

; Every one of these is three bytes of setup and a jump. They are all
; jp and not jr DELIBERATELY: errdie sits below the whole group, so
; the distance from the first of them grows by six bytes every time a
; message is added, and it passed 127. Eight bytes buys a file
; that cannot break that way again - do not "optimise" them back.

; errunk - "unknown option". Does not return.
errunk:		ld	de,msg_unk
		jp	errdie

; errmany - "too many filenames." Does not return.
errmany:	ld	de,msg_many
		jp	errdie

; errdeep - sources nested too deeply. Does not return.
errdeep:	ld	de,msg_deep
		jp	errdie

; errfile - more files open at once than there are buffers. Does not
; return.
errfile:	ld	de,msg_file
		jp	errdie

; errlong - a source line longer than MAXLINE. Does not return.
errlong:	ld	de,msg_long
		jp	errdie

; errfnum - more different source files than we can remember. Does not
; return.
errfnum:	ld	de,msg_fnum
		jp	errdie

; errincl - INCLUDE with no filename after it. Does not return.
errincl:	ld	de,msg_incl
		jp	errdie

; errenvl - the TATARA environment variable is longer than MAXENV, so
; _GENV has handed back a truncated value with no terminator. A search
; path that is quietly shorter than what was set is worse than none.
; Does not return.
errenvl:	ld	de,msg_envl
		jp	errdie

; errnoend - end of file with a macro definition still open. Called
; with A/HL = the MACRO line, not the end of the source: by the time
; this fires the stack is empty and curline is useless. Does not
; return.
errnoend:	ld	de,msg_noend
		jp	errdiea

; errendm - an ENDM with no definition open. Does not return.
errendm:	ld	de,msg_endm
		jp	errdie

; errmnam - a MACRO line with no name in the label field. Does not return.
errmnam:	ld	de,msg_mnam
		jp	errdie

; errparm - more formal parameters than we can count. Does not return.
errparm:	ld	de,msg_parm
		jp	errdie

; errplst - a formal parameter list that does not parse. Two things reach
; it: an empty name, as in "poke macro addr,,val", and an IRP or IRPC
; whose operand has no comma, which names no dummy. Both used to print
; "too many macro parameters", which is a different complaint and sent
; the reader looking for a limit that was not the problem. Does not
; return.
errplst:	ld	de,msg_plst
		jp	errdie

; errheap - the mapper ran out of memory. Does not return.
errheap:	ld	de,msg_heap
		jp	errdie

; errblen - a macro body line that went past MAXLINE: at definition time
; because parameter references became markers, or at expansion time
; because an argument was spliced in. Does not return.
errblen:	ld	de,msg_blen
		jp	errdie

; errwrit - the output file could not be written. Does not return.
errwrit:	ld	de,msg_writ
		jp	errdie

; errlocl - a LOCAL line after body lines have already been stored. The
; lines already stored have no marker for the name, so it would be
; substituted on some lines and not others. Does not return.
errlocl:	ld	de,msg_locl
		jp	errdie

; errcond - an ELSE or ENDIF with no IF open, or a second ELSE for the
; same IF. One message for all three, because the line number will say
; which one it was and three messages is 120 bytes. Does not return.
errcond:	ld	de,msg_cond
		jp	errdie

; errncnd - the source ended with a conditional still open. M80 calls
; this "Unterminated conditional". Does not return.
errncnd:	ld	de,msg_ncnd
		jp	errdiea		; A/HL = the outermost conditional
					; still open, from cndeof

; errcdep - conditionals nested deeper than MAXCND. M80 allows any depth;
; ours costs a byte of ordinary RAM per level and needs a guard, or it
; writes past the end of cndstk. Does not return.
errcdep:	ld	de,msg_cdep
		jp	errdie

; errxund - a name in an expression that nothing has defined. M80 calls
; this a V error; the manual requires an IF's operand to involve values
; "which were previously defined". Does not return.
errxund:	ld	de,msg_xund
		jp	errdie

; errxsyn - an expression that does not parse. Does not return.
errxsyn:	ld	de,msg_xsyn
		jp	errdie

; errexit - EXITM where there is no expansion to leave. Does not return.
errexit:	ld	de,msg_exit
		jp	errdie

; errphase - a label whose value on pass 2 disagrees with the value it
; had on pass 1. M80 calls this a P error. It means the two readings of
; the source assembled different programs, and everything after the
; label is wrong by the difference. The FILE(line) prefix names the
; label's own line. Does not return.
errphase:	ld	de,msg_phase
		jp	errdie

; errp2lab - a label that the FIRST reading of the source defined and
; the second did not: a conditional - an IFDEF or IFNDEF guard, all but
; always - was true on pass 1 and false on pass 2, so the block was
; skipped and its bytes were never emitted, while everything that
; referred to the label still points where pass 1 put it. M80 prints
; nothing and writes the short program; symp2's comment says why we do
; not. Called with A/HL = the label's own line, like errnoend: this
; fires at the end of pass 2, where curline is the END line. Does not
; return.
errp2lab:	ld	de,msg_p2lab
		jp	errdiea

; errrel - a relocatable value used where only an absolute one makes
; sense: multiplied, compared, HIGH/LOW, added to another relocatable,
; subtracted from one in a different segment, or given to DS, REPT or an
; ORG in another segment. The linker would have to know the segment's
; address to get the answer, and nobody does yet. M80 calls this an R
; error. Does not return.
errrel:		ld	de,msg_rel
		jp	errdie

; errseg - an ASEG, CSEG or DSEG line that does not parse: an operand on
; ASEG, a name longer than SGNMAX, TRANSIENT on a CSEG, or a word after
; the comma that is not TRANSIENT. Does not return.
errseg:		ld  de,msg_seg
		jp  errdie

; errsflg - the same segment name, declared differently: "cseg foo" and
; then "dseg foo", or with and without TRANSIENT. The linker calls that
; a mismatch too (tatara-obj-spec.md, SEGDEF). Does not return.
errsflg:	ld  de,msg_sflg
		jp  errdie

; errgrp - a GROUP line that cannot mean anything: outside a transient
; DSEG, without a name, or with a label in front of it. Does not return.
errgrp:		ld  de,msg_grp
		jp  errdie

; errnlab - EQU, DEFL or MACRO with a colon after the name. A colon
; makes the label field a location label (M80 2.3.1), and these three
; take a name - so the pseudo-op is left with nothing to name. M80
; calls it an O error and does not open a macro it refuses. Does not
; return.
errnlab:	ld	de,msg_nlab
		jp	errdie

; errngrp - a label, DS or ORG inside a transient DSEG before any GROUP
; line. Its variables would belong to no group, and a group is the only
; thing that says what may overlay what. Does not return.
errngrp:	ld  de,msg_ngrp
		jp  errdie

; errmseg - more segments or groups than an index byte holds. A segment
; index is one byte because it rides in every symbol's SY_TYPE. Does not
; return.
errmseg:	ld  de,msg_mseg
		jp  errdie

; errmdef - a name defined twice: two labels, two EQUs with different
; values, an EQU and a SET, or a name that EXTRN gave to another module
; and this one defines. M80 calls it an M error. The pass-2 case is a
; phase error instead, because there the SAME line answered differently.
; Does not return.
errmdef:	ld	de,msg_mdef
		jp	errdie

; errext - an external symbol where M80 2.4.3 does not allow one:
; multiplied or compared, two in one expression, or given to EQU, DS or
; ORG. An external is a promise to be kept by the linker, and the only
; arithmetic that survives being kept is adding or subtracting a plain
; number. Does not return.
errext:		ld	de,msg_ext
		jp	errdie

; errdecl - a PUBLIC or EXTRN list that does not parse: an empty name,
; or a name longer than a symbol may be. Does not return.
errdecl:	ld	de,msg_decl
		jp	errdie

; errpund - PUBLIC promised a symbol that nothing in this module ever
; defined. It fires at the END OF PASS 1, while the PUBDEF records are
; written, because that is the first moment the whole module is known.
; The alternative is an object file that offers a name it has no value
; for, and a link that fails one file away from the cause. M80 calls it
; a U error. Does not return.
errpund:	ld	de,msg_pund
		jp	errdie

; errdata - a DB, DW or DC operand that cannot be measured: an item with
; nothing in it, a line that ends inside a string, a string of three or
; more characters in a DW, or a DC that is not given exactly one
; non-empty string. It is deliberately NOT errxsyn: nothing about "dc ''"
; is a bad expression, and pass 1 does not read expressions at all.
; Does not return.
errdata:	ld	de,msg_data
		jp	errdie

; erroper - the operands on this line are not a form this instruction
; has: "and bc", "adc ix,bc", or anything at all left over after a
; complete instruction. It says "form" rather than "operand" because the
; operands may each be perfectly good and still not go together - "ld
; (bc),hl" is two legal operands and no instruction. Does not return.
erroper:	ld	de,msg_oper
		jp	errdie

; errnoop - the operation on this line is not a directive, not a macro
; and not an instruction. A DELIBERATE DEPARTURE FROM M80: 2.3.1 of the
; manual says that an operation which is none of those is treated "as
; if it were a DB statement", so a mistyped "xro a" assembles as one
; byte of data there and the program breaks somewhere else entirely.
; Same judgement as the second-label error and for the same reason -
; a silent wrong answer costs more than an incompatibility nobody
; relies on deliberately. Does not return.
errnoop:	ld	de,msg_noop
		jp	errdie

; errpage - PAGE was given a length outside 10 to 255. M80 marks the
; line with an A and counts it as fatal, which PAGEDIR.AS shows, so
; the value is not quietly ignored. Does not return.

errpage:	ld	de,msg_page
		jp	errdie

; errbytes - a class handler returned without emitting anything. NO Z80
; INSTRUCTION IS ZERO BYTES LONG, so this is a handler that took a path
; where it should have called emitb and did not - and without this
; check the symptom is every address below the line being wrong, in a
; file that assembled without a word.
;
; INTERNAL: it cannot be provoked from source, and no test can reach
; it. It is here for the mnemonic somebody adds in a year, which is
; exactly when nobody will be looking. Does not return.
errbytes:	ld	de,msg_byte
		jp	errdie

; errmemit - a line emitted more bytes than emitbuf keeps. It was decided
; the buffer could be one line's worth and no more, and proved that a
; line's worst case is "dw 1,1,1..." across a full operand field: 128
; items, 256 bytes, which is MAXEMIT exactly. That was safe while the
; buffer only fed the LISTING - past the end, a cosmetic column lost its
; tail. The buffer is what goes into the object file, so the
; same overflow would write a program with bytes missing from the
; middle. The proof still holds; this is the assertion that says so.
; Does not return.
errmemit:	ld	de,msg_memit
		jp	errdie

; errdisp - an index displacement outside -128 to 127. The byte is
; SIGNED and there is nowhere else for the value to go. Every indexed
; instruction reaches its displacement through emitd, so one test
; there covers all of them. Does not return.
errdisp:	ld	de,msg_disp
		jp	errdie

; errrst - an RST operand that is not one of 0, 8, 10h, 18h, 20h, 28h,
; 30h, 38h. The operand IS the opcode - 0C7h + n - so anything else
; would encode as some other instruction entirely. Does not return.
errrst:		ld	de,msg_rst
		jp	errdie

; errim - an IM operand that is not 0, 1 or 2. The three encode as
; 46h, 56h and 5Eh, which is not an arithmetic progression, so there
; is nothing to extend it to. Does not return.
errim:		ld	de,msg_im
		jp	errdie

; errjr - a JR or DJNZ displacement that does not fit a signed byte. The
; target is more than 127 bytes forward or 128 back OF THE ADDRESS AFTER
; THE INSTRUCTION, and JR has no long form to fall back on: M80 says so
; too, rather than quietly assembling a JP. Does not return.
errjr:		ld	de,msg_jr
		jp	errdie

; errbit - a bit number that is not 0 to 7. The number is part of the
; opcode - 40h + 8*b - so an eighth bit would encode as some other
; instruction entirely, exactly as RST's operand does. Does not return.
errbit:		ld	de,msg_bit
		jp	errdie

; errdie - print the $-terminated message in DE, with where it happened
;   and how we got there, and terminate.
;
;   errdiea is the same with the position given rather than taken from
;   curfile/curline. Two errors need it: a definition and a conditional
;   that are never closed both fire at the end of the source, by which
;   time curline points at the last line of the file rather than at the
;   line that opened the thing.
;
;   A line of 0 means no position is known - a command-line error,
;   before any file is open. Line numbers are 1-based, so 0 is free to
;   mean it.
;
; Input:	DE -> message
;		errdiea also: A = file number, HL = line
; Output:	does not return
; Modifies:	everything

errdie:		ld	a,(curfile)
		ld	hl,(curline)

errdiea:	ld	(erfil),a
		ld	(erlin),hl
		ld	(ermsg),de

		ld	hl,(erlin)	; anything open at all?
		ld	a,h
		or	l
		jr	z,errdie.msg	; no: the message on its own

		ld	a,(erfil)	; FILE(line):
		call	getfnam
		call	putszu
		ld	de,msg_ob
		call	putsz
		ld	hl,(erlin)
		call	putdec
		ld	de,msg_cbc
		call	putsz

errdie.msg:	ld	de,msg_err	; THE ONE COPY. Sixty-four messages
		call	putsz		;   carried these seven bytes each
		ld	de,(ermsg)	;
		call	putstr
		call	errtrl
		jp	dosexit

; errtrl - print how we got here: one line per macro expansion on the
;   line source stack, innermost first.
;
;   The stack IS the origin chain. A source is pushed when it starts
;   and popped only when it runs out, so at this instant every level
;   that led to the error is still there, in order.
;
;   A FILE LEVEL PRINTS WHEN THE LEVEL ABOVE IT IS ANOTHER FILE LEVEL.
;   When a macro sits above it, that macro has already named this file
;   and this line as its call site, and saying it twice helps nobody -
;   which is what the old rule said, correctly, about that one case and
;   wrongly about every other. An include is not a call and nothing else
;   prints one, so a chain of includes needs these lines or it is
;   invisible.
;
;   The topmost level needs no test: erprev starts as LSK_MACRO, so a
;   file there says nothing, and errdie has already named it.
;
;   THE PAGE 2 RULE, per level: read the record, read MD_KIND, and get
;   the name - all into ordinary RAM - and only then print anything.
;   Printing goes through _CONOUT and _STROUT, which hand page 2 back
;   to MSX-DOS.
;
; Input:	nothing
; Output:	the trail is printed
; Modifies:	everything

errtrl:		ld	a,LSK_MACRO	; nothing sits above the topmost
		ld	(erprev),a	;   level, and a file there is the
					;   one errdie has already named
		ld	a,(srcdep)
		or	a
		ret	z		; nothing stacked: no trail

errtrl.lp:	dec	a
		ld	(eridx),a
		call	entaddr		; HL -> that entry
		push	hl
		pop	ix
		ld	a,(ix+LS_KIND)
		ld	(erthis),a	; kept: printing destroys IX
		cp	LSK_MACRO
		jr	nz,errtrl.fil

		push	ix		; the record: which descriptor, and
		pop	hl		; where the call was
		ld	de,LS_MX
		add	hl,de
		call	deref
		ld	de,MX_MD
		add	hl,de
		fpsave	ermd		; fpsave leaves HL at MX_BLK
		ld	de,MX_CFIL-MX_BLK
		add	hl,de
		ld	a,(hl)
		ld	(ercfil),a	; MX_CFIL
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(erclin),de	; MX_CLIN

		derefp	ermd		; MD_KIND, while we still can
		ld	a,(hl)
		ld	(erkind),a

		ld	hl,ermd		; and the name, before anything is
		call	macname		; printed. CY clear = DE -> the name
		jr	nc,errtrl.p2

		ld	de,msg_anon	; no name: which sort is it?
		ld	a,(erkind)
		or	a
		jr	nz,errtrl.p2	; not MDK_MACRO: a repeat block
		ld	de,msg_redef	; a macro, but nothing names it now

errtrl.p2:	push	de
		ld	de,msg_in
		call	putsz
		pop	de
		call	putsz
		ld	de,msg_from
		call	putsz
		ld	a,(ercfil)
		call	getfnam
		call	putszu
		ld	de,msg_ob
		call	putsz
		ld	hl,(erclin)
		call	putdec
		ld	de,msg_cb2
		call	putsz
		jr	errtrl.nx	; NOT a fall-through: the file branch
					;   sits between this and errtrl.nx,
					;   and a macro level must not reach
					;   it

; A file level. LS_FILE and LS_LINE are bytes of the entry itself, in
; ordinary RAM, so there is no page 2 rule to keep here - only the
; macro path needs one, for the far pointer at LS_MX.

errtrl.fil:	ld	a,(erprev)
		or	a
		jr	nz,errtrl.nx	; a macro above has already named
					;   this file and this line
		ld	a,(ix+LS_FILE)
		ld	(ercfil),a
		ld	l,(ix+LS_LINE)	; the line it last handed over, which
		ld	h,(ix+LS_LINE+1); is the INCLUDE that suspended it
		ld	(erclin),hl
		ld	de,msg_incfr
		call	putsz
		ld	a,(ercfil)
		call	getfnam
		call	putszu
		ld	de,msg_ob
		call	putsz
		ld	hl,(erclin)
		call	putdec
		ld	de,msg_cb2
		call	putsz

errtrl.nx:	ld	a,(erthis)	; the level below asks what this one
		ld	(erprev),a	;   was
		ld	a,(eridx)
		or	a
		jp	nz,errtrl.lp	; a jp, not a jr: the loop body prints
					; a whole trail line and is far past
					; 127 bytes
		ret

		dseg

; The seven below are ZERO-terminated, not $-terminated, because they
; go through putsz rather than _STROUT: they are interleaved with
; filenames and numbers that BDOS 09h cannot help with. The msg_*
; error texts keep the "$". mdnam, which macname fills, is
; zero-terminated for the same reason.

msg_ob:		defb	"(",0
msg_cbc:	defb	"): ",0
msg_cb2:	defb	")",CHR_CR,CHR_LF,0
msg_in:		defb	"    in ",0
msg_from:	defb	", called from ",0
msg_incfr:	defb	"    included from ",0
msg_anon:	defb	"a repeat block",0
msg_redef:	defb	"a redefined macro",0

erfil:		defs	1	; errdie: where the error was
erlin:		defs	2	;   (a line of 0 = nowhere yet)
ermsg:		defs	2	; the message, across the position printing
eridx:		defs	1	; errtrl: which stack entry
ermd:		defs	4	; far pointer: this level's descriptor
ercfil:		defs	1	; errtrl: where this level was called from
erclin:		defs	2
erkind:		defs	1	; errtrl: MD_KIND, for the unnamed cases
erthis:		defs	1	; errtrl: this level's LS_KIND
erprev:		defs	1	; errtrl: the level above this one's, which
				;   is what decides whether a file level
				;   prints at all

msg_err:	defb	"ERROR: ",0	; printed by errdie.msg, so no
				;   message below says it
msg_unk:	defb	"unknown option.",CHR_CR,CHR_LF,"$"
msg_many:	defb	"too many filenames.",CHR_CR,CHR_LF,"$"
msg_deep:	defb	"sources nested too deeply.",CHR_CR
		defb	CHR_LF,"$"
msg_file:	defb	"too many source files open at once.",CHR_CR
		defb	CHR_LF,"$"
msg_long:	defb	"source line too long.",CHR_CR,CHR_LF,"$"
msg_fnum:	defb	"too many different source files.",CHR_CR
		defb	CHR_LF,"$"
msg_writ:	defb	"cannot write to the output file.",CHR_CR
		defb	CHR_LF,"$"
msg_incl:	defb	"INCLUDE without a filename.",CHR_CR
		defb	CHR_LF,"$"
msg_envl:	defb	"the TATARA variable is too long.",CHR_CR
		defb	CHR_LF,"$"
msg_noend:	defb	"macro definition not closed by ENDM.",CHR_CR
		defb	CHR_LF,"$"
msg_endm:	defb	"ENDM without a macro definition.",CHR_CR
		defb	CHR_LF,"$"
msg_mnam:	defb	"MACRO without a name.",CHR_CR,CHR_LF,"$"
msg_parm:	defb	"too many macro parameters.",CHR_CR,CHR_LF,"$"
msg_plst:	defb	"bad macro parameter list.",CHR_CR,CHR_LF,"$"
msg_heap:	defb	"out of mapper memory.",CHR_CR,CHR_LF,"$"
msg_blen:	defb	"macro line too long.",CHR_CR
		defb	CHR_LF,"$"
msg_locl:	defb	"LOCAL must come before the macro body.",CHR_CR
		defb	CHR_LF,"$"
msg_cond:	defb	"ELSE or ENDIF without a matching IF.",CHR_CR
		defb	CHR_LF,"$"
msg_ncnd:	defb	"conditional not closed by ENDIF.",CHR_CR
		defb	CHR_LF,"$"
msg_cdep:	defb	"conditionals nested too deeply.",CHR_CR
		defb	CHR_LF,"$"
msg_xund:	defb	"undefined symbol in an expression.",CHR_CR
		defb	CHR_LF,"$"
msg_xsyn:	defb	"bad expression.",CHR_CR
		defb	CHR_LF,"$"
msg_exit:	defb	"EXITM outside a macro or repeat block.",CHR_CR
		defb	CHR_LF,"$"
msg_phase:	defb	"phase error - this label had a different"
		defb	" value on pass 1.",CHR_CR,CHR_LF,"$"
msg_p2lab:	defb	"this label was defined on pass 1 and not"
		defb	" on pass 2 - a conditional skipped it."
		defb	CHR_CR,CHR_LF,"$"
msg_rel:	defb	"relocation error - a segment-relative"
		defb	" value is not allowed here.",CHR_CR,CHR_LF,"$"
msg_seg:	defb	"bad ASEG, CSEG or DSEG line.",CHR_CR
		defb	CHR_LF,"$"
msg_sflg:	defb	"this segment was declared differently"
		defb	" before.",CHR_CR,CHR_LF,"$"
msg_grp:	defb	"GROUP needs a name, no label, and a"
		defb	" transient DSEG.",CHR_CR,CHR_LF,"$"
msg_nlab:	defb	"EQU, DEFL and MACRO take a name, not a"
		defb	" label.",CHR_CR,CHR_LF,"$"
msg_ngrp:	defb	"this transient DSEG needs a GROUP"
		defb	" first.",CHR_CR,CHR_LF,"$"
msg_mseg:	defb	"too many segments, groups or"
		defb	" externals.",CHR_CR,CHR_LF,"$"
msg_mdef:	defb	"this name already has a value.",CHR_CR
		defb	CHR_LF,"$"
msg_ext:	defb	"an external symbol may not be used"
		defb	" here.",CHR_CR,CHR_LF,"$"
msg_decl:	defb	"bad PUBLIC or EXTRN list.",CHR_CR
		defb	CHR_LF,"$"
msg_pund:	defb	"a PUBLIC name was never defined."
		defb	CHR_CR,CHR_LF,"$"
msg_data:	defb	"bad DB, DW or DC operand.",CHR_CR
		defb	CHR_LF,"$"
msg_oper:	defb	"not a form this instruction has."
		defb	CHR_CR,CHR_LF,"$"
msg_noop:	defb	"not a directive, a macro or an"
		defb	" instruction.",CHR_CR,CHR_LF,"$"
msg_page:	defb	"a PAGE length must be 10 to 255."
		defb	CHR_CR,CHR_LF,"$"
msg_byte:	defb	"internal - an instruction emitted"
		defb	" nothing.",CHR_CR,CHR_LF,"$"
msg_memit:	defb	"internal - this line emitted more"
		defb	" bytes than fit.",CHR_CR,CHR_LF,"$"
msg_disp:	defb	"an index displacement must be -128"
		defb	" to 127.",CHR_CR,CHR_LF,"$"
msg_rst:		defb	"RST takes 0, 8, 10h and so on to"
		defb	" 38h.",CHR_CR,CHR_LF,"$"
msg_im:		defb	"IM takes 0, 1 or 2.",CHR_CR,CHR_LF
		defb	"$"
msg_jr:		defb	"a JR or DJNZ can only reach -128"
		defb	" to 127.",CHR_CR,CHR_LF,"$"
msg_bit:		defb	"a bit number must be 0 to 7."
		defb	CHR_CR,CHR_LF,"$"
