; extbio.inc - the extended BIOS, and the optional devices.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	extbio.inc
;
; THE NAMES ARE LONG ON PURPOSE. An entry keeps the name its manual
; gives it - INIT, OPEN, EOF - behind a prefix saying whose jump
; table it belongs to, because INIT or EOF on its own would collide
; with half the programs that include this file. Every device added
; later gets its own EXTBIO_ prefix in the same way.
;
; MOST OF THIS FILE IS THE EXTENDED BIOS, described next. The FM
; BIOS at the end is not one: it is a fixed jump table at a fixed
; address inside the MSX-MUSIC ROM, found by searching the slots
; rather than by asking. It is here because the manual keeps the
; optional devices together, and its own section says how it
; differs.
;
; The extended BIOS is how a cartridge offers routines to a program
; that knows nothing about where it is plugged in. The program asks,
; every cartridge that recognises the device number answers, and an
; answer is a slot and the address of a jump table inside it.
;
; To ask: set aside 64 bytes for the answers, put the device number
; in D, the function number in E, the slot of those 64 bytes in B,
; their address in HL, and call EXTBIO (0FFCAh, in hooks.inc). B and
; HL come back pointing past the last answer written. IF NOBODY
; ANSWERED, B AND HL COME BACK UNCHANGED, and that is the test for
; "the device is not here".
;
; An answer is four bytes:
;
;	+0	the slot of the jump table
;	+1	its address, low byte
;	+2	its address, high byte
;	+3	reserved, always 0
;
; A slot byte is laid out as written under EXBRSA in workarea.inc.
; The slot of your own RAM, which is what B wants, is in RAMAD0 to
; RAMAD3, one per page - BUT ONLY ON A MACHINE WITH A DISK. Without
; one those four hold nothing worth reading and the slot has to be
; found by searching for RAM.
;
; Then reach an entry with an inter-slot call: the slot in the high
; half of IY, the address in IX, and CALSLT from bios.inc. A program
; that needs the speed may enable the slot itself and call directly.

; THREE KINDS OF CALL, chosen by the device number in D: 0 is a
; BROADCAST to every device at once, 1 to 254 name one device, and
; 255 is SYSTEM EXCLUSIVE, for a maker putting its own extended BIOS
; in. A device must answer the broadcast as well as its own number.
;
; THE STACK POINTER MUST BE ABOVE 0C000h when the extended BIOS is
; called. Two reasons, both the manual's: the call is an inter-slot
; call and the devices NEST, so every device reached wants at least
; 16 bytes of stack; and an extended BIOS may itself be sitting at
; 8000h to 0BFFFh. This is the general rule behind the page 3 stack
; that MSX-JE asks for further down.
;
; ASCII registers the device numbers, so two kinds of device never
; share one. These are the numbers registered:

EXTBIO_ALL_DEVICE	equ	0	; THE BROADCAST. Every device answers,
					;   and the four functions below are
					;   its own
EXTBIO_DOS2_DEVICE	equ	4	; MSX-DOS 2, the memory mapper support
EXTBIO_MIDI_DEVICE	equ	11	; MSX-MIDI
EXTBIO_KANJI_DEVICE	equ	17	; the kanji driver
EXTBIO_EXCL_DEVICE	equ	255	; SYSTEM EXCLUSIVE, a maker's own.
					;   Nothing here can say what it does

; 1 to 3, 5 to 7, 9, 12 to 15 and 18 to 254 are not registered to
; anything. The three devices this file describes in full - 8, 10
; and 16 - have their own sections below, with their numbers beside
; the rest of what they need.

; The four functions of the broadcast, in E:

EXTBIO_ALL_FN_GETDEV	equ	0	; ask every device for its device
					;   number
EXTBIO_ALL_FN_GETTRAP	equ	1	; ask how many traps are in use
EXTBIO_ALL_FN_DISINT	equ	2	; declare interrupts disabled
EXTBIO_ALL_FN_ENAINT	equ	3	; declare interrupts enabled

; --- MSX RS-232C. The numbers below are OFFSETS IN BYTES from the
; start of the jump table this device answers with, not addresses.
; Offset 2 is a reserved byte. From offset 3 on, each entry is a JP
; and so three bytes; a MODEM cartridge has six more entries from
; offset 42, which are RET on an RS-232C.

