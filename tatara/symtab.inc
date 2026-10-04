; symtab.inc - public interface of symtab.as: the symbol table.
;
; symtab.as includes this file too: it defines SYMTAB_INCLUDED first, which
; skips the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.

		ifndef	SYMTAB_INCLUDED
		extrn symbol_table_init	; empty the table, case mode from
					; optcase.
					; ONCE ONLY, beside heap_init - NOT per
					; pass: the symbol table is the thing
					; that has to survive between passes
		extrn set_symbol	; define or redefine a symbol
					; in:  DE -> the name, B = its length
					;      HL = the value
					;      A  = the type (SY_ABS etc)
					; out: stored (error_out_of_memory does
					; not return)
		extrn look_up_symbol
				; look one up. This is what symbol_lookup
					; points at
					; in:  DE -> the name, B = its length
					; out: CY set   = no such symbol
					;      CY clear = HL is the value,
					;                 A is the type,
					;                 found_flags = its
					;                 flags
		extrn found_flags
				; the flags of the symbol look_up_symbol
					; last found. A byte
		extrn define_symbol	; define a symbol, WITH the rules:
					; multiply-defined, fixed against
					; variable, and pass 2's agreement
					; in:  DE -> the name
					;      B  = its length
					;      HL = the value
					;      A  = the type
					;      C = SYMBOL_VARIABLE, or 0 if
					;      fixed
		extrn declare_public	; mark one name PUBLIC, creating an
					; undefined record if it is not there
					; in:  DE -> the name
					;      B  = its length
		extrn declare_external	; declare one name external, and give
					; it the next external index
					; in:  DE -> the name
					;      B  = its length
		extrn check_pass2_labels
					; every label pass 1 defined and
					; pass 2 did not: a conditional
					; skipped it the second time, so its
					; bytes are missing from the program
					; while everything that referred to
					; it still points where pass 1 put
					; it. Called ONCE, at the end of
					; pass 2
					; in:  nothing
					; out: nothing, or error_pass2_label,
					; which does not return
		extrn dump_symbols	; print the symbol table (/S), in
					; Tatara's own format: the value,
					; the segment and the flags
		extrn list_symbols	; and M80's, for the listing's
					; last page: four hex digits, the
					; relocation mark, and the name
					; in sixteen columns, three to a
					; line. A DIFFERENT WALK, not a
					; reformatting of dump_symbols - one
					; is a diagnostic and the other
					; is M80

		extrn segment_table_init	; create the segment and group
					; tables and the three classic
					; segments. ONCE ONLY, beside
					; symbol_table_init: the indices they
					; hand out are stored in symbols, so
					; they must not change between passes
		extrn segment_reset	; every counter and size to 0, the
					; classic CSEG current. Per PASS
		extrn segment_directive	; an ASEG, CSEG or DSEG line
					; in:  A  = 0 ASEG, 1 CSEG, 2 DSEG
					;      DE -> the operand field
					;      B  = its length
		extrn group_directive	; a GROUP line
					; in:  DE -> the operand field
					;      B  = its length
		extrn require_placeable	; may a label or the location
					; counter be placed here? A
					; transient DSEG with no group
					; open stops with error_group_needed
		extrn location_counter	; the location counter of the
					; CURRENT contribution. A word
		extrn current_segment	; the current contribution's index,
					; which is what a label takes as
					; its type. A byte
		extrn park_counter	; the live counter back into the
					; record it came from, keeping the
					; high-water mark. It is called at
					; the end of pass 1: until it runs,
					; the current contribution's
					; SEGMENT_SIZE is short by whatever
					; location_counter still holds

; --- the tables themselves, for the walks. The object file's GRPDEF,
;     SEGDEF, EXTDEF and PUBDEF records ARE these three tables written
;     out, so objout.as reads them with hash.inc's htnext and the
;     layouts above. Nothing else outside this module touches them.

		extrn symbol_table	; the symbol table's descriptor
		extrn segment_table	; the segment table's
		extrn group_table	; the group table's
		extrn segment_count	; how many segment indices were
					; handed out. 0 is the ASEG, so the
					; SEGDEFs are 1 to segment_count-1
		extrn group_count	; how many group numbers, from 0

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

