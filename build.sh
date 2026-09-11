#!/bin/bash
set -e

echo "=== Building Progressive Blur for macOS ==="

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

APP_NAME="ProgressiveBlur"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "-> Compiling Swift release binary..."
swift build -c release

echo "-> Assembling $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy Shaders.metal to Resources
cp "$PROJECT_DIR/Sources/Graphics/Shaders.metal" "$RESOURCES_DIR/Shaders.metal"

# Copy PNG and graphic assets to Resources
cp "$PROJECT_DIR/Resources/"*.png "$RESOURCES_DIR/" 2>/dev/null || true

# Ad-hoc code signing with stable designated requirement and entitlements
echo "-> Applying code signature with persistent designated requirement..."
codesign --force --deep --sign - \
  -r='designated => identifier "com.antigravity.progressiveblur"' \
  --entitlements "$PROJECT_DIR/Resources/ProgressiveBlur.entitlements" \
  "$APP_BUNDLE"

echo "=== Build Complete! ==="
echo "Application built at: $APP_BUNDLE"
echo "To run, execute: open '$APP_BUNDLE'"
