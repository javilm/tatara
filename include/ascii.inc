; ascii.inc - the character codes below a space, and what the MSX
; does with them.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	ascii.inc
;
; THE VALUES ARE DECIMAL, which the other files in this set are not.
; A character code is written decimal everywhere else - db 13,10 - and
; making this file agree with CHR$(13) is worth more than making it
; agree with the port numbers.
;
; CODES 1 TO 26 ARE CTRL AND A LETTER: 1 is CTRL-A and 26 is CTRL-Z,
; so the key is never worth stating. Where a key of its own also
; produces the code, the entry names it.
;
; A code with no description does nothing when it is printed. It still
; arrives from the keyboard, so a program reading characters has to
; expect it.

CHR_NUL		equ	0	; null
CHR_SOH		equ	1	; start of heading. ON AN MSX IT IS THE
				;   HEADER FOR A GRAPHIC CHARACTER: print
				;   it, then a code, and the graphic in
				;   that slot comes out
CHR_STX		equ	2	; start of text. Cursor to the start of
				;   the word before it
CHR_ETX		equ	3	; end of text. Ends the wait for input
CHR_EOT		equ	4	; end of transmission
CHR_ENQ		equ	5	; enquiry. Deletes from the cursor to the
				;   end of the screen
CHR_ACK		equ	6	; acknowledge. Cursor to the start of the
				;   next word
CHR_BEL		equ	7	; bell. Sounds the speaker, the same as
				;   the BEEP statement
CHR_BS		equ	8	; backspace. Deletes the character before
				;   the cursor
				;   key: BS
CHR_TAB		equ	9	; tab. To the next tab stop
				;   key: TAB
CHR_LF		equ	10	; line feed
CHR_VT		equ	11	; vertical tab. Cursor home, top left
				;   key: HOME
CHR_FF		equ	12	; form feed. CLEARS THE SCREEN and puts
				;   the cursor home
				;   key: CLS
CHR_CR		equ	13	; carriage return. To the left edge, and
				;   NOT down a line
				;   key: RETURN
CHR_SO		equ	14	; shift out. Cursor to the end of the line
CHR_SI		equ	15	; shift in
CHR_DLE		equ	16	; data link escape
CHR_DC1		equ	17	; device control 1, XON
CHR_DC2		equ	18	; device control 2. Turns insert mode on,
				;   and off again
				;   key: INS
CHR_DC3		equ	19	; device control 3, XOFF
CHR_DC4		equ	20	; device control 4
CHR_NAK		equ	21	; negative acknowledge. Deletes the line
				;   from the screen
CHR_SYN		equ	22	; synchronous idle
CHR_ETB		equ	23	; end of transmission block
CHR_CAN		equ	24	; cancel
				;   key: SELECT
CHR_EM		equ	25	; end of medium
CHR_SUB		equ	26	; substitute
CHR_ESC		equ	27	; escape
				;   key: ESC, or CTRL and [
CHR_FS		equ	28	; file separator. Cursor right
				;   key: the right arrow, or CTRL and the
				;        key carrying the backslash
CHR_GS		equ	29	; group separator. Cursor left
				;   key: the left arrow, or CTRL and ]
CHR_RS		equ	30	; record separator. Cursor up
				;   key: the up arrow, or CTRL and ^
CHR_US		equ	31	; unit separator. Cursor down
				;   key: the down arrow, or CTRL and _
CHR_SPACE	equ	32	; space
CHR_DEL		equ	127	; delete. REMOVES THE CHARACTER THE
				;   CURSOR IS ON, where backspace removes
				;   the one before it
				;   key: DEL

; One code with a second name that says more than the first.

CHR_EOF		equ	CHR_SUB	; CTRL-Z, which is what ends a text file
				;   under MSX-DOS

; Two characters that are not control codes, named for the same
; reason the codes above are: 027h and 022h in a comparison tell a
; reader nothing.

QUOTE1		equ	39	; the apostrophe
QUOTE2		equ	34	; the double quote