SYMBOL_BUCKETS	equ	128		; a power of two
SYMBOL_BUCKET_MASK	equ	SYMBOL_BUCKETS-1

; --- the payload, written into each record after the name.
;
;     The value and the type are what pass 1 needs. The flags byte is
;     reserved for one fact we already know we must record: the object
;     format's PUBDEF record (tatara-obj-spec.md, 04h) has to name the
;     symbols other modules may use, and L80 compatibility is G1. It
;     cannot ride in SYMBOL_TYPE, because a symbol is public AND
;     segment-relative at the same time - SYMBOL_TYPE answers "relative to
;     what", which is a choice of one.
;
;     The other seven bits are not named. Those would be guesses.

SYMBOL_VALUE	equ	0		; the value (2)
SYMBOL_TYPE	equ	2		; its segment's index (1)
SYMBOL_FLAGS	equ	3		; SYF_* below (1)
SYMBOL_FILE	equ	4		; A LABEL ONLY: which file its own
SYMBOL_LINE	equ	5		;   line was in, and which line
					;   (1+2). Read once, at the end of
					;   pass 2, so that check_pass2_labels
					;   can say WHERE a label the second
					;   reading never defined was written.
					;   Three bytes per symbol IN THE
					;   MAPPER, where every record already
					;   is - page 3 pays nothing for them
SYMBOL_SIZE	equ	7

SYMBOL_PUBLIC	equ	1		; PUBLIC or ENTRY named it
SYMBOL_EXTERNAL	equ	2		; EXTRN or EXT named it: another
					;   module defines it, and SYMBOL_VALUE
					;   holds its external INDEX rather
					;   than a value
SYMBOL_VARIABLE	equ	4		; SET or DEFL made it, so the source
					;   may redefine it as often as it
					;   likes. Everything else may be
					;   defined once
SYMBOL_DEFINED	equ	8		; it has a value. PUBLIC can name a
					;   symbol before anything defines it,
					;   and that record must not look like
					;   a definition
SYMBOL_IS_LABEL	equ	16		; A LABEL made it: it took the
					;   location counter, rather than a
					;   value EQU, SET or DEFL handed it.
					;   define_label is the only place that
					;   sets it. It is what SYMBOL_FILE and
					;   SYMBOL_LINE belong to, and the only
					;   kind of symbol check_pass2_labels
					;   checks - a guarded EQU that pass 2
					;   skips keeps its pass-1 value and is
					;   CORRECT
SYMBOL_PASS2	equ	32		; defined on THIS reading of the
					;   source. Set only while pass 2 runs,
					;   which is why nothing has to walk
					;   the table to clear it first

EXTERNAL_MAX	equ	0feh		; the highest external index, for
					;   the same reason SEGMENT_MAX stops
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

SEGMENT_BUCKETS	equ	8		; a power of two. A program has a
SEGMENT_BUCKET_MASK	equ	SEGMENT_BUCKETS-1
					;   handful of segments, not hundreds
GROUP_BUCKETS	equ	4		; and fewer groups than segments
GROUP_BUCKET_MASK	equ	GROUP_BUCKETS-1
SEGMENT_NAME_MAX	equ	16	; longest segment or group name.
					;   M80's own are six characters

SEGMENT_COUNTER	equ	0		; its location counter, while it is
					;   not the current one (2)
SEGMENT_SIZE	equ	2		; the highest the counter reached:
					;   the contribution's size (2)
SEGMENT_FLAGS	equ	4		; SGF_* below (1)
SEGMENT_GROUP	equ	5		; its group, GROUP_NONE if none (1)
SEGMENT_INDEX	equ	6		; its index: what SYMBOL_TYPE holds (1)
SEGMENT_RECORD_SIZE	equ	7

SEGMENT_IS_DATA	equ	1		; 0 = code, 1 = data. SEGDEF's bit 0
SEGMENT_IS_TRANSIENT	equ	2	; transient. SEGDEF's bit 1
SEGMENT_IS_ABSOLUTE	equ	4	; the absolute segment. Internal:
					;   ASEG gets no SEGDEF at all

GROUP_NONE	equ	0ffh		; no group is open
SEGMENT_MAX	equ	0feh		; the highest index we hand out
