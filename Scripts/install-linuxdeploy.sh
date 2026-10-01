#!/bin/bash
# Fetch linuxdeploy and the AppImage runtime, so packaging is one call from
# either workflow.
#
# linuxdeploy is itself an AppImage and is extracted rather than run: mounting
# one needs FUSE, which a container may not have, and extracting sidesteps the
# question entirely.
set -euo pipefail

dest=${LINUXDEPLOY_DIR:-/usr/local/lib/linuxdeploy}
runtime_dir=${APPIMAGE_RUNTIME_DIR:-/tmp/appimage-runtime}
arch=$(uname -m)

if [ ! -x "$dest/AppRun" ]; then
  curl -fsSL -o /tmp/linuxdeploy.AppImage \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${arch}.AppImage"
  chmod +x /tmp/linuxdeploy.AppImage
  (cd /tmp && ./linuxdeploy.AppImage --appimage-extract > /dev/null)
  sudo mkdir -p "$dest"
  # -a, not -r: the extracted tree has symlinks and relies on its exec
  # bits, and -r preserves neither reliably.
  sudo cp -a /tmp/squashfs-root/. "$dest/"
  sudo chmod -R a+rX "$dest"
fi

# A tree installed without its exec bits used to fail much later, in the
# packaging script, as "AppRun: Permission denied" -- which reads as a bug
# in packaging.  Fail here instead, where the cause is.
if [ ! -x "$dest/AppRun" ]; then
  echo "install-linuxdeploy: $dest/AppRun is not executable after install" >&2
  ls -l "$dest" >&2 || true
  exit 1
fi

mkdir -p "$runtime_dir"
if [ ! -s "$runtime_dir/runtime-$arch" ]; then
  curl -fsSL -o "$runtime_dir/runtime-$arch" \
    "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-${arch}"
fi
echo "linuxdeploy: $(ls -l "$dest/AppRun")"
echo "runtime:     $runtime_dir/runtime-$arch"
