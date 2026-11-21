# Redmi Book Pro 15 2023 (Ryzen 7 7840HS) — OpenCore EFI

Adapted from [firebat-u6c-hackintosh-efi](../firebat-u6c-hackintosh-efi) (Ryzen 7 H 255 / Radeon 780M — the same Phoenix
silicon). The hardware was read from this machine under Windows; the ACPI names used below come from its own DSDT.

**Status (2026-11-19): boots the macOS Tahoe 26.6 recovery (Darwin 25.6.0) with GUI, touchpad and Wi-Fi (itlwm);
macOS not installed yet.** `EFI/` is the config that got there. Compared with the plan below it still has three
install-time cuts, to be undone one at a time after the install:

- **USB map is external ports only** (USB-A + both USB-C). Bluetooth (XHC0 port 5), the fingerprint reader (port 3) and
  XHC1/XHC4 are left out: with all internal ports visible, recovery stalled on
  `busy timeout[1], (240s): 'IOUSBHostDevice'`. The full map is kept in `Tools/usbmap/UTBMap-full-Info.plist`.
  Add port 5 back first (Bluetooth) and see whether the stall returns.
- **ECEnabler off** — turned off while bisecting the first stall, never shown to be guilty.
- **iGPU `device-id` spoof removed** — same reason. nullarc 0.4.0 matches `1002:15BF` itself.

**Native Wi-Fi + Bluetooth (2026-11-21; Wi-Fi verified after reboot, Bluetooth kexts updated afterwards):** this folder now has the ESP's state (PhxBringup on,
`LauncherOption Full`, 3200×2000) plus:

- **Bluetooth:** `UTBMap.kext` gets XHC0 port 5 (`HS04`, internal) back. Before this, the AX210's BT device never
  appeared on USB, so `IntelBluetoothFirmware` never loaded and macOS showed a fake `BCM_4350C2` controller,
  turned off. If the `IOUSBHostDevice` boot stall comes back, take `HS04` out again.
