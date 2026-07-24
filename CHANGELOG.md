# Changelog

User-facing release notes. The release script (`scripts/publish-release.sh`)
reads the section matching the version being shipped and embeds it in the GitHub
release and the Sparkle appcast, so this file is the single source of truth for
"what's new" — keep each version's prose written for users, not commit-speak.

## 0.3.8

**No more beachball while an app is relaunching.** Clicking Update on another app while one was being quit and relaunched could freeze DuoUpdater for a moment — the spinning rainbow cursor, an unresponsive window, a click that seemingly did nothing. Relaunching an app now happens in the background instead of on the interface, so the rest of the list stays live and clickable throughout. The same freeze could show up when opening an app from a row's right-click menu, or when handing an update off to an app's own updater; both are fixed too.

## 0.3.7

**Backups from uninstalled apps are now cleaned up automatically.** DuoUpdater keeps one backup of an app's previous version so an update can be rolled back. Backups for apps you've since uninstalled or moved were never reclaimed and could quietly pile up gigabytes of disk space over time. They're now deleted automatically during the regular update check. Settings shows how much space backups are currently using, with a toggle to turn off the automatic cleanup and a "Clean Up Now" button to run it on demand.

**JetBrains Toolbox apps no longer show a stuck or incorrect "update available."** Version checks for Toolbox-managed apps (IntelliJ, Android Studio, Fleet, Air, and others) now always ask live rather than sometimes falling back to a local cache that could never actually report a new version — it fixes both a status that lingered after Toolbox had already installed the update, and one that never appeared in the first place.

**Claude Desktop's release notes are now shown in DuoUpdater.** Update entries for Claude Desktop now include Anthropic's own per-version changelog instead of a generic notice.

## 0.3.6

**Update All now also relaunches apps that were only waiting on a restart.** If an app had already downloaded its update and just needed a relaunch to finish — Claude, for instance — clicking Update All used to skip it, leaving a stray "Relaunch" button behind. It now relaunches those too, in the same pass, whenever automatic restart-after-update is on.

**App Store updates recover from a receipt hiccup instead of just failing.** Occasionally a Mac App Store update downloads in full but the very last install step trips over a "receipt" error — a transient App Store glitch that a second attempt usually clears. DuoUpdater now retries once automatically. If it still doesn't take, the row offers an "Open App Store" button to finish the update from the App Store's Updates page, instead of leaving a raw error on screen.

**ToDesk update detection fixed.** A change to ToDesk's download page stopped DuoUpdater from reading its latest Mac version, so ToDesk updates went unnoticed. Detection now reads the version reliably again.

## 0.3.5

**App Store updates no longer show a scary error for an app that's already up to date.** If the Mac App Store had quietly updated an app in the background — TestFlight, say — DuoUpdater's row could go stale and, on Update, try to reinstall the version that was already there. macOS's installer rejects that with an alarming red "The upgrade failed", even though nothing was actually wrong. DuoUpdater now confirms an App Store app really is behind before reinstalling, and treats a no-op reinstall as "already up to date" — settling the row quietly instead of showing an error.

## 0.3.4

**App Store updates now ride out network hiccups.** A brief connection drop mid-update — a flaky link, or a proxy resetting the connection — used to fail an App Store update outright with a "could not connect to the server" error. Those updates now retry automatically a few times before giving up, so a momentary blip no longer strands an update that a second attempt lands cleanly. Clicking Update again after a failure also clears the old error immediately, instead of leaving it on screen next to the spinner.

**Apps that update themselves clear from the list faster.** When an app like Chrome finishes updating itself in the background while an App Store update is running, its "update available" row now clears promptly — it no longer lingers until the rest of the queue finishes.

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
