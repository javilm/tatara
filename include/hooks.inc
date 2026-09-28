; hooks.inc - the MSX hooks.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	hooks.inc
;
; A HOOK IS FIVE BYTES THE SYSTEM CALLS AT A FIXED MOMENT. An unused
; one holds a RET, so the call costs almost nothing and nothing
; happens. To take one over:
;
;   save the five bytes somewhere of your own
;   write what you want in their place - a JP and a RET fits, and so
;     does the RST 30h inter-slot form, which is what the RS-232C
;     hooks in workarea.inc hold
;   put the original five back when you are finished
;
; PUT THEM BACK. A hook left pointing into a program that has ended
; is a crash at the next interrupt, and H.TIMI is called fifty or
; sixty times a second.
;
; TWO HOOKS HAVE TWO NAMES. MSX-MIDI renamed 0FF75h and 0FF93h,
; and both names are here so that old source and new source both
; assemble. They are the same five bytes, not two hooks.
;
; Every hook below is five bytes. The names are the standard ones,
; uppercase, and they contain a dot, which is a legal character in a
; symbol. Under /C they are case-sensitive.

; --- Interrupts, the console, the character set and the key layout.

H.KEYI		equ	0fd9ah	; the interrupt, before anything else. This is
				;   where a device like the RS-232C gets in. A
				;   CARTRIDGE MSX-MIDI SENDS EVERY INTERRUPT
				;   HERE, not only MIDI IN and the 8253 timer,
				;   so a handler has to work out which it was:
				;   bit 1 of 0E9h is MIDI IN, bit 7 the timer.
				;   Reading 0E8h clears MIDI IN and any write
				;   to 0EAh clears the timer
H.TIMI		equ	0fd9fh	; the timer interrupt, every VDP frame. The
				;   one to hang a clock or a music player on
H.CHPU		equ	0fda4h	; CHPUT, which prints one character
H.DSPC		equ	0fda9h	; DSPCSR, which shows the cursor
H.ERAC		equ	0fdaeh	; ERACSR, which hides it
H.DSPF		equ	0fdb3h	; DSPFNK, which shows the function keys
H.ERAF		equ	0fdb8h	; ERAFNK, which hides them
H.TOTE		equ	0fdbdh	; TOTEXT, which puts the screen back into
				;   text mode
H.CHGE		equ	0fdc2h	; CHGET, which waits for a character
H.INIP		equ	0fdc7h	; INIPAT, which loads the character patterns
H.KEYC		equ	0fdcch	; KEYCOD, the key code conversion
H.KEYA		equ	0fdd1h	; KYEASY
H.NMI		equ	0fdd6h	; the non-maskable interrupt
H.PINL		equ	0fddbh	; PINLIN, which reads a program line
H.QINL		equ	0fde0h	; QINLIN, which prints a ? and reads a line
H.INLI		equ	0fde5h	; INLIN, which reads a line
H.ONGO		equ	0fdeah	; ONGOTP, the ON GOTO handler

; --- The disk system. These exist whether or not a disk interface
; is fitted; the interface is what fills them in.

H.DSKO		equ	0fdefh	; DSKO$, disk output
H.SETS		equ	0fdf4h	; SETS$, set attribute
H.NAME		equ	0fdf9h	; NAME, rename a file
H.KILL		equ	0fdfeh	; KILL, delete a file
H.IPL		equ	0fe03h	; IPL, the initial program load
H.COPY		equ	0fe08h	; COPY, copy a file
H.CMD		equ	0fe0dh	; CMD
H.DSKF		equ	0fe12h	; DSKF, how much room is left
H.DSKI		equ	0fe17h	; DSKI, disk input
H.ATTR		equ	0fe1ch	; ATTR$, a file attribute
H.LSET		equ	0fe21h	; LSET, assign left justified
H.RSET		equ	0fe26h	; RSET, assign right justified
H.FIEL		equ	0fe2bh	; FIELD
H.MKI$		equ	0fe30h	; MKI$, make an integer
H.MKS$		equ	0fe35h	; MKS$, make a single precision value
H.MKD$		equ	0fe3ah	; MKD$, make a double precision value
H.CVI		equ	0fe3fh	; CVI, convert to an integer
H.CVS		equ	0fe44h	; CVS, convert to single precision

H.CVD		equ	0fe49h	; CVD, convert to double precision
H.GETP		equ	0fe4eh	; GETPTR, fetch the file pointer
H.SETF		equ	0fe53h	; SETFIL, set the file pointer
H.NOFO		equ	0fe58h	; NOFOR, an OPEN with no FOR
H.NULO		equ	0fe5dh	; NULOPN, opening an empty file
H.NTFL		equ	0fe62h	; NTFL0, the file number is not zero
H.MERG		equ	0fe67h	; MERGE, merging two programs
H.SAVE		equ	0fe6ch	; SAVE
H.BINS		equ	0fe71h	; BINSAV, saving machine code
H.BINL		equ	0fe76h	; BINLOD, loading machine code
H.FILE		equ	0fe7bh	; FILES, listing a directory
H.DGET		equ	0fe80h	; DGET, the disk GET
H.FILO		equ	0fe85h	; FILOU1, file output
H.INDS		equ	0fe8ah	; INDSKC, reading a disk attribute
H.RSLF		equ	0fe8fh	; re-selecting the drive used before
H.SAVD		equ	0fe94h	; saving which drive is selected now
H.LOC		equ	0fe99h	; the LOC function, where in the file
H.LOF		equ	0fe9eh	; the LOF function, how long the file is
H.EOF		equ	0fea3h	; the EOF function
H.FPOS		equ	0fea8h	; the FPOS function
H.BAKU		equ	0feadh	; BAKUPT, the backup

