#!/bin/bash
# For gnustep-release-actions' macos-release.yml: first what CI ran, the unit
# tests against Apple's Core Data, and the PostgreSQL and MySQL stores built
# for testing (against Homebrew's libpq and MariaDB Connector/C, which their
# Xcode projects find in /opt/homebrew); then Model Builder, the universal
# Release build, into $RELEASE_DIR. It links Cocoa and the system Core Data;
# the one framework it embeds is Sparkle.
set -euo pipefail
xcodebuild -version
xcodebuild -project CoreDataTests.xcodeproj -scheme CoreDataTests \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" \
  -resultBundlePath "$RUNNER_TEMP/CoreDataTests.xcresult" test
brew install libpq mariadb-connector-c
xcodebuild -project Backends/PostgreSQL/CDPostgreSQLStore.xcodeproj -scheme CDPostgreSQLStoreTests \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" build-for-testing
xcodebuild -project Backends/MySQL/CDMySQLStore.xcodeproj -scheme CDMySQLStoreTests \
  -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" build-for-testing

xcodebuild -project ModelBuilder/ModelBuilder.xcodeproj -scheme ModelBuilder \
  -destination 'generic/platform=macOS' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" build
ditto "$RUNNER_TEMP/DerivedData/Build/Products/Release/ModelBuilder.app" "$RELEASE_DIR/ModelBuilder.app"
