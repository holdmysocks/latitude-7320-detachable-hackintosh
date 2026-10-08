# Layer 4: the Ice Lake accelerator on Tiger Lake

**Status (2026-10-08): the accelerator starts and schedules work; nothing is drawn.** `AppleIntelICLGraphics`
attaches to `9A40`, creates contexts, submits them, and receives their completions. Blitter work and render-engine
work that draws nothing complete. Every submission that draws hangs with the vertex shader stage busy, the driver
resets the GPU about every 10 seconds, and the login screen stays black with a live cursor.

Everything here is on top of the working framebuffer ([`LAYER3.md`](LAYER3.md), configuration "R"). Five boots,
2026-10-08. Evidence: [`data/layer4/`](data/layer4/). Patch:
[`0004-tgl-accelerator.patch`](../WhateverGreen-patches/0004-tgl-accelerator.patch).

## What was needed to get this far

| # | Obstacle | Fix |
|---|---|---|
| 1 | The accelerator refuses PCI revision ≤ 2 | boot-arg `-allow3d` (Apple's own) |
| 2 | `getGPUInfo()` panics: "Unsupported ICL Sku" | `igfxtglss=6`: patch the subslice count at kext load |
| 3 | Panic: "Unexpected context status buffer entry" | `igfxtglcsb=1`: read the status buffer in the Gen12 layout |
| 4 | **Draws hang in the vertex shader stage** | **none** |

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

## 4. Where it stops

macOS writes an Intel hang report for every GPU reset (`/Library/Logs/DiagnosticReports/Kernel_*.gpuRestart`), with
ring registers, `INSTDONE`, execlist status, ring contents and an MMIO dump. They need no kext logging and survive a
hard power-off. Three are in [`data/layer4/`](data/layer4/).

Every report of a submission that draws shows the same thing, in both GA4 and GA5 and down to identical batch
addresses (`0x40b75ed8`, `0x42b54104`, `0x43b84520`, `0x42f2474c`, `0x452d78a0`):

- the render engine ran a batch (`MI_BATCH_BUFFER_START`) and returned to the ring;
- it stopped on the `PIPE_CONTROL` that follows (`IPEHR = 0x7a000004`, CS stall set);
- `INSTDONE = 0xffdffffb`: **VS and CS not done**; the common-slice `INSTDONE` has bit 0 clear.

The command streamer is waiting for the 3D pipeline to drain, and the vertex shader stage never finishes.

What completes: every blitter submission, and render contexts that only load state.

**Reading, not yet tested:** shader programs are compiled in user space by Apple's Ice Lake Metal/GL driver into
Gen11 EU machine code. Gen12 EUs use a different instruction encoding (Mesa carries separate Gen12 encoders, and
software scoreboard fields replace thread dependency control). The first stage that runs a shader would then never
see its threads terminate. That is the "shader ISA" explanation usually given for Iris Xe on macOS, and these hangs
are what it predicts. The runs do not prove it: no shader kernel from a hung batch has been examined.

Ruled out: the subslice count (GA5, `igfxtglss=4`, same hangs at the same batches).

Not ruled out: the Ice Lake workaround table (`InitIclLpWaTable`) being written to Tiger Lake registers; the power
and clock state in the context image (`0x20C8`); Gen11 3D state commands that Gen12 re-encoded.

## Runs

| Run | Kext build | Added | Outcome |
|---|---|---|---|
| GA1 | 0003x | no `Kernel/Block`, `-allow3d -disablegfxfirmware` | reboot during boot, no panic record ("Unsupported ICL Sku", by the fuse values) |
| GA2 | 0003x | `igfxtglss=6` | accelerator starts; panic at 30 s, context status buffer |
| GA3 | 0003y | `igfxtglcsb=1`, 12-entry reader | black login screen; reader stalled at entry 6 |
| GA4 | 0003z | 6-entry reader | black login screen; 65 events handled; GPU hang every ~10 s, VS busy |
| GA5 | 0003z | `igfxtglss=4` | as GA4; 90 events; same batches hang |

Build 0003z is patches 0001–0004. Boot-args of GA4:
`lilucpu=12 -igfxdvmt -igfxcdc igfxtglmap=0xA83F igfxtglblmax=0xAD9 dc6config=0 -igfxdbeo -allow3d -disablegfxfirmware igfxtglss=6 igfxtglcsb=1`.

`igfxtglcsb=1` logs every event to `/Users/Shared/tgl-csb.bin` (`tools/mac/decode-tglcsb.py`). The file is left
open, so a clean shutdown hangs afterwards: power off by hand.
