; bios.inc - the MAIN ROM entry points.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	bios.inc
;
; An entry is an address and a line saying what it does. What each one
; wants in its registers, what it gives back and what it destroys are
; in the MSX manuals, and are not repeated here: this file exists so
; that you do not have to write "equ 000ch" at the top of a program,
; not to replace the books.
;
; THE ENTRIES ARE IN ADDRESS ORDER, which is how the manual lists
; them and very nearly how they are grouped: the jump table keeps
; most subjects together, so a section head below covers a run of
; consecutive addresses. Where that breaks down - above 0100h - the
; entries say for themselves what they belong to.
;
; CALLING THESE FROM MSX-DOS. Page 0 is RAM there, not the BIOS, so
; an entry is not simply there to be called. MSX-DOS DEFINES FIVE OF
; THEM IN ITS OWN JUMP VECTOR, at the same addresses and doing the
; same job: RDSLT, WRSLT, CALSLT, ENASLT and CALLF. Those five may be
; called directly, and Tatara calls ENASLT that way. EVERY OTHER ENTRY
; IN THIS FILE NEEDS AN INTER-SLOT CALL - see the recipe below. From a
; cartridge, or under BASIC, every direct call works.

; --- The RST entries. All eight are BIOS entries and all eight are
; below, in address order among the rest: RST 00h, 08h, 10h, 18h,
; 20h and 28h belong to the BASIC interpreter, RST 30h is CALLF, the
; inter-slot call, and RST 38h is KEYINT, the timer interrupt.

CHKRAM		equ	0000h	; check the RAM and pick the slot the system
				;   will use for it, then go on into the rest
				;   of the initialisation. THE RESET ENTRY, not
				;   something to call. Changes every register
SYNCHR		equ	0008h	; check that the character HL points at is the
				;   one written IN LINE AFTER THE RST 08h THAT
				;   CALLS IT. Wrong character raises a Syntax
				;   error; right character falls into CHRGTR
				;   below, so it answers the same way

; --- Reaching another slot. The slot byte these take is laid out
; at EXBRSA in workarea.inc.

RDSLT		equ	000ch	; read one byte from any slot
CHRGTR		equ	0010h	; take the next character or token out of the
				;   BASIC text HL points at. HL comes back one
				;   further on, A is that character, CY is set
				;   if it was a digit and Z if it was the end
				;   of a statement - a 00h or a 3Ah
WRSLT		equ	0014h	; write one byte to any slot
OUTDO		equ	0018h	; send A to whichever device output is going
				;   to. PRTFLG not zero sends it to the
				;   printer, PTRFIL not zero to the file PTRFIL
				;   points at. Keeps every register
CALSLT		equ	001ch	; call a routine in any slot
DCOMPR		equ	0020h	; compare HL with DE. Z if they are equal, CY
				;   if HL is the smaller
ENASLT		equ	0024h	; switch a page to a slot
GETYPR		equ	0028h	; report the type of the DAC, the decimal
				;   accumulator whose type byte is VALTYP, by
				;   setting S, Z, P/V and CY. One flag
				;   identifies each type: S for integer, P/V
				;   for single precision, Z for string, CY for
				;   double precision
CALLF		equ	0030h	; call a routine in any slot, with the slot
				;   and the address written inline after the
				;   call instead of passed in registers

; The function keys, on their own between the slot routines and the
; sound.

KEYINT		equ	0038h	; THE TIMER INTERRUPT ITSELF, reached by RST
				;   38h. Not something to call
INITIO		equ	003bh	; initialise the devices. Changes every
				;   register
INIFNK		equ	003eh	; put the ten function key strings back to the
				;   ones BASIC starts with. THE DISPLAYED STRIP
				;   DOES NOT CHANGE UNTIL THE SCREEN IS CLEARED

; --- The VDP. THE FIVE ROUTINES MARKED BELOW ARE FOR THE TMS9918,
; the MSX1 VDP, AND TAKE ONLY THE LOW 14 BITS OF A VRAM ADDRESS.
; On an MSX2 or later, where VRAM runs past 16K, use the N-named
; twin each one points at - they are at 016Eh to 0177h, further
; down this file.

