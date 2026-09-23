#!/bin/bash
# Builds "build/Hop.app". With --install, replaces "~/Applications/Hop.app" and launches it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product Hop
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Hop.app"
INSTALLED="$HOME/Applications/Hop.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Hop" "$APP/Contents/MacOS/Hop"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Hop || true
  mkdir -p "$HOME/Applications"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"
  open "$INSTALLED"
  echo "Installed $INSTALLED"
fi
