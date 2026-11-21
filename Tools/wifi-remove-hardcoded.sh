#!/bin/bash
# Remove the hardcoded Wi-Fi network(s) from itlwm.kext on the boot ESP, so HeliPort
# (which keeps networks in the keychain) is the only place credentials live.
#
# Run ONLY after HeliPort has joined your network and "Launch at Login" is on,
# otherwise the Mac has no Wi-Fi after the next reboot.
#
#   sudo bash Tools/wifi-remove-hardcoded.sh             # itlwm WiFiConfig only
#   sudo bash Tools/wifi-remove-hardcoded.sh --rtl89     # also move the unused Rtl89Driver.kext out
#
# Backups go to ~/Documents/EFI-backup-<date>/wifi/ (mode 600, they still hold the password:
# delete them once the new setup has survived a reboot).
set -euo pipefail

ESP_DEV="${ESP_DEV:-disk0s1}"
REMOVE_RTL89=0
[[ "${1:-}" == "--rtl89" ]] && REMOVE_RTL89=1

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
REAL_USER="${SUDO_USER:-$(stat -f %Su /dev/console)}"
REAL_HOME=$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory | awk '{print $2}')
PB=/usr/libexec/PlistBuddy

pgrep -xq HeliPort || { echo "HeliPort is not running. Start it, join your network, enable Launch at Login, then re-run." >&2; exit 1; }

MNT=$(diskutil info "$ESP_DEV" | awk -F': *' '/Mount Point/{print $2}')
if [[ -z "$MNT" ]]; then
  diskutil mount "$ESP_DEV" >/dev/null
  MNT=$(diskutil info "$ESP_DEV" | awk -F': *' '/Mount Point/{print $2}')
  MOUNTED_HERE=1
fi
OC="$MNT/EFI/OC"
PLIST="$OC/Kexts/itlwm.kext/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "not found: $PLIST" >&2; exit 1; }

BK="$REAL_HOME/Documents/EFI-backup-$(date +%Y-%m-%d)/wifi"
mkdir -p "$BK"
cp -p "$PLIST" "$BK/itlwm-Info.plist.$(date +%H%M%S)"

# Delete every WiFi_N entry, keep an empty WiFiConfig dict.
KEY=":IOKitPersonalities:itlwm:WiFiConfig"
n=0
for entry in $("$PB" -c "Print $KEY" "$PLIST" 2>/dev/null | awk '/= Dict \{/ && $1 ~ /^WiFi_/ {print $1}'); do
  "$PB" -c "Delete $KEY:$entry" "$PLIST"
  n=$((n+1))
done
plutil -lint "$PLIST" >/dev/null
echo "itlwm: removed $n hardcoded network(s)"

if [[ $REMOVE_RTL89 -eq 1 && -d "$OC/Kexts/Rtl89Driver.kext" ]]; then
  if grep -q Rtl89Driver "$OC/config.plist"; then
    echo "Rtl89Driver is referenced in config.plist, leaving it in place" >&2
  else
    mv "$OC/Kexts/Rtl89Driver.kext" "$BK/"
    echo "Rtl89Driver.kext moved to $BK (it is not in config.plist)"
  fi
fi

chown -R "$REAL_USER" "$(dirname "$BK")"
chmod -R go-rwx "$BK"
sync
[[ "${MOUNTED_HERE:-0}" == 1 ]] && diskutil unmount "$ESP_DEV" >/dev/null
echo "done. Backup: $BK  (holds the old password; delete it after a good reboot)"
