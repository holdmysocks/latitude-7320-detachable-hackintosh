# 03 — USB mapping

Two controllers, nine real ports. The map ships as
[`EFI/OC/Kexts/UTBMap.kext`](../EFI/OC/Kexts/UTBMap.kext/Contents/Info.plist)
— it is plist-only, no binary, so it is the one kext this repo does vendor.

---

## 6.4 The two controllers

| Controller | ACPI | PCI | Role |
|---|---|---|---|
| `XHCI` | `\_SB.PC00.XHCI` | `8086:A0ED` | PCH — internals + **USB2 half** of both Type-C |
| `TXHC` | `\_SB.PC00.TXHC` | `8086:9A13` | TB4 — **USB3 half** of both Type-C |

Both halves of each USB-C port live on *different* controllers. That is normal
for Tiger Lake and it is why both controllers must be mapped.

## The nine ports

Types: **9** = Type-C (no switch), **255** = Internal.

### XHCI — `port-count` 15

| Port | Index | Type | What is on it |
|---|---|---|---|
| `HS01` | 1 | 9 | USB-C left (USB2 personality) |
| `HS02` | 2 | 255 | Goodix fingerprint |
| `HS03` | 3 | 255 | Broadcom ControlVault |
| `HS04` | 4 | 255 | Alps keyboard cover / touchpad |
| `HS06` | 6 | 9 | USB-C right (USB2 personality) |
| `HS10` | 10 | 255 | Intel Bluetooth |
| `SS03` | 15 | 255 | DW5821e WWAN |

### TXHC — `port-count` 3

| Port | Index | Type | What is on it |
|---|---|---|---|
| `SS01` | 2 | 9 | USB-C left (USB3 personality) |
| `SS02` | 3 | 9 | USB-C right (USB3 personality) |

## ⚠️ Two traps, both of which cost real time

> **USBToolBox defaults to selecting *every* port.** The originally submitted
> map declared 16 ports on XHCI and 5 on TXHC. Sixteen exceeds macOS's hard
> 15-per-controller limit, which defeats the entire purpose of mapping; and
> eleven of them had nothing attached but were typed 255 (Internal), so macOS
> would enumerate eleven phantom internal ports. Trim to the ports that
> physically exist.
>
> **A map built in *USBToolBox mode* declares
> `OSBundleLibraries: com.dhinakg.USBToolBox.kext`.** That base kext must be
> present and ordered **before** `UTBMap` in `Kernel > Add`, or the map
> silently does nothing and you get unmapped-USB symptoms that look like
> other bugs.

The untrimmed original is kept for comparison at
[`research/data/usb/UTBMap-untrimmed-Info.plist`](../research/data/usb/UTBMap-untrimmed-Info.plist),
alongside the raw USBToolBox topology dump
[`usb.json`](../research/data/usb/usb.json).

## 6.2 Verified result

Nine ports, names matching the trimmed map, each with the predicted device.
This is the proof the map applied — unmapped there would be 16 on XHCI.

| Port | Device found |
|---|---|
| TXHC `SS01` | (empty) — USB-C, USB3 |
| TXHC `SS02` | USB3.1 Hub |
| XHCI `HS01` | USB2.1 Hub |
| XHCI `HS02` | Goodix Fingerprint ✅ |
| XHCI `HS03` | `58200` Broadcom ControlVault ✅ |
| XHCI `HS04` | Alps Touchpad ✅ |
| XHCI `HS06` | (empty) — USB-C, USB2 |
| XHCI `HS10` | Bluetooth USB Host Controller ✅ |
| XHCI `SS03` | DW5821e Snapdragon X20 LTE ✅ |

`@14N00000` addresses renumber sequentially after mapping — that is enumeration
order, not the original port index. **Judge by name, not address.**

> `"USBToolBox" = 0` instances shows in `IOKitDiagnostics` despite the kext
> being loaded. Ignore it; the enumeration above is authoritative.

`UTBMap.kext` is plist-only with no executable, so it **never shows in
`kextstat`**. Verify by port enumeration, not by `kextstat`.

## Rebuilding the map for a different machine

The shipped map is specific to this exact Latitude 7320 Detachable
configuration. On any other machine, build your own:

1. Run [USBToolBox](https://github.com/USBToolBox/tool) on Windows, in
   **USBToolBox mode**, with a USB2 and a USB3 device to hand.
2. Plug something into every physical port, twice — once with a USB2 device,
   once with USB3 — so both personalities get discovered.
3. Select only the ports that lit up. Keep each controller at or under 15.
4. Build the kext, drop it in `EFI/OC/Kexts/`, and add a `Kernel > Add` entry
   **after** `USBToolBox.kext`.

If macOS still enumerates the firmware's ports rather than yours, enable
`SSDT-RHUB.aml` — see [02 — ACPI analysis](02-acpi-analysis.md#51-what-ships-in-efiocacpi).

---

Next: [04 — installation](04-installation.md)
