# The EFI

OpenCore **1.0.7 RELEASE**. `ocvalidate` clean.

This folder is the configuration and the machine-specific parts only. The
OpenCore binaries and third-party kexts are **fetched, not vendored** — see
[`tools/fetch-components.ps1`](../tools/fetch-components.ps1),
[`OC/Kexts/KEXTS.md`](OC/Kexts/KEXTS.md) and
[`OC/Drivers/DRIVERS.md`](OC/Drivers/DRIVERS.md).

## Assembling a bootable EFI

```powershell
.\tools\fetch-components.ps1          # downloads OpenCore 1.0.7 + 16 kexts
.\tools\Setup-SMBIOS.ps1              # fills in serial / MLB / UUID / ROM
```

Then copy `EFI\` to the root of a FAT32/GPT USB stick. Full walkthrough:
[`docs/04-installation.md`](../docs/04-installation.md).

**The committed `config.plist` will not boot as-is** — its SMBIOS fields are
placeholders (`CHANGE-ME-SERIAL`, `CHANGE-ME-MLB`, an all-zero UUID and
`ROM = 11 22 33 44 55 66`). That is deliberate; see
[Personalising](#personalising) below.

## What is in here

```
EFI/
├── BOOT/                 BOOTx64.efi          (fetched)
└── OC/
    ├── ACPI/             4 compiled .aml      (committed — sources in ../ACPI-sources/)
    ├── Drivers/          4 .efi               (fetched — DRIVERS.md)
    ├── Kexts/            16 .kext             (fetched — KEXTS.md)
    │   └── UTBMap.kext   the 9-port USB map   (committed — plist-only)
    ├── Tools/            OpenShell.efi        (fetched)
    ├── OpenCore.efi                           (fetched)
    └── config.plist                           (committed, scrubbed)
```

---

## config.plist — the parts that aren't stock

Everything else is OpenCore's sample defaults. These are the decisions.

```
Kernel > Quirks
  AppleXcpmExtraMsrs      True    <- without this: hang at [EB|#LOG:EXITBS:START]
  AppleXcpmCfgLock        True    <- confirmed needed (CstConfigLock 1)
  DisableIoMapper         True
  DisableLinkeditJettison True
  ProvideCurrentCpuInfo   True

Kernel > Emulate
  Cpuid1Data  E5 06 07 00 00 ... (16 bytes)   reports 0x000706E5 (Ice Lake-U)
  Cpuid1Mask  FF FF FF FF 00 ... (16 bytes)   override first 4 bytes only

Booter > Quirks
  ResizeAppleGpuBars      -1      <- framebuffer BAR sits above 4 GB

PlatformInfo > Generic
  SystemProductName  MacBookPro16,2
```

**Why `AppleXcpmExtraMsrs`:** Tiger Lake lays out several power-management MSRs
differently than XNU expects. `AppleIntelCPUPowerManagement` reads one that
faults. `[EB|#LOG:EXITBS:START]` frozen **on screen** is this quirk's exact
fingerprint.

**Why the CPUID spoof:** XNU's CPU family table has no entry for model `0x8C`.
Without the spoof it falls back to a generic path with no power management. The
mask overrides only the first four bytes, preserving real feature flags.

**Why `MacBookPro16,2`:** 13" 2020 four-TB3, Ice Lake i7-1068NG7 — the closest
real Mac to Tiger Lake, *and* on Tahoe's supported list. Tahoe dropped pre-2019
SMBIOS, leaving only `MacBookPro16,1/16,2/16,4`, `iMac20,1/20,2`, `MacPro7,1`.
No board-ID bypass needed.

**Graphics:** the config starts Apple's Ice Lake framebuffer (`AppleIntelICLLPGraphicsFramebuffer`) on the Tiger
Lake iGPU. It needs the **patched WhateverGreen** from [`WhateverGreen-patches/`](../WhateverGreen-patches/); with a
stock build the panel stays black.

| Setting | Value | Why |
|---|---|---|
| `DeviceProperties` → `PciRoot(0x0)/Pci(0x2,0x0)` → `device-id` | `5A8A0000` | `9A40` is in no Apple match list |
| … → `AAPL,ig-platform-id` | `02005C8A` | `0x8A5C0002`; `0x8A520000` no longer exists in Tahoe |
| boot-arg `lilucpu=12` | | makes Lilu report Ice Lake so WhateverGreen's Ice Lake fixes apply |
| boot-arg `-igfxdvmt` | | without it the driver computes 4 GB of stolen memory and the machine resets |
| boot-arg `igfxtglmap=0xA83F` | | the Tiger Lake register map (patch 0003) |
| boot-args `-igfxcdc -igfxdbeo` | | stock Ice Lake fixes, carried along, not individually verified |
| `Kernel/Block` `AppleIntelICLGraphics` | `Exclude` | no accelerator; framebuffer only |
| `ACPI/Add` `SSDT-PNLF.aml` | enabled | backlight; `_UID` must be 19 |
| `ACPI/Add` `SSDT-DOSI.aml` | enabled | brightness keys (with `BrightnessKeys.kext`) |

There is **no graphics acceleration**. Full account: [`research/LAYER3.md`](../research/LAYER3.md).

To fall back to VESA, remove the `Pci(0x2,0x0)` entry and use boot-args `-v debug=0x100 keepsyms=1 -igfxvesa`.

The other `DeviceProperties` entry is `layout-id = 1` on
`PciRoot(0x0)/Pci(0x1f,0x3)`. It is inert — there is no HDA codec for it to
apply to — and is left in place only because it is harmless and was present in
every configuration the experiments were run against.

## Install-time values you must change afterwards

The committed config carries **install-time** settings, not steady-state ones.
Three of them should be changed once macOS is installed and OpenCore lives on
the internal ESP:

| Key | Committed | Change to | When |
|---|---|---|---|
| `Misc > Security > DmgLoading` | `Any` | `Signed` | after install |
| `Misc > Boot > LauncherOption` | `Disabled` | `Full` | **internal ESP copy only** |
| `Misc > Debug > Target` | `67` | `3` | optional, once you no longer want a log file on the ESP |

`HideAuxiliary` is shipped `False` on purpose so the recovery entry is visible
without pressing Space.

Exact commands: [`docs/05-post-install.md`](../docs/05-post-install.md#94-two-config-changes-internal-copy-only).

> **Leave the USB stick at `LauncherOption = Disabled`.** A rescue device must
> not write NVRAM boot entries.

## Personalising

Four fields in `PlatformInfo > Generic` are placeholders and must be replaced
before first boot:

| Key | Placeholder |
|---|---|
| `SystemSerialNumber` | `CHANGE-ME-SERIAL` |
| `MLB` | `CHANGE-ME-MLB` |
| `SystemUUID` | `00000000-0000-0000-0000-000000000000` |
| `ROM` | `ESIzRFVm` (= `11 22 33 44 55 66`) |

[`tools/Setup-SMBIOS.ps1`](../tools/Setup-SMBIOS.ps1) generates all four —
serial and MLB from `macserial`, a fresh UUID, and `ROM` from your own AX201 MAC
address — then runs `ocvalidate`.

Do this even if you never intend to sign in to iCloud. Booting with
placeholders is harmless in the short term but produces confusing iServices
failures later, and a duplicated `ROM` is worse than a wrong one.
