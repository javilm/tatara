rem BUILD.BAT - EXAMPLE: DIRS
rem
rem Sources in SRC, headers beside them in SRC\INC, shared headers in
rem LIB. The build runs from HERE and nothing is copied anywhere.
rem
rem TATARA holds the directories rule 3 looks in - the same idea as
rem PATH, and the same shape: several may be separated by semicolons.
rem It is set for the build and cleared afterwards so that nothing
rem outside this example inherits it.
rem
rem THE PATH BELOW IS ABSOLUTE and names this example. MSX-DOS gives a
rem batch file no way to ask where it is, so change this line if you
rem put the tree somewhere else.
rem
rem Under MSX-DOS 1 there are no environment variables, and rules 1
rem and 2 are all there is. Move LIB\SYSMSG.INC and MSXDOS.INC in
rem beside MAIN.AS and the example builds there too.

set TATARA=a:\tatara\include;a:\tatara\examples\dirs\lib

echo === Assembling SRC\MAIN.AS
tatara /q src\main.as dirs.tro

echo === Linking
tanren /q /o:dirs.com dirs.tro

set TATARA=

echo === Done. Type DIRS to run it.
