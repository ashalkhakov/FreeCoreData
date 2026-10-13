#!/bin/bash
# The version stamped; linux-install.sh builds and installs the framework,
# momc, the launcher, Model Builder and the samples.
set -euo pipefail
./Scripts/stamp-version.sh "$APP_VERSION"