; --- Logical device names. A cartridge that wants a device of its
; own - a printer, a network, a second disk system - gets its name
; recognised through these.

H.PARD		equ	0feb2h	; PARDEV, fetching a device name
H.NODE		equ	0feb7h	; NODEVN, no device name was given
H.POSD		equ	0febch	; POSDSK, a disk device
H.DEVN		equ	0fec1h	; DEVNAM, handling a device name
H.GEND		equ	0fec6h	; GENDSP, assigning a device

; --- Inside BASIC. Most of these are only useful to something that
; is extending the interpreter, and THE TABLE NAMES MANY OF THEM
; WITHOUT SAYING WHAT THEY DO. Where that is so this file says so:
; the address is the fact, the name is the only hint, and nothing
; below is guessed.

H.RUNC		equ	0fecbh	; RUNC, the clearing RUN does
H.CLEA		equ	0fed0h	; CLEARC, the clearing CLEAR does
H.LOPD		equ	0fed5h	; LOPDFT, repeat and set the defaults
H.STKE		equ	0fedah	; STKERR, a stack error
H.ISFL		equ	0fedfh	; ISFLIO, is this file input or output
H.OUTD		equ	0fee4h	; OUTDO, performing an OUT
H.CRDO		equ	0fee9h	; CRDO, performing a CRLF
H.DSKC		equ	0feeeh	; DSKCHI, reading a disk attribute
H.DOGR		equ	0fef3h	; DOGRPH, performing a graphics operation
H.PRGE		equ	0fef8h	; PRGEND, the end of a program
H.ERRP		equ	0fefdh	; ERRPRT, printing an error
H.ERRF		equ	0ff02h	; not documented
H.READ		equ	0ff07h	; READY
H.MAIN		equ	0ff0ch	; MAIN
H.DIRD		equ	0ff11h	; DIRDO, running a direct statement
H.FINI		equ	0ff16h	; not documented
H.FINE		equ	0ff1bh	; not documented
H.CRUN		equ	0ff20h	; not documented
H.CRUS		equ	0ff25h	; not documented
H.ISRE		equ	0ff2ah	; not documented
H.NTFN		equ	0ff2fh	; not documented
H.NOTR		equ	0ff34h	; not documented
H.SNGF		equ	0ff39h	; not documented
H.NEWS		equ	0ff3eh	; not documented
H.GONE		equ	0ff43h	; not documented
H.CHRG		equ	0ff48h	; not documented
H.RETU		equ	0ff4dh	; not documented
H.PRTF		equ	0ff52h	; not documented
H.COMP		equ	0ff57h	; not documented
H.FINP		equ	0ff5ch	; not documented
H.TRMN		equ	0ff61h	; not documented
H.FRME		equ	0ff66h	; not documented
H.NTPL		equ	0ff6bh	; not documented
H.EVAL		equ	0ff70h	; not documented
H.ONKO		equ	0ff75h	; not documented. SAME HOOK AS H.MDIN below,
				;   which is what MSX-MIDI calls it
H.MDIN		equ	0ff75h	; MSX-MIDI: the MIDI IN interrupt. BUILT IN
				;   MIDI ONLY - a cartridge goes to H.KEYI.
				;   H.ONKO above is the same five bytes, under
				;   the name the hook table gives
H.FING		equ	0ff7ah	; not documented
H.ISMI		equ	0ff7fh	; ISMID$, is this a MID$
H.WIDT		equ	0ff84h	; WIDTHS, the WIDTH statement
H.LIST		equ	0ff89h	; LIST
H.BUFL		equ	0ff8eh	; BUFLIN, the buffer line
H.FRQI		equ	0ff93h	; FRQINT. SAME HOOK AS H.MDTM below, which is
				;   what MSX-MIDI calls it
H.MDTM		equ	0ff93h	; MSX-MIDI: the 8253 timer interrupt. BUILT IN
				;   MIDI ONLY - a cartridge goes to H.KEYI.
				;   H.FRQI above is the same five bytes
H.SCNE		equ	0ff98h	; not documented
H.FRET		equ	0ff9dh	; FRETMP
H.PTRG		equ	0ffa2h	; PTRGET, the pointer for a variable that
				;   is not the default
H.PHYD		equ	0ffa7h	; PHYDIO, physical disk input and output
H.FORM		equ	0ffach	; FORMAT, formatting a disk
H.ERRO		equ	0ffb1h	; ERROR, handling an error in an
				;   application

H.LPTO		equ	0ffb6h	; LPTOUT, printing to a printer that is not
				;   the default one
H.LPTS		equ	0ffbbh	; LPTSTT, the status of that printer
H.SCRE		equ	0ffc0h	; SCREEN
H.PLAY		equ	0ffc5h	; PLAY

; --- The last three are not BASIC hooks. They are the same five
; bytes in the same style, and the system itself uses them.

EXTBIO		equ	0ffcah	; the extended BIOS call. See extbio.inc
DISINT		equ	0ffcfh	; MSX-DOS uses it
ENAINT		equ	0ffd4h	; MSX-DOS uses it

; The hooks end at 0FFD8h, but the extended BIOS owns 29 bytes from
; 0FFCAh and they run past that: five for the EXTBIO entry, five
; each for DISINT and ENAINT, then FOURTEEN MORE AT 0FFD9h WHICH
; ARE THE PROGRAM DISINT AND ENAINT JUMP INTO. 5+5+5+14 is 29, and
; 0FFCAh plus 29 is 0FFE7h, where the VDP register save area picks
; up - in workarea.inc, with the rest of that save area. So nothing
; between 0FFCAh and 0FFE6h is spare.

