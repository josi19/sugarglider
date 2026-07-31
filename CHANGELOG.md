# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Entries are generated
from [Conventional Commits](https://www.conventionalcommits.org/) by
`scripts/changelog.sh` — edit commit messages, not this file.

## [0.2.0](https://github.com/josi19/sugarglider/releases/tag/v0.2.0) — 2026-07-31

### Features

- **settings:** configurable stale delay, full-look presets, dotted numbers ([`3140a8e`](https://github.com/josi19/sugarglider/commit/3140a8e567eefb329acf707b057caf53a1b62e97))
- **chart:** extend the range to 3 days and fetch history incrementally ([`65477df`](https://github.com/josi19/sugarglider/commit/65477dfa1e334d4d540ca6661df2ea19147736e1))
- **dropdown:** make the chart range typeable next to the slider ([`a185bef`](https://github.com/josi19/sugarglider/commit/a185bef2f6254a96615a635d47157afcaf4db6f3))
- **dropdown:** show the action buttons as icons and move Quit to the right ([`4a0e539`](https://github.com/josi19/sugarglider/commit/4a0e53983a46c5b386d478d30fb7a00f43e3619a))
- **chart:** make the slider, line shading, and latest-reading dot configurable ([`1fe6946`](https://github.com/josi19/sugarglider/commit/1fe694609649f519110340a07b5baabc101dedb6))
- **ci:** refuse an auto release when the built app wouldn't change ([`a15d1f2`](https://github.com/josi19/sugarglider/commit/a15d1f268929e4845325b1b2b46da2641a92761a))

### Bug fixes

- **chart:** name the weekday once the window spans a day or more ([`981f900`](https://github.com/josi19/sugarglider/commit/981f9006563e32ac1b75b52b09e84e6aa410fdd5))
- **dropdown:** only edit the chart range when the field is clicked ([`fde7846`](https://github.com/josi19/sugarglider/commit/fde784622b6e4fbbb82e3e6905e3f3841a898753))
- **ci:** use the non-deprecated depends_on form in the cask template ([`a0166d2`](https://github.com/josi19/sugarglider/commit/a0166d23fa2420ab74839901372443d98f2afa56))
- **ci:** stage the cask before checking whether it changed ([`04f359e`](https://github.com/josi19/sugarglider/commit/04f359effce57c2c3a7a2e5c1458fd0609f605ba))

### Refactoring

- **chart:** map readings through Layout and split draw per layer ([`1b19ce0`](https://github.com/josi19/sugarglider/commit/1b19ce0072fead442fbe88563f6bf8fd5e149214))
- **api:** decode Nightscout entries with Codable ([`fca8e3b`](https://github.com/josi19/sugarglider/commit/fca8e3b578417bbdada724190bf21df8b17c03bb))

### Documentation

- drop the removed --no-quarantine flag from install instructions ([`02814cf`](https://github.com/josi19/sugarglider/commit/02814cfc489ebc80061091d64b4b251a091d4e04))
- changelog for v0.1.0 [skip ci] ([`ba71640`](https://github.com/josi19/sugarglider/commit/ba71640233036b99c4400de5391cdf9213220069))

### Build & CI

- adopt the ExistentialAny and MemberImportVisibility features ([`7741a18`](https://github.com/josi19/sugarglider/commit/7741a18fe383d94f99e67200a5f0b1cb0e14614a))

**Full changelog**: https://github.com/josi19/sugarglider/compare/v0.1.0...v0.2.0

## [0.1.0](https://github.com/josi19/sugarglider/releases/tag/v0.1.0) — 2026-07-31

### Features

- make polling interval configurable ([`1cfa834`](https://github.com/josi19/sugarglider/commit/1cfa83435f9a47bef084f8d34a49d5262ab0eff1))

### Documentation

- add changelog, contributing guide, security policy and templates ([`bae498f`](https://github.com/josi19/sugarglider/commit/bae498f3ac354f51b4ec7aa3f549da44a538c5e9))

### Build & CI

- bump the actions group with 2 updates (#1) ([`1e183c2`](https://github.com/josi19/sugarglider/commit/1e183c2351511d8fdcc2fa3c7878e4b6ae85d049))
- add CI and tag-driven release pipeline ([`024932a`](https://github.com/josi19/sugarglider/commit/024932a3337d399f8cafa7976de200d3ba5a941f))
- make build.sh configurable for release automation ([`d14b898`](https://github.com/josi19/sugarglider/commit/d14b898971e4eaa45e62a4198a7798d51540768e))

### Other changes

- Add live color preview to Settings, fix theme and preset overwrite ([`ecef23e`](https://github.com/josi19/sugarglider/commit/ecef23ef485fb26cc1519c989e54924e047f6270))
- Initial commit ([`23ef5dc`](https://github.com/josi19/sugarglider/commit/23ef5dcf096ac8fd2e6352236ba5e6011fef340b))
