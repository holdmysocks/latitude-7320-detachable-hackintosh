# Layer 3 crossed: the Ice Lake framebuffer driving a Tiger Lake panel

**Status (2026-10-07): working.** `AppleIntelICLLPGraphicsFramebuffer` 24.0.5 drives the internal eDP panel of
`8086:9A40` on macOS 26.6 (25G72): 1920×1280 @ 60 Hz, panel recognised as built-in, backlight control, display
sleep and wake. No graphics acceleration.

This document is the technical account: what was wrong, how each cause was found, and what fixes it. The run log
is in [`RESULTS.md`](RESULTS.md); raw evidence is in [`data/layer3/`](data/layer3/).

Conventions: **Fact** means read from a binary, a source file, a log or a register snapshot. **Inference** means
an interpretation that the evidence supports but does not prove.

---

## The recipe

Everything is relative to a config that boots on VESA (`-igfxvesa`, no IGPU `DeviceProperties`).

| What | Value |
|---|---|
| WhateverGreen | upstream `0762cec` (1.7.1) + [`WhateverGreen-patches/`](../WhateverGreen-patches/) 0001, 0002, 0003 |
| boot-args | `lilucpu=12 -igfxdvmt -igfxcdc igfxtglmap=0xA83F igfxtglblmax=0xAD9 dc6config=0 -igfxdbeo` (and no `-igfxvesa`) |
| `DeviceProperties` → `PciRoot(0x0)/Pci(0x2,0x0)` | `device-id` = `5A8A0000`, `AAPL,ig-platform-id` = `02005C8A` (0x8A5C0002) |
| `Kernel/Block` | `com.apple.driver.AppleIntelICLGraphics`, `Exclude` |
| ACPI | `SSDT-PNLF` with `_UID` 15 and `SSDT-DOSI`, both enabled |
| Kernel/Emulate | `Cpuid1Data` Ice Lake spoof (already part of the base config) |

The committed [`EFI/OC/config.plist`](../EFI/OC/config.plist) is exactly this.
`tools/mac/make-experiment.py <vesa-config> <out> R` regenerates it.

What each piece does:

