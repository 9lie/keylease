#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Keylease.app"
SDK="$(xcrun --show-sdk-path)"
TARGET="${KEYLEASE_ARCH:-$(uname -m)}-apple-macos14.0"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -target "$TARGET" -sdk "$SDK" \
  "$ROOT/Sources/KeyleaseApp/main.swift" \
  "$ROOT/Sources/KeyleaseApp/AppDelegate.swift" \
  "$ROOT/Sources/KeyleaseApp/LeaseStore.swift" \
  "$ROOT/Sources/KeyleaseApp/LeaseServer.swift" \
  "$ROOT/Sources/KeyleaseApp/PopoverView.swift" \
  -framework AppKit -framework SwiftUI -framework Carbon \
  -o "$APP/Contents/MacOS/Keylease"

xcrun swiftc -O -target "$TARGET" -sdk "$SDK" \
  "$ROOT/Sources/KeyleaseCLI/main.swift" \
  -o "$BUILD/keylease"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "Built:"
echo "  $APP"
echo "  $BUILD/keylease"
