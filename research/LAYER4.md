# Layer 4: the Ice Lake accelerator on Tiger Lake

**Status (2026-10-08, after run GA11): the GPU draws, the desktop does not come up.** `AppleIntelICLGraphics`
attaches to `9A40`, schedules work, and with every shader translated from Ice Lake to Tiger Lake machine code
before it runs, batches complete and things appear on screen (the cursor over the boot logo, coloured blocks, a
red stripe). GPU hangs remain in three places: a 340 KB shader that was not translated yet, the driver's own
fast-clear/resolve batches, and one draw whose cause is open. Nothing here is usable.

Everything is on top of the working framebuffer ([`LAYER3.md`](LAYER3.md), configuration "R"). Eleven boots,
2026-10-08. Evidence: [`data/layer4/`](data/layer4/). Patch:
[`0004-tgl-accelerator.patch`](../WhateverGreen-patches/0004-tgl-accelerator.patch); translator:
[`../WhateverGreen-patches/tgl-xlate/`](../WhateverGreen-patches/tgl-xlate/).

## What was needed to get this far

| # | Obstacle | Fix |
|---|---|---|
| 1 | The accelerator refuses PCI revision ≤ 2 | boot-arg `-allow3d` (Apple's own) |
| 2 | `getGPUInfo()` panics: "Unsupported ICL Sku" | `igfxtglss=6`: patch the subslice count at kext load |
| 3 | Panic: "Unexpected context status buffer entry" | `igfxtglcsb=1`: read the status buffer in the Gen12 layout |
| 4 | Draws hang: shaders are Gen11 EU machine code | `igfxtglxl=1`: translate every shader to Gen12 at batch submission |
| 5 | Shaders the translator does not cover yet; the driver's fast-clear/resolve batches | open |

`-disablegfxfirmware` was used throughout: the driver's own host scheduler, no GuC.

### 0. OpenCore cannot patch or block this kext

`AppleIntelICLGraphics` (and the framebuffer kext) are in the system kernel collection, not the boot kernel
collection. OpenCore's `Kernel/Patch` and `Kernel/Block` do not reach it: with a `Block`/`Exclude` entry present the
kext still loaded and probed on every boot. The Layer 3 write-up assumed that entry was what kept the accelerator
out. It was not; obstacle 1 was. Patches have to go in through Lilu when the kext loads.

### 1. PCI revision

`IntelAccelerator::probe()` reads the PCI revision and fails with
`[IGPU] Failing probe (-allow3d is NOT set in boot-arg)!` when it is 2 or less. This chip is revision 1. The line is
in the unified log of every Layer 3 boot, twice.

### 2. The subslice fuse is read with the wrong polarity

`getGPUInfo()` reads the fuses straight from the MMIO mapping. It computes the subslice count as
`popcount(~[0x913C])`. On Ice Lake that register is a subslice *disable* mask; on Tiger Lake it is the dual-subslice
*enable* mask. Here it reads `0x1F`, the driver gets 27, and only 1, 4, 6 and 8 are accepted.

Fuse values on the i5-1140G7, read with forcewake held ([`data/layer4/gt-fuses.txt`](data/layer4/gt-fuses.txt)):

| Register | Value | Driver's reading |
|---|---|---|
| `0x9138` | `0x00000001` | 1 slice |
| `0x913C` | `0x0000001F` | 27 subslices (really: 5 dual subslices enabled) |
| `0x9134` | `0x00000000` | 8 EUs per subslice |
| `0x9120` | `0x90000004` | "GPU Sku" 9, which the driver pairs with 1x6x8 |
| `0x9140` | `0x000E00FA` | video/enhancement boxes |

`igfxtglss=<n>` replaces the computation with a constant (`44 89 F8 F7 D0 F3 0F B8 F0 89 B3 88 11 00 00`, the
`not`/`popcnt` becomes `mov $n, %esi`). 6 matches the Sku value; 4 is accepted too (run GA5) and changes nothing
further down.

### 3. The context status buffer

With 1 and 2 the accelerator starts, the GPU executes the first submissions, and the kernel panics about 30 s into
boot in `ContextStatusBufferValidate` (context id mismatch;
[`data/layer4/panic-GA2-context-status-buffer.txt`](data/layer4/panic-GA2-context-status-buffer.txt)).

The driver's `IGHardwareCommandStreamer5::processContextStatusBuffer()` expects Gen8-layout entries: event bits in
the lower dword, the upper half of the context descriptor in the upper dword. Tiger Lake writes the Gen12 layout
(i915 `gen12_csb_parse`):

| | Lower dword | Upper dword |
|---|---|---|
| Gen8/Gen11 | bit 0 idle→active, 1 preempted, 2 element switch, 3 active→idle, 4 complete, 7 wait on semaphore, 15 lite restore | context id in bits 15:5 |
| Gen12 | bit 0 switched to a new queue; bits 25:15 id of the context switched **to** | bits 3:0 switch detail; bits 25:15 id of the context switched **away from** |

Context id `0x7FF` means idle. What the first panic was: entry 0 (idle→active) has bit 0 set in both layouts and was
handled by accident. Entry 1 (active→idle) has a lower nibble of zero; the driver's `bsf` then leaves its index
register unchanged, the dispatch table lands on "element switch", and the id check fails.

**The buffer has 6 entries, not 12.** i915 uses 12 on Gen11 and later, but it also sets
`GEN11_GFX_DISABLE_LEGACY_MODE` in `GFX_MODE`. Apple's `initModeRegisters()` writes `0x80000` to `GFX_MODE`, which
clears that bit, while still submitting through the submit queue (`0x2510`) and the load bit (`0x2550`). In that
mode the hardware wraps from entry 5 to entry 0 and never writes entries 6–11
([`data/layer4/csb-GA3.txt`](data/layer4/csb-GA3.txt): the first version of the reader assumed 12 and stalled at
entry 6). So: Gen12 layout, legacy count.

`igfxtglcsb=1` routes `processContextStatusBuffer()` to a replacement that reads the hardware status page (entries
at `+0x40`, write pointer at `+0xBC`), turns each entry into the Gen8 form and calls the driver's own four handlers:

| Gen12 entry | Handed to | Gen8 lower dword |
|---|---|---|
| away = idle | `csbProcessIdleToActive` | `0x01` |
| new queue, away valid | `csbProcessPreempted` | `0x02`, plus `0x8000` if to = away (lite restore), else `0x10` if detail = 0, `0x80` if detail = 4 |
| no new queue, to valid | `csbProcessElementSwitch` | `0x04` + `0x10` (or `0x80` if detail = 4) |
| no new queue, to = idle | `csbProcessActiveToIdle` | `0x08` + `0x10` (or `0x80` if detail = 4) |

An entry is handed on only if its ids match the driver's execlist state; otherwise it is skipped and logged, because
the driver panics on a mismatch and `csbProcessElementSwitch` dereferences the second slot unchecked. With the
6-entry wrap no entry has been skipped: 65 events in run GA4 and 90 in GA5, on the render and blitter engines,
including lite-restore preemptions and the restart after each GPU reset
([`csb-GA4.txt`](data/layer4/csb-GA4.txt), [`csb-GA5.txt`](data/layer4/csb-GA5.txt)).

The offsets used are those of `AppleIntelICLGraphics` 24.0.5 in macOS 26.6 (25G72) and are listed in the patch.

## 4. Shaders are Ice Lake machine code

macOS writes an Intel hang report for every GPU reset (`/Library/Logs/DiagnosticReports/Kernel_*.gpuRestart`), with
ring registers, `INSTDONE`, execlist status, ring contents and an MMIO dump. They need no kext logging and survive a
hard power-off. Three are in [`data/layer4/`](data/layer4/).

With obstacles 1-3 out of the way every submission that draws hung the same way (GA4, GA5: identical batch
addresses): the render engine ran a batch, returned to the ring and stopped on the `PIPE_CONTROL` with CS stall
that follows; `INSTDONE = 0xffdffffb`, **VS and CS not done**. The subslice count is not involved (GA5).

Run GA6 captured what was executing. `igfxtglhang=1` hooks `IGHardwareRingBuffer::doHangAnalysis`, reads `BB_ADDR`
and the context's PML4 (`PDP0`), walks the per-process page tables, and saves the batch plus the kernels its
`STATE_BASE_ADDRESS` / `3DSTATE_VS` / `3DSTATE_PS` point to
([`hang-capture-GA6.txt`](data/layer4/hang-capture-GA6.txt)). Mesa's Gen11 disassembler reads those kernels as
ordinary shaders ([`translation-examples.txt`](data/layer4/translation-examples.txt)): a matrix times a vertex and
a URB write; a texture sample and a render-target write. Every instruction is valid Gen11 and not valid Gen12.
MOV is opcode `0x01` on Gen11; on Gen12 `0x01` is `sync` and MOV is `0x61`. So the "shader ISA" explanation for
Iris Xe on macOS is correct, and it is the first thing that stops a draw.

## 5. Translating the shaders

The shaders come from Apple's user-space Metal/GL drivers, compiled for Ice Lake. They are fixed up in the kernel
instead: `igfxtglxl=1` hooks `IGHardwareRingBuffer::submitBatchBuffer`, walks each render-engine batch (following
`MI_BATCH_BUFFER_START`), tracks the instruction base address, and for every `3DSTATE_VS/HS/DS/GS/PS` kernel
pointer reads the kernel through the context's page tables, translates it and writes it back **in place**. A
kernel is rewritten only if every instruction in it translates; a cache keyed by physical address and content
keeps a kernel from being translated twice.

The translator ([`tgl_xlate.c`](../WhateverGreen-patches/tgl-xlate/tgl_xlate.c)) is built on Mesa 23.3.6's own
code: it decompacts and decodes with Mesa's Gen11 tables, re-emits each instruction through Mesa's emitter set up
for Gen12, and recompacts with the Gen12 tables. The same file builds as a host tool (`g11to12`, with Mesa's
disassembler and validator) and into the kext. What it has to do beyond re-encoding:

| Gen11 | Gen12 |
|---|---|
| no dependency annotations | software scoreboard: `@1` on every instruction; each send sets a token; a later instruction waits `$n.dst`, or a `sync.nop $n.dst` is inserted; everything outstanding is waited for before a branch or jump target |
| `sends` / `sendsc` (split sends) | `send` / `sendc` with two payload sources |
| extended descriptor bits 15:12 only through `a0.n` | immediate, when `a0.n` was loaded with a constant just before; otherwise the register form |
| accumulator in its native format (`NF`) for plane evaluation: `mad acc0:NF`, `mad dst, acc0:NF` | a general register the kernel never names, as float |
| `mov` to ARF `0xF0` with thread switch (a yield hint) | `mov null, 0` |
| compacted instructions | recompacted; where there is no Gen12 compact form the kernel grows |
| jump distances (`if/else/endif/while/break/continue/halt`, `goto`, `join`, `jmpi`) | recomputed for the new layout. `jmpi` counts from the next instruction, the others from themselves. Mesa has no `join` (`0x2F`): it is handled by raw opcode |
| `g[a0 + imm]` operands, `acc1` destinations, zero padding inside a kernel, code after the first end-of-thread | carried over |

A kernel may grow into the zero padding up to the next 64-byte boundary (kernel pointers are 64-byte aligned); if
that is not enough everything compactable is compacted; if it still does not fit it is rejected. Real shaders seen
so far run from 8 instructions to about 25,000 (a 340 KB image-processing shader).

Checks before each boot: a regression set of captured kernels must give byte-identical output from the host build
and from the objects built with the kext's kernel flags, Mesa's Gen12 validator must pass, and a fuzzer feeds
400,000 random and mutated kernels through a sanitizer build (it found an integer overflow and several places
where arbitrary bytes reached an `unreachable`).

Results, from `/Users/Shared/tgl-xlate.bin` ([`xlate-GA7.txt`](data/layer4/xlate-GA7.txt) ...
[`xlate-GA11.txt`](data/layer4/xlate-GA11.txt)):

| Run | Batches | Kernels translated | Rejected | On screen |
|---|---|---|---|---|
| GA7 | 13 | 15 | 6 | nothing; the batch that hung in GA4-GA6 completes |
| GA8 | 13 | 18 | 1 | nothing |
| GA9 | 64 | 249 | 145 | cursor over the boot logo, coloured blocks |
| GA10 | 141 | 1231 | 56 | a red diagonal stripe; then a machine check (below) |
| GA11 | 205 | 2049 | 52 | similar; GPU hangs |

## 6. Where it stops now

- **A 340 KB pixel shader** (nine copies in GA11) was rejected because only 100 KB were read; its first jump is an
  unconditional `jmpi +335432`. Build 0004g reads up to 700 KB. Untested on the machine.
- **The driver's own resolve batches.** Two GA11 hangs are in the kernel driver's resolve context: a RECTLIST
  draw with the vertex shader off, `3DSTATE_PS` with *render target fast clear enable*, and the `PIPE_CONTROL`
  after it never completes although the pipeline is idle
  ([`hang-capture-GA11.txt`](data/layer4/hang-capture-GA11.txt)). Probable cause, not proven: Tiger Lake re-encoded
  the auxiliary surface modes (Gen11's CCS_D value means MCS on Gen12) and wants aux-map tables for CCS. Build
  0004g can skip those submissions (`igfxtglres`), as an experiment.
- **One hang with a translated shader** whose 8-pixel kernel looks right; the 16- and 32-pixel variants were not
  captured.
- Not looked at: compute and media kernels, the kernels the driver itself uses for blits, message descriptor and
  thread payload differences, whether what is drawn is correct.

## 7. Machine check: do not read stolen memory

GA10 ended in a machine check on every core (`IA32_MC8_ADDR = 0x6C800040`,
[`panic-GA10-machine-check.txt`](data/layer4/panic-GA10-machine-check.txt)). The kext had been changed to read nine
pages per kernel instead of two; past the end of a kernel the GPU page tables point at the driver's placeholder
page, which is in graphics stolen memory, and reading that from the CPU through the kernel's physical map is fatal
on this machine. Since 0004f every physical access is limited to RAM: below the stolen memory base (from the
`0x1080C0` / `0x108040` mirrors of BDSM and GGC) or between 4 and 16 GB.

## Runs

| Run | Kext build | Added | Outcome |
|---|---|---|---|
| GA1 | 0003x | no `Kernel/Block`, `-allow3d -disablegfxfirmware` | reboot during boot, no panic record ("Unsupported ICL Sku", by the fuse values) |
| GA2 | 0003x | `igfxtglss=6` | accelerator starts; panic at 30 s, context status buffer |
| GA3 | 0003y | `igfxtglcsb=1`, 12-entry reader | black login screen; reader stalled at entry 6 |
| GA4 | 0003z | 6-entry reader | black login screen; 65 events handled; GPU hang every ~10 s, VS busy |
| GA5 | 0003z | `igfxtglss=4` | as GA4; 90 events; same batches hang |
| GA6 | 0004a | `igfxtglhang=1` | hung batches and their kernels captured: Gen11 code |
| GA7 | 0004b | `igfxtglxl=1` | 15 kernels translated, the old hang is gone; rejected pixel shaders hang; watchdog reboot |
| GA8 | 0004c | sync insertion, branches, growth | 18 translated, 1 rejected, hang in the batch using it |
| GA9 | 0004d | exact register tracking | first drawing; 249 translated, 145 rejected |
| GA10 | 0004e | jmpi, register descriptors, 36 KB kernels | 1231 translated; machine check reading stolen memory |
| GA11 | 0004f | RAM-only access, goto/join, indirect, padding, 100 KB | 2049 translated, no panic; hangs of section 6 |

The 0004 builds are patches 0001-0004 plus the translator (`tgl-xlate/build-weg2.sh`). Boot-args of GA11:
`lilucpu=12 -igfxdvmt -igfxcdc igfxtglmap=0xA83F igfxtglblmax=0xAD9 dc6config=0 -igfxdbeo -allow3d -disablegfxfirmware igfxtglss=6 igfxtglcsb=1 igfxtglhang=1 igfxtglxl=1`.

Logs: `/Users/Shared/tgl-csb.bin` (`tools/mac/decode-tglcsb.py`), `tgl-hang.bin` (`decode-tglhang.py`),
`tgl-xlate.bin` (`decode-tglxlate.py`). The status-buffer log file is left open, so a clean shutdown hangs
afterwards: power off by hand.
