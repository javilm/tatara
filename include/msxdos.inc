; msxdos.inc - the MSX-DOS and MSX-DOS2 function numbers.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	msxdos.inc
;
; The names are the official ones, the public labels MSX-DOS2 defines
; in CODES.MAC, leading underscore and all. Function number in C,
; parameters in the other registers, then CALL 5:
;
;	ld	c,_CONOUT
;	ld	e,"!"
;	call	BDOS
;
; or, with the macro this file defines:
;
;	ld	e,"!"
;	system	_CONOUT
;
; From Disk-BASIC, or from a program in ROM, the entry is 0F37Dh.
;
; What each one wants in its registers, what it gives back and what
; it destroys are in the MSX-DOS manuals and are not repeated here.
; The error codes are in errors.inc.
;
; Everything below 31h is in MSX-DOS1 too. 31h and up are MSX-DOS2
; only, 31h included.

; --- The BDOS entry, and a macro for calling it.
;
; The macro is wrapped in IFNDEF so that a program whose modules each
; include this file assembles: the second time through, the macro is
; already defined and the block is skipped. MSXDOS_INC is the sentinel
; and has no other use.
;
; "system" loads C and calls BDOS, so it costs you C and whatever the
; function itself destroys, and nothing more. IT ALWAYS CALLS 0005h -
; from Disk-BASIC or from ROM, where the entry is 0F37Dh, do the call
; yourself.

BDOS		equ	0005h	; the MSX-DOS function call entry

		ifndef	MSXDOS_INC
MSXDOS_INC	equ	1	; this file has been included once
system		macro	func
		ld	c,func
		call	BDOS
		endm
		endif

; --- Console, printer and the auxiliary device.

_TERM0		equ	00h	; end the program with a return code of 0
_CONIN		equ	01h	; read a character from standard input
_CONOUT		equ	02h	; write the character in E to standard output
_AUXIN		equ	03h	; read a character from the auxiliary device
_AUXOUT		equ	04h	; write E to the auxiliary device
_LSTOUT		equ	05h	; write E to the printer
_DIRIO		equ	06h	; direct console I/O, no echo and no waiting
_DIRIN		equ	07h	; read a character, no echo, waits
_INNOE		equ	08h	; read a character, no echo
_STROUT		equ	09h	; write the dollar terminated string at DE
_BUFIN		equ	0ah	; read a line into the buffer at DE
_CONST		equ	0bh	; is a character waiting on standard input
_CPMVER		equ	0ch	; the emulated CP/M version, always 2.2

; --- Disks and files through an FCB.

_DSKRST		equ	0dh	; flush the buffers, reset the DTA and drive
_SELDSK		equ	0eh	; make drive E the default, count the drives
_FOPEN		equ	0fh	; open the file the FCB at DE names
_FCLOSE		equ	10h	; close the FCB at DE
_SFIRST		equ	11h	; find the first entry the FCB at DE matches
_SNEXT		equ	12h	; find the next entry, after _SFIRST
_FDEL		equ	13h	; delete the files the FCB at DE matches
_RDSEQ		equ	14h	; read the next 128 byte record into the DTA
_WRSEQ		equ	15h	; write the next 128 byte record from the DTA
_FMAKE		equ	16h	; create the file the FCB at DE names, open it
_FREN		equ	17h	; rename the files the FCB at DE matches
_LOGIN		equ	18h	; which drives exist, a bit each in HL
_CURDRV		equ	19h	; the current drive number
_SETDTA		equ	1ah	; make DE the disk transfer address
_ALLOC		equ	1bh	; the size and free space of drive E

; --- 1Ch to 20h are not used.

_RDRND		equ	21h	; read the random record into the DTA
_WRRND		equ	22h	; write the random record from the DTA
_FSIZE		equ	23h	; the size of the file, in 128 byte records
_SETRND		equ	24h	; set the random record from the current one

; --- 25h is not used.

_WRBLK		equ	26h	; write HL records from the DTA
_RDBLK		equ	27h	; read HL records into the DTA
_WRZER		equ	28h	; _WRRND, zero filling any new clusters

