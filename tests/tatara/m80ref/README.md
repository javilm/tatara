# m80ref

Fifty-one listing files, one per test that is cross-checked against
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