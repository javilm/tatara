; emit.inc - public interface of emit.as: the bytes an assembled line
; comes to.
;
; emit.as includes this file too: it defines EMITLIB first, which skips
; the external declarations below - a symbol cannot be declared external
; in the module that defines it as global.
;
; EVERYTHING GOES THROUGH emitb. It is the sink emit-design.md 4 is
; about, and the ONE routine replaced to write object records
; instead of keeping bytes for a listing. Nothing else in the program
; stores a byte of output, which is what makes that swap a swap rather
; than a rewrite of twenty-one encoders.

		ifndef	EMITLIB

		extrn emitinit		; start a line: where it begins,
					; and nothing emitted yet. Per
					; LINE, not per pass
					; in:  HL = where it begins
					;      A  = its segment index
		extrn emitskip		; this line is inside a branch that
					; is not taken, so it names no
					; place and its address column
					; stays blank - which is what M80
					; does
		extrn emitval		; the listing's address column
					; shows a VALUE rather than a
					; place: EQU and DEFL, which is
					; where M80 puts one. The
					; relocation mark comes from the
					; type, so an absolute value gets
					; none
					; in:  HL = the value
					;      A  = its type (exty)
		extrn emitb		; ONE byte, already known.
					; THE SINK
					; in:  A = the byte
		extrn emitw		; two bytes, the low one first
					; in:  HL = the word
		extrn emitx		; the expression at DE, as ONE
					; byte. errrel if its value is
					; not absolute
					; in:  DE -> the text
					;      A  = how long it is
					; PASS 1 DOES NOT READ IT: it
					; emits a zero, because no value
					; changes any length and nothing
					; reads pass 1's bytes
		extrn emitxw		; the same, as TWO bytes. A
					; relocatable or external value
					; contributes its ADDEND, and the
					; record that tells the linker
					; about it is the object writer's
		extrn emithi		; set bit 7 of the last byte
					; emitted - DC, and nothing else
		extrn emitop		; an opcode in the ORDINARY shape:
					; the prefix an index register forces
					; goes out FIRST, the opcode next,
					; the displacement LAST. The CB
					; group does not come through here
					; in:  A = the opcode
		extrn emitd		; the displacement the last indexed
					; operand carried, as one SIGNED
					; byte. None written means zero
		extrn emitjr		; the remembered expression as a
					; RELATIVE displacement: one signed
					; byte, the target minus the address
					; AFTER the instruction. The only
					; place one address is subtracted
					; from another
		extrn emitxs		; the expression the parser
					; remembered, as ONE byte
		extrn emitxws		; ... and as TWO
		extrn exsval		; its VALUE, for an expression that
					; goes into an OPCODE rather than a
					; byte of its own - RST's, IM's,
					; BIT's number
					; out: HL = it, and 0 ON PASS 1
		extrn emitpfx		; build the listing's two columns,
					; for the first eight bytes
					; out: DE -> the text
					;      A  = how long it is
		extrn emitmore		; the same for the next eight. A
					; line that emitted more than the
					; column holds WRAPS, and the
					; caller asks until this says stop
					; out: CY set = none left, nothing
					;          was built
		extrn emitn		; A WORD: how many bytes this
					; line has emitted
		extrn emitbuf		; them, up to the first MAXEMIT
		extrn emitraw		; A bytes at DE, exactly as they
					; are: no terminator, no CR+LF
					; in:  DE -> the bytes
					;      A  = how many
		extrn emitln		; one line, TABS EXPANDED to the
					; next eight-column stop, then
					; CR+LF. THE BUFFER IS NOT
					; TOUCHED: the two bytes go out
					; on their own, where they used
					; to be written over the line's
					; zero terminator
					; in:  DE -> the line
					;      A  = its length
					;      C  = the column the text
					;           starts at, which the
					;           stops are counted from
		extrn outhand		; A BYTE: where both of them
					; write. outopen sets it to the
					; listing file's handle or to
					; STDOUT; outclose closes it
		extrn lstline		; list one source line, if
					; anything is listening: the
					; modes, the switches, the
					; columns and the continuation
					; lines. It tests passno itself
					; in:  DE -> the text
					;      A  = its length
		extrn lsttset		; remember a TITLE or a SUBTTL.
					; The title is NOT cleared between
					; the passes and the subtitle is,
					; which is what makes a title on
					; source line 3 head page 1
					; in:  DE -> the text
					;      A  = its length
					;      C  = 0 title, 1 subtitle
		extrn lsteject		; PAGE: break the page AFTER the
					; line being listed now. The
					; directive belongs to the page it
					; was written on
		extrn lstff		; a form feed in the source: break
					; the page NOW, before the line is
					; listed, and move the MAIN number.
					; M80 prints the form feed's own
					; line empty at the top of the page
					; it opens
		extrn lstpset		; PAGE expr: how long a page is.
					; 10 to 255; anything else leaves
					; it alone
					; in:  HL = the count
		extrn lsttitl		; THE TITLE ITSELF: a length byte,
					; then the text. objbase reads it -
					; M80's module name is the title's
					; first six characters when there
					; is a title
		extrn lstinit		; the listing, back to where a
					; pass starts it: on, .XALL, page
					; 1, and a header due. PER PASS,
					; from main.pass
		extrn lstend		; THE LAST PAGE: a form feed, the
					; header with S where the number
					; goes, then Macros: and
					; Symbols:. main.fin calls it
					; before outclose, and it returns
					; at once if no listing was asked
					; for
		extrn lstcrlf		; one line ending, wherever the
					; listing goes. The two walks that
					; write the last page end their
					; lines with it
		extrn emitsp		; A spaces, wherever the listing
					; goes - the padding a column of
					; names needs
					; in:  A = how many
		extrn emitchr		; one character to wherever the
					; listing goes. For a name that
					; lives in the mapper, which
					; cannot be handed to _WRITE
					; in:  A = the character
		extrn lstbody		; the same for a line the driver
					; never sees - a MACRO, REPT, IRP
					; or IRPC line, or a line of a
					; body. NO LABEL AND NO ADDRESS:
					; a macro name is not a place
		extrn lston		; A BYTE: 0 once .XLIST has been
					; seen, 0FFh again after .LIST
		extrn lstmode		; A BYTE: LST_LALL, LST_SALL or
					; LST_XALL. The driver writes it from
					; .LALL/.SALL/.XALL; epf.mac reads it
					; for .SALL's "+"
		extrn lstcall		; A BYTE: non-zero if this line
					; called a macro. The DRIVER sets
					; it, after emitinit has cleared
					; it; only .SALL's "+" reads it
		extrn lstmac		; A BYTE: the LS_KIND of the
					; source THIS LINE came from.
					; emitinit snapshots it, because
					; a macro call pushes its body
					; before the call line is listed -
					; ask the stack later and the call
					; line looks like an expansion
		extrn lstaddr		; A WORD: where the current line
					; began, before anything on it moved
					; the counter
		extrn lstseg		; A BYTE: and in which contribution.
					; emitinit records both, and this
					; compares them against the open
					; DATA run to see whether the run
					; continues
		endif

