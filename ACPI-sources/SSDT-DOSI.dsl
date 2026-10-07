/*
 * SSDT-DOSI: Dell OS identification for macOS.
 *
 * The Latitude 7320 firmware decides what to do with hotkeys (brightness, lid) from \_SB.OSID (), which caches its
 * answer in \_SB.ACOS / \_SB.ACSE after asking _OSI for Windows versions. macOS answers "no" to all of them, so ACOS
 * becomes 1 and SMEE never calls EV6 -> GFX0.BRT6 -> Notify (LCD, 0x86/0x87): the brightness keys are dead.
 * The firmware also reports the value to SMM (\_SB.STOS, during \_SB.PC00._INI) and to the EC (ECS2, in the EC's _REG).
 *
 * This table presets the cache to the value the firmware computes for Windows Vista (ACOS = 0x20, ACSE = 0), on Darwin
 * only. That is the smallest value that passes "OSID () >= 0x20". The Windows 8+ flag ACSE stays 0, so every
 * "OIDE () >= 1" branch (I2C, power, WMI) behaves as before.
 *
 * Revision 2: revision 1 set the values from a device's _INI, which runs after the DSDT's own _INI methods, so SMM had
 * already been told "legacy OS". The preset is now module-level code (runs when the table is loaded, before any _INI),
 * and _INI repeats it and calls STOS () so SMM gets the value even if the load-time code ran late.
 */
DefinitionBlock ("", "SSDT", 2, "TGL", "DOSI", 0x00000002)
{
    External (_SB_.ACOS, IntObj)
    External (_SB_.ACSE, IntObj)
    External (_SB_.STOS, MethodObj)    // 0 Arguments

    If (_OSI ("Darwin"))
    {
        \_SB.ACOS = 0x20
        \_SB.ACSE = Zero
    }

    Scope (\_SB)
    {
        Device (DOSI)
        {
            Name (_HID, "TGL0001")  // _HID: Hardware ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (_OSI ("Darwin"))
                {
                    Return (0x0F)
                }

                Return (Zero)
            }

            Method (_INI, 0, NotSerialized)  // _INI: Initialize
            {
                \_SB.ACOS = 0x20
                \_SB.ACSE = Zero
                \_SB.STOS ()
            }
        }
    }
}
