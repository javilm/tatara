; subrom.inc - the SUB ROM entry points.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	subrom.inc
;
; An entry is an address and a line saying what it does. What each one
; wants in its registers, what it gives back and what it destroys are
; in the MSX manuals, and are not repeated here: this file exists so
; that you do not have to write "equ 01f5h" at the top of a program,
; not to replace the books.
;
; THESE ADDRESSES ARE IN THE SUB ROM, WHICH IS IN ANOTHER SLOT. None
; of them can be reached with a plain CALL. Put the address in IX and
; go through EXTROM, which is in bios.inc and finds the SUB ROM's
; slot by itself:
;
;	ld	ix,SUBROM_REDCLK
;	call	EXTROM
;
; The manual gives a second form, for when IX must survive the call:
;
;	push	ix
;	ld	ix,SUBROM_REDCLK
;	jp	SUBROM
;
; SUBROM pushes IX for you, so the pushed copy comes back.
;
; EVERY NAME HERE CARRIES THE PREFIX SUBROM_, and the official name
; follows it. The SUB ROM reuses MAIN ROM names for different
; routines at different addresses - GRPPRT is 008Dh in the MAIN ROM
; and 0089h here - so without the prefix this file and bios.inc
; could not both be included.
;
; THE SUB ROM JUMP TABLE STEPS FOUR BYTES, not the three the MAIN
; ROM uses. A gap of eight between two entries here is one slot,
; not two.
;
; The SUB ROM arrived with the MSX2. An MSX1 has none, and nothing in
; this file can be called there.

; --- The graphics screens.

SUBROM_GRPPRT	equ	0089h	; put the character in A on a graphics screen.
				;   SCREEN 5 TO 8 ONLY

; --- Boxes. Both take the same six parameters: BC the X of the
; starting corner, DE its Y, then GXPOS and GYPOS for the far
; corner, ATRBYT for the colour and LOGOPR for the logical
; operation. Only two of the six are in registers.

SUBROM_NVBXLN	equ	00c9h	; draw the outline of a box
SUBROM_NVBXFL	equ	00cdh	; draw a box and fill it

; --- Screen modes. The INI entries set a mode up; SETTXT sets the
; VDP and nothing else, the same split the MAIN ROM makes. Each
; reads its table addresses from the work area.

SUBROM_CHGMOD	equ	00d1h	; change the screen mode, 0 to 8, the number in
				;   A. SUBROM_CHGMDP 01B5h is the one that sets
				;   the palette with it
SUBROM_INITXT	equ	00d5h	; set up TEXT1 - 40 by 24 - from TXTNAM and
				;   TXTCGP
SUBROM_INIT32	equ	00d9h	; set up TEXT2 - 32 by 24 - from T32NAM,
				;   T32COL, T32CGP, T32ATR and T32PAT
SUBROM_INIGRP	equ	00ddh	; set up the high resolution graphics mode from
				;   GRPNAM, GRPCOL, GRPCGP, GRPATR and GRPPAT
SUBROM_INIMLT	equ	00e1h	; set up MULTI COLOR from MLTNAM, MLTCOL,
				;   MLTCGP, MLTATR and MLTPAT
SUBROM_SETTXT	equ	00e5h	; put the VDP into TEXT1 - 40 by 24 - and
				;   nothing else. Same work area addresses as
				;   SUBROM_INITXT

SUBROM_SETT32	equ	00e9h	; the VDP into TEXT2 - 32 by 24
SUBROM_SETGRP	equ	00edh	; the VDP into the high resolution graphics
				;   mode
SUBROM_SETMLT	equ	00f1h	; the VDP into MULTI COLOR

; --- Sprites. CALPAT, CALATR and GSPSIZ ARE THE SAME ROUTINES AS
; the MAIN ROM entries of the same name, which the manual says
; outright. They are here so that a program already in the SUB ROM
; need not come back out for them.

SUBROM_CLRSPR	equ	00f5h	; clear every sprite: pattern null, each sprite
				;   number set to its own plane number, colour
				;   the foreground colour, vertical position
				;   217. Reads SCRMOD
SUBROM_CALPAT	equ	00f9h	; the VRAM address of sprite A pattern in the
				;   sprite generator table, returned in HL
SUBROM_CALATR	equ	00fdh	; the VRAM address of sprite A entry in the
				;   sprite attribute table, returned in HL
