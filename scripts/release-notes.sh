#!/bin/bash
# Compose the body of a GitHub release: generated changelog + install section.
#
#   scripts/release-notes.sh <version> [from-ref] [to-ref]
#
# NOTARIZED=true drops the Gatekeeper workaround, which only applies to
# ad-hoc-signed builds.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
FROM="${2:-}"
TO="${3:-HEAD}"
NOTARIZED="${NOTARIZED:-false}"

[[ -n "${VERSION}" ]] || { echo "usage: release-notes.sh <version> [from-ref] [to-ref]" >&2; exit 2; }

scripts/changelog.sh notes "${VERSION}" "${FROM}" "${TO}"

cat <<EOF

## Install

Download \`Sugarglider-${VERSION}.dmg\` (or the \`.zip\`) below, drag
**Sugarglider.app** into \`/Applications\`, and launch it. Universal binary
(Apple silicon + Intel), macOS 14 (Sonoma) or newer.
EOF

if [[ "${NOTARIZED}" != "true" ]]; then
    cat <<'EOF'

> [!IMPORTANT]
> This build is **ad-hoc signed and not notarized** by Apple, so macOS puts it in
> quarantine on first launch. Either right-click the app → **Open** → **Open**, or
> clear the flag yourself:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/Sugarglider.app
> ```
EOF
fi

cat <<'EOF'

Verify the download against `checksums.txt`:

```sh
shasum -a 256 -c checksums.txt
```

---

Sugarglider is **not a medical device**. It only displays data your Nightscout
site already holds, can show stale or incorrect values, and must not be used for
treatment decisions.
EOF
