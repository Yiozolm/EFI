/*
 * SSDT-TPD0 for Redmi Book Pro 15 2023: ELAN2310 I2C touchpad in polling mode.
 *
 * Needs the ACPI patch "TPD0 _CRS to XCRS" (Base \_SB.I2CA.TPD0, 5F435253 -> 58435253, Count 1)
 * and SSDT-XOSI (TPD0, I2CA and GPIO are only enabled when the DSDT thinks it runs on Windows 2015).
 *
 * The firmware _CRS has I2cSerialBus (0x15, 400 kHz, \_SB.I2CA) + GpioInt (pin 8 on \_SB.GPIO).
 * VoodooGPIOAMD 1.1 hangs at boot on this Phoenix GPIO controller, and with VoodooGPIO off
 * VoodooI2C panics in VoodooI2CDeviceNub::getGPIOController. Without a GpioInt (and without an
 * APIC Interrupt) VoodooI2C falls back to polling, so under macOS return only the I2C resource.
 * Any other OS gets the firmware's original _CRS.
 */
DefinitionBlock ("", "SSDT", 2, "RMBP15", "TPD0", 0x00001000)
{
    External (_SB_.I2CA, DeviceObj)
    External (_SB_.I2CA.TPD0, DeviceObj)
    External (_SB_.I2CA.TPD0.XCRS, MethodObj)    // 0 Arguments

    Scope (_SB.I2CA.TPD0)
    {
        Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
        {
            If (_OSI ("Darwin"))
            {
                Return (ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0015, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2CA",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                })
            }

            Return (\_SB.I2CA.TPD0.XCRS ())
        }
    }
}
