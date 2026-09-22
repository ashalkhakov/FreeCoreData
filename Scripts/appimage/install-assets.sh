#!/bin/bash
# Put the AppImage's own metadata into AppDir: the launcher, the desktop entry
# and the icon. linuxdeploy insists on a launcher, one desktop file and an
# icon named by it.
set -euo pipefail
workspace_dir=${1:-$(pwd)}
appdir=${2:-AppDir}

mkdir -p "$appdir/usr/share/applications" "$appdir/usr/share/icons/hicolor/256x256/apps"

install -m 0755 "$workspace_dir/Scripts/appimage/AppRun" "$appdir/AppRun"
install -m 0644 "$workspace_dir/Scripts/appimage/FreeCoreData.desktop" \
        "$appdir/freecoredata.desktop"
install -m 0644 "$workspace_dir/Scripts/appimage/FreeCoreData.desktop" \
        "$appdir/usr/share/applications/freecoredata.desktop"

# The same picture ModelBuilder's GNUstep bundle carries as its application
# icon, doing suite duty until the launcher has one of its own.
install -m 0644 "$workspace_dir/ModelBuilder/ModelBuilder.png" \
        "$appdir/freecoredata.png"
install -m 0644 "$workspace_dir/ModelBuilder/ModelBuilder.png" \
        "$appdir/usr/share/icons/hicolor/256x256/apps/freecoredata.png"
