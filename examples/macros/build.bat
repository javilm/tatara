rem BUILD.BAT - EXAMPLE: MACROS
rem
rem The listing is the example here. /L writes one, and the file it
rem goes to is named THIRD on the command line, after the source and
rem the object.
rem
rem A listing shows the bytes a line produced, and a line that came
rem out of a macro is marked with a +. HOW MUCH of an expansion is
rem listed is a choice, and the source makes it three times:
rem
rem   .LALL   every line of every expansion
rem   .XALL   only the lines that produced bytes (the default)
rem   .SALL   none of them, only the call
rem
rem It is assembled twice, to two listings, so the two can be read
rem side by side.

echo === Assembling, listing under the default XALL
tatara /q /l macros.as macros.tro macxall.lst

echo === Assembling again, listing everything
tatara /q /l lall.as lall.tro maclall.lst

echo === Linking
tanren /q /o:macros.com macros.tro

echo === Done. Compare MACXALL.LST with MACLALL.LST, then type MACROS.
