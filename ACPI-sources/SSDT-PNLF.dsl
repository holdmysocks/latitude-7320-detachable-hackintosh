// SSDT-PNLF  -  Latitude 7320 Detachable   [ENABLED]
// Backlight device for \_SB.PC00.GFX0 (_ADR 0x00020000).
// AppleBacklight attaches to it once the panel is driven by AppleIntelICLLPGraphicsFramebuffer as a built-in
// (LVDS) display - see research/LAYER3.md.
//
// _UID 15 (0x0F) selects AppleBacklight profile F15Txxxx, whose levels run from 0 to 0xAD9 (2777). The Ice Lake
// driver's hwSetBacklight() computes duty = level * period / 65535, so on its own that range gives a nearly black
// panel. The WhateverGreen patch rescales it: boot-arg igfxtglblmax=0xAD9 must match this _UID.
DefinitionBlock ("", "SSDT", 2, "OCLT", "PNLF", 0x00000000)
{
    External (_SB_.PC00.GFX0, DeviceObj)

    Device (\_SB.PC00.GFX0.PNLF)
    {
        Name (_ADR, Zero)
        Name (_HID, EisaId ("APP0002"))
        Name (_CID, "backlight")
        Name (_UID, 0x0F)
        Name (_STA, 0x0B)
    }
}
