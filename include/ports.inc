; ports.inc - the MSX I/O ports.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	ports.inc
;
; THE NAMES IN THIS FILE ARE OURS. The work area, the BIOS and the
; hooks all have standard labels that every MSX listing has used since
; 1983; the I/O map has none - it is published as addresses and
; descriptions and nothing else. So these names were chosen here, and
; another program may well call port 0A8h something different.
;
; They are long on purpose. Everything that really is a port is
; IO_something; the two main ROM addresses and the memory mapped
; RS-232C channels are named for what they are instead, so that a
; line using one does not read like an OUT.
;
; A PORT IS ONE BYTE AND IS WRITTEN AS THREE HEX DIGITS, with the
; leading zero even where the first digit would not need one. The two
; entries in this file that are four digits long are main ROM
; addresses, not ports, and are meant to look different.
;
; Ranges the map reserves, or gives to one vendor, are comments here
; and not equates: a range cannot be an equate, and a name for it
; would be a name for nothing.
;
;   000h-03Fh  yours, by the standard
;   040h-04Fh  expansion I/O
;   050h-06Fh  system reserved
;   070h-073h  a MIDI cartridge
;   074h-07Bh  system reserved
;   07Eh-07Fh  system reserved
;   088h-08Bh  the VDP of an MSX2 adapter fitted to an MSX1
;   08Ch-08Dh  MSX MODEM
;   08Eh-08Fh  system reserved
;   092h-097h  system reserved
;   09Ch-09Fh  system reserved
;   0A4h-0A7h  system reserved
;   0ACh-0AFh  MSX ENGINE, the one-chip MSX
;   0B0h-0B3h  expansion memory, one maker only
;   0B6h-0B7h  system reserved
;   0B8h-0BBh  light pen control, one maker only
;   0BCh-0BFh  VHD control, one maker only
;   0C4h-0C7h  system reserved
;   0C8h-0CFh  MSX INTERFACE, an asynchronous serial interface
;   0D0h-0D7h  the floppy disk controller. USABLE ONLY WHILE THE FDC
;              IS BEING ACCESSED: an external signal can cut it off
;   0DCh-0F2h  system reserved
;   0F8h-0FBh  system reserved

; --- MSX-MUSIC, an OPLL. THE MANUAL SAYS NOT TO DRIVE THESE TWO
; PORTS FROM COMMERCIAL SOFTWARE, and to go through the FM BIOS
; instead: get the timing wrong and the chip misbehaves rather
; than complains. They are here because the map has them and
; because a program that does drive them needs the three
; addresses below as well.

IO_MUSREG	equ	07ch	; which register, write only. WAIT 3.36us
				;   AFTER WRITING before touching the chip
				;   again
IO_MUSDAT	equ	07dh	; its value, write only. WAIT 23.52us
				;   AFTER WRITING, seven times as long as
				;   the register write. Ignore either wait
				;   and the value that was set is not
				;   guaranteed.
				;   Those are the two figures the manual
				;   gives. Ours, from them: about 12 and 84
				;   Z80 cycles at 3.58MHz - AND TWICE THAT
				;   MANY on a turbo R at 7.16MHz, so a wait
				;   counted in instructions is too short
				;   there

; An OPLL may be built into the machine or sitting in a cartridge,
; and a cartridge one STARTS SWITCHED OFF. It is switched on by
; BASIC CALL MUSIC, or by the FM BIOS initialising - but only when
; the machine has no OPLL of its own. So a program that drives the
; ports directly has to find the chip and, if it is in a
; cartridge, switch it on:
;
; 1. Look through the slots for OPLL_ID_MACHINE. Found means the
;    machine has its own OPLL and it is ready to use.
; 2. Otherwise look for OPLL_ID_CART. Not found means there is no
;    OPLL anywhere.
; 3. Found: set bit 0 of OPLL_ENABLE in that slot.
;
; THE ORDER MATTERS, and the reason is worth seeing. The eight
; bytes of "APRLOPLL" end at 0401Fh, so its last four bytes ARE
; the four bytes of "OPLL" at 0401Ch: a built-in chip matches the
; cartridge test too. Test for the cartridge first and every
; machine looks like a cartridge.

OPLL_ID_MACHINE	equ	04018h	; "APRLOPLL", eight bytes to 0401Fh:
				;   the machine has an OPLL of its own
OPLL_ID_CART	equ	0401ch	; "OPLL", four bytes to 0401Fh: the
				;   OPLL is in a cartridge
OPLL_ENABLE	equ	07ff6h	; bit 0 switches a cartridge OPLL on.
				;   READ THE BYTE, SET BIT 0, WRITE IT
				;   BACK: the other seven bits belong to
				;   the cartridge and must be left as they
				;   were

