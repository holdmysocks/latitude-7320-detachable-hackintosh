# 01 — BIOS and Windows preparation

Do all of this from Windows, before you build a USB stick.

---

## BIOS settings

| Setting | Value | Why |
|---|---|---|
| SATA/NVMe Operation | **AHCI** | RAID mode = Intel VMD; macOS can't see the NVMe at all |
| Secure Boot | Off | OpenCore is unsigned |
| Thunderbolt Security | No Security | per-device auth macOS can't provide |
| TB Boot Support + Pre-boot Modules | On | needed to boot USB-C |
| Fastboot | Thorough | full USB init before handoff |
| VT-d | Leave on | handled by `DisableIoMapper` |

CFG Lock is not exposed on this platform — confirmed set (`CstConfigLock 1`,
see [00 — hardware survey](00-hardware-survey.md#11-cpu)) and handled in
software with `AppleXcpmCfgLock`.

## ⚠️ The AHCI switch requires prep

Dell's "RAID On" is Intel VMD; Windows only has the VMD driver bound at boot.
Flip to AHCI without preparation and you get `INACCESSIBLE_BOOT_DEVICE`.

```
bcdedit /set "{current}" safeboot minimal      # before the change
                                               # reboot, flip BIOS to AHCI,
                                               # boot once into Safe Mode
bcdedit /deletevalue "{current}" safeboot      # then back to normal
```

## BitLocker

Turn it **off** before touching partitions or NVRAM. A partition-table change
or an NVRAM reset can trigger a recovery-key prompt otherwise.

## Fast Startup

```
powercfg /h off
```

Hybrid hibernation leaves NTFS dirty, which makes macOS mount it read-only at
best and produces bizarre USB/NVRAM behaviour on the next OpenCore boot.

## Make room for macOS — from Windows, not macOS

Shrink `C:` in `diskmgmt.msc`, then **create the partition from Windows**:
right-click the unallocated block → **New Simple Volume**, full size, NTFS,
label `TAHOE`, **do not assign a drive letter**.

This is not optional convenience. Windows places WinRE *after* `C:`, so
shrinking `C:` leaves the free space in the middle of the disk, where macOS
Disk Utility cannot address it. The full explanation and the command you must
**not** run are in
[04 — installation §8.4](04-installation.md#84--disk-utility-cant-use-mid-disk-free-space).

## Dual-boot rules

- OpenCore goes to `\EFI\OC` on the **existing** ESP. Leave `\EFI\Microsoft` alone.
- `LauncherOption` stays **`Disabled`** while running from USB. Only set it to
  `Full` once you're booting from the internal ESP for real —
  [05 — post-install §9.4](05-post-install.md#94-two-config-changes-internal-copy-only).
- Launch Windows *through* the OpenCore picker, not by changing BIOS boot order.
- If a Windows update resets BootOrder: F12 → `\EFI\OC\OpenCore.efi`.

---

Next: [02 — ACPI analysis](02-acpi-analysis.md)
