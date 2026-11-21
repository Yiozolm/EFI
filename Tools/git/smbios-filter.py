#!/usr/bin/env python3
"""git filter for EFI/OC/config.plist: the repository never holds this machine's SMBIOS.

  clean  (worktree -> repo): blank PlatformInfo/Generic SystemSerialNumber, MLB, SystemUUID, ROM.
  smudge (repo -> worktree): put the real values back from .git/info/smbios.plist, if that file exists.

The private values live only in .git/info/smbios.plist (never committed). Install with Tools/git/setup.sh.
"""
import plistlib
import subprocess
import sys
from pathlib import Path

FIELDS = {"SystemSerialNumber": "", "MLB": "", "SystemUUID": "", "ROM": b""}


def private_values():
    try:
        git_dir = subprocess.run(["git", "rev-parse", "--git-dir"], capture_output=True, text=True,
                                 check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    f = Path(git_dir) / "info" / "smbios.plist"
    return plistlib.loads(f.read_bytes()) if f.is_file() else None


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "clean"
    raw = sys.stdin.buffer.read()
    try:
        cfg = plistlib.loads(raw)
    except Exception:
        sys.stdout.buffer.write(raw)  # not a plist: pass through untouched
        return
    generic = cfg.setdefault("PlatformInfo", {}).setdefault("Generic", {})
    if mode == "clean":
        generic.update(FIELDS)
    elif mode == "smudge":
        values = private_values()
        if values:
            generic.update({k: values[k] for k in FIELDS if k in values})
    else:
        sys.exit(f"unknown mode {mode}")
    sys.stdout.buffer.write(plistlib.dumps(cfg))


if __name__ == "__main__":
    main()
