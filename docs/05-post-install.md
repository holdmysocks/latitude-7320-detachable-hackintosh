# 05 — Post-install

Verify, then move OpenCore off the USB stick and onto the internal ESP.

---

## 9.1 Verify XCPM before anything else

```bash
sudo powermetrics --samplers cpu_power -i 1000 -n 5
```

Frequency must step under load. Pinned to one value = the CPUID spoof or
`SSDT-PLUG` isn't taking. **Fix this first** — without XCPM the machine cooks
itself and battery life is catastrophic even by VESA standards.

## 6. Verified running state

From `ioreg` on the installed system. Instance counts are `IOKitDiagnostics`.
Raw dumps: [`research/data/ioreg/`](../research/data/ioreg/) and
[`research/data/kextstat/`](../research/data/kextstat/).

### 6.1 Working — confirmed attached

| Check | Evidence | Meaning |
|---|---|---|
| **XCPM** | `X86PlatformPlugin = 1` | `SSDT-PLUG` on `\_SB.PR00` worked |
| **EC** | `AppleACPIEC = 1` | dummy `Device(EC)` bound; `ECDV` left alone |
| **Battery** | `AppleSmartBattery`, `SMCBatteryManager`, `BatteryManager` all = 1 | full chain |
| **Keyboard** | `ApplePS2Keyboard = 1`, `IOHIKeyboard = 1` | `_CID PNP0303` bound as predicted |
| **Dell thermal** | `SMIMonitor = 1` | SMCDellSensors' worker is live |
| **Bluetooth** | `IOBluetoothHCIController = 1` | controller attached — but see [05b §10.2](05b-wifi-and-bluetooth.md#102-bluetooth--three-kexts-required-not-two), this alone is not "working" |
| **Ethernet** | `IOEthernetController = 1`, `AppleUSBNCMData = 1` | adapter is **NCM class**, native driver — not ASIX |
| **USB map** | 9 ports, exact names — [03](03-usb-mapping.md#62-verified-result) | trimmed `UTBMap` applied |

At install time, on VESA with the stock kexts, `kextstat` showed 13 loaded: Lilu 1.7.2, VirtualSMC 1.3.7, SMCProcessor,
SMCBatteryManager, SMCDellSensors, WhateverGreen 1.7.0, NVMeFix 1.1.3,
ECEnabler 1.0.6, BlueToolFixup 2.7.2, VoodooPS2Controller 2.3.7,
VoodooPS2Keyboard, USBToolBox 1.2.0, IntelBluetoothFirmware 2.4.0.

Two expected absences, neither a fault:

- **`UTBMap.kext`** is plist-only with no executable, so it never shows in
  `kextstat`. Verify via port enumeration instead — [03](03-usb-mapping.md#62-verified-result).
- **`VoodooInput`** only loads for a Voodoo *trackpad*. Ours is USB HID.

### 6.2b Display, with the patched WhateverGreen

These apply to the committed config, which runs Apple's Ice Lake framebuffer
([`research/LAYER3.md`](../research/LAYER3.md)). The numbers earlier in this section were captured on VESA.

| Check | Expected |
|---|---|
| `ioreg -l \| grep -c "class AppleIntelFramebuffer,"` | 3 |
| `AppleIntelFramebuffer@0` | `connector-type = <02000000>`, `built-in`, `AAPL,boot-display` |
| under it | `AppleBacklightDisplay` |
| `system_profiler SPDisplaysDataType` | Intel Iris Plus Graphics, VRAM 1536 MB, 1920 x 1280 @ 60 Hz, Connection Type: Internal |
| `kextstat` | `AppleIntelICLLPGraphicsFramebuffer`, `AppleBacklight`, `BrightnessKeys` |
| Displays → Brightness slider | full range |
| brightness keys | work |
| display sleep and wake | works |

Untested: system sleep, lid close, external displays.

### 6.3 Not working — all expected

| Check | Evidence |
|---|---|
| GPU acceleration | `ioreg -rw0 -c IOAccelerator` is empty. No Metal |
| Audio | `IOAudioDevice = 0`, `IOAudioEngine = 0` — SoundWire, [00 §1.4](00-hardware-survey.md#14-audio--permanently-silent) |
| Camera | no IPU6 driver exists |

---

## 9.2 The ESP is not lettered — mount it first

Unlike the USB stick, the internal EFI System Partition has **no drive letter**.
Every command that touches it must be bracketed:

```powershell
mountvol S: /s        # mount ESP as S:
...                   # do the work
mountvol S: /d        # unmount
```

`mountvol S: /s` requires an **elevated** PowerShell. If you forget the mount,
commands targeting `S:\` fail outright; worse, if a stale `S:` mapping exists
from a previous session you may edit a config that is not the one booting.
**Always re-mount at the start of a session rather than assuming.**

## 9.3 Installing to the internal ESP

Back up the Windows fallback loader before anything:

```powershell
mountvol S: /s
fsutil volume diskfree S:                       # ~170 MB free of 209.7 MB
Copy-Item S:\EFI\BOOT\bootx64.efi S:\EFI\BOOT\bootx64.efi.win-backup -Force
```

Copy OpenCore in, leaving `S:\EFI\Microsoft` untouched:

```powershell
Copy-Item Y:\EFI\OC   S:\EFI\ -Recurse -Force
Copy-Item Y:\EFI\BOOT S:\EFI\ -Recurse -Force
dir S:\EFI                                      # BOOT, Microsoft, OC
```

The EFI is ~30 MB against ~170 MB free — comfortable, but do not accumulate
spare kexts on the ESP.

## 9.4 Two config changes, internal copy ONLY

```powershell
$p = "S:\EFI\OC\config.plist"
$t = Get-Content $p -Raw
$t = $t -replace '(?s)(<key>LauncherOption</key>\s*<string>)Disabled(</string>)', '${1}Full${2}'
$t = $t -replace '(?s)(<key>DmgLoading</key>\s*<string>)Any(</string>)',          '${1}Signed${2}'
[System.IO.File]::WriteAllText($p, $t)
Select-String -Path $p -Pattern 'LauncherOption|DmgLoading' -Context 0,1
Copy-Item $p S:\EFI\OC\config.KNOWNGOOD.plist -Force
mountvol S: /d
```

- `LauncherOption = Full` registers OpenCore as its own NVRAM boot entry
  (`\EFI\OC\OpenCore.efi`) instead of relying on the fallback path.
- `DmgLoading` back to `Signed` — the `Any` workaround was only for
  [§8.2](04-installation.md#82-recovery-entry-still-invisible-after-space) and
  should not be left loose.

**Leave the USB stick at `LauncherOption = Disabled`.** A rescue device must not
write NVRAM boot entries.

That `config.KNOWNGOOD.plist` copy is what every graphics experiment rebuilds
from — see [`research/METHODOLOGY.md`](../research/METHODOLOGY.md).

## 9.5 First internal boot

Remove the USB. Reboot — OpenCore should appear unaided. If not, F12 and pick
the new entry beside Windows Boot Manager. At the picker, highlight Tahoe and
press **Ctrl+Enter** to set default. Reset NVRAM twice if behaviour is odd.

## 9.6 Keep the USB as a rescue device

Do not reformat it. Label it. If an experiment leaves the internal EFI
unbootable, F12 → USB restores a working macOS without touching Windows.

**Test the rescue path while everything is healthy.** A rescue device you have
never booted is not a rescue device.

---

## 11. Baseline snapshot — before touching graphics

```bash
mkdir -p ~/hackintosh-baseline && cd ~/hackintosh-baseline
ioreg -l -w0 > ioreg-baseline.txt
ioreg -rw0 -p IOService -n IGPU > igpu-baseline.txt
log show --last boot --predicate 'sender CONTAINS "AppleIntel"' > gfx-baseline.log
kextstat | grep -v com.apple > kexts-baseline.txt
```

Back up the working `EFI` **off-machine**. You will break it.

> That last predicate is a trap: `sender CONTAINS "AppleIntel"` also matches
> **AppleIntelligenceReporting**. Use
> `'sender CONTAINS "AppleIntelICLLP" OR sender CONTAINS "IOAccelerator"'`
> instead. See [`research/METHODOLOGY.md`](../research/METHODOLOGY.md#diagnostic-traps).

---

Next: [05b — Wi-Fi and Bluetooth](05b-wifi-and-bluetooth.md) ·
[06 — troubleshooting](06-troubleshooting.md)
