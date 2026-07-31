#!/bin/bash
# Build Sugarglider and assemble a menu-bar .app bundle.
#
# Environment overrides (all optional — a bare `./build.sh` still does the right
# thing for local development):
#
#   VERSION        CFBundleShortVersionString. Default: newest git tag without
#                  its leading "v", or 0.0.0-dev outside a tagged checkout.
#   BUILD_NUMBER   CFBundleVersion. Default: commit count on HEAD, which is
#                  monotonically increasing — macOS compares this across updates.
#   SIGN_IDENTITY  codesign identity. Default "-" = ad-hoc. A real Developer ID
#                  additionally enables hardened runtime + secure timestamp,
#                  both of which notarization rejects the app without.
#   UNIVERSAL      1 = arm64 + x86_64 fat binary (what releases ship), 0 = host
#                  arch only (fast local iteration). Default 0.
set -euo pipefail
cd "$(dirname "$0")"

APP="Sugarglider.app"
BIN="Sugarglider"
BUNDLE_ID="dev.nevermind.sugarglider"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
UNIVERSAL="${UNIVERSAL:-0}"

if [[ "${UNIVERSAL}" == "1" ]]; then
    # Two per-arch builds merged with lipo, rather than `swift build --arch a --arch b`:
    # the latter routes through xcbuild and therefore needs a full Xcode, while
    # --triple works on a Command Line Tools-only machine too.
    ARCHS=(arm64 x86_64)
    SLICES=()
    for arch in "${ARCHS[@]}"; do
        echo "==> Compiling ${arch} (release, ${VERSION} build ${BUILD_NUMBER})"
        swift build -c release --triple "${arch}-apple-macosx14.0"
        SLICES+=("$(swift build -c release --triple "${arch}-apple-macosx14.0" --show-bin-path)/${BIN}")
    done
    BIN_PATH=".build/${BIN}-universal"
    echo "==> Merging slices into a universal binary"
    lipo -create -output "${BIN_PATH}" "${SLICES[@]}"
else
    echo "==> Compiling (release, ${VERSION} build ${BUILD_NUMBER})"
    swift build -c release
    BIN_PATH="$(swift build -c release --show-bin-path)/${BIN}"
fi

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN}"
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
    <string>${BUILD_NUMBER}</string>
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

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "==> Ad-hoc signing"
    codesign --force --sign - "${APP}" >/dev/null 2>&1 || echo "    (codesign skipped)"
else
    echo "==> Signing with ${SIGN_IDENTITY}"
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${APP}"
    codesign --verify --strict --verbose=2 "${APP}"
fi

echo "Built ${APP} (${VERSION}, build ${BUILD_NUMBER})"
echo "  Run it:     open ${APP}"
echo "  Install:    cp -r ${APP} /Applications/"
echo "  Login item: System Settings > General > Login Items > +"
