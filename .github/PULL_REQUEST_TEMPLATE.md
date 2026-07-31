<!--
The PR title becomes a Conventional Commit on merge (squash), because
scripts/changelog.sh turns commit subjects into the release notes:

    feat(chart): hover tooltip shows the delta
    fix: don't show a stale delta across a sensor gap
    docs: explain the token permissions

Types: feat, fix, perf, refactor, docs, build, ci, test, chore, style.
A `!` before the colon (or a BREAKING CHANGE trailer) triggers a major bump.
-->

## What changed

## Why

## How I verified it

<!-- SwiftUI views aren't unit-testable here, so UI changes need a real run. -->

- [ ] `swift test` passes
- [ ] `./build.sh` succeeds and I ran `Sugarglider.app`
- [ ] Checked the menu-bar item and the dropdown in **both** Light and Dark mode
      (if this touches drawing or colors)