EXTBIO_RS232_DEVICE	equ	8	; the device number of the MSX RS-232C.
					;   IT GOES IN D, not in the table.
					;   THE MSX MODEM ANSWERS ON 8 TOO, on
					;   purpose, so that a program written
					;   for the serial port works with a
					;   modem. One number, two devices:
					;   read DVTYPE to tell which answered
EXTBIO_RS232_DVINFB	equ	0	; a byte, not an entry: WHAT THIS
					;   CARTRIDGE CAN DO. A 1 says the
					;   feature is there, bit by bit from
					;   1: send interrupt, BREAK detect,
					;   timer interrupt, carrier detect,
					;   ring indicator. Bits 0, 6 and 7 are
					;   reserved
EXTBIO_RS232_DVTYPE	equ	1	; a byte, not an entry: 0 is a single
					;   channel cartridge, AND THEN THERE
					;   IS NO SETCHN ENTRY. Anything else
					;   is multi channel
EXTBIO_RS232_INIT	equ	3	; initialise the port
EXTBIO_RS232_OPEN	equ	6	; open the port
EXTBIO_RS232_STAT	equ	9	; read the status
EXTBIO_RS232_GETCHR	equ	12	; receive a character
EXTBIO_RS232_SNDCHR	equ	15	; send a character
EXTBIO_RS232_CLOSE	equ	18	; close the port
EXTBIO_RS232_EOF	equ	21	; an EOF code has been received
EXTBIO_RS232_LOC	equ	24	; how many characters are waiting in
					;   the receive buffer
EXTBIO_RS232_LOF	equ	27	; how much room is left in the receive
					;   buffer
EXTBIO_RS232_BACKUP	equ	30	; put a character back
EXTBIO_RS232_SNDBRK	equ	33	; send a break
EXTBIO_RS232_DTR	equ	36	; turn the DTR line on or off
EXTBIO_RS232_SETCHN	equ	39	; choose the channel. MULTI CHANNEL
					;   CARTRIDGES ONLY: see the DVTYPE
					;   byte above



; --- MSX MODEM. The numbers below are OFFSETS IN BYTES from the
; start of the jump table, the same as above, and each entry from
; offset 3 on is a JP and so three bytes.
;
; THE TWO TABLES ARE ONE TABLE. Offsets 3 to 33 are the same eleven
; entries as the RS-232C, doing the same jobs, and the proof is at
; the other end: a modem reserves offsets 36 and 39, which is exactly
; where an RS-232C keeps DTR and SETCHN. So the two devices divide
; one layout between them rather than each having its own. Offsets 72
; and 75 are reserved for whatever comes after.

EXTBIO_MODEM_DVINFB	equ	0	; a byte, not an entry: what this modem
					;   has. The same eight bits as the
					;   RS-232C DVINFB above, and a 1 still
					;   means the feature is there
EXTBIO_MODEM_DVTYPE	equ	1	; a byte, not an entry: bit 0 set means
					;   a MULTI TYPE cartridge, one of
					;   several modems that can sit in the
					;   machine at once and be driven
					;   separately. The other seven bits
					;   are reserved. NOT THE SAME MEANING
					;   AS THE RS-232C BYTE OF THIS NAME,
					;   which counts channels
EXTBIO_MODEM_INIT	equ	3	; initialise the modem port
EXTBIO_MODEM_OPEN	equ	6	; open the modem port
EXTBIO_MODEM_STAT	equ	9	; read the status
EXTBIO_MODEM_GETCHR	equ	12	; receive a character
EXTBIO_MODEM_SNDCHR	equ	15	; send a character
EXTBIO_MODEM_CLOSE	equ	18	; close the modem port
EXTBIO_MODEM_EOF	equ	21	; an EOF code has been received
EXTBIO_MODEM_LOC	equ	24	; how many characters are waiting in
					;   the receive buffer
EXTBIO_MODEM_LOF	equ	27	; how much room is left in the receive
					;   buffer
EXTBIO_MODEM_BACKUP	equ	30	; put a character back
EXTBIO_MODEM_SNDBRK	equ	33	; send a break
EXTBIO_MODEM_NCUSTA	equ	42	; the state of the network control unit
EXTBIO_MODEM_SPKCNT	equ	45	; the speaker: on or off
EXTBIO_MODEM_LINSEL	equ	48	; give the line to the telephone or to
					;   the modem