DISSCR		equ	0041h	; stop the screen being displayed
ENASCR		equ	0044h	; display the screen again
WRTVDP		equ	0047h	; write B into the VDP register numbered in C.
				;   Registers 0 to 23 and 32 to 46
RDVRM		equ	004ah	; read the VRAM byte at HL into A. 14 BIT
				;   ADDRESS: NRDVRM at 0174h takes all of it
WRTVRM		equ	004dh	; write A into the VRAM byte at HL. 14 BIT
				;   ADDRESS: NWRVRM at 0177h takes all of it
SETRD		equ	0050h	; point the VDP at the VRAM address in HL and
				;   leave it ready to READ. The address then
				;   steps on by itself, so a run of bytes comes
				;   off the port far faster than calling RDVRM
				;   in a loop. 14 BIT ADDRESS: NSETRD at 016Eh
				;   takes all of it
SETWRT		equ	0053h	; the same, ready to WRITE. 14 BIT ADDRESS:
				;   NSTWRT at 0171h takes all of it
FILVRM		equ	0056h	; fill a stretch of VRAM with one value. 14 BIT
				;   ADDRESS: BIGFIL at 016Bh takes all of it
LDIRMV		equ	0059h	; block move from VRAM into memory. ALL SIXTEEN
				;   BITS of the VRAM address count here, unlike
				;   the five above
LDIRVM		equ	005ch	; block move from memory into VRAM
CHGMOD		equ	005fh	; change the screen mode, 0 to 8, the number in
				;   A. THE PALETTE IS LEFT ALONE: the SUB ROM
				;   entry at 01B5h does the mode and the
				;   palette in one call, and subrom.inc has it
CHGCLR		equ	0062h	; change the screen colours to the three
				;   already put in FORCLR, BAKCLR and BDRCLR
NMI		equ	0066h	; the non maskable interrupt handler. THE Z80
				;   ARRIVES HERE BY ITSELF - it is not
				;   something a program calls
CLRSPR		equ	0069h	; clear every sprite: pattern null, each sprite
				;   number set to its own plane number, colour
				;   the foreground colour, vertical position
				;   209 in SCREEN 0 to 3 and 217 in SCREEN 4 to
				;   12
; --- Setting up a screen mode. INITXT, INIT32, INIGRP and INIMLT
; each set their mode up BUT LEAVE THE PALETTE ALONE: call
; SUBROM_INIPLT, 0141h in the SUB ROM, afterwards if it needs
; setting. CHGMOD above says the same and names a different
; remedy: SUBROM_CHGMDP at 01B5h does the mode and the palette in
; one call. SETTXT, SETT32, SETGRP and SETMLT are those same four
; modes again, but they SET THE VDP AND NOTHING ELSE, and each
; takes the same work area addresses as its INI twin.

INITXT		equ	006ch	; set the screen to TEXT1 - SCREEN 0, 40 by 24.
				;   Takes its addresses from TXTNAM, TXTCGP and
				;   LINL40
INIT32		equ	006fh	; set the screen to TEXT2 - SCREEN 1, 32 by 24.
				;   Takes its addresses from T32NAM, T32COL,
				;   T32CGP, T32ATR, T32PAT and LINL32
INIGRP		equ	0072h	; set the screen to GRAPHIC1 - SCREEN 2. Takes
				;   its addresses from GRPNAM, GRPCOL, GRPCGP,
				;   GRPATR and GRPPAT
INIMLT		equ	0075h	; set the screen to MULTI COLOR - SCREEN 3.
				;   Takes its addresses from MLTNAM, MLTCOL,
				;   MLTCGP, MLTATR and MLTPAT
SETTXT		equ	0078h	; the VDP into TEXT1 - SCREEN 0, 40 by 24
SETT32		equ	007bh	; the VDP into TEXT2 - SCREEN 1, 32 by 24
SETGRP		equ	007eh	; the VDP into GRAPHIC1 - SCREEN 2
SETMLT		equ	0081h	; the VDP into MULTI COLOR - SCREEN 3
CALPAT		equ	0084h	; the VRAM address of sprite A pattern in the
				;   sprite generator table, returned in HL
CALATR		equ	0087h	; the VRAM address of sprite A entry in the
				;   sprite attribute table, returned in HL
