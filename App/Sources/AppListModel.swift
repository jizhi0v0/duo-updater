import Foundation
import Observation
import AppKit
import DuoUpdaterCore

/// Load state for a recipe-backed changelog, driven by the model (not a view) so
/// it survives the user switching apps mid-fetch.
enum ChangelogLoadState {
    case loading
    case loaded(Changelog)
    case failed
}

/// Identity for one rendered changelog in the workbench. Some apps share a
/// bundle id across channels (Thunderbird Stable/ESR/Beta), and templated
/// recipes fetch per-version pages, so bundle id alone is not enough.
struct ChangelogCacheKey: Hashable {
    let bundleID: String
    let channel: ReleaseChannel
    let version: String?
}

/// Owns the scanned app list, their update status, and in-flight installs.
@MainActor
@Observable
final class AppListModel {
    private(set) var results: [UpdateResult] = []
    private(set) var isScanning = false
    private(set) var isChecking = false
    private(set) var lastScan: Date?

    /// Per-app install progress, keyed by app id.
    private(set) var installing: [String: InstallStage] = [:]
    /// True while "Update All" is running. Blocks a second batch from being
    /// started while the first one still has queued work.
    private(set) var isInstallingAll = false
    /// Per-app install error message, keyed by app id.
    private(set) var installErrors: [String: String] = [:]
    /// Per-app informational note (not an error), keyed by app id — e.g. "opened
    /// the running app so its own updater applies the update" under the
    /// defer-to-self-updater install policy. Cleared when a new action starts.
    private(set) var installNotes: [String: String] = [:]
    /// App ids whose on-disk bundle is newer than the version their running
    /// process launched with — i.e. updated (by us, the app's own updater, or
    /// brew) but not yet relaunched, so still executing old code.
    private(set) var needsRestart: Set<String> = []
    /// App ids whose own Squirrel updater has already downloaded and staged a
    /// newer build (in the ShipIt cache) but not yet swapped it in — the app's
    /// "Relaunch to update" state. We surface a Relaunch action for these instead
    /// of offering our own Update, which would re-download and collide with the
    /// pending swap. Keyed by id → the staged update's details.
    private(set) var pendingSelfUpdate: [String: StagedSelfUpdate] = [:]
    /// App ids whose staged self-update is mid-relaunch (we've quit the app and are
    /// waiting for its ShipIt to swap & relaunch). Drives a per-row spinner and,
    /// crucially, blocks re-entry: the swap can take tens of seconds, during which
    /// the Relaunch button must not fire a second quit.
    private(set) var relaunching: Set<String> = []
    /// App ids for which an incremental (AX) App Store update has downloaded but the
    /// app is still running, so App Store is asking to quit it to finish installing.
    /// id → the app's display name (for the prompt). Drives a "Relaunch to finish
    /// update" affordance; tapping it resumes the matching `quitContinuations` entry,
    /// which presses the App Store sheet's Continue button.
    private(set) var awaitingQuitConfirm: [String: String] = [:]
    /// App ids that just finished updating and whose new build is already fully in
    /// effect (in-place swap, or an incremental App Store update that already quit +
    /// reopened the app). Without this the row would vanish the instant the on-disk
    /// version swaps — which reads as "did it fail?" mid-progress. We hold the row a
    /// couple of seconds showing an "Updated ✓" confirmation, then let it drop out.
    private(set) var justUpdated: Set<String> = []
    /// Live Accessibility (AX) trust, mirrored from `AXIsProcessTrusted()`. Unlike
    /// App Management, AX *does* expose a status, so onboarding/Settings can show it
    /// flip to "Granted" the moment the user toggles it — we poll it while a relevant
    /// window is open (`begin/endTrustPolling`).
    private(set) var accessibilityTrusted = AppStoreAXInstaller.isTrusted
    /// Live App Management (`kTCCServiceSystemPolicyAppBundles`) status, read via the
    /// private `TCCAccessPreflight` SPI. `.unknown` when the SPI is unavailable — the UI
    /// falls back to its honest "can't verify, grant to be safe" presentation then.
    private(set) var appManagementStatus = TCCPreflight.appManagementStatus()
    /// Observable mirror of the privileged helper's approval (`helperClient.isEnabled`),
    /// refreshed alongside the other permission statuses. `canAutoInstall` reads THIS
    /// (not the client's live value) so SwiftUI re-renders App Store rows Get→Update the
    /// moment the helper is approved — the live property isn't part of the @Observable
    /// model, so reading it directly wouldn't trigger a re-render.
    private(set) var helperEnabled = false
    /// Suspended `confirmQuit` calls from the AX installer, keyed by app id, resumed
    /// by `confirmQuit(_:proceed:)` when the user accepts or dismisses the prompt.
    @ObservationIgnored private var quitContinuations: [String: CheckedContinuation<Bool, Never>] = [:]
    /// App ids the user agreed to quit (via the confirm affordance) for an
    /// incremental App Store update — App Store's Continue quits but doesn't reopen,
    /// so we relaunch them ourselves once the new build is in place.
    @ObservationIgnored private var reopenAfterQuit: Set<String> = []
    /// id → the build version the running instance launched with, for display.
    private var runningVersionByID: [String: String] = [:]
    /// id → the marketing version the running (pre-self-update) build corresponds to,
    /// recovered from `prefs.marketingByBuild` when we scanned that build before the
    /// swap. Lets the restart line read "1.8.x (build)" instead of a bare build for
    /// apps that updated through their own updater (no rollback backup to draw on).
    private var recoveredRestartMarketing: [String: String] = [:]
    /// When the last full networked check finished — shown in the header so the
    /// user can judge how fresh the results are.
    private(set) var lastCheck: Date?
    /// result.id → the version we have a rollback backup for, refreshed from the
    /// on-disk backup store whenever the list changes.
    private(set) var backupVersions: [String: String] = [:]
    /// Bundle *paths* of apps with at least one live process right now. Kept current
    /// by `NSWorkspace`'s launch/terminate notifications, so a row's running dot
    /// lights up/clears the moment the user opens or quits the app — no refresh
    /// needed. Keyed by path, NOT bundle id: the same app can be installed twice
    /// (e.g. two Android Studio versions side by side) sharing one bundle id, and
    /// only the install whose bundle is actually executing should light up.
    private(set) var runningAppPaths: Set<String> = []

    /// Whether *this exact install* currently has a running process — drives the
    /// green "live" dot in the menu and workbench. Matched on the bundle path so a
    /// second copy of the same app (same bundle id, different path) doesn't falsely
    /// light up when only the other copy is open.
    func isRunning(_ result: UpdateResult) -> Bool {
        runningAppPaths.contains(Self.runtimeBundlePath(result.app.path))
    }

    func runningVersion(_ id: String) -> String? { runningVersionByID[id] }
    func backupVersion(_ id: String) -> String? { backupVersions[id] }

    /// The "from" side of a restart line, as the user should read it. `lsappinfo`
    /// only exposes the running process's *build* (e.g. "3965"), so a bare restart
    /// line reads as a mystery number with its marketing version "lost". We recover
    /// the marketing version from one of two records and pair the two as
    /// "26.609.71450 (3965)", matching the on-disk "to" side's shape:
    ///   1. the rollback backup we wrote right before swapping (our own installs), or
    ///   2. the `marketingByBuild` history captured when we scanned that build before
    ///      it was swapped out (apps that updated through their *own* updater).
    /// Both survive our relaunches. Falls back to the bare build when neither has the
    /// marketing version on record (the app updated while we weren't running). nil
    /// when the app isn't lagging a newer on-disk build.
    func restartFromVersion(_ id: String) -> String? {
        guard let runningBuild = runningVersionByID[id] else { return nil }
        let build = UpdateResult.strippingBuildPrefix(runningBuild)
        // Prefer the rollback backup's marketing (authoritative, written when *we*
        // installed); fall back to the build→marketing history recovered for apps
        // that self-updated outside us. Either way, pair it with the build.
        if let marketing = backupVersions[id] ?? recoveredRestartMarketing[id], marketing != build {
            return "\(marketing) (\(build))"
        }
        return build
    }

    /// The raw staged self-update for a row, if its own updater has downloaded a
    /// newer build than what's on disk (regardless of whether it's the latest).
    func stagedSelfUpdate(_ id: String) -> StagedSelfUpdate? { pendingSelfUpdate[id] }

    /// The staged self-update to surface as **Relaunch** — but only when the staged
    /// build is actually the version the app's channel now offers. Apps download
    /// releases one at a time, so a staged build can already trail a newer release;
    /// relaunching to it would still leave the user a download behind. In that case
    /// we return nil so the row falls back to the normal **Update** (a direct jump
    /// to the latest) instead of a Relaunch that doesn't get you current. "Relaunch"
    /// thus means exactly: the latest is already downloaded, just restart — zero
    /// extra download.
    func actionableStaged(_ result: UpdateResult) -> StagedSelfUpdate? {
        guard let staged = pendingSelfUpdate[result.id] else { return nil }
        if let latest = result.remote?.displayVersion,
           VersionComparator.isNewer(latest, than: staged.version) {
            return nil  // staged trails the latest — show Update, not Relaunch
        }
        return staged
    }

    /// The vendor's advertised version when it's strictly *older* than what's
    /// installed — surfaced (only under "Show all") as a muted, action-less note.
    /// This is usually benign: you're ahead via a beta channel, a pulled release,
    /// or a lagging probe — never a prompt to downgrade. Returns that older version
    /// to display, or nil.
    ///
    /// Gated to **stable** installs: a beta/canary build is *expected* to lead the
    /// stable feed, so flagging it would cry wolf on every beta user. We also stay
    /// silent when there's a real update (that path wins) or the version is equal.
    func downgradeNote(_ result: UpdateResult) -> String? {
        guard result.app.releaseChannel == .stable, !result.hasUpdate else { return nil }
        // Managed sources advertise versions through laggy/regional lookups (App
        // Store iTunes lookup, TestFlight/Toolbox caches), where "installed > remote"
        // is routinely just staleness — too noisy to flag. Only trust real version
        // feeds (Sparkle / Vendor / GitHub).
        guard !result.app.isMASApp, !result.app.isTestFlightApp, !result.app.isToolboxManaged
        else { return nil }
        guard let installed = result.app.shortVersion,
              let remoteShort = result.remote?.shortVersion,
              VersionComparator.isNewer(installed, than: remoteShort) else { return nil }
        return result.remote?.displayVersion ?? remoteShort
    }

    /// A pending update the user hasn't ignored or skipped — what the badge counts
    /// and what "Update All" acts on.
    func isActionableUpdate(_ result: UpdateResult) -> Bool {
        guard result.hasUpdate else { return false }
        if prefs.isIgnored(result.app) { return false }
        if prefs.isVersionSkipped(result.app, version: result.remote?.displayVersion) { return false }
        return true
    }

    var updateCount: Int { results.filter(isActionableUpdate).count }

    /// A full networked refresh rewrites the whole result list. Keep it out of
    /// the way while installs are mutating individual rows and replacing bundles.
    var canRefresh: Bool {
        !isScanning && !isChecking && installing.isEmpty && !isInstallingAll
    }

    /// The count shown on the menu-bar badge. A full refresh briefly blanks every
    /// row to `.unknown` (so `updateCount` dips to 0) before the check repopulates
    /// it — which made the badge flicker to the "no updates" icon and back. While a
    /// scan/check is in flight we hold the last settled count instead; otherwise we
    /// track `updateCount` live (so ignoring/skipping an app updates it at once).
    var badgeCount: Int { (isScanning || isChecking) ? heldBadgeCount : updateCount }
    @ObservationIgnored private var heldBadgeCount = 0

    // MARK: - Homebrew formulae (CLI tools)
    //
    // A standalone surface that mirrors a bare terminal `brew upgrade`, scoped to
    // `--formula`. GUI casks stay per-app via `HomebrewCaskSource`; formulae aren't
    // apps (no bundle, no channel, no changelog), so they live here and can never
    // collide with — or double-count against — the app rows above.
    private let brewFormulaService = BrewFormulaService()
    /// Outdated CLI formulae from the last `brew outdated --formula` read.
    private(set) var brewOutdatedFormulae: [BrewOutdatedFormula] = []
    /// Every top-level (`brew leaves`) formula, outdated or current — the workbench
    /// Brew tree's formula half, so it shows all you manage like the Apps tree does.
    private(set) var brewFormulae: [BrewInstalledFormula] = []
    /// Whether Homebrew is installed at all (cached once — install state doesn't
    /// change mid-session). Lets the menu reserve the brew row's space from the very
    /// first paint for brew users, so the async `brew outdated` result lands in place
    /// instead of inserting a row and shifting clicks.
    let brewInstalled = BrewFormulaService.isAvailable
    /// Flips true once the first `brew outdated` check returns. Until then the menu
    /// shows a "checking" placeholder of the same height as the real row.
    private(set) var brewChecked = false
    /// True while `brew upgrade --formula` is running.
    private(set) var brewUpgrading = false
    /// Last brew-upgrade failure, surfaced under the row; cleared on the next run.
    private(set) var brewUpgradeError: String?
    /// Streamed tail of the running upgrade, shown as a one-line progress note.
    private(set) var brewUpgradeNote: String?
    /// Bulk-upgrade progress: how many of the targeted formulae have finished
    /// pouring, and how many were targeted. Both 0 when no bulk run is active.
    /// Drives the "x/n" readout (popover footer + workbench header) so the bulk
    /// run shows real progress, not just a spinner.
    private(set) var brewUpgradeDone = 0
    private(set) var brewUpgradeTotal = 0
    /// Formula names with a per-row `brew upgrade` in flight (drives the row spinner).
    private(set) var upgradingFormulae: Set<String> = []
    /// Per-formula upgrade failures, keyed by formula name; cleared on the next run.
    private(set) var formulaUpgradeErrors: [String: String] = [:]
    /// Live tail of a per-formula `brew upgrade`'s output (the "Downloading… / Pouring"
    /// line), keyed by formula name — so the row shows real progress instead of a bare
    /// spinner. Cleared when the upgrade finishes.
    private(set) var formulaUpgradeNotes: [String: String] = [:]

    /// Lazily-fetched release notes per formula (keyed by name), loaded only when a
    /// formula is selected in the workbench — so a long outdated list never burns the
    /// GitHub rate limit up front.
    enum FormulaReleaseState { case loading, loaded(FormulaRelease) }
    private(set) var formulaReleaseStates: [String: FormulaReleaseState] = [:]
    private let formulaReleaseService = BrewFormulaReleaseService()

    func formulaReleaseState(name: String) -> FormulaReleaseState? {
        formulaReleaseStates[name]
    }

    /// Every brew-managed cask among the results. `HomebrewCaskSource` stamps each
    /// app it claims with `sourceName == "Homebrew"` (current or outdated alike), so
    /// this is the authoritative set with no extra subprocess. The workbench pulls
    /// these out of its Apps list and shows them under Brew instead.
    var brewCaskResults: [UpdateResult] {
        results.filter { $0.remote?.sourceName == "Homebrew" }
    }

    private let sparkleInstaller = SparkleInstaller()
    private let homebrewInstaller = HomebrewInstaller()
    private let packageInstaller = PackageInstaller()
    private let vendorInstaller = VendorInstaller()
    /// Drives the privileged helper (root daemon) that runs `mas` without a
    /// password prompt; `masInstaller` routes its mas calls through it. The same
    /// client backs the Settings "Enable…" UI and the `canAutoInstall` gate.
    let helperClient = PrivilegedHelperClient()
    private let masInstaller = MASInstaller(runner: HelperShellRunner())
    private let appStoreAXInstaller = AppStoreAXInstaller()

    /// Drives the App Management drag-to-authorize panel (vendored PermissionFlow)
    /// when an install is blocked by the privacy gate. Lazy so we only spin up the
    /// panel/window-tracking machinery the first time we actually hit a denial.
    @ObservationIgnored private lazy var permissionFlow = PermissionFlow.makeController()
    /// During a batch, a stale App Management preflight can make several parallel
    /// installs fail together. Show the permission guide once for that wave.
    @ObservationIgnored private var appManagementPermissionFlowPresentedInBatch = false

    /// User settings (token, concurrency, ignore list, backups…). Read live on
    /// each refresh so a change made in the Settings window takes effect next check.
    let prefs: Preferences

    /// A Settings section another window wants to deep-link to — set by onboarding's
    /// "Set Up GitHub…" before it opens Settings. `SettingsView` consumes and clears
    /// it on appear/change, so the window lands on that tab instead of General.
    var requestedSettingsSection: SettingsView.Section?

    /// An app the workbench should jump to — set by the menu-bar row's "Changelog"
    /// item (the result `id`, i.e. the app path) before it opens the workbench.
    /// `WorkbenchWindowView` consumes and clears it on appear/change, selecting that
    /// app in the sidebar instead of defaulting to the first row.
    var requestedWorkbenchAppID: String?

    /// Whether a GitHub token resolved (explicit, env, or `gh` login) the last
    /// time the source stack was built. Drives the aggregate rate-limit banner:
    /// false + several rate-limited rows ⇒ nudge the user to add a token. Stays
    /// false until the first check (the banner also requires rate-limit errors,
    /// which only exist after a check has run `makeSources` and set this).
    private(set) var hasGitHubToken = false

    /// Background auto-check loop; nil when the frequency is "manual".
    private var scheduler: Task<Void, Never>?

    /// Held while the auto-check loop is armed so macOS App Nap can't suspend it.
    /// Without this, a menu-bar (accessory) app with no open window gets napped when
    /// idle and its `Task.sleep` ticks are throttled/stalled — so the periodic check
    /// never fires and the icon sits on its zero-badge state until you click the
    /// menu (which wakes the app and forces a refresh). `…AllowingIdleSystemSleep`
    /// defeats App Nap but still lets the Mac sleep normally when idle.
    @ObservationIgnored private var napAssertion: (any NSObjectProtocol)?

    /// Watches the app install dirs so a *background* self-update (Chrome's
    /// Keystone, a Sparkle/Squirrel app, brew) flips the Restart badge promptly,
    /// without waiting for a menu open or the next networked check. Both this and
    /// the periodic backstop below are network-free — they just trigger
    /// `refreshLocal` (disk rescan + restart/staging recompute).
    @ObservationIgnored private var appDirWatcher: AppDirectoryWatcher?
    /// Slow backstop in case an FS event is missed (a dir we don't watch, a
    /// coalesced burst we never saw). Re-derives restart state on a lazy cadence.
    @ObservationIgnored private var localRescanTimer: Task<Void, Never>?
    private let localRescanInterval: Duration = .seconds(180)  // 3 min
    /// Coalesce background-triggered rescans: a flurry of FS events plus a timer
    /// tick shouldn't stack up redundant scans on top of each other.
    @ObservationIgnored private var localRescanRunning = false
    /// Set when a background rescan (FS watcher / backstop) was requested but skipped
    /// because an install was in flight — `refreshLocal` would have dropped it anyway
    /// (and a rescan mid-install could churn a spinner row). We remember it and drain
    /// it the moment installs settle, so an app that self-updates *externally* while
    /// we're installing something else (Chrome's Keystone applying a new build during
    /// an "Update All") clears its stale "update available" row at once, instead of
    /// lingering until the next slow backstop tick.
    @ObservationIgnored private var localRescanDeferred = false

