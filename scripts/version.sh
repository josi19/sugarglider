#!/bin/bash
# Semantic version helper driven by git tags + Conventional Commits.
#
#   scripts/version.sh latest              → newest release tag ("v1.2.0"), empty if none
#   scripts/version.sh previous <tag>      → the tag released before <tag>, empty if none
#   scripts/version.sh next [auto|patch|minor|major]
#                                          → next version *without* the "v" prefix
#   scripts/version.sh app-changed [tag]   → exit 0 if the built app would differ
#                                            from <tag> (default: newest), else 1
#
# "auto" derives the bump from the commits since the newest tag:
#   a `!` marker or a BREAKING CHANGE trailer → major
#   any feat:                                 → minor
#   otherwise                                 → patch
#
# `next` deliberately always answers with a number — deciding whether a release
# is warranted at all is `app-changed`'s job, so the two can be used separately.
set -euo pipefail
cd "$(dirname "$0")/.."

# Tags newest-first. Avoids a pipe so `set -o pipefail` can't trip over SIGPIPE.
all_tags() {
    git tag --list 'v[0-9]*' --sort=-v:refname
}

latest_tag() {
    local tags
    tags="$(all_tags)"
    printf '%s' "${tags%%$'\n'*}"
}

previous_tag() {
    local exclude="$1" tag prev
    # The release <exclude> actually follows: the nearest tag reachable from its
    # parent, so a higher version tagged on a side branch doesn't win. Fails
    # when <exclude> isn't a commit yet (the workflow_dispatch path computes the
    # previous tag *before* creating the new one) — then fall through to the list.
    if prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "${exclude}^" 2>/dev/null)"; then
        printf '%s' "${prev}"
        return 0
    fi
    while IFS= read -r tag; do
        [[ -z "${tag}" || "${tag}" == "${exclude}" ]] && continue
        printf '%s' "${tag}"
        return 0
    done <<< "$(all_tags)"
}

# Highest bump level implied by the commits in <range>.
detect_bump() {
    local range="$1" bump="patch" record subject body
    while IFS= read -r -d $'\x1e' record; do
        record="${record#$'\n'}"
        subject="${record%%$'\x1f'*}"
        body="${record#*$'\x1f'}"
        # `feat!:` / `fix(scope)!:` and the BREAKING CHANGE trailer both mean major.
        if [[ "${subject}" =~ ^[a-zA-Z]+(\([^\)]*\))?! ]] || [[ "${body}" == *"BREAKING CHANGE"* ]]; then
            printf 'major'
            return 0
        fi
        [[ "${subject}" =~ ^feat(\([^\)]*\))?: ]] && bump="minor"
    done < <(git log --no-merges --format='%s%x1f%b%x1e' "${range}")
    printf '%s' "${bump}"
}

# Paths whose contents end up in the shipped bundle. Everything else — CI,
# scripts, docs — can change without altering a single byte of the app.
APP_PATHS=(Sources Resources Package.swift)

case "${1:-}" in
app-changed)
    tag="${2:-$(latest_tag)}"
    if [[ -z "${tag}" ]]; then
        echo "changed (no release tag yet)"
        exit 0
    fi
    # git diff --quiet exits 1 when there *are* differences, hence the inversion.
    if git diff --quiet "${tag}" HEAD -- "${APP_PATHS[@]}"; then
        echo "unchanged since ${tag}"
        exit 1
    fi
    echo "changed since ${tag}"
    exit 0
    ;;
latest)
    latest_tag
    echo
    ;;
previous)
    [[ -n "${2:-}" ]] || { echo "usage: version.sh previous <tag>" >&2; exit 2; }
    previous_tag "$2"
    echo
    ;;
next)
    bump="${2:-auto}"
    tag="$(latest_tag)"

    # No tag yet: the first release is 0.1.0 regardless of the requested bump.
    if [[ -z "${tag}" ]]; then
        echo "0.1.0"
        exit 0
    fi

    current="${tag#v}"
    if [[ ! "${current}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "error: newest tag '${tag}' is not a plain MAJOR.MINOR.PATCH version" >&2
        exit 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"

    [[ "${bump}" == "auto" ]] && bump="$(detect_bump "${tag}..HEAD")"

    case "${bump}" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) echo "error: unknown bump '${bump}'" >&2; exit 2 ;;
    esac
    echo "${major}.${minor}.${patch}"
    ;;
*)
    echo "usage: version.sh {latest|previous <tag>|next [auto|patch|minor|major]|app-changed [tag]}" >&2
    exit 2
    ;;
esac
