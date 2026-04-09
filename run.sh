#!/bin/sh
# Launches the menu bar app via `open` so it is NOT tied to this terminal.
# Running .build/release/ZaiTokenWidget directly and pressing Ctrl+C will quit the app.
set -e
cd "$(dirname "$0")"
./package_app.sh
open ZaiTokenWidget.app
echo "ZaiTokenWidget launched (not attached to this shell). Check the menu bar on the right."
