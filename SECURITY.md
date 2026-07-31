# Security policy

## Supported versions

Only the latest release gets fixes. Please reproduce on the newest version
before reporting.

## Reporting a vulnerability

Report privately through GitHub's
[security advisory form](https://github.com/josi19/sugarglider/security/advisories/new)
— **not** a public issue. Include what you did, what happened, and the version
and macOS version you saw it on. Expect a first response within a week.

Please don't include a real Nightscout URL or access token in the report; a
redacted description or a token you've already revoked is enough.

## What's in scope

Sugarglider stores a Nightscout **URL and access token** in the app's user
defaults and sends that token to that one host over HTTPS. There is no
telemetry, no analytics, and no other network traffic. Things worth reporting:

- The token leaking anywhere it shouldn't be — logs, crash reports, error
  messages shown in the UI, a request to a host other than the configured one.
- Requests going somewhere other than the configured Nightscout URL.
- Anything that lets a local process or another app read the stored credentials
  beyond what standard `UserDefaults` permissions already imply (see below).
- Tampering with the released `.app`, `.dmg` or the release pipeline itself.

## Known and accepted

- **The token lives in `UserDefaults`, not the Keychain.** It is readable by
  anything running as your user account. This is a deliberate trade-off for a
  read-only token to your own site; moving it to the Keychain is a reasonable
  feature request, not a vulnerability report.
- **Releases may be ad-hoc signed rather than notarized**, depending on whether
  the maintainer's Developer ID is configured. Release notes say which. Verify
  downloads against the published `checksums.txt` either way.

## Not a medical device

Sugarglider only displays data your Nightscout site already holds. It can show
stale or incorrect values and must not be used for treatment decisions. Bugs
that cause a wrong or misleadingly stale value to be displayed are taken
seriously — please report them as normal issues, and say so clearly in the title.