| Piece | Fixes | Section |
|---|---|---|
| `lilucpu=12` + `-igfxdvmt` | platform reset when the driver starts | [1](#1-the-reset-stolen-memory-computed-as-4-gb) |
| platform id `0x8A5C0002` | driver started with no platform data | [2](#2-0x8a520000-does-not-exist-in-tahoe) |
| `igfxtglmap` `0x02` | eDP link training fails at phase 1 | [3](#3-link-training-registers-tiger-lake-moved) |
| `igfxtglmap` `0x04` `0x08` `0x10` | DDI select, clock select and PLL in the Tiger Lake encoding/location | [3](#3-link-training-registers-tiger-lake-moved) |
| `igfxtglmap` `0x20` | link drops, or the machine freezes, right after training | [4](#4-the-driver-removes-the-transcoders-clock) |
| `igfxtglmap` `0x01` `0x800` | panel treated as an external display; panic on display wake | [5](#5-built-in-panel-and-display-wake-the-edp-transcoder-block) |
| `igfxtglmap` `0x8000`, `igfxtglblmax=0xAD9`, `SSDT-PNLF` `_UID` 15 | black panel (zero duty), then wrong brightness range | [6](#6-backlight) |
| patch 0003 leaves the transcoder alone after the port is disabled | hard freeze at every display sleep | [7](#7-the-display-sleep-freeze) |
| `dc6config=0` | the driver does not load Ice Lake DMC firmware into a Tiger Lake chip. **Not needed for anything demonstrated here** (display sleep passes without it); kept as the safer default | [7](#7-the-display-sleep-freeze) |
| `-igfxcdc`, `-igfxdbeo` | stock WhateverGreen Ice Lake fixes used by the other Tiger Lake reports; **not isolated here** | — |
| `Kernel/Block` | keeps the accelerator from attaching; **not isolated here** (the kext still appears in `kextstat`) | — |

`igfxtglmap` is a feature mask implemented by patch 0003. The full bit list is in
[`WhateverGreen-patches/README.md`](../WhateverGreen-patches/README.md).

---

## 1. The reset: stolen memory computed as 4 GB

**Symptom.** With any defined platform id, the machine reset the moment the framebuffer started. No panic, no log.
This is the "wall" of runs 2 and 5–10.

**Fact.** `AppleIntelFramebufferController::FBMemMgr_Init` computes the DVMT pre-allocated size from the GGC
register as `(GGC << 17) & 0xFE000000`, i.e. `GMS × 32 MB`. In the Tahoe binary:

```
movl  $0x50, %esi ; callq extendedConfigRead16
shll  $0x11, %eax
andl  $0xfe000000, %eax
movl  %eax, 0xd9c(%rbx)
```

Tiger Lake firmware defaults to 60 MB, which is encoded as GMS `0xFE`. The formula yields 4032 MB.

**Fact.** WhateverGreen has a fix for exactly this (`DVMTCalcFix`, `-igfxdvmt`), but it only becomes available in
WhateverGreen's *Ice Lake* code path. Lilu detects this CPU as Tiger Lake, WhateverGreen has no Tiger Lake case, so
in every earlier run it did nothing to the framebuffer at all: no DVMT fix, no connector patching, no MMIO hooks.

**Fact.** Lilu's `lilucpu=N` boot argument overrides the detected generation for every plugin. `12` is Ice Lake.

**Result.** With `lilucpu=12 -igfxdvmt` and a valid platform id (run A), `start()` returned for the first time and
macOS ran normally behind a black panel.

**Inference.** A memory manager that believes it owns 4 GB of stolen memory on a machine with 60 MB hands out
addresses outside graphics memory, which is what took the platform down. The driver still logs
`Insufficient stolen memory` (60 MB against a 64 MB table entry); it is not fatal.

## 2. `0x8A520000` does not exist in Tahoe

**Fact.** The platform table (`_gPlatformInformationList`) is built at load time by
`__GLOBAL__sub_I_AppleIntelOSInfoList.cpp`. The ids in Tahoe 26.6 are:

```
8A510000 8A510001 8A510002   8A520001 8A520002   8A530001 8A530002   8A5A0001   8A5B0001
8A5C0000 8A5C0001 8A5C0002   8A5D0000 8A5D0001   8A700000 8A700001   8A710000 8A710001   FF050000
```

`0x8A520000`, `0x8A530000`, `0x8A5A0000` and `0x8A5B0000` from older lists are gone.

**Fact.** `probe()` only rejects `0xFFFFFFFF` (`Failing probe: Undefined platform ID`). It does not look the id up.
The lookup happens later, in `start()`.

**Consequence.** Runs 2, 9 and 10 injected `0x8A520000` and so started the driver with no platform data. They say
nothing about register access. Runs 6–8 used ids that exist and reset because of [section 1](#1-the-reset-stolen-memory-computed-as-4-gb).

## 3. Link training: registers Tiger Lake moved

**Symptom (run A).** The driver's own log, which survives in the unified log even after a hard power-off:
`Lighting up eDP` → `Fast link training failed` → `Phase 1 of link training failed` →
`Modeset is unsuccessful. Disabling display`. AUX worked (`DPCD_REV: 1.4`, 2 lanes, 2.7 Gbps).

**Fact.** Register use in the Tahoe binary against Linux i915 v6.6 `i915_reg.h`:

| What | Apple driver (Ice Lake) | Tiger Lake |
|---|---|---|
| DP_TP_CTL / DP_TP_STATUS | `0x64040` / `0x64044`, per port | `0x60540` / `0x60544`, per transcoder |
| DDI_DP_COMP_CTL | `0x640F0…` | `0x605F0…` |
| eDP transcoder | own block `0x6F000`, config `0x7F008` | none; eDP uses transcoder A (`0x60000`, `0x70008`) |
| TRANS_DDI_FUNC_CTL DDI select | `port << 28` | `(port + 1) << 27` |
| TRANS_CLK_SEL | `(port + 1) << 29`; unused for the eDP transcoder | `(port + 1) << 28`; required for eDP too |
| Combo DPLL0/1 CFGCR0/1 | `0x164000/04`, `0x164080/84` | `0x164284/88`, `0x16428C/90` |
| DPLL DCO fraction, 38.4 MHz reference | table value (`0x01C001A5` for 2.7 G) | half of it (`0x00E001A5`) |
| Enable order | DP_TP_CTL, then the transcoder | TRANS_CLK_SEL and the DDI select first |

The driver never references any address in the right-hand column. With DP_TP_CTL written to an address Tiger Lake
does not decode, no training pattern is transmitted.

Unchanged between the two generations for this panel: DDI_BUF_CTL, DDI_AUX_CTL, DPLL_ENABLE, DPCLKA_CFGCR0, combo
PHY registers, PP_CONTROL/STATUS, PCH backlight PWM, CDCLK, DBUF, pipe and plane registers.

**Fix.** Patch 0003 translates these accesses inside WhateverGreen's existing `ReadRegister32`/`WriteRegister32`
hooks. Before the driver enables DP_TP_CTL on DDI A it also sets TRANS_CLK_SEL_A and the DDI select in
TRANS_DDI_FUNC_CTL_A (i915 `tgl_ddi_pre_enable_dp` steps 7.a–7.b).

**Result (run C).** `Clock recovery complete`, `Link Training successful`.

**Fact.** A register snapshot later showed the firmware's own DPLL0 value is `0x00E001A5`: exactly the halved
fraction the patch writes.

## 4. The driver removes the transcoder's clock

**Symptom.** Run C: `Link loss occurred on DDI0` 17 ms after the pipe was enabled, then a retrain loop.
Runs D and E (eDP block mapped as well): black, frozen, nothing logged.

**Fact.** `AppleIntelFramebufferController::SetupParams` computes the TRANS_CLK_SEL value as `0` when the port's DDI
index is 0 (a panel on DDI A) and logs it: `TRANS_CLK_SEL = 0x0`. `LightUpEDP` calls `AppleIntelPort::linkTraining`
and, on success, immediately writes that value to `0x46140 + 4 × pipe`.

On Ice Lake that is harmless: the eDP transcoder has no clock select. On Tiger Lake the panel is on transcoder A and
`0` removes its clock.

**Fact.** `hwWaitForVBlank` returns at once when the transcoder's config register reads as disabled. Otherwise it
reaches `TimeCriticalDelayTillVBL`, which loops on the frame counter and scanline with no iteration limit.

**Inference.** In run C the firmware-programmed transcoder lost its clock and the sink lost the stream. In D and E
the transcoder read as enabled but never produced a frame, and the unbounded wait froze the machine.

**Fix.** While DP_TP_CTL of DDI A is enabled, a driver write of `0` to TRANS_CLK_SEL_A becomes "DDI A".

**Result (run F).** Link up and stable, modeset complete, no link loss.

## 5. Built-in panel and display wake: the eDP transcoder block

**Symptom.** With the eDP block unmapped the display worked (run K), but macOS saw the panel as an external
display on framebuffer 1 (`FB1: Invalid port type`, no built-in flag), and waking the display panicked:

```
"[IGFB][PANIC][POWER_WEL] Enable powerwell PG1 called without enabling display engine"
enablePowerWellPG ← LightUpEDP ← hwSetMode ← prepareToEnterWake ← setFramebufferPowerState
```

**Fact.** `probeBootPipe` reads TRANS_DDI_FUNC_CTL of the eDP transcoder first, then A, B, C. On Tiger Lake the eDP
address reads as nothing, so the firmware's transcoder A is taken as a DisplayPort output on the next framebuffer.

**Fact.** The driver uses the eDP block for any panel on DDI A (`hwUpdateRegCache`, `hwWaitForVBlank`,
`populateFBState`, `prepareToEnterWake`). Unmapped, its "disable" never reaches the hardware.

**Fix.** Map the stream registers of the eDP block onto transcoder A from the first access: `0x6F000–0x6F0FF`
(timings, M/N), `0x6F400–0x6F41F` (FUNC_CTL, MSA), `0x7F000–0x7F0FF` (config). The PSR, VRR and DIP registers in that
block are left unmapped.

**Result (run M).** `FB0: Boot pipe found - DDI0, pipe A`; connector type LVDS, `built-in`, `AppleBacklightDisplay`
attached, "Connection Type: Internal". The driver adopts the firmware's mode without retraining. One display sleep
and wake passed on this run: the driver logs `Timeout powering ON the panel` (2 s) and AUX NACKs at DPCD `0x4E0`, then
retrains successfully. That single pass was luck: display sleep froze the machine on most later boots until the fault
in [section 7](#7-the-display-sleep-freeze) was removed.

**Inference.** The panic in run K came from the driver's and the hardware's state diverging across the power
transition. It did not recur once the block was mapped; the exact sequence was not reconstructed.

## 6. Backlight

Three separate faults, found in this order.

**a. Zero duty (runs F, F2: everything running, panel black).** A register snapshot taken three minutes after the
modeset, next to the firmware's values:

| Register | Firmware | Driver |
|---|---|---|
| BXT_BLC_PWM_DUTY1 `0xC8258` | `0x0000BC3C` (50 %) | **`0x00000000`** |
| BXT_BLC_PWM_FREQ1 `0xC8254` | `0x00017700` | `0x00017700` |
| BLC_PWM_CTL `0xC8250`, PP_STATUS, PP_CONTROL | enabled, panel on | same |
| Transcoder A, DDI A, DPLL0, link, pipe A frame counter, plane 1A | running | running |

**Fact.** `disableDisplay` writes the duty register during every modeset; `LightUpEDP` restores only the control and
frequency registers; `hwSetBacklight`, the other writer, is called by the backlight display object, which did not
exist yet. WhateverGreen's `-igfxblr` does not help: it rescales, and zero stays zero.

**b. Wrong range (`_UID` 15).** `hwSetBacklight(level)` computes `duty = level × period / 65535`. `SSDT-PNLF` with
`_UID` 15 selects AppleBacklight profile `F15Txxxx`, whose table ends at 2777, so full brightness was about 4 % duty.
`_UID` 19 (`F19Txxxx`) spans the 16-bit range and was used for a while; the committed configuration keeps `_UID` 15
and lets the patch rescale instead (`igfxtglblmax=0xAD9`, the top of the `F15T` table).

**c. Wrong period.** `AppleIntelFramebufferController::start` sets its PWM period to `0x56CE` or `0x4571` from
SFUSE_STRAP (`0xC2014`) bit 8. The firmware's period is `0x17700`. When the driver adopts the firmware's mode it never
rewrites the frequency register, so duty values on the driver's scale reached a register on the firmware's scale:
full brightness was 23 %.

**Fix.** `igfxtglmap` `0x8000`: keep the firmware's period and rescale every duty write to it. The scale is
`firmware period / (driver period × igfxtglblmax / 65535)`, the driver period taken from the same strap. A zero duty
is passed through (the driver writes it before powering the panel down), and because `LightUpEDP` does not restore
it, the patch writes the last level back when the driver enables the PWM again.

**Result.** Full brightness range through the Displays slider.

## 7. The display sleep freeze

**Symptom.** On most boots, any display power-off (`pmset displaysleepnow`, the idle timer, closing the lid) froze
the whole machine: no panic, no log, hard power-off needed. Within one boot the outcome never changed: a boot that
survived one cycle survived every later one.

**What it was not.** A day went into things that only shifted the odds, each of which looked like the cause for a
few runs: `pmset` settings, `SSDT-PNLF` `_UID` 19, the brightness level (100 % froze, 97 % and below did not, on one
kext revision), the backlight duty value, `BrightnessKeys.kext`, `SSDT-DOSI`, pacing the driver's power-down, the
"first cycle after boot". None survived a clean retest.

**How it was found.** Patch 0003 gained a diagnostic (`igfxtglmap` `0x10000`): once armed, every register access the
driver makes goes into a ring that a kernel thread writes to `/Users/Shared/tgl-trace.bin` with `IO_SYNC`, and the
hook holds the driver until each write access is on disk. After a freeze the file holds the driver's last accesses.
A second mode (`0x40000`) records without holding the driver, so its timing is not disturbed.

**Fact.** Six traces, with and without `dc6config=0`, held back (milliseconds between steps) and at full speed
(microseconds), end at the same entry. The driver's power-down sequence is complete up to the port:

```
W BLC_PWM_DUTY 0 · W BLC_PWM_CTL 0 · W PP_CONTROL 0x63 · planes off · pipe interrupts off
W PIPE_EDP_CONF 0x40000024 · W TRANS_DDI_FUNC_CTL_EDP 0x02000002 · W TRANS_CLK_SEL_A 0
W DDI_BUF_CTL_A 0x00000003 · W DP_TP_CTL_A 0x00040300
```

and then the last thing on disk is a marker inside **patch 0003's own code**: the clean-up that feature `0x20` ran
after the driver disabled DP_TP_CTL. That clean-up cleared the DDI select in `TRANS_DDI_FUNC_CTL_A` and then read
and cleared `TRANS_CLK_SEL_A`. The traces end after the FUNC_CTL write, at the read of `TRANS_CLK_SEL_A`; with the
transcoder reported off (`TRANS_CONF_A = 0x24`), and also after the clear of `TRANS_CLK_SEL_A` had been removed.

**Fix.** The clean-up is gone. After the port is disabled the patch touches nothing; `prepareTranscoderA` programs
both registers again before the next enable.

**Result (run R).** Display sleep and wake at full brightness: 4 of 4 on the first build without the clean-up, 7 of 7
and 6 of 6 on two clean boots of the committed configuration, including the first cycle after boot and 45–60 s off.
Lid close and open: display off and back on, on both builds.

**`dc6config=0` is not part of the fix.** With the clean-up gone and the boot-arg removed (run Q on the final build),
display sleep at full brightness passed 15 of 15 over three boots. With the clean-up still present it had changed the
outcome only while the blocking trace was running. It stays in the committed configuration because the firmware it
keeps out is for a different chip, and because both bad retrains seen so far (below) happened without it: 2 in about
41 wakes without, 0 in about 22 with. That difference is not significant.

**Not established.** Why that access hangs the machine on some boots and not others.

---

## Brightness keys

The keys do not reach macOS as key codes. The EC raises query `_Q66`, which runs `NEVT` → `SMIE` → `SMEE`; `SMEE` asks
SMM which hotkey it was and calls `EV6` → `GFX0.BRT6` → `Notify (LCD, 0x86/0x87)`, but only inside
`If (\_SB.OSID () >= 0x20)`. `OSID` is a Dell-specific OS check, separate from `OSYS`: it caches its answer in
`\_SB.ACOS` / `\_SB.ACSE` from `_OSI ("Windows …")`, and under macOS the answer is 1 ("legacy OS").

Two things are needed:

- `BrightnessKeys.kext`, which turns the notifications on `LCD` into brightness key events.
- [`SSDT-DOSI`](../ACPI-sources/SSDT-DOSI.dsl), which presets `ACOS = 0x20`, `ACSE = 0` on Darwin. `0x20` is what the
  firmware computes for Windows Vista and the smallest value that passes the check; `ACSE` (the Windows 8+ flag) stays
  0, so the branches that test `OIDE ()` behave as before.

**When the value is set matters.** The firmware also reports it to SMM (`\_SB._INI` → `EV4` → `SOS0` → `STOS`) and to
the EC (`ECS2` in the EC's `_REG`). The first version of the table set the value from a device's `_INI`, which runs
after `\_SB._INI`: `OSID ()` then returned `0x20`, but SMM had already been told "legacy" and the keys stayed dead
(run P). The working version (run P2) sets it in module-level code, which runs when the table is loaded, and its `_INI`
repeats the assignment and calls `STOS ()` again.

The same check selects the firmware's lid path (`GLID` instead of `ILID`).

## What does not work

| | State |
|---|---|
| Graphics acceleration | None usable. The accelerator starts and, with shader translation, draws; see [`LAYER4.md`](LAYER4.md). |
| System sleep | The firmware offers no S3: the DSDT has `Name (SS3, Zero)` and defines `_S3` only `If (SS3)`. macOS's attempt hangs ("Darkwake Entry Failure"). Use `pmset -a disablesleep 1`. Hibernation (S4) is offered and untested. |
| Lid close | With system sleep disabled nothing turns the panel off; the lid switch itself works (`AppleACPILid`). `tools/mac/lidwatch.sh` puts the display to sleep on close; opening the lid wakes it. `tools/mac/install-lidwatch.sh` installs it as a login item. |
| External displays | Untested. Type-C ports use the Dekel PHY on Tiger Lake; the driver has MG PHY code only. |

Still logged by the driver on a working boot, apparently harmless: `Insufficient stolen memory`,
`EFI should not enable PG4 power well - overriding`, `EFI using a different backlight frequency`,
`TCON: Aux not ready at HW` / `BAN_DPCD_0x0_EXPECTED failed` (the panel is not an Apple one), and one
`Display Pipe Underrun` on pipe A at boot.

## Open items

- **Hibernation** as the only real suspend this firmware has.
- **Hardware cursor.** On some boots the cursor is drawn doubled and coarse (the cursor plane; screenshots do not
  show it). Not tied to any setting tried, and a display sleep/wake does not clear it.
- **Bad retrains.** Twice the panel came back from display sleep as vertical colour bars; the next sleep/wake cycle
  (or closing and opening the lid) fixed it. The driver's log for such a wake is identical, message for message, to
  a good one, including `Link Training successful`, so it cannot be detected there. Both were without `dc6config=0`.
  The driver logs `Timeout powering ON the panel` and `Fast link training failed` on every wake.
- **Acceleration.** See [`LAYER4.md`](LAYER4.md). The `Kernel/Block` entry in the recipe does nothing: the kext is
  in the system kernel collection, and it stays out only because it refuses this chip's PCI revision.

## Things that are specific to this machine and cost time

- **Writing NVRAM from a kext resets the machine.** Three runs (B, F3, F4) reset at the instant the patch published
  diagnostics through Lilu's `NVStorage`, from inside the register hook and from a separate kernel thread alike. A file
  written with Lilu's `FileIO` from a thread call is safe.
- **Third-party kext `IOLog` output never reaches the unified log on Tahoe.** Apple's `[IGFB]` lines do, and they
  survive a hard power-off if the boot lasted about a minute.
- **A log file of 0 bytes** in `/var/db/diagnostics/Persist` for a boot means the kernel froze or died in the first
  30–60 seconds.
- **Panic reports only appeared once the driver was running.** Every earlier "reset" left nothing.

## Prior art

Two reports of the Ice Lake framebuffer attaching on Tiger Lake, both with a WhateverGreen that enabled the DVMT fix
for Tiger Lake: `lshbluesky` on `9A49` (Catalina–Monterey, panel black after boot) and a Lenovo `9A78` on Ventura
(picture with wrong colours and cursor). Neither reset. That observation is what pointed at
[section 1](#1-the-reset-stolen-memory-computed-as-4-gb). On this machine colours and cursor are correct.
