#!/bin/bash
# Proof it starts. The apps are GUI-only, so each launch mode runs against a
# virtual display: bare (the launcher), a model to open (Model Builder), and
# each sample by its keyword; a bundle that cannot find its framework, its
# backend or its nibs dies here rather than for whoever downloads it.
set -euo pipefail
image=$1
log=$(mktemp)
for mode in "" Tests/MomcFixture.xcdatamodeld staffbook employeedirectory bulletin; do
  timeout 90 xvfb-run -a "$image" $mode > "$log" 2>&1 &
  pid=$!
  sleep 25
  if kill -0 $pid 2>/dev/null; then
    echo "${mode:-launcher}: up after 25s"
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
  else
    status=0; wait $pid || status=$?
    cat "$log"
    echo "::error::AppImage (${mode:-launcher}) exited on its own with status $status"
    exit 1
  fi
  # Staying up is not enough: an app whose nib failed to load stays up too,
  # as an icon with no menu and no window. GNUstep reports that on stderr.
  if grep -qE "Failed to load Xib|could not load nib|failed to load MainMenu" "$log"; then
    cat "$log"
    echo "::error::AppImage (${mode:-launcher}) started without its interface"
    exit 1
  fi
done
