#!/bin/bash
# Build Sugarglider and assemble a menu-bar .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP="Sugarglider.app"
BIN="Sugarglider"
BUNDLE_ID="dev.nevermind.sugarglider"
VERSION="1.0"

echo "==> Compiling (release)"
swift build -c release

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp ".build/release/${BIN}" "${APP}/Contents/MacOS/${BIN}"
cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

echo "==> Stripping symbols"
strip -x "${APP}/Contents/MacOS/${BIN}"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${BIN}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Sugarglider</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.healthcare-fitness</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 nevermind.dev</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --sign - "${APP}" >/dev/null 2>&1 || echo "    (codesign skipped)"

echo "Built ${APP}"
echo "  Run it:     open ${APP}"
echo "  Install:    cp -r ${APP} /Applications/"
echo "  Login item: System Settings > General > Login Items > +"
