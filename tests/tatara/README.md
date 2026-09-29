# The assembler's tests

202 sources and 266 checks, run by one script.

```
tests
```

`TESTS.BAT` assembles each source in turn and appends everything to
`RESULTS.TXT`, with an `=== NAME` marker before each block saying what
the test is and what it should produce. It uses MSX-DOS redirection
rather than Tatara's own output file on purpose: error messages go to
the screen through BDOS `_STROUT` and never reach the file Tatara
writes, and a good half of these tests *are* error messages.

Most of the suite is read by comparing one run against the last. The
previous `RESULTS.TXT` is kept as `RESULTS.OLD` for exactly that.

## What it covers

Conditionals and nested conditionals. Macros - definition, expansion,
parameters, `LOCAL`, `REPT`, `IRP`, `IRPC`, nesting and recursion.
Expressions, operator precedence, character constants and forward
references. The symbol table, long names and case folding. Segments:
`ASEG`, `CSEG`, `DSEG`, named segments, groups and transient segments.
The instruction table and every addressing form. Listings: pagination,
`TITLE`, `SUBTTL`, `.LIST`/`.XLIST` and macro-expansion modes. Object
output, and the include search with its environment variable. Public
symbols, by the directive and by the second colon. Where a
label may sit: column 1 with the colon optional, indented with the
colon required.

Many tests are deliberately wrong programs: the expectation in the
marker line is an error message and its position.

## m80ref

Fifty of the tests are cross-checked against Microsoft's M80. Its
listings are frozen in `m80ref/` and printed into `RESULTS.TXT` beside
Tatara's own, so that `cmpm80.py` can compare address, relocation mark
and bytes for every line that emitted any. That is the only
independent check that this assembler emits the right bytes -
everything else here is Tatara agreeing with itself. See
`m80ref/README.md`.

## Adding a test

Write the source, add two lines to `TESTS.BAT` - an `echo === ` marker
saying what to expect, and the command - and keep the marker free of
apostrophes, quotes, `<` and `>`. MSX-DOS's `ECHO` eats the first two
and obeys the last two.
