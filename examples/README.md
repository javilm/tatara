# Examples

Eight small programs, each in its own directory with its own
`BUILD.BAT`. The build script is where the explanation is: read it
first, then the source.

They are documentation and not tests. Nothing here is compared against
a recorded result - if an example builds and does what its script says,
it is doing its job.

Both tools have to be on the `PATH`. `BUILD.BAT` is run from the
example's own directory:

```
A:\> cd examples\hello
A:\EXAMPLES\HELLO> build
```

| directory | what it shows |
|---|---|
| `hello` | one source to one `.COM`: the whole cycle in two commands |
| `twomod` | `PUBLIC` and `EXTRN` across two modules, linked from a file |
| `layout` | `CSEG`, `DSEG`, and `GROUP`s sharing a `TRANSIENT` one |
| `dirs` | the three places an `INCLUDE` is looked for, and `TATARA` |
| `macros` | `MACRO`, `LOCAL`, `REPT`, `IRP`, and the listing modes |
| `names` | 48-character names, and one source in both case modes |
| `binary` | `ASEG` and `/B`: a `.BIN` that MSX BASIC loads with `BLOAD` |
| `rom` | a 16 KB cartridge that prints a line and never returns |

`hello`, `twomod`, `dirs`, `layout` and `macros` leave a `.COM` you
can type the name of. `names` leaves two text files to compare.
`binary` leaves a file for `BLOAD`. `rom` leaves a cartridge image,
and it is the only one whose result a successful build does not show
you - load it in an emulator.

The build products are not kept in this repository. Run the script.

## What is not here

`examples/` is a tour of the assembler, not a manual. Every option
either tool takes is listed by `TATARA /?` and `TANREN /?`.
