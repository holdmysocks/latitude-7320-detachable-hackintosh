// SSDT-PNLF  -  Latitude 7320 Detachable   [ENABLED]
// Backlight device for \_SB.PC00.GFX0 (_ADR 0x00020000).
// AppleBacklight attaches to it once the panel is driven by AppleIntelICLLPGraphicsFramebuffer as a built-in
// (LVDS) display - see research/LAYER3.md.
//
// _UID 19 (0x13) is required. It selects AppleBacklight profile F19Txxxx, whose table spans the full 16-bit range
// that the Ice Lake driver's hwSetBacklight() expects (duty = level * period / 65535). With _UID 15 the table tops
// out at 2777 and "100 %" is about 4 % duty: a nearly black, flickering panel.
DefinitionBlock ("", "SSDT", 2, "OCLT", "PNLF", 0x00000000)
{
    External (_SB_.PC00.GFX0, DeviceObj)

    Device (\_SB.PC00.GFX0.PNLF)
    {
        Name (_ADR, Zero)
        Name (_HID, EisaId ("APP0002"))
        Name (_CID, "backlight")
        Name (_UID, 0x13)
        Name (_STA, 0x0B)
    }
}
