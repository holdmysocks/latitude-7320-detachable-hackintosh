# Dell Latitude 7320 Detachable — macOS 26 (Tahoe)

OpenCore 1.0.7 · Intel i5-1140G7 (Tiger Lake UP4) · Iris Xe 80 EU
**`8086:9A40`**, subsystem `1028:0A45` · 1920×1280 3:2 panel

> ### This is a research platform, not a usable laptop.
> No GPU acceleration. No audio, ever. No camera. No touchscreen. If you want a
> working portable Mac, this is not it — and no amount of configuration will
> make it one. Read the table below before spending a weekend on this.

## What works

CPU + XCPM power management · NVMe · USB (9-port map) · keyboard · trackpad
(as a plain mouse) · battery · Bluetooth (3 kexts — [see docs](docs/05b-wifi-and-bluetooth.md)) ·
Wi-Fi (`itlwm` + HeliPort)

## What does not, and why

| Component | Status | Reason |
|---|---|---|
| GPU acceleration | ❌ | Iris Xe (Gen12) has no macOS driver. VESA only. |
| Audio | ❌ | SoundWire (RT711/714/1316). macOS has no SoundWire stack. |
| Camera | ❌ | Intel IPU6 MIPI. No macOS driver. |
| Touchscreen / pen | ❌ | macOS has no touch input layer. |
| Fingerprint | ❌ | No driver. |
| AirDrop / Handoff / Continuity | ❌ | `itlwm` is not a native AirPort device. |
| Bluetooth 4.x device pairing | ⚠️ | Intel BT limitation; also fails on real Macs. |

Unaccelerated means unaccelerated: no hardware video decode, no Metal, window
compositing on the CPU. It boots, it runs, and it is slow in the ways you would
expect.

---

## Two audiences

**You have this laptop and want macOS on it.** Start at
[`docs/00-hardware-survey.md`](docs/00-hardware-survey.md) and work through to
[`06`](docs/06-troubleshooting.md). Then:

```powershell
.\tools\fetch-components.ps1    # downloads OpenCore 1.0.7 + the kexts
.\tools\Setup-SMBIOS.ps1        # fills in serial / MLB / UUID / ROM
.\tools\ocvalidate.exe .\EFI\OC\config.plist
```

