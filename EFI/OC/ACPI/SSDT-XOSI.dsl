/*
 * SSDT-XOSI for Redmi Book Pro 15 2023 (Ryzen 7 7840HS).
 *
 * Needs the ACPI patch "_OSI to XOSI" (5F4F5349 -> 584F5349), which OpenCore applies to the
 * firmware's tables only, so the _OSI calls below stay real.
 *
 * Why: the DSDT only enables the touchpad path when it believes it runs on Windows:
 *   \_SB.GPIO._STA and \_SB.I2CA._STA need TSOS >= 0x70  (_OSI "Windows 2015")
 *   \_SB.I2CA.TPD0._STA (ELAN2310) needs TPOS >= 0x60     (_OSI "Windows 2012" or later)
 * The newest string the DSDT asks for is "Windows 2015".
 *
 * Under macOS: answer yes to the Windows strings below (and keep answering for "Darwin").
 * Under any other OS booted through OpenCore (Windows): pass through to the real _OSI.
 */
DefinitionBlock ("", "SSDT", 2, "RMBP15", "XOSI", 0x00002000)
{
    Method (XOSI, 1, NotSerialized)
    {
        If (_OSI ("Darwin"))
        {
            Local0 = Package (0x0B)
                {
                    "Windows 2001",
                    "Windows 2001.1",
                    "Windows 2001 SP1",
                    "Windows 2001 SP2",
                    "Windows 2001 SP3",
                    "Windows 2006",
                    "Windows 2006 SP1",
                    "Windows 2009",
                    "Windows 2012",
                    "Windows 2013",
                    "Windows 2015"
                }
            If ((Match (Local0, MEQ, Arg0, MTR, Zero, Zero) != Ones))
            {
                Return (Ones)
            }

            Return (_OSI (Arg0))
        }

        Return (_OSI (Arg0))
    }
}
