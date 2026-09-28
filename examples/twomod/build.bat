rem BUILD.BAT - EXAMPLE: TWOMOD
rem
rem Two modules, one program. MAIN.AS declares putstr EXTRN and
rem PUTSTR.AS declares it PUBLIC; the linker matches the two.
rem
rem The link itself is in TWOMOD.LNK rather than on this line. @NAME
rem reads a file of words, and .LNK is assumed when the name has no
rem extension. Everything in it could have been typed here instead.

rem The headers are in A:\TATARA\INCLUDE and are not copied here.
rem TATARA is rule 3 of the include search - see the DIRS example.
rem CHANGE THE PATH BELOW if you put the tree somewhere else.

set TATARA=a:\tatara\include

echo === Assembling both modules
tatara /q main.as main.tro
tatara /q putstr.as putstr.tro

echo === Linking from TWOMOD.LNK
tanren /q @twomod

echo === Done. Type TWOMOD to run it.

set TATARA=
