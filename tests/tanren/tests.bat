rem TESTS.BAT - TANREN's tests. Separate from the assembler's, which
rem has 208 files and 4,400 lines of results of its own.
rem
rem The objects are built HERE, by TATARA, rather than borrowed from
rem the other directory: the pair of tools is what is being tested.

if exist results.txt copy results.txt results.old

echo TANREN TEST RUN > results.txt

echo === THE BANNER (no /Q, so it prints) >> results.txt
tanren /? >> results.txt
echo === /V >> results.txt
tanren /v >> results.txt

echo === Building the objects with TATARA >> results.txt
tatara /q small.as small.tro
tatara /q two.as two.tro

echo === SMALL.TRO (expect 5 records, ends at EOF) >> results.txt
tanren /q /r small.tro >> results.txt
echo === TWO.TRO (segments, a public, an external, a fixup) >> results.txt
tanren /q /r two.tro >> results.txt
echo === TWO.TRO without /D (expect the count alone) >> results.txt
tanren two.tro >> results.txt

echo === NOTOBJ.AS as an object file (expect: not a Tatara object) >> results.txt
tanren /q notobj.as >> results.txt
echo === MISSING.TRO (expect: cannot open) >> results.txt
tanren /q missing.tro >> results.txt

echo === THREE MODULES, one table (expect CODE summed) >> results.txt
tatara /q a.as a.tro
tatara /q b.as b.tro
tatara /q c.as c.tro
tanren /q /m a.tro b.tro c.tro >> results.txt
echo === THE SAME THREE with /D as well >> results.txt
tanren /q /r /m a.tro b.tro c.tro >> results.txt
echo === ONE OF THEM TWICE (expect its segments counted twice) >> results.txt
tanren /q /m a.tro a.tro >> results.txt
echo === NO EXTENSIONS (expect the same table as the first one) >> results.txt
tanren /q /m a b c >> results.txt
echo === MISSING, NO EXTENSION (expect the name it tried) >> results.txt
tanren /q missing >> results.txt

echo === SYMBOLS across a and b (expect astart D-, bstart DR) >> results.txt
tanren /q /m a.tro b.tro >> results.txt
echo === THE OTHER ORDER (expect the same two symbols) >> results.txt
tanren /q /m b.tro a.tro >> results.txt
echo === D.AS ALONE (expect BOTH names under Never defined) >> results.txt
tatara /q d.as d.tro
tanren /q /m d.tro >> results.txt
echo === A AND E (expect astart defined twice, naming module e) >> results.txt
tatara /q e.as e.tro
tanren /q a.tro e.tro >> results.txt

echo === THE MAP with addresses (expect C at 0100, D after it) >> results.txt
tanren /q /m a.tro b.tro c.tro >> results.txt
echo === THREE GROUPS OF ONE SEGMENT (expect size 0014, one base) >> results.txt
tatara /q f.as f.tro
tanren /q /m f.tro >> results.txt

echo === TATARA.TRO - the biggest object we have >> results.txt
rem IT IS NAMED BY A PATH. The comment that stood here
rem said an INCLUDE is opened relative to the current directory, so
rem this had to cd into the source directory and back again. That
rem is no longer true: the includes beside
rem the source are found by its own directory, and the shared ones
rem through TATARA.
set TATARA=a:\tatara\repo\shared
tatara /q ..\..\tatara\tatara.as tatara.tro
set TATARA=
tanren tatara.tro >> results.txt

echo === NO /O (expect A.COM, 0100-0109, 10 bytes) >> results.txt
tanren a.tro b.tro >> results.txt
echo === THE OUTPUT AS AN INPUT (expect: also an input file) >> results.txt
tanren /q /o:a.tro a.tro b.tro >> results.txt

echo === ABSOLUTE CONTENT (expect 4000-4004, 5 bytes) >> results.txt
tatara /q abs.as abs.tro
tanren /o:absraw.bin abs.tro >> results.txt
echo === AND ITS FIVE BYTES (expect ROM) >> results.txt
type absraw.bin >> results.txt
echo === /B AND NO /O (expect ABS.BIN, BLOAD header, entry 4000) >> results.txt
tanren /b abs.tro >> results.txt
echo === BOTH ON DISK (expect 5 bytes raw and 12 with header) >> results.txt
dir abs*.bin >> results.txt

