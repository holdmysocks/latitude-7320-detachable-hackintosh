# Iris Xe (Gen12 / `8086:9A40`) on macOS: the display path

**Status (2026-10-07): the framebuffer works.** Apple's `AppleIntelICLLPGraphicsFramebuffer` drives the internal
panel of `9A40` on macOS 26.6: native resolution, built-in display, backlight, display sleep and wake.
**Graphics acceleration is not working and has not been attempted.**

- [`LAYER3.md`](LAYER3.md) — how it was done: every cause, the evidence, the fix
- [`RESULTS.md`](RESULTS.md) — every run, including the ones that tested nothing
- [`METHODOLOGY.md`](METHODOLOGY.md) — controls, and the measurement traps
- [`data/`](data/) — the raw dumps, scrubbed but not edited
- [`../WhateverGreen-patches/`](../WhateverGreen-patches/) — the three patches

---

## Where things stand

| Layer | Component | Status on `9A40` |
|---|---|---|
| 1. PCI match | IOKit `IOPCIPrimaryMatch` | ✅ with an Ice Lake `device-id` |
| 2. Kext load | kext pulled into memory | ✅ |
| 3. Framebuffer | `AppleIntelICLLPGraphicsFramebuffer::start()`, modeset, link, backlight | ✅ **works**, with a patched WhateverGreen |
| 4. Accelerator match | `AppleIntelICLGraphics` / Metal driver | **not attempted** |
| 5. Command submission | Gen12 command streams | **not attempted** |

## ⚠️ Layers 4 and 5 are still untested

The widely repeated assumption about Iris Xe on macOS is that the **shader ISA** is the blocker: Apple's Metal driver
is compiled for Gen11 EU dispatch and command-streamer encodings, Xe-LP changed both.

That may well be correct. **This project has produced no evidence about it.** The accelerator kext is deliberately
kept from attaching (`Kernel/Block`), and nothing has been tried above the framebuffer. If you read anything here as
confirming or refuting the ISA hypothesis, that is a misreading.

## What it took

Six things were wrong. None of them is a connector-layout problem and none can be fixed from `config.plist` alone.

1. **Stolen memory computed as 4 GB.** The driver misreads the Tiger Lake default of 60 MB. WhateverGreen has the
   fix, but only on its Ice Lake path, which a Tiger Lake CPU never reaches. `lilucpu=12` gets it there. This was the
   reset that looked like a wall.
2. **Platform id `0x8A520000` no longer exists** in Tahoe's driver, and `probe()` does not check.
3. **Link training control moved** from a per-port register to a per-transcoder one, along with the DPLL config
   registers and two field encodings.
4. **The driver writes "no clock"** to the transcoder clock select right after training, which is harmless on Ice
   Lake and fatal on Tiger Lake.
5. **Tiger Lake has no eDP transcoder.** The driver's eDP register block has to be mapped onto transcoder A for the
   panel to be recognised as built-in and for display wake to work.
6. **Backlight**: the driver zeroes the PWM duty on every modeset, assumes its own PWM period, and needs an
   AppleBacklight profile with a 16-bit range.

Details and evidence for each: [`LAYER3.md`](LAYER3.md).

## Corrections to what this document used to say

The first version of this write-up (eleven runs, concluded as a negative result) drew several conclusions that
turned out to be wrong. They are listed here so nobody inherits them.

| Earlier claim | What is actually true |
|---|---|
| "WhateverGreen is not implicated" (run 9) | WhateverGreen never touched the framebuffer in *any* of the eleven runs: it has no Tiger Lake case. Disabling it changed nothing because it was doing nothing. Its Ice Lake fixes are in fact required. |
| "WhateverGreen forces `ig-platform-id = 0xFFFFFFFF`" | The value comes from **Lilu**'s `DeviceInfo`, which falls back to the VESA id for generations it has no default for. WhateverGreen only publishes it. |
| "Five personalities fail identically, so it is not the platform id" | The conclusion happens to hold, but the runs with `0x8A520000` were invalid (the id is not in Tahoe's table), and the others reset because of the stolen-memory bug, not because of display registers. |
| "The failure is Gen11 register offsets written into Xe-LP silicon" | Wrong for the reset. Register differences exist, but they cause a failed link training and a black panel, not a platform reset. |
| "No panic, so the kernel did not survive" | Correct for those runs. But the same symptom was later produced by writing NVRAM from a kext, so "silent reset" is not specific to graphics on this machine. |
| "Step 3 needs a hardware debugger or blind trial and error" | The driver logs its own modeset in detail through `os_log`, and those lines survive a hard power-off. Once the reset was gone, that log was the debugger. |

Still true from the original write-up: PCI matching works with any id from the list below; with no platform id
injected the framebuffer declines in `probe()` and the machine stays on VESA; `-igfxvesa` is redundant on an
unpatched setup.

## Ground truth: `IOPCIPrimaryMatch`

From `AppleIntelICLLPGraphicsFramebuffer.kext` in Tahoe, verbatim:

```
0xff058086  0x8A708086  0x8A718086  0x8A518086  0x8A5C8086
0x8A5D8086  0x8A528086  0x8A538086  0x8A5A8086  0x8A5B8086
```

`9A40` is not among them, so a `device-id` spoof is required. This project uses `8A5A` with platform id
`0x8A5C0002`. The platform ids that exist in Tahoe are listed in [`LAYER3.md`](LAYER3.md#2-0x8a520000-does-not-exist-in-tahoe).

**The naming trap:** the framebuffer is `AppleIntelICLLPGraphicsFramebuffer.kext` (**ICLLP**) but the accelerator is
`AppleIntelICLGraphics.kext` and the Metal driver `AppleIntelICLGraphicsMTLDriver.bundle` (**ICL**, no LP).

## Prior art

- `lshbluesky` got the framebuffer to attach on `9A49` by patching WhateverGreen for Tiger Lake, on Catalina to
  Monterey, with the internal panel black after boot, then stopped at acceleration.
- A Lenovo IdeaPad 3 (`9A78`, Ventura) report on InsanelyMac used that fork and got a picture with oversaturated
  colours and a corrupted cursor.

Neither machine reset, and both had the DVMT fix available. That is what pointed at the stolen-memory bug here.
Nobody has reported acceleration on Tiger Lake.

## Summary for citation

- **Hardware:** i5-1140G7, TGL-UP4, Iris Xe 80 EU, `8086:9A40`, subsystem `1028:0A45`, 1920×1280 eDP on DDI A
- **Software:** macOS 26.6 (25G72), OpenCore 1.0.7, Lilu 1.7.2, WhateverGreen 1.7.1 (`0762cec`) + three patches,
  `AppleIntelICLLPGraphicsFramebuffer` 24.0.5
- **Result:** the Ice Lake framebuffer drives the Tiger Lake internal panel: modeset, link, built-in display,
  backlight, display sleep/wake. Colours and cursor are correct.
- **Method:** one change per boot from a known-good config; the driver's own `os_log` output and register snapshots
  written to disk as the feedback channel; every cause confirmed by disassembly of the Tahoe binary against Linux i915
- **Not established:** anything about acceleration (layers 4–5), system sleep, external displays.
