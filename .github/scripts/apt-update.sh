#!/bin/bash
# Refresh the package lists, from Ubuntu's archive only.
#
# The runner image carries third-party apt sources this project never installs
# from -- Google Chrome's and Microsoft's. `apt-get update` exits non-zero when
# any source fails, and Google republishes its index several times a day: a
# fetch that straddles a republish gets
#
#   Err: https://dl.google.com/linux/chrome-stable/deb stable/main amd64 Packages
#     Hash Sum mismatch
#
# and the step fails, though every package we ask for came down fine from
# Ubuntu. Dropping the sources we do not use is what makes this build depend on
# Ubuntu alone; the retries cover a genuinely flaky mirror.
set -euo pipefail

sudo rm -f /etc/apt/sources.list.d/google-chrome* \
           /etc/apt/sources.list.d/*google* \
           /etc/apt/sources.list.d/microsoft* || true

sudo apt-get -q -y -o Acquire::Retries=3 update
