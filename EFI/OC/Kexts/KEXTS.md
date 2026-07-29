# Kexts

**No third-party kext binaries are committed to this repository.** Every one of
them is someone else's work under someone else's licence, and a vendored copy
goes stale the week after it is committed. Fetch them instead:

```powershell
..\..\..\tools\fetch-components.ps1        # Windows
```

```bash
../../../tools/fetch-components.sh         # macOS / Linux
```

Both scripts pull the exact versions in the table below from each project's
GitHub releases and unpack them here.

The one exception is `UTBMap.kext`, which **is** committed — it is plist-only
with no executable, it was generated for this specific machine, and it is
useless to anyone else's hardware. See
[`../../../docs/03-usb-mapping.md`](../../../docs/03-usb-mapping.md).

---

## Load order

Order in `Kernel > Add` is significant in three places. The shipped
`config.plist` already has it right.

| # | Kext | On | Version | Why |
|---|---|---|---|---|
| 1 | `Lilu` | ✅ | 1.7.2 | patch engine — **must be first** |
| 2 | `VirtualSMC` | ✅ | 1.3.7 | SMC emulation |
| 3 | `SMCProcessor` | ✅ | 1.3.7 | CPU temperatures |
| 4 | `SMCBatteryManager` | ✅ | 1.3.7 | battery |
| 5 | `SMCDellSensors` | ✅ | 1.3.7 | Dell SMM fan/thermal |
| 6 | `WhateverGreen` | ✅ | 1.7.0 | non-GPU quirks; also the subject of the graphics research |
| 7 | `NVMeFix` | ✅ | 1.1.3 | BC711 power management |
| 8 | `ECEnabler` | ✅ | 1.0.6 | Dell EC >8-bit battery fields |
| 9 | `VoodooPS2Controller` | ✅ | 2.3.7 | keyboard (PS/2, even though the touchpad is USB) |
| 10 | `itlwm` | ✅ | 2.3.0 | Wi-Fi — needs the HeliPort app |
| 11 | `IntelBluetoothFirmware` | ✅ | **2.5.1** | BT firmware upload — fork build, see below |
| 12 | `IntelBTPatcher` | ✅ | 2.5.1 | **required on Monterey+** — initialises `bluetoothd` |
| 13 | `BlueToolFixup` | ✅ | 2.7.2 | Monterey+ BT stack shim |
| 14 | `VoodooPS2Keyboard` (plugin) | ✅ | 2.3.7 | inside `VoodooPS2Controller.kext` |
| 15 | `VoodooInput` (plugin) | ✅ | 2.3.7 | inside `VoodooPS2Controller.kext` |
| 16 | `USBToolBox` | ✅ | 1.2.0 | port-map driver — **must precede `UTBMap`** |
| 17 | `UTBMap` | ✅ | — | the 9-port map (committed here) |

The three ordering constraints:

1. `Lilu` before everything that depends on it.
2. `IntelBluetoothFirmware` → `IntelBTPatcher` → `BlueToolFixup`, in that order.
3. `USBToolBox` before `UTBMap`, or the map silently does nothing.

## Where to get each one

| Kext | Upstream | Licence |
|---|---|---|
| Lilu | <https://github.com/acidanthera/Lilu> | BSD-3-Clause |
| VirtualSMC + SMC* plugins | <https://github.com/acidanthera/VirtualSMC> | BSD-3-Clause |
| WhateverGreen | <https://github.com/acidanthera/WhateverGreen> | BSD-3-Clause |
| NVMeFix | <https://github.com/acidanthera/NVMeFix> | BSD-3-Clause |
| BlueToolFixup | <https://github.com/acidanthera/BrcmPatchRAM> | BSD-3-Clause |
| ECEnabler | <https://github.com/1Revenger1/ECEnabler> | BSD-3-Clause |
| VoodooPS2Controller | <https://github.com/acidanthera/VoodooPS2> | BSD-3-Clause |
| USBToolBox kext | <https://github.com/USBToolBox/kext> | BSD-3-Clause |
| itlwm | <https://github.com/OpenIntelWireless/itlwm> | GPL-3.0 |
| IntelBluetoothFirmware / IntelBTPatcher | <https://github.com/lshbluesky/IntelBluetoothFirmware> | GPL-2.0 |

`SMCProcessor`, `SMCBatteryManager` and `SMCDellSensors` ship inside the
VirtualSMC release archive, not as separate downloads.

## ⚠️ Bluetooth: use the fork, and mind what you leave out

| Repo | Latest release |
|---|---|
| `OpenIntelWireless/IntelBluetoothFirmware` (upstream) | v2.4.0 |
| `lshbluesky/IntelBluetoothFirmware` (fork) | **v2.5.1** ← in use |

The fork leads upstream here, which is unusual. It explicitly targets Tahoe 26.
Re-check upstream periodically; if it releases past 2.5.x, prefer it.

> **`IntelBluetoothInjector.kext` must stay absent.** It ships in the same
> archive but is for Big Sur and earlier; Apple's Monterey Bluetooth rewrite
> made it actively harmful. Do not add it because it is in the zip.

## Deliberately absent

- **`AppleALC`** — there is no HDA codec on this machine to inject a layout
  into. The codecs are RT711/RT714/RT1316 on SoundWire. See
  [`../../../docs/00-hardware-survey.md`](../../../docs/00-hardware-survey.md#14-audio--permanently-silent).
- **All VoodooI2C components** — the touchpad is USB HID (`044E:1218` Alps) and
  needs no kext at all.
- **`IntelBluetoothInjector`** — see above.
- **`AirportItlwm`** — v2.3.0's builds stop at Sonoma 14.4. There is no Tahoe
  build. Use `itlwm.kext` + HeliPort.

## Expected `kextstat` absences

Neither of these is a fault:

- **`UTBMap.kext`** is plist-only, so it never appears in `kextstat`. Verify by
  port enumeration.
- **`VoodooInput`** only loads for a Voodoo *trackpad*. Ours is USB HID.
