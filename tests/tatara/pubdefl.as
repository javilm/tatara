; pubdefl.as - issue #18: PUBLIC and DEFL together fill the /S type
; column exactly, and the name used to start with no space in front of
; it. Expect "public var" then a space then LEVEL, with TMP's name
; starting in the same column.

		public	level
level		defl	2
tmp		defl	3
		end
