rem BUILD.BAT - EXAMPLE: ROM
rem
rem A 16 KB cartridge image. No MSX-DOS anywhere in it: the code runs
rem from a cartridge slot before there is an operating system, so it
rem calls the BIOS and never returns.
rem
rem   ASEG and ORG 4000h   page 1, where a 16 KB cartridge lives
rem   no /B                a ROM has no header of any kind
rem   ORG 7FFFH and DB 0   what makes the file exactly 16384 bytes
rem
rem THIS IS THE ONE EXAMPLE A SUCCESSFUL BUILD DOES NOT PROVE. Load
rem ROM.ROM as a cartridge in an emulator, or write it to a flash
rem cartridge. It is not a program whose name you can type.

rem The headers are in A:\TATARA\INCLUDE and are not copied here.
rem TATARA is rule 3 of the include search - see the DIRS example.
rem CHANGE THE PATH BELOW if you put the tree somewhere else.

set TATARA=a:\tatara\include

echo === Assembling
tatara /q rom.as rom.tro

echo === Linking, with no header of any kind
tanren /q /o:rom.rom rom.tro

echo === Done. ROM.ROM should be exactly 16384 bytes.

set TATARA=
