#!/bin/bash
set -euo pipefail

VERSION="${1:-0.1.0}"
BUILD_DIR="$(pwd)/.build-app"
APP_NAME="ArtWall"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "==> Building ${APP_NAME} v${VERSION}..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Build release binary
swift build -c release

# Create app bundle structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist with version injected
sed "s/0.1.0/${VERSION}/g" Sources/ArtWall/Info.plist > "${APP_BUNDLE}/Contents/Info.plist"

# Ad-hoc sign
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> App bundle created at ${APP_BUNDLE}"

# Create DMG with Applications symlink for drag-to-install
DMG_NAME="${APP_NAME}-${VERSION}-macOS.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
DMG_TEMP="${BUILD_DIR}/${APP_NAME}-temp.dmg"

echo "==> Creating DMG..."
rm -f "${DMG_TEMP}" "${DMG_PATH}"

hdiutil detach "/Volumes/${APP_NAME}" 2>/dev/null || true
hdiutil create -size 50m -fs HFS+ -volname "${APP_NAME}" "${DMG_TEMP}"
hdiutil attach "${DMG_TEMP}" -nobrowse -mountpoint "/Volumes/${APP_NAME}"
cp -R "${APP_BUNDLE}" "/Volumes/${APP_NAME}/"
ln -s /Applications "/Volumes/${APP_NAME}/Applications"
hdiutil detach "/Volumes/${APP_NAME}"
hdiutil convert "${DMG_TEMP}" -format UDZO -o "${DMG_PATH}"
rm -f "${DMG_TEMP}"

echo "==> DMG created at ${DMG_PATH}"

# Create zip for GitHub release
ZIP_NAME="${APP_NAME}-${VERSION}-macOS.zip"
ZIP_PATH="${BUILD_DIR}/${ZIP_NAME}"
cd "${BUILD_DIR}"
zip -ry "${ZIP_NAME}" "${APP_NAME}.app"
cd ..

echo "==> Zip created at ${ZIP_PATH}"
echo "==> Done!"
