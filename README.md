# Redmi Book Pro 15 2023 (Ryzen 7 7840HS) — OpenCore EFI

Adapted from [firebat-u6c-hackintosh-efi](../firebat-u6c-hackintosh-efi) (Ryzen 7 H 255 / Radeon 780M — the same Phoenix
silicon). The hardware was read from this machine under Windows; the ACPI names used below come from its own DSDT.

**Status: not boot-tested yet.** Treat it as a starting point.

## Detected hardware

| Component | Device | macOS |
|---|---|---|
| CPU | Ryzen 7 7840HS, 8C/16T (Family 19h Model 74h) | ✅ AMD Vanilla patches, core count = 8 |
| iGPU | Radeon 780M `1002:15BF` rev C7, 512 MB UMA | ⚠️ Metal via nullarc (alpha, Tahoe 26.6), spoofed to `1900` — see below |
| Display | 15.6" 3200×2000 120 Hz | ⚠️ Booted at 2560×1600 for nullarc; no backlight control yet |
| Wi-Fi | MediaTek MT7922 `0B48:7922` at `GPP6.WLAN` | ❌ **No macOS driver — swap the card** |
| Bluetooth | MediaTek `35F5:7922` (USB, XHC0 port 5) | ❌ Goes away with the card swap |
| NVMe | KIOXIA BG5 KBG50ZNV512G `1E0F:000C` | ✅ NVMeFix enabled |
| Audio | Senary SN6140 `14F1:1F86` | ❓ Depends on AppleALC support (see below) |
| Touchpad | ELAN2310 I2C (`I2CA.TPD0`, AMDI0010) | ✅ VoodooI2C + VoodooI2CHID |
| Keyboard | PS/2 `FUJ7401` (`KBC0`) | ✅ VoodooPS2Keyboard |
| Webcam | Xiaomi `2B7E:C687` on `GP17.XHC1` port 1 | ❌ Disabled by `SSDT-USB-Reset` (avoids 60 s boot hang) |
| Card reader | Realtek RTS525A | ❌ RealtekCardReader stops at Sonoma |
| Fingerprint | FPC `10A5:9201` | ❌ Never works |
| USB4 / TB | `NHI0`/`NHI1` | ❌ USB-C still works as USB 3 |
| Battery | `EC0` + `BATT` | ✅ SMCBatteryManager (+ ECEnabler, see below) |

## What changed vs. the Firebat EFI

