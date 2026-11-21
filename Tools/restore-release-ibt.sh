#!/bin/bash
# Replace the temporary DEBUG IntelBluetoothFirmware/IntelBTPatcher on the internal ESP with the
# RELEASE builds from this folder's EFI/OC/Kexts.   sudo bash Tools/restore-release-ibt.sh
set -euo pipefail
cd "$(dirname "$0")/../EFI/OC"
diskutil info disk0s1 | grep -q '/Volumes/SYSTEM' || diskutil mount disk0s1 >/dev/null
E=/Volumes/SYSTEM/EFI/OC
U="${SUDO_USER:-$(stat -f %Su /dev/console)}"
B="/Users/$U/Documents/EFI-backup-2026-11-21-esp/OC-ibt-debug-$(date +%H%M%S)"
mkdir -p "$B"
for k in IntelBluetoothFirmware IntelBTPatcher; do
  cp -Rp "$E/Kexts/$k.kext" "$B/"
  rm -rf "$E/Kexts/$k.kext"
  cp -R "Kexts/$k.kext" "$E/Kexts/"
done
find "$E" -name '._*' -delete; sync
chown -R "$U" "$B"
diff -rq . "$E" | grep -v -E '\.DS_Store|/\._|contentFlavour|contentVisibility|before-3200' || echo "ESP matches local"
echo "DEBUG copies saved in $B"