EXTBIO_MODEM_DIALST	equ	51	; dial a whole string
EXTBIO_MODEM_DIALCH	equ	54	; dial one character
EXTBIO_MODEM_DTMFST	equ	57	; the state of the DTMF receiver
EXTBIO_MODEM_RDDTMF	equ	60	; read a DTMF signal
EXTBIO_MODEM_HOKCNT	equ	63	; the hook: pick up or hang up
EXTBIO_MODEM_CONFIG	equ	66	; the device configuration
EXTBIO_MODEM_SPCIAL	equ	69	; special control. SPCIAL IS THE
					;   OFFICIAL SPELLING, with no E: it is
					;   the label the manual prints, not a
					;   slip here


; --- MSX-AUDIO. Two function numbers, then the jump table. Its own
; MBIOS, the Music BIOS, is one entry inside that table rather than
; the table itself: set the registers an MBIOS function asks for,
; PUT IX AND IY INTO THE FIRST FOUR BYTES OF BUF - low byte first,
; IX then IY - and call offset 3. BUF is the BASIC line buffer in
; workarea.inc, borrowed because an inter-slot call has no room for
; two more index registers.

EXTBIO_FN_TABLE		equ	0	; THE FUNCTION NUMBER THAT ASKS A NAMED
					;   DEVICE WHERE ITS JUMP TABLE IS, in
					;   E. The RS-232C, the modem and
					;   MSX-AUDIO all answer it, so it is
					;   not named per device. DEVICE 0 IS
					;   NOT A NAMED DEVICE and function 0
					;   means something else to it
EXTBIO_AUDIO_DEVICE	equ	10	; the device number of MSX-AUDIO. IT
					;   GOES IN D. Not 8: the RS-232C and
					;   the modem share that one, MSX-AUDIO
					;   has its own
EXTBIO_AUDIO_FN_COUNT	equ	1	; a second function, in E, and
					;   MSX-AUDIO only: how many are
					;   fitted. Put 0 in A as well; A comes
					;   back 0, 1 or 2. TWO MSX-AUDIO CHIPS
					;   IN ONE MACHINE IS ALLOWED, which is
					;   what this is for. It keeps BC, DE
					;   and HL and may change anything else

; The jump table. OFFSETS IN BYTES from its start, as with the two
; devices above. Offset 0 is three bytes of version number rather
; than a JP - all three are 0 at the time of writing - so the first
; real entry is at 3 and they step by three from there. MK below is
; the Music Keyboard.

EXTBIO_AUDIO_VERSION	equ	0	; three bytes of software version, not
					;   an entry. All three are 0 so far
EXTBIO_AUDIO_MBIOS	equ	3	; call the MBIOS, the Music BIOS
EXTBIO_AUDIO_AUDIO	equ	6	; initialise MSX-AUDIO
EXTBIO_AUDIO_SYNTHE	equ	9	; call the application that came with
					;   the cartridge
EXTBIO_AUDIO_PLAYF	equ	12	; is the PLAY statement running?
EXTBIO_AUDIO_BGM	equ	15	; turn BGM mode on or off
EXTBIO_AUDIO_MKTEMPO	equ	18	; set the tempo for playing back or
					;   recording the Music Keyboard
EXTBIO_AUDIO_PLAYMK	equ	21	; play back a Music Keyboard
					;   performance
EXTBIO_AUDIO_RECMK	equ	24	; record a Music Keyboard performance
EXTBIO_AUDIO_STOPM	equ	27	; stop the lot: Music Keyboard play and
					;   record, ADPCM and PCM play and
					;   record, and the PLAY statement
EXTBIO_AUDIO_CONTMK	equ	30	; carry on playing back or recording
					;   the Music Keyboard
