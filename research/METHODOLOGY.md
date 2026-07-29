# Methodology

Why the results in [`RESULTS.md`](RESULTS.md) are worth trusting, and the four
measurement traps that nearly made them worthless.

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

- **WhateverGreen was loaded in every run except 9.** It is not a neutral
  observer — it forces `ig-platform-id = 0xFFFFFFFF` on unrecognised `9A40`.
  Run 9 shows it is not the *cause* of the hang, but it shapes what the
  framebuffer receives in all the others.
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
