# Tools

The original five scripts are PowerShell (all but one), because the machine dual-boots Windows
and the first ESP work happened from there. The [macOS-side harness](#mac--the-macos-side-harness-phase-2)
used for the later graphics work is in `mac/`.

| Script | What it does |
|---|---|
| [`fetch-components.ps1`](fetch-components.ps1) / [`.sh`](fetch-components.sh) | downloads OpenCore + the 17 kexts into `EFI/`. Run this first |
| [`Setup-SMBIOS.ps1`](Setup-SMBIOS.ps1) | fills in serial / MLB / UUID / ROM, then validates |
| [`gfx-experiment.ps1`](gfx-experiment.ps1) | the graphics experiment harness |
| [`Install-BluetoothFix.ps1`](Install-BluetoothFix.ps1) | retrofits `IntelBTPatcher` into an older EFI |
| [`scrub.ps1`](scrub.ps1) | redacts identifiers from captured dumps; audits a repo for leaks |

`ocvalidate.exe` and `macserial.exe` are **not** committed — `fetch-components`
drops them here from the OpenCore release, which keeps `ocvalidate` locked to
the OpenCore version it belongs with. Mixing those two versions is the single
most common way to produce a boot failure with no diagnostic.

---

## Typical first run

```powershell
.\fetch-components.ps1        # or -Tested to pin the exact versions used here
.\Setup-SMBIOS.ps1
.\ocvalidate.exe ..\EFI\OC\config.plist
```

Then copy `EFI\` to the root of a FAT32/GPT USB stick.
Walkthrough: [`../docs/04-installation.md`](../docs/04-installation.md).

> `Setup-SMBIOS.ps1` writes a **real MAC address** into whichever
> `config.plist` you point it at. If you point it at the copy inside this
> repository, `git checkout EFI/OC/config.plist` before pushing.

---

## `gfx-experiment.ps1` — the experiment harness

Committed **verbatim**, exactly as used for the runs in
[`../research/RESULTS.md`](../research/RESULTS.md). It has not been tidied up,
because the results reference its behaviour.

```powershell
mountvol S: /s
.\gfx-experiment.ps1 -Drive S -Id 8A52 -Plat FF05
Select-String -Path S:\EFI\OC\config.plist -Pattern 'Pci\(0x2,0x0\)' -Context 0,8
mountvol S: /d
```

| Switch | Effect |
|---|---|
| `-Id <hex>` | `device-id` to inject. Default `8A52` |
| `-Plat <hex>` | `AAPL,ig-platform-id`. Defaults to `-Id` |
| `-Minimal` | `device-id` only — no platform id, no `enable-metal` |
| `-KeepVesa` | inject, but leave `-igfxvesa` in place. **The safe probe** |
| `-NoSpoof` | strip `-igfxvesa` only, inject nothing. **The control** |
| `-NoWEG` | disable WhateverGreen entirely |
| `-Revert` | restore `config.KNOWNGOOD.plist` |

The important property: **it rebuilds from `config.KNOWNGOOD.plist` on every
invocation**, not only on `-Revert`. Tests cannot stack, so a forgotten revert
cannot silently corrupt a run.

### Before you use it

Read [`../research/METHODOLOGY.md`](../research/METHODOLOGY.md) first — in
particular:

1. **Enable SSH with a static DHCP reservation.** Every entry that
   black-screens is worthless without it. With it, a dead panel still leaves a
   live shell.
2. **Verify the injected base64 before every boot.** An ID absent from
   `IOPCIPrimaryMatch` can never match, so the machine boots normally and looks
   like a clean negative while testing nothing. That mistake produced one void
   run here.
3. **Have a tested rescue USB.** Most `-Id` values leave the machine unable to
   boot, and the internal ESP is unlettered, so recovery goes through Windows.

Recovery: F12 → rescue USB → boot Tahoe → from Windows `mountvol S: /s` and
restore `config.KNOWNGOOD.plist` over `config.plist`.

---

## `scrub.ps1`

```powershell
.\scrub.ps1 -Path ..\research\data -Recurse -Check   # audit, no writes
.\scrub.ps1 -Path ..\research\data -Recurse          # apply redactions
```

`-Check` needs no configuration: it sweeps for the *shapes* of identifiers —
Apple serials, MACs in every encoding, non-zero platform UUIDs, IPs, emails —
so it works on anyone's capture. It is intentionally noisy; version strings
like `newfs_apfs (1677.41.3.101.1)` trip the IPv4 pattern.

Applying redactions needs `scrub-map.local.psd1`, which is gitignored. Copy
[`scrub-map.example.psd1`](scrub-map.example.psd1) and fill in your own values.

The map is kept out of the repository on purpose: a scrubbing script that
hardcodes the strings it scrubs republishes exactly what it was written to
remove. What was redacted here, and what deliberately was not, is listed in
[`../research/data/README.md`](../research/data/README.md).

---

## `macrecovery`

Not vendored. It ships inside the OpenCore release archive under
`Utilities/macrecovery/`, and `fetch-components` already downloads that
archive. Usage for Tahoe is in
[`../docs/04-installation.md`](../docs/04-installation.md#option-a--macrecovery-no-mac-required).

---

## `mac/` — the macOS-side harness (phase 2)

Used for runs A–N in [`../research/RESULTS.md`](../research/RESULTS.md). These run on the machine under test, from
macOS, and expect the working files on a FAT32 stick mounted at `/Volumes/TGLDEBUG` (paths are at the top of
`tgl-mac.sh`).

| Script | What it does |
|---|---|
| [`mac/tgl-mac.sh`](mac/tgl-mac.sh) | `status`, `gen`, `apply`, `collect [keep]`, `revert`, `promote`, `vesa`, `install-kext`, `install-extra`, `install-acpi`, `fblog`, `mapstate`, `arm-rescue` |
| [`mac/make-experiment.py`](mac/make-experiment.py) | builds one experiment config from the VESA base config; refuses platform ids Tahoe does not have |
| [`mac/decode-tglmap.py`](mac/decode-tglmap.py) | decodes the register snapshot written by patch 0003 |
| [`mac/extract_kext.py`](mac/extract_kext.py) | copies one kext out of a kernel collection into an inspect-only Mach-O |
| [`mac/dis-icllp.py`](mac/dis-icllp.py) | annotated disassembly of one framebuffer function |
| [`mac/bright.py`](mac/bright.py) | read or set brightness through DisplayServices |
| [`mac/dstest.sh`](mac/dstest.sh), [`mac/ptylog.py`](mac/ptylog.py) | display sleep/wake test that logs the kernel line by line to a file which survives a hard reset |
| [`mac/decode-tgltrace.py`](mac/decode-tgltrace.py) | decodes the on-disk register trace of patch 0003 (`igfxtglmap` `0x10000`) |
| [`mac/lidwatch.sh`](mac/lidwatch.sh) | display off when the lid closes, for a machine with system sleep disabled |
| [`mac/collect-mact.sh`](mac/collect-mact.sh) | the earlier capture script (phase 1 handoff) |

`tgl-mac.sh apply <experiment>` generates the config from `config.BASE-VESA.plist` on the ESP, validates it with
`ocvalidate`, and refuses to run if the live config is not the known-good one. `collect` works out from the running
boot-args whether this boot is the experiment or the fallback, saves the driver log and snapshot, and restores the
known-good config (`collect keep` leaves a surviving experiment in place). The ESP is found as "internal, physical,
type EFI", never by disk number.

`ocvalidate` for macOS comes from the same OpenCore release as the `.exe`; it is not committed.
