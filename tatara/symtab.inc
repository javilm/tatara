; symtab.inc - public interface of symtab.as: the symbol table.
;
; symtab.as includes this file too: it defines SYMLIB first, which skips
; the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.

		ifndef	SYMLIB
		extrn syminit		; empty the table, case mode from
					; optcase.
					; ONCE ONLY, beside heapinit - NOT per
					; pass: the symbol table is the thing
					; that has to survive between passes
		extrn symset		; define or redefine a symbol
					; in:  DE -> the name, B = its length
					;      HL = the value
					;      A  = the type (SY_ABS etc)
					; out: stored (errheap does not return)
		extrn symlook		; look one up. This is what exlook
					; points at
					; in:  DE -> the name, B = its length
					; out: CY set   = no such symbol
					;      CY clear = HL is the value,
					;                 A is the type,
					;                 symfl = its flags
		extrn symfl		; the flags of the symbol symlook
					; last found. A byte
		extrn symdef		; define a symbol, WITH the rules:
					; multiply-defined, fixed against
					; variable, and pass 2's agreement
					; in:  DE -> the name
					;      B  = its length
					;      HL = the value
					;      A  = the type
					;      C  = SYF_VAR, or 0 if fixed
		extrn sympub		; mark one name PUBLIC, creating an
					; undefined record if it is not there
					; in:  DE -> the name
					;      B  = its length
		extrn symext		; declare one name external, and give
					; it the next external index
					; in:  DE -> the name
					;      B  = its length
		extrn symdump		; print the symbol table (/S), in
					; Tatara's own format: the value,
					; the segment and the flags
		extrn lstsyms		; and M80's, for the listing's
					; last page: four hex digits, the
					; relocation mark, and the name
					; in sixteen columns, three to a
					; line. A DIFFERENT WALK, not a
					; reformatting of symdump - one
					; is a diagnostic and the other
					; is M80

		extrn seginit		; create the segment and group
					; tables and the three classic
					; segments. ONCE ONLY, beside
					; syminit: the indices they hand
					; out are stored in symbols, so
					; they must not change between
					; passes
		extrn segrst		; every counter and size to 0, the
					; classic CSEG current. Per PASS
		extrn segdir		; an ASEG, CSEG or DSEG line
					; in:  A  = 0 ASEG, 1 CSEG, 2 DSEG
					;      DE -> the operand field
					;      B  = its length
		extrn seggrp		; a GROUP line
					; in:  DE -> the operand field
					;      B  = its length
		extrn segwr		; may a label or the location
					; counter be placed here? A
					; transient DSEG with no group
					; open stops with errngrp
		extrn locctr		; the location counter of the
					; CURRENT contribution. A word
		extrn curseg		; the current contribution's index,
					; which is what a label takes as
					; its type. A byte
		extrn segpark		; the live counter back into the
					; record it came from, keeping the
					; high-water mark. It is called at
					; the end of pass 1: until it runs,
					; the current contribution's
					; SG_SIZE is short by whatever
					; locctr still holds

; --- the tables themselves, for the walks. The object file's GRPDEF,
;     SEGDEF, EXTDEF and PUBDEF records ARE these three tables written
;     out, so objout.as reads them with hash.inc's htnext and the
;     layouts above. Nothing else outside this module touches them.

		extrn symtab		; the symbol table's descriptor
		extrn segtab		; the segment table's
		extrn grptab		; the group table's
		extrn segnum		; how many segment indices were
					; handed out. 0 is the ASEG, so the
					; SEGDEFs are 1 to segnum-1
		extrn grpnum		; how many group numbers, from 0

		endif

; --- how many buckets. 514 bytes of ordinary RAM, which is the whole
;     cost of this table in page 3: hash.as keeps every record - the name
;     bytes included - in the mapper, and only the descriptor has to be
;     where deref cannot move it.
;
;     128 and not 16 (the macro name table's count, chosen)
;     because this one is looked up ONCE PER OPERAND in pass 1, not once
;     per operation that turned out not to be a directive. At a thousand
;     symbols that is a chain of 8 rather than 16. 256 was costed and
;     refused: 1,026 bytes is the whole remaining budget for one table,
;     and the object record buffer comes out of the same purse.
;
;     It is one equate. If a real source ever makes look-up measurable,
;     256 is this line and a rebuild.

SYBUCKS		equ	128		; a power of two
SYMASK		equ	SYBUCKS-1

; --- the payload, written into each record after the name.
;
;     The value and the type are what pass 1 needs. The flags byte is
;     reserved for one fact we already know we must record: the object
;     format's PUBDEF record (tatara-obj-spec.md, 04h) has to name the
;     symbols other modules may use, and L80 compatibility is G1. It
;     cannot ride in SY_TYPE, because a symbol is public AND
;     segment-relative at the same time - SY_TYPE answers "relative to
;     what", which is a choice of one.
;
;     The other seven bits are not named. Those would be guesses.

SY_VAL		equ	0		; the value (2)
SY_TYPE		equ	2		; its segment's index (1)
SY_FLAGS	equ	3		; SYF_* below (1)
SYSIZE		equ	4

SYF_PUB		equ	1		; PUBLIC or ENTRY named it
SYF_EXT		equ	2		; EXTRN or EXT named it: another
					;   module defines it, and SY_VAL
					;   holds its external INDEX rather
					;   than a value
SYF_VAR		equ	4		; SET or DEFL made it, so the source
					;   may redefine it as often as it
					;   likes. Everything else may be
					;   defined once
SYF_DEF		equ	8		; it has a value. PUBLIC can name a
					;   symbol before anything defines it,
					;   and that record must not look like
					;   a definition

MAXEXT		equ	0feh		; the highest external index, for
					;   the same reason MAXSEGS stops
					;   there: it rides in one byte

; --- the segments. One record per (segment, GROUP) pair, which is
;     what one SEGDEF record in the object file describes: a name, the
;     flags, one group and one size. Two contributions with the same
;     name and group are laid end to end; with different groups they
;     overlay, which is what a transient DSEG is for.
;
;     The records are in the MAPPER, in a hash.as table keyed by the
;     group's number followed by the name. Ordinary RAM holds the bucket
;     arrays and the key, and nothing else: resident data is the scarce
;     thing here, mapper memory is not.

SGBUCKS		equ	8		; a power of two. A program has a
SGMASK		equ	SGBUCKS-1	;   handful of segments, not hundreds
GRBUCKS		equ	4		; and fewer groups than segments
GRMASK		equ	GRBUCKS-1
SGNMAX		equ	16		; longest segment or group name.
					;   M80's own are six characters

SG_CTR		equ	0		; its location counter, while it is
					;   not the current one (2)
SG_SIZE		equ	2		; the highest the counter reached:
					;   the contribution's size (2)
SG_FLAGS	equ	4		; SGF_* below (1)
SG_GRP		equ	5		; its group, GRPNONE if none (1)
SG_IDX		equ	6		; its index: what SY_TYPE holds (1)
SGSIZE		equ	7

SGF_DATA	equ	1		; 0 = code, 1 = data. SEGDEF's bit 0
SGF_TRAN	equ	2		; transient. SEGDEF's bit 1
SGF_ABS		equ	4		; the absolute segment. Internal:
					;   ASEG gets no SEGDEF at all

GRPNONE		equ	0ffh		; no group is open
MAXSEGS		equ	0feh		; the highest index we hand out
