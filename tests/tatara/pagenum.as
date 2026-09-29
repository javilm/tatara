; pagenum.as - issue #17: a form feed in the source starts a new page
; and defines nothing. It also moves the MAIN page number, which the
; PAGE directive does not - the PAGE below gives 2-1 and not 1-1.
;
; The second TITLE is here to show what does NOT happen: M80 starts no
; page for it. CROSS-CHECKED - the four db lines emit bytes, and
; m80ref/pagenum.prn is M80's listing of the same program.
;
; THE FIFTH LINE BELOW IS A SINGLE 0Ch BYTE.

		title	First title
		cseg
		db	1

		db	2
		title	Second title
		db	3
		page
		db	4
		end
