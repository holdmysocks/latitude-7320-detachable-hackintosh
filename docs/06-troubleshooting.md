# 06 — Troubleshooting

Every row here was hit at least once during this build.

| Symptom | Cause | Fix |
|---|---|---|
| Hang at `[EB\|#LOG:EXITBS:START]` **on screen** | TGL MSR layout | `AppleXcpmExtraMsrs = True` |
| Same string as last line **of the file log** | normal | OpenCore cannot write to FAT after ExitBootServices — [04 §8.3](04-installation.md#83-the-entry-is-named-after-the-volume-not-the-os) |
| Installer sees no disks | Dell VMD/RAID mode | BIOS → AHCI — [01](01-bios-and-windows-prep.md#bios-settings) |
| `INACCESSIBLE_BOOT_DEVICE` in Windows | AHCI switch without safeboot | WinRE → Safe Mode → `bcdedit /deletevalue` — [01](01-bios-and-windows-prep.md#-the-ahci-switch-requires-prep) |
| Panic on `MSR 0xE2` | CFG Lock (confirmed set) | `AppleXcpmCfgLock = True` |
| Black screen after picker, machine alive | stock WhateverGreen with the committed config: the link never trains | build the patched kext — [KEXTS.md](../EFI/OC/Kexts/KEXTS.md#-whatevergreen-must-be-built-from-source); or fall back to VESA |
| Reset the moment graphics start | `lilucpu=12` or `-igfxdvmt` missing, or platform id `0x8A520000` | use the committed boot-args and `0x8A5C0002` — [LAYER3 §1–2](../research/LAYER3.md#1-the-reset-stolen-memory-computed-as-4-gb) |
| Picture, but nearly black and flickering | `SSDT-PNLF` `_UID` 15 | `_UID` 19 — [LAYER3 §6](../research/LAYER3.md#6-backlight) |
| Brightness keys do nothing | `SSDT-DOSI.aml` missing or disabled, or `BrightnessKeys.kext` not loaded | enable both — [LAYER3](../research/LAYER3.md#brightness-keys) |
| CPU pinned to one frequency | XCPM not attached | check `SSDT-PLUG` targets `\_SB.PR00` — [02 §4.3](02-acpi-analysis.md#43-other-conclusions) |
| Battery absent | Dell EC >8-bit fields | `ECEnabler.kext` |
| Boot loop, not hang | wrong CPUID spoof | try Samsung reference value |
| Random wakes / USB dies | unmapped ports | rebuild `UTBMap.kext` — [03](03-usb-mapping.md#rebuilding-the-map-for-a-different-machine) |
| USB still wrong after mapping | firmware RHUB declarations | enable `SSDT-RHUB.aml` — [02 §5.1](02-acpi-analysis.md#51-what-ships-in-efiocacpi) |
| Windows won't boot post-update | BootOrder reset | F12 → `\EFI\OC\OpenCore.efi`, then `Ctrl+Enter` |
| Edits to config have no effect | ESP not mounted, or edited the USB copy | `mountvol S: /s` first — [05 §9.2](05-post-install.md#92-the-esp-is-not-lettered--mount-it-first) |
| `S:\` not found | ESP unmounted or shell not elevated | elevated PowerShell + `mountvol S: /s` |
| Internal EFI unbootable after an experiment | bad config | F12 → rescue USB, then restore `config.KNOWNGOOD.plist` — [05 §9.6](05-post-install.md#96-keep-the-usb-as-a-rescue-device) |
| Experiment "boots safely" unexpectedly | injected ID not in `IOPCIPrimaryMatch` | verify base64 before boot — [research/METHODOLOGY.md](../research/METHODOLOGY.md#verify-the-injected-value-before-every-boot) |
| BT controller visible but non-functional | `IntelBTPatcher` missing | add it — [05b §10.2](05b-wifi-and-bluetooth.md#102-bluetooth--three-kexts-required-not-two) |
| BT half-working after a kext change | stale NVRAM controller cache | `nvram -d bluetooth*ControllerInfo` — [05b §10.4](05b-wifi-and-bluetooth.md#104-clearing-stale-bluetooth-state--do-not-reach-for-reset-nvram) |
| BT 4.x device won't pair | Intel BT limitation, also on real Macs | not fixable — [05b §10.6](05b-wifi-and-bluetooth.md#106-bluetooth-expectations) |
| Boots straight to Windows after NVRAM reset | `BootOrder` wiped | F12 → OpenCore → `Ctrl+Enter` — [05b §10.5](05b-wifi-and-bluetooth.md#105-is-reset-nvram-dangerous-on-this-machine) |
| Recovery missing from picker | `HideAuxiliary=True` | Space, or set `False` — [04 §8.1](04-installation.md#81-recovery-entry-invisible-in-the-picker) |
| Recovery still missing after Space | `DmgLoading=Signed` rejects silently | set `Any` — [04 §8.2](04-installation.md#82-recovery-entry-still-invisible-after-space) |
| No `opencore-*.txt` written | `Target=3` is screen-only | set `Target=67` |
| Disk Utility `+` greyed out | free space is mid-disk | partition from Windows — [04 §8.4](04-installation.md#84--disk-utility-cant-use-mid-disk-free-space) |
| Setup Assistant spins forever | update-server round-trip | unplug Ethernet — [04 §8.5](04-installation.md#85-setup-assistant-hangs-on-update-mac-automatically) |
| `system_profiler SPUSBDataType` returns empty | cosmetic | use `ioreg` instead; the map is fine |
| No audio, ever | SoundWire, not HDA | USB-C DAC — [00 §1.4](00-hardware-survey.md#14-audio--permanently-silent) |

## Measurement traps

These are not symptoms, they are wrong readings. Each one cost real time.

- `ioreg -l | grep -c IOAccelerator` counts string occurrences in unrelated
  property names. It returned **4** on a system with no accelerator at all. Use
  `ioreg -rw0 -c IOAccelerator`; **empty output = no accelerator**.
- `log show --predicate 'sender CONTAINS "AppleIntel"'` also matches
  **AppleIntelligenceReporting**. Narrow it to `"AppleIntelICLLP"`.
- The last visible console line before a display death is *where the console
  was*, not the culprit. Observed: `DriverKit-IOUserDockChannelSerial`,
  `AppleKeyStore`. Both routine.
- `About This Mac` reporting **"Display 9 MB"** is the VESA readout. With Apple's
  framebuffer running it reports 1536 MB, which still does not mean acceleration.
- A silent reset is not specific to graphics here: writing NVRAM from a kext
  produces the same symptom.

Full write-up: [`research/METHODOLOGY.md`](../research/METHODOLOGY.md#diagnostic-traps).

---

Back to the [README](../README.md).
