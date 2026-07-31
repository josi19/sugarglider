#!/bin/bash
# Render Conventional Commits into changelog markdown.
#
#   scripts/changelog.sh notes   <version> [from-ref] [to-ref]  → markdown on stdout
#   scripts/changelog.sh prepend <version> [from-ref] [to-ref]  → insert into CHANGELOG.md
#
# from-ref defaults to the newest tag that isn't <to-ref> itself; to-ref to HEAD.
# Commits that don't parse as Conventional Commits aren't dropped — they land in
# "Other changes", so nothing silently disappears from a release's notes.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
VERSION="${2:-}"
FROM="${3:-}"
TO="${4:-HEAD}"

[[ -n "${MODE}" && -n "${VERSION}" ]] || {
    echo "usage: changelog.sh {notes|prepend} <version> [from-ref] [to-ref]" >&2
    exit 2
}

if [[ -z "${FROM}" ]]; then
    FROM="$(scripts/version.sh previous "v${VERSION}")"
fi

if [[ -n "${FROM}" ]]; then
    RANGE="${FROM}..${TO}"
else
    RANGE="${TO}" # first release: everything down to the root commit
fi

# Prefer the CI-provided repo identity; fall back to the origin remote locally.
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    REPO_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
else
    REPO_URL="$(git remote get-url origin 2>/dev/null || echo '')"
    REPO_URL="${REPO_URL%.git}"
    REPO_URL="$(printf '%s' "${REPO_URL}" | sed \
        -e 's|^git@github\.com:|https://github.com/|' \
        -e 's|^ssh://git@github\.com/|https://github.com/|')"
fi

DATE="$(git log -1 --format=%cd --date=short "${TO}" 2>/dev/null || date -u +%Y-%m-%d)"

# Section order is the output order. Keyed by file name in a temp dir because
# macOS ships bash 3.2, which has no associative arrays.
SECTIONS=(breaking feat fix perf refactor docs build test chore other)
title_for() {
    case "$1" in
    breaking) echo "⚠️ Breaking changes" ;;
    feat)     echo "Features" ;;
    fix)      echo "Bug fixes" ;;
    perf)     echo "Performance" ;;
    refactor) echo "Refactoring" ;;
    docs)     echo "Documentation" ;;
    build)    echo "Build & CI" ;;
    test)     echo "Tests" ;;
    chore)    echo "Chores" ;;
    *)        echo "Other changes" ;;
    esac
}

# Conventional Commit type → section.
section_for() {
    case "$1" in
    feat)            echo feat ;;
    fix)             echo fix ;;
    perf)            echo perf ;;
    refactor)        echo refactor ;;
    docs)            echo docs ;;
    build|ci)        echo build ;;
    test)            echo test ;;
    chore|style)     echo chore ;;
    *)               echo other ;;
    esac
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

count=0
while IFS= read -r -d $'\x1e' record; do
    record="${record#$'\n'}"
    sha="${record%%$'\x1f'*}"
    rest="${record#*$'\x1f'}"
    subject="${rest%%$'\x1f'*}"
    body="${rest#*$'\x1f'}"
    [[ -n "${sha}" ]] || continue

    if [[ "${subject}" =~ ^([a-zA-Z]+)(\(([^\)]+)\))?(!)?:[[:space:]]*(.+)$ ]]; then
        type="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
        scope="${BASH_REMATCH[3]}"
        bang="${BASH_REMATCH[4]}"
        desc="${BASH_REMATCH[5]}"
    else
        type="other"
        scope=""
        bang=""
        desc="${subject}"
    fi

    if [[ -n "${bang}" || "${body}" == *"BREAKING CHANGE"* ]]; then
        section="breaking"
    else
        section="$(section_for "${type}")"
    fi

    entry="- "
    [[ -n "${scope}" ]] && entry+="**${scope}:** "
    entry+="${desc}"
    [[ -n "${REPO_URL}" ]] && entry+=" ([\`${sha:0:7}\`](${REPO_URL}/commit/${sha}))"

    printf '%s\n' "${entry}" >> "${WORK}/${section}"
    count=$((count + 1))
done < <(git log --no-merges --format='%H%x1f%s%x1f%b%x1e' "${RANGE}")

render() {
    printf '## [%s](%s) — %s\n' "${VERSION}" "${REPO_URL}/releases/tag/v${VERSION}" "${DATE}"

    if [[ "${count}" -eq 0 ]]; then
        printf '\nNo code changes since %s.\n' "${FROM:-the initial commit}"
    else
        for section in "${SECTIONS[@]}"; do
            [[ -s "${WORK}/${section}" ]] || continue
            printf '\n### %s\n\n' "$(title_for "${section}")"
            cat "${WORK}/${section}"
        done
    fi

    if [[ -n "${FROM}" && -n "${REPO_URL}" ]]; then
        printf '\n**Full changelog**: %s/compare/%s...v%s\n' "${REPO_URL}" "${FROM}" "${VERSION}"
    fi
}

case "${MODE}" in
notes)
    render
    ;;
prepend)
    NEW="$(mktemp)"
    # Quoted delimiter: the preamble is literal markdown, nothing expands.
    cat > "${NEW}" <<'HEADER'
# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Entries are generated
from [Conventional Commits](https://www.conventionalcommits.org/) by
`scripts/changelog.sh` — edit commit messages, not this file.

HEADER
    render >> "${NEW}"

    if [[ -f CHANGELOG.md ]]; then
        # Keep everything below the existing preamble (i.e. from the first
        # release heading onwards) so older entries survive verbatim.
        first_release="$(grep -n '^## ' CHANGELOG.md | head -n1 | cut -d: -f1 || true)"
        if [[ -n "${first_release}" ]]; then
            printf '\n' >> "${NEW}"
            tail -n "+${first_release}" CHANGELOG.md >> "${NEW}"
        fi
    fi

    mv "${NEW}" CHANGELOG.md
    echo "Wrote CHANGELOG.md (${VERSION}, ${count} commits)"
    ;;
*)
    echo "usage: changelog.sh {notes|prepend} <version> [from-ref] [to-ref]" >&2
    exit 2
    ;;
esac
