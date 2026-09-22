#!/bin/bash
# The executables linuxdeploy should trace for dependencies: the app.
# Found rather than named by path, because gnustep-make decides where it
# lands.
set -euo pipefail
appdir=${1:-AppDir}
for name in ModelBuilder; do
  find "$appdir" -type f -name "$name" -perm -111 -exec file {} \; 2>/dev/null \
    | awk -F: '/ELF/{print $1; exit}'
done