GSPSIZ		equ	008ah	; the size of a sprite now, in bytes, in A.
				;   CARRY COMES BACK SET ONLY WHEN SPRITES ARE
				;   16 BY 16
GRPPRT		equ	008dh	; put the character in A on a graphics screen.
				;   In SCREEN 5 to 12 the logical operation
				;   code comes from LOGOPR

; --- The PSG, and music. There is a second sound source besides the
; PSG: bit 7 of PPI port C, toggled by the program itself, mixed
; with the PSG output before the speaker. See IO_PPIC in ports.inc.

GICINI		equ	0090h	; initialise the PSG, and the work area the
				;   PLAY statement uses
WRTPSG		equ	0093h	; write E to the PSG register numbered in A
RDPSG		equ	0096h	; read the PSG register numbered in A,
				;   into A
STRTMS		equ	0099h	; start whatever is in the music queue playing,
				;   if nothing is playing already. The MML goes
				;   at the address in QUEUES, already turned
				;   into the interpreter intermediate form

; --- The keyboard. The timer interrupt scans the key matrix every
; 1/60 second and puts the code of any key pressed into KEYBUF, a
; 40-byte ring in the work area with PUTPNT and GETPNT as its two
; pointers. DISABLE THE TIMER INTERRUPT AND ANYTHING THAT READS THAT
; RING STOPS WORKING, because nothing is filling it any more. SNSMAT
; is the exception: it reads the matrix itself.

CHSNS		equ	009ch	; test whether anything is waiting in
				;   KEYBUF. Z if the buffer is empty
CHGET		equ	009fh	; take one character out of KEYBUF into
				;   A. If the buffer is empty it shows the
				;   cursor and waits for a key. CAPS, KANA
				;   and romaji conversion are all live
				;   while it waits. The work area entries
				;   it reads are CLIKSW, SCNCNT, REPCNT,
				;   MODE, CSTYLE, CAPST and KANAST
CHPUT		equ	00a2h	; display the character in A on the screen

; --- The printer. Eight data bits with a BUSY line and a STROBE
; line. Two work area bytes decide what leaves the machine: NTMSXP
; for hiragana and RAWPRT for the tab code. The ports themselves are
; in ports.inc, where THE BOOK DISAGREES WITH ITSELF about which of
; the two carries the status bit.

LPTOUT		equ	00a5h	; send A to the printer. CY on error. What
				;   the printer is sent depends on NTMSXP
				;   and RAWPRT. One entry heading spells
				;   this LPOUT, which is a typo: LPTOUT is
				;   the spelling that matches LPTSTT below
LPTSTT		equ	00a8h	; ask whether the printer can be used.
				;   A comes back 255 with Z clear when it
				;   can, 0 with Z set when it cannot

; Back to the keyboard and the line it builds.

CNVCHR		equ	00abh	; fold a two byte graphic character, 01h and
				;   then one more byte, into the single byte
				;   code that stands for it. THREE OUTCOMES,
				;   not two: carry clear and A was not a
				;   graphic header byte at all; carry and zero
				;   both set and it was a graphic character, A
				;   now holding the folded code; carry set with
				;   zero clear and it followed a header but is
				;   not a graphic character, A unchanged
PINLIN		equ	00aeh	; read a whole line. The line is left at
				;   BUF, ending with a zero byte, and HL
				;   comes back pointing one byte before it
				;   at BUFMIN. CY if STOP ended the line
				;   rather than RETURN
INLIN		equ	00b1h	; read a whole line like PINLIN, but only from
				;   the cursor position onwards - anything
				;   already on the line to the left of the
				;   cursor is not taken. What the ROM does
				;   differently is set AUTFLG while it runs
QINLIN		equ	00b4h	; print a question mark and one space, then do
				;   INLIN
BREAKX		equ	00b7h	; test whether CTRL and STOP are down. CALL IT
				;   WITH INTERRUPTS DISABLED, which the manual
				;   asks for and which is what makes it useful:
				;   it answers when nothing is filling KEYBUF
				;   and no other key can be read
BEEP		equ	00c0h	; sound the buzzer
CLS		equ	00c3h	; clear the screen
POSIT		equ	00c6h	; move the cursor to column H, row L
FNKSB		equ	00c9h	; look at FNKFLG and either display the
				;   function key strip or erase it, whichever
				;   it says
