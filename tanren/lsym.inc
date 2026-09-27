; lsym.inc - public interface of lsym.as: the link's symbols.
;
; ONE TABLE, NOT TWO. A public and an external are two statements
; about one symbol, so they share a record and a flags byte says
; which statements have been made. "What is missing?" is then a
; single walk looking for referenced-and-not-defined, rather than a
; comparison between two collections.

		ifndef	LSYMLIB

		extrn lsyinit		; the table, empty, in the
					; default case mode
		extrn lsycase		; MODNAME's flags byte: the mode
					; on the first module, and the
					; mixture check on every one after
					; in:  A = the flags byte
					; (errlymix does not return)
		extrn lsypub		; a PUBDEF entry
					; in:  lsfld2 = segment, offset
					;      lobbuf = the name
					; (errlydup does not return)
		extrn lsyext		; an EXTDEF entry
					; in:  lobbuf = the name
		extrn lsyfix		; EVERY DEFINED, NON-ABSOLUTE
					; SYMBOL: its value plus its
					; segment's base, which is an
					; address. AFTER lsglay
		extrn lsyval		; PASS 2: the final value of the
					; name in lobbuf. Every EXTDEF
					; name is in the table by then
					; and lsyfix has made every
					; value an address
					; in:  lobbuf, lobsln
					; out: HL = its value
		extrn lsychk		; END OF PASS 1: name every
					; external nobody defined - ALL of
					; them - and stop if there were
					; any
					; (errlyunr does not return)
		extrn lsymod		; a module is starting: keep its
					; name, for the messages that have
					; to say which module
					; in:  lobbuf, lobsln
		extrn lsydump		; /M: the symbols
		extrn lsfld2		; a PUBDEF's segment and offset,
					; read before its name
		endif

SYF_DEF		equ	001h	; some module defines it
SYF_REF		equ	002h	; some module wants it
SYF_ABS		equ	004h	; its value is an address already, and
				; the layout must NOT add a segment's base
LSYBKTS		equ	64	; buckets. tatara.as alone declares 182
				; externals, so this table is the biggest
				; of the three by an order of magnitude
LSYSIZE		equ	7	; flags, value (2), the segment (4)
LMODMAX		equ	16	; the current module's name, kept for the
				; messages that name one. Cut, not refused
