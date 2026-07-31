# Sugarglider

**Your Nightscout blood glucose, always visible in the macOS menu bar.**

[![CI](https://github.com/josi19/sugarglider/actions/workflows/ci.yml/badge.svg)](https://github.com/josi19/sugarglider/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/josi19/sugarglider?sort=semver&label=release)](https://github.com/josi19/sugarglider/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/josi19/sugarglider/total?label=downloads)](https://github.com/josi19/sugarglider/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Sugarglider is a tiny native menu-bar app for [Nightscout](https://nightscout.github.io)
users. It shows your latest reading, its trend arrow, and how fresh it is — e.g.
`5.6 ↗` — and opens a chart of recent history when clicked. No Dock icon, no
window clutter, no third-party services: just your Mac talking to your own
Nightscout site.

<!-- TODO: add a screenshot before publishing, e.g.
![Sugarglider](docs/screenshot.png)
(capture with demo data, not real readings) -->

## Features

- **Glance value in the menu bar** — current glucose with trend arrow, updated
  on a configurable interval (3–300s, default 60s). Optionally shows the delta
  to the previous reading (`5.6 ↗ (+0.1)`). A `⚠` appears when the newest
  reading is older than ~11 minutes (two missed sensor cycles).
- **Chart dropdown** — click the item for a smoothed chart of the last
  2–48 hours, adjustable with a slider (remembered across launches). Value
  gridlines, a dashed band marking your target range, and hover to inspect any
  point's exact value and time. Sensor dropouts (gaps > 15 min) break the line
  instead of interpolating across them.
- **Zone colors** — the line is colored by zone (very low / below / in range /
  above / very high), either switching at each threshold or blending smoothly.
  Every color is independently pickable with opacity, palettes can be saved as
  named presets, and the monochrome defaults follow Light/Dark mode.
- **Tunable chart details** — the shading under the line can be switched off or
  given its own color, the dot on the latest reading has adjustable size and
  halo (either down to zero to hide it) and can keep its zone color or take a
  fixed one, and the range slider's track color is yours to pick. A live preview
  in Settings shows every change as you make it.
- **mmol/L or mg/dL** — switch the display unit any time; values are stored in
  mg/dL (Nightscout's native unit), so nothing drifts on conversion.
- **Configurable thresholds** — target range and very-low/very-high bounds,
  edited in your display unit.
- **Light/Dark override** — follow the system or force a theme, applied to the
  dropdown and Settings window.
- **Native and lightweight** — pure Swift + SwiftUI, zero dependencies, a
  ~350 KB binary, and one small HTTP request per refresh interval in the
  background.

## Requirements

- macOS 14 (Sonoma) or newer
- A reachable [Nightscout](https://nightscout.github.io) site
- To build: Xcode 16+ or the Xcode Command Line Tools (Swift 6)

## Install

### Download

Grab the latest `.dmg` (or `.zip`) from the
[releases page](https://github.com/josi19/sugarglider/releases/latest) and drag
**Sugarglider.app** into `/Applications`. The build is a universal binary, so it
runs natively on both Apple silicon and Intel.

Releases are ad-hoc signed rather than notarized by Apple, so macOS quarantines
the app on first launch. Either right-click it → **Open** → **Open**, or clear
the flag yourself:

```sh
xattr -dr com.apple.quarantine /Applications/Sugarglider.app
```

Every release ships a `checksums.txt`; verify your download with
`shasum -a 256 -c checksums.txt`.

### Homebrew

```sh
brew install --cask josi19/tap/sugarglider
xattr -dr com.apple.quarantine /Applications/Sugarglider.app
```

The second line is the same quarantine caveat as above. Homebrew 6 dropped the
`--no-quarantine` flag, so clearing the attribute afterwards is the way.

### Build from source

```sh
git clone https://github.com/josi19/sugarglider.git
cd sugarglider
./build.sh
cp -r Sugarglider.app /Applications/
open /Applications/Sugarglider.app
```

To launch it automatically at login: **System Settings → General → Login
Items** → add Sugarglider.

## Setup

The menu-bar item shows `CGM ⚙` until configured. Click it, then
**Settings…** (or press ⌘, while the dropdown is open) and enter:

- **Nightscout URL** — e.g. `https://your-site.nightscout.app`
- **Access token** — create one in Nightscout under *Admin Tools → Subjects*
  with a read role (`readable`). Leave it empty if your site allows
  unauthenticated reads. The field masks the token whenever it isn't focused.

Settings apply immediately — there is no Save button — and the General tab
shows a live **Connected** / failure status for the URL and token as you type.
The Colors and Glucose tabs hold the palette and threshold options.

## Trend arrows

| Arrow | Nightscout direction |
|-------|----------------------|
| ↑↑    | DoubleUp             |
| ↑     | SingleUp             |
| ↗     | FortyFiveUp          |
| →     | Flat                 |
| ↘     | FortyFiveDown        |
| ↓     | SingleDown           |
| ↓↓    | DoubleDown           |

## How it works

Sugarglider polls `GET {url}/api/v1/entries/sgv.json?count=2` on the refresh
interval set in Settings → General (3–300s, default 60s; the second entry
supplies the delta), with generous timer tolerance so macOS can coalesce
wakeups for minimal energy use. Chart history (`count=600`, ≈ 48 h) is fetched
only when the dropdown opens, and at most once per minute regardless of the
refresh interval — moving the range slider re-slices cached data without a new
request.

Your data never goes anywhere else: the app talks exclusively to the
Nightscout URL you configure, and there is no telemetry, analytics, or other
third-party traffic. The URL and token are stored in the app's user defaults
on your Mac.

## Development

```sh
swift build     # debug build
swift test      # run the test suite (needs Xcode, not just the CLT)
./build.sh      # release build + assemble Sugarglider.app
```

CI builds and tests every push and pull request on macOS, including a universal
(arm64 + x86_64) release build, and lints the shell scripts and workflows.

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the setup,
the architecture in a paragraph, and the commit-message convention (the changelog
and version numbers are generated from it). Past releases are in
[CHANGELOG.md](CHANGELOG.md).

## Releasing

Maintainers only. Two ways in, both landing in the same
[release workflow](.github/workflows/release.yml):

```sh
# Let the workflow pick the version from the Conventional Commits since the
# last tag, then tag, build and publish:
gh workflow run release.yml -f bump=auto

# …or force a level, or rehearse without publishing anything:
gh workflow run release.yml -f bump=minor
gh workflow run release.yml -f bump=auto -f dry_run=true

# …or just push a tag yourself:
git tag v1.2.0 && git push origin v1.2.0
```

The workflow runs the tests, builds a universal signed bundle, packages a `.zip`,
a `.dmg` and `checksums.txt`, generates the release notes from the commit log,
publishes the GitHub release, and commits the updated `CHANGELOG.md` back to
`main`.

Nothing releases on its own: pushing to `main` only runs CI. `bump=auto`
additionally refuses when nothing under `Sources/`, `Resources/` or
`Package.swift` has changed since the last tag — a run of CI-only or docs-only
commits would otherwise ship a byte-identical app under a new number. Pass an
explicit `bump=patch` (or push a tag) when you want that anyway.

Everything it does is a script you can run locally, which is the point — a
release should never be a black box:

```sh
scripts/version.sh next auto            # what would the next version be?
scripts/version.sh app-changed          # …and would the app actually differ?
scripts/release-notes.sh 1.2.0          # what would the notes say?
VERSION=1.2.0 UNIVERSAL=1 ./build.sh    # the exact bundle CI produces
VERSION=1.2.0 scripts/make-dmg.sh
```

### Optional repository configuration

Everything below is optional — without it releases still build and publish,
just ad-hoc signed and without the Homebrew cask.

| Secret / variable            | Type     | Effect when set                                         |
| ---------------------------- | -------- | ------------------------------------------------------- |
| `MACOS_CERTIFICATE_P12`      | secret   | Developer ID cert (base64 `.p12`); enables real signing |
| `MACOS_CERTIFICATE_PASSWORD` | secret   | Password for that `.p12`                                |
| `MACOS_SIGN_IDENTITY`        | secret   | e.g. `Developer ID Application: Name (TEAMID)`          |
| `APPLE_ID`                   | secret   | Apple ID; enables notarization and stapling             |
| `APPLE_TEAM_ID`              | secret   | Team ID for notarization                                |
| `APPLE_APP_PASSWORD`         | secret   | App-specific password for notarization                  |
| `HOMEBREW_TAP_TOKEN`         | secret   | PAT with `contents:write` on the tap; updates the cask  |
| `HOMEBREW_TAP_REPO`          | variable | Tap repo, defaults to `<owner>/homebrew-tap`            |

Base64-encode the certificate with
`base64 -i cert.p12 | pbcopy`. Once the Apple secrets exist the workflow signs
and notarizes automatically, and the Gatekeeper warning disappears from the
release notes.

## Disclaimer

Sugarglider is **not a medical device**. It only displays data already
collected by your Nightscout site, can show stale or incorrect values, and
must not be used for treatment decisions. Always rely on your approved
CGM/meter readings and the guidance of your care team.

## License

[MIT](LICENSE)
