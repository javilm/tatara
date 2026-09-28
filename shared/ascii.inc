; ascii.inc - symbolic names for the first 33 ASCII characters (0-32).
;
; Use these instead of bare character codes in comparisons and defb data
; so the intent is readable: cp CHR_TAB, not cp 9.

CHR_NUL		equ	0		; null
CHR_SOH		equ	1		; start of heading (Ctrl-A)
CHR_STX		equ	2		; start of text (Ctrl-B)
CHR_ETX		equ	3		; end of text (Ctrl-C)
CHR_EOT		equ	4		; end of transmission (Ctrl-D)
CHR_ENQ		equ	5		; enquiry (Ctrl-E)
CHR_ACK		equ	6		; acknowledge (Ctrl-F)
CHR_BEL		equ	7		; bell/beep (Ctrl-G)
CHR_BS		equ	8		; backspace (Ctrl-H)
CHR_TAB		equ	9		; horizontal tab (Ctrl-I)
CHR_LF		equ	10		; line feed (Ctrl-J)
CHR_VT		equ	11		; vertical tab (Ctrl-K)
CHR_FF		equ	12		; form feed / clear screen (Ctrl-L)
CHR_CR		equ	13		; carriage return (Ctrl-M)
CHR_SO		equ	14		; shift out (Ctrl-N)
CHR_SI		equ	15		; shift in (Ctrl-O)
CHR_DLE		equ	16		; data link escape (Ctrl-P)
CHR_DC1		equ	17		; device control 1 / XON (Ctrl-Q)
CHR_DC2		equ	18		; device control 2 (Ctrl-R)
CHR_DC3		equ	19		; device control 3 / XOFF (Ctrl-S)
CHR_DC4		equ	20		; device control 4 (Ctrl-T)
CHR_NAK		equ	21		; negative acknowledge (Ctrl-U)
CHR_SYN		equ	22		; synchronous idle (Ctrl-V)
CHR_ETB		equ	23		; end of transmission block (Ctrl-W)
CHR_CAN		equ	24		; cancel (Ctrl-X)
CHR_EM		equ	25		; end of medium (Ctrl-Y)
CHR_SUB		equ	26		; substitute (Ctrl-Z)
CHR_ESC		equ	27		; escape
CHR_FS		equ	28		; file separator
CHR_GS		equ	29		; group separator
CHR_RS		equ	30		; record separator
CHR_US		equ	31		; unit separator
CHR_SPACE	equ	32		; space

; Aliases for codes with a second, more meaningful name in MSX-DOS/CP/M

CHR_EOF		equ	CHR_SUB		; Ctrl-Z = text-file end-of-file marker

; Two characters that are not control codes, named here for the same
; reason the codes above are: 027h in a comparison is unreadable, and
; two modules have to recognise them - fields.as, finding the
; end of an operand, and tatara.as, measuring a DB.

QUOTE1		equ	027h		; '
QUOTE2		equ	022h		; "
