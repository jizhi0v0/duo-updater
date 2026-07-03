# Changelog

User-facing release notes. The release script (`scripts/publish-release.sh`)
reads the section matching the version being shipped and embeds it in the GitHub
release and the Sparkle appcast, so this file is the single source of truth for
"what's new" — keep each version's prose written for users, not commit-speak.

## 0.3.3

**One-click updates for four more apps.** HBuilderX, JetBrains Toolbox, and Microsoft Edge's Beta and Dev channels now update in place with a single click, instead of only telling you that an update exists. HBuilderX also now reads its version straight from DCloud's own release feed, so it picks up new builds sooner and more reliably.

## 0.3.2

**Self-updating apps stay in their own lane.** A running app that ships its own Sparkle updater is now handed off to that updater — the same courtesy DuoUpdater already gave other self-updating apps — instead of being replaced underneath it, unless you've chosen "Always replace" in Settings.

**Fixes**

- The running-app dot and "Relaunch" badge no longer briefly lose track of an app right after an in-place update, when macOS keeps its process pinned to the temporary swap location for a moment.
- When you restart an app yourself after it updated in the background, the "Relaunch" badge now clears the moment the app comes back up — instead of lingering until the next background check.

## 0.3.1

**Fixes**

- When you restart an app yourself after it updated in the background, the "Relaunch" badge now clears the moment the app comes back up — instead of lingering until the next background check.

## 0.3.0

**See when your apps actually ship.** DuoUpdater now keeps a Release Log: a running timeline of every release the apps you track put out, each stamped with its publish time. Open it from the clock icon at the bottom of the popover.

**Release-habit heatmap.** A new Patterns view charts releases by weekday and hour, so you can see when an app tends to ship — pick any single app for its own pattern and version history, or view all of them together. History is backfilled from each app's update feed, so the heatmap is useful right away instead of starting empty.

**Honest about what it can't time.** Apps that publish an exact release date (Sparkle, GitHub, Alcove) are timed to the minute. Apps that only expose a version number get a clearly-marked "≈" estimated window — bounded by when DuoUpdater last saw the old version and first saw the new one — and never skew the heatmap.

**Fixes**

- ToDesk update checks no longer report an older grayscale build; they now track the version actually offered for download.

## 0.2.0

**Passwordless App Store updates.** Updating Mac App Store apps no longer interrupts you for your password every time. DuoUpdater now installs a small, signed privileged helper (one-time approval) and bundles `mas`, so App Store updates apply directly in the background.

**Cleaner "Restart to finish" lines.** When an app updates itself on disk while it's still running, the pending-restart line now shows the real marketing version on both sides — e.g. `1.8.x (build) → 1.9.0 (build)` instead of a bare build number on the left.

**Fixes**

- Fixed a build issue on Xcode 26.5 (changelog extractor name collision).

## 0.1.9

**Apps that update themselves now clear correctly.** If an app updated through its own updater (for example, Chrome via "About Chrome") while DuoUpdater was busy installing other updates, it could keep showing a stale "update available" row long after it was already current. DuoUpdater now re-checks the moment the installs finish, so the row clears right away instead of lingering.

**"Update All" shows the whole queue.** Every app in an "Update All" run now shows a "Queued" state immediately, instead of leaving the ones further down the list looking idle with a clickable Update button. Clicking Update on an app that's already queued can no longer start a second install of it.
