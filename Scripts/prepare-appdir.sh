#!/bin/bash
# Assemble AppDir. Ported from XFormsKit's Scripts/prepare-appdir.sh (by way of
# RDLKit and UDQuakeTools, where it is known to work); the differences are
# marked.
#
#   GNUSTEP_PREFIX=/path/to/gnustep ./Scripts/prepare-appdir.sh
#
# Exit immediately if a command exits with a non-zero status
set -e

WORKSPACE_DIR=$(pwd)
# The prefix is built in the same job rather than unpacked into /opt, so it is
# passed in. The default keeps the original behaviour.
LOCAL_PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"

# 1. Recreate clean AppDir structural root
rm -rf AppDir
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/lib
mkdir -p AppDir/usr/etc
mkdir -p AppDir/usr/local/bin

# 2. Source GNUstep environment once
. "${LOCAL_PREFIX}/System/Library/Makefiles/GNUstep.sh"

# 3. Install into the prefix.
# DIFFERENCE from XFormsKit: the root GNUmakefile builds the CoreData framework
# alone (the XCTest bundle has its own, in Tests/), so there is nothing to
# exclude. ModelBuilder links the framework the root build produced and finds
# the installed copy at runtime.
make
make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C ModelBuilder
make -C ModelBuilder install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM

# The samples and the launcher that dispatches between everything (the
# XFormsKit arrangement: the image opens CDLauncher, which starts its
# sibling apps). Staffbook's model is compiled by momc, built first and
# pointed at explicitly - the tool is not installed on PATH here.
make -C Tools/momc
make -C CDLauncher
make -C CDLauncher install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C Examples/EmployeeDirectory
make -C Examples/EmployeeDirectory install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C Examples/Staffbook MOMC="${WORKSPACE_DIR}/Tools/momc/obj/momc"
make -C Examples/Staffbook install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM MOMC="${WORKSPACE_DIR}/Tools/momc/obj/momc"

if [ -d "${LOCAL_PREFIX}/System/Library/Themes" ]; then
mkdir -p AppDir/usr/System/Library/Themes
cp -Rp "${LOCAL_PREFIX}/System/Library/Themes/"* AppDir/usr/System/Library/Themes/
fi

# 4. Dynamically locate the background tools
for tool in gdnc gpbs make_services; do
FOUND_TOOL=$(find "${LOCAL_PREFIX}" -type f -name "$tool" 2>/dev/null | head -n 1 || true)
if [ -n "$FOUND_TOOL" ]; then
    cp -p "$FOUND_TOOL" AppDir/usr/lib/
    cp -p "$FOUND_TOOL" AppDir/usr/local/bin/
fi
done

# 5. Pull BOTH System and Local hierarchies into AppDir/usr/
if [ -d "${LOCAL_PREFIX}/System" ]; then
mkdir -p AppDir/usr/System
cp -Rp "${LOCAL_PREFIX}/System/"* AppDir/usr/System/
fi
if [ -d "${LOCAL_PREFIX}/Local" ]; then
mkdir -p AppDir/usr/Local
cp -Rp "${LOCAL_PREFIX}/Local/"* AppDir/usr/Local/
fi

# Bundle libobjc from the prefix base lib directory
for libobjc in "${LOCAL_PREFIX}"/lib/libobjc.so.*.*; do
if [ -f "$libobjc" ]; then
    soname=$(basename "$libobjc")
    cp -p "$libobjc" AppDir/usr/lib/
    ln -sf "$soname" "AppDir/usr/lib/${soname%.*}"
    ln -sf "$soname" AppDir/usr/lib/libobjc.so
fi
done

# Bundle libdispatch and its BlocksRuntime dependency safely
echo "=== Manually staging libdispatch and BlocksRuntime ==="
if ls "${LOCAL_PREFIX}/lib"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
elif ls "${LOCAL_PREFIX}/lib64"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib64"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib64"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
fi

# 6. Maintain versioned and unversioned fallback bundle linking
BACKEND_BUNDLE=$(find AppDir/usr -name "libgnustep-back-*.bundle" 2>/dev/null | head -n 1 || true)
if [ -n "$BACKEND_BUNDLE" ]; then
BUNDLE_DIR=$(dirname "$BACKEND_BUNDLE")
BACKEND_NAME=$(basename "$BACKEND_BUNDLE")
ln -sfv "$BACKEND_NAME" "$BUNDLE_DIR/libgnustep-back.bundle" || true
ln -sfv "$BACKEND_NAME" "$BUNDLE_DIR/back.bundle" || true
fi

# --- BUNDLE FONTS FOR PORTABILITY ---
# AppRun selects Liberation for the UI and DejaVu covers what it lacks, so the
# window looks the same on a host that has neither installed.
mkdir -p AppDir/usr/etc/fonts
cp Scripts/appimage/fonts.conf AppDir/usr/etc/fonts/fonts.conf
for dir in /usr/share/fonts/truetype/dejavu /usr/share/fonts/truetype/liberation \
           /usr/share/fonts/truetype/msttcorefonts; do
if [ -d "$dir" ]; then
    mkdir -p "AppDir/usr/share/fonts/truetype/$(basename "$dir")"
    cp -Rp "$dir"/* "AppDir/usr/share/fonts/truetype/$(basename "$dir")/"
fi
done

# Clean up residual folders
find AppDir -maxdepth 1 -type d ! -name "AppDir" ! -name "usr" -exec rm -rf {} + 2>/dev/null || true

echo "AppDir assembled:"
du -sh AppDir
# The apps and the framework they link, or the image is not what it says it is.
missing=0
for wrapper in CDLauncher.app ModelBuilder.app Staffbook.app EmployeeDirectory.app CoreData.framework; do
    found=$(find AppDir/usr -maxdepth 5 -name "$wrapper" | head -n 1)
    if [ -n "$found" ]; then
        echo "  $found"
    else
        echo "  MISSING: $wrapper" >&2
        missing=1
    fi
done
exit $missing
