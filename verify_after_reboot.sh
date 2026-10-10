#!/bin/bash
set -uo pipefail

EXPECTED_VERSION="1.0.1"
# Compare the loaded extension with the installed binary, not with the
# maintainer's build UUID (it changes between builds).
KEXT_BINARY="/Library/Extensions/iSCSIInitiator.kext/Contents/MacOS/iSCSIInitiator"
EXPECTED_UUID=""
if [ -f "$KEXT_BINARY" ]; then
  EXPECTED_UUID="$(dwarfdump --uuid "$KEXT_BINARY" 2>/dev/null | grep '(arm64e)' | grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | tr '[:lower:]' '[:upper:]' | head -1)"
fi
BUNDLE_ID="com.github.iscsi-osx.iSCSIInitiator"
HBA_CLASS="com_github_iscsi_osx_iSCSIVirtualHBA"

echo "=== iSCSI shutdown-fix verification ==="

loaded_line="$(kmutil showloaded 2>/dev/null | grep "$BUNDLE_ID" | head -1 || true)"
if [ -z "$loaded_line" ]; then
  echo "[FAIL] $BUNDLE_ID is not loaded"
  exit 2
fi

echo "[INFO] loaded: $loaded_line"

if echo "$loaded_line" | grep -q "($EXPECTED_VERSION)"; then
  echo "[OK] version $EXPECTED_VERSION is loaded"
else
  echo "[FAIL] expected version $EXPECTED_VERSION"
fi

loaded_uuid="$(echo "$loaded_line" | grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | tr '[:lower:]' '[:upper:]' | head -1)"
if [ -z "$EXPECTED_UUID" ]; then
  echo "[SKIP] Installed KEXT UUID unavailable (could not inspect $KEXT_BINARY)"
elif [ "$loaded_uuid" = "$EXPECTED_UUID" ]; then
  echo "[OK] Loaded UUID matches installed KEXT: $EXPECTED_UUID"
else
  echo "[FAIL] UUID mismatch: got $loaded_uuid, installed binary has $EXPECTED_UUID"
fi

power_dump="$(/usr/sbin/ioreg -p IOPower -r -c "$HBA_CLASS" -l -w0 2>/dev/null || true)"
if printf '%s\n' "$power_dump" | grep "$HBA_CLASS" >/dev/null; then
  echo "[OK] HBA is a member of the IOPower plane"
else
  echo "[FAIL] HBA not found in IOPower plane; systemWillShutdown() may not run"
fi

service_dump="$(/usr/sbin/ioreg -r -c "$HBA_CLASS" -l -w0 2>/dev/null || true)"
if printf '%s\n' "$service_dump" | grep "$HBA_CLASS" >/dev/null; then
  echo "[OK] HBA exists in IOService plane"
else
  echo "[FAIL] HBA missing from IOService plane"
fi

echo
echo "--- Current iSCSI disks ---"
found_disk=0
for node in /dev/disk[0-9]*; do
  disk="${node#/dev/}"
  case "$disk" in *s[0-9]*) continue ;; esac
  info="$(diskutil info "$disk" 2>/dev/null || true)"
  if printf '%s\n' "$info" | grep 'Protocol:.*iSCSI' >/dev/null; then
    found_disk=1
    printf '%s\n' "$info" | grep -E 'Device Identifier|Protocol|Disk Size|Mounted|Mount Point' || true
  fi
done
[ "$found_disk" -eq 1 ] || echo "(no iSCSI disks found)"

echo
echo "--- Recent driver messages (last 15 minutes) ---"
log show --last 15m --style compact --predicate 'eventMessage CONTAINS[c] "iscsi: HBA joined IOPower plane" OR eventMessage CONTAINS[c] "iscsi: systemWillShutdown" OR eventMessage CONTAINS[c] "iscsi: shutdown quiesce"' 2>/dev/null | tail -80 || true

echo
echo "For the decisive test, keep an iSCSI target connected and perform a normal restart."
echo "After the next boot, rerun this script and check DiagnosticReports for a new shutdown_stall/panic."
