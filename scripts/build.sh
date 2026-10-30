#!/bin/sh
# Builds build/Annex.app — one app that both sends (extends this Mac) and receives (acts as a display).
set -e
cd "$(dirname "$0")/.."
SDK="$(xcrun --show-sdk-path)"
APP=build/Annex.app
VERSION=0.3.0
rm -rf build/obj "$APP" && mkdir -p build/obj "$APP/Contents/MacOS" "$APP/Contents/Resources"

for f in src/engine/*.m; do
  xcrun clang -c -isysroot "$SDK" -fobjc-arc -O2 -Wall -arch arm64 -mmacosx-version-min=14.0 \
    "$f" -o "build/obj/$(basename "$f" .m).o"
done

xcrun swiftc -O -parse-as-library -sdk "$SDK" -target arm64-apple-macos14.0 \
  -import-objc-header src/engine/Annex-Bridging-Header.h \
  src/app/*.swift build/obj/*.o -o "$APP/Contents/MacOS/Annex" \
  -framework ScreenCaptureKit -framework VideoToolbox -framework AVFoundation -framework CoreMedia \
  -framework IOKit -framework ServiceManagement

if [ ! -f assets/AppIcon.icns ]; then
  xcrun swiftc -sdk "$SDK" scripts/make-icon.swift -o build/make-icon && build/make-icon build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o assets/AppIcon.icns
fi
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.kvksatish.annex</string>
  <key>CFBundleName</key><string>Annex</string>
  <key>CFBundleDisplayName</key><string>Annex</string>
  <key>CFBundleExecutable</key><string>Annex</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSScreenCaptureUsageDescription</key><string>Annex sends your extra display to your other Mac.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Annex finds and connects to your other Mac over a cable or Wi-Fi.</string>
  <key>NSBonjourServices</key><array><string>_annex._tcp</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP ($VERSION)"
