# Results

Two phases. Runs 0–10 are the original configuration-only experiments, which ended in a reset every time a platform
id was injected. Runs A–N (2026-10-07) found why and got the framebuffer working. What it all means is in
[`LAYER3.md`](LAYER3.md); method and controls are in [`METHODOLOGY.md`](METHODOLOGY.md).

Hardware: Intel i5-1140G7 (TGL-UP4), Iris Xe 80 EU, **`8086:9A40`**, subsystem `1028:0A45`. macOS 26 Tahoe (26.6,
25G72 for runs A–N), OpenCore 1.0.7.

> **Read runs 0–10 with two corrections in mind.** (1) WhateverGreen 1.7.0 has no Tiger Lake case, so it did
> nothing to the framebuffer in any of them, including its DVMT fix; every run with a defined platform id therefore
> started the driver believing it had 4 GB of stolen memory. (2) `0x8A520000` is not in Tahoe's platform table, so
> runs 2, 9 and 10 started the driver with no platform data at all. The verdicts below are annotated accordingly.

---

## Phase 2: runs A–N (2026-10-07)

All on device-id `8A5A`, platform id `0x8A5C0002`, `lilucpu=12 -igfxdvmt -igfxcdc`, accelerator excluded.
`igfxtglmap` is the feature mask of patch 0003 ([bit list](../WhateverGreen-patches/README.md)).

