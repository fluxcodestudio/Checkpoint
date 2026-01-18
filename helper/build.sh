#!/usr/bin/env bash
# ==============================================================================
# Build CheckpointHelper menu bar app
# ==============================================================================
# Usage: ./build.sh [release|debug]
# Output: CheckpointHelper.app in current directory
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/CheckpointHelper"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="CheckpointHelper"
OUTPUT_APP="$SCRIPT_DIR/$APP_NAME.app"

BUILD_TYPE="${1:-release}"

echo "Building $APP_NAME ($BUILD_TYPE)..."

# Clean previous build
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_APP"
mkdir -p "$BUILD_DIR"

# Build flags
if [[ "$BUILD_TYPE" == "release" ]]; then
    SWIFT_FLAGS="-O -whole-module-optimization"
else
    SWIFT_FLAGS="-g"
fi

# Compile all Swift files
echo "Compiling Swift sources..."
SWIFT_FILES=(
    "$SOURCE_DIR/main.swift"
    "$SOURCE_DIR/HeartbeatMonitor.swift"
    "$SOURCE_DIR/DaemonController.swift"
    "$SOURCE_DIR/NotificationManager.swift"
    "$SOURCE_DIR/MenuBarManager.swift"
    "$SOURCE_DIR/DashboardWindow.swift"
    "$SOURCE_DIR/AppDelegate.swift"
)

swiftc \
    $SWIFT_FLAGS \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macos12.0 \
    -import-objc-header /dev/null \
    -framework Cocoa \
    -framework SwiftUI \
    -framework UserNotifications \
    -o "$BUILD_DIR/$APP_NAME" \
    "${SWIFT_FILES[@]}"

# Create app bundle structure
echo "Creating app bundle..."
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"

# Copy executable
mv "$BUILD_DIR/$APP_NAME" "$OUTPUT_APP/Contents/MacOS/"

# Copy Info.plist
cp "$SOURCE_DIR/Info.plist" "$OUTPUT_APP/Contents/"

# Sign the app (ad-hoc for local use)
echo "Signing app..."
codesign --force --deep --sign - "$OUTPUT_APP"

# Clean up
rm -rf "$BUILD_DIR"

echo ""
echo "Build complete: $OUTPUT_APP"
echo ""
echo "To install:"
echo "  cp -r '$OUTPUT_APP' /Applications/"
echo ""
echo "To add to Login Items:"
echo "  osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"/Applications/$APP_NAME.app\", hidden:true}'"
