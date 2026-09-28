rem BUILD.BAT - EXAMPLE: HELLO
rem
rem The whole cycle in two commands:
rem
rem   tatara source object    assembles one file
rem   tanren /o:file object   links one or more objects
rem
rem /Q keeps both tools quiet. An error is printed whether or not /Q
rem was given, so a silent run is a successful one.

rem The headers are in A:\TATARA\INCLUDE and are not copied here.
rem TATARA is rule 3 of the include search - see the DIRS example.
rem CHANGE THE PATH BELOW if you put the tree somewhere else.

set TATARA=a:\tatara\include

echo === Assembling
tatara /q hello.as hello.tro

echo === Linking
tanren /q /o:hello.com hello.tro

echo === Done. Type HELLO to run it.

set TATARA=
TARA=