; --- 29h is not used.

; --- The clock.

_GDATE		equ	2ah	; the date, and the day of the week
_SDATE		equ	2bh	; set the date
_GTIME		equ	2ch	; the time
_STIME		equ	2dh	; set the time

; --- Sectors, and the disk itself.

_VERIFY		equ	2eh	; turn verify after write on or off
_RDABS		equ	2fh	; read H sectors from drive L into the DTA
_WRABS		equ	30h	; write H sectors to drive L from the DTA
_DPARM		equ	31h	; the format parameters of drive L

; --- From 40h on is MSX-DOS2. Directory entries and FIBs.

_FFIRST		equ	40h	; find the first entry matching, into a FIB
_FNEXT		equ	41h	; find the next entry, after _FFIRST
_FNEW		equ	42h	; create a new directory entry

; --- File handles.

_OPEN		equ	43h	; open a file handle on the file DE names
_CREATE		equ	44h	; create a file or subdirectory and open it
_CLOSE		equ	45h	; close file handle B
_ENSURE		equ	46h	; flush file handle B without closing it
_DUP		equ	47h	; copy file handle B
_READ		equ	48h	; read HL bytes from handle B into DE
_WRITE		equ	49h	; write HL bytes from DE to handle B
_SEEK		equ	4ah	; move the file pointer of handle B
_IOCTL		equ	4bh	; look at or change the state of handle B
_HTEST		equ	4ch	; is handle B the same file as DE names

; --- Files and subdirectories by name.

_DELETE		equ	4dh	; delete the file or subdirectory DE names
_RENAME		equ	4eh	; rename it to the name at HL
_MOVE		equ	4fh	; move it to the path at HL
_ATTR		equ	50h	; get or set the attribute byte
_FTIME		equ	51h	; get or set the date and time of a file

; --- The same operations, by file handle.

_HDELETE	equ	52h	; delete the file and close handle B
_HRENAME	equ	53h	; rename the file handle B is open on
_HMOVE		equ	54h	; move the file handle B is open on
_HATTR		equ	55h	; get or set the attribute byte of handle B
_HFTIME		equ	56h	; get or set the date and time of handle B

; --- The disk transfer address.

_GETDTA		equ	57h	; the current disk transfer address
_GETVFY		equ	58h	; is verify after write on

; --- The current directory, and parsing strings.

_GETCD		equ	59h	; the current directory of drive B
_CHDIR		equ	5ah	; change the current directory to DE
_PARSE		equ	5bh	; parse a drive-path-file string
_PFILE		equ	5ch	; parse a filename into the buffer at HL
_CHKCHR		equ	5dh	; check a character and fold it to upper case
_WPATH		equ	5eh	; the full path of the last entry found
_FLUSH		equ	5fh	; flush the disk buffers of drive B

; --- Processes.

_FORK		equ	60h	; start a child process
_JOIN		equ	61h	; return to the parent process

; --- Ending, and handling errors.

_TERM		equ	62h	; end the program with the error code in B
_DEFAB		equ	63h	; define the abort routine, 0 to undefine
_DEFER		equ	64h	; define the disk error routine, 0 to undefine
_ERROR		equ	65h	; the error code from the last function
_EXPLAIN	equ	66h	; the message for the error code in B

; --- Formatting, the RAM disk, buffers, drive mapping.

_FORMAT		equ	67h	; format a disk, or update its boot sector
_RAMD		equ	68h	; make, remove or size the RAM disk
_BUFFER		equ	69h	; how many sector buffers, or set them
_ASSIGN		equ	6ah	; map a logical drive to a physical one

; --- Environment variables.

_GENV		equ	6bh	; the value of the variable named at HL
_SENV		equ	6ch	; set an environment variable
_FENV		equ	6dh	; the name of variable number DE

; --- The system.

_DSKCHK		equ	6eh	; get or set whether disk change is checked
_DOSVER		equ	6fh	; the MSX-DOS version numbers
_REDIR		equ	70h	; get or set the redirection state

