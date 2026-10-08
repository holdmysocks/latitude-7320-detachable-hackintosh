# tgl-xlate: Gen11 to Gen12 EU code

Translates Intel execution-unit machine code compiled for Ice Lake (Gen11) into Tiger Lake (Gen12) code, one kernel
at a time. Used by patch 0004 (`igfxtglxl=1`) to rewrite the shaders Apple's Ice Lake drivers emit, in place, before
the GPU runs them. Why and how: [`../../research/LAYER4.md`](../../research/LAYER4.md), section 5.

It is built on Mesa 23.3.6's Intel compiler (MIT licence): instruction accessors, compaction tables, emitter,
disassembler, validator. No Mesa source is in this repository; `setup.sh` fetches it (sparse clone, about 40 MB).

| File | |
|---|---|
| `tgl_xlate.c`, `tgl_xlate.h` | the translator; the same file goes into the host tool and the kext |
| `g11to12.c` | host tool: `g11to12 dis11\|dis12 <file>`, `g11to12 xlate <in> [out]` (prints the result and runs Mesa's validator) |
| `kruntime.c`, `kshim/` | what Mesa's encoder needs from a C library, for the kernel build: a static arena, an `assert` that fails the translation instead of panicking, no output |
| `eu-stubs/`, `stub/` | stand-ins for `brw_compiler.h` and the generated workaround header |
| `a1_3src_helpers.h` | four small functions from Mesa's `brw_disasm.c` (three-source region decoding) |
| `mesa-brw_eu_emit-acc1.patch` | lets Mesa's emitter take `acc1` as a three-source destination |
| `fuzz.c`, `fzbuild.sh` | sanitizer build fed with random and mutated kernels: `./fzbuild.sh all <seed kernels>` |
| `ktest.c` | links the objects built with the kext's kernel flags on the host and compares their output with reference files |
| `build-weg2.sh` | builds WhateverGreen (patches 0001-0004 applied) together with the translator |

```sh
./setup.sh                                   # Mesa, ./eu
./build.sh                                   # ./g11to12
./build-weg2.sh ../path/to/WhateverGreen out # the kext
```

A kernel is translated completely or rejected; `tgl_xlate_kernel()` returns the reason. Not reentrant. Limits and
what is not handled are listed at the top of `translate()` and in LAYER4.md.
