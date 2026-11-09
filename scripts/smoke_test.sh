#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=== Running Slate Automated Smoke Test Suite ==="

BUILD_DIR="$DIR/build/smoke"
mkdir -p "$BUILD_DIR"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

SOURCES=$(find "$DIR/Sources" -name "*.swift" ! -name "SlateApp.swift")
TEST_RUNNER="$DIR/Tests/Smoke/SmokeTestRunner.swift"
TEST_BIN="$BUILD_DIR/smoke_test_runner"

echo "Compiling smoke test binary..."
xcrun swiftc \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  -module-name SlateSmokeTest \
  $SOURCES \
  "$TEST_RUNNER" \
  -o "$TEST_BIN"

echo "Executing smoke tests (in-memory mode)..."
SLATE_IN_MEMORY_STORE=1 "$TEST_BIN"
echo "=== Smoke tests finished successfully! ==="
