#!/bin/sh
# Developer shortcut: build, install Annex on this Mac and on a second Mac over SSH, and launch both.
# Usage: scripts/deploy-dev.sh user@other-mac
set -e
cd "$(dirname "$0")/.."
OTHER=${1:?usage: scripts/deploy-dev.sh user@other-mac}
./scripts/build.sh

echo "→ $OTHER"
tar -C build -czf - Annex.app | ssh "$OTHER" '
  set -e
  # remove the old proof-of-concept receiver if present
  launchctl bootout gui/$(id -u)/tech.satish.airextend.receiver 2>/dev/null || true
  rm -f ~/Library/LaunchAgents/tech.satish.airextend.receiver.plist
  rm -rf ~/Applications/AirExtend.app
  pkill -x Annex || true; sleep 0.5
  DEST=/Applications; [ -w "$DEST" ] || DEST=~/Applications; mkdir -p "$DEST"
  rm -rf "$DEST/Annex.app" && tar -C "$DEST" -xzf - && xattr -cr "$DEST/Annex.app"
  open "$DEST/Annex.app" && echo "launched $DEST/Annex.app"
'

echo "→ this Mac"
pkill -f AirExtend.app/Contents/MacOS/airext || true
rm -rf /Applications/AirExtend.app
pkill -x Annex || true; sleep 0.5
rm -rf /Applications/Annex.app && cp -R build/Annex.app /Applications/
open /Applications/Annex.app && echo "launched /Applications/Annex.app"
