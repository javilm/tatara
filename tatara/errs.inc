; errs.inc - public interface of errs.as: the error messages.
;
; errs.as includes this file too: it defines ERRSLIB first, which skips
; the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.
;
; EVERY ONE OF THESE PRINTS AND TERMINATES. None of them returns, so a
; caller reaches one with jp or jr and never has to think about what
; comes back. The one exception is errtrl at the foot of the file,
; which is a printer rather than an error and does come back.
;
; This file exists because the SOLID assembler resolves an undeclared
; symbol to 0000h and writes the .com anyway. A module's export list is
; therefore the only thing between a mistyped name and a program that
; links cleanly and calls address zero. Seven modules used to keep their
; own hand-picked lists of these names; now there is one list, here.

		ifndef	ERRSLIB

; --- the command line, before any file is open. These print the message
;     with no FILE(line) prefix, because there is no position yet.

		extrn errunk		; unknown option
		extrn errmany		; too many filenames

; --- files and lines

		extrn errdeep		; sources nested too deeply
		extrn errfile		; too many source files open at once
		extrn errfnum		; too many different source files
		extrn errlong		; source line too long
		extrn errwrit		; cannot write to the output file
		extrn errincl		; INCLUDE without a filename
		extrn errenvl		; the TATARA variable is too long

; --- macro definitions and expansions

		extrn errnoend		; definition not closed by ENDM.
					; in: A = file, HL = the MACRO or REPT
					;     line - it fires at the end of the
					;     source, so curline is useless
		extrn errendm		; ENDM without a definition
		extrn errmnam		; MACRO without a name
		extrn errparm		; more formal params than we can count
		extrn errplst		; a parameter list that does not parse
		extrn errlocl		; LOCAL after the body has started
		extrn errblen		; a macro line that went past MAXLINE
		extrn errexit		; EXITM outside a macro or repeat block
		extrn errphase		; a label whose val on pass 2 disagrees
					; with pass 1's. M80 calls it a P error
		extrn errp2lab		; a label pass 1 defined and pass 2
					; did not: a conditional skipped it
					; the second time
					; in:  A = its file number,
					;      HL = its line

; --- conditionals

		extrn errcond		; ELSE or ENDIF without a matching IF
		extrn errncnd		; conditional not closed by ENDIF.
					; in: A = file, HL = the outermost one
					;     still open, from cndeof
		extrn errcdep		; conditionals nested too deeply

; --- expressions, and the heap

		extrn errxund		; undefined symbol in an expression
		extrn errxsyn		; bad expression
		extrn errrel		; a segment-relative value where the
					; operaetion needs an absolute one, or
					; two segments that do not combine.
					; M80 calls it an R error
		extrn errheap		; out of mapper memory

; --- segments

		extrn errseg		; a bad ASEG/CSEG/DSEG line
		extrn errsflg		; this segment name was declared
					; with different flags before
		extrn errgrp		; GROUP outside a transient DSEG,
					; or with no name, or with a label
		extrn errngrp		; a transient DSEG with no GROUP
					; open yet
		extrn errlabc		; a label holding a character that
					; is not a name character
		extrn errnlab		; EQU, DEFL or MACRO with a colon
					; after the name, which makes it a
					; label - M80 2.3.1
		extrn errmseg		; more segments or group than an
					; index byte can hold

; --- symbols declared

		extrn errmdef		; this name already has a value
		extrn errext		; an external symbol where the rules
					; do not allow one
		extrn errdecl		; a PUBLIC or EXTRN list that does
					; not parse
		extrn errpund		; PUBLIC named a symbol and nothing
					; in this module ever defined it
					;

; --- the data directives

		extrn errdata		; a DB, DW or DC operand that
					; cannot be measured

; --- instructions

		extrn erroper		; the operands are not a form this
					; instruction has
		extrn errpage		; PAGE was given a length outside
					; 10 to 255
		extrn errnoop		; the operation is not a directive, a
					; macro or an instruction either

; --- emitting

		extrn errmemit		; INTERNAL: a line emitted more bytes
					; than emitbuf keeps, which was proved
					; cannot happen and is checked anyway,
					; the buffer having become the object
					; file's content
		extrn errbytes		; INTERNAL: a handler returned without
					; emitting anything, which no Z80
					; instruction does. The other half of
					; it - the length and the bytes
					; disagreeing - stopped being possible
					;
		extrn errdisp		; an index displacement outside
					; -128 to 127
		extrn errrst		; an RST operand that is not 8n below
					; 40h
		extrn errim		; an IM operand that is not 0, 1 or 2
		extrn errjr		; a JR or DJNZ displacement that does
					; not fit a signed byte
		extrn errbit		; a bit number that is not 0 to 7

; --- and one that is NOT an error, and DOES return.

		extrn errtrl		; print how we got to the line that
					; failed: one line per level of the
					; source stack, innermost first.
					; errdie calls it, and so does
					; main.noinc, which prints its own
					; first line and wants the rest of
					; the chain under it

		endif
