; pubcc.as - "name::" declares the name PUBLIC.
;
; THE PAIR IS THE TEST. One colon and two, side by side, so the dump
; says which of them did it. IND is indented, which 082 made a label
; and which must carry the flag too. An EQU cannot carry it at all -
; see COLNEQ.AS.

one:		ld	a,1		; one colon: a label, nothing more
two::		ld	a,2		; two colons: PUBLIC
	ind::	ld	a,3		; indented, and PUBLIC
		end