EXTBIO_AUDIO_RECMOD	equ	33	; set the Music Keyboard record mode
EXTBIO_AUDIO_STPPLY	equ	36	; stop the PLAY statement alone
EXTBIO_AUDIO_SETPCM	equ	39	; set aside an area for ADPCM or PCM
EXTBIO_AUDIO_RECPCM	equ	42	; record ADPCM or PCM
EXTBIO_AUDIO_PLAYPCM	equ	45	; play ADPCM or PCM
EXTBIO_AUDIO_PCMFREQ	equ	48	; change the playback frequency
EXTBIO_AUDIO_MKPCM	equ	51	; give the Music Keyboard some ADPCM
					;   data to use, or take it away
EXTBIO_AUDIO_PCMVOL	equ	54	; set the playback volume
EXTBIO_AUDIO_SAVEPCM	equ	57	; save ADPCM or PCM data
EXTBIO_AUDIO_LOADPCM	equ	60	; load ADPCM or PCM data
EXTBIO_AUDIO_COPYPCM	equ	63	; move ADPCM or PCM data about
EXTBIO_AUDIO_CONVP	equ	66	; ADPCM data to PCM data
EXTBIO_AUDIO_CONVA	equ	69	; PCM data to ADPCM data
EXTBIO_AUDIO_VOICE	equ	72	; set an FM voice
EXTBIO_AUDIO_VOICECOPY	equ	75	; move FM voice data


; THE MBIOS ITSELF IS NOT IN THIS FILE. Its routines, its work area
; and its several dozen function codes run to a hundred pages of the
; manual and will get an include of their own; the entry above is
; what you need to reach it in the meantime.


; --- MSX-JE, the kana to kanji conversion engine. It may be a
; cartridge of its own, built into the machine, or a word processor
; lending out the one it already has; a program that follows this
; interface gets Japanese input without doing any conversion itself.
; Two levels of service, told apart by the function number: a
; virtual terminal that converts as you type, and a way to read the
; dictionary directly.

EXTBIO_MSXJE_DEVICE	equ	16	; the device number of MSX-JE. IT GOES
					;   IN D, and with function 0 in E that
					;   makes DE = 1000h, which is the
					;   value MSX-JE itself watches for

; CHECK HOKVLD FIRST. Bit 0 of it, in workarea.inc, says whether
; there is an extended BIOS at all; if it is clear there is none and
; EXTBIO MUST NOT BE CALLED. Then the usual: 64 bytes for the answers,
; the slot of those bytes in B, their address in HL, and call EXTBIO.
; THE STACK MUST BE IN PAGE 3 for that call, which is this chapter
; restating the general rule at the top of this file: the stack
; pointer must be above 0C000h for any extended BIOS call.
;
; An answer here is four bytes, not the three and a pad of the other
; devices:
;
;	+0	the capability vector, below
;	+1	the slot of the entry
;	+2	its address, low byte then high
;
; HL comes back unchanged when no MSX-JE answered.
;
; THE CAPABILITY VECTOR IS INVERTED: a 0 means the feature IS there.
; Bit 0 is always 0 and is what says this is an MSX-JE at all; bit 1
; clear means the virtual terminal is there, bit 2 clear the
; dictionary interface, bit 3 clear the ability to add to and delete
; from the dictionary. Bits 7 to 4 are always 1, reserved for
; supersets. So a program wanting only the virtual terminal ANDs the
; byte with 03h and expects 0.
;
; CALLING MSX-JE, once its slot and address are known: A the function
; number, BC and DE its parameters, and HL THE ADDRESS OF A WORK AREA
; THE CALLER OWNS - MSX-JE cannot keep one at a fixed address, so it
; is handed one every single call.
;
; THE WORK AREA AND ANYTHING A PARAMETER POINTS AT MUST BE IN PAGE 2
; OR PAGE 3, and those pages enabled before the call. The reason is
; speed: allowing them behind the page MSX-JE itself occupies would
; force a slot switch on every access.
;
; ONLY THE RETURN VALUES AND SP SURVIVE. An undefined function number
; does nothing at all - and still guarantees nothing but SP.
;
; The manual's suggested way in is a CALLF by another name, worth
; recognising:
;
;	ld	hl,<the work area>
;	rst	30h		; CALLF, in bios.inc
;	defb	<the slot>
;	defw	<the entry>
;	ret

