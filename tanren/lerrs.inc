; lerrs.inc - public interface of lerrs.as: TANREN's errors.
;
; lerrs.as includes this file too: it defines LERRLIB first, which
; skips the external declarations below.
;
; SEPARATE FROM errs.as ON PURPOSE. The assembler's error module is
; about 2.5 KB of messages about macros, conditionals and expressions,
; and the linker would carry every byte of it to print none of them.
; Nothing shared calls into either one - alloc.as, hash.as, msxdos.as
; and strutil.as all answer with carry and let the caller decide.
;
; NONE OF THESE RETURN.

		ifndef	LERRLIB

		extrn errlopn		; the object file will not open
		extrn errlmag		; the first five bytes are not a
					; Tatara object file's
		extrn errlver		; they are, but the version byte is
					; not one this linker knows
		extrn errltrn		; the file ends inside a record, or
					; a record claims a length the file
					; does not have
		extrn errlunk		; an option we do not know
		extrn errlheap		; the mapper is full: a table
					; record would not fit
		extrn errlmseg		; more segments or groups in one
					; module than its maps hold
		extrn errlovlp		; /D: put the data on top of the
					; code
		extrn errlbig		; the image runs past FFFFh
		extrn errlydup		; two modules define the same
					; public symbol
		extrn errlyunr		; some external was never defined.
					; The NAMES are printed by lsychk
					; before this is reached - all of
					; them, which is the one place
					; either program does not stop at
					; the first
		extrn errlymix		; a module assembled /C is being
					; linked with one that was not, or
					; the other way round. MODNAME's
					; flags byte is what says so
		extrn errlrsp		; the response file will not
					; open, or "@" named nothing
		extrn errlnest		; a response file holds an "@"
		extrn errltwo		; a second "@FILE" on one command
					; line. One list, and it may not
					; name another: the objects named
					; in each are looked for in its own
					; directory, and only one of those
					; is remembered
		extrn errlargs		; more words, or a longer word,
					; than the list holds
		extrn errlenv		; the TANREN variable is too long
		extrn errlout		; the output file cannot be
					; created
		extrn errlwrt		; or cannot be written to
		extrn errlover		; the output file is one of the
					; input files
		extrn errlmext		; more externals in one module
					; than its map holds
		extrn errlsflg		; a segment was declared with
					; different flags in another module -
					; the format document calls this a
					; link error
		endif
