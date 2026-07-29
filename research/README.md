# Iris Xe (Gen12 / `8086:9A40`) on macOS — a controlled negative result

**Status: concluded.** Stock Apple kexts plus `DeviceProperties` spoofing cannot
get past framebuffer *attach* on `9A40`. Eleven runs, one uniform failure mode.

No published experiment targets `9A40`. Prior Tiger Lake work used `9A49`. So
even a clean negative result here is new.

If you are about to attempt Iris Xe acceleration on macOS, this document exists
so that you can skip what has already been ruled out — and, just as importantly,
so you do not inherit a conclusion this project never actually tested.

- [`RESULTS.md`](RESULTS.md) — all eleven runs, what each establishes
- [`METHODOLOGY.md`](METHODOLOGY.md) — controls, and the four measurement traps
- [`data/`](data/) — the raw dumps, scrubbed but not edited

---

## Where the wall is

| Layer | Component | Status on `9A40` |
|---|---|---|
| 1. PCI match | IOKit `IOPCIPrimaryMatch` | ✅ works with any `8A5x` spoof |
| 2. Kext load | kext pulled into memory | ✅ confirmed via `kextstat` |
| 3. Framebuffer attach | `AppleIntelICLLPGraphicsFramebuffer::start()` | ❌ **hard hang — the wall** |
| 4. Accelerator match | `AppleIntelICLGraphicsMTLDriver` | **never reached** |
| 5. Command submission | Gen12 command streams | **never reached** |

## ⚠️ Layers 4 and 5 were never tested

This is the most important sentence in the repository.

The widely-repeated assumption about Iris Xe on macOS is that the **shader ISA**
is the blocker: Apple's Metal driver is compiled for Gen11 EU thread dispatch
and command-streamer encodings, Xe-LP changed both, therefore Gen11-encoded
command buffers fault on Gen12 hardware.

That assumption may well be correct. **This project produced no evidence about
it whatsoever**, because the display engine fails one full layer earlier. The
machine never got as far as submitting a command stream, or matching a Metal
driver, or rendering anything.

The expectation going in was the opposite — that the framebuffer would attach
and the accelerator would be the blocker. That is not what happened.

So: the ISA wall remains an **untested hypothesis**. If you read anything in
this repository as confirming it, that is a misreading, and it is the specific
misreading this write-up was structured to prevent.

## What *is* established

Three findings, each of which closes a line of enquiry.

### 1. It is not a connector-configuration problem

Five distinct Ice Lake personalities were injected — `8A52`, `FF05`, `8A5C`,
`8A51`, `8A70`. They describe **different connector, pipe and DDI layouts**, and
`8A70` is a different GT tier entirely. All five failed identically.

A mismatched connector layout — the obvious hypothesis for a 3:2 1920×1280 panel
with no external outputs — would not produce five identical failures. **Ruled
out.** Do not spend time hunting for the "right" platform ID; there is no reason
to think one exists.

### 2. WhateverGreen is not implicated

Run 9 disabled WhateverGreen entirely and got the identical hang. WG's
unrecognised-hardware patching is not the cause.

### 3. AGDC handoff is not implicated

Run 10 set `igfxagdc=0` and got the identical hang.

### What remains

`AppleIntelICLLPGraphicsFramebuffer` programming **Gen11 display-engine register
offsets into Xe-LP silicon**, and taking the platform down below the OS's
ability to report it: no panic, no surviving kernel, spontaneous hardware reset.

---

## The WhateverGreen finding — separately useful

Worth knowing even if you never touch acceleration.

`ig-platform-id` reads `<ffffffff>` on a boot with **`-igfxvesa` removed and
nothing injected**. `0xFFFFFFFF` is WhateverGreen's VESA sentinel.

**WhateverGreen forces VESA on its own, because it does not recognise `9A40`.**

- **`-igfxvesa` is redundant on this hardware.** WG does it regardless. If you
  remove the boot-arg on a TGL machine and nothing changes, this is why.
- **WG is an active participant in every result**, not a neutral observer.
- Unless an explicit `AAPL,ig-platform-id` is injected, the ICLLP framebuffer
  always receives `0xFFFFFFFF` and declines in `probe()` — captured verbatim in
  [`data/ioreg/gfx-minimal.log`](data/ioreg/gfx-minimal.log):

  ```
  [IGFB][ERROR][DISPLAY   ] Failing probe: Undefined platform ID
  ```

  That clean refusal is why runs 1 and 4 boot safely. Inject a *defined*
  platform ID and probe succeeds — then `start()` kills the machine.

