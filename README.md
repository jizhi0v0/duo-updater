# Duo Updater

A macOS menu-bar app that finds updates for the apps you already have, and
installs them the way each app expects to be updated.

Most updaters pick one mechanism and push every app through it. This one reads
each app's own release channel — its Sparkle appcast, its App Store listing, its
Homebrew cask, its vendor's release feed — and uses that. When an app ships its
own updater, it hands over instead of fighting it; when it can't do something
safely, it says so rather than guessing. Pure Swift, no telemetry, no server.

<p align="center">
  <img src="assets/menu-bar.png" alt="The Duo Updater menu bar popover, listing apps with an update available: each row shows the installed version, the new version, and either an Update or a Relaunch button." width="420">
</p>

Each row says what you are going from and to, and the button says what will
actually happen: **Update** installs, **Relaunch** means it is already updated on
disk and only the running copy is stale. A green dot marks an app that is
running, so you know before you click whether something is about to be quit and
reopened.

<p align="center">
  <img src="assets/settings.png" alt="Duo Updater's General settings: check interval, post-update behaviour including automatic restart and rollback backups, concurrency, and install routing for App Store and self-updating apps." width="760">
</p>

Most of the settings are about how much autonomy you want to give it — whether
to restart apps for you, whether to keep a rollback backup, and how to route the
two awkward cases: Mac App Store apps, and apps that ship their own updater.

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

## Privacy

There is no telemetry, no analytics SDK, and no server of ours. Every network
request goes straight to the vendor whose app is being checked (or to
`api.github.com` / `formulae.brew.sh`), and carries nothing about you beyond what
that request needs: the app's own version, so a vendor feed can answer for the
right channel.

Three things are worth calling out explicitly, because they involve reading
outside our own container:

- **CleanShot X** — if it is installed, its `activationKey` is read from its
  preferences and used to request the personalised appcast that its own updater
  uses. Without it, CleanShot's feed reports the trial channel. The key is sent
  only to `legit.maketheweb.io`, is never logged, and is excluded from the HTTP
  disk cache.
- **TablePlus** — its `IsReceiveBetaBuild` preference is read so we detect on the
  same channel the app itself is set to.
- **GitHub** — to raise the API rate limit from 60/hour to 5000/hour, a token is
  taken from `GITHUB_TOKEN`/`GH_TOKEN` or, failing that, from `gh auth token`.
  It is sent only to `api.github.com`, and is stripped from any redirect that
  leaves that host.

Credentials you enter yourself (a GitHub token, an Alcove licence) are stored in
the login Keychain as `AfterFirstUnlockThisDeviceOnly` — not synced, not in a
plist. Changelog panes render vendor pages in a `WKWebView` with a non-persistent
data store, so vendor cookies do not survive a relaunch.

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

### Building under your own Developer ID

The build signs with the author's team by default. To build a fork, set your own
team once — the build scripts and `App/project.yml` both read it:

```sh
export DUO_TEAM_ID=YOURTEAMID
make install
```

That is the only change required. The privileged helper and the app pin each
other with code-signing requirements, but each derives the team from **its own
signature** at runtime (`App/Shared/OwnTeamIdentifier.swift`), so the pin follows
whatever identity you built with — no source edit, and no way to end up with an
app and helper that disagree.

The requirement stays "same team as me", never "no team": a build with no
resolvable team identifier (unsigned, or ad-hoc) refuses to connect at all rather
than talking to an unpinned root daemon. If you are hacking on this with an
ad-hoc signature, expect Mac App Store installs to be unavailable — everything
else works.

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

Notarized builds are published as GitHub Releases on this repository, and
`appcast.xml` at the repository root is the Sparkle feed the app updates itself
from. Set `RELEASE_REPO` to publish somewhere else.

The script never commits into your working tree: it makes a shallow throwaway
clone to update the appcast, so a release does not depend on which branch you
have checked out or what is uncommitted beside it.

```sh
# One-time local setup
xcrun notarytool store-credentials "duoupdater-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"

# Build + notarize + publish a GitHub Release to the public repo
NOTARYTOOL_PROFILE=duoupdater-notary make release
```

Useful overrides:

- `RELEASE_REPO=owner/repo` to publish the release and appcast elsewhere
- `TAG=v0.1.0` / `TITLE="DuoUpdater 0.1.0"` to override the generated release name
- `RELEASE_NOTES_FILE=/path/to/notes.md` to publish custom notes

## Third-party components

| Component | Where | Licence |
| --- | --- | --- |
| [Sparkle](https://github.com/sparkle-project/Sparkle) 2.9.3 | SPM dependency, used to install other apps' Sparkle updates and to update this app | MIT |
| [`mas`](https://github.com/mas-cli/mas) | `App/Resources/mas`, a prebuilt universal binary invoked for Mac App Store installs | MIT |
| PermissionFlow | `App/Sources/Vendor/PermissionFlow/` (vendored source) | MIT — see the `LICENSE` and `NOTICE.md` in that directory |

`App/Resources/mas` is checked in as a binary because it has to be embedded and
re-signed with the app's own identity for the privileged helper to invoke it.
If you would rather not trust a committed binary, build `mas` from source and
replace the file — `scripts/install.sh` re-signs whatever is there.
