# Tools

Five scripts. All PowerShell except one, because the machine dual-boots Windows
and the ESP work has to happen from there anyway.

| Script | What it does |
|---|---|
| [`fetch-components.ps1`](fetch-components.ps1) / [`.sh`](fetch-components.sh) | downloads OpenCore + the 16 kexts into `EFI/`. Run this first |
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