ERAFNK		equ	00cch	; erase the function key strip
DSPFNK		equ	00cfh	; display the function key strip

TOTEXT		equ	00d2h	; force the screen into text mode

; --- The joystick, the paddles and the mouse. Both entries below
; read the keyboard instead when they are asked for device 0, which
; makes a loop that works with either a stick or the keys a matter
; of one number.

GTSTCK		equ	00d5h	; read a direction into A. 0 in A reads the
				;   cursor keys, 1 or 2 the joystick in that
				;   port. 0 back means centred, then 1 is up
				;   and the numbers run clockwise from there to
				;   8, up and to the left. Same as BASIC STICK
GTTRIG		equ	00d8h	; read a trigger into A, 0FFh pressed and
				;   0 released. 0 in A reads the space key,
				;   1 or 2 a joystick trigger. On a mouse 1
				;   and 2 are the left buttons of ports 1
				;   and 2, and 3 and 4 the right buttons
GTPAD		equ	00dbh	; read a touch panel, a light pen, a mouse
				;   or a trackball. A in is a device id, 0
				;   to 19; A back is the answer. Same as
				;   BASIC PAD. The ids run in fours: 0 the
				;   first touch panel, 4 the second, 8 the
				;   light pen, 12 the first mouse or
				;   trackball, 16 the second. Within each
				;   four, +0 is a status or a request, +1
				;   the X, +2 the Y, +3 the button
GTPDL		equ	00deh	; read a paddle. A in is the paddle
				;   number, 1 to 12; A back is the angle it
				;   is turned to, 0 to 255

; Four things about GTPAD that a caller has to know:
;
; * THE LIGHT PEN IS READ BY THE id 8 CALL. Ids 9, 10 and 11 hand
;   back what that call fetched, and mean nothing unless it answered
;   0FFh.
; * A MOUSE OR TRACKBALL MUST BE ASKED FIRST. Call with id 12 or 16
;   to request input, then read the coordinates AS SOON AS POSSIBLE.
;   Time spent between the two calls makes the numbers unreliable.
; * The button on a mouse or trackball is read with GTTRIG, not here.
;   Ids 15 and 19 always answer 00h and mean nothing.
; * A mouse and a trackball are told apart by the machine itself.

; --- The cassette interface. NONE OF THIS EXISTS ON THE MSX turbo R:
; the machine has no cassette port, so these seven entries have
; nothing to drive.
;
; THE READ AND WRITE LOOPS MUST DO NOTHING ELSE. Printing a byte to
; the screen while the next one comes off the tape is enough to
; produce a read error.

TAPION		equ	00e1h	; start the motor and read a header, long
				;   or short. Works out the baud rate the
				;   file was written at and sets the work
				;   area to match. Interrupts are disabled.
				;   CY on error
TAPIN		equ	00e4h	; read one byte from the tape into A.
				;   CY on error
TAPIOF		equ	00e7h	; stop reading. Interrupts are enabled
				;   again
TAPOON		equ	00eah	; start the motor and write a header: 0
				;   in A writes a short header, anything
				;   else a long one. Interrupts are
				;   disabled. CY on error
TAPOUT		equ	00edh	; write A to the tape. CY on error
TAPOOF		equ	00f0h	; stop writing. Interrupts are enabled
				;   again
STMOTR		equ	00f3h	; set the motor from A: 0 stops it, 1
				;   starts it, 255 puts it into the
				;   opposite state to the one it is in now

; --- The entries above 0100h. This is the one stretch where the
; jump table stops being grouped by subject: the subjects are mixed
; together and the entries sit in address order and nothing else.
; Each one says for itself what it belongs to. NO LIST OF THEM HERE
; - a list in this head has gone stale twice.

CHGCAP		equ	0132h	; turn the CAPS lamp on or off from A. 0 TURNS
				;   IT ON and anything else turns it off, which
				;   is the opposite way round from CHGSND just
				;   below
CHGSND		equ	0135h	; SOUND. Set the one bit sound port - bit
				;   7 of PPI port C, the second sound
				;   source named in the PSG section above -
				;   from A: 0 turns the bit off, anything
				;   else turns it on
