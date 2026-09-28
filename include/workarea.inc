; workarea.inc - the MSX system work area.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	workarea.inc
;
; THE NUMBER AFTER THE SEMICOLON IS THE LENGTH IN BYTES. One byte is
; read with "ld a,(LABEL)" and two with "ld hl,(LABEL)", and getting
; that wrong is the easiest way to read a work area entry and come
; away with an answer that is almost right.
;
; The names are the standard ones, uppercase, as the MSX documentation
; prints them. UNDER /C THEY ARE CASE-SENSITIVE, so write them as they
; appear here.
;
; The area is not one run of bytes: the gaps between the groups below
; belong to the system and are not published.

; --- Disk drive. Present only on a machine with a disk interface.

DISKVE		equ	0f323h	; 2  -> the pointer to the disk error routine
BREAKV		equ	0f325h	; 2  -> the pointer to the CTRL-C routine
RAMAD0		equ	0f341h	; 1  slot address of the RAM in page 0
RAMAD1		equ	0f342h	; 1  slot address of the RAM in page 1
RAMAD2		equ	0f343h	; 1  slot address of the RAM in page 2
RAMAD3		equ	0f344h	; 1  slot address of the RAM in page 3
MASTERS		equ	0f348h	; 1  slot address of the master cartridge

; --- Inter-slot call. THESE ARE ROUTINES, NOT VARIABLES: the system
; copies the code here at boot because a routine that switches slots
; cannot live in a slot it is about to switch away. Call them.

RDPRIM		equ	0f380h	; 5  read a byte from a primary slot
WRPRIM		equ	0f385h	; 7  write a byte to a primary slot
CLPRIM		equ	0f38ch	; 14 call a routine in a primary slot

; --- USR entry points, and the text screen.

USRTAB		equ	0f39ah	; 20 the start addresses of USR(0) to USR(9),
				;    two bytes each. Each one points at the
				;    BASIC error routine until DEFUSR sets it
LINL40		equ	0f3aeh	; 1  line width in SCREEN 0, set by WIDTH
LINL32		equ	0f3afh	; 1  line width in SCREEN 1, set by WIDTH
LINLEN		equ	0f3b0h	; 1  line width of the current screen
CRTCNT		equ	0f3b1h	; 1  number of lines on the current screen
CLMLST		equ	0f3b2h	; 1  PRINT control: LINLEN minus
				;    (LINLEN MOD 14) minus 14

; --- The VRAM address of each table, per screen mode, and a few other
; screen settings. Each entry is an address INSIDE VRAM.

TXTNAM		equ	0f3b3h	; 2  SCREEN 0 pattern name table
TXTCOL		equ	0f3b5h	; 2  SCREEN 0 colour table	; MSX2
TXTCGP		equ	0f3b7h	; 2  SCREEN 0 pattern generator table
TXTATR		equ	0f3b9h	; 2  unused
TXTPAT		equ	0f3bbh	; 2  unused
T32NAM		equ	0f3bdh	; 2  SCREEN 1 pattern name table
T32COL		equ	0f3bfh	; 2  SCREEN 1 colour table
T32CGP		equ	0f3c1h	; 2  SCREEN 1 pattern generator table
T32ATR		equ	0f3c3h	; 2  SCREEN 1 sprite attribute table
T32PAT		equ	0f3c5h	; 2  SCREEN 1 sprite generator table
GRPNAM		equ	0f3c7h	; 2  SCREEN 2 pattern name table
GRPCOL		equ	0f3c9h	; 2  SCREEN 2 colour table
GRPCGP		equ	0f3cbh	; 2  SCREEN 2 pattern generator table
GRPATR		equ	0f3cdh	; 2  SCREEN 2 sprite attribute table
GRPPAT		equ	0f3cfh	; 2  SCREEN 2 sprite generator table
MLTNAM		equ	0f3d1h	; 2  SCREEN 3 pattern name table
MLTCOL		equ	0f3d3h	; 2  unused
MLTCGP		equ	0f3d5h	; 2  SCREEN 3 pattern generator table
MLTATR		equ	0f3d7h	; 2  SCREEN 3 sprite attribute table
MLTPAT		equ	0f3d9h	; 2  SCREEN 3 sprite generator table
CLIKSW		equ	0f3dbh	; 1  key click: 0 off, anything else on
CSRY		equ	0f3dch	; 1  cursor row
CSRX		equ	0f3ddh	; 1  cursor column
CNSDFG		equ	0f3deh	; 1  function key display: 0 hidden,
				;    anything else shown

