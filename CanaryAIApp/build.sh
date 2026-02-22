#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

VERSION="0.2.4"
APP_NAME="CanaryAI"
DMG_NAME="CanaryAI-${VERSION}.dmg"

# --- Sync version into SettingsView.swift ---
sed -i '' "s/Text(\"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\")\.foregroundStyle(\.secondary)/Text(\"${VERSION}\").foregroundStyle(.secondary)/" Sources/SettingsView.swift

# --- Build ---
echo "Building ${APP_NAME}..."
swift build -c release

# --- Create .app bundle ---
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mkdir -p "${APP_NAME}.app/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# --- Bundle canaryai CLI (makes DMG self-contained) ---
echo "Bundling canaryai CLI..."
PYLIB="${APP_NAME}.app/Contents/Resources/python"
rm -rf "${PYLIB}"
mkdir -p "${PYLIB}"

# Install canaryai package + PyYAML into the bundle (no editable install)
pip3 install --target "${PYLIB}" --quiet "../canaryai" pyyaml

# Launcher script — uses the bundled Python packages
cat > "${APP_NAME}.app/Contents/Resources/canaryai" <<'LAUNCHER'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHONPATH="${DIR}/python" /usr/bin/python3 -c \
  "import sys; sys.argv[0]='canaryai'; from canaryai.cli import main; main()" "$@"
LAUNCHER
chmod +x "${APP_NAME}.app/Contents/Resources/canaryai"

# --- Icon ---
if [ ! -f "AppIcon.icns" ]; then
    echo "Generating icon..."
    swift make_icon.swift
fi
cp "AppIcon.icns" "${APP_NAME}.app/Contents/Resources/AppIcon.icns"

cat > "${APP_NAME}.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.canaryai.app</string>
    <key>CFBundleName</key>
    <string>CanaryAI</string>
    <key>CFBundleDisplayName</key>
    <string>CanaryAI</string>
    <key>CFBundleExecutable</key>
    <string>CanaryAI</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSUserNotificationUsageDescription</key>
    <string>Notify you when suspicious AI agent behavior is detected.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "Built ${APP_NAME}.app"

# --- Ad-hoc sign the app (prevents "damaged" error on macOS without a paid Developer account) ---
echo "Signing ${APP_NAME}.app..."
codesign --force --deep --sign - "${APP_NAME}.app"

# --- Create DMG ---
echo "Creating DMG..."

DMG_STAGING="dmg_staging"
rm -rf "${DMG_STAGING}" "${DMG_NAME}"
mkdir -p "${DMG_STAGING}"

cp -R "${APP_NAME}.app" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
    -volname "CanaryAI" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

rm -rf "${DMG_STAGING}"

echo ""
echo "Done!"
echo "  App: ${APP_NAME}.app"
echo "  DMG: ${DMG_NAME}"
echo ""
echo "Run with:  open ${APP_NAME}.app"
echo "Share:     ${DMG_NAME}"

# --- Strip quarantine so macOS doesn't block unsigned app ---
xattr -dr com.apple.quarantine "${APP_NAME}.app" 2>/dev/null || true
