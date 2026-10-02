# Tatara and Tanren

**Tatara** is a macro assembler for the MSX and **Tanren** is its linker. They read M80 syntax, write and read relocatable object files, and run **on the MSX itself**, under MSX-DOS2 or Nextor. There is no cross-assembler and no other computer involved: Tatara assembles itself, and the `TATARA.COM` in `build/` was built from the sources beside it by the copy before it.

M80 and L80 were written for CP/M, and nothing in them knows about MSX-DOS2 directories, environment variables or a memory mapper. Tatara and Tanren use all three. The symbol table, the macro text and the linker's output image live in **mapper RAM**, so what you can build is limited by how much memory the MSX has, not by what fits beside the tool in a 64 KB address space.

**[Website](https://tatara.tools/en/)** · **[Manual](https://tatara.tools/en/manual/)** · **[マニュアル（日本語）](https://tatara.tools/ja/manual/)** · **[Download](https://tatara.tools/en/download/)** · **[Changelog](CHANGELOG.md)**

## Features

- **Runs on the MSX.** Any MSX2, MSX2+ or MSX turbo R with MSX-DOS2 or Nextor.
- **M80 syntax.** Sources written for MSX-M80 assemble with few or no changes. The manual has a checklist for converting them.
- **Long symbol names.** Up to 255 characters, all of them significant, and optionally case-sensitive (`/C`).
- **Macros and conditional assembly**, with `REPT`, `IRP`, `IRPC`, `LOCAL` and `EXITM`.
- **Segments.** Code, data and absolute segments, and named segments, which Tanren joins by name across modules.
- **Transient data segments.** Variables that are never in use at the same time can share memory, without working out the addresses by hand. A transient data segment is divided into groups with `GROUP`: every group starts at the same address, and the segment takes only as much memory as its largest group. Tanren does the same across modules, so routines in different source files can share one scratch area.
- **MSX-DOS2 directories.** An `INCLUDE` file is looked for in three places, and the `TATARA` and `TANREN` environment variables give the search paths.
- **Mapper memory.** Both tools keep their tables in the mapper, and Tanren builds the program there, so the output can be larger than the free TPA.
- **Link files.** Tanren reads its module list and options from a text file, so the 127-character command line of MSX-DOS is no limit.
- **Errors that cite your line**, even when the line came from a macro or an included file.
- **Several kinds of output.** `.COM` programs, `BLOAD` binaries for MSX-BASIC, raw images for any address, and ROM cartridge images.
- **R800 and undocumented instructions.** `MULUB` and `MULUW`, `SLL`, the index halves `IXH` to `IYL`, `IN F,(C)` and `OUT (C),0`.
- **Include files** with 904 names: MSX-DOS2 functions and error codes, BIOS and SUB ROM entries, the system work area, hooks, I/O ports and more (`include/`).

## Requirements

- An MSX2, MSX2+ or MSX turbo R.
- **MSX-DOS2 or Nextor.** Under MSX-DOS1 both tools stop with a message saying so.
- A memory mapper. Every MSX that runs MSX-DOS2 has one; 512 KB is recommended for large programs.

A floppy disk is enough for small programs. An SD or CompactFlash card makes larger ones much easier.

## Getting started

1. Download `TATAR120.LZH` from [tatara.tools/en/download](https://tatara.tools/en/download/) and extract it on the MSX with PMext. It holds `TATARA.COM`, `TANREN.COM` and `INCLUDES.LZH`, the include files.
2. Put the two programs on the `PATH`, and point the `TATARA` environment variable at the include files.
3. Assemble and link a program:

```
A:\TATARA\EXAMPLES\HELLO>tatara hello.as hello.tro
A:\TATARA\EXAMPLES\HELLO>tanren /o:hello.com hello.tro
A:\TATARA\EXAMPLES\HELLO>hello
```

Chapters 3 and 4 of the [manual](https://tatara.tools/en/manual/) go through the installation and a first program step by step. The manual is in English and Japanese, online and as PDF.

## Why not M80 and L80, or AS and LD

| | Tatara / Tanren | M80 / L80 | SOLiD AS / LD |
|---|---|---|---|
| Symbol length | 255 | 6 | ? |
| Case-sensitive symbols | optional | no | no |
| MSX-DOS2 directories in filenames | yes | no | partial |
| Places an INCLUDE is looked for | 3 | 1 | 1 |
| Search path from the environment | yes | no | no |
| Named segments | any number | 3 fixed | no |
| Overlaid data segments (GROUP) | yes | no | no |
| Symbol table in mapper RAM | yes | no | no |
| Output image built in mapper RAM | yes | no | no |
| Output larger than the free TPA | yes | no | no |
| Linker instructions from a file | yes | no | doesn't seem to work |
| Errors cite the line you typed | yes | yes | no |
| Errors traced across included files | yes | no | no |
| BLOAD header, raw image or ROM | yes | no | yes |
| R800 MULUB and MULUW | yes | no | no |
| Undocumented Z80 instructions | yes | no | partial |
| Assembles itself | yes | ? | ? |
| Redistributable | yes | no | ? |

## Building from source

The tools are built on the MSX, with themselves. With `TATARA.COM` and `TANREN.COM` on the `PATH` (a release, or the copies in `build/`), run from the top of the repository:

```
A:\SRC\TATARA>build
```

`build.bat` assembles the 27 modules and links both tools into `build/`. It is silent when everything works: anything printed between the `===` lines is a problem. Chapter 35 of the manual walks through it.

Every file the MSX reads is CR+LF. `.gitattributes` tells Git never to convert line endings; keep it that way, or a source checked out with LF assembles as one enormous line.

## The directories

| | |
|---|---|
| `shared/` | modules both tools link: heap, hash table, strings, MSX-DOS |
| `tatara/` | the assembler |
| `tanren/` | the linker |
| `include/` | the include files for your own programs |
| `build/` | the built `TATARA.COM` and `TANREN.COM` |
| `examples/` | eight small programs, each with its own build script |
| `tests/tatara/` | the assembler's test suite |
| `tests/tanren/` | the linker's test suite |
| `build.bat` | assembles all 27 modules and links both tools into `build/` |
| `tatara.lnk` | the assembler's module list, read by Tanren as `@tatara` |
| `tanren.lnk` | the linker's own |

Each of `examples/`, `include/`, `tests/tatara/` and `tests/tanren/` has a README of its own.

## License

Copyright © 2026 Javier Lavandeira. Licensed under the [Apache License, Version 2.0](LICENSE).

MSX is a trademark of MSX Licensing Corporation. Nextor is copyright © Néstor Soriano.