- `SSDT-EC.aml`: re-targeted from `\_SB.PCI0.SBRG` to `\_SB.PCI0.LPC0` (this DSDT has no `SBRG`). AML checksum fixed.
- `SSDT-CPUR`, `SSDT-USB-Reset`, `SSDT-ALS0`, `SSDT-USBX`, `SSDT-RMNE`: kept as-is — the paths (`PLTF.C000..C00F`, `GP17.XHC1`) match.
- Audio `DeviceProperties` path `PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x6)` matches this laptop's HDA controller.
- Kexts on: SMCBatteryManager, BrightnessKeys, NVMeFix, BlueToolFixup, IntelBluetoothFirmware, IntelBTPatcher.
- Kexts removed: RtWlanU, RtWlanU1827, RealtekBluetoothFirmware (Firebat's USB dongle), RDNA3Driver, DebugEnhancer.
- `revcpuname` set to the 7840HS.
- nullarc prep: GPU `device-id` spoof to `1900`, PhxBringup entry (disabled), `phxdebug=1`, GOP resolution 2560×1600.
- **SMBIOS serials cleared** — never reuse another machine's serials. Generate your own (step 3).

## What you need to do

### 1. Replace the Wi-Fi card: MT7922 → Intel AX200 or AX210

MediaTek MT7922 has no macOS driver, and none is coming. Buy an **Intel AX210** (Wi-Fi 6E, same class as the MT7922) or
**AX200** (Wi-Fi 6). Both are M.2 2230 A+E key, same as the stock card, and both work with itlwm.

- Get the non-vPro retail card ("AX210NGW"/"AX200NGW"). Skip the "AX201"/"AX211"/"AX411" CNVi cards — they need an Intel
  chipset and **will not work on AMD**.
- Swap: unplug the battery connector first, move the two antenna leads (MAIN/AUX) across, one screw.
- Bluetooth comes along on the same card (USB line to XHC0 port 5). The BT kexts are already enabled.

### 2. Add the Wi-Fi and battery kexts

These are already in `config.plist` as **disabled** entries. Copy the kext into `EFI/OC/Kexts/`, then set `Enabled` to `true`:

- **itlwm.kext** ([OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm/releases)) + the
  [HeliPort](https://github.com/OpenIntelWireless/HeliPort/releases) app to join networks. Best choice on Tahoe.
  Alternatively replace the bundled `AirportItlwm.kext` (a Sonoma 2.3.0 build) with one built for your macOS version and
  enable that instead — **never both**.
- **ECEnabler.kext** ([1Revenger1/ECEnabler](https://github.com/1Revenger1/ECEnabler/releases)) — lets SMCBatteryManager
  read the EC's 16-bit battery fields without DSDT patches.

### 3. Generate your own SMBIOS

Run [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) → model `MacBookPro16,1` → put the Serial, Board Serial (MLB),
SmUUID into `PlatformInfo > Generic`, and your real Ethernet/Wi-Fi MAC (no colons) into `ROM`. Check the serial shows
"invalid" at checkcoverage.apple.com.

### 4. BIOS settings

Secure Boot **off**; UMA frame buffer as high as the BIOS allows (often hidden on Xiaomi BIOS); fast boot off. TPM can stay.

### 5. First boot, then fix-ups

- **USB map**: in Windows, run [USBToolBox](https://github.com/USBToolBox/tool) → build `UTBMap.kext`, drop it in, enable
  `USBToolBox.kext` + `UTBMap.kext`. `SSDT-USB-Reset` disables all of `XHC1`'s root hub — if a physical USB port stops
  working in macOS, it lives on XHC1; tell me and I'll narrow the SSDT to just the webcam port.
- **Audio**: macOS Tahoe no longer ships `AppleHDA.kext`, so AppleALC alone gives no sound. AppleHDA has to be restored
  (OpenCore Legacy Patcher), *and* AppleALC must support the Senary SN6140. Check the
  [AppleALC Supported Codecs](https://github.com/acidanthera/AppleALC/wiki/Supported-codecs) page; if it isn't listed,
  use a USB audio adapter or Bluetooth headphones.
- **AC adapter**: the Firebat needed nullarc's `hardware/acpi/SSDT-ADP1` because its `_PSR` fails under macOS. This
  laptop's adapter is `\_SB.ACAD` with `EC0` under `LPC0`. If macOS shows "not charging" while plugged in, the same
  fix is needed, but with those paths.
- Once things work, trim boot-args (drop `-v`, `debug=0x100`, `keepsyms=1`).

## Graphics acceleration with nullarc

[../nullarc](../nullarc) gives the 780M Metal 3 and a GPU-composited desktop on **macOS Tahoe 26.6**. It's alpha, and it
has only been tested on the Firebat U6C. Without it you get a framebuffer only (slow UI, no Metal apps).

### Already done in this EFI

| Setting | Why |
|---|---|
| `DeviceProperties` → `PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)` → `device-id` = `00190000` | This laptop's 780M is `1002:15BF` (Phoenix1); nullarc's kexts only match `1002:1900` (Hawk Point, the Firebat). Same gfx1103 / GC 11.0.1 silicon and the same firmware — nullarc's own Mesa patch says so — so the GPU is presented as `1900`. |
| `Kernel → Add` → `PhxBringup.kext`, `MinKernel 25.0.0`, after VirtualSMC, **disabled** | Turn it on once the kext is in `EFI/OC/Kexts`. |
| boot-args: `amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta phxdebug=1`, `csr-active-config 7F080000`, `SecureBootModel Disabled` | nullarc's requirements (`AMFIPass.kext` is already enabled). |
| `UEFI → Output → Resolution` = `2560x1600@32` | See the warning below. |

> [!WARNING]
> **Boot framebuffer size.** nullarc's bring-up puts GPU structures at fixed offsets in VRAM: the PSP ring at 17 MiB
> (`psp create 0x1100000`) and the TMR at 20 MiB. The firmware's boot framebuffer sits at the start of VRAM. At the
> Firebat's 2560×1600 it ends at 16.4 MB; at this panel's native 3200×2000 it would end at ~24.4 MiB and overlap both. So
> OpenCore asks GOP for 2560×1600, and nullarc takes over whatever mode GOP lit, so macOS runs at 2560×1600 scaled onto
> the panel (a little soft).
> In the OpenCore log, check that the 2560×1600 mode was actually set. If GOP doesn't offer it, use `1920x1200@32`.
> **Never boot nullarc at 3200×2000** unless the offsets in `src/phxbringup/PhxNativeABI.h` and `tools/phxctl/bringup*.sh`
> have been moved above the framebuffer.

### Steps (after macOS Tahoe 26.6 installs and boots without nullarc)

1. Get `nullarc-<version>.zip` from the [releases page](https://github.com/luuumi-dev/nullarc/releases) (or build
   `PhxBringup.kext` with `src/phxbringup/build.sh` on the Mac).
2. Copy `EFI/OC/Kexts/PhxBringup.kext` into this EFI, set its `Enabled` to `true`, reboot.
   `ioreg -l | grep phx-build` must print a line.
3. `ioreg -l | grep '"device-id"'` on the GPU should read `<00190000>`. If not, the spoof path is wrong.
4. Turn on automatic login, then `sudo ./install.sh --check`, then `sudo ./install.sh --windowserver`, and reboot twice.
5. Check `/var/log/phxboot.log` ends with `done`, and System Information → Graphics shows Metal 3.

Keep a USB installer and a copy of this EFI. phxboot falls back to the firmware framebuffer by itself after failed
boots. To turn the GPU off by hand: `sudo touch /Users/Shared/gpu/phxboot-off`. To remove nullarc: `sudo ./uninstall.sh`, then
disable PhxBringup.

**Still missing in nullarc:** external displays (HDMI/USB-C), video decode/encode, backlight control. `amfi=0x80` also
breaks FairPlay playback (Apple TV+, Netflix in Safari). Sleep is usually broken on AMD laptops; display sleep/wake works.

**UMA VRAM:** the BIOS gives the 780M 512 MB (the Firebat has 4 GB). nullarc's 512 MB VRAM pool comes from macOS
system RAM, and its fixed carve-out offsets end below ~200 MB, so 512 MB should be enough. If you can raise it (Xiaomi
hides the option), 1–2 GB is a safer margin.
