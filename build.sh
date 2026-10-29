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
# Sign with a stable identity so macOS remembers "Always Allow" for Keychain access across rebuilds.
# Override with HOP_SIGN_IDENTITY (a name or SHA-1 from `security find-identity -v -p codesigning`); "-" forces ad hoc.
IDENTITY="${HOP_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  # `|| true`: under `set -e`, a pipeline that ends in no match (grep exits 1) would otherwise
  # abort the script here instead of falling through to the ad-hoc warning below.
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | grep -v REVOKED | head -1 | awk '{print $2}' || true)
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  echo "warning: no Apple Development identity found; signing ad hoc, so macOS will ask for Keychain access after every rebuild." >&2
  echo "         Sign in to Xcode (Settings > Accounts) to get one, or set HOP_SIGN_IDENTITY." >&2
fi
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Hop || true
  mkdir -p "$HOME/Applications"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"
  if [[ -d "$HOME/bin" ]]; then
    ln -sfn "$INSTALLED/Contents/MacOS/Hop" "$HOME/bin/hop"
    echo "Linked $HOME/bin/hop"
  else
    echo "Command line: $INSTALLED/Contents/MacOS/Hop (make ~/bin to get a 'hop' link)"
  fi
  open "$INSTALLED"
  echo "Installed $INSTALLED"
fi
