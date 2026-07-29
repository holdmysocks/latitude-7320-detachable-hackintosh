// SSDT-EC-USBX  -  Latitude 7320 Detachable
// Real EC is \_SB.PC00.LPCB.ECDV  (PNP0C09, _STA always 0x0F).
// Because it is NOT named "EC", no rename is required - we simply add a
// dummy Device(EC) for macOS's AppleACPIEC to bind to, leaving ECDV alone
// so battery reporting keeps working through the real controller.
// USBX supplies USB power properties (laptop values, 2100 mA).
DefinitionBlock ("", "SSDT", 2, "OCLT", "ECUSBX", 0x00000000)
{
    External (_SB_.PC00.LPCB, DeviceObj)

    Scope (\_SB.PC00.LPCB)
    {
        Device (EC)
        {
            Name (_HID, "ACID0001")
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin")) { Return (0x0F) }
                Else { Return (Zero) }
            }
        }
    }

    Scope (\_SB)
    {
        Device (USBX)
        {
            Name (_ADR, Zero)
            Method (_DSM, 4, NotSerialized)
            {
                If ((Arg2 == Zero)) { Return (Buffer (One) { 0x03 }) }
                Return (Package (0x08)
                {
                    "kUSBSleepPowerSupply",      0x13EC,
                    "kUSBSleepPortCurrentLimit", 0x0834,
                    "kUSBWakePowerSupply",       0x13EC,
                    "kUSBWakePortCurrentLimit",  0x0834
                })
            }
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin")) { Return (0x0F) }
                Else { Return (Zero) }
            }
        }
    }
}
