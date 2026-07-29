// SSDT-PLUG  -  Latitude 7320 Detachable
// Enables X86PlatformPlugin (XCPM) on CPU0.
// DSDT declares Processor(PR00..) inside Scope(_SB) -> path is \_SB.PR00
DefinitionBlock ("", "SSDT", 2, "OCLT", "CpuPlug", 0x00000000)
{
    External (_SB_.PR00, ProcessorObj)
    Scope (\_SB.PR00)
    {
        Method (_DSM, 4, NotSerialized)
        {
            If ((Arg2 == Zero)) { Return (Buffer (One) { 0x03 }) }
            Return (Package (0x02) { "plugin-type", One })
        }
    }
}