; --- Where the VDP registers are remembered. The BIOS writes a VDP
; register by writing here first, so a program that sets a register
; behind its back will be undone by the next BIOS call that touches
; the same one. The eight are contiguous and may be indexed.

RG0SAV		equ	0f3dfh	; 1  VDP register 0
RG1SAV		equ	0f3e0h	; 1  VDP register 1
RG2SAV		equ	0f3e1h	; 1  VDP register 2
RG3SAV		equ	0f3e2h	; 1  VDP register 3
RG4SAV		equ	0f3e3h	; 1  VDP register 4
RG5SAV		equ	0f3e4h	; 1  VDP register 5
RG6SAV		equ	0f3e5h	; 1  VDP register 6
RG7SAV		equ	0f3e6h	; 1  VDP register 7
STATFL		equ	0f3e7h	; 1  the VDP status register. On MSX2 and
				;    later machines, status register 0

; --- The same area continues: the default colours, two routines
; LINE patches, and the key buffer pointers.

TRGFLG		equ	0f3e8h	; 1  the joystick trigger buttons
FORCLR		equ	0f3e9h	; 1  default foreground colour
BAKCLR		equ	0f3eah	; 1  default background colour
BDRCLR		equ	0f3ebh	; 1  default border colour
MAXUPD		equ	0f3ech	; 3  LINE writes a JP here and calls it
MINUPD		equ	0f3efh	; 3  the same, for the other direction
ATRBYT		equ	0f3f2h	; 1  the colour graphics are drawn in
QUEUES		equ	0f3f3h	; 2  -> the queue table PLAY uses
FRCNEW		equ	0f3f5h	; 1  used by the BASIC interpreter
SCNCNT		equ	0f3f6h	; 1  how often the keyboard is scanned,
				;    normally 1. CHGET SETS IT BACK, so a
				;    program changing the repeat rate must
				;    set it before every CHGET call
REPCNT		equ	0f3f7h	; 1  delay before a held key repeats,
				;    normally 50. CHGET SETS THIS BACK TOO
PUTPNT		equ	0f3f8h	; 2  -> where the next key goes INTO the
				;    key buffer
GETPNT		equ	0f3fah	; 2  -> where the next key comes OUT of it

; --- Cassette parameters. The widths are in units the tape routines
; count in, not microseconds.

CS120		equ	0f3fch	; 10 two groups of five. 1200 baud first:
				;    the LOW and HIGH widths of a 0, the
				;    LOW and HIGH widths of a 1, and the
				;    short-header bit length. Then the
				;    same five for 2400 baud
CSLOW		equ	0f406h	; 2  the LOW and HIGH widths of a 0 at the
				;    rate in use. Set by SCREEN.
				;    Official name: LOW - see the note at
				;    the end of this file
CSHIGH		equ	0f408h	; 2  the same pair for a 1. Set by SCREEN.
				;    Official name: HIGH
HEADER		equ	0f40ah	; 1  the short-header bit length at the
				;    rate in use. Set by SCREEN
ASPCT1		equ	0f40bh	; 2  256 divided by the aspect ratio. Set
				;    by SCREEN, read by CIRCLE
ASPCT2		equ	0f40dh	; 2  256 times the aspect ratio
ENDPRG		equ	0f40fh	; 5  a pretend end of program, so that
				;    RESUME NEXT has somewhere to go

; --- What BASIC keeps for itself. Reading these is how a machine
; code program finds out what the interpreter is doing; writing them
; is how it confuses the interpreter.

ERRFLG		equ	0f414h	; 1  the last error code
LPTPOS		equ	0f415h	; 1  the printer head position
PRTFLG		equ	0f416h	; 1  send output to the printer
NTMSXP		equ	0f417h	; 1  0 if the printer is an MSX printer.
				;    Zero also means hiragana is turned
				;    into katakana on the way out, which is
				;    what a printer that cannot print
				;    hiragana needs. Anything else sends
				;    hiragana as it stands
RAWPRT		equ	0f418h	; 1  not zero: print raw, with no character
				;    code translation. Zero, which is the
				;    usual state, turns a tab (09h) into
				;    spaces. SET THIS BEFORE SENDING A BIT
				;    IMAGE, or every 09h byte in the image
				;    becomes a row of spaces
