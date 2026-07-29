# Raw data

Everything here came off the machine. Nothing was reconstructed, and no run was
dropped because it was inconvenient.

```
data/
├── acpi/         33 firmware tables dumped by OpenCore's SysReport
├── ioreg/        baseline + per-experiment IOKit registry dumps
├── kextstat/     loaded-kext lists, baseline and per-experiment
├── sysreport/    CPU / GOP / PCI / driver text reports
├── usb/          USBToolBox topology and both port maps
└── icllp-match.txt
```

---

## What was redacted, and what was not

Every text file here was passed through
[`../../tools/scrub.ps1`](../../tools/scrub.ps1). Redacted:

| Category | Replaced with |
|---|---|
| Mac serial (SMBIOS + the hex-encoded copy in `serial-number`) | `XXXXXXXXXXXX` |
| MLB / board serial | `CHANGE-ME-MLB` |
| `SystemUUID` and `IOPlatformUUID` | all-zero UUID |
| Wi-Fi MAC (`ROM`) and USB-Ethernet MAC | `11:22:33:44:55:66` |
| Account short name and full name | `user` / `Redacted User` |
| NVMe and attached-USB device serials | `X`-padded, same length |

Replacements are **length-preserving** wherever a length carries meaning, so
the dumps stay structurally faithful to what the machine actually printed.

Deliberately **not** redacted, because they are not personal and removing them
would damage the data:

- **Kext binary UUIDs** in `kextstat/` — identical on every machine running
  that build. They are how you confirm you are looking at the same
  `AppleIntelICLLPGraphicsFramebuffer 24.0.5` this project tested.
- **APFS container and volume UUIDs** in `ioreg-baseline.txt` — machine-local
  and meaningless elsewhere.
- **Apple and Microsoft constant GUIDs** (NVRAM variable namespaces, Windows
  device class GUIDs in `usb.json`).
- **Hardware IDs** — `8086:9A40`, subsystem `1028:0A45` and everything in
  `sysreport/PCIInfo.txt`. These identify the *model*, which is the point.

Two files were **excluded** from the repository rather than redacted:

- `SysReport/ACPI/MSDM-1.aml` — the MSDM table carries the OEM Windows product
  key.
- `SysReport/SMBIOS/DataV1.bin` — carries the Dell service tag and the real
  system UUID.

To audit this yourself:

```powershell
..\..\tools\scrub.ps1 -Path . -Recurse -Check
```

It sweeps for identifier *shapes* rather than known values, so it works on your
own captures too. It is intentionally noisy — version strings like
`newfs_apfs (1677.41.3.101.1)` trip the IPv4 pattern.

---

## `acpi/`

The machine's real firmware tables, dumped by OpenCore's `SysReport` during
Phase 1 (DEBUG build — `SysReport` is compiled out of RELEASE builds).

`DSDT.aml` decompiles to 78,990 lines. To read it:

```bash
iasl -da -dl DSDT.aml SSDT-*.aml      # all tables together, so externals resolve
```

The four SSDTs *we wrote* are not here — they are in
[`../../ACPI-sources/`](../../ACPI-sources/). Everything in this folder is the
vendor's.

Notable tables: `SSDT-2` (`DptfTabl`), `SSDT-6` (the largest, 45 KB),
`SSDT-8` (`UsbCTabl`, contains `\_SB.UBTC`). `NHLT` is present and describes
the SoundWire endpoints — the audio finding is visible at the ACPI layer as
well as at PCI.

## `ioreg/`

| File | Run | What it shows |
|---|---|---|
| `ioreg-baseline.txt` | 0 | full `ioreg -l -w0` on the working VESA system |
| `igpu-baseline.txt` | 0 | the `IGPU@2` subtree, extracted from the above |
| `igpu-novesa-nospoof.txt` | 1 | control — `device-id 409a0000`, still `IONDRVFramebuffer` |
| `igpu-8A52-keepvesa.txt` | 3 | decoupling probe — `device-id 528a0000`, still `IONDRVFramebuffer` |
| `igpu-minimal.txt` | 4 | `device-id` only — `528a0000`, `ig-platform-id ffffffff` |
| `gfx-minimal.log` | 4 | **the probe failure, in the kext's own words** |
| `accel-nub.txt` | — | `ioreg -rw0 -c IOAccelerator`. **Empty. That is the result.** |
| `accel-count.txt` | — | `grep -c IOAccelerator` returned `4` on the same boot. The trap |
| `props-minimal.txt` | 4 | `ig-platform-id` and the IOKit compatibility template |
| `displays-minimal.txt` | 4 | `system_profiler` — "VRAM 9 MB", the VESA readout |
| `icllp-count.txt` | — | `0` |

`igpu-baseline.txt` was extracted from `ioreg-baseline.txt` rather than
captured separately; the header in the file says so. It is the exact subtree
`ioreg -rw0 -p IOService -n IGPU` would have printed.

> `props-minimal.txt` contains an IOKit *compatibility template* listing
> `AGXMetalA12` and `VRAM,totalMB = 16384`. That is a static property template
> present on every Mac, not a description of this machine. Do not read it as
> evidence of a 16 GB Metal device.

## `kextstat/`

| File | Run | Shows |
|---|---|---|
| `kexts-baseline.txt` | 0 | the 13 non-Apple kexts on a working boot |
| `kexts-novesa-nospoof.txt` | 1 | **empty** — no graphics kext loaded |
| `kexts-8A52-keepvesa.txt` | 3 | `AppleIntelICLLPGraphicsFramebuffer 24.0.5` **loaded** |
| `kx-minimal.txt` | 4 | framebuffer *and* `AppleIntelICLGraphics` *and* `IOAcceleratorFamily2` loaded |

`kexts-8A52-keepvesa.txt` is the single most important file in this directory:
it is the proof that PCI matching and kext load succeed, independently of
attach. See [`../README.md`](../README.md).

## `usb/`

- `usb.json` — raw USBToolBox topology dump from Windows.
- `UTBMap-untrimmed-Info.plist` — the first map, selecting **all** ports
  (16 on XHCI, 5 on TXHC). Kept because the failure it causes is instructive.

The trimmed 9-port map that actually shipped is at
[`../../EFI/OC/Kexts/UTBMap.kext`](../../EFI/OC/Kexts/UTBMap.kext/Contents/Info.plist).

## `sysreport/`

Text reports from the same Phase 1 SysReport dump. `CPUInfo.txt` is where
`CstConfigLock 1` comes from; `GOPInfo.txt` establishes the 1920×1280 panel and
the above-4 GB framebuffer BAR; `PCIInfo.txt` is the authoritative device list.
