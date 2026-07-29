# 00 — Hardware survey

Everything below was verified from the machine, not inferred. BIOS **1.46.0**
(2026-03-30).

Source dumps for this page live in
[`research/data/sysreport/`](../research/data/sysreport/).

---

## 1.1 CPU

From `SysReport/CPU/CPUInfo.txt`:

```
CPUID              0x000806C1     family 6, model 0x8C, stepping 1
AppleProcessorType 0x0609         auto-detected -> leave ProcessorType = 0
CpuGeneration      21             OpenCore recognizes Tiger Lake natively
CstConfigLock      1              CFG Lock IS set -> AppleXcpmCfgLock REQUIRED
CPUFrequency       1.8 GHz base   MSR_PLATFORM_INFO 0x804043DF0811200
MSR_TURBO_RATIO    0x2323232323232A2A   -> 4.2 GHz 1-2 core, 3.5 GHz all-core
Cores/Threads      4 / 8
```

`CstConfigLock 1` is the useful one — it converts `AppleXcpmCfgLock` from a
precaution into a confirmed requirement.

## 1.2 Display

From `SysReport/GOP/GOPInfo.txt`:

```
1920x1280, fmt 1, BPP 4
Framebuffer 0x4000000000, size 0x960000   (= 1920*1280*4, checks out)
```

3:2 panel. Framebuffer sits in a 64-bit BAR above 4 GB — hence
`ResizeAppleGpuBars = -1`.

## 1.3 PCI map

| Path | ID | Device | macOS |
|---|---|---|---|
| `Pci(0x0,0x0)` | `8086:9A12` | TGL host bridge | ✅ |
| `Pci(0x2,0x0)` | **`8086:9A40`** | **Iris Xe 80 EU** | ❌ VESA only |
| `Pci(0x4,0x0)` | `8086:9A03` | DPTF participant | ⚪ self-disables |
| `Pci(0x5,0x0)` | `8086:9A19` | **IPU6 camera** | ❌ no driver |
| `Pci(0x6,0x0)/Pci(0x0,0x0)` | `1C5C:174A` | SK hynix BC711 NVMe | ✅ NVMeFix |
| `Pci(0x8,0x0)` | `8086:9A11` | GNA accelerator | ⚪ |
| `Pci(0xD,0x0)` | `8086:9A13` | **TXHC** (TB4 xHCI) | ✅ mapped |
| `Pci(0xD,0x2)` | `8086:9A1B` | USB4 host interface | ⚪ |
| `Pci(0x14,0x0)` | `8086:A0ED` | **XHCI** (PCH) | ✅ mapped |
| `Pci(0x14,0x3)` | `8086:A0F0` | AX201 CNVi Wi-Fi | ⚠️ itlwm only |
| `Pci(0x15,0x0-2)` | `A0E8/9/A` | Serial IO I2C 0/1/2 | ⚪ unused |
| `Pci(0x1F,0x3)` | `8086:A0C8` | **audio, class `0x040100`** | ❌ see below |

**The audio class code is the tell.** `0x040100` is a generic multimedia audio
device. An HD Audio controller reports `0x040300`. Independent PCI-level
confirmation of the SoundWire finding.

Full dump: [`research/data/sysreport/PCIInfo.txt`](../research/data/sysreport/PCIInfo.txt).

## 1.4 Audio — permanently silent

```
INTELAUDIO\CTLR_DEV_A0C8&LINKTYPE_05&DEVTYPE_05&VEN_8086&DEV_AE35
SNDW\...&PART_0711    Realtek RT711  headset codec
SNDW\...&PART_0714    Realtek RT714  mic array
SNDW\...&PART_1316    Realtek RT1316 speaker amp
```

No `HDAUDIO\FUNC_01` device exists on this machine. The DSDT confirms it
structurally too — `Scope(_SB.PC00.HDAS.SNDW)` contains `Device(SWD0)`,
a SoundWire endpoint, where an HDA codec would otherwise live.

macOS has no SoundWire bus driver and no SST/DSP driver:

- **AppleALC can't help** — it injects layouts for HDA-attached codecs.
- **VoodooHDA can't help** — it's an HDA driver.
- **Disabling the DSP in BIOS won't help** — RT711-class parts are
  SoundWire-only silicon, not wired to HDA pins.

**Only path to sound: USB-C DAC or USB headset** (USB Audio Class is native).

## 1.5 Everything else

| Component | Identifier | Status |
|---|---|---|
| Camera | IPU6 + `ACPI\OVTI5678` / `OVTI8856` + `INT3472` | ❌ dead |
| Keyboard | `\_SB.PC00.LPCB.PS2K`, `_HID DLLK0A45`, **`_CID PNP0303`** | ✅ VoodooPS2 |
| Touchpad | USB `044E:1218` Alps HID | ✅ native, no kext |
| Touchscreen/pen | `ACPI\WCOM49A3` Wacom I2C | ❌ no touch layer in macOS |
| Fingerprint | USB `27C6:6384` Goodix | ❌ |
| ControlVault | USB `0A5C:5842` | ❌ |
| WWAN | USB `413C:81D7` DW5821e | ❌ |
| Bluetooth | USB `8087:0026` Intel | ✅ |
| Storage | BC711 256 GB, DRAM-less/HMB | ✅ mediocre writes |

---

## 2. Storage layout

Single 256 GB M.2 2230, ~238 GB usable. BitLocker **off**. SATA mode **AHCI**.
**120 GB unallocated**, ready for macOS.

Shared ESP with **170 MB free** — plenty for OpenCore.

### Dual-boot rules

- OpenCore goes to `\EFI\OC` on the **existing** ESP. Leave `\EFI\Microsoft` alone.
- `LauncherOption` stays **`Disabled`** while running from USB. Only set it to
  `Full` once you're booting from the internal ESP for real.
- Launch Windows *through* the OpenCore picker, not by changing BIOS boot order.
- If a Windows update resets BootOrder: F12 → `\EFI\OC\OpenCore.efi`.

### Fast Startup

`powercfg /h off` — hybrid hibernation leaves NTFS dirty, which makes macOS
mount it read-only at best and produces bizarre USB/NVRAM behaviour on the
next OpenCore boot.

---

Next: [01 — BIOS and Windows prep](01-bios-and-windows-prep.md)