VLZADR		equ	0f419h	; 2  -> the character VAL overwrote
VLZDAT		equ	0f41bh	; 1  the character VAL overwrote it with
CURLIN		equ	0f41ch	; 2  the line number BASIC is running
KBUF		equ	0f41fh	; 318 the crunch buffer: BUF turned into
				;    the tokens BASIC stores
BUFMIN		equ	0f55dh	; 1  a comma, so that INPUT can start
				;    reading at one
BUF		equ	0f55eh	; 258 what was typed, as characters.
				;    MSX-AUDIO BORROWS THE FIRST FOUR
				;    BYTES: an MBIOS call leaves IX and IY
				;    here, low byte first, IX then IY,
				;    because an inter-slot call has no room
				;    for them. See the MSX-AUDIO section of
				;    extbio.inc
ENDBUF		equ	0f660h	; 1  guards the end of BUF
TTYPOS		equ	0f661h	; 1  where BASIC thinks the cursor is
DIMFLG		equ	0f662h	; 1  distinguishes an array from a simple
				;    variable
VALTYP		equ	0f663h	; 1  the type of a variable
OPRTYP		equ	0f664h	; 1  the saved operator, or whether a word
				;    can be crunched
DONUM		equ	0f665h	; 1  a crunch flag
CONTXT		equ	0f666h	; 2  -> the text pointer CHGET saved
CONSAV		equ	0f668h	; 1  the token of a constant, saved after
				;    CHGET
CONTYP		equ	0f669h	; 1  the type of that constant
CONLO		equ	0f66ah	; 8  the value of that constant
MEMSIZ		equ	0f672h	; 2  the highest address BASIC uses
STKTOP		equ	0f674h	; 2  the highest address usable as stack.
				;    CLEAR moves it
TXTTAB		equ	0f676h	; 2  -> the start of the BASIC program
TEMPPT		equ	0f678h	; 2  -> the first free temporary descriptor
TEMPST		equ	0f67ah	; 30 the temporary descriptors themselves
DSCTMP		equ	0f698h	; 3  the descriptor for the answer of a
				;    string function
FRETOP		equ	0f69bh	; 2  -> the first free byte of string space
TEMP3		equ	0f69dh	; 2  garbage collection
TEMP8		equ	0f69fh	; 2  garbage collection
ENDFOR		equ	0f6a1h	; 2  -> the address after a FOR
DATLIN		equ	0f6a3h	; 2  the line number READ last read a DATA
				;    statement from
SUBFLG		equ	0f6a5h	; 1  set while USR and friends use an array
FLGINP		equ	0f6a6h	; 1  used by INPUT and READ
TEMP		equ	0f6a7h	; 2  a statement code, kept for a moment


; --- Still BASIC: AUTO, the error statements, and where the program
; and its variables begin and end.

PTRFLG		equ	0f6a9h	; 1  not zero if there is a line number to
				;    convert
AUTFLG		equ	0f6aah	; 1  not zero while AUTO is on
AUTLIN		equ	0f6abh	; 2  the last line number AUTO offered
AUTINC		equ	0f6adh	; 2  the step AUTO adds
SAVTXT		equ	0f6afh	; 2  -> the text RESUME returns to
SAVSTK		equ	0f6b1h	; 2  the stack the error routine saved
ERRLIN		equ	0f6b3h	; 2  the line the error happened in
DOT		equ	0f6b5h	; 2  the current line - what the dot means
				;    in LIST.
ERRTXT		equ	0f6b7h	; 2  the same line number, for RESUME
ONELIN		equ	0f6b9h	; 2  the line ON ERROR GOTO names
ONEFLG		equ	0f6bbh	; 1  1 while the error handler is running
TEMP2		equ	0f6bch	; 2  somewhere to put something briefly
OLDLIN		equ	0f6beh	; 2  the line CTRL-STOP, END or STOP
				;    stopped at
OLDTXT		equ	0f6c0h	; 2  -> the statement that would run next
VARTAB		equ	0f6c2h	; 2  -> the simple variables. NEW sets it
				;    to (TXTTAB) plus 2
ARYTAB		equ	0f6c4h	; 2  -> the array table
STREND		equ	0f6c6h	; 2  -> the last byte BASIC is using for
				;    the program and its variables
