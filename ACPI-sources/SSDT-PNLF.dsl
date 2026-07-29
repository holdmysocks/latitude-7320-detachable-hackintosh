// SSDT-PNLF  -  Latitude 7320 Detachable   [DISABLED BY DEFAULT]
// Backlight control for \_SB.PC00.GFX0 (_ADR 0x00020000).
// Cannot function while running -igfxvesa: AppleBacklight needs an
// accelerated framebuffer to attach to. Present for the day that changes.
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