; --- RS-232C. An 8251, an 8253 and 8K of ROM, on a cartridge.
; THESE ARE THE SINGLE CHANNEL ADDRESSES. The multi channel type
; puts the same registers in memory instead, and follows below.

IO_RSDATA	equ	080h	; 8251 data, read and write
IO_RSSTAT	equ	081h	; 8251 status on read, command on write
IO_RSINTM	equ	082h	; TWO DIFFERENT REGISTERS AT ONE ADDRESS.
				;   Read it for the system status, bit by
				;   bit from 7: CTS, timer/counter output
				;   2 from the 8253, four reserved bits,
				;   RI, CD. CTS, RI AND CD READ 0 WHEN THE
				;   SIGNAL IS ASSERTED. RI and CD are both
				;   optional, and a cartridge that has only
				;   one of them has CD.
				;   Write it to mask interrupts, bit by
				;   bit from 7: four reserved bits, the
				;   8253 channel 2 timer, sync character or
				;   break detect, TxReady, RxReady. A 1
				;   DISABLES and a 0 ENABLES, and every bit
				;   starts as 1. All but RxReady are
				;   optional: on the smallest cartridge
				;   RxReady is the only interrupt there is.
				;   The four reserved bits are not all
				;   reserved on the multi channel type: see
				;   the note after RS232_MULTI_CH3 below
IO_RSTIMR	equ	084h	; 8253 counter 0. 085h is counter 1, 086h
				;   is counter 2, and 087h the mode
				;   register, write only. 083h, between the
				;   two groups, is reserved

; --- RS-232C, the multi channel type. THESE ARE MEMORY ADDRESSES,
; not ports: four channels cannot share 080h to 087h, so a cartridge
; with more than one puts its registers in memory. Four channels to
; a machine at most, in one cartridge or spread over two. The ROM
; sits at 4000h to 5FFFh, 8K at least, and the RAM at 6000h to
; 67FFh. That same RAM is visible again at 0A000h to 0A7FFh: one
; memory at two addresses, so a byte written at the one is read at
; the other. Everything from 6800h to 9FFFh and from 0A800h to
; 0BFDFh is unused, and the channels sit at the very top.
;
; A channel is eight bytes laid out like 080h to 087h above: +0
; data, +1 the 8251 status and command, +2 the status and the mask,
; +3 reserved, +4 to +6 the 8253 counters, +7 its mode register.
; THE BASES COUNT DOWNWARDS. Channels must be fitted from 0 upwards
; with no gaps: 0 alone, 0 and 1, 0 to 2, or all four. Channel 1
; without channel 0, or 0 and 2 without 1, is wrong.

RS232_MULTI_CH0	equ	0bff8h	; channel 0, the eight bytes to 0BFFFh
RS232_MULTI_CH1	equ	0bff0h	; channel 1, the eight bytes to 0BFF7h
RS232_MULTI_CH2	equ	0bfe8h	; channel 2, the eight bytes to 0BFEFh
RS232_MULTI_CH3	equ	0bfe0h	; channel 3, the eight bytes to 0BFE7h

; 0BFFAh READ is 082h read, bit for bit: the status register is
; the same on both types. 0BFFAh WRITTEN is the interrupt mask
; again, with three differences:
;
; * BIT 4 IS THE I/O PORT ENABLE for channel 0, and here 1 ALLOWS
;   while 0 forbids. It starts at 0. Allow it and channel 0
;   answers at 080h to 087h as well, which is how a program
;   written for the single channel type goes on working. Mind the
;   sense: in this one register a 1 in bit 4 allows, and a 1 in
;   bits 3 to 0 disables.
; * BIT 4 IS THE ONE BIT OF 082h THAT IS NOT 0BFFAh. It cannot be
;   reached through the port at all, and that is deliberate: a
;   program able to clear it through 082h could cut off the very
;   port it was reaching the cartridge through.
; * BITS 7, 6 AND 5 MUST BE WRITTEN AS 1. The single channel type
;   calls them reserved and says nothing about their value.

; --- The printer. WHICH PORT CARRIES THE STATUS BIT IS IN DISPUTE
; and this file will not guess. The I/O map in volume 1 appendix
; A.4 gives 090h as bit 0 strobe on write and 091h as bit 1 status
; on read, and never mentions a data port. Figure 6.18 in volume 2
; chapter 4 gives 091h as the eight data bits, bit 0 of 090h as the
; strobe when written, and bit 1 of 090h as the status when read,
; 0 ready and 1 busy. Both agree on one thing only: the strobe is
; bit 0 of 090h, and it sends the byte when it is LOW. The names
; below follow the I/O map, which is the list this file was made
; from. See the printer entries in bios.inc, and prefer LPTOUT to
; driving these ports by hand until the question is settled.