DATPTR		equ	0f6c8h	; 2  -> the text READ last read from
DEFTBL		equ	0f6cah	; 26 the default type of a variable, one
				;    byte per initial letter A to Z

; --- The parameters of a DEF FN function, twice over: PARM1 is the
; definition and PARM2 is the call.

PRMSTK		equ	0f6e4h	; 2  -> the previous definition block on
				;    the stack, for garbage collection
PRMLEN		equ	0f6e6h	; 2  the length of the table in hand
PARM1		equ	0f6e8h	; 100 the parameter definition table
PRMPRV		equ	0f74ch	; 2  -> the previous parameter block, for
				;    garbage collection
PRMLN2		equ	0f74eh	; 2  the length of that block
PARM2		equ	0f750h	; 100 where the parameters themselves go
PRMFLG		equ	0f7b4h	; 1  set once PARM1 has been searched
ARYTA2		equ	0f7b5h	; 2  where that search stops
NOFUNS		equ	0f7b7h	; 1  zero when there is no function in hand
TEMP9		equ	0f7b8h	; 2  garbage collection
FUNACT		equ	0f7bah	; 2  how many functions are in hand
SWPTMP		equ	0f7bch	; 8  the first variable of a SWAP, while
				;    the second is being moved
TRCFLG		equ	0f7c4h	; 1  0 TRACE OFF, anything else TRACE ON

; --- The Math-pack. DAC is the accumulator and ARG is the other
; operand: the floating point routines take their arguments here and
; leave their answer in DAC.

FBUFFR		equ	0f7c5h	; 43 scratch for the Math-pack routines
DECTMP		equ	0f7f0h	; 2  decimal to floating point
DECTM2		equ	0f7f2h	; 2  the division routine
DECCNT		equ	0f7f4h	; 1  the division routine
DAC		equ	0f7f6h	; 16 THE ACCUMULATOR. Put the value to
				;    work on here
HOLD8		equ	0f806h	; 48 registers, saved across a decimal
				;    multiplication
HOLD2		equ	0f836h	; 8  Math-pack scratch
HOLD		equ	0f83eh	; 8  Math-pack scratch
ARG		equ	0f847h	; 16 the second operand, the one DAC is
				;    combined with
RNDX		equ	0f857h	; 8  the first random number, as a double
				;    precision value

; --- Files, function keys, and where the screen tables are now.

MAXFIL		equ	0f85fh	; 1  the highest file number MAXFILES
				;    allows
FILTAB		equ	0f860h	; 2  -> the file data
NULBUF		equ	0f862h	; 2  -> the buffer SAVE and LOAD use
PTRFIL		equ	0f864h	; 2  -> the file data of the file in hand
RUNFLG		equ	0f866h	; 0  not zero: run the program once it is
				;    loaded. LENGTH ZERO IS NOT A MISPRINT -
				;    it shares its byte with FILNAM below
FILNAM		equ	0f866h	; 11 a filename
FILNM2		equ	0f871h	; 11 a second filename
NLONLY		equ	0f87ch	; 1  not zero while a program is loading
SAVEND		equ	0f87dh	; 2  the last address SAVE will write
FNKSTR		equ	0f87fh	; 160 the ten function key strings, sixteen
				;    characters each. A string ends with a
				;    zero byte, so fifteen characters is
				;    the most one key holds. Pressing the
				;    key pushes its string into KEYBUF
CGPNT		equ	0f91fh	; 3  the slot and address of the character
				;    font in ROM
NAMBAS		equ	0f922h	; 2  -> the pattern name table in use now
CGPBAS		equ	0f924h	; 2  -> the pattern generator table
PATBAS		equ	0f926h	; 2  -> the sprite generator table

; --- The rest of the screen bases, and the graphics scratch.

ATRBAS		equ	0f928h	; 2  -> the sprite attribute table in use
CLOC		equ	0f92ah	; 2  the graphics routines, internally
CMASK		equ	0f92ch	; 1  the same
MINDEL		equ	0f92dh	; 2  the same
MAXDEL		equ	0f92fh	; 2  the same

; --- CIRCLE and PAINT. Most of it is scratch the two statements use
; while they run; the few entries that mean something on their own
; say what.

ASPECT		equ	0f931h	; 2  the ratio CIRCLE draws to, from its
				;    own ratio argument
