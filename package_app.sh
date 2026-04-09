#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP="ZaiTokenWidget.app"
BIN=".build/release/ZaiTokenWidget"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/ZaiTokenWidget"
echo "Built $APP — run: open \"$APP\""
