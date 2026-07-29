# 05b — Wi-Fi and Bluetooth

Both work. Neither works the way a real Mac's does, and the Bluetooth failure
mode is genuinely misleading, so read §10.2 before concluding your adapter is
faulty.

---

## 10.1 Wi-Fi — itlwm + HeliPort ✅ working

`itlwm` v2.3.0's `AirportItlwm` assets stop at **Sonoma 14.4**. There is no
Sequoia or Tahoe build. Use **`itlwm.kext` + the HeliPort app**.

Consequences: no native Wi-Fi menu-bar item, no AirDrop, no Handoff, no
Continuity. It connects to networks; that is the extent of it.

`itlwm.kext` is enabled in the shipped config. It does nothing until HeliPort
is installed and running.

## 10.2 Bluetooth — three kexts required, not two

AX201, USB `8087:0026`, XHCI port `HS10` (correctly mapped —
[03](03-usb-mapping.md#62-verified-result)).

On Monterey and newer **all three** are required:

| Kext | Role |
|---|---|
| `IntelBluetoothFirmware.kext` | uploads firmware, renames the device to "Bluetooth USB Host Controller" |
| `IntelBTPatcher.kext` | **fixes a bug in `bluetoothd` by correctly initialising the module** |
| `BlueToolFixup.kext` | shim for Apple's rewritten Monterey+ Bluetooth stack |

The original EFI shipped only the first and third. **Symptom of the missing
patcher:** the controller attaches (`IOBluetoothHCIController = 1`) and appears
in System Report, but Bluetooth does not actually function — the hardware is up
and `bluetoothd` never initialises it. Easy to misread as a hardware fault.

`IntelBTPatcher` requires **Lilu 1.6.2+** (we ship 1.7.2).

**Load order:** `Lilu` → `IntelBluetoothFirmware` → `IntelBTPatcher` → `BlueToolFixup`

All four are already present and correctly ordered in this repo's
`config.plist`. If you are retrofitting an older EFI that predates the fix,
[`tools/Install-BluetoothFix.ps1`](../tools/Install-BluetoothFix.ps1) inserts
the entry in the right place.

> **`IntelBluetoothInjector.kext` must stay absent.** It ships in the same
> archive but is for Big Sur and earlier; Apple's Monterey Bluetooth rewrite
> made it actively harmful. Do not add it because it is in the zip.

## 10.3 Versions — the fork is ahead of upstream

| Repo | Latest release |
|---|---|
| `OpenIntelWireless/IntelBluetoothFirmware` (upstream) | v2.4.0 |
| `lshbluesky/IntelBluetoothFirmware` (fork) | **v2.5.1** ← in use |

Unusually, the fork leads. It explicitly targets Tahoe 26 and comes from the
same developer as the Tiger Lake framebuffer research
([`research/README.md`](../research/README.md#prior-art)). Upstream has not cut
a release past 2.4.0. Documentation remains upstream's and applies to both:
<https://openintelwireless.github.io/IntelBluetoothFirmware/>

Re-check upstream periodically; if it releases past 2.5.x, prefer it.

## 10.4 Clearing stale Bluetooth state — do NOT reach for Reset NVRAM

Bluetooth controller identity is cached in exactly two NVRAM variables. Stale
values are the usual cause of half-working Bluetooth after a kext change.
Delete only those:

```bash
sudo nvram -d bluetoothActiveControllerInfo
sudo nvram -d bluetoothInternalControllerInfo
```

Reboot. Surgical, and touches nothing else.

**Full Reset NVRAM is not required for this and has side effects.** See §10.5.

## 10.5 Is Reset NVRAM dangerous on this machine?

Short answer: **not a brick risk here, but it is not free either.**

The "NVRAM reset bricked my machine" reports are real but vendor-specific —
HP firmware is the notorious case, where the variable store holds data the
firmware will not regenerate. **Dell business laptops do not do this**: BIOS
settings, service tag and asset data live in a separate flash region that
OpenCore's NVRAM reset does not touch.

What actually happens on this machine:

| Effect | Consequence |
|---|---|
| `BootOrder` wiped | Windows Boot Manager and the OpenCore entry vanish |
| Recovery | F12 → fallback `\EFI\BOOT\BOOTx64.efi`; `LauncherOption = Full` re-registers OpenCore on the next good boot |
| BitLocker re-trigger | N/A — BitLocker is off ([01](01-bios-and-windows-prep.md#bitlocker)) |
| Secure Boot measured state | N/A — already disabled |
| Dell BIOS settings | unaffected |

So it is a self-inflicted boot-entry cleanup, not damage. Reasonable to use when
behaviour is inconsistent between identical boots; unnecessary for routine kext
changes. Prefer §10.4 first.

> If you do reset and the machine boots straight to Windows afterwards, that is
> the wiped `BootOrder`, not a failure. F12 → OpenCore → `Ctrl+Enter` to restore
> the default.

## 10.6 Bluetooth expectations

Intel Bluetooth is only partly compatible with Apple's drivers and has limited
functionality:

- BT **5.x** devices should pair normally.
- BT **4.x** devices may fail to connect. This also happens on **real Macs**
  with Intel modules — not a Hackintosh defect.
- **Handoff, Continuity, AirDrop, Unlock-with-Watch will not work.** Those
  require a native AirPort device; `itlwm` presents as Ethernet. Working
  Bluetooth does not change this.
- Bluetooth audio may work but is unreliable. For the SoundWire-silent audio
  problem ([00 §1.4](00-hardware-survey.md#14-audio--permanently-silent)), a
  USB-C DAC remains the dependable answer.

## 10.7 Verify

```bash
kextstat | grep -i intelbt
system_profiler SPBluetoothDataType | head -30
ioreg -l -w0 | grep -c IOBluetoothHCIController
```

---

Next: [06 — troubleshooting](06-troubleshooting.md)