CENCNT		equ	0f933h	; 2  CIRCLE, internally
CLINEF		equ	0f935h	; 1  draw a line to the centre
CNPNTS		equ	0f936h	; 2  the points to plot
CPLOTF		equ	0f938h	; 1  CIRCLE, internally
CPCNT		equ	0f939h	; 2  how many eighths of the circle
CPCNT8		equ	0f93bh	; 2  CIRCLE, internally
CRCSUM		equ	0f93dh	; 2  CIRCLE, internally
CSTCNT		equ	0f93fh	; 2  CIRCLE, internally
CSCLXY		equ	0f941h	; 1  the X and Y scale
CSAVEA		equ	0f942h	; 2  saved for ADVGRP
CSAVEM		equ	0f944h	; 1  saved for ADVGRP
CXOFF		equ	0f945h	; 2  X offset from the centre
CYOFF		equ	0f947h	; 2  Y offset from the centre
LOHMSK		equ	0f949h	; 1  PAINT, internally
LOHDIR		equ	0f94ah	; 1  PAINT, internally
LOHADR		equ	0f94bh	; 2  PAINT, internally
LOHCNT		equ	0f94dh	; 2  PAINT, internally
SKPCNT		equ	0f94fh	; 2  the skip count
MOVCNT		equ	0f951h	; 2  the move count
PDIREC		equ	0f953h	; 1  the direction PAINT is going
LFPROG		equ	0f954h	; 1  PAINT, internally
RTPROG		equ	0f955h	; 1  PAINT, internally

; --- PLAY. The three voice queues are 128 bytes each. That length is
; usually quoted as MUSQLN, a constant nobody writes down; the
; addresses say it three times, F975 to F9F5 to FA75, and then
; exactly on to the MSX2 area at FAF5.

MCLTAB		equ	0f956h	; 2  -> the PLAY and DRAW macro table
MCLFLG		equ	0f958h	; 1  which of the two is meant
QUETAB		equ	0f959h	; 24 the queue table, four queues of six
QUEBAK		equ	0f971h	; 4  used by BCKQ
VOICAQ		equ	0f975h	; 128 the queue for voice 1
VOICBQ		equ	0f9f5h	; 128 the queue for voice 2
VOICCQ		equ	0fa75h	; 128 the queue for voice 3

; --- Added in MSX2. Every entry below needs an MSX2 or later; on an
; MSX1 the addresses hold whatever the machine left there.

DPPAGE		equ	0faf5h	; 1  the page being displayed	; MSX2
ACPAGE		equ	0faf6h	; 1  the page being drawn on	; MSX2
AVCSAV		equ	0faf7h	; 1  the AV control port, saved	; MSX2
EXBRSA		equ	0faf8h	; 1  THE SUB ROM SLOT		; MSX2
				;    Every SUB ROM call needs it. THIS IS THE
				;    SLOT BYTE EVERY SLOT ROUTINE TAKES:
				;      bits 1,0  the primary slot, 0 to 3
				;      bits 3,2  which expansion slot of it
				;      bit 7     1 if that primary is expanded
				;      bits 6,5,4 unused
CHRCNT		equ	0faf9h	; 1  romaji to kana: how many	; MSX2
				;    characters are in hand, 0 to 2
ROMA		equ	0fafah	; 2  romaji to kana: the chars	; MSX2
				;    themselves, in the buffer
MODE		equ	0fafch	; 1  romaji mode, VRAM size	; MSX2
				;    Bit by bit, 7 down to 0:
				;      7  0 hiragana, 1 katakana
				;      6  1 if the level 2 kanji ROM is there
				;      5  0 SCREEN 10, 1 SCREEN 11 (on MSX2+,
				;         the RGB flag)
				;      4  0 clip, 1 do not clip
				;      3  1 to AND a SCREEN 0 to 3 VRAM
				;         address with 3FFFh. SCREEN 4 and
				;         above never mask
				;      2,1  VRAM: 00 is 16K, 01 is 64K,
				;         10 is 128K
				;      0  1 to convert romaji
NORUSE		equ	0fafdh	; 1  the kanji driver uses it	; MSX2
XSAVE		equ	0fafeh	; 2  the light pen X, low byte	; MSX2
				;    The top bit of the high byte is set
				;    when the pen has raised an interrupt.
				;    The other seven bits of it are an
				;    unsigned offset