; How many of a line's bytes are KEPT. The COUNT is not capped and must
; not be: "dw 1,1,1..." across a full operand field is 128 items and
; 256 bytes, one over. Past this the sink keeps counting and stops
; storing, so locctr stays right and only the listing loses the tail.

MAXEMIT		equ	256	; the worst a line can
				;   do - "dw 1,1,1..." across a full
				;   operand field, 128 items, 256 bytes -
				;   and the cap was one short of it.
				;   emitb compares emitn against this as
				;   a WORD, so crossing 255 costs one
				;   byte of buffer and nothing else

; How many bytes the LISTING shows on one line, and where the source
; text begins. BOTH ARE M80'S, measured off an M80 .PRN in RESULTS.TXT
; rather than chosen:
;
;   "  0002'   DD A6 05              t2:     and     (ix+5)"
;      ^       ^                     ^
;      2       10                    32
;
; 2 spaces + 4 digits + the relocation mark + 3 spaces = 10, then three
; characters a byte. M80 wraps at FOUR and starts the source at 32 -
; so LSTWIDE is not 10 + 3*MAXSHOW. The source column does not move
; when the byte field is shorter than the space kept for it.
;
; the wrapping was built with 8 and 34, which was a guess made before
; anyone measured. The machinery did not change; these two numbers did.

MAXSHOW		equ	4
LSTWIDE		equ	32

; And where M80 flags a macro-generated line. MEASURED the same way,
; off M80's listing of MACPLUS.AS:
;
;   "  0000'   01              +             db      1"
;      ^       ^               ^
;      2       10              26
;
; A column of its own, six before the source text - not the last
; space in front of it, which was the guess before anyone asked.

LSTPLUS		equ	26

; --- the page, measured off M80's LONGLST.PRN: a header, two
;     blank lines, and this many lines of text. Every page after the
;     first starts with a form feed.

PAGELEN		equ	56	; and now only the DEFAULT: the
				;   PAGE expr moves it

; --- the header's own fields

MAXTITL		equ	28	; the longest TITLE or SUBTTL kept. With
				;   LSTNAMW below, the widest header this
				;   can produce is 77 columns
LSTNAMW		equ	13	; and the name-and-version field's width.
				;   M80's own is thirteen - "MSX.M-80
				;   2.00" - and every column after it in
				;   the header is measured from there

; --- how much of a macro expansion the listing shows. M80's
;     default is .XALL. The three MUST keep these values: the driver
;     gets the mode by subtracting D_LALL from the directive's number.

LST_LALL	equ	0	; .LALL: every line of an expansion
LST_SALL	equ	1	; .SALL: none of them
LST_XALL	equ	2	; .XALL: the ones that generated code
