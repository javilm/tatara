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

		ifndef	ARGLIST_INCLUDED

		extrn split_command_tail	; the command tail, split into
					; words, with any @FILE expanded
					; where it stands
					; (error_out_of_memory,
					; error_too_many_words,
					; error_cannot_open_list,
					; error_nested_file_list
					; do not return)
		extrn read_response_file	; one response file's words,
					; appended to the list
					; in:  response_file_name = its
					;      name, ASCIIZ
		extrn arglist_add	; one word, appended
					; in:  DE -> the word, ASCIIZ
		extrn arglist_first	; start walking the list
		extrn arglist_next	; the next word
					; in:  DE -> where it goes
					; out: CY set = there are no more
		extrn arglist_count	; how many words the list holds
					; (a WORD)
		extrn tail_truncated	; 0FFh = the command tail was
					; exactly 127 characters long and
					; MAY have been truncated
		extrn response_file_name	; the response file being read,
					; for the error that names it
		extrn response_file_directory
					; the directory that file lives in,
					; ASCIIZ - empty if there was none,
					; or it named no directory
		extrn word_from_file	; 0FFh = the word arglist_next just
					; handed out came from it
		endif

ARGLIST_BLOCK_SIZE	equ	4096	; the block the words live in.
					; A link of eighteen modules with
					; fourteen-character names is under
					; three hundred bytes, so this is
					; room for ten of them - and it is
					; mapper memory, where the image
					; already takes four times as much
ARGLIST_WORD_MAX	equ	129	; the longest single word: PATH_MAX
					; and its terminator
RESPONSE_CHUNK_SIZE	equ	128	; the response file is read in
					; chunks of this, which is a
					; sector's worth and one BDOS call
					; per 128 characters instead of one
					; per character
RESPONSE_FILE_CHAR	equ	"@"	; what makes a word a response file,
RESPONSE_COMMENT_CHAR	equ	";"	;   and what starts a comment in one
