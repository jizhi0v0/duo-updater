# Duo Updater

A personal macOS menu-bar app that checks installed apps for updates and installs
them with one click — a lightweight, source-respecting take on the
MacUpdater idea, built in pure Swift.

## How it works

Apps are scanned from `/Applications`, `/Applications/Utilities`, and
`~/Applications`, then checked against multiple update sources, in priority order:

1. **Mac App Store** — iTunes lookup API, with storefront/region awareness
   (only native `mac-software` results are trusted; iOS-on-Mac apps are skipped
   to avoid phantom updates).
2. **Sparkle** — the app's own `SUFeedURL` appcast.
3. **Homebrew Cask** — matched by `.app` filename, falling back to bundle id
   (so `pkg`-only casks like AweSun are still found).

It **respects each app's own update channel**:

| Channel | Action |
| --- | --- |
| Sparkle | Native install — download → EdDSA + code-signature + Team ID checks → swap → relaunch |
| Mac App Store | Open the store page (deep link); region-locked apps are flagged |
| Self-updating (Electron/Squirrel) | Open the app and let it update itself |
| Homebrew app cask | `brew install --cask --force` |
| Homebrew `pkg` cask | Download the official package and open the system installer |

## Install safety

- **Never force-quits** a running app. It quits gracefully (so the app can run
  its own save prompts) and aborts the install if it won't quit — your unsaved
  work is never at risk.
- **Major version upgrades** are gated behind a warning (a commercial app may
  need a new license) instead of a one-click button.
- **Defensive re-check** before installing, so a stale list never triggers a
  redundant install.
- **Restart detection**: if an app was updated on disk but is still running an
  older build (compared via LaunchServices), it's surfaced with a Restart action.

## Project layout

- `DuoUpdaterCore/` — Swift Package with the detection engine and install
  pipeline (no UI). Buildable and testable on its own.
- `App/` — the SwiftUI `MenuBarExtra` app, generated with
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `App/project.yml`.

## Build

```sh
# Core package
cd DuoUpdaterCore && swift build && swift test   # some tests hit the network

# App (open in Xcode to iterate)
cd App && xcodegen generate && open DuoUpdater.xcodeproj
```

Requires macOS 14+, Swift 6, and `xcodegen` (`brew install xcodegen`).

### Install

```sh
make install   # build + sign (Developer ID) + deploy to /Applications
```

`make install` builds a Release with a **stable Developer ID signature** and
deploys the single canonical copy to `/Applications/DuoUpdater.app`. This matters
for permissions: macOS keys TCC grants (Full Disk Access — the gate behind the
"access data from other apps" prompt — plus Accessibility, App Management) to the
app's code identity. An ad-hoc signature changes its CDHash every rebuild and
invalidates the grant; the Developer ID identity is stable, so a grant given once
survives all future rebuilds. The script refuses to deploy an ad-hoc binary. After
the first install, add the app to **Full Disk Access** once (System Settings →
Privacy & Security) — the script prints the reminder.

### Public distribution

The source repo can stay private. Public binaries are published to the separate
release-only repo [`jizhi0v0/duo-updater-releases`](https://github.com/jizhi0v0/duo-updater-releases),
which contains notarized `.zip` artifacts and release notes, but no source code.

```sh
# One-time local setup
xcrun notarytool store-credentials "duoupdater-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "RS59HDH7Y3" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"

# Build + notarize + publish a GitHub Release to the public repo
NOTARYTOOL_PROFILE=duoupdater-notary make release
```

Useful overrides:

- `RELEASE_REPO=jizhi0v0/duo-updater-releases` to target a different binary repo
- `TAG=v0.1.0` / `TITLE="DuoUpdater 0.1.0"` to override the generated release name
- `RELEASE_NOTES_FILE=/path/to/notes.md` to publish custom notes
