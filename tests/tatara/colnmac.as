; colnmac.as - MACRO takes a name, not a label. M80 error O, and M80
; does not open the macro: its ENDM gets an O of its own.

foo:		macro
		endm
		end
