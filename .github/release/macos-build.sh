#!/bin/bash
# ModelBuilder for gnustep-release-actions' macos-release.yml: stamped, and
# the universal Release build into $RELEASE_DIR. It links Cocoa and the
# system CoreData; the one framework it embeds is Sparkle.
set -euo pipefail
./Scripts/stamp-version.sh "$APP_VERSION"
xcodebuild -project ModelBuilder/ModelBuilder.xcodeproj -scheme ModelBuilder \
  -destination 'generic/platform=macOS' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" build
ditto "$RUNNER_TEMP/DerivedData/Build/Products/Release/ModelBuilder.app" "$RELEASE_DIR/ModelBuilder.app"
