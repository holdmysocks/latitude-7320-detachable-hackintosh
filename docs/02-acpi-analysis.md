# 02 — ACPI analysis

The SSDTs in this repo were generated from this machine's own firmware tables,
not from a template. The dumped tables are in
[`research/data/acpi/`](../research/data/acpi/); the `.dsl` sources for the
four SSDTs we ship are in [`ACPI-sources/`](../ACPI-sources/).

Decompiled with `iasl -da -dl` from the Phase 1 SysReport dump. 78,990 lines.

---

## 4.1 Objects that matter

```
\_SB.PR00 .. PR11          Processor(...) objects inside Scope(_SB)
\_SB.PC00.LPCB.ECDV        real EC, PNP0C09, _STA hardcoded 0x0F
\_SB.PC00.LPCB.PS2K        _HID DLLK0A45, _CID PNP0303, IO 0x60/0x64
\_SB.PC00.GFX0             _ADR 0x00020000
\_SB.PC00.XHCI.RHUB        HS01-HS08 / SS01+, NO _STA method
\_SB.PC00.HDAS.SNDW.SWD0   SoundWire endpoint
\_SB.UBTC                  USBC000/PNP0CA0 (in SSDT-8 "UsbCTabl")
\_SB.IETM                  INTC1040 DPTF (in SSDT-2 "DptfTabl")
```

## 4.2 The `OSYS` finding — this shaped the whole ACPI plan

`_INI` sets `OSYS = 0x03E8` (1000), then raises it only if `_OSI("Windows ...")`
returns true. macOS answers `_OSI` only for `"Darwin"`. **So under macOS,
`OSYS` stays 1000.**

Trace what depends on it:

| Device | Gate | Result under macOS |
|---|---|---|
| `UBTC` (UCSI) | `OSYS >= 0x07DF` | returns `Zero` → **off** |
| `INT33D2` GPIO buttons | `OSYS >= 0x07DD` | **off** |
| `INT33D3/D4` slate/dock | `OSYS >= 0x07DC` | **off** |
| `IETM` DPTF | `\DPTF && \IN34` | **off** |
| `I2C0.TPL0`, `I2C1.TPD0` `_CRS` | `OSYS < 0x07DC` | returns legacy APIC resources |

The last row is the only branch that *does* fire, and it only affects the I2C
touchpad and digitizer — devices we don't use, since the touchpad is USB.

**Therefore: no `SSDT-XOSI`.** Adding one would spoof Windows, raise `OSYS`, and
switch UCSI and DPTF back on for zero benefit. The three devices earlier drafts
planned to disable with `_STA` overrides disable themselves for free.

## 4.3 Other conclusions

- **HPET** uses `Memory32Fixed` only, no `IRQNoFlags` → **no FixHPET needed.**
- **RHUB** has no `_STA`, so an override Method is safe to add. Shipped disabled.
- **EC is `ECDV`, not `EC`** → no rename. Add a dummy `Device(EC)` for
  `AppleACPIEC` and leave `ECDV` driving the battery through the real controller.
- **Processors are `Processor` objects, not `Device` objects** → plain
  `SSDT-PLUG` on `\_SB.PR00`. `SSDT-PLUG-ALT` is for the `Device`-object form.

---

## 5.1 What ships in `EFI/OC/ACPI/`

| File | Enabled | Purpose |
|---|---|---|
| `SSDT-PLUG.aml` | ✅ | `plugin-type=1` on `\_SB.PR00` → attaches `X86PlatformPlugin` (XCPM) |
| `SSDT-EC-USBX.aml` | ✅ | dummy `Device(EC)` in `\_SB.PC00.LPCB` + `USBX` power props (laptop values, 2100 mA) |
| `SSDT-PNLF.aml` | ❌ | backlight on `GFX0`. Cannot work under `-igfxvesa` — `AppleBacklight` needs an accelerated framebuffer |
| `SSDT-RHUB.aml` | ❌ | forces macOS to rebuild the USB port map. Enable only if mapping misbehaves |

`.dsl` sources ship in [`ACPI-sources/`](../ACPI-sources/) so you can read and
rebuild them.

## 5.2 Deliberately absent

- **`SSDT-XOSI`** — see §4.2 above.
- **`SSDT-GPI0`** — only existed to service VoodooI2C. Touchpad is USB.
- **`SSDT-AWAC`** — TGL uses a normal RTC, no AWAC problem in this DSDT.
- **HPET/IRQ patches** — see §4.3 above.

---

Next: [03 — USB mapping](03-usb-mapping.md)
