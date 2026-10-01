# Changelog

Tatara and Tanren. Newest first.

## v1.1.7 - 2026-10-02

- A column-1 word beginning with `*` or `$` is a **control line**, which
  is what M80 makes of one. `*EJECT` and `$EJECT` are the two this
  assembler has; any other stops with `only *EJECT and its dollar
  spelling are control lines`. `*TITLE` and `$TITLE` are M80's spelling
  of `SUBTTL` and are not accepted: the title text holds a space, so
  the line is cut into fields before anything could read it - **write
  `SUBTTL`**. Before this, `$title('Dollar title')` was refused for
  holding characters a name may not, which was true of the line and no
  help to its author.
- A label may hold only the characters a name may hold - letters,
  digits and `? @ . _ $`. `foo*bar` was accepted and entered in the
  symbol table, where nothing could ever refer to it: an expression's
  name stops at the `*`. M80 answers such a line with a `U` and one
  fatal error.
- `*EJECT` and `$EJECT` in column 1 are accepted as `PAGE`, which is
  what M80 does with them. The other starred controls are not followed:
  `*TITLE` needs an operand syntax of its own, and `*LIST` and
  `*INCLUDE` are not M80 controls at all.
- **A semicolon can be passed to a macro**, as `!;` or inside `<...>`,
  which is what M80 does with both. The macro expander always
  understood them; the line was cut into fields at the semicolon before
  it ever saw them, so `m a!;b` passed `a`.
- A label on a `PUBLIC`, `EXTRN`, `INCLUDE` or `EXITM` line is now
  defined, with the location counter, instead of being dropped in
  silence. M80 defines it on all of these - it was asked - and 088's
  rule already said it should: *a label on a line that emits no bytes
  takes the location counter, if that line is being assembled*. A label
  on a `LOCAL` or an `ENDM` line is still dropped, and that is correct
  and matches M80: those lines are read while a macro body is collected
  and are never assembled.
- Tanren warns when **the entry point is not the first byte of the
  image**: `WARNING: NAME.COM is entered at 0100, not at 0168.` MSX-DOS
  loads a `.COM` at its start address and jumps there, so a program
  whose first bytes are data runs the data; the address `END` names
  reaches the object file and the summary and nothing else reads it.
  The warning is printed **before the summary, so `/Q` does not hide
  it** - a build file is exactly where this goes unnoticed. Nothing is
  said when `/B` was given, because a BLOAD header carries an
  execution address and BASIC obeys it, nor when no module named an
  entry point at all.
- `examples/dirs`: `SRC\MAIN.AS` included its two message headers
  before `CSEG`, so `DIRS.COM` began with 104 bytes of text and was
  entered in the middle of it - it printed nothing from `A:` and froze
  the machine from anywhere else. The two includes are now below the
  code, where every other example already keeps its messages, and the
  file says why.

## v1.1.6 - 2026-10-01

- Tanren names the object file in the five errors it can raise while
  reading one: `NAME.TRO: ERROR: ...`, the way Tatara names the source
  file and line. The segment error also names the segment. The errors
  raised after every file is closed are unchanged, because by then
  there is no file to name.
- Tanren reports **bytes after the END record in any module**, not only
  in the last one read, and prints the name of each module they were
  found in. The summary flag was stored rather than accumulated, so a
  link whose last file ended cleanly said `ends at EOF.` however many
  of the others had not.
- Tanren's `/M` no longer prints the empty record a transient segment
  has outside every group. A transient `DSEG`'s memory belongs to its
  groups, and nothing may be placed in one before its first `GROUP`
  line, so that record is always empty: it was listed with no size and
  no end address among the records that have both. The record itself
  is unchanged and so are every segment's addresses - only the map is
  different. `/D`, which dumps what the object file holds, still shows
  it.