    /// `NSWorkspace` launch/terminate observers that keep `runningBundleIDs` live.
    /// Retained for the app's lifetime (the single model never deallocates), so they
    /// stay registered without explicit teardown.
    @ObservationIgnored private var runningAppObservers: [NSObjectProtocol] = []
    /// Coalesces the terminate+launch burst a manual app restart emits into a single
    /// restart-info recompute (see `handleRunningAppsChange`). Cancel-and-reschedule,
    /// so a flurry of process events collapses to one `lsappinfo` read.
    @ObservationIgnored private var restartRecheckTask: Task<Void, Never>?

    /// Periodic "your app downloaded an update on its own — relaunch to apply it"
    /// reminder. Decoupled from the (possibly hours-long) update-check interval:
    /// once we detect a self-staged build, we nudge right away and then keep
    /// re-nudging on this cadence until the user relaunches and it's applied. Nil
    /// when nothing is staged.
    @ObservationIgnored private var selfUpdateReminder: Task<Void, Never>?
    private let selfUpdateReminderInterval: Duration = .seconds(300)  // 5 min

    /// Per-app download traffic, tracked to the byte and persisted across runs.
    private let trafficStore = TrafficStore()
    /// Snapshot of per-app traffic for the UI, refreshed after each recorded
    /// download. Sorted heaviest-app-first by the store.
    private(set) var trafficStats: [AppTrafficStat] = []
    /// Grand total bytes downloaded across every app.
    private(set) var trafficTotalBytes: Int64 = 0

    /// Per-app release history, built up over time from each check's results and
    /// persisted across runs. Only releases that arrive with a trustworthy vendor
    /// timestamp (Sparkle/GitHub/Alcove, plus any VendorProbe recipe carrying a
    /// `publishedAtPattern`) are logged.
    private let releaseTimelineStore = ReleaseTimelineStore()
    /// Snapshot of the release timelines for the UI, most-recently-released app
    /// first. Refreshed after each check records new releases.
    private(set) var releaseTimelines: [AppReleaseTimeline] = []

    @MainActor
    private func syncDockBadge() {
        AppDockBadge.sync(count: badgeCount)
    }

