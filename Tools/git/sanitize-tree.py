#!/usr/bin/env python3
"""Remove machine-specific data from a checkout of this repository (used to rewrite history before
making it public, and safe to re-run):

  - EFI/OC/config.plist: blank SMBIOS (serial, MLB, SystemUUID, ROM)
  - README.md: the AX210 MAC / Bluetooth address
  - Tools/make-usb.ps1: the author's Windows temp path for the recovery download

    python3 -I Tools/git/sanitize-tree.py <repo-root>
"""
import plistlib
import re
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
MAC = r"5[Cc]:67:83:9[Bb]:0[Ee]:[0-9A-Fa-f]{2}"

cfg = root / "EFI/OC/config.plist"
if cfg.is_file():
    p = plistlib.loads(cfg.read_bytes())
    g = p.get("PlatformInfo", {}).get("Generic")
    if g is not None and any(g.get(k) for k in ("SystemSerialNumber", "MLB", "SystemUUID", "ROM")):
        g.update({"SystemSerialNumber": "", "MLB": "", "SystemUUID": "", "ROM": b""})
        cfg.write_bytes(plistlib.dumps(p))

readme = root / "README.md"
if readme.is_file():
    s = readme.read_text(encoding="utf-8")
    s = re.sub(rf"MAC `{MAC}` is in `ROM`", "put the card's MAC address in `ROM` (step 3)", s)
    s = re.sub(rf", address `{MAC}`", "", s)
    s = re.sub(MAC, "XX:XX:XX:XX:XX:XX", s)
    readme.write_text(s, encoding="utf-8")

ps1 = root / "Tools/make-usb.ps1"
if ps1.is_file():
    raw = ps1.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    s = raw.decode("utf-8-sig")
    s = re.sub(r"(?m)^\$Recovery\s*=\s*'C:\\Users\\[^']*'",
               lambda m: "$Recovery = Join-Path $env:TEMP 'recovery'   # folder with BaseSystem.dmg + BaseSystem.chunklist",
               s)
    ps1.write_bytes((b"\xef\xbb\xbf" if bom else b"") + s.encode("utf-8"))
