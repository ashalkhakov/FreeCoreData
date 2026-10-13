#!/bin/bash
# The version stamped; prepare-appdir.sh (linux-package.sh) builds the
# framework, momc, the launcher, Model Builder and the samples.
set -euo pipefail
./Scripts/stamp-version.sh "$APP_VERSION"