SUBROM_GSPSIZ	equ	0101h	; the size of a sprite now, in bytes, in A.
				;   CARRY COMES BACK SET ONLY WHEN SPRITES ARE
				;   16 BY 16

; --- Characters and VRAM.

SUBROM_GETPAT	equ	0105h	; fetch the pattern of the character in A. THE
				;   PATTERN COMES BACK IN PATWRK, not in a
				;   register
SUBROM_WRTVRM	equ	0109h	; write A into the VRAM byte at HL, ALL SIXTEEN
				;   BITS of the address. The MAIN ROM WRTVRM
				;   004Dh takes only fourteen

SUBROM_RDVRM	equ	010dh	; read the VRAM byte at HL into A, ALL SIXTEEN
				;   BITS of the address. The MAIN ROM RDVRM
				;   004Ah takes only fourteen
SUBROM_CHGCLR	equ	0111h	; change the screen colours to the three
				;   already put in FORCLR, BAKCLR and BDRCLR. A
				;   is the screen mode
SUBROM_CLSSUB	equ	0115h	; clear the screen
SUBROM_DSPFNK	equ	011dh	; display the function key strip
SUBROM_WRTVDP	equ	012dh	; write B into the VDP register numbered in C
SUBROM_VDPSTA	equ	0131h	; read the VDP register numbered in A, 0 to 9,
				;   back into A. RDVDP 013Eh in the MAIN ROM is
				;   the TMS9918 one and takes no number
SUBROM_SETPAG	equ	013dh	; switch VRAM pages: DPPAGE names the one to
				;   display, ACPAGE the one to draw on. PAGE
				;   638 SPELLS THE FIRST DDPAGE

; --- The palette. The two below are a pair: SUBROM_INIPLT puts the
; palette back to the one the machine starts with AND THE ONE IT
; REPLACED IS KEPT IN VRAM, where SUBROM_RSTPLT fetches it from.
; SUBROM_INIPLT is the one the screen mode entries in bios.inc send
; you to.

SUBROM_INIPLT	equ	0141h	; set the palette to the starting one. THE
				;   PALETTE IT REPLACES IS SAVED IN VRAM
SUBROM_RSTPLT	equ	0145h	; put the palette back from the copy in VRAM

SUBROM_GETPLT	equ	0149h	; read palette entry A, 0 to 15. B comes back
				;   with red in its top four bits and blue in
				;   its bottom four, C with green in its bottom
				;   four
SUBROM_SETPLT	equ	014dh	; write palette entry D, 0 to 15. A carries red
				;   in its top four bits and blue in its bottom
				;   four, E green in its bottom four

; --- The rest.

SUBROM_BEEP	equ	017dh	; sound the buzzer
SUBROM_PROMPT	equ	0181h	; display the prompt
SUBROM_NEWPAD	equ	01adh	; read a light pen or a mouse. A in is a device
				;   id, 8 to 19, and the ids run in the same
				;   fours as GTPAD in bios.inc - 8 the light
				;   pen, 12 the first mouse, 16 the second. THE
				;   TOUCH PANEL IDS 0 TO 7 ARE NOT HERE
SUBROM_CHGMDP	equ	01b5h	; change the VDP mode, 0 to 8 in A, AND
				;   INITIALISE THE PALETTE WITH IT.
				;   SUBROM_CHGMOD 00D1h is the one that leaves
				;   the palette alone
SUBROM_KNJPRT	equ	01bdh	; MSX2+. Put the JIS kanji code in BC on a
				;   graphics screen, SCREEN 5 TO 8 ONLY, at
				;   GRPACX and GRPACY. A picks the shape: 0 all
				;   16 by 16 dots, 1 the even dots, 2 the odd
				;   ones. MSX2 reaches level 1 kanji, MSX2+
				;   levels 1 and 2

; --- CLOCK-IC, and the memory the battery keeps. The value in C is
; not a plain register number: bits 3 to 0 are the register and bits
; 5 and 4 are the block it lives in - page 643 calls that the mode -
; so one call does what would otherwise be a write to the MODE
; register followed by a read.

SUBROM_REDCLK	equ	01f5h	; read the CLOCK-IC register named in C into A.
				;   ONLY THE LOW FOUR BITS OF THE ANSWER MEAN
				;   ANYTHING
SUBROM_WRTCLK	equ	01f9h	; write the low four bits of A to the CLOCK-IC
				;   register named in C