- **Wi-Fi:** [kgp-macPro/AirportItlwm-Tahoe](https://github.com/kgp-macPro/AirportItlwm-Tahoe) **2.0.0** (AX210
  validated, AppleVTD/`DisableIoMapper=false` OK) replaces itlwm, which stays in `Kernel/Add` disabled. It runs on
  the Ventura legacy stack: `IOSkywalkFamily.kext` (Ventura, OCLP payload v1.2.0) + `IO80211FamilyLegacy.kext`
  (payload v1.0.0, Brcm plugin removed) in `Kernel/Add` ahead of it, and `Kernel/Block com.apple.iokit.IOSkywalkFamily`
  (Exclude), like OCLP's own EFI builder does. The user-space half has to come from
  [OCLP-CustoMac](https://github.com/kgp-macPro/OCLP-CustoMac/releases) 3.0.3: Root Patch → **Modern Wi-Fi only**
  (Modern Audio stays off, since nullarc's AppleHDA route is separate). It changes the system snapshot, and it has
  to be redone after every macOS update.
- All of this is done by `Tools/apply-airportitlwm-tahoe.py`. `--revert` turns itlwm back on and the Wi-Fi
  families/Block off; the root patch is reverted from OCLP-CustoMac.

**USB is slow everywhere (found 2026-11-21):** in every boot in the log, every USB device's first GET_DESCRIPTOR fails
(`0xe00002cd`, not responding) and it takes 18–24 s to enumerate, on XHC0 and XHC3 alike. After that, each transfer
takes seconds (a USB stick needs over a minute to show up). This is the likely cause of the old `IOUSBHostDevice` 240 s
stall, the webcam hang behind `SSDT-USB-Reset`, and the Bluetooth failure: IntelBluetoothFirmware never gets the
answer to its first HCI command (`interruptPipeRead Timeout` / `Reading Intel version command failed`). Bluetooth works
in Windows. The likely fix is [XHCILagFix](https://github.com/hbyonly1/XHCILagFix) 0.1.0 (Lilu plugin, right after
Lilu; off with `-xhcilagfixoff`): AppleUSBXHCI routes transfer events to interrupters 1/2, whose notifications don't
reach the CPU on these AMD controllers, and the kext points them back to interrupter 0. A Hawk Point user on 26.7.2
reports it fixed USB input, storage and a 240 s Bluetooth stall. Isochronous devices (USB audio, webcam) reportedly still
don't work with it. **Verified 2026-11-21 10:43:** `ioreg -r -c XHCILagFix` shows `Active = Yes`; the BT device enumerates in 0.2 s (was 8–10 s) and a USB stick in 0.5 s (was 18 s) and mounts; Bluetooth loads its firmware and comes up. `Tools/bt-reprobe` re-runs the BT firmware load without rebooting.

**Wi-Fi with itlwm (fallback):** networks are joined with HeliPort 1.5.0 (keychain, auto-join at login). `itlwm.kext` here has
an empty `WiFiConfig`. To get Wi-Fi before login (e.g. on an installer USB), add a `WiFi_1` dict with `ssid` and
`password` to the copy on the USB only, never in this folder. `Tools/wifi-remove-hardcoded.sh` (run with sudo)
removes such entries from the internal ESP again.

## Detected hardware

| Component | Device | macOS |
|---|---|---|
| CPU | Ryzen 7 7840HS, 8C/16T (Family 19h Model 74h) | ✅ AMD Vanilla patches, core count = 8 |
| iGPU | Radeon 780M `1002:15BF` rev C7, 512 MB UMA | ⚠️ Metal via nullarc v0.4.0-alpha (Tahoe 26.6) plus the `redmibook-15bf` bring-up — see below |
| Display | 15.6" 3200×2000 120 Hz | ⚠️ First boot at 2560×1600; brightness through nullarc's `PhxAMDFB` (PWM, not yet tried on this panel) |
| Wi-Fi | Intel AX210 `8086:2725` at `GPP6.WLAN` (swapped from MediaTek MT7922 on 2026-11-18) | ✅ AirportItlwm-Tahoe 2.0.0 + OCLP-CustoMac 3.0.3 Modern Wi-Fi root patch on 26.7.3 (2026-11-21): native `Wi-Fi` port `en0`, IO80211FamilyLegacy stack. itlwm + HeliPort kept as disabled fallback. put the card's MAC address in `ROM` (step 3) |
| Bluetooth | Intel AX210 `8087:0032` (USB, XHC0 port 5) | ✅ Working 2026-11-21: State On, USB transport, firmware v12490. Needs XHCILagFix (see above) + IntelBluetoothFirmware/IntelBTPatcher 2.5.3 + BlueToolFixup 2.7.6 (kgp Tahoe hotfix) |
| NVMe | KIOXIA BG5 KBG50ZNV512G `1E0F:000C` | ✅ NVMeFix enabled |
| Audio | Senary SN6140 `14F1:1F86` | ❓ Depends on AppleALC support (see below) |
| Touchpad | ELAN2310 I2C (`I2CA.TPD0`, AMDI0010, GpioInt pin 8 on `\_SB.GPIO`) | ⚠️ VoodooI2C + VoodooI2CHID in **polling mode**: `SSDT-XOSI` + `_OSI→XOSI` (enables GPIO/I2CA/TPD0), `SSDT-TPD0` + `TPD0 _CRS→XCRS` (I2C-only `_CRS` under macOS), VoodooGPIO **off** — VoodooGPIOAMD 1.1 hangs at boot here, and without it a `GpioInt` in `_CRS` panics VoodooI2C in `getGPIOController` |
| Keyboard | PS/2 `FUJ7401` (`KBC0`) | ✅ VoodooPS2Keyboard |
| Webcam | Xiaomi `2B7E:C687` on `GP17.XHC1` port 1 | ❌ Disabled by `SSDT-USB-Reset` (avoids 60 s boot hang) |
| Card reader | Realtek RTS525A | ❌ RealtekCardReader stops at Sonoma |
| Fingerprint | FPC `10A5:9201` | ❌ Never works |
| USB-C ×2 | USB 3.2 Gen 2, `GP19.XHC3`/`XHC4` (`1022:15C0`/`15C1`) | ✅ USB once mapped; ❌ no video out yet (nullarc) |
| USB4 / TB | — | Not on this model: `NHI0`/`NHI1` exist in the DSDT only, no device on the PCI bus |
| Battery | `EC0` + `BATT` | ✅ SMCBatteryManager (ECEnabler currently off, see Status) |

## What changed vs. the Firebat EFI

- `SSDT-EC.aml`: re-targeted from `\_SB.PCI0.SBRG` to `\_SB.PCI0.LPC0` (this DSDT has no `SBRG`). AML checksum fixed.
- `SSDT-CPUR`, `SSDT-USB-Reset`, `SSDT-ALS0`, `SSDT-USBX`, `SSDT-RMNE`: kept as-is — the paths (`PLTF.C000..C00F`, `GP17.XHC1`) match.
- Audio `DeviceProperties` path `PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x6)` matches this laptop's HDA controller.
- `SSDT-XOSI.aml` rewritten and enabled with the `_OSI to XOSI` rename: this DSDT hides `\_SB.GPIO` and `\_SB.I2CA`
  unless `_OSI("Windows 2015")` is true (`TSOS >= 0x70`), and the touchpad `TPD0` unless `TPOS >= 0x60`. The new XOSI
  answers the Windows 2001–2015 strings only under macOS and passes `_OSI` through for Windows booted via OpenCore.
- Kexts on: SMCBatteryManager, ECEnabler, BrightnessKeys, NVMeFix, BlueToolFixup, IntelBluetoothFirmware, IntelBTPatcher, itlwm.
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
- Bluetooth comes along on the same card (USB line to XHC0 port 5). The BT kexts are already enabled:
  `IntelBluetoothFirmware` + `IntelBTPatcher` **2.5.2** from the Tahoe-maintained fork
  [lshbluesky/IntelBluetoothFirmware](https://github.com/lshbluesky/IntelBluetoothFirmware/releases/tag/v2.5.2)
  (it matches AX210 BT `8087:0032`), plus `BlueToolFixup` 2.7.3, which includes the macOS 26 `bluetoothd` patches.
  Don't add `IntelBluetoothInjector.kext`: it is for Big Sur and older only.
- **Windows** needs Intel's AX210 Wi-Fi and Bluetooth drivers. Download them *before* the swap (the laptop has no
  Ethernet port), or use phone USB tethering.
- After the swap, put the **AX210's** MAC address into SMBIOS `ROM` (step 3). Run `getmac /v` in Windows to get it.

### 2. Wi-Fi and battery kexts — done (2026-11-18)

Both are in `EFI/OC/Kexts/` and enabled in `config.plist`:

- **itlwm.kext 2.3.0** ([OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm/releases/tag/v2.3.0),
  `itlwm_v2.3.0_stable.kext.zip`). It shows up as an Ethernet interface; join networks with the
  **HeliPort 1.5.0** app, saved as `Tools/HeliPort-1.5.0.dmg` (git-ignored). Copy it to the Mac, install it into
  Applications, add it to Login Items. If 1.5.0 misbehaves on Tahoe, try the
  [2.0.0-alpha](https://github.com/OpenIntelWireless/HeliPort/releases/tag/v2.0.0-alpha).
  The bundled `AirportItlwm.kext` (Sonoma 2.3.0 build) stays **disabled** — never enable both. It does not load on
  Tahoe anyway: upstream OpenIntelWireless has no Tahoe build. Tahoe options, as of 2026-11-21, none tried here yet:
  - [laobamac/itlwm](https://github.com/laobamac/itlwm) `AirportItlwm-Tahoe` v2.4.0-alpha: native Wi-Fi menu, WPA2
    and WPA2/WPA3 transition only, no AirDrop/AWDL. Its docs don't say whether an OCLP root patch is needed, and no
    26.7.x test is listed. Limit it to Darwin 25 (`MinKernel 25.0.0`, `MaxKernel 25.99.99`) and disable itlwm.
  - [kgp-macPro/AirportItlwm-Tahoe](https://github.com/kgp-macPro/AirportItlwm-Tahoe) 2.0.0: needs OCLP-CustoMac
    3.0.0+ root patches (IO80211FamilyLegacy, IOSkywalkFamily block), so it modifies the system volume.
- **ECEnabler.kext 1.0.6** ([averycblack/ECEnabler](https://github.com/averycblack/ECEnabler/releases/tag/1.0.6), formerly
  1Revenger1/ECEnabler) — lets SMCBatteryManager read the EC's 16-bit battery fields without DSDT patches.

### 3. Generate your own SMBIOS — done (2026-11-18)

Serial, MLB and SystemUUID were generated for `MacBookPro16,1` with `macserial` from OpenCore 1.0.8 and are in
`PlatformInfo > Generic`; `ROM` holds the AX210's MAC. **Still to check by hand:** the serial must show "invalid" at
checkcoverage.apple.com — if it is valid (someone else's Mac), generate a new one. These values belong to this machine:
don't publish this `config.plist` or copy it to another computer.

### 4. BIOS settings

Secure Boot **off**; UMA frame buffer as high as the BIOS allows (often hidden on Xiaomi BIOS); fast boot off. TPM can stay.

### 5. First boot, then fix-ups

- **USB map — done in Windows (2026-11-18)** with USBToolBox 0.2; `USBToolBox.kext` 1.2.0 + this laptop's `UTBMap.kext`
  are enabled (the Firebat map is gone). Raw discovery data: `Tools/usb.json`. The map:

  | Controller | Port | Connector | What |
  |---|---|---|---|
  | `GP17.XHC0` | HS01 (1) + SS01 (6) | Type-C | USB-C port |
  | `GP17.XHC0` | HS02 (2) + SS02 (7) | USB 3 Type-A | USB-A port — added by hand after the first scan; the second scan saw the SanDisk on SS port 7, and ACPI marks it Type-A |
  | `GP17.XHC0` | HS03 (3) | internal | FPC fingerprint (no macOS driver) |
  | `GP17.XHC0` | HS04 (5) | internal | AX210 Bluetooth |
  | `GP17.XHC1` | HS01 (1) | internal | Webcam — the whole controller is disabled by `SSDT-USB-Reset`, no physical port lives here |
  | `GP19.XHC3` | HS01 (1) + SS01 (2) | Type-C | USB-C port |

  The fingerprint reader is port 3, not 2/7. Flipping a USB-C plug does not change the port number on either C port
  (checked in the second scan). `GP19.XHC4` (2 ports, no connector type in ACPI) saw no device and is not mapped. If a port doesn't work in macOS —
  most likely the USB-A or one orientation of a USB-C plug — re-run `Tools/USBToolBox.exe`, plug into that port, rebuild.
- **Audio**: macOS Tahoe no longer ships `AppleHDA.kext`, so AppleALC alone gives no sound. nullarc 0.4.0 has a route
  that works on the Firebat: `AppleHDA.kext` in `/Library/Extensions` (Auxiliary kernel collection), an AppleALC whose
  AppleHDA paths point there (`tools/phxctl/alc_le_paths.py`), and `PhxHDA.kext` (`src/phxhda`, a Lilu plugin injected
  after AppleALC). The installer does not set this up; it is done by hand. Two things differ here: AppleALC must support
  the Senary SN6140 (`14F1:1F86`) — check the
  [AppleALC Supported Codecs](https://github.com/acidanthera/AppleALC/wiki/Supported-codecs) page — and the Firebat's
  `alcid=18` is for its own codec, so the layout has to be found for this one (`tools/phxctl/hdadump` shows the pins).
  Until then, use a USB audio adapter or Bluetooth headphones.
- **USB-C plug-in stall**: on the Firebat, plugging a USB-C device froze macOS for 20–30 s because `\_SB.ALIB(0x0C)`
  fails; nullarc ships `hardware/acpi/SSDT-ALIB` for it. Add it only if this laptop shows the same stall and its DSDT
  has the same method.
- **AC adapter**: the Firebat needed nullarc's `hardware/acpi/SSDT-ADP1` because its `_PSR` fails under macOS. This
  laptop's adapter is `\_SB.ACAD` with `EC0` under `LPC0`. If macOS shows "not charging" while plugged in, the same
  fix is needed, but with those paths.
- Once things work, trim boot-args (drop `-v`, `debug=0x100`, `keepsyms=1`).

## Graphics acceleration with nullarc

[nullarc](https://github.com/luuumi-dev/nullarc) gives the 780M Metal 3 and a GPU-composited desktop on **macOS Tahoe 26.6**. It's alpha
(v0.4.0-alpha, 2026-11-09), and it has only been tested on the Firebat U6C: upstream's own `docs/760M_STATUS.md` says the
760M/740M support in its README is diagnostic-only. Without it you get a framebuffer only (slow UI, no Metal apps).

Since 0.4.0 the release kexts match this laptop's `1002:15BF`, and brightness, Night Shift and a GPU hang watchdog are
in. What the release still gets wrong for this laptop is the user-space bring-up, which is why the `redmibook-15bf`
branch (rebased onto v0.4.0) is still needed — see the warning.

### Already done in this EFI

| Setting | Why |
|---|---|
| ~~`DeviceProperties` → `PciRoot(0x0)/Pci(0x8,0x1)/Pci(0x0,0x0)` → `device-id` = `00190000`~~ **removed 2026-11-19** | Left over from 0.3.0, whose kexts only matched `1002:1900` (Hawk Point, the Firebat). The 0.4.0 kexts match `1002:15BF` themselves, so it is optional now. It does no harm (same gfx1103 silicon and firmware); remove it once acceleration works. |
| `Kernel → Add` → `PhxBringup.kext`, `MinKernel 25.0.0`, after VirtualSMC, **disabled** | Turn it on once the kext is in `EFI/OC/Kexts`. |
| boot-args: `amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta phxdebug=1`, `csr-active-config 7F080000`, `SecureBootModel Disabled` | nullarc's requirements (`AMFIPass.kext` is already enabled). |
| `UEFI → Output → Resolution` = `2560x1600@32` | See the warning below. |

> [!WARNING]
> **Do not let the release's own bring-up run on this laptop** (0.3.0 or 0.4.0), at any resolution. Two things in it
> are the Firebat's:
>
> - **The VRAM carve-out.** `mesboot` and `bringup5.sh` use the Firebat's physical address (`0x6A0000000`, 6 GiB) for
>   the GART page table, the TMR and the fault page. This laptop's 512 MB carve-out is somewhere else, so those
>   addresses would point at memory that is not the GPU's.
> - **The boot framebuffer size.** The PSP ring is put at 17 MiB (`psp create 0x1100000`). The firmware's boot
>   framebuffer sits at the start of VRAM: at the Firebat's 2560×1600 it ends at 16.4 MB, at this panel's native
>   3200×2000 at ~24.4 MiB, over the ring.
>
> The branch `redmibook-15bf` fixes both. Until it has booted once, OpenCore still asks GOP for 2560×1600 (macOS then
> runs at 2560×1600 scaled onto the panel, a little soft). In the OpenCore log, check that the mode was actually set;
> if GOP doesn't offer it, use `1920x1200@32`.

### nullarc branch `redmibook-15bf` (on top of v0.4.0)

It lives in the fork [Yiozolm/nullarc](https://github.com/Yiozolm/nullarc/tree/redmibook-15bf)
(`git clone -b redmibook-15bf https://github.com/Yiozolm/nullarc.git`): one commit on top of upstream
[luuumi-dev/nullarc](https://github.com/luuumi-dev/nullarc) `main`. It makes the bring-up read this machine's layout instead of assuming the
Firebat's:

- `PhxBringup` (build 35) publishes `phx-bootfb-bytes` (the GOP console's size) and refuses a PSP ring inside it.
  `bringup5.sh` places the ring 1 MiB above the console: 17 MiB at 2560×1600 as before, 26 MiB at 3200×2000.
- `bringup5.sh` and `mesboot` read the carve-out's MC base, physical address and size from `PhxBringup`
  (`phx-fb-mc-base`, `phx-fb-phys`, `phx-fb-size`) instead of the Firebat's 6 GiB at `0x6A0000000`. That covers the TOC/TMR
  addresses, the GART page table, the system aperture (sized to this machine's 512 MiB) and the fault page.
- If the layout doesn't fit, phxboot leaves the GPU untouched and stays on the firmware framebuffer.

The release's `PhxAccel.kext`, Metal plugin and RADV are used as they are; only `PhxBringup.kext`, `mesboot` and three
scripts come from the branch. None of this has been built or booted yet.

### Steps (after macOS Tahoe 26.6 installs and boots without nullarc)

On the Mac, with the Command Line Tools, [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK), a checkout of the
branch, and `nullarc-v0.4.0-alpha.zip` from the [releases page](https://github.com/luuumi-dev/nullarc/releases):

1. `sh src/phxbringup/build.sh /path/to/MacKernelSDK` → copy the built `PhxBringup.kext` into `EFI/OC/Kexts`, set its
   `Enabled` to `true`, reboot.
2. Check the kext sees this machine: `ioreg -l | grep -E 'phx-build|phx-bootfb-bytes|phx-fb-size'` must print all
   three; `phx-build` is 35 and `phx-fb-size` is 536870912 (512 MiB).
3. Turn on automatic login. From the release folder: `sudo ./install.sh --check`, then
   `sudo ./install.sh --windowserver`. **Do not reboot yet** — the installer has just put the Firebat bring-up in place.
4. Replace it from the branch checkout:
   `clang -O2 -o mesboot tools/phxctl/mesboot.c -framework IOKit -framework CoreFoundation`, then
   `sudo install -m 755 mesboot /Users/Shared/gpu/phxctl/` and
   `sudo install -m 755 tools/phxctl/{bringup5,full,phxboot}.sh /Users/Shared/gpu/`.
   Repeat this step after every run of `install.sh`.
5. Reboot twice. `/var/log/phxboot.log` must end with `done`, `/tmp/bringup5.log` shows the layout line
   (`VRAM: MC … phys …, PSP ring at +0x1100000`), and System Information → Graphics shows Metal 3.
6. Native resolution: set `UEFI → Output → Resolution` to `3200x2000@32` and reboot. `/tmp/bringup5.log` should now
   show `PSP ring at +0x1A00000`.
7. Optional: remove the `device-id` entry from `DeviceProperties`.

**About `mesa-patches-phoenix`:** no rebuild is needed for this laptop. RADV's GPU description comes from Mesa's
`phoenix` entry, which is the **`1002:15BF`** chip this laptop has; it is reported to Vulkan as `1900` (the Firebat's
ID). Since 0.4.0 (patch 0007) the CU/RB topology comes from `PhxBringup`, which gives a `15BF` chip the full 780M
profile (12 CUs). The one hardware check is in
patch 0001: RADV compares the live `GB_ADDR_CONFIG` register with the canned phoenix value and refuses the device on a
mismatch. A full 12-CU 7840HS should match. If `vkprobe` or a Metal app logs
`radv-darwin: live GB_ADDR_CONFIG 0x… != canned phoenix 0x…`, send that line before trying
`RADV_DARWIN_ALLOW_ADDRCFG=1`, because a real mismatch means the tiling setup differs.

Keep a USB installer and a copy of this EFI. phxboot falls back to the firmware framebuffer by itself after failed
boots. To turn the GPU off by hand: `sudo touch /Users/Shared/gpu/phxboot-off`. To remove nullarc: `sudo ./uninstall.sh`, then
disable PhxBringup.

**Still missing in nullarc 0.4.0:** external displays (HDMI/USB-C, in progress upstream), video decode/encode, lid
sleep (only display sleep/wake works; S4 hibernation is planned). Some Metal compute loads still fail (Geekbench 6's
MPSGraph tests). `amfi=0x80` also breaks FairPlay playback (Apple TV+, Netflix in Safari).

**Brightness:** `PhxAMDFB` drives both backlight PWM generators of the display block, which gives the Control Center
slider and the Fn keys on the Firebat. That works here only if this panel follows its PWM pin; upstream's
`tools/phxctl/phxaux` reads the panel's DPCD to tell.

**UMA VRAM:** the BIOS gives the 780M 512 MB (the Firebat has 6 GB). The bring-up uses only the first ~200 MB of the
carve-out, and nullarc's VRAM pool comes from macOS system RAM, so 512 MB is enough; upstream now recommends shrinking
the Firebat's to 1 GB because the rest is wasted RAM.
