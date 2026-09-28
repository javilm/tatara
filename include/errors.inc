; errors.inc - the MSX-DOS and MSX-DOS2 error codes.
;
; Part of the Tatara distribution. Nothing here is built into the
; assembler or the linker; put the file where TATARA points and
; include what you need:
;
;	include	errors.inc
;
; THE NAMES CARRY A LEADING DOT because that is what the manual
; prints and what the MSX-DOS2 sources use throughout. A dot is a
; name character, and a label is a label because it starts in
; column 1, so a dotted label is never taken for a dotted
; directive like .LIST.
;
; HOW AN MSX-DOS2 FUNCTION REPORTS ONE. The functions numbered 40h and
; up return a code in A, and zero means it worked. MSX-DOS2 does an
; OR A just before it returns, so a JR NZ immediately after the CALL 5
; tests for an error without a CP:
;
;	call	5
;	jr	nz,failed
;
; At the jump you normally load the code into B and call the terminate
; with error code function, which hands it to the command interpreter
; and the message is printed there. A program that would rather print
; the message itself can ask for the text with the explain error code
; function.
;
; THE CODES COUNT DOWN FROM 0FFh, so this file is in DESCENDING order
; - the order the manual lists them in, and the order they were
; allotted. Every other file in include/ ascends.
;
; Below 40h are the user errors. The system does not use them and a
; program is free to return its own. A user error below 20h returned
; to the command interpreter prints nothing at all.
;
; THE MESSAGES ARE SPELLED CORRECTLY HERE. Three of them are misspelt
; in the manual - Seek errror, File allocation errror, Cannnot
; transfer above 64K - and this file does not copy that through.
;
; Asked to explain a code that has no message, the explain error code
; function answers System error <n> or User error <n>.

; --- 16.1 DISK ERRORS. These go to the disk error handling routine,
; which by default reports them as an abort-or-retry error. EXCEPT
; UNDER FORMAT A DISK THEY ARE NOT RETURNED FROM BDOS AT ALL: the
; function call hands them to the error routine instead, so a caller
; testing A after CALL 5 will not see them.

.NCOMP		equ	0ffh	; Incompatible disk. The drive cannot get at
				;   this disk - a double sided disk in a single
				;   sided drive, for one
.WRERR		equ	0feh	; Write error. Something went wrong while
				;   writing to the disk
.DISK		equ	0fdh	; Disk error. A disk error whose cause is not
				;   known
.NRDY		equ	0fch	; Not ready. The drive does not answer. Usually
				;   there is no disk in it
.VERFY		equ	0fbh	; Verify error. With VERIFY on, a sector did
				;   not read back correctly after it was
				;   written
.DATA		equ	0fah	; Data error. A sector would not read because
				;   its CRC check failed, which usually means
				;   the disk is damaged. The CRC goes into the
				;   sector beside the data, and checking it is
				;   how a bad read is caught
.RNF		equ	0f9h	; Sector not found. The sector asked for is not
				;   on the disk. Usually the disk is damaged
.WPROT		equ	0f8h	; Write protected disk. A write was tried on a
				;   disk with its write protect on
.UFORM		equ	0f7h	; Unformatted disk. The disk is not formatted,
				;   or is formatted some other way
.NDOS		equ	0f6h	; Not a DOS disk. The disk is formatted for
				;   another operating system and MSX-DOS cannot
				;   read it
.WDISK		equ	0f5h	; Wrong disk. The disk was swapped while
				;   MSX-DOS was using it. The right one has to
				;   go back in
.WFILE		equ	0f4h	; Wrong disk for file. The disk was swapped
				;   while a file open on it was still open. The
				;   right one has to go back in
.SEEK		equ	0f3h	; Seek error. The track asked for was not found
.IFAT		equ	0f2h	; Bad file allocation table. The FAT on the
				;   disk is broken. CHKDSK can sometimes get
				;   some of the data back
.NOUPB		equ	0f1h	; NO MESSAGE AND NEVER SEEN. MSX-DOS traps it
				;   inside itself as part of handling a disk
				;   change, so it does not reach a program at
				;   all
.IFORM		equ	0f0h	; Cannot format this drive. A format was tried
				;   on a drive that cannot be formatted.
				;   Usually a RAM disk

; --- 16.2 MSX-DOS FUNCTION ERRORS. THESE ARE THE ONES A FUNCTION
; CALL RETURNS, which is what makes them different from 16.1 above:
; these arrive in A and a program tests for them. 17.3 says which
; function returns which.

.INTER		equ	0dfh	; Internal error. An error that should never
				;   happen
