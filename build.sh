#!/bin/zsh
# Builds StarTime.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP="build/StarTime.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O \
  -target arm64-apple-macos13.0 \
  -framework Cocoa \
  -o "$APP/Contents/MacOS/StarTime" \
  Sources/main.swift

# Stable requirement so the Accessibility permission survives rebuilds.
codesign --force --sign - \
  -r='designated => identifier "com.furkangonenc.startime"' \
  "$APP"
echo "Built $APP"