YSAVE		equ	0fb00h	; 2  the light pen Y, low byte	; MSX2


LOGOPR		equ	0fb02h	; 1  the logical operation code	; MSX2
				;    V9938 and later

; --- RS-232C, and the disk. RSTMP IS AN UMBRELLA: it names the whole
; 50-byte area, and every entry from TOCNT to DRVTBL lives inside it.
; 0FB29h to 0FB34h is the unnamed tail of it, and 0FB35h, where the
; next table starts, is exactly where the 50 bytes end.

RSTMP		equ	0fb03h	; 50 the whole area, RS-232C or disk
TOCNT		equ	0fb03h	; 1  RS-232C, internally
RSFCB		equ	0fb04h	; 2  the RS-232C address, low byte then
				;    high. Only the low byte is named
RSIQLN		equ	0fb06h	; 1  RS-232C, internally
MEXBIH		equ	0fb07h	; 5  A HOOK, not a variable: RST 30h, a
				;    byte, an address low then high, and a
				;    RET. Five bytes you may rewrite
OLDSTT		equ	0fb0ch	; 5  the same shape
OLDINT		equ	0fb11h	; 5  the same shape
DEVNUM		equ	0fb16h	; 1  RS-232C, internally
DATCNT		equ	0fb17h	; 3  a byte, then two bytes of pointer
ERRORS		equ	0fb1ah	; 1  RS-232C, internally
FLAGS		equ	0fb1bh	; 1  RS-232C, internally
ESTBLS		equ	0fb1ch	; 1  RS-232C, internally
COMMSK		equ	0fb1dh	; 1  RS-232C, internally
LSTCOM		equ	0fb1eh	; 1  RS-232C, internally
LSTMOD		equ	0fb1fh	; 1  RS-232C, internally
HOKVLD		equ	0fb20h	; 1  BIT 0 SAYS WHETHER THE EXTENDED BIOS
				;    IS THERE. Clear means it is not, and
				;    then EXTBIO in hooks.inc must not be
				;    called at all. Test the bit, not the
				;    byte
DRVTBL		equ	0fb21h	; 8  the DISK ROM slot address, and more

; --- PLAY. From here down the area is the same on an MSX1. The
; three voice control blocks are 37 bytes each - a length usually
; quoted as VCBSIZ and rarely as a number. FB41 to FB66 to FB8B,
; then exactly on to FBB0, says 37 three times.

PRSCNT		equ	0fb35h	; 1  PLAY, internally
SAVSP		equ	0fb36h	; 2  the stack pointer, kept while PLAY runs
VOICEN		equ	0fb38h	; 1  the voice being interpreted
SAVVOL		equ	0fb39h	; 2  the volume, kept across a rest
MCLLEN		equ	0fb3bh	; 1  PLAY, internally
MCLPTR		equ	0fb3ch	; 2  PLAY, internally
QUEUEN		equ	0fb3eh	; 1  PLAY, internally
MUSICF		equ	0fb3fh	; 1  the interrupt flag that drives the
				;    music
PLYCNT		equ	0fb40h	; 1  how many PLAY statements are queued
VCBA		equ	0fb41h	; 37 the voice control block for voice 1
VCBB		equ	0fb66h	; 37 voice 2
VCBC		equ	0fb8bh	; 37 voice 3

; --- The keyboard, the function keys, and the ends of memory.

ENSTOP		equ	0fbb0h	; 1  not zero: CTRL-SHIFT-GRAPH-KANA will
				;    warm start the machine
BASROM		equ	0fbb1h	; 1  not zero: the BASIC program is in ROM
LINTTB		equ	0fbb2h	; 24 the line terminator table, one byte per
				;    screen line
FSTPOS		equ	0fbcah	; 2  where the first character of the line
				;    INLIN read is
CODSAV		equ	0fbcch	; 1  the character the cursor is sitting on
FNKSWI		equ	0fbcdh	; 1  which function key row is displayed
FNKFLG		equ	0fbceh	; 10 which function keys are being trapped
ONGSBF		equ	0fbd8h	; 1  the global event flag
CLIKFL		equ	0fbd9h	; 1  the key click flag
OLDKEY		equ	0fbdah	; 11 the key matrix as it was
NEWKEY		equ	0fbe5h	; 11 the key matrix as it is now
SFTKEY		equ	0fbebh	; 1  NEWKEY plus 6: the row holding RETURN,
				;    CTRL and SHIFT