; --- MSX-MUSIC, the FM BIOS. THESE ARE ADDRESSES, NOT OFFSETS - the
; only entries in this file that are. They are fixed addresses in the
; MSX-MUSIC ROM. Search every slot for OPLL_ID_CART in ports.inc -
; "OPLL" at 0401Ch - and the entries start at 4110h in the slot that
; answers. THAT TEST IS THE RIGHT ONE HERE even though ports.inc
; warns against using it alone: there it has to tell a built-in chip
; from a cartridge and 0401Ch matches both, while here matching both
; is the point, because both have an FM BIOS. Then reach an entry the
; usual way: the slot in the high half of IY, the address in IX,
; CALSLT from bios.inc.
;
; CALL INIOPL FIRST. Nothing else below works until it has run once,
; and it fails quietly rather than loudly.

FMBIOS_WRTOPL		equ	04110h	; write E into the OPLL register
					;   numbered in A. DOES NO DI AND EI OF
					;   ITS OWN, and nor does TSTBGM below:
					;   bracket the call yourself if an
					;   interrupt would disturb it
FMBIOS_INIOPL		equ	04113h	; set up the FM BIOS. HL is where its
					;   work area goes and the address is
					;   kept in SLTWRK. Call this before
					;   any other entry below. Returns with
					;   interrupts enabled. IT ALSO LEAVES
					;   THE SLOTS DISTURBED - see the notes
					;   under the table
FMBIOS_MSTART		equ	04116h	; start playing the music at HL. A is 0
					;   to repeat for ever or 1 to 254 for
					;   a count, and 255 MUST NOT BE USED.
					;   The first byte of the data already
					;   says the mode - 0Eh six FM voices
					;   and rhythm, 12h nine FM voices - so
					;   there is nothing to write. NOTHING
					;   PLAYS UNLESS FMBIOS_OPLDRV IS
					;   ALREADY HOOKED ON H.TIMI: the call
					;   succeeds and is silent
FMBIOS_MSTOP		equ	04119h	; stop playing, silence every OPLL
					;   voice and clear the MSX-MUSIC work
					;   area
FMBIOS_RDDATA		equ	0411ch	; read voice A, 0 to 63, out of the ROM
					;   into the work area at HL
FMBIOS_OPLDRV		equ	0411fh	; THE DRIVER ITSELF, and the one entry
					;   here not meant to be called by
					;   hand: point H.TIMI at it and the
					;   timer interrupt plays the music.
					;   INIOPL must have run first or
					;   nothing after it is guaranteed
FMBIOS_TSTBGM		equ	04122h	; is the music MSTART began still
					;   playing? A comes back 0 once it has
					;   finished and not zero while it
					;   plays. Does no DI and EI of its own

; Interrupts, across the seven: INIOPL, MSTART and MSTOP say they
; return with them enabled. WRTOPL and TSTBGM say they do no DI or
; EI at all. RDDATA and OPLDRV say neither way, so assume nothing.

; WHERE THE WORK AREA MAY LIVE, which is INIOPL's HL:
;
; * NEVER IN PAGE 1. Not under any circumstances.
; * Page 2 or page 3 for preference, and it may straddle the two.
; * Page 0 only if the program is managing slots properly, and even
;   then it may not run over the join into page 1.
; * THE ADDRESS MUST BE EVEN. That is not the chip being fussy: the
;   FM BIOS keeps this address in SLTWRK, which it shares with
;   MSX-MUSIC's extended BASIC, and the sharing is what costs the
;   odd addresses.

; INIOPL LEAVES THE SLOTS DISTURBED. To find out whether another slot
; also holds an FM BIOS it walks them with ENASLT, reading the ID at
; 0401Ch, and for an expanded slot it walks the four expansion slots
; as well - WITHOUT PUTTING THE EXPANSION SLOT SELECT REGISTER BACK.
; It leaves expansion slot 3 selected. So on return, page 1 of an
; expanded slot shows expansion slot 3 rather than whatever was
; there before, and the FM BIOS hands that state to the caller.
;
; The case the manual gives: slot 0 expanded with BASIC in 0-0, an FM
; BIOS somewhere in slots 1 to 3, and a machine code routine called
; from BASIC by USR. It calls INIOPL, comes back, and cannot return
; to BASIC - page 1 is now slot 0-3.
;
; The cure is one line each side: READ PAGE 1'S SLOT BEFORE CALLING
; INIOPL AND PUT IT BACK AFTERWARDS.