echo === THE SPEC EXAMPLE (expect 0100-010F, entry 0100) >> results.txt
tatara /q putstr.as putstr.tro
tanren /o:hello.com two.tro putstr.tro >> results.txt
echo === THE FIXUPS THAT ARE EASY TO GET WRONG >> results.txt
tatara /q ok.as ok.tro
tatara /q second.as second.tro
tanren /o:ok.com ok.tro second.tro putstr.tro >> results.txt
echo === RUNNING BOTH (expect Hi then OK DONE, no newlines) >> results.txt
hello >> results.txt
ok >> results.txt

echo === A RESPONSE FILE (expect 3 modules, 0100-0121) >> results.txt
tanren /o:okr.com @ok.lnk >> results.txt
echo === AND IT COMPOSES WITH SWITCHES (expect a map too) >> results.txt
tanren /q /m /o:okr.com @ok.lnk >> results.txt
echo === NO EXTENSION ON THE LIST (expect the same again) >> results.txt
tanren /q /m /o:okr.com @ok >> results.txt
echo === WORDS BEFORE AND AFTER IT (expect 4 modules) >> results.txt
tanren /q /m /o:mix.com a.tro @ok.lnk >> results.txt
echo === A LIST NAMING ANOTHER (expect: may not name another) >> results.txt
tanren /q @nest.lnk >> results.txt
echo === A LIST THAT IS NOT THERE (expect: cannot open) >> results.txt
tanren /q @nosuch >> results.txt

echo === /P: (expect C at 4000, D after it) >> results.txt
tanren /q /m /o:p.bin /p:4000 a.tro b.tro >> results.txt
echo === /P: AND /D: (expect C at 4000, D at 5000) >> results.txt
tanren /q /m /o:pd.bin /p:4000 /d:5000 a.tro b.tro >> results.txt
echo === /D: ALONE (expect C at 0100, D at 0200) >> results.txt
tanren /q /m /o:d.bin /d:0200 a.tro b.tro >> results.txt
echo === DATA BELOW CODE (expect C at 4000, D at 2000) >> results.txt
tanren /q /m /o:db.bin /p:4000 /d:2000 a.tro b.tro >> results.txt
echo === THEM OVERLAPPING (expect: on top of the code) >> results.txt
tanren /q /o:x.bin /p:4000 /d:4000 a.tro b.tro >> results.txt
echo === A BAD ADDRESS (expect: unknown option) >> results.txt
tanren /q /o:x.bin /p:zzzz a.tro b.tro >> results.txt
echo === FIVE DIGITS (expect: unknown option) >> results.txt
tanren /q /o:x.bin /p:12345 a.tro b.tro >> results.txt
echo === /D WITH NO COLON (expect: unknown option) >> results.txt
tanren /q /o:x.bin /d a.tro b.tro >> results.txt
echo === /P:0100 IS THE DEFAULT (expect the HELLO.COM numbers) >> results.txt
tanren /o:p100.com /p:0100 two.tro putstr.tro >> results.txt

echo === Copying two objects into a subdirectory >> results.txt
copy a.tro objs\suba.tro
copy b.tro objs\subb.tro

echo === A LIST BESIDE ITS OBJECTS (expect 2 modules) >> results.txt
tanren /q /m /o:sub.com @objs\sub.lnk >> results.txt
echo === THE SAME TWO, TANREN unset (expect: cannot open) >> results.txt
set TANREN=
tanren /q /o:env.com suba.tro subb.tro >> results.txt
echo === AND WITH TANREN set (expect 2 modules) >> results.txt
set TANREN=a:\tatara\repo\tests\tanren\objs
tanren /q /m /o:env.com suba.tro subb.tro >> results.txt
set TANREN=

echo === END OF RUN >> results.txt