Copy `EFI\` to a FAT32/GPT USB stick. The committed `config.plist` has
placeholder SMBIOS and **will not boot as-is** — that is deliberate.

**You are researching Tiger Lake / Iris Xe graphics on macOS.** Go straight to
[**`research/README.md`**](research/README.md). It exists so you can skip what
has already been ruled out.

Short version: the wall is at framebuffer **attach**, not the shader ISA.
Five distinct Ice Lake personalities fail identically, so it is not a connector
configuration problem; disabling WhateverGreen changes nothing; `igfxagdc=0`
changes nothing. **Layers 4–5 were never reached, so this project produced no
evidence at all about the ISA hypothesis** — do not cite it as if it had.

---

## Repository layout

```
EFI/                 scrubbed, ready to personalise. Binaries are fetched, not vendored
ACPI-sources/        the four SSDTs as readable .dsl, and why XOSI/GPI0 are absent
docs/                the build, split into eight documents
research/            the negative result: findings, all 11 runs, and the raw dumps
tools/               fetch, personalise, experiment, scrub
```

| | |
|---|---|
| [`docs/00-hardware-survey.md`](docs/00-hardware-survey.md) | what is actually in the machine, verified not inferred |
| [`docs/01-bios-and-windows-prep.md`](docs/01-bios-and-windows-prep.md) | AHCI without bricking Windows |
| [`docs/02-acpi-analysis.md`](docs/02-acpi-analysis.md) | the `OSYS` finding, and the SSDTs it made unnecessary |
| [`docs/03-usb-mapping.md`](docs/03-usb-mapping.md) | two controllers, nine ports, two traps |
| [`docs/04-installation.md`](docs/04-installation.md) | the five things that actually blocked the install |
| [`docs/05-post-install.md`](docs/05-post-install.md) | verification, and moving OpenCore to the internal ESP |
| [`docs/05b-wifi-and-bluetooth.md`](docs/05b-wifi-and-bluetooth.md) | the `IntelBTPatcher` trap, and NVRAM safety |
| [`docs/06-troubleshooting.md`](docs/06-troubleshooting.md) | symptom → cause → fix |
| [`research/README.md`](research/README.md) | **the findings** |
| [`research/RESULTS.md`](research/RESULTS.md) | all eleven runs, including the void one |
| [`research/METHODOLOGY.md`](research/METHODOLOGY.md) | controls, and four measurement traps |
| [`research/data/`](research/data/) | ACPI tables, `ioreg`, `kextstat`, USB topology |

## Key specifics

| | |
|---|---|
| CPU | i5-1140G7, CPUID `0x000806C1`, family 6 model `0x8C` stepping 1 |
| iGPU | `8086:9A40`, Iris Xe 80 EU, subsystem `1028:0A45` |
| SMBIOS | `MacBookPro16,2` |
| OpenCore | 1.0.7 RELEASE, `ocvalidate` clean |
| macOS | 26 Tahoe |
| Kexts | 17 entries — [`EFI/OC/Kexts/KEXTS.md`](EFI/OC/Kexts/KEXTS.md) |
| BIOS | 1.46.0, AHCI, Secure Boot off, TB security off |

Three non-obvious requirements, each of which produces a silent failure if
missed: `AppleXcpmExtraMsrs` (Tiger Lake MSR layout), `AppleXcpmCfgLock`
(`CstConfigLock` is confirmed set), and a `Cpuid1Data` spoof to Ice Lake-U
because XNU has no entry for model `0x8C`. Details in
[`EFI/README.md`](EFI/README.md).

## End of life

**macOS 26 Tahoe is the last Intel-supporting release.** macOS 27 is Apple
Silicon only, so there will be no Intel code for OpenCore or OCLP to work with.
Expect roughly three years of security updates from Tahoe's launch, and then
nothing. This is a terminal platform by design — which is part of why the
research here was worth recording rather than continuing.

## Privacy

Every file was scrubbed before publication: SMBIOS serials, MLB, platform
UUIDs, MAC addresses, account names and attached-device serials. The MSDM table
(OEM Windows key) and the SMBIOS blob (Dell service tag) were excluded
entirely. What was redacted and what deliberately was not:
[`research/data/README.md`](research/data/README.md). Audit it yourself with
`tools/scrub.ps1 -Check`.

## Credits

This project is a write-up of other people's work applied to one machine, plus
one negative result.

- **[acidanthera](https://github.com/acidanthera)** — OpenCore, Lilu,
  VirtualSMC, WhateverGreen, NVMeFix, VoodooPS2, BrcmPatchRAM
- **[corpnewt](https://github.com/corpnewt)** — SSDTTime, ProperTree, GenSMBIOS,
  MountEFI
- **[USBToolBox](https://github.com/USBToolBox)** — the port mapping tool and kext
- **[OpenIntelWireless](https://github.com/OpenIntelWireless)** — itlwm,
  IntelBluetoothFirmware, HeliPort
- **[1Revenger1](https://github.com/1Revenger1) / averycblack** — ECEnabler
- **[lshbluesky](https://github.com/lshbluesky)** — prior Tiger Lake framebuffer
  work, and the IntelBluetoothFirmware fork that actually targets Tahoe
- **[Dortania](https://dortania.github.io/)** — the guides

## Licence

[MIT](LICENSE), covering the documentation, scripts, ACPI sources,
configuration and research data here. No third-party binaries are
redistributed; [`EFI/OC/Kexts/KEXTS.md`](EFI/OC/Kexts/KEXTS.md) and
[`EFI/OC/Drivers/DRIVERS.md`](EFI/OC/Drivers/DRIVERS.md) list where each
component comes from and under which licence.