| Run | Change | Outcome | What it showed |
|---|---|---|---|
| A | WhateverGreen in Ice Lake mode (`lilucpu=12`), DVMT fix, valid platform id | **no reset**; black, alive | `start()` returns. Driver log: eDP link training fails at phase 1 |
| B | A + first register map: every translation, plus diagnostics written to registry/NVRAM/IOLog at the first register access | reset ×3, nothing logged | later traced to the NVRAM write, not to the translation |
| C | `igfxtglmap=0x3E`: DP_TP, encodings, DPLL, pre-enable writes; eDP block unmapped; no side effects | black, alive | **`Link Training successful`**, then `Link loss` 17 ms after pipe enable |
| D | `0x43F`: C + whole eDP block (reads mapped after the driver's first write) | black, frozen, nothing logged | |
| E | `0xC3F`: D with only the eDP stream registers | black, frozen, nothing logged | not PSR. Cause of C, D, E found by disassembly: the driver writes TRANS_CLK_SEL = 0 after training |
| F | `0x3E` + clock-select fix | black, alive | link up and stable, modeset complete |
| F2 | F + `-igfxblr -igfxdbeo` | black, alive | no change |
| F3 | F2 + register snapshot published to NVRAM from the hook, 60 s after the modeset | self-reboot at ~80 s | |
| F4 | F3 with the publish moved to a kernel thread call | self-reboot at ~80 s | not the calling context: the NVRAM write itself |
| F5 | snapshot written to a file instead | black, alive for 4 min | **snapshot: backlight duty 0, everything else running** |
| K | `0x603E`: F + keep the firmware's backlight values | **picture** | first working display. Panel on FB1 as an external display; display wake panics |
| M | `0xA83F` + `SSDT-PNLF`: eDP stream registers mapped from the start, rescaling backlight | picture | built-in panel on FB0, AppleBacklight, display sleep/wake works. Brightness range far too low (`_UID` 15) |
| — | `SSDT-PNLF` `_UID` 19 | picture | brighter; maximum still 23 % (driver's PWM period differs from the firmware's) |
| N | M + backlight scale from SFUSE_STRAP + `BrightnessKeys.kext` | picture | **full brightness range.** Brightness keys still dead (firmware does not send the events to macOS) |
| P | N + `SSDT-DOSI` rev. 1: `\_SB.ACOS = 0x20` set from a device `_INI` | picture | keys still dead: SMM was told the OS type before the `_INI` ran |
| P2 | N + `SSDT-DOSI` rev. 2: set at table load, `STOS ()` repeated | picture | **brightness keys work.** Display sleep, not retested since M, **hard-freezes the machine** |
| — | a day of display-sleep runs on P2, N, M and variants (`pmset` settings, `_UID`, kext revisions, brightness 5–100 %) | freeze on most boots | nothing reproducible: each suspect shifted the odds and failed a clean retest. Constant within a boot |
| Q | P2 with `_UID` 15 + `igfxtglblmax=0xAD9` (scaling moved into the patch) | picture | full brightness without `_UID` 19; display sleep still freezes |
| QT | Q + on-disk register trace (`0x10000`) | freeze ×5 | **all traces end in patch 0003's clean-up after the driver disables DP_TP_CTL** |
| QT + `dc6config=0` | no Ice Lake DMC firmware | survived ×5 (trace running) | looked like the fix |
| R′, S | the same without the trace; with a paced power-down | freeze | it was not |
| RT | no-wait trace (`0x40000`), `dc6config=0` | freeze | same last entry at full speed: the clean-up itself, not a timer |
| **R** | clean-up removed from patch 0003; Q + `dc6config=0` | picture | **display sleep/wake 7/7 and 6/6 at full brightness on clean boots; lid close and open work** |
| Q (final build) | R without `dc6config=0`, three boots | picture | display sleep/wake 15/15: the boot-arg is not part of the fix. One wake came back as colour bars |

Run R is the committed configuration. Evidence: [`data/layer3/`](data/layer3/) (driver logs for A, C, F, F2, K, M;
register snapshots for F5 and K; the panic report from K's display wake; the register traces of the display-sleep
freeze; the run log).

---

## Phase 1: runs 0–10

## The table

| # | Configuration | Boot | Framebuffer | Verdict |
|---|---|---|---|---|
| 0 | baseline, `-igfxvesa` | ✅ | `IONDRVFramebuffer` | reference |
| 1 | `-igfxvesa` removed, nothing injected | ✅ | `IONDRVFramebuffer` | **control.** `ffffffff` (from Lilu) anyway; nothing changed |
| 2 | dev `8A52` + plat `8A520000` + `enable-metal` | ❌ reset | — | first hang. **Invalid:** `8A520000` is not in Tahoe's table |
| 3 | dev `8A52`, `-igfxvesa` **kept** | ✅ | `IONDRVFramebuffer` | kext **loaded**, never attached — proves PCI matching works |
| 4 | dev `8A52` only, no plat | ✅ | `IONDRVFramebuffer` | Lilu supplied `ffffffff`; FB bailed **in probe** |
| — | dev `85A1` (typo / script bug) | ✅ | `IONDRVFramebuffer` | **void.** `85A1` is in no match list |
| 5 | dev `8A52` + plat `FF05` | ❌ reset | — | generic fallback personality. Reset = stolen-memory bug |
| 6 | dev `8A5C` | ❌ reset | — | stolen-memory bug |
| 7 | dev `8A51` | ❌ reset | — | stolen-memory bug |
| 8 | dev `8A70` | ❌ reset | — | GT1/UHD variant. Stolen-memory bug |
| 9 | dev `8A52`, **WhateverGreen disabled** | ❌ reset | — | **Invalid** (`8A520000`). WG was inert in every run anyway |
| 10 | dev `8A52` + `igfxagdc=0` | ❌ reset | — | **Invalid** (`8A520000`) |

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
nothing in runs 2–10 can be attributed to its absence. Second, `0xFFFFFFFF` is the VESA
platform id and it is applied with no prompting. See [where it comes from](#where-0xffffffff-comes-from).

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
`ig-platform-id` injected, Lilu supplies `0xFFFFFFFF`, the framebuffer
reaches `probe()`, finds an undefined platform ID and **declines cleanly**. The
system stays on VESA and stays alive.

Inject a *defined* platform ID and probe succeeds, and `start()` runs. Without the DVMT fix that resets the
machine. That is the difference between run 4 and runs 5–8.

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

`8A52`/`FF05`, `8A5C`, `8A51`, `8A70`. All reset identically.

At the time this was read as "not a connector-layout problem", which is true, and as "the display engine is being
programmed wrongly", which is not what these runs show. All of them started the driver with WhateverGreen's DVMT fix
unavailable, so `FBMemMgr_Init` computed 4032 MB of stolen memory from the firmware's 60 MB. That is what reset the
machine; see [`LAYER3.md`](LAYER3.md#1-the-reset-stolen-memory-computed-as-4-gb).

### Runs 9 and 10 — void

Both used `0x8A520000`, which Tahoe's driver has no table entry for
([`LAYER3.md`](LAYER3.md#2-0x8a520000-does-not-exist-in-tahoe)). Run 9 additionally "disabled" a WhateverGreen that
was not doing anything to the framebuffer in the first place. Neither supports the conclusions originally drawn from
them ("WhateverGreen is not implicated", "AGDC is not implicated").

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

## Where `0xFFFFFFFF` comes from

`ig-platform-id` reads `<ffffffff>` even on a boot with `-igfxvesa` removed and nothing injected (run 1).

The value comes from **Lilu**: `DeviceInfo` falls back to the VESA platform id for CPU generations it has no default
for, and WhateverGreen publishes it as the property. WhateverGreen 1.7.0 itself has no Tiger Lake case in
`IGFX::init()`, so on this machine it never selects a framebuffer kext to patch.

Consequences:

1. **`-igfxvesa` is redundant on an unpatched setup.** With nothing injected the framebuffer always receives
   `0xFFFFFFFF` and declines in `probe()`, which is what [run 4](#run-4--the-kext-says-why-in-its-own-words) captured.
2. **No WhateverGreen framebuffer feature did anything in runs 0–10**: connector patches, `-igfxdvmt`, `-igfxcdc`, the
   MMIO hooks. `lilucpu=12` is what makes them available.

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

Continue to [`LAYER3.md`](LAYER3.md) for what the results establish.
