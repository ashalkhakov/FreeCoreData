#!/bin/bash
# Write a version into everything ModelBuilder's About panel reads, so a
# packaged build says which build it is.
#
#   ./Scripts/stamp-version.sh 1.2.3
#
# Ported from XFormsKit's. The version comes from the tag, or from the run
# number for an unreleased build -- the same value the AppImage and the macOS
# archive are named after. Only the release and CI workflows run this; the
# numbers committed to the tree are what a build from a working copy says.
#
# Three files:
#   * ModelBuilder/Info.plist is the macOS bundle's plist (the Xcode target
#     sets GENERATE_INFOPLIST_FILE = NO and points INFOPLIST_FILE here).
#     CFBundleShortVersionString and CFBundleVersion are Apple's.
#   * ModelBuilder/Info-gnustep.plist is the GNUstep bundle's, copied into
#     Resources verbatim by ModelBuilder/GNUmakefile. ApplicationRelease and
#     FullVersionID are what GSInfoPanel shows.
#   * ModelBuilder.xcodeproj's MARKETING_VERSION / CURRENT_PROJECT_VERSION, so
#     the build settings agree with the plist they sit beside.
#
# Two forms of the version go in, because Apple parses some of these keys and
# GNUstep does not:
#
#   display -- the version as given, less any leading "v". The GNUstep About
#     panel shows this, and it can say anything: "0.0.0-229-18df32a" identifies
#     a build in a way a release number cannot.
#   numeric -- the leading dotted number of that, and nothing else.
#     CFBundleShortVersionString and CFBundleVersion are documented as
#     period-separated integers, and notarization rejects a bundle whose
#     version is not one.
set -euo pipefail

version=${1:-}
if [ -z "$version" ]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

display=${version#v}
numeric=$(printf '%s' "$display" | sed -n 's/^\([0-9][0-9.]*\).*/\1/p' | sed 's/\.$//')
if [ -z "$numeric" ]; then
    echo "$0: '$version' has no leading number; using 0.0.0 where Apple needs one" >&2
    numeric=0.0.0
fi

root=$(cd "$(dirname "$0")/.." && pwd)

# PlistBuddy is not on Linux and neither is xcodebuild: every file is edited the
# one way that works on either host.
python3 - "$root" "$display" "$numeric" <<'PY'
import re, sys
root, display, numeric = sys.argv[1:4]

def sub(path, text, pattern, value, expect_one=True):
    text, n = re.subn(pattern, lambda m: m.group(1) + value + m.group(2), text)
    if (expect_one and n != 1) or n == 0:
        raise SystemExit("%s: expected %s %s, found %d"
                         % (path, "one" if expect_one else "some", pattern, n))
    return text

# The Apple plist: XML, numeric form only.
path = "%s/ModelBuilder/Info.plist" % root
text = open(path).read()
for key in ("CFBundleShortVersionString", "CFBundleVersion"):
    text = sub(path, text, r"(<key>%s</key>\s*<string>)[^<]*(</string>)" % key, numeric)
open(path, "w").write(text)

# The GNUstep plist: OpenStep format, display form. FullVersionID is not in
# the tree -- a working-copy build has nothing to say beyond its release -- so
# it is added beside ApplicationRelease rather than replaced.
path = "%s/ModelBuilder/Info-gnustep.plist" % root
text = open(path).read()
text = sub(path, text, r'(\bApplicationRelease = ")[^"]*(";)', display)
text = re.sub(r'\n\s*FullVersionID = "[^"]*";', "", text)
text = text.replace('ApplicationRelease = "%s";' % display,
                    'ApplicationRelease = "%s";\n  FullVersionID = "%s";' % (display, display))
open(path, "w").write(text)

path = "%s/ModelBuilder/ModelBuilder.xcodeproj/project.pbxproj" % root
text = open(path).read()
for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
    text = sub(path, text, r"(\b%s = )[^;]*(;)" % key, numeric, expect_one=False)
open(path, "w").write(text)
PY

echo "stamped $display, and $numeric where Apple parses it"
grep -h -A1 -E "CFBundleShortVersionString|CFBundleVersion" "$root/ModelBuilder/Info.plist" | grep "<string>"
grep -E "ApplicationRelease|FullVersionID" "$root/ModelBuilder/Info-gnustep.plist"
grep -m 1 -n "MARKETING_VERSION" "$root/ModelBuilder/ModelBuilder.xcodeproj/project.pbxproj"