RSLREG		equ	0138h	; read the primary slot select register into A
WSLREG		equ	013bh	; write A to the primary slot select register
RDVDP		equ	013eh	; read the VDP status register into A. A
				;   TMS9918 ROUTINE, like the five VRAM entries
				;   near the top of this file
SNSMAT		equ	0141h	; read one row of the key matrix, numbered
				;   0 to 10 in A, back into A. A BIT READS
				;   0 WHEN ITS KEY IS DOWN. Reads the
				;   matrix itself, so it still works with
				;   the timer interrupt disabled
ISFLIO		equ	014ah	; ask whether the device is working. THE ANSWER
				;   IS THE WAY ROUND YOU WOULD NOT GUESS: 0 in
				;   A means it IS working, anything else means
				;   it is not
OUTDLP		equ	014dh	; send A to the printer the way LPRINT
				;   does. Unlike LPTOUT it always
				;   turns a tab into the right number of
				;   spaces, always folds hiragana into
				;   katakana on a printer that is not an
				;   MSX one, and reports a failure as the
				;   BASIC error Device I/O error
KILBUF		equ	0156h	; throw away whatever is in KEYBUF
CALBAS		equ	0159h	; inter-slot call an address in IX inside the
				;   BASIC interpreter

; --- THE ENTRIES FROM 015Ch TO 0177h WERE ADDED FOR MSX2. The
; appendix heads the run so. Two more follow them, for MSX2+.

; --- Reaching the SUB ROM. The BIOS finds the slot it is in by
; itself; the two differ only in whether the value in IX is pushed,
; and EXTROM is the usual one.

SUBROM		equ	015ch	; call an address in the SUB ROM, pushing IX
EXTROM		equ	015fh	; call an address in the SUB ROM

; --- CALLING THE SUB ROM FROM MSX-DOS, which is the awkward one.
;
; Both entries above want the address in IX, and from MSX-DOS there is
; no way to have IX set at the moment the MAIN ROM is entered: it has
; to be loaded AFTER the BIOS is in, and jumped from. The documented
; way round it is to put a short routine of your own somewhere the
; stack can reach, point THE NMI HOOK at it, and then inter-slot call
; the BIOS NMI entry - the hook exists and the BIOS never uses it.
; Your routine loads IX and jumps to EXTROM.
;
; Four things the manual is explicit about:
;
;   the entry condition is the address in IX and nothing else
;   THE STACK MUST NOT BE IN PAGE 0
;   interrupts need not be disabled
;   the NMI hook need not be put back afterwards
;
; An ordinary BIOS entry is easier, because the slot is in EXPTBL and
; IY picks it up a byte early:
;
;	ld	iy,(EXPTBL-1)	; the MAIN ROM slot, into IYh
;	ld	ix,<the entry>
;	call	CALSLT

EOL		equ	0168h	; delete from the position in H and L - H the
				;   column, L the row - to the end of that line
BIGFIL		equ	016bh	; fill VRAM like FILVRM 0056h, WITHOUT ITS
				;   SCREEN MODE CHECK. FILVRM looks at the mode
				;   and, in SCREEN 0 to 3, treats the VDP as
				;   having 16K of VRAM and no more. BIGFIL does
				;   not look, and works to the numbers it is
				;   given
NSETRD		equ	016eh	; point the VDP at the VRAM address in HL ready
				;   to READ, all address bits. SETRD 0050h is
				;   the 14 bit twin
NSTWRT		equ	0171h	; point the VDP at the VRAM address in HL ready
				;   to WRITE, all address bits. SETWRT 0053h is
				;   the 14 bit twin
NRDVRM		equ	0174h	; read the VRAM byte at HL into A, all address
				;   bits. RDVRM 004Ah is the 14 bit twin
NWRVRM		equ	0177h	; write A into the VRAM byte at HL, all address
				;   bits. WRTVRM 004Dh is the 14 bit twin

; --- THE LAST TWO ENTRIES WERE ADDED FOR MSX2+, and they end the
; MAIN ROM list.

RDRES		equ	017ah	; read the RESET port into A. THE TOP BIT CLEAR
				;   MEANS THE MACHINE CAME UP FROM A HARDWARE
				;   RESET
WRRES		equ	017dh	; write A to the RESET port. To make a hardware
				;   reset happen: clear the top bit of A, call
				;   this, then jump to 0000h in the BIOS

