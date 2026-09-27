; LIB\SYSMSG.INC - not beside MAIN.AS, and not in the directory the
; build runs from. BUILD.BAT puts this directory in TATARA, which is
; rule 3, and that is how a project keeps its shared headers in one
; place instead of a copy per program.

sysmsg:		db	"Rule 3: found through TATARA.",13,10,"$"
