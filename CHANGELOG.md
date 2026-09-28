# Changelog

Tatara and Tanren. Newest first.

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
