rem BUILD.BAT - EXAMPLE: LAYOUT
rem
rem This example is about the two maps it writes, not about the
rem program, which only prints a line.
rem
rem   TATARA /S   the symbol table: every name, by segment, with its
rem               offset inside that segment
rem   TANREN /M   the segment and group tables: where each segment
rem               ended up, how big it is, and which groups share it
rem
rem It links twice. The first is an ordinary .COM at 0100h. The second
rem puts the code at 8000h and the data at C000h - a real MSX layout,
rem code in the top pages with its variables above it, and not
rem something MSX-DOS can run as a command, so it goes to a .BIN that
rem nobody is asked to run.

echo === Assembling, keeping the symbol table
tatara /q /s layout.as layout.tro > layout.sym

echo === Linking at 0100h, keeping the map
tanren /q /m /o:layout.com layout.tro > layout.map

echo === Linking again, code at 8000h and data at C000h
tanren /q /m /o:layout8.bin /p:8000 /d:c000 layout.tro > layout8.map

echo === Done. Read LAYOUT.SYM, LAYOUT.MAP and LAYOUT8.MAP.
