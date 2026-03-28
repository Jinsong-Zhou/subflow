#!/bin/bash
set -euo pipefail

# === Configuration ===
APP_NAME="SubFlow"
SCHEME="SubFlow"
CONFIGURATION="Release"
DERIVED_DATA="build/DerivedData"
DMG_DIR="build/dmg"
OUTPUT_DIR="build"

# === Clean ===
rm -rf "$DERIVED_DATA" "$DMG_DIR"
mkdir -p "$DMG_DIR" "$OUTPUT_DIR"

# === Generate Xcode project ===
echo "==> Generating Xcode project with XcodeGen..."
xcodegen generate

# === Build ===
echo "==> Building $APP_NAME ($CONFIGURATION)..."
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  STRIP_INSTALLED_PRODUCT=YES \
  build

# === Locate .app ===
APP_PATH=$(find "$DERIVED_DATA" -name "${APP_NAME}.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
  echo "ERROR: ${APP_NAME}.app not found in $DERIVED_DATA"
  exit 1
fi
echo "==> Found app: $APP_PATH"

# === Read version from Info.plist ===
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

# === Prepare DMG staging ===
echo "==> Preparing DMG contents..."
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# === Create DMG ===
echo "==> Creating DMG: $DMG_NAME..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Done: $DMG_PATH"

# Output for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "DMG_PATH=$DMG_PATH" >> "$GITHUB_OUTPUT"
  echo "DMG_NAME=$DMG_NAME" >> "$GITHUB_OUTPUT"
fi
