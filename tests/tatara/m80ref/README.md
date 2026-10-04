# m80ref

Fifty-two listing files, one per test that is cross-checked against
Microsoft's M80.

`TESTS.BAT` prints each of these into `RESULTS.TXT` beside Tatara's
own `/L` listing of the same source, and `cmpm80.py` compares the two
line by line: the address, its relocation mark, and the byte sequence.
It is the only independent check that this assembler emits the right
bytes — everything else in the suite is Tatara agreeing with itself.

These are frozen copies of what M80 produced. M80 never changes, so a
snapshot of its answer is as good an oracle as the program, and it
works on a machine that has never had a copy — which matters, because
M80 is Microsoft's and cannot be distributed with this.

Nothing regenerates them. If a test's source changes, its reference
here no longer describes it and has to be replaced by hand, with M80.


## The comments in these are one rename behind

Note 157 swept `repo/tests/` against the finished `naming-map.md` and changed
twenty-one comments in sixteen test sources, which named routines of the
assembler by names the rename sequence had replaced. The references here still
show the old text, because nothing regenerates them.

That is harmless. `cmpm80.py` collects only the lines that produced bytes —
the address, its relocation mark and the byte sequence — so a comment never
enters either side of the comparison. 157 kept the line count of every source
unchanged all the same, because `parse()` stops at the first form feed and a
comment line more or fewer could move a page break; `ifcase.prn` and
`pagenum.prn` are the only two references that hold one.

A reference regenerated here in future will simply pick the new comment text
up, and nothing has to be done about the ones that were not.
