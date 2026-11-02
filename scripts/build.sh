#!/bin/sh
# Builds build/annex, the command-line tool on top of the engine.
set -e
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -isysroot "$(xcrun --show-sdk-path)" -fobjc-arc -O2 -Wall -arch arm64 -mmacosx-version-min=14.0 \
  -Isrc/engine src/engine/*.m src/cli/main.m -o build/annex \
  -framework Cocoa -framework ScreenCaptureKit -framework VideoToolbox -framework AVFoundation \
  -framework CoreMedia -framework IOKit
codesign --force --sign - build/annex
echo "built build/annex"
