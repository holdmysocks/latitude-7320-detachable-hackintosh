# Dell Latitude 7320 Detachable — macOS 26 (Tahoe)

OpenCore 1.0.7 · Intel i5-1140G7 (Tiger Lake UP4) · Iris Xe 80 EU
**`8086:9A40`**, subsystem `1028:0A45` · 1920×1280 3:2 panel

> ### This is a research platform, not a usable laptop.
> No GPU acceleration. No audio, ever. No camera. No touchscreen. If you want a
> working portable Mac, this is not it. Read the table below before spending a
> weekend on this.
>
> **What is new (October 2026):** the internal display now runs on Apple's own
> Intel framebuffer driver instead of VESA: native mode setting, built-in panel,
> backlight control, display sleep. It needs a patched WhateverGreen, which is
> documented and included as source. See [`research/LAYER3.md`](research/LAYER3.md).

## What works

CPU + XCPM power management · NVMe · USB (9-port map) · keyboard · trackpad
(as a plain mouse) · battery · Bluetooth (3 kexts — [see docs](docs/05b-wifi-and-bluetooth.md)) ·
Wi-Fi (`itlwm` + HeliPort) · **internal display on the native Intel framebuffer**
(1920×1280 @ 60 Hz, brightness slider, display sleep and wake — patched
WhateverGreen required)

## What does not, and why

| Component | Status | Reason |
|---|---|---|
| GPU acceleration | ❌ | Iris Xe (Gen12) has no macOS accelerator. The framebuffer works; Metal does not. |
| Brightness keys | ✅ | `SSDT-DOSI` + `BrightnessKeys.kext`. |
| System sleep, lid close, external displays | ❔ | Untested since the framebuffer change. |
| Audio | ❌ | SoundWire (RT711/714/1316). macOS has no SoundWire stack. |
| Camera | ❌ | Intel IPU6 MIPI. No macOS driver. |
| Touchscreen / pen | ❌ | macOS has no touch input layer. |
| Fingerprint | ❌ | No driver. |
| AirDrop / Handoff / Continuity | ❌ | `itlwm` is not a native AirPort device. |
| Bluetooth 4.x device pairing | ⚠️ | Intel BT limitation; also fails on real Macs. |

Unaccelerated means unaccelerated: no hardware video decode, no Metal, window
compositing on the CPU. It boots, it runs, and it is slow in the ways you would
expect. The native framebuffer changes how the panel is driven, not how fast
anything draws.

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

The committed config also expects the **patched WhateverGreen**
([`WhateverGreen-patches/`](WhateverGreen-patches/)); with the stock kext the
panel stays black. For a first install, use the VESA fallback described in
[`EFI/OC/Kexts/KEXTS.md`](EFI/OC/Kexts/KEXTS.md#-whatevergreen-must-be-built-from-source)
and switch once macOS is running.

**You are researching Tiger Lake / Iris Xe graphics on macOS.** Go straight to
[**`research/README.md`**](research/README.md). It exists so you can skip what
has already been ruled out.

Short version: the Ice Lake framebuffer **does** drive this Tiger Lake panel.
The resets that looked like a wall were a stolen-memory miscalculation that
WhateverGreen already knows how to fix, but only for CPUs it believes are Ice
Lake. Behind that were four register-level differences and a backlight
problem, each small once visible. **Acceleration has not been attempted, so
this project still has no evidence about the shader-ISA hypothesis** — do not
cite it as if it had.

---

## Repository layout

```
EFI/                 scrubbed, ready to personalise. Binaries are fetched, not vendored
ACPI-sources/        the four SSDTs as readable .dsl, and why XOSI/GPI0 are absent
WhateverGreen-patches/  the three patches that make the framebuffer work, and how to build
docs/                the build, split into eight documents
research/            the graphics work: findings, every run, and the raw evidence
tools/               fetch, personalise, experiment (Windows and macOS), scrub
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
| [`research/README.md`](research/README.md) | **the findings**, and what the first write-up got wrong |
| [`research/LAYER3.md`](research/LAYER3.md) | how the framebuffer was made to work: causes, evidence, fixes |
| [`research/RESULTS.md`](research/RESULTS.md) | every run of both phases, including the void ones |
| [`research/METHODOLOGY.md`](research/METHODOLOGY.md) | controls, and the measurement traps |
| [`research/data/`](research/data/) | ACPI tables, `ioreg`, `kextstat`, USB topology, driver logs, register snapshots |
| [`WhateverGreen-patches/`](WhateverGreen-patches/) | the patches, the feature mask, build instructions |

## Key specifics

| | |
|---|---|
| CPU | i5-1140G7, CPUID `0x000806C1`, family 6 model `0x8C` stepping 1 |
| iGPU | `8086:9A40`, Iris Xe 80 EU, subsystem `1028:0A45` |
| SMBIOS | `MacBookPro16,2` |
| OpenCore | 1.0.7 RELEASE, `ocvalidate` clean |
| macOS | 26 Tahoe (26.6) |
| Graphics | `AppleIntelICLLPGraphicsFramebuffer` 24.0.5 via `device-id 8A5A`, platform `0x8A5C0002`, patched WhateverGreen |
| Kexts | 18 entries — [`EFI/OC/Kexts/KEXTS.md`](EFI/OC/Kexts/KEXTS.md) |
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
nothing. This is a terminal platform by design.

## Privacy

Every file was scrubbed before publication: SMBIOS serials, MLB, platform
UUIDs, MAC addresses, account names and attached-device serials. The MSDM table
(OEM Windows key) and the SMBIOS blob (Dell service tag) were excluded
entirely. What was redacted and what deliberately was not:
[`research/data/README.md`](research/data/README.md). Audit it yourself with
`tools/scrub.ps1 -Check`.

## Credits

This project is a write-up of other people's work applied to one machine, plus
one piece of original work: getting Apple's Ice Lake framebuffer to drive a
Tiger Lake panel.

- **[acidanthera](https://github.com/acidanthera)** — OpenCore, Lilu,
  VirtualSMC, WhateverGreen, NVMeFix, VoodooPS2, BrcmPatchRAM, BrightnessKeys,
  MaciASL
- **[corpnewt](https://github.com/corpnewt)** — SSDTTime, ProperTree, GenSMBIOS,
  MountEFI
- **[USBToolBox](https://github.com/USBToolBox)** — the port mapping tool and kext
- **[OpenIntelWireless](https://github.com/OpenIntelWireless)** — itlwm,
  IntelBluetoothFirmware, HeliPort
- **[1Revenger1](https://github.com/1Revenger1) / averycblack** — ECEnabler
- **[lshbluesky](https://github.com/lshbluesky)** — prior Tiger Lake framebuffer
  work, and the IntelBluetoothFirmware fork that actually targets Tahoe
- **[Dortania](https://dortania.github.io/)** — the guides
- **Linux i915** — the reference for every Ice Lake / Tiger Lake register
  difference

## Licence

[MIT](LICENSE), covering the documentation, scripts, ACPI sources,
configuration and research data here. No third-party binaries are
redistributed; [`EFI/OC/Kexts/KEXTS.md`](EFI/OC/Kexts/KEXTS.md) and
[`EFI/OC/Drivers/DRIVERS.md`](EFI/OC/Drivers/DRIVERS.md) list where each
component comes from and under which licence.
