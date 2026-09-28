; MACROS.AS - a line that becomes many.
;
; MACRO defines one, ENDM ends the definition, and the name is then
; used like a mnemonic. LOCAL, REPT and IRP are below.

		include	msxdos.inc	; BDOS, _STROUT, _TERM0 and "system"

; PRINT - three instructions from one line. The parameter is
; substituted wherever the name appears in the body.

print		macro	addr
		ld	de,addr
		system	_STROUT	; a macro inside a macro
		endm

; DELAY - and why LOCAL exists. The body has a label in it, and a
; macro used twice would define that label twice. LOCAL makes a fresh
; name for each expansion, so this may be used as often as you like.

delay		macro	n
		local	loop
		ld	bc,n
loop:		dec	bc
		ld	a,b
		or	c
		jr	nz,loop
		endm

		cseg

start:		print	msg1
		delay	20000
		print	msg2
		delay	20000
		ld	c,_TERM0
		jp	BDOS

msg1:		db	"A macro is a line that becomes many.",13,10,"$"
msg2:		db	"LOCAL is why DELAY can be used twice.",13,10,"$"

; REPT repeats a body a counted number of times, with no parameter.
; Neither it nor IRP takes a label: the body is what produces the
; bytes, and a label belongs on a line inside it.

		rept	8
		db	0ffh
		endm

; IRP repeats it once for each item in the list, and IRPC once for
; each character of a word. INSIDE A STRING the parameter is only
; substituted if an ampersand is put in front of it, which is how M80
; tells a parameter from two letters that happen to match.

		irp	n,<1,2,4,8>
		db	n
		endm

		irpc	c,TATARA
		db	'&c'
		endm
		db	0

		end	start
