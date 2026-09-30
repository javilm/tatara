; twocode.as - two CODE segments in one module: the default one and a
; named one. This is issue #24's shape, and the reason it matters.
;
; A .COM is entered at 0100h whatever the object file says, so whichever
; code segment is placed first is the one that RUNS. Until 094 that was
; decided by the hash of the segment names, and renaming EXTRA could
; have changed which byte the machine executed first.
;
; Expect C at 0100h and EXTRA after it, because the assembler makes the
; classic segments before it reads a line and writes its SEGDEFs in
; index order - so the default one arrives first and is placed first.

		cseg
		db	1

		cseg	extra
		db	2

		end
