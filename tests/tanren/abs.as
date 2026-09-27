; absolute content, which decision 8 now says is WRITTEN WHERE
; IT SAYS. A cartridge driver loads at 4000h and no .COM can hold it,
; so the file is five bytes that start there - and the summary says
; 4000-4004 and not 0100.
	aseg
	org	04000h
	defb	"ROM",13,10
	end
