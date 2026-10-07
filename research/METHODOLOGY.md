# Methodology

How the runs in [`RESULTS.md`](RESULTS.md) were controlled, what was not controlled, and the
measurement traps. The first part describes phase 1 (runs 0–10); [phase 2](#phase-2-runs-an-what-changed-in-the-method)
is at the end.

---

## Design

**Every run rebuilt from a known-good config.**
[`../tools/gfx-experiment.ps1`](../tools/gfx-experiment.ps1) copies
`config.KNOWNGOOD.plist` over `config.plist` before applying anything, on every
invocation, whether or not `-Revert` was used. Tests therefore **cannot stack**.
A forgotten revert is the classic way an experiment log turns into fiction; this
removes the possibility rather than relying on discipline.

**One variable per run.** The only exception is run 2, which changed three
things at once (`device-id`, `ig-platform-id`, `enable-metal`). It is reported
as the first hang and nothing is concluded from it alone — runs 5–10 isolate
each component.

**A genuine control.** Run 1 removed `-igfxvesa` and injected *nothing*. It
booted. Without this, every subsequent failure could have been attributed to the
absence of `-igfxvesa` rather than to the injection. This is the run that makes
the rest of the table mean anything.

**A decoupling probe.** Run 3 applied the `device-id` spoof but **kept**
`-igfxvesa`, so the machine survived to be inspected. It showed the framebuffer
kext loaded while VESA still owned the display — separating *PCI match* and
*kext load* from *attach*, which the hanging runs cannot distinguish between.

**SSH as a liveness oracle.** Remote Login enabled, with a **static DHCP
reservation** at the router. This converts "no shell after the panel died" from
an ambiguous network problem into evidence that the kernel is gone. Without the
static reservation, a DHCP lease change would look identical to a dead kernel.

**A void run recorded rather than discarded.** See
[`RESULTS.md`](RESULTS.md#the-void-run).

## What was not controlled

Stated plainly, because a methodology section that only lists strengths is
advertising:

- **WhateverGreen was loaded in every run except 9, and did nothing to the
  framebuffer in any of them.** Version 1.7.0 has no Tiger Lake case, so its
  DVMT fix, connector patches and MMIO hooks never ran. This was not known at
  the time and it invalidates what runs 5–10 were taken to show; see
  [`RESULTS.md`](RESULTS.md) and [`LAYER3.md`](LAYER3.md). The `0xFFFFFFFF`
  platform id comes from Lilu, not from WhateverGreen.
- **Platform id `0x8A520000` was assumed valid.** It is not in Tahoe's table.
- **Run 2 changed three variables.** Nothing rests on it alone.
- **Single machine, single sample per configuration.** Each hang was observed
  once. The failure mode was consistent across seven distinct configurations,
  which is the reason for confidence — not repetition of any one of them.
- **No hardware debugger, no serial console.** The failure destroys the
  platform's ability to report on itself. What the machine did between
  `probe()` returning success and the reset is unobserved.
- **One macOS build.** Tahoe 26, `AppleIntelICLLPGraphicsFramebuffer 24.0.5`.

---

## The experiment harness

```powershell
mountvol S: /s
.\gfx-experiment.ps1 -Drive S -Id 8A52 -Plat FF05
Select-String -Path S:\EFI\OC\config.plist -Pattern 'Pci\(0x2,0x0\)' -Context 0,8
mountvol S: /d
```

Since OpenCore lives on the **unlettered internal ESP**, every experiment must
be bracketed with a mount — see
[`../docs/05-post-install.md`](../docs/05-post-install.md#92-the-esp-is-not-lettered--mount-it-first).
Editing an unmounted or stale `S:` is a silent no-op that presents as "the
change had no effect".

Recovery when a config leaves the internal EFI unbootable: F12 → **rescue USB**
→ boot Tahoe → then from Windows `mountvol S: /s` and restore
`config.KNOWNGOOD.plist` over `config.plist`.

### Verify the injected value before every boot

| Command | `ig-platform-id` | `device-id` |
|---|---|---|
| `-Id 8A52 -Plat FF05` | `AAAF/w==` | `UooAAA==` |
| `-Id 8A52` | `AABSig==` | `UooAAA==` |
| `-Id 8A5C` | `AABcig==` | `XIoAAA==` |
| `-Id 8A51` | `AABRig==` | `UYoAAA==` |
| `-Id 8A70` | `AABwig==` | `cIoAAA==` |

> If a run boots when it should have hung, **suspect the injected value before
> concluding anything.** An ID absent from `IOPCIPrimaryMatch` can never match,
> so the framebuffer never binds and the machine boots normally — looking
> exactly like a "safe" result while testing nothing. This check would have
> caught the void `85A1` run.

### Capture per run

Locally if it boots, over SSH if the panel dies:

```bash
O=/Volumes/OCBOOT/gfxdata; mkdir -p $O; T=<tag>
ioreg -rw0 -p IOService -n IGPU  > $O/igpu-$T.txt
ioreg -rw0 -c IOAccelerator      > $O/accel-$T.txt      # EMPTY = no accelerator
kextstat | grep -iE 'ICLLP|ICLGraphics' > $O/kx-$T.txt
grep -oE '\+-o \.Display[^ ]* +<class [A-Za-z]+' $O/igpu-$T.txt
```

### Outcome key

| Observation | Meaning |
|---|---|
| `.Display_boot = IONDRVFramebuffer` | FB never attached. Personality rejected. Try next ID |
| `.Display_boot = AppleIntelICLLPGraphicsFramebuffer`, `accel-*.txt` empty | **FB attached, no accelerator.** lshbluesky's frontier |
| FB attached **and** `IOAccelerator` object present | new territory for `9A40` |
| black screen, SSH alive | FB attached then hung the display only — check `ioreg` over SSH |
| black screen, SSH dead, reset | hardware-level hang — where this project stopped |

---

## Diagnostic traps

Each of these cost real time, and each produces a confident, wrong answer.

### `[EB|LOG:EXITBS:START]` as the last log line is normal

It is the last line of **every** OpenCore file log. OpenCore cannot write to
FAT after ExitBootServices, so the log always ends there regardless of what
happened next. It indicates a hang **only when frozen on screen**.

### `ioreg -l | grep -c IOAccelerator` is useless

It counts string occurrences in unrelated property names. It returned **4** on a
system with no accelerator at all — see
[`data/ioreg/accel-count.txt`](data/ioreg/accel-count.txt) next to the empty
[`data/ioreg/accel-nub.txt`](data/ioreg/accel-nub.txt).

The real test is `ioreg -rw0 -c IOAccelerator`. **Empty output = no accelerator
object exists.**

### The last console line before a display death is not the culprit

It is *where the console happened to be*. Observed:
`DriverKit-IOUserDockChannelSerial`, `AppleKeyStore`. Both entirely routine.
Chasing them wastes days.

### `sender CONTAINS "AppleIntel"` matches Apple Intelligence

`gfx-baseline.log` returned exactly one line, from
**AppleIntelligenceReporting**. No graphics kext had logged anything, because
none had loaded. Use a tighter predicate:

```bash
log show --last boot --predicate 'sender CONTAINS "AppleIntelICLLP" OR sender CONTAINS "IOAccelerator"'
```

That corrected predicate is what produced
[`data/ioreg/gfx-minimal.log`](data/ioreg/gfx-minimal.log) — the only run where
the framebuffer explained its own refusal.

### Reading `About This Mac`

"Display 9 MB" is the unaccelerated readout. It describes the VESA linear
framebuffer, not a GPU. `system_profiler` likewise reports
`Kernel Extension Info: No Kext Loaded`
([`data/ioreg/displays-minimal.txt`](data/ioreg/displays-minimal.txt)) — that is
the correct answer, not a missing driver you can install.

Judge attachment by **the class of `.Display_boot`**, and by nothing else:
`IONDRVFramebuffer` means VESA; `AppleIntelICLLPGraphicsFramebuffer` means the
Apple kext took it.

---

## Phase 2 (runs A–N): what changed in the method

The first eleven runs had no feedback channel: every failure was a silent reset. Phase 2 worked because three
channels turned out to exist.

**The driver logs its own modeset.** `AppleIntelICLLPGraphicsFramebuffer` writes detailed `[IGFB]` lines through
`os_log`: register values it computes, link-training phases, power-state transitions, every error. They are in the
unified log and survive a hard power-off, provided the boot lived about a minute:

```bash
log show --start "2026-10-07 13:14:00" --predicate 'process == "kernel" AND eventMessage CONTAINS "IGFB"' --style compact
```

Once the reset was gone (run A), this log named each next problem.

**Register snapshots written to a file.** Patch 0003 can read a fixed list of registers at the driver's first access
(the firmware's working state) and again minutes after the modeset, and write both to
`/Users/Shared/tgl-map-state.bin` from a kernel thread. Comparing the two columns is what found the zeroed backlight
duty. `tools/mac/decode-tglmap.py` decodes it.

**Disassembly of the exact binary.** `tools/mac/extract_kext.py` copies one kext out of
`SystemKernelExtensions.kc` into a file `nm` and `objdump` can read; `tools/mac/dis-icllp.py` annotates a function
with the log strings it references. Every cause in [`LAYER3.md`](LAYER3.md) was confirmed there before a boot was
spent on it.

**One change per boot, generated, validated, recorded.** `tools/mac/tgl-mac.sh` builds each experiment from the VESA
base config, runs `ocvalidate`, refuses to stack experiments, checks after the boot which config actually ran (by
comparing the running boot-args), and restores the known-good config.

### What was not controlled in phase 2

- `-igfxcdc`, `-igfxdbeo` and the `Kernel/Block` entry for the accelerator were carried through every run from A
  onward and never removed individually. They may be unnecessary.
- Runs F2 and M each changed more than one thing, by choice, to save boots. Their individual parts were isolated
  afterwards only where something went wrong.
- Single machine, one sample per configuration, as before.

### Additional traps

- **Writing NVRAM from a kext resets this machine.** Runs B, F3 and F4 reset at the moment diagnostics were written
  through Lilu's `NVStorage`. It looked exactly like the graphics failures of phase 1. A diagnostic that can kill the
  machine has to be ruled out before its absence is read as information.
- **Third-party kext `IOLog` output is not in the unified log on Tahoe.** Not early, not late. Only `dmesg` has it,
  and the 128 KiB buffer wraps within a minute on this machine.
- **A log file of 0 bytes** in `/var/db/diagnostics/Persist` for a boot means the kernel froze or died in the first
  30–60 seconds. A populated one means it lived, whatever the screen showed.
- **Disk numbers change between boots.** The USB stick became `disk0` once; a script that assumed the internal ESP
  was `disk0s1` would have written to the wrong disk. Find the ESP by "internal, physical, type EFI".
- **Booting through Windows shifts the macOS clock** by the UTC offset until NTP corrects it, so log timestamps of
  the next boot are off by hours.
- **`sudo` drops environment variables.** `KEEP=1 sudo script` does not pass `KEEP`.
- **`Kernel/Block` with `Exclude` did not keep `AppleIntelICLGraphics` out of `kextstat`.** It attached nothing, but
  "blocked" is not what happened.