## Ground truth: `IOPCIPrimaryMatch`

From `AppleIntelICLLPGraphicsFramebuffer.kext` in Tahoe, verbatim:

```
0xff058086  0x8A708086  0x8A718086  0x8A518086  0x8A5C8086
0x8A5D8086  0x8A528086  0x8A538086  0x8A5A8086  0x8A5B8086
```

Ten Ice Lake IDs. `9A40` is not among them and never will be.

**The naming trap:** the framebuffer is `AppleIntelICLLPGraphicsFramebuffer.kext`
(**ICLLP**) but the Metal driver is `AppleIntelICLGraphicsMTLDriver.bundle`
(**ICL**, no LP). `AppleIntelICLLPGraphicsVAME.bundle` is ICLLP again. Scripts
that assume one spelling silently find nothing.

---

## Prior art

`lshbluesky` got `AppleIntelICLLPGraphicsFramebuffer` to **attach** on Tiger
Lake and report 1536 MB VRAM — by **patching WhateverGreen's source in Xcode**,
not by configuration — then abandoned the acceleration research. That repo now
receives only version bumps.

Framebuffer attach: solved by them. Acceleration: unsolved, by the person who
got furthest.

Their hardware was `9A49`; this is `9A40`.

## What would actually be required to go further

> **Layer 3 cannot be crossed with `config.plist` alone.** No combination of
> `device-id`, `AAPL,ig-platform-id`, boot-args or kext toggles gets past it.

That is the whole conclusion. The remaining path is a code project:

1. Build WhateverGreen from source (`acidanthera/WhateverGreen`); framebuffer
   logic lives in `kern_igfx*.cpp`.
2. Add Tiger Lake / `9A40` awareness so WG stops emitting the `0xFFFFFFFF` VESA
   sentinel for this device.
3. Identify which display-engine registers `ICLLPGraphicsFramebuffer` touches
   during `start()`, and where Gen12 relocated them. Linux `i915` Gen12 source
   is the authoritative reference.
4. Patch those accesses in flight, the way WG already does for other
   generations.
5. **Only then** does layer 4 become testable.

Realistic assessment: step 3 is the hard one. It needs either a hardware
debugger or a great deal of trial-and-error against a machine that hard-resets
on every wrong guess — with no panic log, no serial console and no surviving SSH
session. That is a poor debugging loop, and it is the honest reason this project
stopped where it did.

### One loose thread

`AppleIntelICLGraphics` was observed declining to probe with
`Failing probe (-allow3d is NOT set in boot-arg)!`. Nobody re-ran with
`-allow3d` set. It may gate something or nothing; no conclusion here depends on
it. It is recorded because it is the only observed lead sitting *above* the
layer where everything else failed. See
[`RESULTS.md`](RESULTS.md#run-4--the-kext-says-why-in-its-own-words).

## Further reading

- `acidanthera/WhateverGreen` — framebuffer patch logic in `kern_igfx*.cpp`
- Linux `i915` Gen12 — authoritative register and command-streamer documentation
- InsanelyMac: "Iris Xe iGPU on Tiger Lake successfully loaded ICLLP Framebuffer"

---

## Summary for citation

- **Hardware:** i5-1140G7, TGL-UP4, Iris Xe 80 EU, `8086:9A40`, subsys `1028:0A45`
- **OS:** macOS 26 Tahoe, OpenCore 1.0.7, WhateverGreen 1.7.0,
  `AppleIntelICLLPGraphicsFramebuffer` 24.0.5
- **Method:** every run rebuilt from a known-good config; one variable at a
  time; a genuine control and a decoupling probe; SSH on a static reservation so
  "no shell" is evidence rather than ambiguity
- **Findings:**
  1. WhateverGreen forces `ig-platform-id = 0xFFFFFFFF` on unrecognised `9A40`,
     independent of `-igfxvesa`. `-igfxvesa` is therefore redundant here.
  2. PCI matching and kext load succeed with any `8A5x` `device-id` spoof.
  3. Framebuffer attach hard-hangs the platform: no panic, no surviving kernel,
     spontaneous reset.
  4. Five distinct Ice Lake personalities fail identically → not a connector
     configuration problem.
  5. Neither disabling WhateverGreen nor `igfxagdc=0` changes the outcome.
- **Conclusion:** on `9A40` the blocker is the **display engine**, not the
  shader ISA. Configuration-only approaches are exhausted. Progress requires
  patching WhateverGreen's framebuffer path from source.
- **Not established:** anything at all about layers 4–5.