    /// Call from a window's `.onAppear`: keep the badge current and bring the
    /// first surfaced window to the front.
    func windowAppeared() {
        syncDockBadge()
        AppDockBadge.syncSoon(count: badgeCount)
        if NSApp.keyWindow == nil && NSApp.mainWindow == nil {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Call from a window's `.onDisappear`. Kept for symmetric lifecycle sites even
    /// though the app now stays `.regular` permanently.
    func windowDisappeared() {
    }

    /// Bring an already-open (or just-opened) SwiftUI `Window` scene to the visual
    /// front. `openWindow(id:)` re-keys a window but, on macOS 26/27, does NOT
    /// raise its z-order above a sibling window of the same app — and when the
    /// window is *already open behind* another, its view never re-runs `.onAppear`,
    /// so the lifecycle-based ordering never fires. So every Settings open site
    /// calls this right after `openWindow` to force the order regardless of state.
    ///
    /// Matches on the SwiftUI window identifier, whose rawValue embeds the scene id
    /// (e.g. "settings-AppWindow-1"). Runs on the next runloop so the window exists
    /// for a fresh open, and after `windowAppeared`'s `activate` so our order wins.
    func surfaceWindow(sceneID: String) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: {
                ($0.identifier?.rawValue.contains(sceneID) ?? false) && $0.isVisible
            }) else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    // MARK: - Accessibility trust polling

    @ObservationIgnored private var trustPollTask: Task<Void, Never>?
    @ObservationIgnored private var trustPollers = 0
    @ObservationIgnored private var trustObserver: NSObjectProtocol?
    /// Set while a drag-panel is up, so the moment we detect the corresponding grant we
    /// can dismiss that now-pointless panel. Both are now detectable — Accessibility via
    /// `AXIsProcessTrusted()`, App Management via the `TCCAccessPreflight` SPI.
    @ObservationIgnored private var awaitingAccessibilityGrant = false
    @ObservationIgnored private var awaitingAppManagementGrant = false

    /// Refresh both mirrored permission states once, and auto-dismiss a drag-panel whose
    /// grant just landed. Cheap: `AXIsProcessTrusted()` + one `TCCAccessPreflight` call.
    ///
    /// Caveat we can't engineer around for *Accessibility*: TCC reflects a *grant* to a
    /// running process live, but a *revocation* is cached — `AXIsProcessTrusted()` keeps
    /// returning true for a process that has already used Accessibility until it
    /// relaunches. So that flips false→true on its own but true→false only after a
    /// restart. (App Management goes through `tccd` each call, so it tracks both ways
    /// better.) The distributed-notification hook below catches changes promptly.
    func refreshPermissionStatus() {
        let trusted = AppStoreAXInstaller.isTrusted
        accessibilityTrusted = trusted
        if trusted, awaitingAccessibilityGrant {
            awaitingAccessibilityGrant = false
            permissionFlow.closePanel(returnToPreviousApp: true)
        }

        let appMgmt = TCCPreflight.appManagementStatus()
        appManagementStatus = appMgmt
        if appMgmt == .granted, awaitingAppManagementGrant {
            awaitingAppManagementGrant = false
            permissionFlow.closePanel(returnToPreviousApp: true)
        }

        // Mirror the helper's approval into observable state, and refresh the client's
        // published status so the Settings "App Store helper" row flips on its own once
        // approved in Login Items (no second click). The menu's `.task` calls this on
        // appear, so App Store rows reflect the helper without opening Settings.
        helperClient.refreshStatus()
        helperEnabled = helperClient.isEnabled

        logPermissionsOnce()
    }

    /// Track AX trust while a permission-aware window (Welcome, Settings) is open, so a
    /// freshly-granted toggle reflects without a relaunch. Two signals: macOS's TCC
    /// change notification (`com.apple.accessibility.api`, fires the instant the user
    /// flips the switch) plus a slow poll as a backstop. Ref-counted; pair with `end`.
    func beginTrustPolling() {
        trustPollers += 1
        refreshPermissionStatus()
        if trustObserver == nil {
            trustObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil, queue: .main
            ) { [weak self] _ in
                // TCC can lag the notification slightly — re-check now and once more shortly.
                Task { @MainActor in
                    self?.refreshPermissionStatus()
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.refreshPermissionStatus()
                }
            }
        }
        guard trustPollTask == nil else { return }
        trustPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                self?.refreshPermissionStatus()
            }
        }
    }

    func endTrustPolling() {
        trustPollers = max(0, trustPollers - 1)
        if trustPollers == 0 {
            trustPollTask?.cancel()
            trustPollTask = nil
            if let trustObserver {
                DistributedNotificationCenter.default().removeObserver(trustObserver)
                self.trustObserver = nil
            }
        }
    }

    /// True when the user is on the incremental App Store route, AX isn't granted, and
    /// at least one actionable App Store update is waiting on it — i.e. a setup nudge
    /// is genuinely warranted (vs. nagging users who don't use that route).
    var needsAccessibilitySetup: Bool {
        guard prefs.appStoreUpdateStrategy == .incremental, !accessibilityTrusted else { return false }
        // iOS-on-Mac apps redirect to the App Store (no AX), so they don't justify
        // an Accessibility nudge on their own.
        return results.contains {
            isActionableUpdate($0) && $0.remote?.appStore?.trackID != nil && !$0.app.isiOSAppOnMac
        }
    }

    /// Whether a *user-present* refresh has read the TestFlight container yet this
    /// launch. The silent background scheduler never reads it (so a cold launch
    /// can't trigger the "access data from other apps" prompt out of nowhere); the
    /// first time the user actually opens the menu/workbench we read it once — a
    /// natural, user-initiated moment for the TCC prompt. A Developer ID signature
    /// makes that grant persist across launches, so it's a one-time ask.
    private(set) var testFlightReadThisSession = false

    init(prefs: Preferences = .shared) {
        self.prefs = prefs
        // Restore when we last checked so the scheduler can pick up where it left
        // off across relaunches instead of restarting the interval from zero.
        self.lastCheck = prefs.lastCheckDate
        // Register the notification delegate + actionable categories (this also
        // requests notification permission once).
        NotificationController.shared.register(model: self)
        // Load any previously recorded traffic so the stats view isn't empty on
        // launch before the first install of this session.
        Task { await refreshTrafficStats() }
        // Arm the background auto-check loop at launch — not on first menu open —
        // so a menu-bar app that's never clicked still checks on schedule.
        reschedule()
        // Watch the app dirs (+ a slow backstop) so a background self-update —
        // Chrome's Keystone staging a new build, a Sparkle app swapping itself —
        // flips the Restart badge without waiting for a menu open or networked check.
        armLocalRescan()
        // Track which apps are running so each row can show a live "running" dot,
        // kept current by NSWorkspace launch/terminate notifications.
        armRunningAppsMonitor()
    }

    /// The explicit GitHub token preference as the resolver should see it: nil when
    /// the field is empty, the raw saved value otherwise.
    private func explicitGitHubToken() -> String? {
        prefs.githubToken.isEmpty ? nil : prefs.githubToken
    }

    /// Resolve a GitHub token off the main actor, but don't let a wedged `gh auth
    /// token` hold the whole refresh hostage forever. Falling back to nil just means
    /// the check runs unauthenticated this cycle.
    private static func resolveGitHubToken(
        explicit: String?, timeout: Duration = .seconds(2)
    ) async -> String? {
        let loader = Task.detached(priority: .utility) {
            GitHubToken.resolve(explicit: explicit)
        }
        if let token = await firstResult(of: loader, within: timeout) {
            return token
        }
        Log.app.error("GitHub token resolve timed out — continuing without a token")
        return nil
    }

    /// The ordered source stack, rebuilt per check so it picks up a token change
    /// and the App Store source re-reads the signed-in storefront region.
    private func makeSources(token: String?) -> [any UpdateSource] {
        hasGitHubToken = (token != nil)
        var sources: [any UpdateSource] = [
            MacAppStoreSource(),
            SparkleAppcastSource(),
            HomebrewCaskSource(),
            // GitHub Releases for apps distributed that way (detection only unless
            // a rule names an installable asset).
            GitHubReleasesSource(token: token),
        ]
        // Alcove's licensed update channel, ahead of the vendor probe: it's the only
        // surface carrying release notes, an exact publish time and an installable
        // (licensed) download, so when the user's credentials are present it answers
        // first. Otherwise it's omitted and the public VendorProbe recipe handles
        // Alcove — same version, but detection-only and without notes.
        if let creds = alcoveCredentials() {
            sources.append(AlcoveUpdateSource(credentials: creds))
        }
        // Last resort: bespoke per-vendor version endpoints. Only fires when
        // the earlier sources all miss and a recipe exists.
        sources.append(VendorProbeSource())
        return sources
    }

    /// Alcove's licensed-update credentials, or nil if either secret is missing
    /// (then the public vendor probe handles Alcove, lagging).
    private func alcoveCredentials() -> AlcoveUpdateSource.Credentials? {
        let key = prefs.alcoveLicenseKey
        let instance = prefs.alcoveInstanceID
        guard !key.isEmpty, !instance.isEmpty else { return nil }
        return AlcoveUpdateSource.Credentials(licenseKey: key, instanceID: instance)
    }

    /// Pull the latest per-app traffic snapshot out of the store onto the main
    /// actor for the UI.
    private func refreshTrafficStats() async {
        let snapshot = await trafficStore.snapshot()
        let total = await trafficStore.totalBytes()
        trafficStats = snapshot
        trafficTotalBytes = total
    }

    /// Record the bytes one install transferred, keyed to its app, then refresh
    /// the UI snapshot. `bytes <= 0` (e.g. an install that did no measured
    /// download) is ignored by the store.
    private func recordTraffic(_ result: UpdateResult, bytes: Int64) async {
        await trafficStore.record(
            appID: result.app.id,
            appName: result.app.name,
            bundleID: result.app.bundleID,
            fromVersion: result.app.shortVersion,
            toVersion: result.remote?.displayVersion,
            sourceName: result.remote?.sourceName,
            bytes: bytes
        )
        await refreshTrafficStats()
    }

    /// Log every release in `checked` that arrived with a trustworthy vendor
    /// timestamp into the release timeline, then refresh the UI snapshot. The
    /// store dedupes by (app, version), so re-checks are cheap no-ops and only a
    /// genuinely new release writes to disk. Results without a `publishedAt`
    /// (vendor probes, MAS, Homebrew) are skipped by the store.
    private func recordReleaseTimeline(for checked: [UpdateResult]) async {
        var added = false
        for result in checked {
            guard let remote = result.remote else { continue }
            // The latest release (when it carries a date)…
            if remote.publishedAt != nil {
                let didAdd = await releaseTimelineStore.record(
                    appID: result.app.id,
                    appName: result.app.name,
                    bundleID: result.app.bundleID,
                    version: remote.displayVersion,
                    sourceName: remote.sourceName,
                    publishedAt: remote.publishedAt
                )
                added = added || didAdd
            }
            // …plus any prior releases the source surfaced (Sparkle appcast items,
            // a GitHub releases list), so an app's history backfills in one shot.
            // The store dedupes by version, so the latest overlapping here is free.
            for entry in remote.releaseHistory {
                let didAdd = await releaseTimelineStore.record(
                    appID: result.app.id,
                    appName: result.app.name,
                    bundleID: result.app.bundleID,
                    version: entry.version,
                    sourceName: remote.sourceName,
                    publishedAt: entry.publishedAt
                )
                added = added || didAdd
            }
            // Detection-only sources (a vendor probe, a Homebrew cask, the App
            // Store) report a version but no date. We can't know when they shipped,
            // only that a version *change* happened between two checks — so track
            // the reported version and, on a change, log an estimated window.
            if remote.publishedAt == nil, remote.releaseHistory.isEmpty,
               let v = remote.displayVersion {
                let didAdd = await releaseTimelineStore.observeForChange(
                    appID: result.app.id,
                    appName: result.app.name,
                    bundleID: result.app.bundleID,
                    version: v,
                    sourceName: remote.sourceName
                )
                added = added || didAdd
            }
        }
        // One write for the whole check. The store batches every `record` /
        // `observeForChange` above into dirty flags precisely so a 100-app check
        // doesn't turn into 100 full-file atomic rewrites.
        await releaseTimelineStore.flush()
        // Always refresh on first run (snapshot starts empty); otherwise only when
        // something actually changed.
        if added || releaseTimelines.isEmpty {
            releaseTimelines = await releaseTimelineStore.snapshot()
        }
    }

    /// Per-app load state for a recipe-backed changelog, keyed by
    /// bundle/channel/target-version. The workbench reads this to render
    /// reactively; it never drives the fetch from a view's `.task`, so switching
    /// apps can't cancel an in-flight load.
    private(set) var changelogState: [ChangelogCacheKey: ChangelogLoadState] = [:]
    /// The live load task per changelog key, owned by the model (NOT the view).
    /// Because it lives here, navigating away from an app mid-fetch doesn't cancel
    /// it — the fetch finishes in the background and caches, so coming back is
    /// instant instead of restarting from scratch.
    @ObservationIgnored private var changelogTasks: [ChangelogCacheKey: Task<Void, Never>] = [:]

    /// The current state of an app's changelog, if it's recipe-backed. `nil` means
    /// the app has no recipe (the workbench then renders inline/structured/web
    /// notes directly, with no fetch involved).
    func changelogState(for result: UpdateResult) -> ChangelogLoadState? {
        guard let key = changelogKey(for: result) else { return nil }
        return changelogState[key] ?? .loading
    }

    /// The hand-authored changelog recipe to use for THIS result, or nil. Recipes
    /// are keyed by bundle id, but a recipe targets a vendor's *official-site*
    /// distribution; when the same bundle id is also installed from the Mac App
    /// Store, that copy is a separate distribution whose notes come from the store's
    /// own "What's New" (`releaseNotesHTML` / the store page). WeChat is the live
    /// case: the official-site copy and the App Store copy share
    /// `com.tencent.xinWeChat`, but the official site's per-version page doesn't
    /// describe the App Store build. So gate the recipe out for App-Store-sourced
    /// results (only `MacAppStoreSource` attaches `appStore`) and let them fall
    /// through to the store notes.
    private func applicableRecipe(for result: UpdateResult) -> ChangelogRecipe? {
        guard result.remote?.appStore == nil else { return nil }
        return ChangelogRecipeRegistry.recipe(
            forBundleID: result.app.bundleID, channel: result.app.releaseChannel)
    }

    /// Kick off a background load for an app's recipe-backed changelog if one isn't
    /// already loaded or in flight. Idempotent and non-blocking: the task runs off
    /// the main actor's critical path (it only `await`s the network) and survives
    /// the user navigating to another app, so the result is ready on return.
    /// Re-tries a previous `.failed`.
    func ensureChangelogLoading(for result: UpdateResult) {
        guard let bundleID = result.app.bundleID,
              let recipe = applicableRecipe(for: result) else { return }
        let targetVersion = result.remote?.displayVersion ?? result.app.shortVersion
        let key = ChangelogCacheKey(
            bundleID: bundleID, channel: result.app.releaseChannel, version: targetVersion)
        switch changelogState[key] {
        case .loaded, .loading: return          // already done / in flight
        case .failed, .none: break              // (re)start
        }
        changelogState[key] = .loading
        // The version whose notes to show: the offered update if any, else the
        // installed build. Templated recipes (Thunderbird) fetch exactly that
        // version's page so the rendered notes match what the user sees.
        //
        // Stale-while-revalidate: if the cross-launch disk cache already holds this
        // version's notes, paint them instantly, then revalidate from the network
        // and swap in any change. A released version's notes are immutable, so the
        // cached value is correct to show outright; the revalidation just catches a
        // post-publish edit and keeps the very latest list current.
        changelogTasks[key] = Task { [weak self] in
            if let cached = await ChangelogService.diskCached(recipe, version: targetVersion) {
                if Task.isCancelled { return }
                guard let self else { return }
                self.changelogState[key] = .loaded(cached)
            }
            let fresh = await ChangelogService.load(recipe, version: targetVersion)
            // A concurrent invalidate (app updated on disk) cancels this task and
            // clears the key; bail rather than resurrect stale notes or clobber the
            // task slot a fresh load may have installed.
            if Task.isCancelled { return }
            guard let self else { return }
            self.changelogTasks[key] = nil
            if let fresh {
                self.changelogState[key] = .loaded(fresh)
            } else if case .loaded = self.changelogState[key] {
                // Network revalidation failed but we already painted cached notes —
                // keep them rather than dropping to the web-view fallback.
            } else {
                self.changelogState[key] = .failed
            }
        }
    }

    private func changelogKey(for result: UpdateResult) -> ChangelogCacheKey? {
        guard let bundleID = result.app.bundleID,
              applicableRecipe(for: result) != nil
        else { return nil }
        return ChangelogCacheKey(
            bundleID: bundleID,
            channel: result.app.releaseChannel,
            version: result.remote?.displayVersion ?? result.app.shortVersion)
    }

    /// Drop one app's cached changelog across both layers — the session-wide
    /// parsed cache here *and* the network-level `ChangelogCache` — and cancel any
    /// in-flight load. Called after an app updates to a new version on disk: the
    /// notes the user saw were for the old release, and the model cache has no TTL
    /// of its own, so without this they'd persist until the next manual refresh.
    /// The next `ensureChangelogLoading` re-fetches fresh notes for the new build.
    func invalidateChangelog(forBundleID bundleID: String?) {
        guard let bundleID else { return }
        for key in changelogTasks.keys.filter({ $0.bundleID == bundleID }) {
            changelogTasks[key]?.cancel()
            changelogTasks[key] = nil
        }
        for key in changelogState.keys.filter({ $0.bundleID == bundleID }) {
            changelogState[key] = nil
        }
        // Clear the network cache for every channel variant (Stable & ESR share this
        // bundle id but have different sources; Warp's three channels share one
        // endpoint but get distinct channel-fragmented cache slots), since we don't
        // know here which channel's notes were cached.
        let recipes = ChangelogRecipeRegistry.recipes(forBundleID: bundleID)
        if !recipes.isEmpty {
            Task { for recipe in recipes { await ChangelogService.invalidateMemoryCache(for: recipe) } }
        }
    }

    /// Pre-warm every recipe-backed app's changelog right after a check, so opening
    /// one paints instantly with no loading flash. The key insight is that the
    /// workbench renders the *in-memory* `changelogState`; the disk cache alone
    /// isn't enough, because the view still has to round-trip to disk on first
    /// appear (showing the spinner meanwhile). So this fills `changelogState`
    /// directly — disk-first, fetching only when disk has nothing for this version.
    ///
    /// Because a released version's notes are immutable, a disk hit needs no network
    /// at all; steady-state this touches the wire only for genuinely new releases
    /// (the periodic check thus doubles as a near-free changelog pre-warm). Runs for
    /// every recipe-backed app, not just those with updates, since the user browses
    /// notes for up-to-date apps too. On failure it leaves the key absent so the
    /// open path retries rather than getting stuck on a stale spinner / web fallback.
    /// Bounds how many changelog prewarms hit the network at once (a cold cache would
    /// otherwise fire one fetch per recipe-backed installed app simultaneously).
    private static let prewarmNetworkGate = AsyncSemaphore(value: 4)

    private func prewarmChangelogs(for results: [UpdateResult]) {
        for result in results {
            guard let key = changelogKey(for: result),
                  let recipe = applicableRecipe(for: result) else { continue }
            // Don't clobber an entry that's already loaded, loading, or being viewed.
            if changelogState[key] != nil { continue }
            let targetVersion = result.remote?.displayVersion ?? result.app.shortVersion
            changelogState[key] = .loading
            changelogTasks[key] = Task { [weak self] in
                var changelog = await ChangelogService.diskCached(recipe, version: targetVersion)
                if changelog == nil {
                    // Cap concurrent network prewarms: a cold cache would otherwise
                    // fan out one fetch per recipe-backed app at once. Disk hits above
                    // skip the gate; only genuine network fetches queue through it.
                    await Self.prewarmNetworkGate.wait()
                    changelog = await ChangelogService.load(recipe, version: targetVersion)
                    await Self.prewarmNetworkGate.signal()
                }
                if Task.isCancelled { return }
                guard let self else { return }
                self.changelogTasks[key] = nil
                if let changelog {
                    self.changelogState[key] = .loaded(changelog)
                    self.prewarmImages(in: changelog)
                } else {
                    // Network miss during pre-warm: settle on `.failed` so the pane
                    // shows the web-view fallback rather than stranding on the spinner.
                    // (`changelogState(for:)` maps a *missing* key back to `.loading`,
                    // and the view's `.onAppear` fires once per appearance — so clearing
                    // the key would leave an in-flight-looking spinner that never
                    // re-triggers a fetch. The next refresh re-prewarms and can recover.)
                    self.changelogState[key] = .failed
                }
            }
        }
    }

    /// Warm the changelog image cache for every illustration in `changelog`, so a
    /// prewarmed entry's pictures (WeChat embeds feature screenshots) are on screen
    /// the instant the user opens it, not streamed in on appear. Fetches the bytes
    /// (disk-first via `ImageStore`) and decodes into the main-actor memory cache.
    /// Skips URLs already decoded in memory; cheap and idempotent.
    private func prewarmImages(in changelog: Changelog) {
        let urls = changelog.entries
            .flatMap(\.content)
            .compactMap { block -> URL? in
                if case let .image(url) = block { return url }
                return nil
            }
        for url in urls where ImageMemoryCache.shared.image(for: url) == nil {
            // Detached so the NSImage decode in `store` runs off the main actor —
            // prewarming several full-res WeChat screenshots shouldn't hitch the UI.
            Task.detached(priority: .utility) {
                guard let data = await ImageStore.shared.data(for: url) else { return }
                ImageMemoryCache.shared.store(data, for: url)
            }
        }
    }

    /// Scan the disk, then check every app for updates.
    /// The one in-flight full refresh, if any. For the whole app lifecycle there
    /// is **at most one concurrent refresh**: overlapping callers (first menu
    /// open, the manual button, a background tick) coalesce onto this task rather
    /// than racing. Two interleaved refreshes used to stomp each other on the
    /// main actor — one resets `results` to `.unknown` while the other is mid
    /// network check — which is exactly how an "up to date" snapshot could clobber
    /// a check that had found updates.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Whether the in-flight `refreshTask` was started with TestFlight reads enabled.
    /// A user-present caller (`allowTestFlight: true`) that coalesces onto a silent
    /// background refresh (`false`) would otherwise return with TestFlight tags never
    /// applied — so we check this and run one follow-up that does the TestFlight read.
    @ObservationIgnored private var refreshTaskAllowedTestFlight = false

    /// The Toolbox inventory to use for a scan: the real one (reads `state.json`)
    /// when JetBrains Toolbox is actually installed, an EMPTY one when it isn't.
    ///
    /// Toolbox's `state.json` outlives an uninstall — uninstallers (AppCleaner et al.)
    /// remove the `.app` and its Preferences but not the shared
    /// `~/Library/Application Support/JetBrains` dir — so a stale `state.json` would
    /// keep tagging the IDEs as Toolbox-managed, leaving a dead "Toolbox" button and
    /// blocking our own update path. Anchoring management on the `.app` actually
    /// resolving means: Toolbox gone → not managed → the JetBrains IDEs fall back to
    /// the Vendor source (one-click DMG). Safe to call off the main actor.
    nonisolated static func toolboxInventory() -> ToolboxInventory {
        let installed = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.jetbrains.toolbox") != nil
        return installed ? ToolboxInventory() : ToolboxInventory(managedPaths: [])
    }

    /// Single-flight entry point. If a refresh is already running, await it and
    /// return instead of starting a second one.
    ///
    /// `allowTestFlight` gates the one read that triggers the "access data from
    /// other apps" TCC prompt: user-present callers (menu/window open, the manual
    /// button) pass `true`; the silent background scheduler passes `false` so a
    /// cold launch never prompts unprompted.
    func refresh(allowTestFlight: Bool = true) async {
        if let existing = refreshTask {
            // A `true` caller that lands on a silent (`false`) refresh would otherwise
            // return without ever doing the TestFlight read — its tags stay missing
            // until the next refresh. Note the in-flight grant *before* awaiting, since
            // the owning call clears `refreshTask`/`refreshTaskAllowedTestFlight` once
            // it returns.
            let needTestFlightFollowUp = allowTestFlight && !refreshTaskAllowedTestFlight
            Log.app.info("refresh: already in flight — coalescing onto it")
            await existing.value
            // Run one fresh refresh with TestFlight enabled. This recurses at most
            // once: that refresh starts with `allowTestFlight == true`, so it can't
            // re-trigger this branch and loop. (`reapplyTestFlightWhenGranted` also
            // folds in, so no duplicate prompt.)
            if needTestFlightFollowUp {
                Log.app.info("refresh: coalesced onto a silent refresh — running TestFlight follow-up")
                await refresh(allowTestFlight: true)
            }
            return
        }
        guard canRefresh else {
            Log.app.info("refresh: skipped — install/check already in flight")
            return
        }
        // Only this path ever assigns `refreshTask`; coalescing callers above just
        // await it. Clear ownership *inside* the task — before `task.value` resolves
        // — so a `true` caller that coalesced onto a silent refresh resumes to find
        // `refreshTask` already nil. Clearing it *after* `await task.value` (out here)
        // left a window where that caller re-entered the TestFlight follow-up branch
        // above against the same just-finished silent task and recursed on
        // `refresh(allowTestFlight: true)` forever — a main-thread livelock (ANR).
        let task = Task {
            await self.performRefresh(allowTestFlight: allowTestFlight)
            self.refreshTask = nil
            self.refreshTaskAllowedTestFlight = false
        }
        refreshTask = task
        refreshTaskAllowedTestFlight = allowTestFlight
        await task.value
    }

    /// Race a detached task against a timeout. Returns the task's value if it
    /// finishes within `timeout`, otherwise `nil` — and crucially the task keeps
    /// running, so the caller can still await it later.
    ///
    /// We deliberately do NOT use `withTaskGroup`: it won't return until *every*
    /// child finishes, and the child that does `await task.value` can't be
    /// cancelled out of a blocked `open()`, so the group would join on it and
    /// defeat the timeout entirely (the bug this replaces). Instead we resume a
    /// continuation from whichever of {loader, timeout} fires first, with a
    /// once-only guard, and simply abandon the loser.
    private static func firstResult<T: Sendable>(
        of task: Task<T, Never>, within timeout: Duration
    ) async -> T? {
        let gate = RaceGate()
        return await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            Task {
                let value = await task.value
                if await gate.claim() { cont.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if await gate.claim() { cont.resume(returning: nil) }
            }
        }
    }

    /// Start loading TestFlight's inventory (off-main) and wait only briefly, then
    /// take whatever's ready. Its DB is in another app's sandbox container, so
    /// `open()` is gated by the "access data from other apps" TCC prompt and blocks
    /// until the user answers — local reads are otherwise milliseconds, so a timeout
    /// here means "the prompt is up". On timeout we return an empty, `accessible ==
    /// false` inventory so the caller proceeds unfrozen, and hand back the still-
    /// running loader so it can re-apply once the user clicks Allow (callers that
    /// don't need that, e.g. a single-app recheck, just ignore the loader).
    private static func beginTestFlightLoad(
        timeout: Duration = .seconds(2)
    ) async -> (inventory: TestFlightInventory, pendingLoader: Task<TestFlightInventory, Never>?) {
        let loader = Task.detached(priority: .utility) { TestFlightInventory() }
        if let loaded = await firstResult(of: loader, within: timeout) {
            return (loaded, nil)
        }
        Log.scan.info("TestFlight: read pending (TCC prompt unanswered) — proceeding without it")
        return (TestFlightInventory(macRows: [], accessible: false), loader)
    }

    /// When the TestFlight read was blocked by the TCC prompt, keep awaiting the
    /// detached loader — the blocked `open()` returns the instant the user answers.
    /// If they granted access, re-run the check so TestFlight tagging appears with
    /// no manual refresh. Denial (or a missing DB) leaves `accessible == false`, so
    /// we don't loop. `refresh()` is single-flight, so overlapping re-applies fold
    /// into one.
    @ObservationIgnored private var testFlightReapplyPending = false
    private func reapplyTestFlightWhenGranted(_ loader: Task<TestFlightInventory, Never>) {
        // One waiter at a time: repeated menu-opens while the prompt is up shouldn't
        // stack N re-checks that all fire when the user finally clicks Allow.
        guard !testFlightReapplyPending else { return }
        testFlightReapplyPending = true
        Task { [weak self] in
            let late = await loader.value
            guard let self else { return }
            self.testFlightReapplyPending = false
            guard late.accessible else { return }  // Don't Allow / missing DB → don't loop
            Log.scan.info("TestFlight: access granted after prompt — re-checking")
            await self.refresh()
        }
    }

    @ObservationIgnored private var didRecoverSwaps = false

    /// Run the interrupted-swap recovery sweep once per session, off the main thread.
    /// Scans `/Applications` (the only place the privileged, non-atomic swap path can
    /// leave an orphan — user-writable locations take the atomic path).
    private func recoverInterruptedSwapsOnce() {
        guard !didRecoverSwaps else { return }
        didRecoverSwaps = true
        Task.detached(priority: .utility) {
            InPlaceSwap.recoverInterruptedSwaps(in: URL(fileURLWithPath: "/Applications"))
        }
    }

    private func performRefresh(allowTestFlight: Bool = true) async {
        Log.app.info("refresh: start (scan + network check, testflight=\(allowTestFlight, privacy: .public))")
        // Once per session, before the scan: recover any app left at
        // `<App>.app.duoupdater-old` by a privileged swap that died mid-rename (a
        // power loss / force-quit on the non-admin install path). Restoring it here
        // means the about-to-run scan sees a working app rather than a missing one.
        recoverInterruptedSwapsOnce()
        // Snapshot the current count before we blank the rows below, so the menu-bar
        // badge holds it steady through the scan/check instead of flickering to 0.
        heldBadgeCount = updateCount
        // Expire all cached changelog pages so the detail window re-fetches
        // after a manual refresh — the user expects fresh release notes. Drop the
        // parsed-changelog cache too, so the workbench re-loads fresh notes.
        await ChangelogCache.shared.invalidateAll()
        changelogState = [:]
        changelogTasks.values.forEach { $0.cancel() }
        changelogTasks = [:]
        isScanning = true
        // The Toolbox inventory and the on-disk scan are local and fast. The
        // TestFlight inventory is the one TCC-gated read — another app's sandbox
        // container — that can sit on the "access data from other apps" prompt. So
        // we DON'T let it gate the visible list: scan and show apps immediately with
        // no TestFlight data, then fold its tags in once the read lands (or hand it
        // to the re-apply path if the prompt is still up). A TestFlight install may
        // briefly show as a MAS app until then; the re-tag below corrects it.
        let toolbox = await Task.detached(priority: .userInitiated) { Self.toolboxInventory() }.value

        // Start the TCC-gated TestFlight read OFF the critical path. Skipped on a
        // silent background refresh, which must never surface the prompt unprompted;
        // managed-app tagging then carries over from the last user-present check.
        let tfLoader: Task<TestFlightInventory, Never>? =
            allowTestFlight ? Task.detached(priority: .utility) { TestFlightInventory() } : nil
        if allowTestFlight { testFlightReadThisSession = true }

        // First scan with no TestFlight data → the list appears instantly, with no
        // wait on the prompt.
        let initialTF = TestFlightInventory(macRows: [], accessible: false)
        // User-added scan folders (Settings → Folders). Captured on the main actor
        // before hopping off it, since `prefs` is `@MainActor`-isolated.
        let extraScan = prefs.customScanLocations
        // Start token resolution early and off-main so a slow `gh` CLI overlaps the
        // local scan instead of freezing the UI or delaying the whole refresh later.
        async let githubToken = Self.resolveGitHubToken(explicit: explicitGitHubToken())
        var found = await Task.detached(priority: .userInitiated) {
            AppScanner(extraLocations: extraScan, toolbox: toolbox, testflight: initialTF).scan()
        }.value
        // Cold start (no rows yet): show plain `.unknown` rows while the check runs.
        // But when we already have results — e.g. the menu bar populated them and
        // the user just opened the workbench — DON'T blank them to `.unknown`, which
        // would make every update arrow vanish from the sidebar until the network
        // check lands a few seconds later. Carry the prior status/remote forward
        // (re-evaluated against the fresh on-disk version) so the list stays put and
        // the menu bar's data shows immediately; the check then overwrites it.
        results = results.isEmpty
            ? found.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
            : sorted(mergeScanned(found))
        lastScan = .now
        isScanning = false

        // Resolve TestFlight without blocking the list just shown. If it lands in
        // time, re-tag so TestFlight installs route correctly in this same pass; if
        // the prompt is still up, hand the still-running read to the re-apply path,
        // which re-checks the instant the user clicks Allow. Local reads are
        // milliseconds, so a timeout here means "the prompt is up".
        var testflight = initialTF
        if let tfLoader {
            if let loaded = await Self.firstResult(of: tfLoader, within: .seconds(2)), loaded.accessible {
                testflight = loaded
                let retagged = testflight
                found = await Task.detached(priority: .userInitiated) {
                    AppScanner(extraLocations: extraScan, toolbox: toolbox, testflight: retagged).scan()
                }.value
                results = sorted(mergeScanned(found))
            } else {
                Log.scan.info("TestFlight: read pending (TCC prompt unanswered) — proceeding without it")
                reapplyTestFlightWhenGranted(tfLoader)
            }
        }

        isChecking = true
        let checker = UpdateChecker(
            sources: makeSources(token: await githubToken),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(inventory: toolbox),
            testflight: testflight)
        Log.app.info("refresh: checking \(found.count, privacy: .public) apps")
        let checked = await checker.check(found)
        results = sorted(checked)
        // Pre-warm the disk changelog cache for anything pending, so opening its
        // notes is instant (and a no-op network-wise for versions already cached).
        prewarmChangelogs(for: checked)
        // Log any newly-seen releases (those carrying a real vendor timestamp)
        // into the persistent release timeline.
        await recordReleaseTimeline(for: checked)
        await computeRestartInfo()
        await computeSelfUpdateStaging()
        if prefs.pruneOrphanBackups {
            await Task.detached(priority: .utility) { BackupStore.pruneOrphans() }.value
        }
        await refreshBackupIndex()
        isChecking = false
        lastCheck = .now
        prefs.lastCheckDate = lastCheck  // persist so the scheduler survives relaunches
        // Announce anything newly pending — keyed off a persisted baseline, so it
        // fires no matter which refresh path got here first (background or manual).
        notifyNewUpdates()
        // Force-push (not plain `sync`) so every check re-asserts the badge even when the
        // count is unchanged — otherwise a wiped badge (e.g. after a Dock restart) never
        // comes back, since re-setting the same value is a no-op the Dock skips.
        AppDockBadge.syncSoon(count: badgeCount)
        Log.app.info("refresh done: \(self.updateCount, privacy: .public) updates, \(self.needsRestart.count, privacy: .public) need restart")
    }

    /// True when this update installs seamlessly in place (Sparkle EdDSA, or a
    /// drag-to-Applications Homebrew cask). Excludes `pkg` casks, which need the
    /// system installer — see `requiresInstaller`.
    ///
    /// A Homebrew result only ever reaches us when the app was *actually*
    /// installed via Homebrew (the source gates on the local Caskroom), so
    /// `brew install --cask --force` here updates through the app's real
    /// channel — no cross-channel mixing.
    func canAutoInstall(_ result: UpdateResult) -> Bool {
        // The app's own updater already staged *the latest* for relaunch — installing
        // it ourselves would re-download the same bytes and collide with the pending
        // ShipIt swap. Defer to Relaunch. (A staged build that *trails* the latest
        // isn't actionable as Relaunch, so we still offer Update — a direct jump.)
        if actionableStaged(result) != nil { return false }
        switch result.remote?.sourceName {
        case "Sparkle":
            // Signed feed: the full EdDSA path — needs both the app's SUPublicEDKey
            // and a signature in the item.
            if result.app.sparkleEdPublicKey?.isEmpty == false {
                return result.remote?.edSignature != nil
            }
            // Unsigned feed (no SUPublicEDKey, e.g. Fork): best-effort one-click.
            // `SparkleInstaller` gates the download on code signature + same Team +
            // same bundle id instead of EdDSA (identical to Vendor/GitHub). Offer it
            // only when the enclosure is an archive we can extract and swap in place
            // — a `.pkg` is a system-installer payload, not an in-place archive, and
            // a missing URL leaves nothing to install.
            let ext = result.remote?.downloadURL?.pathExtension.lowercased()
            return ext.map {
                ["dmg", "zip", "gz", "bz2", "xz", "tar", "tbz", "tgz", "app"].contains($0)
            } ?? false
        case "Homebrew":
            return result.remote?.sourceIdentifier != nil
                && result.remote?.requiresManualInstaller == false
        case "Vendor", "GitHub":
            // A vendor-website or GitHub-release app with a resolved installer
            // archive (zip/dmg/tar.gz). We download it, verify the code signature
            // matches the installed app's Team ID, then swap in place — same
            // channel, no mix. GitHub rules without an asset pattern stay
            // detection-only (vendorInstallerKind nil), so they fall through here.
            return result.remote?.vendorInstallerKind != nil
                && result.remote?.requiresManualInstaller == false
        case "App Store":
            // Requires the adamID, and that the app is installable here: not
            // region-locked and not a newer build that dropped Mac support. Both
            // routes replay the store's own download, so it's the app's real update
            // channel — no mixing. Which route depends on the user's preference:
            //   • full        → mas CLI; offered only when mas is actually installed
            //     (else we fall through to the App Store deep link).
            //   • incremental → AX-driven; needs no mas. Accessibility is requested
            //     on demand at install time (mirroring App Management), so we don't
            //     gate the offer on it here.
            // iOS-on-Mac apps (wrapped iPhone/iPad bundles) are never a one-click:
            // `mas` has no Mac-store entry to install (it errors "No apps found for
            // ADAM ID"), and the AX route is too unreliable for them. Only the App
            // Store app itself updates these, so the row offers an "Open in App
            // Store" redirect instead (see the App Store branch in both row views).
            guard let info = result.remote?.appStore,
                  !info.isRegionMismatch, !info.isLatestMacIncompatible,
                  !result.app.isiOSAppOnMac else { return false }
            switch prefs.appStoreUpdateStrategy {
            // `.full` now routes mas through the privileged helper — offered only
            // once the helper is approved (else the row falls back to App Store "Get").
            // Reads the observable mirror so rows re-render the moment it's approved.
            case .full:        return helperEnabled
            case .incremental: return true
            }
        default:
            return false
        }
    }

    /// True when this update is a `pkg` (a `pkg` cask, or a vendor pkg): we
    /// download the official package and open it in the system installer (which
    /// prompts for admin itself).
    ///
    /// For Vendor we key strictly on a `.pkg` install spec — NOT on
    /// `requiresManualInstaller`, which a *detection-only* vendor recipe also
    /// sets (meaning "send the user to download by hand"). Conflating the two
    /// made detection-only apps (LM Studio, Chrome, …) wrongly show an installer
    /// button pointed at their version-check endpoint.
    func requiresInstaller(_ result: UpdateResult) -> Bool {
        // Same as `canAutoInstall`: only a staged build that *is* the latest is
        // relaunch-only; one that trails the latest still gets a normal installer.
        if actionableStaged(result) != nil { return false }
        switch result.remote?.sourceName {
        case "Homebrew":
            return result.remote?.requiresManualInstaller == true
        case "Vendor", "GitHub":
            return result.remote?.vendorInstallerKind == .pkg
        default:
            return false
        }
    }

    /// Whether, per the user's `vendorInstallPolicy`, this update should be handed
    /// to the app's OWN updater rather than installed over by us right now. True for
    /// running self-updating apps when the policy is `.deferWhenRunning`. A
    /// not-running app (nothing to disturb) or the `.alwaysOverwrite` policy installs
    /// in place as usual. Detection-only vendor apps (no installable spec) already
    /// just "Open" their update path, so they're excluded here.
    func defersToSelfUpdater(_ result: UpdateResult) -> Bool {
        guard prefs.vendorInstallPolicy == .deferWhenRunning,
              isRunning(result),
              canAutoInstall(result) || requiresInstaller(result)
        else { return false }
        switch result.remote?.sourceName {
        case "Vendor":
            return true
        case "Sparkle":
            return result.app.sparkleFeedURL != nil
        default:
            return false
        }
    }

    /// Hand a running self-updating app off to its own update path instead of
    /// swapping the bundle under it: open an app-scheme deep link (Chrome's
    /// `chrome://settings/help` makes Keystone check+download) when the recipe
    /// carries one, otherwise just bring the app forward so its built-in updater
    /// (MAU, a daemon, Sparkle) applies the update on its own schedule.
    func openSelfUpdater(_ result: UpdateResult) {
        installErrors[result.id] = nil
        if let url = result.remote?.downloadURL, let scheme = url.scheme,
           scheme != "http", scheme != "https" {
            NSWorkspace.shared.open(
                [url], withApplicationAt: result.app.path,
                configuration: NSWorkspace.OpenConfiguration())
            installNotes[result.id] =
                "Opened \(result.app.name) — its own updater is applying the update."
        } else {
            // Detached from this call so a slow LaunchServices activation doesn't
            // block the main actor (see `launchApp`); the note below is what the
            // user actually waits on, and it lands immediately either way.
            let path = result.app.path
            Task { await Self.launchApp(path) }
            installNotes[result.id] =
                "\(result.app.name) is running — brought it to the front so its own updater applies the update. Quit it (or switch to “Always replace” in Settings) to install directly."
        }
        Log.app.info("defer-to-self-updater: \(result.app.name, privacy: .public)")
    }

    /// A cheap, network-free rescan to run whenever the menu opens. Re-reads each
    /// app from disk and re-evaluates it against the remote we already fetched, so
    /// we notice an app that updated itself in the background (its own Sparkle/
    /// Squirrel/Keystone updater, or brew) — the on-disk version jumps ahead while
    /// the running process stays old. That flips its row to up-to-date AND lets
    /// `computeRestartInfo` surface a Restart badge. No network: the full update
    /// check still runs on first open and on the manual refresh.
    func refreshLocal() async {
        // Don't churn the list while an install is in flight: this rebuilds and
        // re-sorts `results` wholesale, which would reorder/replace the row under
        // an active spinner. Installs key by id and finish fine, but the visible
        // row shouldn't shuffle mid-install. (`installAll` calls `performLocalRescan`
        // directly in its post-batch sweep — installs done, nothing to churn.)
        guard !results.isEmpty, !isChecking, installing.isEmpty, !isInstallingAll else { return }
        await performLocalRescan()
    }

    /// The guard-free body of `refreshLocal`: re-scan disk, re-derive every row's
    /// status against its cached remote (network-free), and refresh the
    /// restart/staging/backup flags. Callers that have already ensured no install is
    /// mid-flight — `refreshLocal` (behind its guard) and `installAll`'s post-batch
    /// sweep — go through here so an app that self-updated externally is re-evaluated
    /// and clears, not just the restart badge.
    private func performLocalRescan() async {
        localRescanDeferred = false
        let extraScan = prefs.customScanLocations
        let found = await Task.detached(priority: .userInitiated) {
            AppScanner(extraLocations: extraScan).scan()
        }.value
        results = sorted(mergeScanned(found))
        await computeRestartInfo()
        await computeSelfUpdateStaging()
        await refreshBackupIndex()
        syncDockBadge()
    }

    /// Re-read a single app from disk and re-derive its row plus the restart/staging
    /// flags — the per-app equivalent of `refreshLocal`, but WITHOUT its
    /// `installing.isEmpty` guard. The wholesale `refreshLocal` deliberately no-ops
    /// while any install is in flight (so it doesn't churn the list under an active
    /// spinner), which means a quit-to-apply action that lands *during* an "Update
    /// All" batch would otherwise have its refresh silently dropped — stranding a
    /// stale "1.x → 1.y / Relaunch" row that never clears (the app is already current
    /// on disk and running the new build, but the row never got re-read). Only the
    /// touched row is replaced here, so the concurrently-installing app's spinner row
    /// is left intact.
    private func refreshRow(_ result: UpdateResult) async {
        let updated = await recheck(result)
        replaceRow(updated)
        await computeRestartInfo()
        await computeSelfUpdateStaging()
    }

    // MARK: - Homebrew formulae (CLI tools)

    /// Re-read outdated CLI formulae via `brew outdated --formula`. A local tap
    /// read (no implicit `brew update`), so it's cheap enough to call on every
    /// popover open. Never throws to the caller — any failure just leaves the list
    /// empty, so no row shows on a clean or brew-less machine.
    func refreshBrewFormulae() async {
        guard BrewFormulaService.isAvailable else {
            brewOutdatedFormulae = []
            brewFormulae = []
            brewChecked = true
            return
        }
        // Phase 1 — fast local inventory: paint the Brew tree immediately with the
        // installed leaves (no update badges yet), mirroring how the Apps tree shows
        // every app before its update check lands. The `await` yields to the runloop,
        // so SwiftUI repaints with the list before phase 2 runs. Best-effort:
        // installedLeaves() returns [] on any brew hiccup.
        brewFormulae = (try? await brewFormulaService.installedLeaves()) ?? []

        // Phase 2 — the slower `brew outdated` read: learn which leaves have an
        // upgrade, then re-stamp the already-shown list so badges appear in place
        // (updates floating to the top). `brewChecked` flips only here, since until
        // outdated returns we don't actually know the update state.
        defer { brewChecked = true }
        do {
            brewOutdatedFormulae = try await brewFormulaService.outdated()
        } catch {
            Log.app.info("brew outdated --formula failed: \(error.localizedDescription, privacy: .public)")
            brewOutdatedFormulae = []
        }
        brewFormulae = BrewFormulaService.merge(brewFormulae, outdated: brewOutdatedFormulae)
        prewarmFormulaReleases()
    }

    /// Warm formula release notes after a brew refresh so selecting an outdated
    /// formula paints instantly instead of spinning on a `brew info` + GitHub fetch.
    /// Rate-limit-aware: a disk-cached version loads for free (no Process, no API
    /// call), but an UNcached formula is fetched up front only when a GitHub token is
    /// present. Without a token the service stays deliberately lazy (on-select) so a
    /// screenful of outdated formulae can't burn the 60/hr unauthenticated budget —
    /// the disk cache still makes every re-select and relaunch instant.
    private func prewarmFormulaReleases() {
        let explicitToken = explicitGitHubToken()
        let tokenTask = Task {
            await Self.resolveGitHubToken(explicit: explicitToken)
        }
        for formula in brewFormulae where formula.hasUpdate {
            guard formulaReleaseStates[formula.name] == nil else { continue }
            let version = formula.availableVersion ?? formula.installedVersion
            // Claim the slot SYNCHRONOUSLY before suspending: the `cached(...)` await
            // below yields the main actor, and a concurrent `ensureFormulaReleaseLoading`
            // (user selecting this formula) would pass its own nil-guard in that window
            // and double-fetch (`brew info` + GitHub) — the redundant work the
            // rate-limit design avoids. `.loading` makes both guards reject.
            formulaReleaseStates[formula.name] = .loading
            Task { [weak self] in
                guard let self else { return }
                if let cached = await self.formulaReleaseService.cached(
                    for: formula.name, version: version) {
                    self.formulaReleaseStates[formula.name] = .loaded(cached)
                } else if await tokenTask.value != nil {
                    // Fetch up front (a token means we have budget). We can't delegate
                    // to `ensureFormulaReleaseLoading` — its own nil-guard would reject
                    // the slot we just claimed — so do the load it would do.
                    let release = await self.formulaReleaseService.release(
                        for: formula.name, version: version, token: await tokenTask.value)
                    self.formulaReleaseStates[formula.name] = .loaded(release)
                } else {
                    // No token and not cached: stay deliberately lazy/on-select so a
                    // screenful of formulae can't burn the 60/hr unauthenticated
                    // budget. Release the claimed slot so a later select can fetch it.
                    self.formulaReleaseStates[formula.name] = nil
                }
            }
        }
    }

    /// Run `brew upgrade --formula` (the bulk action, mirroring a bare terminal
    /// `brew upgrade` but formula-scoped) and refresh the list when it finishes.
    func upgradeBrewFormulae() async {
        guard !brewUpgrading else { return }
        // Don't stack a bulk run on top of in-flight per-row upgrades — both call
        // `brew`, which takes a single global lock; the second would just fail.
        guard upgradingFormulae.isEmpty else { return }
        brewUpgrading = true
        brewUpgradeError = nil
        brewUpgradeNote = "Starting…"
        // Snapshot the target set so dependency formulae brew pulls in (which also
        // emit a 🍺 line) don't inflate the count past the user-visible total.
        let targets = Set(brewOutdatedFormulae.map(\.name))
        brewUpgradeTotal = targets.count
        brewUpgradeDone = 0
        defer { brewUpgrading = false; brewUpgradeNote = nil; brewUpgradeDone = 0; brewUpgradeTotal = 0 }
        do {
            try await brewFormulaService.upgradeAll { [weak self] line in
                Task { @MainActor in
                    self?.brewUpgradeNote = line
                    // One 🍺 Cellar line per poured formula — count only the targeted
                    // ones, clamped so it never reads past the total.
                    if let name = Self.brewPouredFormula(from: line), targets.contains(name),
                       let self, self.brewUpgradeDone < self.brewUpgradeTotal {
                        self.brewUpgradeDone += 1
                    }
                }
            }
            await refreshBrewFormulae()
        } catch {
            brewUpgradeError = error.localizedDescription
        }
    }

    /// Name of the formula a `🍺  /…/Cellar/<name>/<version>: …` success line
    /// reports, or nil for any other line. brew prints exactly one such line per
    /// formula it finishes installing, so counting them tracks bulk progress.
    nonisolated static func brewPouredFormula(from line: String) -> String? {
        guard let range = line.range(of: "/Cellar/") else { return nil }
        let after = line[range.upperBound...]
        guard let slash = after.firstIndex(of: "/") else { return nil }
        let name = String(after[..<slash])
        return name.isEmpty ? nil : name
    }

    /// Upgrade a single formula (`brew upgrade --formula <name>`) — the per-row
    /// action in the workbench Brew list — then re-read the outdated set.
    func upgradeBrewFormula(named name: String) async {
        guard !upgradingFormulae.contains(name) else { return }
        upgradingFormulae.insert(name)
        formulaUpgradeErrors[name] = nil
        formulaUpgradeNotes[name] = "Starting…"
        defer {
            upgradingFormulae.remove(name)
            formulaUpgradeNotes[name] = nil
        }
        do {
            try await brewFormulaService.upgrade(formula: name) { [weak self] line in
                // Map brew's noisy raw output to a clean phase word; ignore lines we
                // don't recognize so the label stays stable instead of flickering
                // through dependency chatter ("✔ Bottle graphite2 …").
                guard let phase = Self.brewUpgradePhase(from: line) else { return }
                Task { @MainActor in self?.formulaUpgradeNotes[name] = phase }
            }
            await refreshBrewFormulae()
        } catch {
            formulaUpgradeErrors[name] = error.localizedDescription
        }
    }

    /// Classify a raw `brew upgrade` output line into a friendly phase, or nil when
    /// it's chatter we'd rather not surface. brew prints download percentages with
    /// carriage returns (not newlines), so a numeric progress bar isn't reliably
    /// available — the phase is the stable signal.
    nonisolated static func brewUpgradePhase(from line: String) -> String? {
        let l = line.lowercased()
        if l.contains("pouring") || l.contains("installing") { return "Installing…" }
        if l.contains("downloading") || l.contains("fetching") || l.contains("bottle") { return "Downloading…" }
        if l.contains("cleaning") || l.contains("cleanup") { return "Cleaning up…" }
        return nil
    }

    /// One-line "x/n" status for an in-flight bulk upgrade — the count of the next
    /// formula being worked on over the total. nil when no bulk run is active.
    var brewBulkProgressText: String? {
        guard brewUpgrading, brewUpgradeTotal > 0 else { return nil }
        let current = min(brewUpgradeDone + 1, brewUpgradeTotal)
        return "Upgrading… (\(current)/\(brewUpgradeTotal))"
    }

    /// Fetch a formula's release notes once, on first selection. Idempotent: a
    /// loaded/loading entry is left alone, so reselecting renders the cache instantly.
    func ensureFormulaReleaseLoading(name: String, version: String) {
        guard formulaReleaseStates[name] == nil else { return }
        formulaReleaseStates[name] = .loading
        let explicitToken = explicitGitHubToken()
        Task {
            let token = await Self.resolveGitHubToken(explicit: explicitToken)
            let release = await formulaReleaseService.release(for: name, version: version, token: token)
            formulaReleaseStates[name] = .loaded(release)
        }
    }

    /// Merge a fresh disk scan onto the current rows, carrying each app's prior
    /// status/remote forward (re-evaluated against the new on-disk version) so a
    /// rescan doesn't blank out what we already knew. Shared by `refreshLocal` (the
    /// network-free rescan) and the in-flight `performRefresh` (so the sidebar holds
    /// the menu bar's data instead of flashing `.unknown` rows during a re-check).
    /// Apps new since the last scan come in as `.unknown`.
    private func mergeScanned(_ found: [InstalledApp]) -> [UpdateResult] {
        let prior = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return found.map { app -> UpdateResult in
            guard let was = prior[app.id] else {
                return UpdateResult(app: app, remote: nil, status: .unknown)
            }
            // Re-derive status from the cached remote against the fresh on-disk
            // version. With no remote (App Store / Toolbox / unknown) keep what we
            // had, just refreshed to the new bundle info.
            guard let remote = was.remote else {
                return UpdateResult(app: app, remote: nil, status: was.status)
            }
            // A Toolbox row can't be re-run through `evaluate` (its verdict is a
            // Toolbox build compare, not a compare against `shortVersion`), but it
            // must still settle when Toolbox installs the update itself between our
            // checks — otherwise the cached "update available" stands beside the
            // freshly-rescanned version, reading "262.132.21 → 262.132.21".
            if remote.sourceName == "Toolbox" {
                return UpdateResult(
                    app: app, remote: remote,
                    status: UpdateChecker.evaluateToolbox(
                        cached: was.status, installed: app, remote: remote))
            }
            // TestFlight owns its betas' status (its own cache, not a version
            // compare) — keep it; don't re-evaluate.
            guard remote.sourceName != "TestFlight" else {
                return UpdateResult(app: app, remote: remote, status: was.status)
            }
            return UpdateResult(
                app: app, remote: remote,
                status: UpdateChecker.evaluate(installed: app, remote: remote))
        }
    }

    /// Update one app's install stage, coalescing download progress to whole
    /// percent. A `URLSession` download fires `didWriteData` dozens of times per
    /// second; each write would otherwise mutate `installing` and re-render every
    /// row (the dictionary invalidates as a whole). Skipping same-percent ticks
    /// cuts that churn by ~50× and removes the visible jitter when several apps
    /// download at once.
    private func setStage(_ id: String, _ stage: InstallStage) {
        // Progress callbacks dispatch un-awaited onto the main actor, so a late tick
        // can land after the install finished and cleared `installing[id]`. Resurrecting
        // a stale stage here would re-show a phantom row and wedge the re-entrancy
        // guard (`installing[id] == nil`). Every real stage is preceded by a direct
        // `installing[id] = …` assignment, so a nil here means the install is over.
        guard installing[id] != nil else { return }
        if case .downloading(let f) = stage,
           case .downloading(let prev)? = installing[id],
           Int(f * 100) == Int(prev * 100) {
            return  // same whole percent — nothing the user can see changed
        }
        installing[id] = stage
    }

    /// Flash an "Updated ✓" confirmation on a just-completed row, then let it go.
    /// The row keeps showing in `visible` while its id is here; after a short beat we
    /// drop it, at which point the (now up-to-date) app filters out of the list
    /// normally. Idempotent re-entry just restarts the window.
    private func markJustUpdated(_ id: String) {
        justUpdated.insert(id)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.justUpdated.remove(id)
        }
    }

    /// Install an update, routing to the right installer for its source. `notify`
    /// is false for the batch path so "Update All" posts one summary banner
    /// instead of one per app. Returns true only when a bundle was actually
    /// installed (not when the app turned out already-current, or an early-out/
    /// error path was taken) so the batch summary count is exact.
    ///
    /// The per-app "updated"/"ready to restart" banners are NOT gated on
    /// `prefs.notifyOnUpdates`: that setting governs unsolicited *background*
    /// discovery alerts, whereas these are direct feedback for an install the user
    /// just clicked. The batch path opts out via `notify: false` instead.
    ///
    /// `deferBookkeeping` (batch only) skips the shared post-install sweep —
    /// restart info (`lsappinfo`), self-update staging, backup index — which is
    /// independent of *which* app just installed. Run per app inside a sequential
    /// "Update All", each finished row would sit at 100% while that sweep (an
    /// `lsappinfo` call that can stall right after we relaunch apps) blocked the
    /// next install from starting. `installAll` runs it once after the whole batch.
    @discardableResult
    func install(_ result: UpdateResult, notify: Bool = true, deferBookkeeping: Bool = false) async -> Bool {
        let id = result.id
        // Re-entrancy / cross-path guard (matches `retry`): the popover "Update
        // anyway" button and the major-upgrade badge aren't disabled while an install
        // is in flight, so a double-click — or a manual click racing "Update All" for
        // the same app — could otherwise launch two concurrent installs (two
        // downloads, two in-place swaps, two notifications). Claim the id *before* any
        // await so whoever sets `.queued` first wins and the loser returns false.
        // `installAll` pre-claims all its targets, so a manual click on a queued batch
        // row no-ops here and the row keeps its spinner instead of a live button.
        guard installing[id] == nil else { return false }
        // Re-initiating clears a prior attempt's error/note right away, so a re-clicked
        // row shows a clean "Queued" spinner — not last failure's red error text
        // sitting beside it. (Otherwise the error only clears later in `performInstall`,
        // once this row's turn at the gate comes up — long after the re-click if it's
        // queued behind another install, as an App Store row is behind the single-slot
        // store gate.)
        installErrors[id] = nil
        installNotes[id] = nil
        installing[id] = .queued
        return await runInstall(result, notify: notify, deferBookkeeping: deferBookkeeping)
    }

    /// Gate-wait, then install a row whose `installing[id] == .queued` claim the
    /// caller has ALREADY made — `install` for a single click, `installAll` for a
    /// batch it pre-queued. Splitting the claim from the work lets the batch mark
    /// every target `.queued` up front (so each shows a queued spinner at once and
    /// the re-entrancy guard blocks a manual click) while the gates here still pace
    /// the actual installs.
    private func runInstall(_ result: UpdateResult, notify: Bool, deferBookkeeping: Bool) async -> Bool {
        let id = result.id
        // Bound *total* concurrent installs across every entry point through one
        // global gate: "Update All" and each manual row click queue through the
        // same permits, so a wave of clicks (or a batch overlapping manual clicks)
        // can't all fire at once — saturating the network, thrashing the disk, and
        // stacking several privileged-swap auth prompts. The row was marked `.queued`
        // by the caller before this suspension point, so the UI already shows the wait
        // and the re-entrancy guard already rejects re-clicks; here we just park until
        // a slot frees (the semaphore is FIFO).
        //
        // Per-host sub-cap: several apps that download from the *same* host (GitHub
        // releases, one vendor CDN) would otherwise split that host's bandwidth and
        // are the most likely to trip its rate limiter / WAF. Acquired *before* the
        // global permit so a saturated host parks here without burning a global slot
        // (which would starve apps on other, idle hosts).
        //
        // App Store rows are special-cased to a dedicated single-slot gate instead:
        // they drive the one App Store UI (AX/mas), so two at once would fight over
        // it — and `MacAppStoreSource` gives them `apps.apple.com` as a `downloadURL`
        // host, which would otherwise let two share the per-host cap of 2. Homebrew
        // *does* carry a real `downloadURL` host (the cask's source CDN), so it still
        // takes a host gate as a coarse limiter even though brew fetches the bytes.
        let gate: AsyncSemaphore? = result.remote?.sourceName == "App Store"
            ? Self.appStoreInstallGate
            : result.remote?.downloadURL?.host.map(hostInstallGate(for:))
        await gate?.wait()
        await Self.installGate.wait()
        // A queued item cancelled while waiting — e.g. "Update All" was stopped
        // before this row's turn came up — releases its slots and clears its claim
        // without installing. (`installAll`'s cleanup also sweeps any claim that never
        // reached here at all.)
        if Task.isCancelled {
            installing[id] = nil
            await Self.installGate.signal()
            await gate?.signal()
            return false
        }
        // `performInstall` catches all its own errors and always returns, so both
        // permits are guaranteed to recycle here.
        let didInstall = await performInstall(result, notify: notify, deferBookkeeping: deferBookkeeping)
        await Self.installGate.signal()
        await gate?.signal()
        // If something self-updated externally while this install ran, its rescan was
        // deferred — drain it now that the install is done (no-op in a batch, which
        // drains once at the end of `installAll`, and when nothing was deferred).
        await drainDeferredLocalRescan()
        return didInstall
    }

    @discardableResult
    private func performInstall(_ result: UpdateResult, notify: Bool, deferBookkeeping: Bool) async -> Bool {
        let id = result.id
        installErrors[id] = nil
        installNotes[id] = nil
        Log.install.info("install start: \(result.app.name, privacy: .public) \(result.app.shortVersion ?? "?", privacy: .public) → \(result.remote?.displayVersion ?? "?", privacy: .public) via \(result.remote?.sourceName ?? "?", privacy: .public)")

        // Defensive re-check: the app may already be current — e.g. a manual
        // pkg install we couldn't observe, or it was updated by its own updater
        // since the last scan. Re-read it from disk and re-query before we
        // download or replace anything.
        installing[id] = .checking
        let result = await recheck(result)
        replaceRow(result)
        guard result.hasUpdate else {
            // Already current on disk — but the running instance may predate
            // that update, so recompute whether a restart is needed.
            Log.install.info("install skipped: \(result.app.name, privacy: .public) already current on disk")
            await computeRestartInfo()
            installing[id] = nil
            return false
        }

        // Install policy: a running self-updating app is handed to its own
        // updater rather than swapped under it — unless the user chose to always
        // overwrite. (Re-checked here, not just in the UI, so any caller honors it.)
        // Re-derive the live running set first: `runningAppPaths` is only updated by
        // NSWorkspace launch/terminate notifications, which aren't delivered while
        // this menu-bar app is App-Napped — so a quit that happened during a nap can
        // leave the set stale and make `isRunning` (and thus this defer) lie. This is
        // a consequential decision, so base it on the live process list, not a cache.
        refreshRunningApps()
        if defersToSelfUpdater(result) {
            Log.install.info("install deferred to self-updater: \(result.app.name, privacy: .public) (running, policy=deferWhenRunning)")
            openSelfUpdater(result)
            installing[id] = nil
            return false
        }

        // Back up the current bundle first (when enabled) so this update can be
        // rolled back. Only for in-place swaps we perform ourselves — Homebrew and
        // pkg installs go through their own tools and manage their own state.
        // App Store apps are excluded: mas re-downloads through the store, which
        // can always re-fetch the prior build, so a local backup is dead weight.
        if prefs.keepBackups, canAutoInstall(result), !requiresInstaller(result),
           result.remote?.sourceName != "App Store" {
            await backupCurrent(result)
        }

        do {
            // pkg casks: download the official installer and open it. The
            // actual install happens in macOS's installer under the user's
            // control, so we don't mark it up to date — a later rescan will.
            if requiresInstaller(result) {
                installing[id] = .downloading(fraction: 0)
                let bytes = try await packageInstaller.downloadAndOpen(
                    url: result.remote?.downloadURL,
                    installedApp: result.app.path,
                    headers: result.remote?.downloadHeaders ?? [:]
                ) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
                await recordTraffic(result, bytes: bytes)
                installing[id] = nil
                return true
            }

            switch result.remote?.sourceName {
            case "Homebrew":
                // Reset the spinner on this early-out too: with the re-entrancy
                // guard above, a stuck `installing[id]` would otherwise block every
                // future install/retry for this app permanently.
                guard let token = result.remote?.sourceIdentifier else {
                    installing[id] = nil
                    return false
                }
                installing[id] = .runningCommand("starting brew…")
                // brew performs its own download, so we never see those bytes —
                // intentionally not recorded (we only count what we measured).
                try await homebrewInstaller.upgrade(caskToken: token) { line in
                    Task { @MainActor in self.setStage(id, .runningCommand(line)) }
                }
            case "App Store":
                // iOS-on-Mac apps can only be updated by the App Store app itself
                // (mas has no Mac-store entry; the AX route is unreliable for them).
                // `canAutoInstall` already keeps them out of the one-click button and
                // Install-All, but guard here too so any other caller redirects to the
                // store instead of firing a doomed `mas` install.
                if result.app.isiOSAppOnMac {
                    installing[id] = nil
                    if let url = result.remote?.appStore?.deepLink { NSWorkspace.shared.open(url) }
                    return false
                }
                // Reset the spinner on this early-out too (see Homebrew above) so a
                // missing adamID can't wedge every future install for this app.
                guard let adamID = result.remote?.appStore?.trackID else {
                    installing[id] = nil
                    return false
                }
                installing[id] = .downloading(fraction: 0)
                // Both routes download through the App Store daemon, so we never see
                // those bytes — intentionally not recorded (we only count measured).
                if result.remote?.appStore?.isRegionMismatch == true {
                    // Region-locked app (listed in a storefront other than the signed-in
                    // account's). mas can't fetch it (wrong storefront) and its product
                    // page is "App Not Available" — but an *already-installed* one still
                    // appears in App Store's Updates list and updates fine from there.
                    // So this is AX-only (via `showUpdatesPage`), regardless of the
                    // full/incremental preference, and there's no mas fallback. If the
                    // store hasn't surfaced the update into the list yet, the installer
                    // throws `.notInUpdatesList`, shown as a "try again later" hint.
                    guard AppStoreAXInstaller.isTrusted else {
                        installing[id] = nil
                        installErrors[id] = AppStoreAXInstaller.AXError.notTrusted.errorDescription
                        presentAccessibilityPermissionFlow()
                        return false
                    }
                    try await appStoreAXInstaller.update(
                        trackID: adamID,
                        appPath: result.app.path,
                        bundleID: result.app.bundleID,
                        appName: result.app.name,
                        currentShortVersion: result.app.shortVersion,
                        viaUpdatesList: true
                    ) { stage in
                        Task { @MainActor in self.setStage(id, stage) }
                    } confirmQuit: { [weak self] appName in
                        await self?.requestQuitConfirmation(id: id, appName: appName) ?? false
                    }
                } else {
                    // Pre-flight before we drive the store: the row may have gone current
                    // since the install-time re-check ran — the App Store's own background
                    // updater can land the update while this row waits its turn at the
                    // single-slot store gate. If the bundle on disk is already at the target
                    // AND `mas` (the authority on what a force-reinstall could actually
                    // fetch) doesn't list it as outdated, there's nothing to install: skip
                    // the doomed `mas install --force` / AX redrive before downloading
                    // anything, and settle the row to up-to-date.
                    //
                    // Fail-safe by construction: the on-disk check gates the skip, so a
                    // flaky or silently-empty `mas outdated` (it has been unreliable across
                    // macOS releases) can NEVER suppress a genuinely-behind update. `mas`
                    // may only VETO the skip by listing the app as outdated (`!= true`);
                    // "not outdated" and "couldn't check" (nil) both defer to the on-disk
                    // verdict. And because that on-disk gate is evaluated first, `mas
                    // outdated` runs only in the already-current case — never slowing a real
                    // update, and never firing for a user without mas (nil → skip on disk).
                    if let target = result.remote?.displayVersion,
                       let onDisk = Self.readShortVersion(result.app.path),
                       !VersionComparator.isNewer(target, than: onDisk),
                       await masInstaller.outdatedContains(adamID: adamID) != true {
                        Log.install.notice("App Store: \(result.app.name, privacy: .public) already current (on-disk \(onDisk, privacy: .public) ≥ target \(target, privacy: .public), not outdated per mas) — skipping install before download")
                        await refreshRow(result)
                        installing[id] = nil
                        return false
                    }
                    switch prefs.appStoreUpdateStrategy {
                    case .full:
                        try await masInstaller.install(adamID: adamID) { stage in
                            Task { @MainActor in self.setStage(id, stage) }
                        }
                    case .incremental where AppStoreAXInstaller.isTrusted:
                        try await appStoreAXInstaller.update(
                            trackID: adamID,
                            appPath: result.app.path,
                            bundleID: result.app.bundleID,
                            appName: result.app.name,
                            currentShortVersion: result.app.shortVersion
                        ) { stage in
                            Task { @MainActor in self.setStage(id, stage) }
                        } confirmQuit: { [weak self] appName in
                            await self?.requestQuitConfirmation(id: id, appName: appName) ?? false
                        }
                    case .incremental where MASInstaller.isAvailable:
                        // Incremental is selected but Accessibility isn't granted (the
                        // user declined the opt-in prompt, or revoked it later). There's
                        // no "denied" callback from the TCC flow, so we resolve it here,
                        // at use time: don't fail the update — fall back to the full (mas)
                        // route this once, and guide the user to grant Accessibility (once
                        // per session, so we don't nag) so the next update can go
                        // incremental. We deliberately leave the *setting* on incremental:
                        // it self-heals to the delta route as soon as access is granted.
                        Log.install.notice("App Store incremental without Accessibility — using mas this time: \(result.app.name, privacy: .public)")
                        guideAccessibilityOncePerSession()
                        try await masInstaller.install(adamID: adamID) { stage in
                            Task { @MainActor in self.setStage(id, stage) }
                        }
                    case .incremental:
                        // Incremental, no Accessibility, and no mas to fall back to — we
                        // can't update at all. Surface the need and guide to the grant;
                        // the row's retry picks up once access is granted.
                        installing[id] = nil
                        installErrors[id] = AppStoreAXInstaller.AXError.notTrusted.errorDescription
                        presentAccessibilityPermissionFlow()
                        return false
                    }
                }
            case "Vendor", "GitHub":
                installing[id] = .downloading(fraction: 0)
                let bytes = try await vendorInstaller.install(result) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
                await recordTraffic(result, bytes: bytes)
            default:
                installing[id] = .downloading(fraction: 0)
                let bytes = try await sparkleInstaller.install(result) { stage in
                    Task { @MainActor in self.setStage(id, stage) }
                }
                await recordTraffic(result, bytes: bytes)
            }
            // An incremental App Store update the user OK'd quitting for: the app
            // was open before we quit it to update, so bring it back — and to the
            // front (the user clicked Relaunch; they expect to see it return, not a
            // silent background relaunch). Apps that weren't running never enter
            // `reopenAfterQuit`, so this only reopens what we closed. Done before the
            // recheck so the running-version probe sees the relaunched process.
            reopenIfQuitForUpdate(id: id, path: result.app.path)

            // Re-read from disk to reflect the new version, then recompute the
            // Restart flag by comparing each running instance's launch version
            // to what's now on disk. In-place installs (Homebrew) leave the old
            // process running stale code; Sparkle relaunches, so it won't show.
            let updated = await recheck(result)
            // The bundle was replaced in place (same path); drop its cached icon so
            // the row re-reads the new one instead of showing the old until restart.
            AppIconCache.invalidate(updated.app.path.path)
            // The version on disk just changed, so the changelog the workbench has
            // cached describes the *old* release — expire it (both layers) so the
            // next detail-window open re-fetches notes for the build we just landed.
            invalidateChangelog(forBundleID: updated.app.bundleID)
            replaceRow(updated)
            // In a batch, this shared sweep is deferred to once after the loop (see
            // `installAll`) so each row clears at 100% immediately instead of holding
            // the next install behind a per-app `lsappinfo`/staging/backup pass.
            if !deferBookkeeping {
                await computeRestartInfo()
                await computeSelfUpdateStaging()
                await refreshBackupIndex()
            }

            // Tell the user it landed. If the app was running, its live process
            // is still on the old code (so it's in needsRestart) — point them at
            // the Restart action. Otherwise the in-place swap is already fully in
            // effect and there's nothing left to do.
            let version = updated.app.shortVersion
            if needsRestart.contains(updated.id) {
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public) on disk, awaiting restart")
                if notify { UpdateNotifier.readyToRestart(app: updated.app.name, version: version, appID: updated.app.bundleID) }
                // Finish the job the user started: a one-click Update shouldn't leave
                // a second "Restart" click dangling. Auto-restart unless the user
                // opted out. In a batch we skip here and let `installAll` restart the
                // whole set once at the end (so parallel installs don't quit apps out
                // from under each other mid-run). `restart()` is graceful — it honors
                // save prompts and leaves the badge if the app won't quit.
                if prefs.autoRestartAfterUpdate, !deferBookkeeping {
                    await restart(updated)
                }
            } else {
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public)")
                if notify { UpdateNotifier.updated(app: updated.app.name, version: version) }
                // The swap is fully in effect and nothing is left to do, so this row is
                // about to filter out of the list. Hold it briefly with an "Updated ✓"
                // confirmation (see `visible`/`trailing`) so completion is legible
                // instead of the row just disappearing mid-progress.
                markJustUpdated(id)
            }
        } catch let error as AppManagementRequiredError {
            // The swap was blocked by the App Management privacy gate. There's no
            // API to request it, so guide the user to the right Settings pane with
            // the drag-to-authorize panel; the install can be retried once granted.
            Log.install.error("install blocked by App Management: \(result.app.name, privacy: .public)")
            installErrors[id] = error.errorDescription
            presentAppManagementPermissionFlowForInstallFailure()
        } catch {
            // A failed *App Store* install whose bundle is ALREADY at the target
            // version isn't a real failure — it's a no-op reinstall the store tooling
            // rejected. The canonical case: the row went stale because the app updated
            // out of band (an App Store background update, or the user updating it in
            // App Store) after we listed it — or the store updated it mid-install,
            // racing our own attempt. `mas install --force` then re-downloads the
            // current build and macOS's installer refuses to "upgrade" it over the same
            // version ("installer: The upgrade failed", exit 1); the AX route dead-ends
            // the same way (the offer button reads "Open", the press no-ops, we time
            // out). Surfacing that alarming red error for an app that's actually current
            // is wrong, so re-check the row instead — it settles to up-to-date and drops
            // out of the list. The `!isNewer(target, onDisk)` guard keeps a genuine
            // failure (bundle still behind the target) on the normal error path below.
            if result.remote?.sourceName == "App Store",
               let target = result.remote?.displayVersion,
               let onDisk = Self.readShortVersion(result.app.path),
               !VersionComparator.isNewer(target, than: onDisk) {
                Log.install.notice("install: \(result.app.name, privacy: .public) reported a failure but is already at \(onDisk, privacy: .public) on disk (target \(target, privacy: .public)) — treating as already-current, clearing the stale row")
                reopenIfQuitForUpdate(id: id, path: result.app.path)
                relaunching.remove(id)
                await refreshRow(result)  // re-scan + re-check → up-to-date, error-free
                installing[id] = nil       // clear the spinner last, matching the skip path
                return false
            }
            Log.install.error("install failed: \(result.app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            installErrors[id] = error.localizedDescription
        }
        // If an AX App Store update quit the app but then threw before the swap
        // landed (e.g. timed out, or App Store raised an unexpected sheet), Continue
        // already closed it and won't reopen it — so reopen it ourselves here too,
        // not only on the success path above. Idempotent: the success path removed
        // it from `reopenAfterQuit`, so this no-ops there.
        reopenIfQuitForUpdate(id: id, path: result.app.path)
        installing[id] = nil
        // Drop the "Relaunching…" indicator a confirmed App Store quit raised, on
        // every exit (success or error) so a failed/cancelled install can't strand it.
        relaunching.remove(id)
        // True only if we reached the install path without throwing.
        return installErrors[id] == nil
    }

    /// True when the row's install error is the mas receipt-import dead end — mas
    /// can't finish it (a macOS/CommerceKit limitation), so the row offers a manual
    /// jump to the App Store's Updates page instead of just showing the red note.
    func showsAppStoreUpdatesFallback(_ id: String) -> Bool {
        installErrors[id]?.contains(MASInstaller.MASError.appStoreUpdatesHint) == true
    }

    /// Open the App Store's Updates list, where the user can finish an update mas
    /// couldn't. User-initiated (no focus steal from us).
    func openAppStoreUpdatesPage() {
        if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
    }

    /// Flag apps whose running instance launched with an older build than
    /// what's now on disk — reliably, by reading the live launch version from
    /// LaunchServices (`lsappinfo`), which is cached at launch and so differs
    /// from the on-disk Info.plist after an update. Covers our own installs,
    /// the app's own updater, and brew — across app restarts.
    private func computeRestartInfo() async {
        let running = await Self.runningBuildVersions()
        var ids: Set<String> = []
        var versions: [String: String] = [:]
        var recovered: [String: String] = [:]
        let history = prefs.marketingByBuild
        // Rebuilt from scratch each scan, then persisted — so it stays pruned to
        // builds that currently matter (the on-disk build of every install, plus any
        // still-running pre-update build) and never accumulates dead entries.
        var freshHistory: [String: String] = [:]
        for result in results {
            // Match on the resolved bundle path, not bundle id: a row whose exact
            // .app isn't running must not pick up a channel sibling's running
            // version (Android Studio Preview vs Stable share one bundle id).
            let runKey = result.app.path.resolvingSymlinksInPath().path
            // Remember the marketing version this on-disk build carries, so that
            // AFTER a future self-update — when only the build survives in the running
            // process (via `lsappinfo`) — we can still name the version it launched
            // with. Keyed by build, so the new build's entry never clobbers the old.
            if let diskBuild = result.app.buildVersion, let marketing = result.app.shortVersion {
                freshHistory[Preferences.marketingByBuildKey(path: runKey, build: diskBuild)] = marketing
            }
            guard let runVersion = running[runKey],
                  let disk = result.app.buildVersion ?? result.app.shortVersion,
                  VersionComparator.isNewer(disk, than: runVersion) else { continue }
            // Always record the lagging running version — even for a row that
            // also has a newer update pending — so the update row can show it as
            // "current". The Restart badge, though, only makes sense when there's
            // nothing newer to install: an update-available row shows Update and
            // installing it re-triggers the restart prompt afterward.
            versions[result.id] = runVersion
            // Recover the running build's marketing version from a scan taken before
            // the swap, and keep that entry alive in the pruned history until the
            // restart is resolved. Absent only when we never scanned the old build
            // (the app updated while we weren't running) — then the line falls back
            // to the bare build in `restartFromVersion`.
            let runHistoryKey = Preferences.marketingByBuildKey(path: runKey, build: runVersion)
            if let runMarketing = history[runHistoryKey] {
                recovered[result.id] = runMarketing
                freshHistory[runHistoryKey] = runMarketing
            }
            if !result.hasUpdate { ids.insert(result.id) }
        }
        needsRestart = ids
        runningVersionByID = versions
        recoveredRestartMarketing = recovered
        // Guard against an empty/partial pass wiping the persisted history before a
        // real scan has populated `results`.
        if !results.isEmpty, freshHistory != history {
            prefs.setMarketingByBuild(freshHistory)
        }
        // Re-sort: a row that just flipped to needs-restart should move up into
        // the actionable tier rather than stay wherever it last sorted.
        results = sorted(results)
    }

    /// Flag apps whose own updater has downloaded and staged a newer build (the
    /// "Relaunch to update" state) that hasn't been swapped in yet — Squirrel's
    /// ShipIt cache, plus vendors with their own staging layout (Spotify). Reads
    /// each candidate's staging area off-main — pure filesystem work, but enough of
    /// it (a plist/json parse per candidate) to keep off the main actor.
    private func computeSelfUpdateStaging() async {
        // Track which apps were surfacing a *Relaunch* (actionable staged = the
        // staged build is the latest) so we can clear their banner if they stop —
        // applied, staging gone, OR a newer release now makes the staged build trail.
        let previouslyActionable = Set(results.compactMap { actionableStaged($0) != nil ? $0.id : nil })
        let apps = results.map(\.app).filter(SelfUpdaterStaging.mayHaveStaging)
        let staged = await Task.detached(priority: .utility) {
            var map: [String: StagedSelfUpdate] = [:]
            for app in apps {
                if let s = SelfUpdaterStaging.staged(for: app) { map[app.id] = s }
            }
            return map
        }.value
        pendingSelfUpdate = staged
        // Dismiss delivered "Relaunch to apply it" banners for apps that are no
        // longer actionable-staged, so a stale one doesn't linger.
        let nowActionable = Set(results.compactMap { actionableStaged($0) != nil ? $0.id : nil })
        for id in previouslyActionable.subtracting(nowActionable) {
            UpdateNotifier.clearSelfDownloaded(appID: id)
        }
        if !nowActionable.isEmpty {
            let names = results.filter { nowActionable.contains($0.id) }
                .map { "\($0.app.name)→\(pendingSelfUpdate[$0.id]!.version)" }.joined(separator: ", ")
            Log.app.info("self-update staged (relaunch pending): \(names, privacy: .public)")
        }
        // Move any actionable-staged row into the actionable tier (rank 0).
        results = sorted(results)
        // Start (or stop) the periodic relaunch reminder to match what's actionable.
        updateSelfUpdateReminder()
    }

    /// True when any row is surfacing a Relaunch (its staged build is the latest).
    private var hasActionableStaged: Bool {
        results.contains { actionableStaged($0) != nil }
    }

    /// Keep the periodic self-update reminder in sync with `pendingSelfUpdate`:
    /// run a loop while anything is staged, tear it down when nothing is. The loop
    /// nudges immediately on first detection, then re-nudges every
    /// `selfUpdateReminderInterval` so a staged build the user glanced at but didn't
    /// act on resurfaces instead of being forgotten. Each app's banner uses a stable
    /// identifier, so a re-nudge replaces the prior one rather than piling up.
    private func updateSelfUpdateReminder() {
        guard hasActionableStaged else {
            selfUpdateReminder?.cancel()
            selfUpdateReminder = nil
            return
        }
        guard selfUpdateReminder == nil else { return }  // already nudging
        selfUpdateReminder = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.prefs.notifyOnUpdates else { self.selfUpdateReminder = nil; return }
                for result in self.results {
                    // Only nudge "relaunch to apply X" when X is actually the latest —
                    // a staged build that trails a newer release goes through the
                    // normal updates-available path instead.
                    guard let staged = self.actionableStaged(result) else { continue }
                    UpdateNotifier.selfDownloaded(
                        app: result.app.name, version: staged.version, appID: result.id)
                }
                try? await Task.sleep(for: self.selfUpdateReminderInterval)
                if !self.hasActionableStaged { self.selfUpdateReminder = nil; return }
            }
        }
    }

    /// Relaunch the app named by a notification's Relaunch action.
    ///
    /// A delivered banner can outlive the condition that posted it: between the
    /// nudge and the tap the user may have applied the update another way (the
    /// app's own "Relaunch to update", a manual quit/reopen) or updated it
    /// manually. Acting on that stale banner would needlessly quit a now-current
    /// app. So we re-read disk first (`refreshLocal` recomputes `pendingSelfUpdate`
    /// and `needsRestart` from the fresh on-disk version, and clears the banner if
    /// it's been applied), then only restart if it's *still* pending.
    func restart(byID id: String) async {
        await refreshLocal()
        guard let result = results.first(where: { $0.id == id }) else {
            UpdateNotifier.clearSelfDownloaded(appID: id)  // gone from the scan — drop the banner
            return
        }
        if actionableStaged(result) != nil {
            await relaunchStagedUpdate(result)   // staged IS latest: let ShipIt apply it
        } else if needsRestart.contains(id) {
            await restart(result)                // our/brew install: we reopen
        } else {
            // No longer actionable — applied since the banner was posted, or a newer
            // release now makes the staged build trail (handled via the Update path).
            // Either way clear the stale banner and don't relaunch to an old build.
            UpdateNotifier.clearSelfDownloaded(appID: id)
            Log.app.info("restart(byID): \(result.app.name, privacy: .public) no longer actionable-staged — stale banner cleared")
        }
    }

    /// Map of symlink-resolved bundle path → the build version each running app
    /// launched with, parsed from `lsappinfo list` (one call for all running apps).
    ///
    /// Keyed by *path*, not bundle id, on purpose: channel siblings like Android
    /// Studio Preview and Stable share one bundle id (`com.google.android.studio`),
    /// so a bundle-id map would let a *non-running* Preview inherit the running
    /// Stable's version — and since Preview's build is higher, falsely flag Preview
    /// as needing a restart, then strand the Restart click trying to quit Stable.
    ///
    /// Runs entirely off the main actor: `lsappinfo` talks to `coreservicesd`
    /// and can be slow or hang — most acutely right after we terminate and
    /// relaunch a batch of apps during an install. Blocking `@MainActor` here
    /// froze the whole UI (spin report) and stranded the half-restarted app.
    nonisolated private static func runningBuildVersions() async -> [String: String] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lsappinfo")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            // nullDevice, not Pipe(): an undrained stderr pipe deadlocks once
            // its 64KB buffer fills — lsappinfo blocks writing, we block in
            // waitUntilExit(), forever.
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return [:] }

            // Timeout backstop so a wedged lsappinfo can't hang us indefinitely.
            // SIGTERM first; if it's ignored (a wedged process can hold stdout's
            // write end open, so the blocking read below would never return),
            // escalate to SIGKILL, which the kernel can't refuse — that closes the
            // pipe and unblocks the read for sure.
            let pid = process.processIdentifier
            let term = DispatchWorkItem { process.terminate() }
            let kill = DispatchWorkItem { Foundation.kill(pid, SIGKILL) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: term)
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: kill)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            term.cancel()
            kill.cancel()
            guard let text = String(data: data, encoding: .utf8) else { return [:] }

            var map: [String: String] = [:]
            var current: String?
            for line in text.split(separator: "\n") {
                if let path = quotedValue(after: "bundle path", in: line) {
                    // Resolve symlinks to line up with how `AppScanner` records
                    // `InstalledApp.path` (and `computeRestartInfo`'s lookup key).
                    current = runtimeBundlePath(URL(fileURLWithPath: path))
                } else if let cur = current, map[cur] == nil,
                          let version = quotedValue(after: "Version", in: line) {
                    map[cur] = version
                }
            }
            return map
        }.value
    }

    /// Extract the value of a `key="value"` pair from a line.
    nonisolated private static func quotedValue(after key: String, in line: Substring) -> String? {
        guard let start = line.range(of: key + "=\"") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    /// The running instances launched from *this exact .app*, not just any app
    /// sharing its bundle id. Channel siblings (Android Studio Preview/Stable,
    /// etc.) share one bundle id, so terminating "all with this bundle id" would
    /// also kill the sibling we never meant to touch — and the quit-wait below
    /// would never see the set empty (the sibling stays up), stranding the spinner.
    private func runningInstances(of result: UpdateResult) -> [NSRunningApplication] {
        let target = Self.runtimeBundlePath(result.app.path)
        let candidates = result.app.bundleID.map {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        } ?? NSWorkspace.shared.runningApplications
        return candidates.filter { app in
            guard let bundleURL = app.bundleURL else { return false }
            return Self.runtimeBundlePath(bundleURL) == target
        }
    }

    /// Quit the stale running instance and relaunch it so the new version takes
    /// effect. Graceful only — if it won't quit (unsaved work), we leave it and
    /// keep the Restart prompt for the user to retry.
    func restart(_ result: UpdateResult) async {
        guard let bundleID = result.app.bundleID else { return }
        // Block re-entry and show the in-flight spinner (the `relaunching`
        // indicator replaces the button): the quit→wait→reopen takes a beat, and
        // without feedback the click reads as "nothing happened" even though it
        // worked. A second click would otherwise fire a second quit.
        guard !relaunching.contains(result.id) else { return }
        relaunching.insert(result.id)
        defer { relaunching.remove(result.id) }
        Log.app.info("restart: \(result.app.name, privacy: .public) [\(bundleID, privacy: .public)]")
        let running = runningInstances(of: result)
        guard !running.isEmpty else { needsRestart.remove(result.id); return }
        for app in running { app.terminate() }
        // Wait up to ~30s for a graceful quit. A heavy app (large workspace) can take
        // well over the old 6s to actually exit; bailing early would leave it
        // terminated-but-not-relaunched — i.e. we asked it to quit and then never
        // brought it back. The only case we intentionally give up on is a genuine
        // hang/save-prompt, where the app stays *up* (so it's never stranded down).
        for _ in 0..<150 {
            if runningInstances(of: result).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard runningInstances(of: result).isEmpty else {
            Log.app.error("restart: \(result.app.name, privacy: .public) won't quit (likely a save prompt) — leaving badge")
            return  // still up (likely a save prompt) — leave the badge
        }
        let relaunched = await Self.launchApp(result.app.path)
        needsRestart.remove(result.id)
        runningVersionByID[result.id] = nil
        Log.app.info("restart: \(result.app.name, privacy: .public) relaunched=\(relaunched, privacy: .public)")
        if relaunched {
            UpdateNotifier.restarted(app: result.app.name, version: result.app.shortVersion, appID: result.app.bundleID)
        }
    }

    /// Apply a self-updater-staged build (the ShipIt "Relaunch to update" state).
    ///
    /// Crucially different from `restart`: we must **not** reopen the app
    /// ourselves. The app's own ShipIt swaps the bundle *only while every instance
    /// is quit*, then relaunches it. `restart`'s immediate `NSWorkspace.open`
    /// raced that — ShipIt saw the app already back up and aborted with "App Still
    /// Running Error" every time (the bug behind "Relaunch did nothing, then the
    /// row flipped to Update"). So here we just quit and let ShipIt take over,
    /// polling disk to confirm the swap landed. We never optimistically clear the
    /// staged flag: the trailing `refreshLocal` re-derives it from the real on-disk
    /// version, so a swap that didn't land stays "Relaunch" instead of falling back
    /// to our (colliding) Update.
    func relaunchStagedUpdate(_ result: UpdateResult) async {
        guard result.app.bundleID != nil else { return }
        // Block re-entry: a slow swap must not be re-triggered by repeated clicks.
        guard !relaunching.contains(result.id) else {
            Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) already in flight — ignoring repeat")
            return
        }
        relaunching.insert(result.id)
        defer { relaunching.remove(result.id) }
        let running = runningInstances(of: result)
        guard !running.isEmpty else {
            // Not running: the staged swap applies on the app's own next quit, not
            // on demand from us. Leave the badge; a later check clears it once the
            // app itself applies the update.
            Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) not running — ShipIt applies on its own next quit")
            return
        }
        let old = result.app.shortVersion ?? result.app.buildVersion
        Log.app.info("relaunch-staged: quitting \(result.app.name, privacy: .public) (\(old ?? "?", privacy: .public)) — letting its own updater swap & relaunch (no reopen)")
        for app in running { app.terminate() }

        // Wait for the updater: with all instances quit it swaps the (large) bundle,
        // then relaunches. Success = on-disk version advances past `old`. We
        // deliberately do NOT reopen while waiting — that's what made ShipIt abort.
        //
        // Two phases with very different patience:
        //  • Until it actually quits: short. If it's still up after a few seconds a
        //    save prompt is blocking the quit — bail and leave it staged.
        //  • Once quit: long. Applying a big update (e.g. Spotify extracting a 161MB
        //    .tbz and replacing its whole app bundle) takes a while, and a busy or
        //    slow disk stretches it further — so be patient rather than dropping the
        //    spinner mid-swap and looking stuck.
        let quitGraceTicks = 25   // ~5s to actually quit (else a save prompt is up)
        let maxTicks = 900        // up to ~180s for a slow swap on a busy disk
        var applied = false
        var everQuit = false
        for tick in 0..<maxTicks {
            try? await Task.sleep(for: .milliseconds(200))
            if let disk = await Self.readShortVersionOffMain(result.app.path),
               let old, VersionComparator.isNewer(disk, than: old) {
                applied = true
                break
            }
            if runningInstances(of: result).isEmpty {
                everQuit = true  // quit succeeded — now we're waiting on the swap
            } else if !everQuit && tick >= quitGraceTicks {
                // Never quit → a save prompt (or similar) is keeping it up; the swap
                // can't start, so don't block the long window on it.
                Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) won't quit (likely a save prompt) — leaving it staged")
                break
            }
        }
        // Fallback: if ShipIt swapped but didn't relaunch (or never ran), bring the
        // app back so the user isn't left without it.
        if runningInstances(of: result).isEmpty {
            await Self.launchApp(result.app.path)
        }
        Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) applied=\(applied, privacy: .public)")
        // Re-read disk: clears the staged flag + reminder banner if the swap landed
        // (via `computeSelfUpdateStaging`'s departed-id sweep), keeps "Relaunch" if
        // it didn't. Never optimistic, never an Update fallback. Use the per-app
        // `refreshRow`, not `refreshLocal`: the latter no-ops while an "Update All"
        // batch is still installing, which would strand this row stale (it's current
        // on disk but the row never gets re-read).
        await refreshRow(result)
        if applied {
            let version = await Self.readShortVersionOffMain(result.app.path)
            UpdateNotifier.restarted(app: result.app.name, version: version, appID: result.app.bundleID)
        }
    }

    /// Launch an app bundle **without wedging the main actor**.
    ///
    /// `NSWorkspace.open(_:)` is synchronous: it doesn't return until
    /// LaunchServices has actually launched the app. For a big bundle — worse,
    /// one just rewritten by its own updater, so nothing is in the page cache —
    /// that's hundreds of milliseconds to a few seconds of blocked main thread,
    /// during which every other row's button is dead and the pointer spins
    /// (the "clicking another Update mid-relaunch beachballs" report).
    /// `openApplication(at:configuration:)` does the same work off-main and
    /// suspends instead. Default configuration matches `open(_:)`'s behaviour
    /// (it activates the launched app).
    @discardableResult
    nonisolated static func launchApp(_ bundle: URL) async -> Bool {
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: bundle, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            Log.app.error("launch failed: \(bundle.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// `readShortVersion` off the main actor. The staged-relaunch poll calls it
    /// five times a second against a bundle the vendor's updater is actively
    /// replacing — a synchronous read of a file mid-swap on a busy disk is
    /// exactly the kind of small stall that adds up to a visible hitch.
    nonisolated private static func readShortVersionOffMain(_ bundle: URL) async -> String? {
        await Task.detached(priority: .utility) { readShortVersion(bundle) }.value
    }

    /// Read a bundle's `CFBundleShortVersionString` straight off disk — used to
    /// poll for a ShipIt swap landing while the app is quit.
    nonisolated private static func readShortVersion(_ bundle: URL) -> String? {
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info),
              let dict = (try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)) as? [String: Any]
        else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Open System Settings → Privacy & Security → App Management and float the
    /// drag-to-authorize panel, prompting the user to drag **DuoUpdater itself**
    /// into the list (the permission is granted to the app doing the replacing,
    /// not the target). App Management exposes no *public* status API, but the private
    /// `TCCAccessPreflight` SPI lets us read it (see `appManagementStatus`), so we can
    /// now auto-dismiss this panel the moment the grant lands — same as Accessibility.
    /// Also callable directly (e.g. from a menu item) so it isn't gated on a failure.
    func presentAppManagementPermissionFlow(sourceFrameInScreen: CGRect? = nil) {
        // This pane takes over the panel; swap which grant we're watching to auto-close.
        awaitingAccessibilityGrant = false
        awaitingAppManagementGrant = true
        permissionFlow.authorize(
            pane: .appManagement,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: sourceFrameInScreen ?? Self.permissionFlowLaunchFrame()
        )
    }

    private func presentAppManagementPermissionFlowForInstallFailure() {
        if isInstallingAll {
            guard !appManagementPermissionFlowPresentedInBatch else { return }
            appManagementPermissionFlowPresentedInBatch = true
        }
        presentAppManagementPermissionFlow()
    }

    /// Open System Settings → Privacy & Security → Accessibility and float the same
    /// drag-to-authorize panel, prompting the user to drag **DuoUpdater itself** into
    /// the list. Needed only for the incremental (AX-driven) App Store update route,
    /// which presses App Store.app's Update button via the Accessibility API. Like
    /// App Management, there's no after-the-fact status we trust, so the user simply
    /// retries the update once granted.
    func presentAccessibilityPermissionFlow(sourceFrameInScreen: CGRect? = nil) {
        // Watch for the grant so `refreshPermissionStatus()` can auto-dismiss the panel.
        // The Welcome/Settings window that floated this is still open, so its trust
        // polling + TCC-change observer are live to detect the grant and trigger the close.
        awaitingAccessibilityGrant = true
        awaitingAppManagementGrant = false
        permissionFlow.authorize(
            pane: .accessibility,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: sourceFrameInScreen ?? Self.permissionFlowLaunchFrame()
        )
    }

    /// Called when the user opts into incremental App Store updates: if Accessibility
    /// isn't granted yet, guide them to grant it right away (the drag-to-authorize
    /// panel) rather than letting the first update fail. No-op when already trusted.
    func guideAccessibilityForIncrementalIfNeeded() {
        guard !AppStoreAXInstaller.isTrusted else { return }
        presentAccessibilityPermissionFlow()
    }

    /// Set once we've floated the Accessibility panel during a mas-fallback this run,
    /// so a user who's content with the full route isn't nagged on every update.
    @ObservationIgnored private var didGuideAccessibilityThisSession = false

    /// Float the Accessibility panel at most once per launch — used on the mas
    /// fallback path, where the update still succeeds and the prompt is only a nudge
    /// toward the cheaper incremental route.
    private func guideAccessibilityOncePerSession() {
        guard !didGuideAccessibilityThisSession else { return }
        didGuideAccessibilityThisSession = true
        presentAccessibilityPermissionFlow()
    }

    /// Awaited by the AX installer when App Store asks to quit a running app to
    /// finish installing. Records the prompt state and suspends until the user acts
    /// via `confirmQuit(_:proceed:)`.
    private func requestQuitConfirmation(id: String, appName: String) async -> Bool {
        await withCheckedContinuation { cont in
            // A second sheet for the same app shouldn't strand the first continuation.
            quitContinuations.removeValue(forKey: id)?.resume(returning: false)
            awaitingQuitConfirm[id] = appName
            quitContinuations[id] = cont
        }
    }

    /// Resolve a pending quit-to-install prompt: `proceed` true presses the App Store
    /// sheet's Continue (the app quits and the update lands), false presses Cancel.
    /// Wired to the per-row "Relaunch to finish update" affordance.
    func confirmQuit(_ id: String, proceed: Bool) {
        awaitingQuitConfirm[id] = nil
        // App Store's Continue quits the app without reopening it; remember to
        // relaunch it ourselves once the install lands. Show the "Relaunching…"
        // indicator meanwhile (cleared when the install settles in `installApp`).
        if proceed {
            reopenAfterQuit.insert(id)
            relaunching.insert(id)
        }
        let cont = quitContinuations.removeValue(forKey: id)
        Log.install.info("confirmQuit: \(id, privacy: .public) proceed=\(proceed) resumedInstaller=\(cont != nil)")
        cont?.resume(returning: proceed)
    }

    /// Reopen an app we quit for an incremental App Store update (App Store's
    /// Continue closes it without reopening). Idempotent — the set membership
    /// guards against a double reopen — so it's safe to call on both the success
    /// and the error/timeout exit of `install`, ensuring a quit-but-failed update
    /// never strands the user's app closed. Apps that weren't running were never
    /// inserted into `reopenAfterQuit`, so this only reopens what we closed.
    private func reopenIfQuitForUpdate(id: String, path: URL) {
        guard reopenAfterQuit.remove(id) != nil else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(
            at: path, configuration: config, completionHandler: { _, _ in })
    }

    /// A small launch rect at the center of the window the user is currently
    /// looking at, used as the origin for the drag panel's fly-to-Settings
    /// animation. Returns `nil` when no app window is available (e.g. the call
    /// came from a background failure path with nothing frontmost), in which
    /// case the panel simply snaps under System Settings without the fly-in.
    /// Kept deliberately small and non-empty: `FloatingDropPanel` skips the
    /// animation for an empty source rect and scales the launch size up from the
    /// card's minimum, so the card flies in compact rather than window-sized.
    private static func permissionFlowLaunchFrame() -> CGRect? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return nil }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)
    }

    // MARK: - Backups & rollback

    /// Copy the app's current bundle into the backup store before we replace it,
    /// so the update can be undone. Best-effort: a failed backup logs and proceeds
    /// (the user opted into the update; a missing safety net mustn't block it).
    private func backupCurrent(_ result: UpdateResult) async {
        let path = result.app.path
        let bundleID = result.app.bundleID
        let key = BackupStore.key(bundleID: bundleID, path: path)
        let version = result.app.shortVersion ?? result.app.buildVersion
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            do {
                try BackupStore.save(appPath: path, key: key, version: version, bundleID: bundleID)
                return true
            } catch { return false }
        }.value
        if !ok {
            Log.install.error("backup failed: \(result.app.name, privacy: .public) — proceeding without a rollback point")
            // Tell the user their safety net is gone for this update, rather than
            // discovering it only when they later try to roll back and find nothing.
            installNotes[result.id] =
                "Couldn’t back up the current version — this update will be applied without a rollback point."
        }
    }

    /// Settings' "Clean Up Now" button: prunes orphaned backups regardless of the
    /// auto-prune preference, and refreshes the on-screen backup index so any
    /// rollback affordance that pointed at a just-removed orphan disappears.
    /// Returns the bytes freed, for the confirmation the button shows.
    func cleanUpOrphanBackups() async -> Int64 {
        let freed = await Task.detached(priority: .utility) { BackupStore.pruneOrphans() }.value
        await refreshBackupIndex()
        return freed
    }

    /// Re-read which apps have a rollback backup on disk (one directory scan),
    /// mapping it onto the current rows.
    private func refreshBackupIndex() async {
        let map = await Task.detached(priority: .utility) { BackupStore.allBackups() }.value
        var byID: [String: String] = [:]
        for result in results {
            for key in BackupStore.keyCandidates(
                bundleID: result.app.bundleID, path: result.app.path)
            where map[key] != nil {
                byID[result.id] = map[key]?.version ?? "previous"
                break
            }
        }
        backupVersions = byID
    }

    /// Restore the previous version from its backup, swapping it back over the
    /// installed bundle. Mirrors `install`'s shape: a per-row spinner, an error
    /// surfaced on the row, and a restart prompt if the running process is now
    /// ahead of what's on disk.
    func rollback(_ result: UpdateResult) async {
        let id = result.id
        guard installing[id] == nil else { return }
        let target = result.app.path
        let key = BackupStore.keyCandidates(bundleID: result.app.bundleID, path: target)
            .first { BackupStore.backup(forKey: $0) != nil }
            ?? BackupStore.key(bundleID: result.app.bundleID, path: target)
        installErrors[id] = nil
        installing[id] = .installing
        Log.install.info("rollback start: \(result.app.name, privacy: .public)")
        do {
            let restored = try await Task.detached(priority: .userInitiated) { () -> String? in
                try BackupStore.restore(forKey: key, over: target)
            }.value
            AppIconCache.invalidate(target.path)
            let updated = await recheck(result)
            replaceRow(updated)
            await computeRestartInfo()
            await computeSelfUpdateStaging()
            await refreshBackupIndex()
            installing[id] = nil
            Log.install.info("rollback done: \(updated.app.name, privacy: .public) → \(restored ?? "?", privacy: .public)")
            if needsRestart.contains(updated.id) {
                UpdateNotifier.readyToRestart(app: updated.app.name, version: restored, appID: updated.app.bundleID)
            }
        } catch {
            Log.install.error("rollback failed: \(result.app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            installErrors[id] = error.localizedDescription
            installing[id] = nil
        }
    }

    // MARK: - Batch update

    /// Keep batch installs parallel without letting a large update wave saturate
    /// the network, Homebrew, and privileged swap prompts all at once.
    private static let maxParallelInstalls = 3

    /// The single concurrency authority for *all* installs, manual or batch. Every
    /// `install()` acquires a permit before doing any work and releases it when
    /// done, so the total in-flight count never exceeds this regardless of how the
    /// install was triggered. The batch task group below bounds how many tasks it
    /// *spawns*; this bounds how many actually *run* — including manual clicks that
    /// land while a batch is in progress.
    private static let installGate = AsyncSemaphore(value: maxParallelInstalls)

    /// App Store installs serialize to one at a time, regardless of how many rows
    /// the user clicks. They don't fetch bytes we control — they drive the single
    /// App Store UI via AX/mas — so two at once would fight over the same window
    /// (and `MacAppStoreSource` gives them `apps.apple.com` as a `downloadURL` host,
    /// which would otherwise let two share the per-host cap of 2). This dedicated
    /// gate replaces the host gate for App Store rows.
    private static let appStoreInstallGate = AsyncSemaphore(value: 1)

    /// How many concurrent installs may download from a single host. Lower than the
    /// global cap on purpose: same-host downloads compete for that host's bandwidth
    /// and are the ones that trip its rate limiter / WAF.
    private static let maxPerHostInstalls = 2

    /// One semaphore per download host, created on demand. Main-actor isolated, so
    /// the lookup/insert needs no extra locking. Entries are never evicted — the set
    /// of hosts is tiny and bounded by the installed-app catalog.
    private var hostInstallGates: [String: AsyncSemaphore] = [:]

    private func hostInstallGate(for host: String) -> AsyncSemaphore {
        if let gate = hostInstallGates[host] { return gate }
        let gate = AsyncSemaphore(value: Self.maxPerHostInstalls)
        hostInstallGates[host] = gate
        return gate
    }

    /// Pending updates "Update All" should act on: in-place installs only, no
    /// confirmation gates, and no row that's already busy. Snapshotted up front
    /// so the re-sorting each install triggers can't reshuffle what we iterate.
    private func installAllTargets() -> [UpdateResult] {
        results.filter { result in
            isActionableUpdate(result)
                && canAutoInstall(result)
                && !defersToSelfUpdater(result)
                && !result.isMajorUpgrade
                && installing[result.id] == nil
        }
    }

    /// Only independent archive/appcast installs run in parallel, and only once
    /// App Management is known granted. Package installers, Homebrew, and App Store
    /// all involve shared system UI/tools, so they stay serial.
    private func canBatchInstallInParallel(_ result: UpdateResult) -> Bool {
        guard !requiresInstaller(result) else { return false }
        guard appManagementStatus == .granted else { return false }
        switch result.remote?.sourceName {
        case "Sparkle", "Vendor", "GitHub":
            return true
        default:
            return false
        }
    }

    private func installInParallel(_ targets: [UpdateResult], limit: Int) async -> Int {
        guard !targets.isEmpty, limit > 0 else { return 0 }
        var installed = 0
        await withTaskGroup(of: Bool.self) { group in
            var next = 0
            var inFlight = 0

            func addNext() -> Bool {
                guard next < targets.count else { return false }
                let target = targets[next]
                next += 1
                group.addTask {
                    // `runInstall`, not `install`: the batch already claimed this
                    // target `.queued` up front, so going through `install`'s guard
                    // would reject it as "already in flight".
                    await self.runInstall(target, notify: false, deferBookkeeping: true)
                }
                return true
            }

            while inFlight < limit, addNext() {
                inFlight += 1
            }
            while let didInstall = await group.next() {
                if didInstall { installed += 1 }
                inFlight -= 1
                if Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                if addNext() {
                    inFlight += 1
                }
            }
        }
        return installed
    }

    private func hitAppManagementGate(_ result: UpdateResult) -> Bool {
        installErrors[result.id]?.contains("App Management permission") == true
    }

    /// Install every pending update we can apply in place without a confirmation
    /// gate — skipping major upgrades (license-boundary warning), pkg/installer
    /// updates (need the system installer), Toolbox / TestFlight (managed
    /// elsewhere), and anything ignored or version-skipped. App Store and Homebrew
    /// entries run serially because they share global tools/UI automation; independent
    /// Sparkle/Vendor/GitHub swaps may run with a bounded parallel window. The shared
    /// restart/staging/backup sweep runs once after the whole batch has settled.
    func installAll() async {
        guard !isInstallingAll, !isScanning, !isChecking, installing.isEmpty else { return }
        refreshPermissionStatus()
        let targets = installAllTargets()
        guard !targets.isEmpty else { return }
        isInstallingAll = true
        appManagementPermissionFlowPresentedInBatch = false
        // Claim every target `.queued` up front so each row shows a queued spinner
        // immediately — not a still-clickable "Update" button that would otherwise let
        // a manual tap race the batch — for the whole queue, not just the few currently
        // running. `runInstall` (below) skips the per-call claim since we made it here;
        // the gates still pace the actual work. Anything we claim but never run (a
        // cancelled batch, or serial targets after an App Management gate breaks the
        // loop) is released in the `defer` so no row is left with a phantom spinner.
        for target in targets {
            installErrors[target.id] = nil  // clear a prior attempt's error up front (see `install`)
            installNotes[target.id] = nil
            installing[target.id] = .queued
        }
        defer {
            isInstallingAll = false
            appManagementPermissionFlowPresentedInBatch = false
            for target in targets where installing[target.id] == .queued {
                installing[target.id] = nil
            }
        }

        let parallelTargets = targets.filter(canBatchInstallInParallel)
        let serialTargets = targets.filter { !canBatchInstallInParallel($0) }
        let limit = min(Self.maxParallelInstalls, parallelTargets.count)
        Log.app.info("update all: \(targets.count, privacy: .public) apps, parallel=\(parallelTargets.count, privacy: .public), serial=\(serialTargets.count, privacy: .public), parallelism=\(limit, privacy: .public)")
        // Count only the installs that actually happened (runInstall returns false for
        // already-current/early-out/error), so the summary banner is exact.
        var installed = 0
        installed += await installInParallel(parallelTargets, limit: limit)
        for target in serialTargets {
            if Task.isCancelled { break }
            // `runInstall`, not `install`: the target is already claimed above.
            if await runInstall(target, notify: false, deferBookkeeping: true) {
                installed += 1
            }
            if hitAppManagementGate(target) {
                Log.app.info("update all: stopping serial batch after App Management gate")
                break
            }
        }
        // The shared post-install sweep, run once for the whole batch rather than
        // per app (`deferBookkeeping: true` above): each pass is independent of which
        // app just installed, and running it inline made every finished row linger at
        // 100% while the next install waited on it (most visibly the `lsappinfo`
        // restart probe, which can stall right after a wave of relaunches). A full
        // local rescan (not just the restart/staging/backup flags) so an app that
        // self-updated *externally* while the batch ran — Chrome's Keystone applying a
        // new build during the "Update All" — is re-evaluated and clears, instead of
        // keeping its stale "update available" row until the next backstop tick. Safe
        // here: every install in the batch has finished, so there's no spinner to churn.
        await performLocalRescan()
        // Auto-restart the apps this batch just updated and left awaiting a restart,
        // so "Update All" doesn't leave a pile of "Restart" buttons (the per-app
        // path defers to here in a batch). Only the apps we actually touched — not
        // a pre-existing badge from some background self-update — and graceful, the
        // same as the single-app flow. Done after the shared sweep above so
        // `needsRestart` is current.
        if prefs.autoRestartAfterUpdate {
            for target in targets where needsRestart.contains(target.id) {
                if Task.isCancelled { break }
                await restart(target)
            }
            // Also flush any apps that already staged a self-update and are only
            // waiting on a relaunch (the "Relaunch" rows, e.g. Claude's ShipIt).
            // These are never install targets — `installAllTargets` requires
            // `hasUpdate`, and a staged row has none — so they'd otherwise sit
            // untouched after "Update All". Relaunching them can't collide with the
            // batch: the installs are done, and the app's own updater does the swap
            // on quit (we don't reopen). Scoped to the same `autoRestartAfterUpdate`
            // opt-in as the restart loop above, since it quits running apps.
            for result in results where actionableStaged(result) != nil {
                if Task.isCancelled { break }
                await relaunchStagedUpdate(result)
            }
        }
        if prefs.notifyOnUpdates && installed > 0 {
            UpdateNotifier.batchUpdated(count: installed)
        }
    }

    /// True when there's more than one app "Update All" would act on — used to
    /// decide whether to show the batch button.
    var canUpdateAll: Bool {
        !isInstallingAll && !isScanning && !isChecking && installing.isEmpty && installAllTargets().count > 1
    }

    // MARK: - Ignore / skip

    /// Toggle whether this app is hidden from update checks entirely.
    func toggleIgnore(_ result: UpdateResult) {
        let nowIgnored = !prefs.isIgnored(result.app)
        prefs.setIgnored(nowIgnored, result.app)
        syncDockBadge()
        Log.app.info("\(nowIgnored ? "ignore" : "unignore", privacy: .public): \(result.app.name, privacy: .public)")
    }

    /// Decline the currently-offered version for this app; a newer one still shows.
    func skipThisVersion(_ result: UpdateResult) {
        guard let version = result.remote?.displayVersion else { return }
        prefs.skipVersion(version, result.app)
        syncDockBadge()
        Log.app.info("skip \(version, privacy: .public): \(result.app.name, privacy: .public)")
    }

    // MARK: - Background scheduler

    /// One-time UI wiring, run when the menu first appears: hand the "show updates"
    /// action to the notification controller. The background loop itself is armed at
    /// launch (in `init`), not here, so the app checks on schedule even if its menu
    /// is never opened. Idempotent.
    private var started = false
    func start(showUpdates: @escaping @Sendable @MainActor () -> Void) {
        guard !started else { return }
        started = true
        NotificationController.shared.setOnShowUpdates(showUpdates)
    }

    /// Logged once, the first time we read permission state, so a "why didn't it
    /// install" can be traced to a missing grant. App Management comes from the private
    /// TCCAccessPreflight SPI (`.unknown` if that SPI ever goes away).
    @ObservationIgnored private var didLogPermissions = false
    private func logPermissionsOnce() {
        guard !didLogPermissions else { return }
        didLogPermissions = true
        Log.app.info("permissions: accessibility=\(self.accessibilityTrusted, privacy: .public) appManagement=\(String(describing: self.appManagementStatus), privacy: .public)")
    }

    /// Upper bound on how long after launch the first auto-check may wait. Caps the
    /// persisted-`lastCheck` interval for the first tick only, so a relaunch refreshes
    /// within minutes instead of sleeping a full (up to 6h) interval — while a flurry
    /// of dev relaunches inside this window is still throttled to one check.
    private static let launchCheckFloor: TimeInterval = 5 * 60

    /// Drop the App Nap opt-out (if held). Called when switching to manual, where
    /// there's no loop to keep alive.
    private func releaseNapAssertion() {
        if let napAssertion {
            ProcessInfo.processInfo.endActivity(napAssertion)
            self.napAssertion = nil
        }
    }

    /// (Re)arm the background auto-check loop from the current frequency setting.
    /// Called at launch and whenever the user changes the frequency. A "manual"
    /// frequency tears the loop down entirely.
    ///
    /// The loop schedules each check *relative to `lastCheck`* (persisted across
    /// launches) and checks **before** sleeping, so a cold start whose last check is
    /// already overdue runs one right away instead of waiting a full interval.
    func reschedule() {
        scheduler?.cancel()
        guard let interval = prefs.checkFrequency.interval else {
            scheduler = nil
            releaseNapAssertion()  // manual mode → let the app nap freely
            Log.app.info("scheduler: manual — no background checks")
            return
        }
        // Keep the app out of App Nap while a periodic check is armed, so the loop's
        // sleeps actually fire when no window is open (see `napAssertion`).
        if napAssertion == nil {
            napAssertion = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Periodic update checks")
        }
        Log.app.info("scheduler: every \(Int(interval), privacy: .public)s (last check \(self.lastCheck.map { "\(Int(-$0.timeIntervalSinceNow))s ago" } ?? "never", privacy: .public))")
        scheduler = Task { [weak self] in
            var isFirstCheck = true
            while !Task.isCancelled {
                guard let self else { return }
                // The FIRST check after launch uses a small floor instead of the
                // full interval. `lastCheck` is persisted across relaunches (so we
                // don't re-check on *every* launch), but a fresh process starts with
                // an empty in-memory list — without this floor a relaunch that
                // inherited a recent `lastCheck` would sleep a whole interval (up to
                // 6h) showing nothing. The floor refreshes promptly after launch
                // while still throttling rapid dev relaunches within a few minutes.
                let effectiveInterval = isFirstCheck ? min(interval, Self.launchCheckFloor) : interval
                // Sleep only until the next check is *due* relative to the last one
                // — zero (run now) when we're already overdue, e.g. a cold launch.
                let due = (self.lastCheck ?? .distantPast).addingTimeInterval(effectiveInterval)
                // A cold launch with nothing in memory yet shows the empty zero-badge
                // icon until something populates `results`. Check immediately in that
                // case rather than waiting out the floor, so the menu-bar icon
                // reflects real state right after (re)launch without a click.
                let wait = (isFirstCheck && self.results.isEmpty)
                    ? 0
                    : max(0, due.timeIntervalSinceNow)
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled else { return }
                }
                // Skip this tick — without running it — when offline (lid closed,
                // no Wi-Fi) or busy (manual check / install in flight). Offline is
                // the important case: a check would fail every networked source,
                // litter the list with retry rows, and still reset `lastCheck` so
                // the next tick sleeps a full interval into a missed check. By
                // deferring we leave `lastCheck` untouched, stay overdue, and
                // re-evaluate on a short backoff — so the moment connectivity
                // returns the next tick (≤60s away) runs the check immediately.
                let offline = !NetworkMonitor.shared.isOnline
                if !offline && self.canRefresh {
                    Log.app.info("scheduler: tick — running background check")
                    await self.backgroundRefresh()
                    isFirstCheck = false
                } else {
                    let why = offline ? "offline" : "busy"
                    Log.app.info("scheduler: tick deferred (\(why, privacy: .public)) — retrying in 60s")
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    /// A scheduled check. Notifications are emitted by `notifyNewUpdates` at the
    /// end of every refresh (manual or background), so this just runs the check —
    /// skipping the TestFlight container read so a silent scheduled check (notably
    /// the one a cold launch fires immediately) can't surface the "access data from
    /// other apps" prompt unprompted.
    private func backgroundRefresh() async {
        await refresh(allowTestFlight: false)
    }

    /// Arm the filesystem watcher and the slow periodic backstop that keep the
    /// Restart badge current when an app updates itself in the background (e.g.
    /// Chrome's Keystone). Called once at launch. Both paths are network-free.
    private func armLocalRescan() {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").path
        var paths = ["/Applications"]  // covers /Applications/Utilities (subtree)
        if FileManager.default.fileExists(atPath: home) { paths.append(home) }
        // User-added scan folders too, so a background swap there flips the Restart
        // badge. Folders added after launch are picked up on the next relaunch; the
        // add action itself triggers an immediate rescan from Settings.
        for path in prefs.customScanPaths where FileManager.default.fileExists(atPath: path) {
            paths.append(path)
        }
        let watcher = AppDirectoryWatcher(paths: paths) { [weak self] in
            Task { @MainActor in await self?.backgroundLocalRescan() }
        }
        appDirWatcher = watcher
        watcher.start()
        Log.app.info("local rescan: watching \(paths.joined(separator: ", "), privacy: .public) + \(Int(self.localRescanInterval.components.seconds), privacy: .public)s backstop")

        localRescanTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.localRescanInterval ?? .seconds(180))
                guard !Task.isCancelled, let self else { return }
                await self.backgroundLocalRescan()
            }
        }
    }

    /// A background-triggered local rescan (FS watcher or backstop timer). Coalesces
    /// so overlapping triggers don't stack, and leans on `refreshLocal`'s own guards
    /// (skips while empty / checking / installing) to stay out of the way.
    private func backgroundLocalRescan() async {
        guard !localRescanRunning else { return }
        localRescanRunning = true
        defer { localRescanRunning = false }
        // An install is replacing bundles / mutating rows: a full rescan now would be
        // dropped by `refreshLocal`'s guard (and could churn a spinner row). Remember
        // the request and drain the full pass when the install settles (see `install` /
        // `installAll`). But an app that self-updated externally *while* an unrelated
        // install/batch runs — Chrome's Keystone swapping in a new build during a slow
        // App Store batch — shouldn't stay stale until the whole batch ends: clear it
        // now with a narrowed pass that touches only the settled (non-installing) rows.
        guard installing.isEmpty, !isInstallingAll else {
            localRescanDeferred = true
            await clearSettledExternalUpdates()
            return
        }
        Log.app.debug("local rescan: triggered (watcher or backstop)")
        await refreshLocal()
    }

    /// A narrowed local rescan run *while* an install is in flight: re-read disk and
    /// re-derive status against each row's cached remote, but replace only rows that
    /// are NOT currently installing (or queued). This clears an app that self-updated
    /// externally mid-install — which the deferred full rescan would otherwise leave
    /// stale until the batch ends — without touching the installing rows, their
    /// spinners, or the global restart/staging/backup flags (the install flow owns
    /// those and recomputes them once it settles). Conservative by design: it only
    /// updates rows already on screen, so it never adds/removes rows mid-batch.
    private func clearSettledExternalUpdates() async {
        guard !results.isEmpty else { return }
        let extraScan = prefs.customScanLocations
        let found = await Task.detached(priority: .utility) {
            AppScanner(extraLocations: extraScan).scan()
        }.value
        let mergedByID = Dictionary(
            mergeScanned(found).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var next = results
        var changed = false
        for i in next.indices where installing[next[i].id] == nil {
            guard let fresh = mergedByID[next[i].id],
                  fresh.status != next[i].status
                    || fresh.app.shortVersion != next[i].app.shortVersion else { continue }
            next[i] = fresh
            changed = true
        }
        guard changed else { return }
        Log.app.debug("local rescan (narrowed, mid-install): cleared settled external update(s)")
        results = sorted(next)
        syncDockBadge()
    }

    /// Run a local rescan that an in-flight install deferred (see
    /// `backgroundLocalRescan`), now that the bundles have settled — clearing any app
    /// that self-updated externally while we were installing. No-op when nothing was
    /// deferred, so a plain single install pays no extra scan.
    private func drainDeferredLocalRescan() async {
        guard localRescanDeferred, installing.isEmpty, !isInstallingAll else { return }
        await performLocalRescan()
    }

    /// Seed `runningAppPaths` from the current process list and keep it live via
    /// NSWorkspace's launch/terminate notifications. These fire on the main thread
    /// the instant an app opens or quits, so a row's running dot updates without
    /// waiting for the next scan. We recompute the whole set on each event (cheap —
    /// it's a single in-memory array walk) rather than diffing, so a missed/coalesced
    /// notification can't leave the set wrong.
    private func armRunningAppsMonitor() {
        refreshRunningApps()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleRunningAppsChange() }
            }
            runningAppObservers.append(observer)
        }
    }

    /// Handle an app launch/terminate. Always refresh the running-dot set, and — when
    /// a Restart is pending — re-read the running builds to clear it.
    ///
    /// A manual quit+relaunch of a restart-pending app is the *one* update signal that
    /// never touches the .app on disk: its bundle was already swapped ahead of the
    /// still-running old process, so relaunching changes only which build is executing.
    /// The FS watcher sees no bundle write and no networked check fires, so this
    /// notification is the only live event that marks it. Without recomputing here the
    /// "Relaunch" badge lingered until the 180s backstop (or the user reopening the
    /// popover) — the "I restarted it myself but it still shows Relaunch" report.
    private func handleRunningAppsChange() {
        refreshRunningApps()
        // Nothing pending → nothing a relaunch could clear. A launch can't *create* a
        // needsRestart entry (that needs a newer on-disk build, which only a disk swap
        // produces — already covered by the FS watcher), so this stays a no-op on the
        // vast majority of app opens/quits. Defer to the install/check flows while
        // they're running: they recompute restart state themselves and emit their own
        // relaunch events (auto-restart), which we shouldn't race.
        guard !needsRestart.isEmpty, installing.isEmpty, !isInstallingAll, !isChecking else { return }
        // Coalesce the terminate+launch (plus helper-process) burst one restart emits
        // into a single read, and give the freshly-relaunched process a moment to
        // report its new build to `lsappinfo`.
        restartRecheckTask?.cancel()
        restartRecheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, !self.needsRestart.isEmpty,
                  self.installing.isEmpty, !self.isInstallingAll, !self.isChecking else { return }
            await self.computeRestartInfo()
        }
    }

    /// Recompute the set of running bundle paths from the live process list. We use
    /// each process's `bundleURL` (the .app it launched from), symlink-resolved to
    /// match how `AppScanner` records `InstalledApp.path` (it resolves symlinks too),
    /// so the comparison in `isRunning` lines up.
    private func refreshRunningApps() {
        runningAppPaths = Set(
            NSWorkspace.shared.runningApplications.compactMap {
                $0.bundleURL.map(Self.runtimeBundlePath)
            })
    }

    /// Normalize app bundle paths reported by running processes back to the live
    /// installed bundle. macOS can keep a process mapped to DuoUpdater's temporary
    /// `replaceItemAt` staging name after a hot swap; treating that hidden/deleted
    /// path as distinct makes running detection and Restart miss the exact app.
    nonisolated private static func runtimeBundlePath(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        let name = resolved.lastPathComponent
        let parent = resolved.deletingLastPathComponent()
        let stagedPrefix = ".duoupdater-staged-"

        if name.hasPrefix(stagedPrefix) {
            let original = String(name.dropFirst(stagedPrefix.count))
            return parent.appendingPathComponent(original).resolvingSymlinksInPath().path
        }
        for suffix in [".duoupdater-old", ".duoupdater-new"] where name.hasSuffix(suffix) {
            let original = String(name.dropLast(suffix.count))
            return parent.appendingPathComponent(original).resolvingSymlinksInPath().path
        }
        return resolved.path
    }

    /// Post a "new updates available" banner for actionable updates the user hasn't
    /// been told about yet, diffed against a *persisted* (app key → notified
    /// version) baseline rather than the live in-memory list.
    ///
    /// Run at the end of every full refresh, so an update gets announced no matter
    /// which path discovers it first — the scheduled background check, or the manual
    /// `refresh()` that fires the first time the user opens the menu/workbench.
    /// Diffing against the in-memory `results` instead made that first manual refresh
    /// silently become the baseline, so any update it surfaced was seen but never
    /// notified (by the time the background check ran, it already had it in hand).
    private func notifyNewUpdates() {
        guard prefs.notifyOnUpdates else { return }
        // Self-staged builds (the app downloaded its own update) are announced by the
        // periodic relaunch reminder `computeSelfUpdateStaging` arms — on their own
        // cadence — so they ride along here only as much as they always did via
        // `isActionableUpdate`.
        let actionable = results.filter(isActionableUpdate)
        // The version we'd announce for each app; key by `key(for:)` to match how
        // ignore/skip identify an app (survives the app moving on disk).
        func version(_ r: UpdateResult) -> String {
            r.remote?.displayVersion ?? r.remote?.shortVersion ?? ""
        }
        var baseline = prefs.notifiedVersions

        // First run ever: adopt today's pending list as the baseline *silently*. The
        // user can already see it in the app; banners are for what shows up next.
        guard prefs.notificationBaselineSeeded else {
            for r in actionable { baseline[prefs.key(for: r.app)] = version(r) }
            prefs.setNotifiedVersions(baseline)
            prefs.notificationBaselineSeeded = true
            Log.app.info("notify: seeded baseline with \(actionable.count, privacy: .public) pending (no banner)")
            return
        }

        // Consult the legacy key too: a baseline recorded before the switch to
        // per-path keys lives under the old bundle-id key, and we don't want that
        // migration to re-announce everything once as "new".
        func wasNotified(_ r: UpdateResult) -> Bool {
            baseline[prefs.key(for: r.app)] == version(r)
                || baseline[prefs.legacyKey(for: r.app)] == version(r)
        }
        let newly = actionable.filter { !wasNotified($0) }

        // Record the current target version for every actionable app (so a later
        // refresh won't re-announce the same version), and drop entries for apps no
        // longer present in the scan to keep the map from growing without bound.
        let liveKeys = Set(results.map { prefs.key(for: $0.app) })
        baseline = baseline.filter { liveKeys.contains($0.key) }
        for r in actionable { baseline[prefs.key(for: r.app)] = version(r) }
        prefs.setNotifiedVersions(baseline)

        guard !newly.isEmpty else { return }
        Log.app.info("notify: \(newly.count, privacy: .public) new updates")
        UpdateNotifier.updatesAvailable(total: actionable.count, newApps: newly.map(\.app.name))
    }

    // MARK: - Recheck

    /// Re-read one app from disk and re-check it across all sources. Cheap
    /// enough to run right before installing, as a guard against acting on a
    /// stale row.
    private func recheck(_ result: UpdateResult) async -> UpdateResult {
        let id = result.id
        // Off-main and TestFlight-free: the post-install recheck must never block the
        // UI on the TestFlight container's TCC gate. The next full refresh re-applies
        // TestFlight tagging, so a single-app recheck just scans without it.
        let testflight = TestFlightInventory(macRows: [], accessible: false)
        let toolbox = await Task.detached(priority: .userInitiated) { Self.toolboxInventory() }.value
        async let githubToken = Self.resolveGitHubToken(explicit: explicitGitHubToken())
        let extraScan = prefs.customScanLocations
        let apps = await Task.detached(priority: .userInitiated) {
            AppScanner(extraLocations: extraScan, toolbox: toolbox, testflight: testflight).scan()
        }.value
        guard let fresh = apps.first(where: { $0.id == id }) else { return result }
        let checker = UpdateChecker(
            sources: makeSources(token: await githubToken),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(inventory: toolbox),
            testflight: testflight)
        return await checker.check(fresh)
    }

    /// Re-run the update check for one app whose source errored — the retry
    /// affordance on an `.error` row (e.g. a transient GitHub rate-limit). Reuses
    /// the install-stage spinner to show "Checking" on just that row, and bails
    /// if the row is already busy (installing or mid-recheck).
    func retry(_ result: UpdateResult) async {
        let id = result.id
        guard installing[id] == nil else { return }
        Log.app.info("retry: re-checking \(result.app.name, privacy: .public)")
        installing[id] = .checking
        let updated = await recheck(result)
        installing[id] = nil
        replaceRow(updated)
        Log.app.info("retry done: \(updated.app.name, privacy: .public) → \(String(describing: updated.status), privacy: .public)")
    }

    /// Replace a single row by id and re-sort.
    private func replaceRow(_ updated: UpdateResult) {
        if let idx = results.firstIndex(where: { $0.id == updated.id }) {
            results[idx] = updated
            results = sorted(results)
        }
    }

    /// Actionable rows first: apps updated-on-disk that still need a restart,
    /// then pending updates, then everything else — each tier alphabetical.
    /// Needs-restart is the most urgent action (the update already landed and
    /// only a restart stands between the user and the new version), so it sorts
    /// ahead of pending updates rather than sinking below them.
    private func sorted(_ list: [UpdateResult]) -> [UpdateResult] {
        func rank(_ r: UpdateResult) -> Int {
            if needsRestart.contains(r.id) { return 0 }
            // A staged build that IS the latest is one relaunch from live, just like
            // needs-restart — top tier. One that trails the latest ranks as a normal
            // pending update (it'll show Update).
            if actionableStaged(r) != nil { return 0 }
            if r.hasUpdate { return 1 }
            return 2
        }
        return list.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
        }
    }
}

/// Once-only winner gate for `firstResult`: the first racer to `claim()` wins and
/// may resume the continuation; everyone after gets `false` and must do nothing.
/// Guarantees the checked continuation is resumed exactly once.
private actor RaceGate {
    private var claimed = false
    func claim() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }
}
