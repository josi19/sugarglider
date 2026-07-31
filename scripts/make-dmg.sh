#!/bin/bash
# Wrap Sugarglider.app in a drag-to-Applications disk image.
#
#   VERSION        names the image and its volume. Default: the app's own
#                  CFBundleShortVersionString.
#   SIGN_IDENTITY  codesign identity for the image itself ("-" = skip). A DMG
#                  carrying a Developer ID app should be signed too, otherwise
#                  Gatekeeper evaluates the container as unsigned.
#
# Deliberately no Finder/AppleScript window styling (background image, icon
# positions): it drives Finder over Apple Events, which is unreliable on a
# headless CI runner. A plain UDZO image installs identically.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Sugarglider.app"
[[ -d "${APP}" ]] || { echo "error: ${APP} not found — run ./build.sh first" >&2; exit 1; }

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
OUT="dist/Sugarglider-${VERSION}.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

echo "==> Staging disk image contents"
# ditto, not cp -R: it preserves the code signature and extended attributes.
ditto "${APP}" "${STAGING}/${APP}"
ln -s /Applications "${STAGING}/Applications"

mkdir -p dist
rm -f "${OUT}"

echo "==> Creating ${OUT}"
hdiutil create \
    -volname "Sugarglider ${VERSION}" \
    -srcfolder "${STAGING}" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    -quiet \
    "${OUT}"

if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    echo "==> Signing ${OUT}"
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${OUT}"
fi

echo "Built ${OUT}"
