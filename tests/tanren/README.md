# The linker's tests

13 sources and 50 checks, run by one script.

```
tests
```

`TESTS.BAT` builds its own objects with Tatara first - the pair of
tools is what is being tested, so the objects are not borrowed from
the assembler's suite - and then links them in every way the linker
offers, appending everything to `RESULTS.TXT` with an `=== NAME`
marker before each block.

## What it covers

Reading object files, and refusing files that are not ones. Segments
across modules: concatenation, groups, transient segments overlaid,
and the largest-of-them rule. Publics and externals, duplicate
definitions and undefined ones. Fixups, entry points and absolute
content. The image: `/P:` and `/D:` origins, overlapping spans, `/B`
for a BLOAD header, and output that is not a `.COM`. Response files -
composing with the command line, nesting refused, and objects found
beside the list. The object search and its environment variable.

`OBJS/` holds two objects copied into a subdirectory by the run, so
that a file list can be found somewhere other than the current
directory.

## Adding a test

As for the assembler's suite: a source if it needs one, two lines in
`TESTS.BAT`, and no apostrophes or quotes in the marker.
