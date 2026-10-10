#!/bin/bash
# Safely stage the rebuilt iSCSIInitiator KEXT for the next reboot.
# Does NOT unload the currently running KEXT or stop iscsid.
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(id -u)" != "0" ]; then
  echo "Run with sudo:"
  echo "  sudo ./install_kext_next_boot.sh"
  exit 1
fi

SRC="build/iSCSIInitiator.kext"
DST="/Library/Extensions/iSCSIInitiator.kext"
EXPECTED_VERSION="1.0.1"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/Library/Extensions/iSCSIInitiator.kext.backup-${STAMP}"

[ -d "$SRC" ] || { echo "Missing $SRC; run ./build_kext.sh first."; exit 1; }

echo ">> Verifying rebuilt KEXT..."
codesign --verify --deep --strict "$SRC"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SRC/Contents/Info.plist")"
if [ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]; then
  echo "Refusing to stage unexpected KEXT version: $ACTUAL_VERSION (expected $EXPECTED_VERSION)"
  exit 2
fi
echo "   version $ACTUAL_VERSION verified"

if [ -d "$DST" ]; then
  echo ">> Backing up installed KEXT:"
  echo "   $BACKUP"
  cp -Rp "$DST" "$BACKUP"
fi

echo ">> Staging rebuilt KEXT (running KEXT is NOT unloaded)..."
rm -rf "$DST"
cp -R "$SRC" "$DST"
chown -R root:wheel "$DST"
chmod -R go-w "$DST"

echo ">> Asking macOS to stage the KEXT update..."
echo "   (The currently running KEXT is intentionally NOT unloaded.)"
if kmutil load -p "$DST"; then
  echo "   kmutil accepted the update request."
else
  echo "   kmutil did not load it immediately. On Apple Silicon this can mean"
  echo "   the update is awaiting approval/reboot; the installed KEXT remains"
  echo "   staged at $DST and the backup remains untouched."
fi

echo
echo "=== Staged successfully ==="
echo "The currently running iSCSI KEXT remains active until reboot."
echo "If Privacy & Security asks to approve the updated extension, approve it,"
echo "then reboot normally when convenient."
echo
echo "After reboot verify:"
echo "  kmutil showloaded | grep -i iscsi"
echo "  ioreg -p IOPower -r -c com_github_iscsi_osx_iSCSIVirtualHBA -l"
echo
echo "Rollback (if needed):"
echo "  sudo rm -rf \"$DST\""
echo "  sudo cp -Rp \"$BACKUP\" \"$DST\""
echo "  sudo chown -R root:wheel \"$DST\""
echo "  sudo kmutil load -p \"$DST\""
echo "  sudo reboot"
