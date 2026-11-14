#!/bin/sh
# Builds the app, then packs it into build/DevIsland-<version>.dmg with a shortcut to Applications.
set -e
cd "$(dirname "$0")/.."
sh Scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGE="build/dmg"
DMG="build/DevIsland-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/DevIsland.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DevIsland" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Created $DMG"
