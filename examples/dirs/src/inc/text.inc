; SRC\INC\TEXT.INC - reached as inc\text.inc from SRC\MAIN.AS, so
; rule 1 found it: a name with a separator in it is still relative to
; the file that asked for it.
;
; The include below has no directory at all, and rule 1 finds it
; beside THIS file rather than beside MAIN.AS.

		include	msg.inc

text:		db	"Rule 1: beside the file that asked.",13,10,"$"
