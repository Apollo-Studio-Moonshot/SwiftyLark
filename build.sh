#!/bin/bash
# Builds Swifty Lark with Xcode. The "Build Rust Core" build phase compiles
# rust/ with cargo, then Xcode builds the SwiftUI app, bundles mechanics.json
# and embeds swiftylark-core into Contents/Resources. Exits without opening a
# window. Output: build/Swifty Lark.app.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> building Swifty Lark (Xcode)"
rm -rf build
xcodebuild \
    -project "Swifty Lark.xcodeproj" \
    -scheme "Swifty Lark" \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    build

PRODUCT="build/DerivedData/Build/Products/Release/Swifty Lark.app"
APP="build/Swifty Lark.app"
rm -rf "$APP"
mkdir -p build
cp -R "$PRODUCT" "$APP"

echo "built $APP"