- Tanren places segments of a kind **in the order they first appear**,
  which for the default `CSEG` and `DSEG` means first of all. The order
  used to come from the segment table's hash, so it followed the
  segment NAMES: renaming a segment could move it, and since a `.COM`
  is entered at 0100h whatever the object file says, renaming a code
  segment could change which code ran first. `/M` now prints the
  segments in the order they were placed rather than in the table's.
- Tanren accepts **one** `@FILE` list on a command line, and reports
  `only one file list may be given` for a second. Two were accepted
  before, and every word of both was read - but only one file's
  directory was remembered, so the objects named in the first were
  looked for in the second's directory and usually not found. A list
  still composes with names typed on the line, and still may not name
  another list.
- An error on the second pass no longer leaves a partial object file
  behind. The file is created when the first pass ends, so an error
  after that left one with the right name, a current timestamp and part
  of its content - and the object file it replaced was already gone.
  Nothing about such a file says it is unusable, and a batch file would
  hand it straight to Tanren. It is now closed and deleted. **An error
  before the file was created still leaves an earlier file of that name
  untouched**, which is the reason the object file is created at the end
  of pass 1 in the first place. The listing file is left as it is: it
  records how far the assembly got.
- The listing's last page marks an external with `*` and shows `0000`
  instead of the external's position in the module's import table. That
  position was printed where a value goes and with no mark at all, so
  `exit` and `print` read as absolute symbols worth 0 and 1. M80 prints
  the address of the external's last use with the star; Tatara does not
  keep that address, and `0000*` at least cannot be mistaken for a
  value. The `/S` table was already right - it gives externals a
  section of their own with no number.
- `/S` puts a space between the type and the name when both `PUBLIC`
  and `DEFL` apply to it. The type column was ten characters and
  `public var` is ten characters, so the name ran straight on. All four
  types are now eleven wide, which also lines these names up with the
  sections that have no address column.
- `/F` no longer lists macro definitions when `/P` is given as well.
  `/F` replaces each line's listing with its field dump, but the
  routine that lists a macro's own lines never tested for it, so the
  definition appeared under a page heading in the middle of the dump.
- A form feed in the source starts a new page in the listing, as it
  does in M80, instead of being taken for a label. A line holding
  nothing but a form feed was given the location counter and entered in
  the symbol table under the name `^L`; it now breaks the page, moves
  the MAIN page number - which the `PAGE` directive does not, so a
  `PAGE` after a form feed reads `2-1` - and lists as an empty line at
  the top of the page it opens.
- `IFIDN` and `IFDIF` now compare their two arguments exactly, case
  included, which is what M80 does. They folded both sides to upper
  case before, so `IFIDN <abc>,<ABC>` was true and the matching `IFDIF`
  was false - both the wrong way round. This is unrelated to `/C`,
  which makes NAMES case-sensitive: these two compare text, not names,
  and the old behaviour was wrong in both modes. A macro's dummy
  parameter is a name and is still matched ignoring case, which is also
  what M80 does.

## v1.1.5 - 2026-09-29

- An error inside an included file now prints the chain that led to it:
  one `included from FILE(line)` for each file above it, innermost
  first. Before, only the file the error was in was named, which is no
  help when two directories each hold a file of the same name. A macro
  already names its own call site, so nothing is said twice.
- The summary line reads `ended at FILE(line)` instead of `FILE: N
  lines.` The number never was a count: it is the line the assembly
  ended on. `END` inside an included file ends that file and every file
  above it, so the name here is where assembly stopped and not always
  the file you named on the command line.
- The `included from` line printed after a `cannot open` error is
  indented four spaces, matching the trail printed under every other
  error. It used to be seven, and the two lines say the same thing.
- An INCLUDE that cannot be found inside an included file now prints
  the whole chain that led to it, not just the line the failing INCLUDE
  was on.
- A line inside a conditional branch that is not taken no longer shows
  the location counter in the listing's address column when it carries
  a label. M80 leaves the column blank there, and a skipped EQU showing
  an address read as a symbol with the wrong value.
