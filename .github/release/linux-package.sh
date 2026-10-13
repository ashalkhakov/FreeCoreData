#!/bin/bash
# FreeCoreData-<version>-x86_64.AppImage: the CDLauncher chooser, Model
# Builder and the sample apps, with the GNUstep runtime, in one file.
set -euo pipefail
GNUSTEP_PREFIX="$PREFIX" ./Scripts/prepare-appdir.sh
GNUSTEP_PREFIX="$PREFIX" ./Scripts/package-appimage.sh
