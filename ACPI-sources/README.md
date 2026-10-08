# ACPI sources

Four SSDTs, all generated from this machine's own dumped tables rather than
from a template. The compiled `.aml` files are in
[`../EFI/OC/ACPI/`](../EFI/OC/ACPI/); these are the readable sources.

Rebuild with [`iasl`](https://github.com/acpica/acpica):

```bash
iasl -ve SSDT-PLUG.dsl        # produces SSDT-PLUG.aml
```

The analysis that produced them is in
[`../docs/02-acpi-analysis.md`](../docs/02-acpi-analysis.md).

---

## What ships, and why

### `SSDT-PLUG.dsl` — enabled

Attaches `X86PlatformPlugin` (XCPM) by declaring `plugin-type = 1`.

The target path is the whole point. This DSDT declares processors as
`Processor(PR00..PR11)` objects **inside `Scope(_SB)`**, so the path is
`\_SB.PR00`. The commonly-published `SSDT-PLUG-ALT` targets the
`Device`-object form (`\_SB.PCI0.CPU0` and friends) and does nothing here.

Verify it took: `X86PlatformPlugin = 1` in `ioreg`, and frequency stepping
under `powermetrics`.

### `SSDT-EC-USBX.dsl` — enabled

Two jobs in one table.

**The dummy EC.** The real embedded controller is `\_SB.PC00.LPCB.ECDV`
(`PNP0C09`, `_STA` hardcoded `0x0F`). Because it is **not** named `EC`, macOS's
`AppleACPIEC` will not bind to it — but equally, **no rename is required**. We
add an empty `Device(EC)` with `_HID "ACID0001"` for `AppleACPIEC` to bind to,
gated on `_OSI("Darwin")`, and leave `ECDV` alone so battery reporting keeps
working through the real controller.

**`USBX`.** Supplies USB power properties at laptop values (`0x0834` = 2100 mA
port current limit).

### `SSDT-PNLF.dsl` — enabled

Backlight device under `\_SB.PC00.GFX0` (`_ADR 0x00020000`). `AppleBacklight` attaches to it now that the panel is
driven by Apple's framebuffer as a built-in display.

**`_UID` is 15 and pairs with the boot-arg `igfxtglblmax=0xAD9`.** `_UID` 15 selects AppleBacklight profile
`F15Txxxx`, whose levels end at `0xAD9` (2777); the Ice Lake driver expects a 16-bit range, so the WhateverGreen
patch rescales by that maximum. Without the boot-arg full brightness is about 4 % duty. Change one, change the
other (`_UID` 19 would need `igfxtglblmax=0xFFFF`, the default).

The firmware's own tables define no `PNLF` device (the `PNLF` name in the DSDT is an unrelated field), so there is no
conflict. See [`../research/LAYER3.md`](../research/LAYER3.md#6-backlight).

### `SSDT-DOSI.dsl` — enabled

Presets the firmware's Dell-specific OS identity (`\_SB.ACOS = 0x20`, `\_SB.ACSE = 0`) on Darwin, at table load,
and repeats `\_SB.STOS ()` from its `_INI`. Without it the firmware never sends `Notify (LCD, 0x86/0x87)` and the
brightness keys do nothing. Why it has to run that early:
[`../research/LAYER3.md`](../research/LAYER3.md#brightness-keys).

### `SSDT-RHUB.dsl` — shipped disabled

Returns `Zero` from `\_SB.PC00.XHCI.RHUB._STA` under Darwin, which forces macOS
to rebuild the USB port map itself instead of trusting the firmware's
declarations.

The DSDT declares `RHUB` with static `HS01`–`HS08` / `SS01+` port devices and
**no existing `_STA`**, so adding one here is safe — an override that collides
with an existing method would not be.

Enable **only** if USB port mapping misbehaves. With the trimmed `UTBMap` in
place it is unnecessary — see [`../docs/03-usb-mapping.md`](../docs/03-usb-mapping.md).

---

## What is deliberately absent

This list matters as much as the list above. Each of these appears in most
Tiger Lake guides and each is wrong for this machine.

### No `SSDT-XOSI`

`_INI` sets `OSYS = 0x03E8` and only raises it when `_OSI("Windows ...")`
returns true. macOS answers `_OSI` only for `"Darwin"`, so **`OSYS` stays 1000
under macOS** — and every device gated on a higher `OSYS` turns itself off for
free: `UBTC` (UCSI), `INT33D2` GPIO buttons, `INT33D3/D4` slate/dock, `IETM`
(DPTF).

Adding `SSDT-XOSI` would spoof Windows, raise `OSYS`, and switch UCSI and DPTF
back **on** for zero benefit. The only `OSYS < 0x07DC` branch that does fire
returns legacy APIC resources for the I2C touchpad and digitizer — devices we
don't use, since the touchpad is USB.

`OSYS` is not the only OS check in this firmware. Hotkey dispatch uses a second, Dell-specific one,
`\_SB.OSID ()`. That one does need an answer, or the brightness keys are dead; `SSDT-DOSI` gives it without
touching `_OSI` or `OSYS`.

Full trace: [`../docs/02-acpi-analysis.md`](../docs/02-acpi-analysis.md#42-the-osys-finding--this-shaped-the-whole-acpi-plan).

### No `SSDT-GPI0`

Only ever existed to service VoodooI2C. The touchpad on this machine is USB
(`044E:1218` Alps HID) and needs no kext at all.

### No `SSDT-AWAC`

Tiger Lake here uses a normal RTC. There is no AWAC/`RTC0` conflict in this
DSDT.

### No HPET or IRQ patches

`HPET` declares `Memory32Fixed` only, with no `IRQNoFlags`. There is nothing
for `FixHPET` to fix.

### No EC rename

Covered above — `ECDV` is not called `EC`, so nothing collides.
