#!/bin/bash
# Submit an artifact to Apple's notary service and wait for the verdict.
#
#   scripts/notarize.sh <file> [--staple]
#
# Requires APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD (an app-specific
# password from appleid.apple.com, not the account password).
#
# A .zip can be submitted but not stapled — the ticket goes onto the .app
# *inside* it, so callers notarize the zip, staple the app, then re-zip. A .dmg
# is both submitted and stapled directly, hence the flag.
set -euo pipefail

FILE="${1:-}"
STAPLE="${2:-}"
[[ -n "${FILE}" && -e "${FILE}" ]] || { echo "usage: notarize.sh <file> [--staple]" >&2; exit 2; }

: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"

echo "==> Notarizing ${FILE}"
# Capture rather than stream, so the submission id is still available to fetch
# the rejection log — "Invalid" is the one verdict where the detail matters.
if output="$(xcrun notarytool submit "${FILE}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait \
    --timeout 30m 2>&1)"; then
    printf '%s\n' "${output}"
else
    printf '%s\n' "${output}" >&2
    submission="$(printf '%s\n' "${output}" | awk '/^ *id: /{print $2; exit}')"
    if [[ -n "${submission}" ]]; then
        echo "==> Notarization failed; fetching log for ${submission}" >&2
        xcrun notarytool log "${submission}" \
            --apple-id "${APPLE_ID}" \
            --team-id "${APPLE_TEAM_ID}" \
            --password "${APPLE_APP_PASSWORD}" >&2 || true
    fi
    exit 1
fi

if [[ "${STAPLE}" == "--staple" ]]; then
    echo "==> Stapling ${FILE}"
    xcrun stapler staple "${FILE}"
    xcrun stapler validate "${FILE}"
fi
