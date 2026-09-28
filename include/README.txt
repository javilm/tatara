include\ - header files for MSX programs
========================================

These are equates, not code. Nothing in this directory is built into
Tatara or TANREN; it is here for the programs you write with them. Put
the directory where the TATARA environment variable points, and include
what you need:

	include	msxdos.inc

Where the MSX has an official name, that is the name here, taken from
the MSX Datapack. Where a name is ours, the file's own header says so
and says why.

  file            entries  what it is
  --------------  -------  ---------------------------------------------
  ascii.inc            37  the control codes, 00h to 7Fh, as CHR_ names
  bios.inc             92  MAIN ROM entry points, 0000h to 017Dh
  errors.inc           76  MSX-DOS and MSX-DOS2 error codes, 0FFh down
                           to 081h
  extbio.inc           85  the extended BIOS: device numbers, function
                           numbers, and the MSX-MUSIC FM BIOS
  hooks.inc           117  the hooks, 0FD9Ah to 0FFD4h
  msxdos.inc           94  MSX-DOS function numbers, 00h to 70h, and the
                           "system" macro
  ports.inc            56  the I/O ports, and the few memory addresses
                           that behave like one
  subrom.inc           36  SUB ROM entry points, 0089h to 01F9h, MSX2
                           and later
  workarea.inc        311  the system work area, 0F323h to 0FFFFh

904 names in all.


THINGS WORTH KNOWING BEFORE YOU INCLUDE ONE

errors.inc runs downwards. The codes count down from 0FFh, which is how
the manual lists them and the order they were allotted in. Every other
file ascends.

subrom.inc prefixes every name SUBROM_. The SUB ROM reuses MAIN ROM
names for different routines at different addresses - GRPPRT is 008Dh in
the MAIN ROM and 0089h in the SUB ROM - so without the prefix this file
and bios.inc could not both be included.

msxdos.inc defines a macro as well as the function numbers. "system
func" loads C and calls BDOS, and it is wrapped in IFNDEF so that a
program whose modules each include the file still assembles.

Two hooks have two names. MSX-MIDI renamed 0FF75h and 0FF93h, and
hooks.inc carries the old name and the new one for each. They are the
same five bytes, not four hooks.

