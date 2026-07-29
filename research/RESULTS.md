# Results

Eleven runs. Every one rebuilt from `config.KNOWNGOOD.plist`, one variable at a
time. Method and controls: [`METHODOLOGY.md`](METHODOLOGY.md).

Hardware: Intel i5-1140G7 (TGL-UP4), Iris Xe 80 EU, **`8086:9A40`**, subsystem
`1028:0A45`. macOS 26 Tahoe, OpenCore 1.0.7, WhateverGreen 1.7.0.

---

## The table

| # | Configuration | Boot | Framebuffer | Verdict |
|---|---|---|---|---|
| 0 | baseline, `-igfxvesa` | ✅ | `IONDRVFramebuffer` | reference |
| 1 | `-igfxvesa` removed, nothing injected | ✅ | `IONDRVFramebuffer` | **control.** WG forced `ffffffff`; nothing changed |
| 2 | dev `8A52` + plat `8A520000` + `enable-metal` | ❌ reset | — | first hang |
| 3 | dev `8A52`, `-igfxvesa` **kept** | ✅ | `IONDRVFramebuffer` | kext **loaded**, never attached — proves PCI matching works |
| 4 | dev `8A52` only, no plat | ✅ | `IONDRVFramebuffer` | WG supplied `ffffffff`; FB bailed **in probe** |
| — | dev `85A1` (typo / script bug) | ✅ | `IONDRVFramebuffer` | **void.** `85A1` is in no match list |
| 5 | dev `8A52` + plat `FF05` | ❌ reset | — | generic fallback personality |
| 6 | dev `8A5C` | ❌ reset | — | |
| 7 | dev `8A51` | ❌ reset | — | |
| 8 | dev `8A70` | ❌ reset | — | GT1/UHD variant |
| 9 | dev `8A52`, **WhateverGreen disabled** | ❌ reset | — | WG is not implicated |
| 10 | dev `8A52` + `igfxagdc=0` | ❌ reset | — | AGDC is not implicated |

