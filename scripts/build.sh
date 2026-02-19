#!/bin/bash
set -euo pipefail

VERSION="${1:-0.1.0}"
BUILD_DIR="$(pwd)/.build-app"
APP_NAME="ArtWall"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Usebits corp (Q9D9H424KQ)}"

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

# Copy resources
cp Sources/ArtWall/Resources/ArtWall.icns "${APP_BUNDLE}/Contents/Resources/"
cp Sources/ArtWall/Resources/MenuBarIcon.png "${APP_BUNDLE}/Contents/Resources/"
cp Sources/ArtWall/Resources/MenuBarIcon@2x.png "${APP_BUNDLE}/Contents/Resources/"

# Code sign
codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

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
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Zip created at ${ZIP_PATH}"

# Notarize the DMG
if [ -n "${NOTARY_PASSWORD:-}" ]; then
    NOTARY_ARGS="--apple-id ${APPLE_ID} --team-id ${APPLE_TEAM_ID} --password ${NOTARY_PASSWORD}"

    echo "==> Notarizing DMG..."
    DMG_RESULT=$(xcrun notarytool submit "${DMG_PATH}" ${NOTARY_ARGS} --wait 2>&1) || true
    echo "${DMG_RESULT}"
    DMG_ID=$(echo "${DMG_RESULT}" | grep "id:" | head -1 | awk '{print $2}')
    if echo "${DMG_RESULT}" | grep -q "status: Invalid"; then
        echo "==> Notarization failed, fetching log..."
        xcrun notarytool log "${DMG_ID}" ${NOTARY_ARGS} || true
        exit 1
    fi
    xcrun stapler staple "${DMG_PATH}"
    echo "==> DMG notarized and stapled"
else
    echo "==> NOTARY_PASSWORD not set, skipping notarization"
fi

echo "==> Done!"
