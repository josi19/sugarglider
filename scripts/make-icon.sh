#!/bin/bash
# Compile Resources/AppIcon.icon (an Icon Composer document) into the four
# artifacts the app bundle ships, all committed next to it:
#
#   Resources/Assets.car        the real icon — an image stack carrying separate
#                               Aqua / DarkAqua / tintable renditions, which is
#                               what makes macOS swap the icon with the system
#                               appearance. Referenced by CFBundleIconName.
#   Resources/AppIcon.icns      single-appearance fallback for anything that
#                               predates the catalog. Referenced by CFBundleIconFile.
#   Resources/AppIcon-Light.png the same artwork as flat images, for the About
#   Resources/AppIcon-Dark.png  tab — the catalog's variants are reachable only
#                               through the system icon services, never through
#                               NSImage(named:). See the icon bullet in CLAUDE.md.
#
# Run this only when the artwork changes — `build.sh` just copies the results.
# That split is deliberate: actool ships only with a full Xcode (26+ for .icon
# documents), while build.sh is meant to work on a Command Line Tools-only
# machine, and CI's pinned macos-15 runners have neither. Committing what actool
# produced keeps every build reproducible without that dependency.
set -euo pipefail
cd "$(dirname "$0")/.."

ICON="Resources/AppIcon.icon"
[[ -d "${ICON}" ]] || { echo "error: ${ICON} not found" >&2; exit 1; }

# xcrun resolves actool only when a full Xcode is *selected*; having it merely
# installed (the common case — `xcode-select -p` still points at the CLT) is
# enough for us, so fall back to looking for it directly.
ACTOOL="$(xcrun --find actool 2>/dev/null || true)"
if [[ -z "${ACTOOL}" ]]; then
    for candidate in /Applications/Xcode*.app; do
        [[ -x "${candidate}/Contents/Developer/usr/bin/actool" ]] || continue
        ACTOOL="${candidate}/Contents/Developer/usr/bin/actool"
        export DEVELOPER_DIR="${candidate}/Contents/Developer"
        break
    done
fi
[[ -n "${ACTOOL}" ]] || {
    echo "error: actool not found. Compiling an Icon Composer document needs a" >&2
    echo "       full Xcode 26 or newer; the Command Line Tools don't ship it." >&2
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# $1 = .icon document, $2 = output directory
compile_icon() {
    mkdir -p "$2"   # actool writes into the directory but won't create it
    # ...and it fails with "no such file" on a relative .icon path, however
    # valid, so hand it an absolute one.
    local document="$1"
    [[ "${document}" == /* ]] || document="${PWD}/${document}"
    "${ACTOOL}" "${document}" \
        --compile "$2" \
        --app-icon AppIcon \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --output-partial-info-plist "$2/partial.plist" \
        --errors --warnings >/dev/null
    [[ -f "$2/Assets.car" && -f "$2/AppIcon.icns" ]] \
        || { echo "error: actool produced no usable output for $1" >&2; exit 1; }
}

echo "==> Compiling ${ICON} with ${ACTOOL}"
compile_icon "${ICON}" "${TMP}/light"
cp "${TMP}/light/Assets.car" "${TMP}/light/AppIcon.icns" Resources/

# The About tab's two PNGs come out of actool as well rather than out of Icon
# Composer's export panel: that panel emits iOS/watchOS artwork only — flat and
# full-bleed — because on macOS the squircle, padding and shadow are applied
# when the icon is rendered, not when it's drawn. Compiling gives us the real
# thing. There's no flag for "render the dark appearance", so the dark pass goes
# through a copy of the document with its dark specializations promoted to
# defaults; the resulting .icns then holds the dark artwork in macOS form.
echo "==> Compiling a dark-appearance pass"
cp -R "${ICON}" "${TMP}/AppIcon.icon"
python3 - "${TMP}/AppIcon.icon/icon.json" <<'PY'
import json, sys

def promote(node):
    """Replace every fill-specializations list with its dark entry alone."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "fill-specializations" and isinstance(value, list):
                dark = [s for s in value if isinstance(s, dict) and s.get("appearance") == "dark"]
                if dark:
                    promoted = dict(dark[0])
                    promoted.pop("appearance", None)
                    node[key] = [promoted]
            else:
                promote(value)
    elif isinstance(node, list):
        for value in node:
            promote(value)

path = sys.argv[1]
document = json.load(open(path))
promote(document)
json.dump(document, open(path, "w"), indent=2)
PY
compile_icon "${TMP}/AppIcon.icon" "${TMP}/dark"

# 128@2x = 256px, twice what the About tab's 64pt view needs on a Retina display
# and the largest size actool puts in the fallback .icns.
for pass in light dark; do
    iconutil -c iconset "${TMP}/${pass}/AppIcon.icns" -o "${TMP}/${pass}.iconset"
    variant="$(tr '[:lower:]' '[:upper:]' <<<"${pass:0:1}")${pass:1}"
    cp "${TMP}/${pass}.iconset/icon_128x128@2x.png" "Resources/AppIcon-${variant}.png"
done

for artifact in Assets.car AppIcon.icns AppIcon-Light.png AppIcon-Dark.png; do
    echo "    Resources/${artifact} ($(du -h "Resources/${artifact}" | cut -f1))"
done

echo
echo "Info.plist keys build.sh writes for these (kept in sync by hand):"
sed -n 's/^\t*//p' "${TMP}/light/partial.plist" | grep -A1 'CFBundleIcon' || true