The void run is kept deliberately. See [below](#the-void-run).

## The uniform failure mode

Runs 2 and 5–10 failed **identically**:

- kernel alive and printing verbose text right up to the blackout
- **no kernel panic** — no `.panic` file, despite `debug=0x100`, which holds
  panics on screen
- **no SSH afterwards**, with a static DHCP reservation — the kernel did not
  survive
- spontaneous hardware reset

The last visible console line differed every time
(`DriverKit-IOUserDockChannelSerial`, `AppleKeyStore`, …). **These are routine
messages, not culprits** — they are simply where the console happened to be
when the display died. Do not chase them.

---

## What each run establishes

### Run 1 — the control

`-igfxvesa` removed, **nothing injected**. It booted, and `ig-platform-id`
still read `<ffffffff>`.

Two things follow. First, removing `-igfxvesa` is by itself harmless, so
nothing in runs 2–10 can be attributed to its absence. Second — and this was
not expected — `0xFFFFFFFF` is WhateverGreen's VESA sentinel, and WG applied it
with no prompting. See [WhateverGreen](#whatevergreen-is-a-participant-not-an-observer).

Evidence: [`data/ioreg/igpu-novesa-nospoof.txt`](data/ioreg/igpu-novesa-nospoof.txt)
(`device-id = <409a0000>`, the real `9A40`),
[`data/kextstat/kexts-novesa-nospoof.txt`](data/kextstat/kexts-novesa-nospoof.txt)
(empty — no graphics kext loaded at all).

### Run 3 — the decoupling probe

`device-id` spoofed to `8A52`, but `-igfxvesa` **kept**. The machine survives,
so it can be inspected.

`kextstat` shows `com.apple.driver.AppleIntelICLLPGraphicsFramebuffer (24.0.5)`
**loaded**, while `.Display_boot` is still `IONDRVFramebuffer`.

That single pairing separates three things that are otherwise easy to conflate:

| | |
|---|---|
| PCI match | ✅ succeeds |
| Kext load | ✅ succeeds |
| Framebuffer attach | ❌ never happens |

Evidence: [`data/kextstat/kexts-8A52-keepvesa.txt`](data/kextstat/kexts-8A52-keepvesa.txt),
[`data/ioreg/igpu-8A52-keepvesa.txt`](data/ioreg/igpu-8A52-keepvesa.txt).

### Run 4 — the kext says why, in its own words

`device-id` spoofed to `8A52`, **no** `ig-platform-id` injected, `-igfxvesa`
removed. It booted, and the log captured the rejection:

```
(IOGraphicsFamily) IOG flags 0x3 (0x51)
(AppleIntelICLLPGraphicsFramebuffer) Entry to probe function
(AppleIntelICLLPGraphicsFramebuffer) [IGFB][ERROR][DISPLAY   ] Failing probe: Undefined platform ID
(AppleIntelICLGraphics) [IGPU] Failing probe (-allow3d is NOT set in boot-arg)!
(AppleIntelICLGraphics) [IGPU] Failing probe (-allow3d is NOT set in boot-arg)!
```

Full capture: [`data/ioreg/gfx-minimal.log`](data/ioreg/gfx-minimal.log).

This is the mechanism behind runs 1 and 4 booting safely. With no
`ig-platform-id` injected, WhateverGreen supplies `0xFFFFFFFF`, the framebuffer
reaches `probe()`, finds an undefined platform ID and **declines cleanly**. The
system stays on VESA and stays alive.

Inject a *defined* platform ID and probe succeeds — and then `start()` takes
the machine down. That is the difference between run 4 and runs 5–8.

`kextstat` for this run also shows `AppleIntelICLGraphics (24.0.5)` and
`IOAcceleratorFamily2 (487.4.3)` loaded
([`data/kextstat/kx-minimal.txt`](data/kextstat/kx-minimal.txt)) — loaded, and
declining to probe. **Loading is not attaching.** No accelerator object was
ever created: [`data/ioreg/accel-nub.txt`](data/ioreg/accel-nub.txt) is empty.

> ### ⚠️ The `-allow3d` line is a loose thread, not a finding
>
> `AppleIntelICLGraphics` refusing to probe because `-allow3d` is absent was
> **not investigated**. Nobody re-ran with `-allow3d` set. It may be a gate
> worth opening, or it may be an Apple-internal debug flag that gates nothing
> useful — this project produced no evidence either way, and nothing in the
> conclusions below depends on it.
>
> It is recorded here because it is the only observed lead that sits *above*
> the layer where everything else failed.

### Runs 5–8 — five personalities, one failure

`8A52`, `FF05`, `8A5C`, `8A51`, `8A70`. These describe **different connector,
pipe and DDI configurations** — `8A70` is even a different GT tier (GT1/UHD
rather than Iris Plus). `FF05` is the generic fallback personality.

All five failed identically.

If the hang were caused by a mismatched connector layout — the obvious
hypothesis for a 3:2 1920×1280 panel with no external outputs — five different
layouts would not fail the same way. **Wrong-personality is ruled out.**

### Run 9 — WhateverGreen is not the cause

Same spoof as run 2, with WhateverGreen's `Enabled` flipped to `false`.
Identical hang.

WG's unrecognised-hardware patching is therefore not what kills the machine.
(This is separate from WG's *sentinel* behaviour, which is real and is
described below — WG shapes what the framebuffer receives, but it is not the
thing that hangs.)

### Run 10 — AGDC is not the cause

Same spoof plus `igfxagdc=0`, which disables the Apple Graphics Device Control
handoff. Identical hang. AGDC is not implicated.

---

## The void run

`-Id 85A1` was entered instead of `8A51`. The machine **booted normally**.

`85A1` appears in no `IOPCIPrimaryMatch` list, so no Apple graphics kext could
ever have matched it. Nothing was tested. The run produced a result that looks
exactly like a safe, informative negative — and it means nothing at all.

It is kept in the table because deleting it would misrepresent the method, and
because the trap generalises: **in this experiment, "it booted" is the failure
mode of the apparatus, not a data point.** Every subsequent run had its
injected base64 verified before boot. See
[`METHODOLOGY.md`](METHODOLOGY.md#verify-the-injected-value-before-every-boot).

---

## WhateverGreen is a participant, not an observer

`ig-platform-id` reads `<ffffffff>` even on a boot with `-igfxvesa` removed and
nothing injected (run 1). `0xFFFFFFFF` is WhateverGreen's VESA sentinel.

**WhateverGreen forces VESA on its own, because it does not recognise `9A40`.**

Three consequences, all of which matter to anyone else working on Tiger Lake:

1. **`-igfxvesa` is redundant on this hardware.** WG does it regardless. Anyone
   reporting that removing `-igfxvesa` "did nothing" on a TGL machine is
   observing this, not a broken boot-arg.
2. **WG is in the path of every result**, including the ones that look like
   clean stock-kext behaviour.
3. Unless an explicit `AAPL,ig-platform-id` is injected, the ICLLP framebuffer
   always receives `0xFFFFFFFF` and declines in `probe()` — which is precisely
   what [run 4](#run-4--the-kext-says-why-in-its-own-words) captured.

`-NoWEG` takes WG out of the path as a diagnostic. It also disables WG's
non-graphics patches, so it is a probe, not a destination.

---

## Ground truth: `IOPCIPrimaryMatch`

From `AppleIntelICLLPGraphicsFramebuffer.kext` in Tahoe, verbatim
([`data/icllp-match.txt`](data/icllp-match.txt)):

```
0xff058086  0x8A708086  0x8A718086  0x8A518086  0x8A5C8086
0x8A5D8086  0x8A528086  0x8A538086  0x8A5A8086  0x8A5B8086
```

Ten Ice Lake IDs. **`9A40` is not among them and never will be** — which is why
no Apple graphics kext binds by default, and why a `device-id` spoof is the
only way to get one to try.

### The naming trap

The framebuffer and the Metal driver are **not** named consistently:

| | Bundle |
|---|---|
| Framebuffer | `AppleIntelICLLPGraphicsFramebuffer.kext` — **ICLLP** |
| Metal driver | `AppleIntelICLGraphicsMTLDriver.bundle` — **ICL**, no LP |
| Video accel | `AppleIntelICLLPGraphicsVAME.bundle` — ICLLP again |

`data/icllp-match.txt` preserves the moment this bit: the capture looks for
`AppleIntelICLLPGraphicsMTLDriver.bundle` and gets
`No such file or directory`. The bundle exists; the name is wrong. If you are
scripting against these, check both spellings.

### An earlier draft said to spoof `9A49`. That was wrong.

`9A49` is the real hardware ID of the UP3 Tiger Lake part other researchers
happened to own. It is no more Ice-Lake-compatible than `9A40`, and it is in no
match list. The spoof target must be an ID **from the list above**.

---

Continue to [`README.md`](README.md) for what these results do and do not
establish.
