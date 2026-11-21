#!/bin/bash
# Re-run IntelBluetoothFirmware on the AX210 BT (8087:0032) without rebooting and capture its log.
#   sudo bash Tools/bt-reprobe/run.sh        -> writes ./bt-reprobe.log
# Needs the DEBUG IntelBluetoothFirmware for detailed lines ("IntelFirmware: ..."); kern.msgbuf is
# raised to 1 MB first because the 128 KB default is overwritten within a minute of boot.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
OUT="${PWD}/bt-reprobe.log"
[[ -x "$D/reenum" ]] || clang -O2 -o "$D/reenum" "$D/reenum.c" -framework IOKit -framework CoreFoundation
sysctl -w kern.msgbuf=1048576
"$D/reenum"
echo "waiting 25 s for enumeration + firmware load..."
sleep 25
dmesg | grep -a -E 'IntelFirmware|HS04@|8087/0032' > "$OUT" || true
chown "${SUDO_USER:-root}" "$OUT"
tail -25 "$OUT"
