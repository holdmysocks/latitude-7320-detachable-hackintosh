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

**Graphics:** `DeviceProperties` has **no** IGPU entry; boot-args carry
`-igfxvesa`. Deliberate. Injecting a framebuffer ID before the system boots
reliably produces black screens indistinguishable from a dozen other failures.

It is also, on this hardware, redundant — WhateverGreen forces
`ig-platform-id = 0xFFFFFFFF` on unrecognised `9A40` whether or not
`-igfxvesa` is set. See [`research/README.md`](../research/README.md).

The only `DeviceProperties` entry is `layout-id = 1` on
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
