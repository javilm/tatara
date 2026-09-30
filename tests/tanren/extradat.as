; extradat.as - EXTRA as a data segment, where twocode.as makes it a
; code segment. Linking the two is issue #26's segment error, and the
; point of the test is what the message SAYS: the file it happened in
; and the name of the segment it happened to.

		dseg	extra
		db	9

		end
