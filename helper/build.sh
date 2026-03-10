#!/usr/bin/env bash
# ==============================================================================
# Build CheckpointHelper menu bar app
# ==============================================================================
# Usage: ./build.sh [release|debug] [--sign] [--notarize]
# Output: CheckpointHelper.app in current directory
#
# Options:
#   release|debug       Build type (default: release)
#   --sign              Sign with Developer ID (requires certificate)
#   --notarize          Sign + submit to Apple for notarization
#   --dmg               Create distributable .dmg after build
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/CheckpointHelper"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="CheckpointHelper"
OUTPUT_APP="$SCRIPT_DIR/$APP_NAME.app"

# Code signing identity (override via environment variables)
DEVELOPER_ID="${CHECKPOINT_DEVELOPER_ID:-Developer ID Application: Fluxcode Studio LLC (${CHECKPOINT_TEAM_ID:-5L88QV65A9})}"
TEAM_ID="${CHECKPOINT_TEAM_ID:-5L88QV65A9}"
BUNDLE_ID="com.checkpoint.helper"
ENTITLEMENTS="$SOURCE_DIR/CheckpointHelper.entitlements"

# Parse arguments
BUILD_TYPE="release"
DO_SIGN=false
DO_NOTARIZE=false
DO_DMG=false

for arg in "$@"; do
    case "$arg" in
        release|debug) BUILD_TYPE="$arg" ;;
        --sign) DO_SIGN=true ;;
        --notarize) DO_SIGN=true; DO_NOTARIZE=true ;;
        --dmg) DO_DMG=true ;;
        --help|-h)
            echo "Usage: ./build.sh [release|debug] [--sign] [--notarize] [--dmg]"
            exit 0
            ;;
    esac
done

echo "Building $APP_NAME ($BUILD_TYPE)..."
[[ "$DO_SIGN" == "true" ]] && echo "  Code signing: Developer ID"
[[ "$DO_NOTARIZE" == "true" ]] && echo "  Notarization: enabled"

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

# Copy icon assets
echo "Copying icon assets..."
if [[ -f "$SOURCE_DIR/StatusBarIconTemplate.png" ]]; then
    cp "$SOURCE_DIR/StatusBarIconTemplate.png" "$OUTPUT_APP/Contents/Resources/"
fi
if [[ -f "$SOURCE_DIR/StatusBarIconTemplate@2x.png" ]]; then
    cp "$SOURCE_DIR/StatusBarIconTemplate@2x.png" "$OUTPUT_APP/Contents/Resources/"
fi
if [[ -f "$SOURCE_DIR/AppIcon.icns" ]]; then
    cp "$SOURCE_DIR/AppIcon.icns" "$OUTPUT_APP/Contents/Resources/"
fi

# Copy Checkpoint logo for dashboard
LOGO_SRC="$SCRIPT_DIR/../website/checkpoint-logo-no-text.png"
if [[ -f "$LOGO_SRC" ]]; then
    cp "$LOGO_SRC" "$OUTPUT_APP/Contents/Resources/checkpoint-logo.png"
fi

# Sign the app
echo "Signing app..."
if [[ "$DO_SIGN" == "true" ]]; then
    # Verify identity exists
    if ! security find-identity -v -p codesigning | grep -q "$TEAM_ID"; then
        echo "❌ Developer ID certificate not found in keychain" >&2
        echo "   Expected: $DEVELOPER_ID" >&2
        echo "   Falling back to ad-hoc signing" >&2
        codesign --force --deep --sign - "$OUTPUT_APP"
    else
        # Sign with Developer ID + hardened runtime + entitlements
        codesign --force --deep \
            --sign "$DEVELOPER_ID" \
            --entitlements "$ENTITLEMENTS" \
            --options runtime \
            --timestamp \
            "$OUTPUT_APP"
        echo "  Signed with: $DEVELOPER_ID"

        # Verify signature
        if codesign --verify --deep --strict "$OUTPUT_APP" 2>/dev/null; then
            echo "  Signature verified ✓"
        else
            echo "⚠ Signature verification failed" >&2
        fi
    fi
else
    # Ad-hoc signing for local development
    codesign --force --deep --sign - "$OUTPUT_APP"
    echo "  Ad-hoc signed (local use only)"
fi

# Notarize
if [[ "$DO_NOTARIZE" == "true" ]]; then
    echo ""
    echo "Notarizing app..."

    # Create zip for notarization submission
    NOTARIZE_ZIP="$SCRIPT_DIR/$APP_NAME-notarize.zip"
    ditto -c -k --keepParent "$OUTPUT_APP" "$NOTARIZE_ZIP"

    # Submit to Apple
    echo "  Submitting to Apple notary service..."
    if xcrun notarytool submit "$NOTARIZE_ZIP" \
        --team-id "$TEAM_ID" \
        --keychain-profile "notarytool-profile" \
        --wait 2>&1 | tee /tmp/notarize-output.txt; then

        # Staple the notarization ticket
        echo "  Stapling notarization ticket..."
        xcrun stapler staple "$OUTPUT_APP"
        echo "  Notarization complete ✓"
    else
        echo ""
        echo "⚠ Notarization failed. If this is your first time, set up credentials:"
        echo ""
        echo "  xcrun notarytool store-credentials notarytool-profile \\"
        echo "    --apple-id YOUR_APPLE_ID \\"
        echo "    --team-id $TEAM_ID \\"
        echo "    --password APP_SPECIFIC_PASSWORD"
        echo ""
        echo "  Generate an app-specific password at: https://appleid.apple.com/account/manage"
    fi

    rm -f "$NOTARIZE_ZIP"
fi

# Create DMG
if [[ "$DO_DMG" == "true" ]]; then
    echo ""
    echo "Creating DMG..."
    DMG_PATH="$SCRIPT_DIR/$APP_NAME.dmg"
    rm -f "$DMG_PATH"

    # Create temp DMG folder with app + Applications symlink
    DMG_STAGING="$BUILD_DIR/dmg-staging"
    mkdir -p "$DMG_STAGING"
    cp -r "$OUTPUT_APP" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH" 2>/dev/null

    # Sign the DMG too
    if [[ "$DO_SIGN" == "true" ]]; then
        codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"
    fi

    rm -rf "$DMG_STAGING"
    echo "  DMG created: $DMG_PATH"
fi

# Clean up
rm -rf "$BUILD_DIR"

echo ""
echo "Build complete: $OUTPUT_APP"
echo ""
echo "To install:"
echo "  cp -r '$OUTPUT_APP' /Applications/"
echo ""
if [[ "$DO_SIGN" != "true" ]]; then
    echo "To build for distribution:"
    echo "  ./build.sh release --sign --notarize --dmg"
    echo ""
fi
echo "To add to Login Items:"
echo "  osascript -e 'tell application \"System Events\" to make login item at end with properties {path:\"/Applications/$APP_NAME.app\", hidden:true}'"