IO_PRNSTB	equ	090h	; bit 0 is the strobe, LOW to send. The
				;   figure puts the status bit here too,
				;   in bit 1, when the port is read
IO_PRNSTS	equ	091h	; the I/O map calls this bit 1 status,
				;   read only. The figure calls it the
				;   eight data bits, write

; --- The VDP. THE 098h FAMILY IS A CONVENTION, NOT A GUARANTEE.
;
; The port a machine really uses is in the main ROM: 0006h holds the
; read port and 0007h the write port. Check there in anything meant
; to run on hardware you have not seen. An MSX1 with an MSX2 adapter
; in it answers at 088h to 08Bh instead.

ROM_VDP_READ	equ	0006h	; main ROM: the VDP read port. AN ADDRESS,
				;   not a port
ROM_VDP_WRITE	equ	0007h	; main ROM: the VDP write port
IO_VDPVRM	equ	098h	; VRAM, read and write
IO_VDPCMD	equ	099h	; write: a register or a VRAM address
				;   read: the status register
IO_VDPPAL	equ	09ah	; the palette, write only
IO_VDPIND	equ	09bh	; indirect register write, write only

; --- The sound generator, an AY-3-8910.

IO_PSGREG	equ	0a0h	; which register, write only
IO_PSGWR	equ	0a1h	; its value, write
IO_PSGRD	equ	0a2h	; its value, read

; --- The 8255. PORT A IS THE SLOT SELECTION for all four pages,
; two bits each, and port C drives the keyboard row, CAPS, the key
; click and the cassette motor.

IO_PPIA		equ	0a8h	; port A
IO_PPIB		equ	0a9h	; port B
IO_PPIC		equ	0aah	; port C. BIT 7 IS A SOUND OUTPUT: the
				;   program toggles it and the result is
				;   mixed with the PSG before the speaker
IO_PPICTL	equ	0abh	; mode set

; --- The clock chip, an RP-5C01.

IO_CLKADR	equ	0b4h	; which register, write only
IO_CLKDAT	equ	0b5h	; its value

; --- MSX-AUDIO, a Y8950. Two channels: the master is required and
; the slave is optional, and each is an address port and a data
; port. ONLY THE READABLE REGISTERS CAN BE READ BACK through the
; data ports.

IO_AUDADR	equ	0c0h	; the master channel: which register, write
				;   only
IO_AUDDAT	equ	0c1h	; the master channel: its value
IO_AUDADR2	equ	0c2h	; the slave channel, which a cartridge need not
				;   have: which register, write only
IO_AUDDAT2	equ	0c3h	; the slave channel: its value

; The Y8950 also has a four bit general purpose port OF ITS OWN,
; reached through the registers above rather than from the Z80. Bit
; by bit from 3: the filter used while recording or playing, 0 for
; ADPCM and PCM and 1 for FM; then the switch READ at start up to
; choose what runs, 0 extended BASIC and 1 the built-in application;
; then two bits the built-in application writes for its own purposes.

; --- MSX-AUDIO, the cartridge's own banks. THESE TWO ARE MEMORY
; ADDRESSES INSIDE THE CARTRIDGE, not ports, and they are WRITE ONLY
; IN AN UNUSUAL WAY: a write goes to the register, a read gets the
; ordinary memory that lives at the address. So neither can be read
; back, and read-modify-write is not available.
;
; Both answer whichever bank is showing, and both can be written at
; 7FFEh and 7FFFh as well. That is not a second decoder: 7000h to
; 7FFFh is an image of the RAM at 3000h to 3FFFh, and these two
; addresses sit in it.
;
; BOTH MUST BE SET TO 00 AT RESET.

AUDIO_BANK	equ	03ffeh	; which of the four 32K banks shows. Bits 1 and
				;   0 only: 0 the MBIOS and extended BASIC, 1
				;   the built-in application, 2 ADPCM data ROM
				;   1, 3 ADPCM data ROM 2. Bank 0 is ROM at
				;   0000h to 2FFFh, RAM to 3FFFh, ROM to 6FFFh
				;   and the RAM image to 7FFFh; each of the
				;   other three is one ROM from 4000h to 0BFFFh
AUDIO_PORTSEL	equ	03fffh	; where the Y8950 answers. Bits 1 and 0 only: 0
				;   nowhere, 1 from 0C0h, 2 from 0C2h, 3 two
				;   chips in one cartridge, one at each.
				;   Extended BASIC sets this while initialising
				;   after a reset

