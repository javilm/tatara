rem BUILD.BAT - EXAMPLE: NAMES
rem
rem One source, assembled twice, and the two symbol tables are the
rem answer.
rem
rem   /S   print the symbol table when the assembly ends
rem   /P   assemble to the screen, producing no object file
rem   /C   make symbol and macro names case-SENSITIVE
rem
rem Without /C, Counter and counter are one symbol whose value ends up
rem 2, and the table has one entry. With /C they are two symbols, 1
rem and 2, and the table has both. The default is M80s behaviour.
rem
rem The two long names are 48 characters each and differ in the last
rem five. M80 would have made them one symbol.

echo === Case-insensitive, which is the default
tatara /q /p /s names.as > insens.txt

echo === Case-sensitive
tatara /q /p /c /s names.as > sens.txt

echo === Done. Compare INSENS.TXT with SENS.TXT.