KEYBUF		equ	0fbf0h	; 40 the key code buffer PUTPNT and GETPNT
				;    walk round
BUFEND		equ	0fc18h	; 0  the end of KEYBUF. LENGTH ZERO AGAIN -
				;    it is a marker, and LINWRK starts here
LINWRK		equ	0fc18h	; 40 scratch for the screen handler
PATWRK		equ	0fc40h	; 8  scratch for the pattern converter
BOTTOM		equ	0fc48h	; 2  the lowest address of the RAM fitted
HIMEM		equ	0fc4ah	; 2  the highest address a program may use

TRPTBL		equ	0fc4ch	; 78 the interrupt trap table, three bytes
				;    for each of 26 traps. The length is
				;    usually quoted as 3 times NUMTPR;
				;    0FC4Ch to 0FC9Ah makes NUMTPR 26

; --- Interrupts, the cursor, the graphics accumulator, and the slot
; tables.

RTYCNT		equ	0fc9ah	; 1  BASIC, internally
INTFLG		equ	0fc9bh	; 1  PUT 03h HERE TO STOP A PROGRAM, which
				;    is what CTRL-STOP does
PADY		equ	0fc9ch	; 1  a paddle coordinate - see the note at
				;    the end of this file
PADX		equ	0fc9dh	; 1  the other one
JIFFY		equ	0fc9eh	; 2  PLAY, internally
INTVAL		equ	0fca0h	; 2  the interval ON INTERVAL GOSUB set
INTCNT		equ	0fca2h	; 2  the counter that interval runs down
LOWLIM		equ	0fca4h	; 1  used while reading a cassette
WINWID		equ	0fca5h	; 1  used while reading a cassette
GRPHED		equ	0fca6h	; 1  set while a graphic character is being
				;    printed
ESCCNT		equ	0fca7h	; 1  how far into an escape sequence
INSFLG		equ	0fca8h	; 1  insert mode
CSRSW		equ	0fca9h	; 1  show the cursor or not
CSTYLE		equ	0fcaah	; 1  the cursor shape: 0 a block, anything
				;    else an underline
CAPST		equ	0fcabh	; 1  the CAPS key: 0 off, anything else on
KANAST		equ	0fcach	; 1  the KANA key: 0 off, anything else on
KANAMD		equ	0fcadh	; 1  not zero if kana is in the JIS layout
FLBMEM		equ	0fcaeh	; 1  zero while a BASIC program loads
SCRMOD		equ	0fcafh	; 1  THE SCREEN MODE NUMBER, 0 upwards
OLDSCR		equ	0fcb0h	; 1  the screen mode before this one
CASPRV		equ	0fcb1h	; 1  a character CAS: kept back
BRDATR		equ	0fcb2h	; 1  the border colour PAINT uses
GXPOS		equ	0fcb3h	; 2  the X coordinate
GYPOS		equ	0fcb5h	; 2  the Y coordinate
GRPACX		equ	0fcb7h	; 2  the graphics accumulator, X
GRPACY		equ	0fcb9h	; 2  the graphics accumulator, Y
DRWFLG		equ	0fcbbh	; 1  DRAW, internally
DRWSCL		equ	0fcbch	; 1  the DRAW scale factor. Zero means no
				;    scaling
DRWANG		equ	0fcbdh	; 1  the DRAW angle, 0 to 3
RUNBNF		equ	0fcbeh	; 1  whether this is a BLOAD, a BSAVE or
				;    neither
SAVENT		equ	0fcbfh	; 2  the address BSAVE starts at
EXPTBL		equ	0fcc1h	; 4  ONE BYTE PER PRIMARY SLOT. Bit 7 says
				;    whether that slot is expanded, and every
				;    piece of slot handling starts here.
				;    THE FIRST BYTE DOES DOUBLE DUTY: 0FCC1h
				;    is the whole slot byte of the MAIN ROM,
				;    not just its expanded bit, which is why
				;    ld iy,(EXPTBL-1) fetches it into IYh.
				;    In 0FCC2h to 0FCC4h only bit 7 is used