; --- The kanji ROM.

IO_KAN1LO	equ	0d8h	; level 1: the low address, bits 5 to 0,
				;   write only
IO_KAN1HI	equ	0d9h	; level 1: write the high address, bits 5
				;   to 0. Read the data, all eight bits
IO_KAN2LO	equ	0dah	; level 2, the same pair
IO_KAN2HI	equ	0dbh	; level 2

; --- MSX-MIDI. An 8251 and an 8253. A MACHINE WITH IT BUILT IN
; HAS THEM AT 0E8h TO 0EFh; a cartridge starts at 0E0h and 0E1h
; and can be moved onto the built in addresses with 0E2h below.
;
; THE 8251 NEEDS 16 CLOCKS AT 3.579545MHz BETWEEN WRITES to its
; mode and command registers, so put a wait between them. Writing
; 00h, 00h, 00h, 40h to its status port resets it, and a mode has
; to be set afterwards or it does not work as MIDI.
;
; To tell whether a machine has any: bit 0 of 002Eh in the MAIN
; ROM says it is built in, and with the MAIN ROM version at 002Dh
; 03h or higher, a slot holding MIDI at 401Ch to 401Fh is a
; cartridge. Version 02h or lower has none.

IO_MIDDAT2	equ	0e0h	; 8251 data, cartridge, when 0E2h bit 0 is 1
IO_MIDSTA2	equ	0e1h	; 8251 status and control, the same case
IO_MIDCFG	equ	0e2h	; where a cartridge MIDI lives, write only
IO_MIDDAT	equ	0e8h	; 8251 data, read and write
IO_MIDSTA	equ	0e9h	; 8251 status on read, control on write
IO_MIDLAT	equ	0eah	; 8253 OUT2 latch. ANY WRITE CLEARS THE
				;   counter 2 interrupt. 0EBh is the same port
IO_MIDCT0	equ	0ech	; 8253 counter 0, the 8251 baud rate
IO_MIDCT1	equ	0edh	; 8253 counter 1, general purpose
IO_MIDCT2	equ	0eeh	; 8253 counter 2, the periodic interrupt
IO_MIDCTL	equ	0efh	; 8253 control word, write only

; --- Ports the later machines added.

IO_VDPMOD	equ	0f3h	; THE DISPLAY MODE, MSX2+. Bit by bit,
				;   0 upwards: M3, M4, M5, M2, M1, TP,
				;   YUV, YAE
IO_RESETF	equ	0f4h	; the hardware reset flag, MSX2+. It is
				;   the top bit that carries it
IO_SYSCTL	equ	0f5h	; SYSTEM CONTROL, WRITE ONLY. A one in a
				;   bit makes that device usable, and the
				;   bits are, 0 upwards: kanji ROM level 1,
				;   kanji ROM level 2, MSX-AUDIO,
				;   superimpose, MSX INTERFACE, RS-232C,
				;   light pen, clock chip.
				;   THE BIOS OWNS THIS PORT. It is how a
				;   built-in device and a cartridge that
				;   wants the same address are kept apart,
				;   and it is set once at initialisation.
				;   An application must not read or write it
IO_COLBUS	equ	0f6h	; the colour bus
IO_AVCTRL	equ	0f7h	; A/V CONTROL. Bit by bit, 0 upwards:
				;   audio R and mixing on, audio L and
				;   mixing off, video input select and
				;   21-pin RGB, video input detected (this
				;   one reads), AV control and TV, Ym
				;   control and TV, invert bit 4 of VDP
				;   register 9, invert bit 5 of it. All of
				;   them write except bit 3

; --- The memory mapper, 0FCh to 0FFh, write only.
;
; WHICH PAGE EACH OF THE FOUR BELONGS TO IS IN DISPUTE and this file
; will not guess. The I/O map these came from puts page 3 at 0FCh
; and counts down to page 0 at 0FFh; the rest of the world, and a
; comment in this project's own mapper, has 0FCh as page 0 and
; counts up. One of the two is wrong and being wrong here crashes
; the machine, so no page is named below.
;
; IN A PROGRAM RUNNING UNDER MSX-DOS 2 THE QUESTION DOES NOT ARISE.
; Ask the mapper support routines for a segment and let them switch
; it: they keep MSX-DOS's own record of page 2 true, which a write to
; a port does not, and page 3 is where the operating system lives.

IO_MAPSEG	equ	0fch	; the first of the four segment select
				;   registers. The four are 0FCh, 0FDh,
				;   0FEh and 0FFh



