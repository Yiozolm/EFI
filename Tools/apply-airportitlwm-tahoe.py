#!/usr/bin/env python3
"""Switch an OpenCore EFI/OC folder from itlwm to kgp-macPro AirportItlwm-Tahoe 2.0.0,
and add AX210 Bluetooth (XHC0 port 5) to the USBToolBox map.

    python3 -I Tools/apply-airportitlwm-tahoe.py <EFI/OC> <AirportItlwm.kext> <IOSkywalkFamily.kext> <IO80211FamilyLegacy.kext>

Kernel side, as OCLP-CustoMac's own EFI builder does it for Modern Wireless (Sonoma+):
  IOSkywalkFamily.kext (Ventura) + IO80211FamilyLegacy.kext in Kernel/Add, MinKernel 23.0.0,
  and Kernel/Block com.apple.iokit.IOSkywalkFamily (Exclude). AirPortBrcmNIC is Broadcom-only: left out.
User space (IO80211.framework, WiFiPeerToPeer, wifip2pd) comes from the OCLP-CustoMac
"Modern Wi-Fi" root patch, which this script does not touch.

itlwm stays in Kernel/Add, disabled. Rollback: run with --revert.
"""
import plistlib, shutil, sys
from pathlib import Path

REVERT = "--revert" in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith("--")]
oc = Path(args[0])
cfg_path = oc / "config.plist"
cfg = plistlib.loads(cfg_path.read_bytes())
kadd = cfg["Kernel"]["Add"]
kexts = oc / "Kexts"


def entry(bundle, comment, exe=True, mink="", maxk=""):
    name = bundle.split("/")[-1][:-5]
    return {
        "Arch": "x86_64", "BundlePath": bundle, "Comment": comment, "Enabled": True,
        "ExecutablePath": f"Contents/MacOS/{name}" if exe else "",
        "MaxKernel": maxk, "MinKernel": mink, "PlistPath": "Contents/Info.plist",
    }


def find(bundle):
    return next((i for i, k in enumerate(kadd) if k["BundlePath"] == bundle), None)


def copy_kext(src, name):
    dst = kexts / name
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)


SKY = "com.apple.iokit.IOSkywalkFamily"
block = cfg["Kernel"]["Block"]

if REVERT:
    for b in ("IOSkywalkFamily.kext", "IO80211FamilyLegacy.kext"):
        i = find(b)
        if i is not None:
            kadd[i]["Enabled"] = False
    kadd[find("AirportItlwm.kext")]["Enabled"] = False
    kadd[find("itlwm.kext")]["Enabled"] = True
    for b in block:
        if b.get("Identifier") == SKY:
            b["Enabled"] = False
else:
    airport_src, sky_src, legacy_src = map(Path, args[1:4])
    copy_kext(airport_src, "AirportItlwm.kext")
    copy_kext(sky_src, "IOSkywalkFamily.kext")
    copy_kext(legacy_src, "IO80211FamilyLegacy.kext")
    # The Brcm plugin is unused with Intel; drop it so nothing can match it by accident.
    brcm = kexts / "IO80211FamilyLegacy.kext/Contents/PlugIns/AirPortBrcmNIC.kext"
    if brcm.exists():
        shutil.rmtree(brcm)

    kadd[find("itlwm.kext")]["Enabled"] = False
    kadd[find("itlwm.kext")]["Comment"] = (
        "itlwm 2.3.0 + HeliPort - fallback, OFF while AirportItlwm-Tahoe is on (never both)")

    ai = find("AirportItlwm.kext")
    kadd[ai] = entry("AirportItlwm.kext",
                     "kgp-macPro AirportItlwm-Tahoe 2.0.0 - needs OCLP-CustoMac Modern Wi-Fi root patch",
                     mink="25.0.0", maxk="25.99.99")
    # Families must load before the driver, and IO80211FamilyLegacy links against IOSkywalkFamily:
    # final order is IOSkywalkFamily, IO80211FamilyLegacy, AirportItlwm (each inserted in front of the driver).
    for b, c in (("IOSkywalkFamily.kext", "IOSkywalkFamily Ventura (OCLP-CustoMac payload v1.2.0) - pairs with Block below"),
                 ("IO80211FamilyLegacy.kext", "IO80211FamilyLegacy (OCLP-CustoMac payload v1.0.0) for AirportItlwm-Tahoe")):
        i = find(b)
        if i is not None:
            kadd.pop(i)
        kadd.insert(find("AirportItlwm.kext"), entry(b, c, mink="23.0.0"))

    b = next((b for b in block if b.get("Identifier") == SKY), None)
    if b is None:
        b = {}
        block.append(b)
    b.update({"Arch": "Any", "Comment": "Allow IOSkywalk Downgrade (AirportItlwm-Tahoe)", "Enabled": True,
              "Identifier": SKY, "MaxKernel": "", "MinKernel": "23.0.0", "Strategy": "Exclude"})

    # Bluetooth: AX210 BT is on XHC0 port 5 (internal). Leave the fingerprint (port 3) out.
    utb = kexts / "UTBMap.kext/Contents/Info.plist"
    m = plistlib.loads(utb.read_bytes())
    ports = m["IOKitPersonalities"]["XHC0"]["IOProviderMergeProperties"]["ports"]
    ports["HS04"] = {"UsbConnector": 255, "port": bytes([5, 0, 0, 0])}
    utb.write_bytes(plistlib.dumps(m))

# Sanity: never both Wi-Fi drivers.
on = {k["BundlePath"] for k in kadd if k["Enabled"]}
assert not {"itlwm.kext", "AirportItlwm.kext"} <= on, "itlwm and AirportItlwm both enabled"
for k in kadd:
    if k["Enabled"]:
        p = kexts / k["BundlePath"]
        assert p.is_dir(), f"missing {p}"
        if k["ExecutablePath"]:
            assert (p / k["ExecutablePath"]).is_file(), f"missing {p / k['ExecutablePath']}"

cfg_path.write_bytes(plistlib.dumps(cfg))
print("reverted" if REVERT else "applied", "->", cfg_path)
