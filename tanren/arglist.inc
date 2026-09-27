; arglist.inc - public interface of arglist.as: the words a program
; was asked to work on.
;
; THE LAYER BELOW A COMMAND-LINE PARSER, and the reason it is its own
; module: cmdline.as and lcmd.as are deliberately not shared, because
; the two programs take different switches - but SPLITTING a command
; tail into words, and reading those words out of a file instead, is
; the same job for both. [R10] asks for exactly this: "the
; file-reading should be written once and shared, the way alloc.as,
; hash.as and the command-tail parser already are".
;
; Nothing here knows what a word MEANS. A "/" is not a switch here,
; it is a character.

		ifndef	ARGLIB

		extrn argtail		; the command tail, split into
					; words, with any @FILE expanded
					; where it stands
					; (errlheap, errlargs, errlrsp,
					; errlnest do not return)
		extrn argfile		; one response file's words,
					; appended to the list
					; in:  argfn = its name, ASCIIZ
		extrn argadd		; one word, appended
					; in:  DE -> the word, ASCIIZ
		extrn argfrst		; start walking the list
		extrn argnext		; the next word
					; in:  DE -> where it goes
					; out: CY set = there are no more
		extrn argn		; how many words the list holds
					; (a WORD)
		extrn argcut		; 0FFh = the command tail was
					; exactly 127 characters long and
					; MAY have been truncated
		extrn argfn		; the response file being read,
					; for the error that names it
		extrn argrdir		; the directory that file lives in,
					; ASCIIZ - empty if there was none,
					; or it named no directory
		extrn argfrf		; 0FFh = the word argnext just
					; handed out came from it
		endif

ARGSIZE		equ	4096	; the block the words live in. A link of
				; eighteen modules with fourteen-character
				; names is under three hundred bytes, so
				; this is room for ten of them - and it is
				; mapper memory, where the image already
				; takes four times as much
ARGMAX		equ	129	; the longest single word: LMAXPATH and
				; its terminator
ARGBUFS		equ	128	; the response file is read in chunks of
				; this, which is a sector's worth and one
				; BDOS call per 128 characters instead of
				; one per character
ARGAT		equ	"@"	; what makes a word a response file,
ARGCOM		equ	";"	;   and what starts a comment in one
