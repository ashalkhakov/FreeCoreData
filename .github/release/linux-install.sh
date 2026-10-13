#!/bin/bash
# The framework, Model Builder, the launcher and the samples (their models compiled by the momc built here, which is not on PATH) into the prefix's System domain, where gnustep-release-actions'
# appimage takes them from.
set -eo pipefail
# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
momc="$(pwd)/Tools/momc/obj/momc"
make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C Tools/momc
for dir in ModelBuilder CDLauncher Examples/EmployeeDirectory Examples/Staffbook Examples/Bulletin; do
  make -C "$dir" install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM MOMC="$momc"
done
