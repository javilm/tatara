; lateent.as - the entry point is not the first byte of the image.
;
; Three bytes of data, then the code, then END naming the code. The
; linked image begins at 0100h and MSX-DOS would enter it there, in
; the middle of the DB - which is 097's warning and was examples/dirs
; before it was fixed.

		cseg
		db	1,2,3

start:		ret

		end	start
