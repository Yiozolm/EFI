#!/bin/bash
# One-time setup for a clone that holds a *real* config.plist (your own SMBIOS).
#
#   bash Tools/git/setup.sh
#
# - Saves your current SMBIOS (serial, MLB, SystemUUID, ROM) to .git/info/smbios.plist (never committed).
# - Registers the "smbios" filter: commits always get blank SMBIOS, checkouts get yours back.
# - Installs a pre-commit check that refuses any staged file containing those values.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
GD="$(git rev-parse --git-dir)"
CFG=EFI/OC/config.plist
mkdir -p "$GD/info" "$GD/hooks"

if [[ ! -f "$GD/info/smbios.plist" ]]; then
  python3 -I - "$CFG" "$GD/info/smbios.plist" <<'EOF'
import plistlib, sys
g = plistlib.load(open(sys.argv[1], "rb"))["PlatformInfo"]["Generic"]
keep = {k: g[k] for k in ("SystemSerialNumber", "MLB", "SystemUUID", "ROM") if g.get(k)}
if not keep:
    sys.exit("config.plist has no SMBIOS to save; fill it in first, then re-run")
plistlib.dump(keep, open(sys.argv[2], "wb"))
print("saved", ", ".join(keep), "->", sys.argv[2])
EOF
  chmod 600 "$GD/info/smbios.plist"
fi

git config filter.smbios.clean  'python3 -I Tools/git/smbios-filter.py clean'
git config filter.smbios.smudge 'python3 -I Tools/git/smbios-filter.py smudge'
git config filter.smbios.required true
cp Tools/git/pre-commit "$GD/hooks/pre-commit"
chmod +x "$GD/hooks/pre-commit"
git add --renormalize "$CFG" >/dev/null 2>&1 || true
echo "smbios filter and pre-commit check installed"
