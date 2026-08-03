# Changelog

User-facing release notes. The release script (`scripts/publish-release.sh`)
reads the section matching the version being shipped and embeds it in the GitHub
release and the Sparkle appcast, so this file is the single source of truth for
"what's new" — keep each version's prose written for users, not commit-speak.

## 0.3.12

**An installer you've already downloaded no longer downloads again.** Some apps update through an installer package that macOS opens for you to confirm. If you closed that window without finishing — or quit DuoUpdater and came back — the row went back to offering "Update", and taking it fetched the whole package a second time. ToDesk's is 375 MB. The download was on your disk the entire time; nothing was pointing at it. Those rows now offer "Install" instead, which just re-opens the file you already have. If the installer window is still open it comes forward rather than opening a second one, and the offer stands until either the download is gone or a newer version comes out — at which point the old package would be the wrong one, so the row goes back to a normal "Update".

**Homebrew packages that aren't apps now show up.** DuoUpdater tracked outdated Homebrew formulae, and left casks alone on the grounds that a cask installs an app, which already gets its own row. That holds right up until a cask installs no app — a command-line tool like `codex`, a font, a driver. Those had no row anywhere: nothing for the app list to find, and not a formula either. `codex` sat three versions behind without a word. They're now part of the Homebrew panel, which reads "packages" rather than "formulae" to match. Casks that do install an app are still managed per-app exactly as before, and apps that update themselves are still left to their own updater.

## 0.3.11

**"Update All" now includes apps that install from a package.** A handful of apps — ToDesk and AweSun among them — ship their update as an installer package rather than something DuoUpdater can swap into place on its own. Those were quietly left out of "Update All" and had to be updated one row at a time; if such an app was the only other update pending, the button disappeared altogether rather than acting on just one. They're now part of the batch, and they run at the very end: everything that updates unattended finishes first, so nothing opens a window or asks for your admin password until the rest is already done. One caveat worth knowing — DuoUpdater can't tell when macOS's installer has finished, so if two package updates come up in the same batch, both installer windows open one after the other rather than waiting in line.

## 0.3.10

**Fixes updates going unnoticed for days at a time.** DuoUpdater re-uses the answers it gets from each app's version feed so it isn't re-downloading the same file every few minutes. The problem was how long it trusted a stored answer: when a vendor's server doesn't say how long its reply stays valid, macOS guesses — and it guesses longer the longer that feed has gone unchanged. So the very feeds that had been quiet for a while were exactly the ones DuoUpdater stopped re-reading, and a new release could sit there for days with the app still reporting "up to date" and no error to show for it. Every version check now always asks the server whether anything changed, while still skipping the download when nothing has. OrbStack 2.2.2 is the release that surfaced this; the same blind spot applied to most apps checked directly against their vendor, including Chrome, Cursor, Claude, ChatGPT, Warp, Spotify, and Visual Studio Code.

**Homebrew-managed apps no longer get stuck at the version they were on when DuoUpdater started.** The catalog DuoUpdater reads to learn the latest version of a Homebrew app was loaded once per launch and never refreshed, which is invisible if you quit the app daily and wrong if you leave it running for weeks. It now refreshes periodically. As a bonus, machines with no Homebrew casks installed no longer download that 5 MB catalog at all.

## 0.3.9

**Uses less memory and does less work in the background.** This release is entirely under the hood — nothing about what DuoUpdater does has changed, only what it costs to leave running. Every update it downloaded used to leave a small amount of memory behind that was never reclaimed; harmless once, but it adds up over the weeks a menu-bar app tends to stay open. Separately, while the main window was open DuoUpdater re-read every installed app from disk every 15 seconds and started a system process each time to see what was running — that now happens every three minutes, since the filesystem watcher already notices a real change the moment it happens. Recording the release history after each check also used to save its file once per app rather than once per check, and release notes could be fetched more than once when the same page was already on its way in.

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