- A label on a line that emits no bytes is now defined, as M80 defines
  it: on `IF`, `ELSE` and `ENDIF` lines, and on `REPT`, `IRP`, `IRPC`
  and `END`. It takes the location counter, and only when that line is
  being assembled - a label on an `ENDIF` that closes a branch which was
  skipped stays undefined, exactly as it does in M80. Before, all of
  these were silently dropped and any reference to one failed with
  `undefined symbol in an expression` pointing at the reference rather
  than at the label.
- A label that the first reading of the source defines and the second
  one skips is now an error, naming the line the label is on. An
  `IFNDEF` guard is set on pass 1 and still set on pass 2, so a guarded
  block holding code is assembled once and skipped once: the label
  keeps the address pass 1 gave it and its bytes never reach the object
  file. M80 writes the short program without a word. A guard around
  equates only is unaffected and stays legal - those keep their values
  and are correct.

## v1.1.4 - 2026-09-28

- `name::` declares `name` PUBLIC, which is what M80 does. Tatara had
  accepted the second colon and done nothing with it, so an object file
  could come out missing a public symbol and fail at link time instead.
- `EQU`, `DEFL` and `MACRO` now refuse a colon after the name. A colon
  makes the label field a label, and those three take a name, so the
  line leaves them with nothing to name - M80 rejects it too.

## v1.1.3 - 2026-09-28

- A label no longer has to start in column 1. An indented one is a label
  if a colon ends it, which is what M80 accepts, and `name::` works
  indented too. A line starting in column 1 is unchanged - there the
  colon is still optional.

## v1.1.2 - 2026-09-28

- The tools are now distributed as a single LZH archive, `TATARxyz.LZH`,
  where `x`, `y` and `z` are the version numbers - `TATAR112.LZH` for this
  release. It holds `TATARA.COM`, `TANREN.COM` and `INCLUDES.LZH`, an inner
  archive with the headers from `include/`. The inner archive is stored
  rather than compressed, so unpacking the outer one leaves it ready to
  extract wherever the headers are wanted.
- `include/msxdos.inc`: the `system` macro is no longer wrapped in `IFNDEF`.
  The guard was keyed on a symbol, and a symbol defined on pass 1 is still
  defined on pass 2 - so the macro was defined on pass 1 and then vanished
  on pass 2, and every use of `system` failed. Repeating a `MACRO` is legal
  and replaces the definition, so there was nothing to guard against.
- `include/README.md`, `include/README.txt`: the name count is 903, not 904.
  The guard's own symbol had been counted as a name.

## v1.1.1 - 2026-09-28

- `examples/`: the examples include `msxdos.inc` and `bios.inc` instead of
  defining their own equates for BDOS functions and BIOS entries.
- Each `BUILD.BAT` sets `TATARA` to `A:\TATARA\INCLUDE` before assembling
  and clears it afterwards, so the headers are found through the include
  search path rather than copied into every example directory. Change that
  one line if the tree lives somewhere else.
- `examples/hello/BUILD.BAT`: removed `<` and `>` from its `rem` lines. The
  command processor scans a whole line for redirection before deciding it is
  a `rem`, so the brackets were being read as filenames.

## v1.1.0 - 2026-09-28

- New `include/` directory: 903 MSX names in nine headers, transcribed from
  the MSX Datapack.

  | | |
  |---|---|
  | `ascii.inc` | control codes and printable ASCII |
  | `bios.inc` | MAIN ROM entry points |
  | `errors.inc` | MSX-DOS and MSX-DOS 2 error codes |
  | `extbio.inc` | extended BIOS device and function numbers |
  | `hooks.inc` | the system hooks |
  | `msxdos.inc` | BDOS function codes, the BDOS entry and `system` |
  | `ports.inc` | I/O ports, including MSX-MIDI |
  | `subrom.inc` | SUB ROM entry points |
  | `workarea.inc` | the system work area |

- `include/README.md` and `include/README.txt`: what each header holds and
  how the include search path finds them.

## v1.0.0 - 2026-09-27

- Initial public release. Tatara and Tanren, the examples and the test suite.
