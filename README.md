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
| USB-C ×2 | USB 3.2 Gen 2, `GP19.XHC3`/`XHC4` (`1022:15C0`/`15C1`) | ✅ USB once mapped; ❌ no video out yet (nullarc) |
| USB4 / TB | — | Not on this model: `NHI0`/`NHI1` exist in the DSDT only, no device on the PCI bus |
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
- Bluetooth comes along on the same card (USB line to XHC0 port 5). The BT kexts are already enabled:
  `IntelBluetoothFirmware` + `IntelBTPatcher` **2.5.2** from the Tahoe-maintained fork
  [lshbluesky/IntelBluetoothFirmware](https://github.com/lshbluesky/IntelBluetoothFirmware/releases/tag/v2.5.2)
  (it matches AX210 BT `8087:0032`), plus `BlueToolFixup` 2.7.3, which includes the macOS 26 `bluetoothd` patches.
  Don't add `IntelBluetoothInjector.kext`: it is for Big Sur and older only.
- **Windows** needs Intel's AX210 Wi-Fi and Bluetooth drivers. Download them *before* the swap (the laptop has no
  Ethernet port), or use phone USB tethering.
- After the swap, put the **AX210's** MAC address into SMBIOS `ROM` (step 3). Run `getmac /v` in Windows to get it.

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
  `USBToolBox.kext` + `UTBMap.kext`. The bundled `UTBMap.kext` is the Firebat's map — replace it, don't keep both. Plug a
  device into both USB-C ports at USB 3 and USB 2 speeds so the XHC3/XHC4 ports get mapped. `SSDT-USB-Reset` disables all of `XHC1`'s root hub — if a physical USB port stops
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
> **Never boot the 0.3.0 release at 3200×2000.** The nullarc branch `redmibook-15bf` fixes this (see below).

### Native mode: nullarc branch `redmibook-15bf`

That branch makes nullarc fit this laptop instead of making the laptop look like the Firebat:

- `PhxBringup`, `PhxAccel` (`PhxAMDFB` + `NMXAccel`) and `PhxProbe` match `1002:15BF` as well as `1002:1900`, so the
  `device-id` spoof is no longer needed (it does no harm either; keep it while you still run release kexts).
- `PhxBringup` publishes `phx-bootfb-bytes` (the GOP console's size) and refuses a PSP ring inside it.
  `bringup5.sh` places the ring 1 MiB above the console: 17 MiB at 2560×1600 as before, 26 MiB at 3200×2000.
- `bringup5.sh` and `mesboot` read the carve-out's MC base, physical address and size from `PhxBringup`
  (`phx-fb-mc-base`, `phx-fb-phys`, `phx-fb-size`) instead of the Firebat's 6 GiB at `0x6A0000000`. That covers the TOC/TMR
  addresses, the GART page table, the system aperture (sized to this machine's 512 MiB) and the fault page.
- If the layout doesn't fit, phxboot leaves the GPU untouched and stays on the firmware framebuffer.

To use it, install the 0.3.0 release first as described below (spoof on, 2560×1600). Then, on the Mac, from a checkout of
the branch:

1. `sh src/phxbringup/build.sh /path/to/MacKernelSDK` → copy `PhxBringup.kext` over the one in `EFI/OC/Kexts`.
2. `sh src/phxaccel/build.sh /path/to/MacKernelSDK` → replace `/Library/Extensions/PhxAccel.kext` with it (owner
   `root:wheel`), then `sudo bash /Users/Shared/gpu/kinst.sh` to rebuild the Auxiliary kernel collection.
3. `clang -O2 -o mesboot tools/phxctl/mesboot.c -framework IOKit -framework CoreFoundation`, then
   `sudo install -m 755 mesboot /Users/Shared/gpu/phxctl/` and
   `sudo install -m 755 tools/phxctl/{bringup5,full,phxboot}.sh /Users/Shared/gpu/`.
4. Reboot. `ioreg -l | grep phx-bootfb-bytes` must print a line, and `/var/log/phxboot.log` must still end with `done`.
5. Set `UEFI → Output → Resolution` to `3200x2000@32` and reboot. `/tmp/bringup5.log` should show `PSP ring at +0x1A00000`.
6. Optional: remove the `device-id` entry from `DeviceProperties`.


### Steps (after macOS Tahoe 26.6 installs and boots without nullarc)

1. Get `nullarc-<version>.zip` from the [releases page](https://github.com/luuumi-dev/nullarc/releases) (or build
   `PhxBringup.kext` with `src/phxbringup/build.sh` on the Mac).
2. Copy `EFI/OC/Kexts/PhxBringup.kext` into this EFI, set its `Enabled` to `true`, reboot.
   `ioreg -l | grep phx-build` must print a line.
3. `ioreg -l | grep '"device-id"'` on the GPU should read `<00190000>`. If not, the spoof path is wrong.
4. Turn on automatic login, then `sudo ./install.sh --check`, then `sudo ./install.sh --windowserver`, and reboot twice.
5. Check `/var/log/phxboot.log` ends with `done`, and System Information → Graphics shows Metal 3.

**About `mesa-patches-phoenix`:** no rebuild is needed for this laptop. RADV's GPU description comes from Mesa's
`phoenix` entry, which is the **`1002:15BF`** chip this laptop has; patch 0002 only *reports* it as `1900` rev BA (the
Firebat's ID) to Vulkan. That's the same identity the OpenCore spoof gives, so the two agree. The one hardware check is in
patch 0001: RADV compares the live `GB_ADDR_CONFIG` register with the canned phoenix value and refuses the device on a
mismatch. A full 12-CU 7840HS should match. If `vkprobe` or a Metal app logs
`radv-darwin: live GB_ADDR_CONFIG 0x… != canned phoenix 0x…`, send that line before trying
`RADV_DARWIN_ALLOW_ADDRCFG=1`, because a real mismatch means the tiling setup differs.

Keep a USB installer and a copy of this EFI. phxboot falls back to the firmware framebuffer by itself after failed
boots. To turn the GPU off by hand: `sudo touch /Users/Shared/gpu/phxboot-off`. To remove nullarc: `sudo ./uninstall.sh`, then
disable PhxBringup.

**Still missing in nullarc:** external displays (HDMI/USB-C), video decode/encode, backlight control. `amfi=0x80` also
breaks FairPlay playback (Apple TV+, Netflix in Safari). Sleep is usually broken on AMD laptops; display sleep/wake works.

**UMA VRAM:** the BIOS gives the 780M 512 MB (the Firebat has 4 GB). nullarc's 512 MB VRAM pool comes from macOS
system RAM, and its fixed carve-out offsets end below ~200 MB, so 512 MB should be enough. If you can raise it (Xiaomi
hides the option), 1–2 GB is a safer margin.
