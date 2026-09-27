; TESTS\TATARA\INCENV.AS - Assembled TWICE: once with TATARA unset,
; where it must fail to find IENV.INC, and once with TATARA naming
; TESTS\TATARA\LIB, where it must find it.
;
; THE PAIR IS THE TEST. A success on its own would not say what
; found the file.
		include	ienv.inc
		end
