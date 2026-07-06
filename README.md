# Sugarglider

**Your Nightscout blood glucose, always visible in the macOS menu bar.**

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

Build from source:

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
swift test      # run the test suite
./build.sh      # release build + assemble Sugarglider.app
```

Contributions are welcome — feel free to open an issue or pull request.

## Disclaimer

Sugarglider is **not a medical device**. It only displays data already
collected by your Nightscout site, can show stale or incorrect values, and
must not be used for treatment decisions. Always rely on your approved
CGM/meter readings and the guidance of your care team.

## License

[MIT](LICENSE)
