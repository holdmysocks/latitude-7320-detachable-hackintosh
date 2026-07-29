// SSDT-RHUB  -  Latitude 7320 Detachable   [DISABLED BY DEFAULT]
// The DSDT declares \_SB.PC00.XHCI.RHUB with static HS01-HS08 / SS01+ port
// devices. It has NO existing _STA, so adding one here is safe.
// Enable ONLY if USB port mapping misbehaves - forces macOS to rebuild the
// port map itself instead of trusting the firmware's declarations.
DefinitionBlock ("", "SSDT", 2, "OCLT", "RHUBoff", 0x00000000)
{
    External (_SB_.PC00.XHCI.RHUB, DeviceObj)

    Method (_SB.PC00.XHCI.RHUB._STA, 0, NotSerialized)
    {
        If (_OSI ("Darwin")) { Return (Zero) }
        Else { Return (0x0F) }
    }
}
