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
    /// Suspended `confirmQuit` calls from the AX installer, keyed by app id, resumed
    /// by `confirmQuit(_:proceed:)` when the user accepts or dismisses the prompt.
    @ObservationIgnored private var quitContinuations: [String: CheckedContinuation<Bool, Never>] = [:]
    /// App ids the user agreed to quit (via the confirm affordance) for an
    /// incremental App Store update — App Store's Continue quits but doesn't reopen,
    /// so we relaunch them ourselves once the new build is in place.
    @ObservationIgnored private var reopenAfterQuit: Set<String> = []
    /// id → the build version the running instance launched with, for display.
    private var runningVersionByID: [String: String] = [:]
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
        runningAppPaths.contains(result.app.path.resolvingSymlinksInPath().path)
    }

    func runningVersion(_ id: String) -> String? { runningVersionByID[id] }
    func backupVersion(_ id: String) -> String? { backupVersions[id] }

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

    /// The count shown on the menu-bar badge. A full refresh briefly blanks every
    /// row to `.unknown` (so `updateCount` dips to 0) before the check repopulates
    /// it — which made the badge flicker to the "no updates" icon and back. While a
    /// scan/check is in flight we hold the last settled count instead; otherwise we
    /// track `updateCount` live (so ignoring/skipping an app updates it at once).
    var badgeCount: Int { (isScanning || isChecking) ? heldBadgeCount : updateCount }
    @ObservationIgnored private var heldBadgeCount = 0

    private let sparkleInstaller = SparkleInstaller()
    private let homebrewInstaller = HomebrewInstaller()
    private let packageInstaller = PackageInstaller()
    private let vendorInstaller = VendorInstaller()
    private let masInstaller = MASInstaller()
    private let appStoreAXInstaller = AppStoreAXInstaller()

    /// Drives the App Management drag-to-authorize panel (vendored PermissionFlow)
    /// when an install is blocked by the privacy gate. Lazy so we only spin up the
    /// panel/window-tracking machinery the first time we actually hit a denial.
    @ObservationIgnored private lazy var permissionFlow = PermissionFlow.makeController()

    /// User settings (token, concurrency, ignore list, backups…). Read live on
    /// each refresh so a change made in the Settings window takes effect next check.
    let prefs: Preferences

    /// Background auto-check loop; nil when the frequency is "manual".
    private var scheduler: Task<Void, Never>?

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

    /// `NSWorkspace` launch/terminate observers that keep `runningBundleIDs` live.
    /// Retained for the app's lifetime (the single model never deallocates), so they
    /// stay registered without explicit teardown.
    @ObservationIgnored private var runningAppObservers: [NSObjectProtocol] = []

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

    /// Parsed changelogs the workbench detail has loaded this session, keyed by
    /// bundle id. The workbench reads this *synchronously* before deciding to show
    /// a spinner: a hit renders instantly, so flipping between apps in the sidebar
    /// no longer re-fetches or flashes a progress wheel. Cleared on every manual
    /// refresh (alongside the network-level `ChangelogCache`) so the notes stay
    /// fresh after the user asks for a re-check.
    private(set) var changelogByBundleID: [String: Changelog] = [:]

    /// How many of our top-level windows (workbench, Settings) are currently open.
    /// A menu-bar (.accessory) app has no Dock presence; we promote it to .regular
    /// while any window is open so it gets a Dock icon, app menu, and ⌘-Tab, then
    /// drop back to .accessory when the last closes. Ref-counted so the two window
    /// types don't fight over the policy.
    @ObservationIgnored private var openWindowCount = 0

    /// Call from a window's `.onAppear`: bump the count, ensure .regular, focus.
    func windowAppeared() {
        openWindowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call from a window's `.onDisappear`: drop the count, return to .accessory
    /// once no window remains.
    func windowDisappeared() {
        openWindowCount = max(0, openWindowCount - 1)
        if openWindowCount == 0 { NSApp.setActivationPolicy(.accessory) }
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
        return results.contains { isActionableUpdate($0) && $0.remote?.appStore?.trackID != nil }
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

    /// The ordered source stack, rebuilt per check so it picks up a token change
    /// and the App Store source re-reads the signed-in storefront region.
    private func makeSources() -> [any UpdateSource] {
        let token = GitHubToken.resolve(explicit: prefs.githubToken.isEmpty ? nil : prefs.githubToken)
        return [
            MacAppStoreSource(),
            SparkleAppcastSource(),
            HomebrewCaskSource(),
            // GitHub Releases for apps distributed that way (detection only unless
            // a rule names an installable asset).
            GitHubReleasesSource(token: token),
            // Last resort: bespoke per-vendor version endpoints. Only fires when
            // the earlier sources all miss and a recipe exists.
            VendorProbeSource()
        ]
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

    /// Per-app load state for a recipe-backed changelog, keyed by bundle id. The
    /// workbench reads this to render reactively; it never drives the fetch from a
    /// view's `.task`, so switching apps can't cancel an in-flight load.
    private(set) var changelogState: [String: ChangelogLoadState] = [:]
    /// The live load task per bundle id, owned by the model (NOT the view). Because
    /// it lives here, navigating away from an app mid-fetch doesn't cancel it — the
    /// fetch finishes in the background and caches, so coming back is instant
    /// instead of restarting from scratch (the "it refetches every time" bug).
    @ObservationIgnored private var changelogTasks: [String: Task<Void, Never>] = [:]

    /// The current state of an app's changelog, if it's recipe-backed. `nil` means
    /// the app has no recipe (the workbench then renders inline/structured/web
    /// notes directly, with no fetch involved).
    func changelogState(for result: UpdateResult) -> ChangelogLoadState? {
        guard let bundleID = result.app.bundleID,
              ChangelogRecipeRegistry.recipe(forBundleID: bundleID) != nil else { return nil }
        return changelogState[bundleID] ?? .loading
    }

    /// Kick off a background load for an app's recipe-backed changelog if one isn't
    /// already loaded or in flight. Idempotent and non-blocking: the task runs off
    /// the main actor's critical path (it only `await`s the network) and survives
    /// the user navigating to another app, so the result is ready on return.
    /// Re-tries a previous `.failed`.
    func ensureChangelogLoading(for result: UpdateResult) {
        guard let bundleID = result.app.bundleID,
              let recipe = ChangelogRecipeRegistry.recipe(forBundleID: bundleID) else { return }
        switch changelogState[bundleID] {
        case .loaded, .loading: return          // already done / in flight
        case .failed, .none: break              // (re)start
        }
        changelogState[bundleID] = .loading
        changelogTasks[bundleID] = Task { [weak self] in
            let changelog = await ChangelogService.load(recipe)
            guard let self else { return }
            self.changelogTasks[bundleID] = nil
            if let changelog {
                self.changelogByBundleID[bundleID] = changelog
                self.changelogState[bundleID] = .loaded(changelog)
            } else {
                self.changelogState[bundleID] = .failed
            }
        }
    }

    /// Drop one app's cached changelog across both layers — the session-wide
    /// parsed cache here *and* the network-level `ChangelogCache` — and cancel any
    /// in-flight load. Called after an app updates to a new version on disk: the
    /// notes the user saw were for the old release, and the model cache has no TTL
    /// of its own, so without this they'd persist until the next manual refresh.
    /// The next `ensureChangelogLoading` re-fetches fresh notes for the new build.
    func invalidateChangelog(forBundleID bundleID: String?) {
        guard let bundleID else { return }
        changelogTasks[bundleID]?.cancel()
        changelogTasks[bundleID] = nil
        changelogByBundleID[bundleID] = nil
        changelogState[bundleID] = nil
        if let recipe = ChangelogRecipeRegistry.recipe(forBundleID: bundleID) {
            Task { await ChangelogCache.shared.invalidate(recipe.source) }
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

    /// Single-flight entry point. If a refresh is already running, await it and
    /// return instead of starting a second one.
    ///
    /// `allowTestFlight` gates the one read that triggers the "access data from
    /// other apps" TCC prompt: user-present callers (menu/window open, the manual
    /// button) pass `true`; the silent background scheduler passes `false` so a
    /// cold launch never prompts unprompted.
    func refresh(allowTestFlight: Bool = true) async {
        if let existing = refreshTask {
            Log.app.info("refresh: already in flight — coalescing onto it")
            await existing.value
            return
        }
        // Only this path ever assigns `refreshTask`; coalescing callers above just
        // await it. So once our task finishes we can clear it unconditionally.
        let task = Task { await self.performRefresh(allowTestFlight: allowTestFlight) }
        refreshTask = task
        await task.value
        refreshTask = nil
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

    private func performRefresh(allowTestFlight: Bool = true) async {
        Log.app.info("refresh: start (scan + network check, testflight=\(allowTestFlight, privacy: .public))")
        // Snapshot the current count before we blank the rows below, so the menu-bar
        // badge holds it steady through the scan/check instead of flickering to 0.
        heldBadgeCount = updateCount
        // Expire all cached changelog pages so the detail window re-fetches
        // after a manual refresh — the user expects fresh release notes. Drop the
        // parsed-changelog cache too, so the workbench re-loads fresh notes.
        await ChangelogCache.shared.invalidateAll()
        changelogByBundleID = [:]
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
        let toolbox = await Task.detached(priority: .userInitiated) { ToolboxInventory() }.value

        // Start the TCC-gated TestFlight read OFF the critical path. Skipped on a
        // silent background refresh, which must never surface the prompt unprompted;
        // managed-app tagging then carries over from the last user-present check.
        let tfLoader: Task<TestFlightInventory, Never>? =
            allowTestFlight ? Task.detached(priority: .utility) { TestFlightInventory() } : nil
        if allowTestFlight { testFlightReadThisSession = true }

        // First scan with no TestFlight data → the list appears instantly, with no
        // wait on the prompt.
        let initialTF = TestFlightInventory(macRows: [], accessible: false)
        var found = await Task.detached(priority: .userInitiated) {
            AppScanner(toolbox: toolbox, testflight: initialTF).scan()
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
                    AppScanner(toolbox: toolbox, testflight: retagged).scan()
                }.value
                results = sorted(mergeScanned(found))
            } else {
                Log.scan.info("TestFlight: read pending (TCC prompt unanswered) — proceeding without it")
                reapplyTestFlightWhenGranted(tfLoader)
            }
        }

        isChecking = true
        let checker = UpdateChecker(
            sources: makeSources(),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(inventory: toolbox),
            testflight: testflight)
        Log.app.info("refresh: checking \(found.count, privacy: .public) apps")
        let checked = await checker.check(found)
        results = sorted(checked)
        await computeRestartInfo()
        await computeSelfUpdateStaging()
        await refreshBackupIndex()
        isChecking = false
        lastCheck = .now
        prefs.lastCheckDate = lastCheck  // persist so the scheduler survives relaunches
        // Announce anything newly pending — keyed off a persisted baseline, so it
        // fires no matter which refresh path got here first (background or manual).
        notifyNewUpdates()
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
            return result.app.sparkleEdPublicKey?.isEmpty == false
                && result.remote?.edSignature != nil
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
            guard let info = result.remote?.appStore,
                  !info.isRegionMismatch, !info.isLatestMacIncompatible else { return false }
            switch prefs.appStoreUpdateStrategy {
            case .full:        return MASInstaller.isAvailable
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
    /// to the app's OWN updater rather than installed over by us right now. True
    /// only for a self-updating vendor app (a `VendorProbeSource` result) that is
    /// currently running, when the policy is `.deferWhenRunning`. A not-running app
    /// (nothing to disturb) or the `.alwaysOverwrite` policy installs in place as
    /// usual. Detection-only vendor apps (no installable spec) already just "Open"
    /// their update path, so they're excluded here.
    func vendorDefersToSelfUpdater(_ result: UpdateResult) -> Bool {
        guard result.remote?.sourceName == "Vendor",
              prefs.vendorInstallPolicy == .deferWhenRunning,
              isRunning(result),
              canAutoInstall(result) || requiresInstaller(result)
        else { return false }
        return true
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
            NSWorkspace.shared.open(result.app.path)
            installNotes[result.id] =
                "\(result.app.name) is running — brought it to the front so its own updater applies the update. Quit it (or switch to “Always replace” in Settings) to install directly."
        }
        Log.app.info("vendor defer-to-self-updater: \(result.app.name, privacy: .public)")
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
        // row shouldn't shuffle mid-install.
        guard !results.isEmpty, !isChecking, installing.isEmpty else { return }
        let found = await Task.detached(priority: .userInitiated) {
            AppScanner().scan()
        }.value
        results = sorted(mergeScanned(found))
        await computeRestartInfo()
        await computeSelfUpdateStaging()
        await refreshBackupIndex()
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
            // Toolbox and TestFlight own their apps' status (computed from their
            // own cache, not a version compare) — keep it; don't re-evaluate.
            guard remote.sourceName != "Toolbox", remote.sourceName != "TestFlight" else {
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
    @discardableResult
    func install(_ result: UpdateResult, notify: Bool = true) async -> Bool {
        let id = result.id
        // Re-entrancy guard (matches `retry`): the popover "Update anyway" button
        // and the major-upgrade badge aren't disabled while an install is in
        // flight, so a double-click could otherwise launch two concurrent installs
        // for the same app — two downloads, two in-place swaps, two notifications.
        guard installing[id] == nil else { return false }
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

        // Install policy: a running self-updating vendor app is handed to its own
        // updater rather than swapped under it — unless the user chose to always
        // overwrite. (Re-checked here, not just in the UI, so any caller honors it.)
        if vendorDefersToSelfUpdater(result) {
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
                // Reset the spinner on this early-out too (see Homebrew above) so a
                // missing adamID can't wedge every future install for this app.
                guard let adamID = result.remote?.appStore?.trackID else {
                    installing[id] = nil
                    return false
                }
                installing[id] = .downloading(fraction: 0)
                // Both routes download through the App Store daemon, so we never see
                // those bytes — intentionally not recorded (we only count measured).
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
            await computeRestartInfo()
            await computeSelfUpdateStaging()
            await refreshBackupIndex()

            // Tell the user it landed. If the app was running, its live process
            // is still on the old code (so it's in needsRestart) — point them at
            // the Restart action. Otherwise the in-place swap is already fully in
            // effect and there's nothing left to do.
            let version = updated.app.shortVersion
            if needsRestart.contains(updated.id) {
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public) on disk, awaiting restart")
                if notify { UpdateNotifier.readyToRestart(app: updated.app.name, version: version) }
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
            presentAppManagementPermissionFlow()
        } catch {
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

    /// Flag apps whose running instance launched with an older build than
    /// what's now on disk — reliably, by reading the live launch version from
    /// LaunchServices (`lsappinfo`), which is cached at launch and so differs
    /// from the on-disk Info.plist after an update. Covers our own installs,
    /// the app's own updater, and brew — across app restarts.
    private func computeRestartInfo() async {
        let running = await Self.runningBuildVersions()
        var ids: Set<String> = []
        var versions: [String: String] = [:]
        for result in results {
            guard let bundleID = result.app.bundleID,
                  let runVersion = running[bundleID],
                  let disk = result.app.buildVersion ?? result.app.shortVersion,
                  VersionComparator.isNewer(disk, than: runVersion) else { continue }
            // Always record the lagging running version — even for a row that
            // also has a newer update pending — so the update row can show it as
            // "current". The Restart badge, though, only makes sense when there's
            // nothing newer to install: an update-available row shows Update and
            // installing it re-triggers the restart prompt afterward.
            versions[result.id] = runVersion
            if !result.hasUpdate { ids.insert(result.id) }
        }
        needsRestart = ids
        runningVersionByID = versions
        // Re-sort: a row that just flipped to needs-restart should move up into
        // the actionable tier rather than stay wherever it last sorted.
        results = sorted(results)
    }

    /// Flag apps whose own Squirrel updater has downloaded and staged a newer
    /// build (the ShipIt "Relaunch to update" state) that hasn't been swapped in
    /// yet. Reads each candidate's ShipIt cache off-main — pure filesystem work,
    /// but enough of it (plist parse per Squirrel app) to keep off the main actor.
    private func computeSelfUpdateStaging() async {
        // Track which apps were surfacing a *Relaunch* (actionable staged = the
        // staged build is the latest) so we can clear their banner if they stop —
        // applied, staging gone, OR a newer release now makes the staged build trail.
        let previouslyActionable = Set(results.compactMap { actionableStaged($0) != nil ? $0.id : nil })
        let apps = results.map(\.app).filter(\.hasSelfUpdater)
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

    /// Map of bundle id → the build version each running app launched with,
    /// parsed from `lsappinfo list` (one call for all running apps).
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
                if let bundleID = quotedValue(after: "bundleID", in: line) {
                    current = bundleID
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
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { needsRestart.remove(result.id); return }
        for app in running { app.terminate() }
        for _ in 0..<30 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            Log.app.error("restart: \(result.app.name, privacy: .public) won't quit (likely a save prompt) — leaving badge")
            return  // still up (likely a save prompt) — leave the badge
        }
        let relaunched = NSWorkspace.shared.open(result.app.path)
        needsRestart.remove(result.id)
        runningVersionByID[result.id] = nil
        Log.app.info("restart: \(result.app.name, privacy: .public) relaunched=\(relaunched, privacy: .public)")
        if relaunched {
            UpdateNotifier.restarted(app: result.app.name, version: result.app.shortVersion)
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
        guard let bundleID = result.app.bundleID else { return }
        // Block re-entry: a slow swap must not be re-triggered by repeated clicks.
        guard !relaunching.contains(result.id) else {
            Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) already in flight — ignoring repeat")
            return
        }
        relaunching.insert(result.id)
        defer { relaunching.remove(result.id) }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else {
            // Not running: the staged swap applies on the app's own next quit, not
            // on demand from us. Leave the badge; a later check clears it once the
            // app itself applies the update.
            Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) not running — ShipIt applies on its own next quit")
            return
        }
        let old = result.app.shortVersion ?? result.app.buildVersion
        Log.app.info("relaunch-staged: quitting \(result.app.name, privacy: .public) (\(old ?? "?", privacy: .public)) — letting ShipIt swap & relaunch (no reopen)")
        for app in running { app.terminate() }

        // Wait for ShipIt: with all instances quit it swaps the (large Electron)
        // bundle, then relaunches. Success = on-disk version advances past `old`.
        // We deliberately do NOT reopen while waiting — that's what made ShipIt
        // abort. If the app never quits (a save prompt keeps it up), bail early so
        // we don't block ~40s on a swap that can't start.
        var applied = false
        for tick in 0..<200 {  // up to ~40s
            try? await Task.sleep(for: .milliseconds(200))
            if let disk = Self.readShortVersion(result.app.path),
               let old, VersionComparator.isNewer(disk, than: old) {
                applied = true
                break
            }
            let stillUp = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
            if stillUp && tick >= 15 {  // ~3s and never quit → refused (likely a save prompt)
                Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) won't quit (likely a save prompt) — leaving it staged")
                break
            }
        }
        // Fallback: if ShipIt swapped but didn't relaunch (or never ran), bring the
        // app back so the user isn't left without it.
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            NSWorkspace.shared.open(result.app.path)
        }
        Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) applied=\(applied, privacy: .public)")
        // Re-read disk: clears the staged flag + reminder banner if the swap landed
        // (via `computeSelfUpdateStaging`'s departed-id sweep), keeps "Relaunch" if
        // it didn't. Never optimistic, never an Update fallback.
        await refreshLocal()
        if applied {
            UpdateNotifier.restarted(app: result.app.name, version: Self.readShortVersion(result.app.path))
        }
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
        quitContinuations.removeValue(forKey: id)?.resume(returning: proceed)
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
        }
    }

    /// Re-read which apps have a rollback backup on disk (one directory scan),
    /// mapping it onto the current rows.
    private func refreshBackupIndex() async {
        let map = await Task.detached(priority: .utility) { BackupStore.allBackups() }.value
        var byID: [String: String] = [:]
        for result in results {
            let key = BackupStore.key(bundleID: result.app.bundleID, path: result.app.path)
            if let backup = map[key] { byID[result.id] = backup.version ?? "previous" }
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
        let key = BackupStore.key(bundleID: result.app.bundleID, path: target)
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
                UpdateNotifier.readyToRestart(app: updated.app.name, version: restored)
            }
        } catch {
            Log.install.error("rollback failed: \(result.app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            installErrors[id] = error.localizedDescription
            installing[id] = nil
        }
    }

    // MARK: - Batch update

    /// Install every pending update we can apply in place without a confirmation
    /// gate — skipping major upgrades (license-boundary warning), pkg/installer
    /// updates (need the system installer), App Store / Toolbox / TestFlight
    /// (managed elsewhere), and anything ignored or version-skipped. Sequential on
    /// purpose: parallel installs would contend on the network, the privileged
    /// swap, and the restart bookkeeping. Snapshots the target set up front so the
    /// re-sorting each install triggers can't reshuffle what we iterate.
    func installAll() async {
        let targets = results.filter { result in
            isActionableUpdate(result)
                && canAutoInstall(result)
                && !result.isMajorUpgrade
                && installing[result.id] == nil
        }
        guard !targets.isEmpty else { return }
        Log.app.info("update all: \(targets.count, privacy: .public) apps")
        // Count only the installs that actually happened (install returns false for
        // already-current/early-out/error), so the summary banner is exact.
        var installed = 0
        for target in targets {
            if await install(target, notify: false) { installed += 1 }
        }
        if prefs.notifyOnUpdates && installed > 0 {
            UpdateNotifier.batchUpdated(count: installed)
        }
    }

    /// True when there's more than one app "Update All" would act on — used to
    /// decide whether to show the batch button.
    var canUpdateAll: Bool {
        results.filter {
            isActionableUpdate($0) && canAutoInstall($0) && !$0.isMajorUpgrade
        }.count > 1
    }

    // MARK: - Ignore / skip

    /// Toggle whether this app is hidden from update checks entirely.
    func toggleIgnore(_ result: UpdateResult) {
        let nowIgnored = !prefs.isIgnored(result.app)
        prefs.setIgnored(nowIgnored, result.app)
        Log.app.info("\(nowIgnored ? "ignore" : "unignore", privacy: .public): \(result.app.name, privacy: .public)")
    }

    /// Decline the currently-offered version for this app; a newer one still shows.
    func skipThisVersion(_ result: UpdateResult) {
        guard let version = result.remote?.displayVersion else { return }
        prefs.skipVersion(version, result.app)
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
            Log.app.info("scheduler: manual — no background checks")
            return
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
                let wait = max(0, due.timeIntervalSinceNow)
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled else { return }
                }
                // Don't stomp on a manual check or an install in flight; back off a
                // little and re-evaluate rather than busy-looping while overdue.
                if !self.isChecking && !self.isScanning && self.installing.isEmpty {
                    Log.app.info("scheduler: tick — running background check")
                    await self.backgroundRefresh()
                    isFirstCheck = false
                } else {
                    Log.app.info("scheduler: tick deferred (busy) — retrying in 60s")
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
        Log.app.debug("local rescan: triggered (watcher or backstop)")
        await refreshLocal()
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
                Task { @MainActor in self?.refreshRunningApps() }
            }
            runningAppObservers.append(observer)
        }
    }

    /// Recompute the set of running bundle paths from the live process list. We use
    /// each process's `bundleURL` (the .app it launched from), symlink-resolved to
    /// match how `AppScanner` records `InstalledApp.path` (it resolves symlinks too),
    /// so the comparison in `isRunning` lines up.
    private func refreshRunningApps() {
        runningAppPaths = Set(
            NSWorkspace.shared.runningApplications.compactMap {
                $0.bundleURL?.resolvingSymlinksInPath().path
            })
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

        let newly = actionable.filter { baseline[prefs.key(for: $0.app)] != version($0) }

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
        let apps = await Task.detached(priority: .userInitiated) {
            AppScanner(testflight: testflight).scan()
        }.value
        guard let fresh = apps.first(where: { $0.id == id }) else { return result }
        let checker = UpdateChecker(
            sources: makeSources(),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(),
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
