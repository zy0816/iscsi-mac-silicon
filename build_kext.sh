#!/bin/bash
# Build the iSCSI kernel extension for modern macOS (arm64), using only
# Command Line Tools (no full Xcode / KDK required — the Kernel.framework
# headers ship inside the CLT macOS SDK).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
SDK="$(xcrun --show-sdk-path)"
KH="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
PKH="$SDK/System/Library/Frameworks/Kernel.framework/PrivateHeaders"
SHARED="Source/User/iSCSI Framework"

BUNDLE_ID="com.github.iscsi-osx.iSCSIInitiator"
KEXT_NAME="iSCSIInitiator"
VERSION="1.0.1"
BUILD="build"
KEXT="$BUILD/$KEXT_NAME.kext"
# Apple Silicon kernel + kexts are arm64e with the kernel ABI. The kmod
# static libs in the SDK only ship an 'arm64e.kernel' slice, so we must build
# arm64e (plain arm64 will fail to link). Intel builds use x86_64.
ARCH="${ARCH:-arm64e}"

mkdir -p "$BUILD/obj"

DEFS=(-DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
      -DNAME_PREFIX_U=com_github_iscsi_osx)
# Set DEBUG=1 in the environment to enable the kext's DBLog() kernel logging
# (IOLog). Useful for diagnosing the login/data path; noisy, so off by default.
if [ -n "${DEBUG:-}" ]; then DEFS+=(-DDEBUG); echo "   (DEBUG kernel logging enabled)"; fi
INCS=(-I"$KH" -I"$PKH" -I"Source/Kernel" -I"$SHARED")
COMMON=(-arch "$ARCH" -isysroot "$SDK" "${INCS[@]}" "${DEFS[@]}"
        -fno-builtin -fno-common -mkernel -Os -g
        -fno-stack-protector -fno-stack-check
        -Wno-deprecated-declarations)
CXXFLAGS=("${COMMON[@]}" -include Source/Kernel/Prefix.pch
          -fapple-kext -fno-exceptions -fno-rtti -std=gnu++17)
CFLAGS=("${COMMON[@]}" -std=gnu11)

# Explicit source list mirroring the kext target's Sources build phase.
# NOTE: iSCSIInitiatorClient.cpp / iSCSIInitiatorClient.h are legacy dead code
# (superseded by iSCSIHBAUserClient.cpp) and are intentionally excluded.
CXX_SRCS=(
  Source/Kernel/iSCSIInitiator.cpp
  Source/Kernel/iSCSIVirtualHBA.cpp
  Source/Kernel/iSCSIHBAUserClient.cpp
  Source/Kernel/iSCSIPDUKernel.cpp
  Source/Kernel/iSCSITaskQueue.cpp
  Source/Kernel/iSCSIIOEventSource.cpp
)
C_SRCS=(
  Source/Kernel/crc32c.c
)

OBJS=()
echo ">> Compiling C++ kernel sources..."
for f in "${CXX_SRCS[@]}"; do
  o="$BUILD/obj/$(basename "${f%.cpp}").o"
  clang++ "${CXXFLAGS[@]}" -c "$f" -o "$o"
  OBJS+=("$o")
  echo "   [cxx] $(basename "$f")"
done
echo ">> Compiling C kernel sources..."
for f in "${C_SRCS[@]}"; do
  o="$BUILD/obj/$(basename "${f%.c}").o"
  clang "${CFLAGS[@]}" -c "$f" -o "$o"
  OBJS+=("$o")
  echo "   [cc ] $(basename "$f")"
done

# Generate the kmod_info structure the kernel requires to load the kext.
# Xcode normally auto-generates this; we do it by hand. _start/_stop come from
# libkmod; _realmain/_antimain are 0 because class instantiation is driven by
# the IOKitPersonalities, not a module main().
KMODC="$BUILD/obj/kmod_info.c"
cat > "$KMODC" <<EOF
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
KMOD_EXPLICIT_DECL($BUNDLE_ID, "$VERSION", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOF
clang "${CFLAGS[@]}" -c "$KMODC" -o "$BUILD/obj/kmod_info.o"
OBJS+=("$BUILD/obj/kmod_info.o")
echo "   [cc ] kmod_info.c"

echo ">> Linking kext binary..."
clang++ -arch "$ARCH" -isysroot "$SDK" -nostdlib -fapple-kext \
  -Xlinker -kext -Xlinker -object_path_lto -Xlinker "$BUILD/lto.o" \
  -lkmodc++ -lkmod -lcc_kext \
  "${OBJS[@]}" -o "$BUILD/$KEXT_NAME"

echo ">> Assembling .kext bundle..."
rm -rf "$KEXT"
mkdir -p "$KEXT/Contents/MacOS"
cp "$BUILD/$KEXT_NAME" "$KEXT/Contents/MacOS/$KEXT_NAME"

# Expand Info.plist placeholders
python3 - "$ROOT/Source/Kernel/Info.plist" "$KEXT/Contents/Info.plist" <<'PY'
import sys, re
src, dst = sys.argv[1], sys.argv[2]
data = open(src).read()
repl = {
    "${EXECUTABLE_NAME}": "iSCSIInitiator",
    "$(PRODUCT_BUNDLE_IDENTIFIER)": "com.github.iscsi-osx.iSCSIInitiator",
    "${PRODUCT_NAME}": "iSCSIInitiator",
    "${NAME_PREFIX_D}": "com.github.iscsi-osx",
    "$(NAME_PREFIX_D)": "com.github.iscsi-osx",
    "${NAME_PREFIX_U}": "com_github_iscsi_osx",
    "$(NAME_PREFIX_U)": "com_github_iscsi_osx",
}
for k, v in repl.items():
    data = data.replace(k, v)
open(dst, "w").write(data)
print("   Info.plist written")
PY

# Align the bundle version with the kmod_info version (OSKext checks these match)
plutil -replace CFBundleVersion -string "$VERSION" "$KEXT/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$KEXT/Contents/Info.plist"

echo ">> Ad-hoc code-signing kext..."
codesign --force --sign - "$KEXT"

echo ">> Validating bundle..."
codesign -vvv "$KEXT" 2>&1 || true
file "$KEXT/Contents/MacOS/$KEXT_NAME"
kmutil inspect --bundle-path "$KEXT" 2>&1 | head -5 || true

echo ">> Done: $KEXT"
