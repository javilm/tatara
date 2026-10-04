rem BUILD.BAT - assemble and link both tools, with Tatara.

rem SILENCE IS SUCCESS. /Q prints nothing for a module that works and
rem errors print anyway, so anything on the screen between the ===
rem lines is a problem.

set TATARA=shared\


echo === Assembling TATARA modules...
tatara /q tatara\tatara.as tatara.tro
tatara /q tatara\cmdline.as cmdline.tro
tatara /q tatara\srcline.as srcline.tro
tatara /q tatara\fields.as fields.tro
tatara /q tatara\dirtab.as dirtab.tro
tatara /q tatara\macros.as macros.tro
tatara /q tatara\errs.as errs.tro
tatara /q tatara\expand.as expand.tro
tatara /q tatara\cond.as cond.tro
tatara /q tatara\expr.as expr.tro
tatara /q tatara\symtab.as symtab.tro
tatara /q tatara\optab.as optab.tro
tatara /q tatara\insn.as insn.tro
tatara /q tatara\emit.as emit.tro
tatara /q tatara\objout.as objout.tro

echo === Assembling TANREN modules...
tatara /q tanren\tanren.as tanren.tro
tatara /q tanren\lcmd.as lcmd.tro
tatara /q tanren\lobj.as lobj.tro
tatara /q tanren\lseg.as lseg.tro
tatara /q tanren\lsym.as lsym.tro
tatara /q tanren\lerrs.as lerrs.tro
tatara /q tanren\limg.as limg.tro
tatara /q tanren\arglist.as arglist.tro

echo === Assembling shared modules...
tatara /q shared\msxdos.as msxdos.tro
tatara /q shared\strutil.as strutil.tro
tatara /q shared\alloc.as alloc.tro
tatara /q shared\hash.as hash.tro

echo === Linking TATARA and TANREN binaries
tanren /o:build\tatara.com @tatara.lnk
tanren /o:build\tanren.com @tanren.lnk

echo === Cleaning up
del *.tro

echo === Copying binaries to A:\TATARA\BIN\
copy build\*.com a:\tatara\bin
