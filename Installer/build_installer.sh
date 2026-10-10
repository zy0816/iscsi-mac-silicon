#!/bin/bash
# Assemble the distributable installer: a signed-payload .pkg wrapped in a .dmg.
# Prerequisites (built by the repo's other scripts):
#   ../build/iSCSIInitiator.kext   (build_kext.sh)
#   ../build/iSCSI.framework       (build_user.sh)
#   ../build/iscsid ../build/iscsictl
#   ../App/build/iSCSI.app         (App/build_app.sh)
set -euo pipefail
cd "$(dirname "$0")"
ROOT=".."
BUILD="$ROOT/build"
APP="$ROOT/App/build/iSCSI.app"
VERSION="${1:-1.0.1}"
PKG_ID="com.github.iscsi-osx.installer"

for f in "$BUILD/iSCSIInitiator.kext" "$BUILD/iSCSI.framework" "$BUILD/iscsid" "$BUILD/iscsictl" "$APP"; do
  [ -e "$f" ] || { echo "Missing: $f — build it first."; exit 1; }
done

echo ">> Staging payload…"
PAY="stage/payload"
rm -rf stage; mkdir -p \
  "$PAY/Library/Extensions" \
  "$PAY/Library/Frameworks" \
  "$PAY/Library/LaunchDaemons" \
  "$PAY/usr/local/libexec" \
  "$PAY/usr/local/bin" \
  "$PAY/Applications"

cp -R "$BUILD/iSCSIInitiator.kext" "$PAY/Library/Extensions/"
cp -R "$BUILD/iSCSI.framework"     "$PAY/Library/Frameworks/"
cp    "$BUILD/iscsid"              "$PAY/usr/local/libexec/"
cp    "$BUILD/iscsictl"            "$PAY/usr/local/bin/"
cp    "$ROOT/Source/User/iscsid/com.github.iscsi-osx.iscsid.plist" \
      "$PAY/Library/LaunchDaemons/"
cp -R "$APP"                       "$PAY/Applications/"

echo ">> Building component pkg…"
mkdir -p stage/scripts
cp scripts/postinstall stage/scripts/postinstall
chmod +x stage/scripts/postinstall

pkgbuild \
  --root "$PAY" \
  --scripts stage/scripts \
  --identifier "$PKG_ID.component" \
  --version "$VERSION" \
  --install-location "/" \
  stage/iSCSI-component.pkg

echo ">> Building product archive with welcome/conclusion…"
cat > stage/distribution.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>iSCSI for Apple Silicon</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <options customize="never" require-scripts="true" hostArchitectures="arm64"/>
  <volume-check>
    <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
  </volume-check>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="iSCSI"><pkg-ref id="$PKG_ID.component"/></choice>
  <pkg-ref id="$PKG_ID.component" version="$VERSION" onConclusion="none">iSCSI-component.pkg</pkg-ref>
</installer-gui-script>
EOF

OUT="$BUILD/iSCSI-for-Apple-Silicon-$VERSION.pkg"
productbuild \
  --distribution stage/distribution.xml \
  --resources resources \
  --package-path stage \
  "$OUT"

echo ">> Wrapping in a .dmg…"
DMG_DIR="stage/dmg"; mkdir -p "$DMG_DIR"
cp "$OUT" "$DMG_DIR/"
ln -sf /Applications "$DMG_DIR/Applications" 2>/dev/null || true
DMG="$BUILD/iSCSI-for-Apple-Silicon-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "iSCSI $VERSION" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG" >/dev/null

echo ""
echo "=== Installer ready ==="
echo "  PKG: $OUT"
echo "  DMG: $DMG"