.NORAM		equ	0deh	; Not enough memory. MSX-DOS has used up its
				;   16K kernel data segment. Use fewer sector
				;   buffers or drop some environment variables.
				;   It also comes back when there is no free
				;   segment left to build a RAM disk out of
.IBDOS		equ	0dch	; Invalid MSX-DOS call. The function number was
				;   not a real one. MOST BAD FUNCTION NUMBERS
				;   RETURN NOTHING AT ALL; this one can come
				;   back from the get previous error code
				;   function
.IDRV		equ	0dbh	; Invalid drive. The drive number, or the drive
				;   letter in a drive-path-file string, is not
				;   one this system has
.IFNM		equ	0dah	; Invalid filename. ONLY FOR A BARE FILENAME
				;   STRING, not for a drive-path-file string
.IPATH		equ	0d9h	; Invalid pathname. The syntax of the string is
				;   wrong somewhere. Any function taking an
				;   ASCIIZ drive-path-file string can return it
.PLONG		equ	0d8h	; Pathname too long. The whole path, counting
				;   the current directory when that is in play,
				;   is longer than 63 characters
.NOFIL		equ	0d7h	; File not found. From any function that
				;   searches the disk for a file. ALSO when a
				;   directory was named and not found - .NODIR
				;   below is for a directory in the MIDDLE of
				;   the path
.NODIR		equ	0d6h	; Directory not found. A directory part way
				;   along the drive-path-file string was not
				;   there
.DRFUL		equ	0d5h	; Root directory full. From create or move,
				;   when a new entry was wanted in the root
				;   directory and it is full. THE ROOT
				;   DIRECTORY CANNOT BE EXTENDED
.DKFUL		equ	0d4h	; Disk full. From a write with no room left for
				;   the data, and from creating or extending a
				;   subdirectory on a full disk
.DUPF		equ	0d3h	; Duplicate filename. From rename or move, when
				;   the name wanted is already in the directory
				;   wanted
.DIRE		equ	0d2h	; Invalid directory move. A subdirectory was to
				;   be moved under itself, which would cut a
				;   loop out of the tree
.FILRO		equ	0d1h	; Read only file. A write or a delete was tried
				;   on a file with its read only attribute set
.DIRNE		equ	0d0h	; Directory not empty. A subdirectory that
				;   still has something in it cannot be deleted
.IATTR		equ	0cfh	; Invalid attributes. An attribute was to be
				;   changed in a way that is not allowed, or
				;   something only a subdirectory can do was
				;   asked of a file. Misusing the volume name
				;   FIB gives it too
.DOT		equ	0ceh	; Invalid . or .. operation. Renaming or moving
				;   the . and .. entries of a subdirectory is
				;   not allowed
.SYSX		equ	0cdh	; System file exists. A file or subdirectory
				;   was to be created over an existing system
				;   file. A SYSTEM FILE IS NEVER DELETED FOR
				;   YOU
.DIRX		equ	0cch	; Directory exists. A file or subdirectory was
				;   to be created over an existing
				;   subdirectory. A SUBDIRECTORY IS NEVER
				;   DELETED FOR YOU
.FILEX		equ	0cbh	; File exists. A subdirectory was to be created
				;   over an existing file. A FILE IS NEVER
				;   DELETED FOR YOU
.FOPEN		equ	0cah	; File is already in use. Deleting, renaming,
				;   moving or changing the attributes, date or
				;   time of a file that has a file handle open
				;   on it, without going through that handle
.OV64K		equ	0c9h	; Cannot transfer above 64K. The disk transfer
				;   area would run past 0FFFFh
.FILE		equ	0c8h	; File allocation error. The cluster chain of
				;   the file is broken. CHKDSK recovers what it
				;   can
.EOF		equ	0c7h	; End of file. A read was tried with the file
				;   pointer already at or past the end of the
				;   file
.ACCV		equ	0c6h	; File access violation. A read or a write on a
				;   file handle that was not opened with the
				;   access bit for it. SOME OF THE STANDARD
				;   HANDLES ARE OPENED READ ONLY OR WRITE ONLY
.IPROC		equ	0c5h	; Invalid process id. The one handed to the
				;   return to parent process function is not a
				;   real one
.NHAND		equ	0c4h	; No spare file handles. Every one is in use
				;   already. THIS VERSION HAS 64
.IHAND		equ	0c3h	; Invalid file handle. The number is above the
				;   highest the system allows
.NOPEN		equ	0c2h	; File handle not open. That handle is not open
				;   at the moment
.IDEV		equ	0c1h	; Invalid device operation. A file handle or
				;   FIB belonging to a device was used for
				;   something a device cannot do, searching or
				;   moving for instance
.IENV		equ	0c0h	; Invalid environment string. There is a
				;   character in the name that is not allowed
