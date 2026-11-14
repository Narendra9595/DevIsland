#!/bin/sh
# Builds build/DevIsland.app (release, Apple silicon + Intel) with its icon, signed ad-hoc.
# Not notarized: on first open macOS asks you to allow it (see README → Install).
set -e
cd "$(dirname "$0")/.."

# Universal binary when the toolchain supports it, otherwise this Mac's architecture.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/DevIsland"
else
    swift build -c release
    BINARY="$(swift build -c release --show-bin-path)/DevIsland"
fi

APP="build/DevIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/DevIsland"
cp Resources/Info.plist "$APP/Contents/"

# App icon: the app draws it in code; export every size and pack it as AppIcon.icns.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/DevIsland" --export-iconset "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
