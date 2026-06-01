#!/bin/bash
# Build PlayNotch and package it as a runnable .app bundle.
# Usage: ./scripts/build_app.sh [--run]
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PlayNotch"
BUNDLE_ID="com.playnotch.app"
CONFIG="release"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="build/${APP_NAME}.app"

echo "==> Compiling (${CONFIG})..."
swift build -c "${CONFIG}"

echo "==> Assembling ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>PlayNotch needs to control Music and Spotify to show and manage what is playing.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || echo "   (codesign skipped)"

echo "==> Done: ${APP_DIR}"

if [[ "${1:-}" == "--run" ]]; then
    # Kill any running instance first, otherwise `open` reuses the old one.
    pkill -9 -f "${APP_NAME}.app/Contents/MacOS" 2>/dev/null || true
    sleep 1
    echo "==> Launching..."
    open "${APP_DIR}"
fi
