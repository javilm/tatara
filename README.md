# Tatara and TANREN

**Tatara** is an M80-compatible macro assembler for the MSX and
**TANREN** is its linker. They read M80 syntax, produce and consume
relocatable object files, and run **on the MSX itself** under
MSX-DOS2 - there is no cross-assembler and no other computer involved.
Tatara assembles itself: the `TATARA.COM` in `build/` was built from
the sources beside it, by the copy before it.

M80 and L80 were written for CP/M, and nothing in them knows about
MSX-DOS 2 directories, environment variables or a memory mapper.
Tatara and TANREN use all three. The symbol table, the macro text and
the linker's output image live in **mapper RAM**, so what you can build
is bounded by how much memory the machine has and not by what fits
beside the tool in a 64 KB address space.

## Requirements

**MSX-DOS2 or Nextor.**

## Why not M80 and L80, or AS and LD

| | Tatara / TANREN | M80 / L80 | SOLiD AS / LD |
|---|---|---|---|
| Symbol length | 255 | 6 | - |
| Case-sensitive symbols | optional | no | no |
| MSX-DOS 2 directories in filenames | yes | no | partly |
| Places an INCLUDE is looked for | 3 | 1 | 1 |
| Search path from the environment | yes | no | no |
| Named segments | any number | 3 fixed | - |
| Overlaid data segments (GROUP) | yes | no | - |
| Symbol table in mapper RAM | yes | no | no |
| Output image built in mapper RAM | yes | no | no |
| Output larger than the free TPA | yes | no | no |
| Linker instructions from a file | yes | no | does not work |
| Assembler names its own output file | yes | yes | no |
| Errors cite the line you typed | yes | yes | no |
| Reserved space padded into the image | no | no | yes |
| BLOAD header, raw image or ROM | yes | - | - |
| R800 MULUB and MULUW | yes | no | - |
| Assembles itself | yes | - | - |
| Redistributable | yes | no | - |

A `-` is not a claim: it means this project never tested it. The
`AS`/`LD` column is what was observed while SOLiD's pair was used to
bootstrap Tatara, and nothing more.

## The directories

| | |
|---|---|
| `shared/` | modules both tools link: heap, hash table, strings, MSX-DOS |
| `tatara/` | the assembler |
| `tanren/` | the linker |
| `build/` | the built `TATARA.COM` and `TANREN.COM` |
| `examples/` | eight small programs, each with its own build script |
| `tests/tatara/` | the assembler's test suite |
| `tests/tanren/` | the linker's test suite |
| `build.bat` | assembles all 27 modules and links both tools into `build/` |
| `tatara.lnk` | the assembler's module list, read by TANREN as `@tatara` |
| `tanren.lnk` | the linker's own |

Each of `examples/`, `tests/tatara/` and `tests/tanren/` has a README
of its own.
