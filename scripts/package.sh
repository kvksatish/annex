#!/bin/sh
# Builds Annex and wraps it in build/Annex.dmg (drag-to-Applications installer).
set -e
cd "$(dirname "$0")/.."
./scripts/build.sh
STAGE=build/dmg
rm -rf "$STAGE" build/Annex.dmg && mkdir -p "$STAGE"
cp -R build/Annex.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Annex" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet build/Annex.dmg
echo "packaged build/Annex.dmg ($(du -h build/Annex.dmg | cut -f1))"