.ELONG		equ	0bfh	; Environment string too long. A name or a
				;   value went past 255 characters, or the
				;   buffer handed in was not big enough for it
.IDATE		equ	0beh	; Invalid date. The date handed to the set date
				;   function is not a real one
.ITIME		equ	0bdh	; Invalid time. The time handed to the set time
				;   function is not a real one
.RAMDX		equ	0bch	; RAM disk already exists, and it is drive H.
				;   From the RAM disk function, asked to make
				;   one when there is one
.NRAMD		equ	0bbh	; RAM disk does not exist. From the RAM disk
				;   function, asked to remove one when there is
				;   none. REACHING for a RAM disk that is not
				;   there gives .IDRV instead, not this
.HDEAD		equ	0bah	; File handle has been deleted. The file the
				;   handle belonged to is gone, so the handle
				;   is no use
.EOL		equ	0b9h	; NO MESSAGE. An internal error that should
				;   never happen
.ISBFN		equ	0b8h	; Invalid sub-function number. The one handed
				;   to the device I/O control function is not a
				;   real one
.IFCB		equ	0b7h	; Invalid File Control Block. From a read or a
				;   write through an FCB that was never opened,
				;   or is not a valid FCB

; --- 16.3 PROGRAM TERMINATION ERRORS. The system makes these itself
; and hands them to the abort routine. THEY ARE NOT NORMALLY
; RETURNED FROM A FUNCTION CALL either. The abort routine also gets
; whatever a program passes to the terminate with error code
; function, so it sees codes from outside this list too.

.STOP		equ	09fh	; Ctrl-STOP pressed. Checked in most system
				;   calls, and in all the character I/O ones
.CTRLC		equ	09eh	; Ctrl-C pressed. CHECKED ONLY in the character
				;   functions that do a status check, which is
				;   the difference from Ctrl-STOP above
.ABORT		equ	09dh	; Disk operation aborted, by the user or by the
				;   system itself. THE DISK ERROR THAT STARTED
				;   IT COMES TO THE ABORT ROUTINE IN B, as a
				;   secondary code
.OUTERR		equ	09ch	; Error on standard output, while it was being
				;   reached through a character function, 01h
				;   to 0Bh. The real error comes in B as a
				;   secondary code. Normally only happens to a
				;   program that has changed the standard
				;   handles
.INERR		equ	09bh	; Error on standard input, the same way and
				;   with the same secondary code in B. .EOF IS
				;   THE LIKELY ONE

; --- 16.4 COMMAND ERRORS. The command interpreter uses these and no
; MSX-DOS function call returns them. They are here because a
; program may return them itself.

.BADCOM		equ	08fh	; Wrong version of command. COMMAND2.COM loaded
				;   its transient part off the disk and the
				;   checksum was not the one expected
.BADCM		equ	08eh	; Unrecognized command. Not an internal
				;   command, and no COM or BAT file of that
				;   name was found either
.BUFUL		equ	08dh	; Command too long. A line in a batch file went
				;   past 127 characters
.OKCMD		equ	08ch	; NO MESSAGE. An internal code, returned when a
				;   command handed to COMMAND2.COM on the
				;   command line has finished
.IPARM		equ	08bh	; Invalid parameter. Something is wrong with a
				;   parameter to the command, a number out of
				;   range for one
.INP		equ	08ah	; Too many parameters. Every parameter the
				;   command wanted has been read and there is
				;   still something on the line that is not a
				;   delimiter
.NOPAR		equ	089h	; Missing parameter. The end of the line came
				;   where a parameter should have been
.IOPT		equ	088h	; Invalid option. The character after the / is
				;   not one this command takes
.BADNO		equ	087h	; Invalid number. Something that is not a digit
				;   turned up where a number was wanted
.NOHELP		equ	086h	; File for HELP not found, or the parameter was
				;   not one HELP takes
.BADVER		equ	085h	; Wrong version of MSX-DOS. THE COMMAND
				;   INTERPRETER NEVER USES THIS ONE - it has a
				;   message of its own for the case. It is here
				;   for a program that finds it useful to
				;   return
.NOCAT		equ	084h	; Cannot concatenate destination file. The file
				;   CONCAT was to write matches one of the ones
				;   it was to read
.BADEST		equ	083h	; Cannot create destination file. Creating it
				;   would write over one of the source files,
				;   or over another file already in use
.COPY		equ	082h	; File cannot be copied onto itself. Creating
				;   the destination would write over the source
.OVDEST		equ	081h	; Cannot overwrite previous destination file.
				;   COPY was given a source with wildcards in
				;   it and a destination with none, which is
				;   not a directory and not a device either