SLTTBL		equ	0fcc5h	; 4  what each expansion slot register was
				;    last set to, one byte per primary slot,
				;    TWO BITS PER PAGE: bits 1,0 are page 0
				;    and bits 7,6 are page 3. The register
				;    itself does not read back plainly - see
				;    EXPSLT - so this is where the value is
SLTATR		equ	0fcc9h	; 64 one byte for each of the 64 slot and
				;    page pairs, 0FCC9h being slot 0-0 page 0
				;    and 0FD08h slot 3-3 page 3. Three bits
				;    are used, and each is 1 for present:
				;      bit 5  an extended statement handler
				;      bit 6  an extended device handler
				;      bit 7  BASIC text
SLTWRK		equ	0fd09h	; 128 two bytes of work area for each of
				;    the same 64 pairs, for whatever is in
				;    that slot. 0FD09h is slot 0-0 page 0 and
				;    0FD87h is slot 3-3 page 3.
				;    TWO BYTES IS AN ADDRESS, NOT A VALUE,
				;    and two tenants may share the pair: the
				;    FM BIOS keeps its work area address
				;    here alongside MSX-MUSIC extended
				;    BASIC, which is why that address has to
				;    be even. See FMBIOS_INIOPL in
				;    extbio.inc
PROCNM		equ	0fd89h	; 16 the name after CALL, as characters. A
				;    zero byte ends it
DEVICE		equ	0fd99h	; 1  which device a cartridge is


; --- The top of memory, after the hooks. THE VDP REGISTER SAVE AREA
; IS IN THREE PIECES: registers 0 to 7 are at 0F3DFh, near the top
; of this file, 8 to 23 are here, and 25 to 27 are above the gap at
; 0FFF7h. Register 24 has no save area at all.

RG8SAV		equ	0ffe7h	; 1  VDP register 8		; MSX2
RG9SAV		equ	0ffe8h	; 1  VDP register 9		; MSX2
RG10SA		equ	0ffe9h	; 1  VDP register 10		; MSX2
RG11SA		equ	0ffeah	; 1  VDP register 11		; MSX2
RG12SA		equ	0ffebh	; 1  VDP register 12		; MSX2
RG13SA		equ	0ffech	; 1  VDP register 13		; MSX2
RG14SA		equ	0ffedh	; 1  VDP register 14		; MSX2
RG15SA		equ	0ffeeh	; 1  VDP register 15		; MSX2
RG16SA		equ	0ffefh	; 1  VDP register 16		; MSX2
RG17SA		equ	0fff0h	; 1  VDP register 17		; MSX2
RG18SA		equ	0fff1h	; 1  VDP register 18		; MSX2
RG19SA		equ	0fff2h	; 1  VDP register 19		; MSX2
RG20SA		equ	0fff3h	; 1  VDP register 20		; MSX2
RG21SA		equ	0fff4h	; 1  VDP register 21		; MSX2
RG22SA		equ	0fff5h	; 1  VDP register 22		; MSX2
RG23SA		equ	0fff6h	; 1  VDP register 23		; MSX2
RG25SA		equ	0fffah	; 1  VDP register 25		; MSX2
RG26SA		equ	0fffbh	; 1  VDP register 26		; MSX2
RG27SA		equ	0fffch	; 1  VDP register 27		; MSX2
EXPSLT		equ	0ffffh	; 1  THE SECONDARY SLOT SELECT REGISTER of
				;    whichever primary slot is in page 3.
				;    Written, not read: reading it gives the
				;    value back inverted. THIS NAME IS OURS -
				;    the table gives the address and no label

; --- One entry whose description we could not settle.
;
; PADY at 0FC9Ch and PADX at 0FC9Dh hold the paddle coordinates, and
; the table they come from labels them the other way round from what
; their names say: PADY described as the X coordinate and PADX as
; the Y. One of the two is a slip and a second source has not been
; consulted yet. THE ADDRESSES ARE RIGHT EITHER WAY; if your paddle
; reads sideways, swap them and tell us.
; --- Two names this file could not use.
;
; The work area has a LOW at 0F406h and a HIGH at 0F408h, and HIGH
; and LOW ARE OPERATORS - "ld a,HIGH addr" takes the top byte of
; an address. An equate of either name defines a symbol that can
; never be read, because the expression parser reaches the operator
; first. They are here as CSLOW and CSHIGH, which is what they are
; for, and this paragraph is so that nobody thinks the file is
; missing them.
