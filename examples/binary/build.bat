rem BUILD.BAT - EXAMPLE: BINARY
rem
rem A .BIN for MSX BASIC instead of a .COM for MSX-DOS. Two things
rem make the difference:
rem
rem   ASEG and ORG   the code is at a fixed address, not relocatable
rem   TANREN /B      the seven-byte BLOAD header goes in front of it
rem
rem The address BASIC calls is the one on the END line of the source.
rem Without /B the same link writes the bytes and no header, which is
rem what a ROM needs - see the ROM example.
rem
rem To run it, from BASIC:  BLOAD then the file name in quotes, ,R

rem The headers are in A:\TATARA\INCLUDE and are not copied here.
rem TATARA is rule 3 of the include search - see the DIRS example.
rem CHANGE THE PATH BELOW if you put the tree somewhere else.

set TATARA=a:\tatara\include

echo === Assembling
tatara /q beep.as beep.tro

echo === Linking, with a BLOAD header
tanren /q /b /o:beep.bin beep.tro

echo === Done. BEEP.BIN is 7 bytes of header and the rest is code.

set TATARA=
