# Contributing to Sugarglider

Thanks for taking a look. Issues and pull requests are both welcome.

Sugarglider intentionally stays small: a native menu-bar app in pure Swift +
SwiftUI, **zero third-party dependencies**, talking to nothing but the
Nightscout site the user configures. Changes that preserve those properties are
the easiest ones to merge.

## Getting set up

```sh
git clone https://github.com/josi19/sugarglider.git
cd sugarglider
swift build              # debug build
swift test               # test suite (Swift Testing)
./build.sh               # release build + assemble Sugarglider.app
open Sugarglider.app
```

Requirements: **macOS 14+** and **Xcode 16 or newer**. The Command Line Tools
alone are enough to compile the app, but *not* to run `swift test` — the
`Testing` module ships with Xcode, so a CLT-only machine fails with
`no such module 'Testing'`. Either install Xcode or let CI run the tests for you.

To relaunch after a rebuild, quit the running copy first:

```sh
osascript -e 'quit app "Sugarglider"' ; ./build.sh && open Sugarglider.app
```

## Architecture in one paragraph

SwiftUI app lifecycle (`MenuBarExtra` + `Settings` scenes), no
`NSApplicationDelegate`. `AppSettings` holds persisted settings, `ReadingStore`
holds live state, `Nightscout` is a stateless API client, `ChartMath` is pure
chart geometry, and the rest are views. Logic lives in the first four so it can
be unit-tested — **SwiftUI view bodies are not unit-testable here**, which is
why view code should stay thin and declarative. `CLAUDE.md` documents the
non-obvious conventions (why every setting is a stored property with a `didSet`,
why the theme override needs two different mechanisms, why glucose is always
stored in mg/dL); read it before changing those areas.

## Commit messages

The changelog and the version number are both generated from commit subjects, so
this repo uses [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(chart): show the delta in the hover tooltip
fix: don't render a stale delta across a sensor gap
docs: explain which Nightscout token role is needed
```

| Type                  | Shows up as    | Version bump |
| --------------------- | -------------- | ------------ |
| `feat`                | Features       | minor        |
| `fix`                 | Bug fixes      | patch        |
| `perf`                | Performance    | patch        |
| `refactor`            | Refactoring    | patch        |
| `docs`                | Documentation  | patch        |
| `build`, `ci`         | Build & CI     | patch        |
| `test`                | Tests          | patch        |
| `chore`, `style`      | Chores         | patch        |
| anything else         | Other changes  | patch        |

Append `!` before the colon (`feat!:`) or add a `BREAKING CHANGE:` trailer for a
major bump. Commits that don't match the pattern still appear in the release
notes under "Other changes" — nothing gets silently dropped — they just don't
influence the version.

Pull requests are squash-merged, so it's the **PR title** that ends up in the
changelog. Make that one count.

## Before you open a PR

- `swift test` passes.
- `./build.sh` succeeds and you've actually run the app.
- Anything touching drawing or colors was checked in **both** Light and Dark
  mode, and with both mmol/L and mg/dL if it touches values.
- Shell scripts pass `shellcheck build.sh scripts/*.sh`.

CI runs the same checks on macOS, plus a universal (arm64 + x86_64) release
build, so a PR that builds only on your architecture will be caught.

## A note on health data

This app displays medical data. Two things follow from that:

- **Never commit real readings, site URLs or tokens** — not in tests, fixtures,
  screenshots or issue reports. Tests use synthetic data
  (`ChartMath.sampleReadings`) and a loopback HTTP server for exactly this reason.
- **Correctness beats cleverness.** A wrong or silently stale number on screen is
  worse than a visibly missing one. This is why stale readings get a `⚠`, why
  sensor gaps break the chart line instead of interpolating across them, and why
  the delta hides itself when the previous reading is too old. Keep that bias.

## Releasing

Maintainers only — see [Releasing](README.md#releasing).
