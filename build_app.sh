#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Building Slate Native macOS App via Xcode ==="

APP_NAME="Slate"
BUILD_DIR="$DIR/build"
INSTALL_PATH="/Applications/$APP_NAME.app"
DERIVED_DATA="$BUILD_DIR/DerivedData"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# Generate xcodeproj if missing or project.yml changed
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --quiet
fi

xcodebuild \
  -project "$DIR/Slate.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build >/dev/null

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"

echo "Installing to $INSTALL_PATH..."
killall "$APP_NAME" 2>/dev/null || true
sleep 0.3
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "=== Build & Install Complete! ==="
echo "Installed:  $INSTALL_PATH"
open "$INSTALL_PATH" 2>/dev/null || true
