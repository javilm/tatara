; SRC\INC\MSG.INC - a bare name, included from TEXT.INC, which lives
; in this directory.
;
; IF THE SEARCH STARTED IN THE CURRENT DIRECTORY, THIS WOULD NOT BE
; FOUND: the build runs two levels up, and there is no MSG.INC there.

deeper:		db	"Rule 1 again, one level deeper.",13,10,"$"
