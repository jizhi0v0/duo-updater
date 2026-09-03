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

    /// The one state a scheduled refresh is allowed to drop — see
    /// `RefreshIntent.dropsChangelogEntry(failed:)`.
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
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
    private(set) var results: [UpdateResult] = [] {
        // Drop the derived memos whenever the list itself is replaced. This is the
        // *only* thing that invalidates them, which is what lets their getters be a
        // bare lookup: any change to an app — its path moving to a location with
        // different permissions, or the permissions changing under an identical
        // path — arrives as a write here, and staleness is bounded to one scan
        // cycle, the same window every other derived fact in this model lives in.
        didSet {
            elevationPathsCache = nil
            pruneSettledInstallErrors()
            pruneRetractedNotes()
        }
    }

    /// Drop the install errors that no longer describe anything real. Hung off the
    /// same write that invalidates the memos above because that is the one place
    /// every re-derivation of a row arrives — a scan, a check, a single-row
    /// refresh — and an error has to stop being shown the moment its row settles,
    /// whichever of those settled it.
    ///
    /// Nothing else clears one: every `installErrors` write site is the start of
    /// another action on that row, so before this a refused install left its red
    /// line under a row that had since gone "up to date ✓" and kept it there
    /// through every rescan until the app was relaunched. `UpdatePolicy` owns
    /// which rows count as settled (and, importantly, which do not).
    private func pruneSettledInstallErrors() {
        guard !installErrors.isEmpty else { return }
        for id in UpdatePolicy.settledRowIDs(
            installErrors.keys, results: results, installing: Set(installing.keys)
        ) {
            installErrors[id] = nil
        }
    }

    /// The notes half of the same problem. `installNotes` renders in the same
    /// place in the row as the error and went stale the same way: "brought it to
    /// the front so its own updater applies the update" outlived the hand-off it
    /// described, because the only thing that ever took it down was the *next*
    /// action on that row.
    ///
    /// Only the in-flight notes are eligible — `inFlightNotes` says which, and its
    /// doc says what it deliberately leaves out — and only while they are still
    /// the text on screen. `backupCurrent`'s "applied without a rollback point" is
    /// never registered: it describes the install that just finished, so a settled
    /// row is when it starts to matter, not when it stops.
    ///
    /// The second pass is housekeeping, not policy: a registration whose note some
    /// other writer has already replaced can never be acted on again, and leaving
    /// it would let the registry outlive every text in it.
    private func pruneRetractedNotes() {
        guard !inFlightNotes.isEmpty else { return }
        for id in UpdatePolicy.retractableNoteIDs(
            notes: installNotes, writtenByUs: inFlightNotes,
            results: results, installing: Set(installing.keys)
        ) {
            installNotes[id] = nil
        }
        inFlightNotes = inFlightNotes.filter { installNotes[$0.key] == $0.value }
    }
    private(set) var isScanning = false
    private(set) var isChecking = false
    /// True for the whole of `performRefresh`, unlike `isScanning`/`isChecking`
    /// which each cover only one leg of it. A user-present refresh suspends TWICE
    /// with both of those false: at `ChangelogCache.invalidateAll()` before the scan,
    /// and at the TestFlight read between the legs (up to 2s). SwiftUI renders at
    /// both. `results` still carries the previous round's `.error` rows there — long
    /// enough for a failure banner keyed on those to flash in and back out — and
    /// every whole-list control read as enabled (#253).
    ///
    /// Surfaces that must stay quiet for a whole round read this instead, via
    /// `listActivity`.
    private(set) var isRefreshing = false
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
    /// Running apps whose bundle was replaced during Update All, before the batch's
    /// deferred `lsappinfo` sweep can promote them into `needsRestart`. Keep these
    /// rows visible as “Installed · waiting to restart”; a checkmark would falsely
    /// imply the old running process had already been replaced. The value is the
    /// pre-install display version used for the running → installed line.
    private(set) var pendingBatchRestart: [String: String] = [:]
    /// App ids whose own Squirrel updater has already downloaded and staged a
    /// newer build (in the ShipIt cache) but not yet swapped it in — the app's
    /// "Relaunch to update" state. We surface a Relaunch action for these instead
    /// of offering our own Update, which would re-download and collide with the
    /// pending swap. Keyed by id → the staged update's details.
    private(set) var pendingSelfUpdate: [String: StagedSelfUpdate] = [:]
    /// Installer packages already downloaded and handed to the system installer,
    /// keyed by row id. While one is present and still matches the version on offer,
    /// the row shows "Install" (re-open the local package) rather than "Update"
    /// (download it again). Mirrored to `Preferences` so it survives a relaunch.
    private(set) var stagedPackages: [String: StagedPackage] = [:]
    /// Rows whose handed-off installer package has LANDED on disk while a copy that
    /// predates the hand-off is still running the old code — the pkg equivalent of
    /// `needsRestart`. Kept separate because `computeRestartInfo` rebuilds
    /// `needsRestart` from a version comparison that is blind to apps whose
    /// `Info.plist` version is frozen across builds (WeChat DevTools reports Electron's
    /// `36.6.0` on every 2.02.x build); this set is driven by launch time instead and
    /// then unioned into `needsRestart` so the existing Relaunch affordance just works.
    /// See `reconcilePackageRestarts` and `PackageRestartState`.
    private(set) var packageRestartPending: Set<String> = []
    /// Rows we've already posted a "ready to restart" notification for after a pkg
    /// landed, so a repeated rescan doesn't re-notify. Cleared when the row settles
    /// (relaunched, quit, or restarted from here).
    private var notifiedPackageRestart: Set<String> = []
    /// App ids whose staged self-update is mid-relaunch (we've quit the app and are
    /// waiting for its ShipIt to swap & relaunch). Drives a per-row spinner and,
    /// crucially, blocks re-entry: the swap can take tens of seconds, during which
    /// the Relaunch button must not fire a second quit.
    private(set) var relaunching: Set<String> = []
    /// A quit we asked for that the app hasn't come back from yet.
    ///
    /// Every path that arms one of these has the same shape: DuoUpdater quits a
    /// running app so an update can take effect, the app's own quit-confirmation
    /// dialog (a save prompt, Claude's "active conversation" sheet) keeps it up,
    /// and we deliberately give up waiting rather than force-kill unsaved work.
    /// Giving up on *waiting* must not mean giving up on the *hand-off*: when the
    /// user answers that dialog minutes later the quit finally goes through — the
    /// swap lands, or was already on disk — and with nobody left watching, the app
    /// simply stays closed. Worse, the only visible trace (the Restart badge, the
    /// "Relaunch to apply it" banner) is cleared by the very rescan that observes
    /// the app is gone. This marker lets the NSWorkspace terminate observer pick
    /// the hand-off back up — see `settleQuitHandoffs`.
    struct QuitHandoff: Sendable {
        /// What has to be true on disk before the app is brought back.
        ///
        /// The enum and both of its version comparisons live in Core now
        /// (`RelaunchLanding`), because neither could be tested here — `App` has
        /// no test target — and both were wrong in the same way for an app whose
        /// marketing version does not move between builds.
        typealias Landing = RelaunchLanding

        /// The row at bail time — the bundle to poll and the row to refresh.
        let result: UpdateResult
        /// What the relay waits for before launching.
        let landing: Landing
        /// Whether relaunching should hand the app the front spot — it was
        /// frontmost when we bailed (its quit dialog was up, over our click).
        let activates: Bool
        /// Bail time. A marker older than `quitHandoffMaxAge` is dropped instead
        /// of relayed: past that, a quit is the user closing the app, not a late
        /// answer to the dialog our relaunch attempt put up.
        let armedAt: Date
    }
    /// Armed quit hand-offs by row id. In-memory only (the window is minutes);
    /// reset by the next relaunch attempt for the row, dropped by
    /// `computeSelfUpdateStaging` when the staging it was armed for goes away,
    /// and consumed (at most once) by `settleQuitHandoffs`.
    private var quitHandoffs: [String: QuitHandoff] = [:]
    /// How long an armed quit hand-off stays live. Generous enough to answer a
    /// quit dialog after stepping away; short enough that a quit hours later is
    /// clearly not this hand-off.
    private static let quitHandoffMaxAge: TimeInterval = 10 * 60
    /// App ids for which an incremental (AX) App Store update has downloaded but the
    /// app is still running, so App Store is asking to quit it to finish installing.
    /// id → the app's display name (for the prompt). Drives a "Relaunch to finish
    /// update" affordance; tapping it records an answer in `quitAnswers`, which the
    /// installer reads on its next poll.
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
    /// The user's answer to a pending quit-to-install prompt, keyed by app id, read
    /// by the AX installer on each poll and cleared when it withdraws the question.
    ///
    /// Deliberately state and not a continuation. Awaiting one made the installer
    /// stop watching while it waited, and the answer often arrives somewhere it
    /// cannot be resumed from — App Store's own Continue button, in App Store's own
    /// window. The install then sat parked while the update landed behind it, and the
    /// button we had left on screen still meant "quit this app", so pressing it later
    /// terminated an app that had finished updating (measured 2026-08-29).
    @ObservationIgnored private var quitAnswers: [String: QuitPromptAnswer] = [:]
    /// App ids the user agreed to quit (via the confirm affordance) for an
    /// incremental App Store update — App Store's Continue quits but doesn't reopen,
    /// so we relaunch them ourselves once the new build is in place.
    /// Why a row is expecting to be reopened.
    ///
    /// The distinction only decides what to do with an app that is **still
    /// running** when the install returns: `userAskedToQuit` means a quit was
    /// explicitly agreed to and is merely late, so it can be handed to the
    /// terminate observer on its own. `storeMayCloseIt` needs the install to have
    /// succeeded before it earns the same treatment — otherwise a failed or
    /// cancelled update relaunches an app the user closed themselves.
    ///
    /// It is *not* a proxy for "did anything close the app": `userAskedToQuit` is
    /// reachable only through the App Store AX sheet, which the default strategy
    /// never raises. Gating the relay on it alone left every `mas` update unable
    /// to bring a running app back.
    enum ReopenReason: Sendable, Equatable {
        /// The user answered a quit-to-install prompt, so a quit is expected.
        case userAskedToQuit
        /// An App Store install started with the app running. The store's daemon
        /// may close it to swap the bundle — or the install may fail and close
        /// nothing at all.
        case storeMayCloseIt
    }
    @ObservationIgnored private var reopenAfterQuit: [String: ReopenReason] = [:]
    /// id → the exact hold-back text this model last wrote into `installNotes`,
    /// so a later restart that goes through can retract its own note and nothing
    /// else.
    ///
    /// `installNotes` is shared with `backupCurrent`, which uses it to say "this
    /// update was applied without a rollback point". Clearing the whole entry on
    /// every restart retracted that warning too — and since `autoRestartAfterUpdate`
    /// defaults on, that meant a running app's backup warning was never readable
    /// by anyone.
    ///
    /// The text, not a `Set` of ids. A set is a second copy of a fact that three
    /// other places already change: `install`, `performInstall` and `installAll`
    /// all clear `installNotes` without knowing this exists, so a member left
    /// behind by any of them would later authorise the very blanket clear this
    /// was added to prevent. Comparing against what we wrote cannot drift,
    /// because whoever overwrote the note also invalidated the comparison.
    @ObservationIgnored private var restartHoldBackNotes: [String: String] = [:]
    /// id → the "it wouldn't quit" text this model last wrote into `installNotes`,
    /// under exactly the discipline `restartHoldBackNotes` documents above.
    ///
    /// Written by `restart`'s `.stillRunning` bail, which until now said nothing to
    /// the user at all: the spinner ran the full 30s `AppRestarter` allows for a
    /// graceful quit, the button came back unchanged, and the only trace was an
    /// `os_log` line. Measured on Eudic (欧路词典) 2026-09-01 — its login sheet was
    /// up, so AppKit refused the quit — and the two clicks 52 seconds apart in that
    /// user's log are what a silent bail buys you.
    ///
    /// Not registered in `inFlightNotes` for the same reason the hold-back text
    /// isn't: the row already has the new build on disk, so it reads `.upToDate`
    /// for the whole time this note is up and the settle rule would take it down on
    /// the next rescan with nothing changed. What ends this one is the app finally
    /// quitting, which `settleQuitHandoffs` observes directly.
    @ObservationIgnored private var restartWontQuitNotes: [String: String] = [:]
    /// id → the "App Store can't replace this while it's open" text this model wrote
    /// into `installNotes`, so the install can retract exactly its own note when it
    /// finishes. Same discipline as `restartHoldBackNotes`, and for the same reason:
    /// `installNotes` has other writers, and a parallel `Set` of ids would drift.
    @ObservationIgnored private var appStoreQuitNotes: [String: String] = [:]
    /// The notes this model wrote to describe an action still in progress *whose
    /// row will tell us when it ended* — the self-updater hand-off, the re-opened
    /// installer, and the App Store quit prompt — keyed by id, holding the exact
    /// text. `pruneRetractedNotes` retracts whatever is left of these once the row
    /// settles under them.
    ///
    /// Membership is the whole design, so it is worth saying what is out and why.
    /// `restartHoldBackNotes`' text is not registered here: that row already has
    /// the new build on disk, so it reads `.upToDate` for as long as the note is
    /// up, and "settled" would fire on the first rescan while nothing about the
    /// standoff had changed. A note whose row cannot report the end of the thing
    /// it describes does not belong in this dictionary.
    ///
    /// Overlaps `appStoreQuitNotes` rather than replacing it, because that one
    /// retracts at a *moment* (the install returning) and this one on a *verdict*,
    /// and the moment does not generalise: the hand-off note is written from
    /// inside `performInstall`, whose exit is precisely when the user starts
    /// needing to read it. Folding them together would have made that install's
    /// own `defer` erase the sentence it had just put there.
    ///
    /// Not cleared at that retraction site: an entry whose note somebody else has
    /// already taken down can never be acted on again, and the housekeeping pass
    /// in `pruneRetractedNotes` drops it on the next rebuild of the list.
    @ObservationIgnored private var inFlightNotes: [String: String] = [:]
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
    /// The same backups as comparable pairs. Kept beside `backupVersions` rather
    /// than replacing it: that one is a DISPLAY string (it falls back to
    /// "previous"), and comparing against it is what hid the Rollback row.
    private(set) var backupSides: [String: VersionSide] = [:]
    /// Bundle *paths* of apps with at least one live process right now. Kept current
    /// by `armRunningAppsMonitor` (KVO on `NSWorkspace.runningApplications`), so a
    /// row's running dot lights up/clears the moment the user opens or quits the
    /// app — no refresh needed. Keyed by path, NOT bundle id: the same app can be installed twice
    /// (e.g. two Android Studio versions side by side) sharing one bundle id, and
    /// only the install whose bundle is actually executing should light up.
    private(set) var runningAppPaths: Set<String> = []
    /// The identifiers behind the same processes, read in the same pass. Carries
    /// the running answer for bundles no path can match — see
    /// `InstallEnvironment.runningBundleIDs`.
    private(set) var runningBundleIDs: Set<String> = []

    /// Whether *this exact install* currently has a running process — drives the
    /// green "live" dot in the menu and workbench. Matched on the bundle path so a
    /// second copy of the same app (same bundle id, different path) doesn't falsely
    /// light up when only the other copy is open.
    func isRunning(_ result: UpdateResult) -> Bool {
        UpdatePolicy.isRunning(result, environment: policyEnvironment)
    }

    func runningVersion(_ id: String) -> String? { runningVersionByID[id] }
    func backupVersion(_ id: String) -> String? { backupVersions[id] }

    /// Whether restoring this row's backup would change anything — the workbench's
    /// filter for offering Rollback at all. Decided in Core; see
    /// `BackupStore.rollbackIsDistinct`.
    func rollbackIsDistinct(_ result: UpdateResult) -> Bool {
        guard let backup = backupSides[result.id] else { return false }
        return BackupStore.rollbackIsDistinct(
            installed: result.app.versionSide, backup: backup)
    }

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
        restartFromSide(id)?.text(withBuild: true)
    }

    /// The same running side, still in parts, so the line can be formatted against
    /// the on-disk side rather than in isolation — see `UpdateResult.relaunchLine`.
    /// The marketing version is left nil when it adds nothing (nothing recovered it,
    /// or it is the build over again), which is exactly the case where the target's
    /// build has to stay for the two sides to be comparable at all.
    func restartFromSide(_ id: String) -> UpdateResult.VersionSide? {
        guard let runningBuild = runningVersionByID[id] else { return nil }
        let build = UpdateResult.strippingBuildPrefix(runningBuild)
        // Prefer the rollback backup's marketing (authoritative, written when *we*
        // installed); fall back to the build→marketing history recovered for apps
        // that self-updated outside us.
        let marketing = backupVersions[id] ?? recoveredRestartMarketing[id]
        return .init(marketing: marketing == build ? nil : marketing, build: build)
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
        UpdatePolicy.actionableStaged(result, staged: pendingSelfUpdate[result.id])
    }

    /// The vendor's advertised version when it's strictly *older* than what's
    /// installed — surfaced (only under "Show all") as a muted, action-less note.
    /// This is usually benign: you're ahead via a beta channel, a pulled release,
    /// or a lagging probe — never a prompt to downgrade. The rule itself lives in
    /// `UpdatePolicy` so it can be tested; see it for what settles the comparison.
    func downgradeNote(_ result: UpdateResult) -> String? {
        UpdatePolicy.laggingRemoteVersion(result)
    }

    /// The one version-line fact the row should explain. The precedence lives in
    /// Core so a relaunch and a lagging-feed note cannot silently swap places in a
    /// view with no test target (#210).
    func versionLineState(for result: UpdateResult) -> RowVersionLineState {
        RowVersionLine.state(
            staged: actionableStaged(result),
            pendingBatchRestartMarketing: pendingBatchRestart[result.id],
            restartFrom: needsRestart.contains(result.id) ? restartFromSide(result.id) : nil,
            downgradeVersion: downgradeNote(result))
    }

    /// Bring JetBrains Toolbox forward — the action for every Toolbox-managed row,
    /// in both windows. On the model rather than duplicated per view, for the same
    /// reason `rowState` is: one row, one behaviour.
    func openToolbox() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.jetbrains.toolbox") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// Bring TestFlight forward — the action for every TestFlight-managed row, in
    /// both windows and in the row menu. On the model for the same reason
    /// `openToolbox` is: one row, one behaviour.
    func openTestFlight() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.TestFlight") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// The single answer both the popover and the workbench render.
    ///
    /// `ui = f(state)`: the two surfaces used to each carry their own ladder of
    /// `if`/`else if`, in different orders and with different coverage, so the same
    /// row could read differently in the two windows — and did (see
    /// `RowActionState`). They now ask this and decide only how to *draw* the
    /// answer, never what the answer is.
    ///
    /// Presentation may still differ where it is a deliberate product decision: the
    /// workbench does not one-click a major upgrade, because the licence-boundary
    /// warning that makes that safe lives in the popover. What it may not do is
    /// render a state as nothing.
    func rowState(for result: UpdateResult) -> RowActionState {
        RowAction.state(for: RowActionFacts(
            status: result.status,
            awaitingQuitConfirm: awaitingQuitConfirm[result.id],
            isRelaunching: relaunching.contains(result.id),
            hasPendingBatchRestart: pendingBatchRestart[result.id] != nil,
            justUpdated: justUpdated.contains(result.id),
            installStage: installing[result.id],
            isIgnored: prefs.isIgnored(result.app),
            isVersionSkipped: prefs.isVersionSkipped(result.app, version: result.remote?.versionSide),
            stagedRelaunchTarget: actionableStaged(result).map { result.stagedRelaunchLine($0).to },
            needsRestart: needsRestart.contains(result.id),
            // Feeds the `.unknown` / `.upToDate` rungs' source-hint and channel
            // priority — moved here from the popover's own `isMASApp` /
            // `isTestFlightApp` / `sparkleFeedURL` reads (issue #260), so the
            // priority between them lives in `RowAction.state` rather than a view.
            isMASApp: result.app.isMASApp,
            isTestFlightApp: result.app.isTestFlightApp,
            hasSparkleFeed: result.app.sparkleFeedURL != nil,
            // `self.` because the route is an `@autoclosure` the facts hold rather
            // than a value they copy — see `RowActionFacts.route`. The capture is
            // safe: the struct is built and consumed in this one expression, and
            // the closure is called (at most once) before it returns.
            route: self.rowRoute(for: result)))
    }

    /// How an available update would be applied. Resolved here rather than in each
    /// view so both windows agree on whether a row is one-click at all — the
    /// invariant that matters, since one window offering Update while the other
    /// does not is the same row telling two stories.
    ///
    /// The decision itself is `UpdateRoute.resolve(_:)` in Core (issue #261) — this
    /// is only the wiring that fills `RouteInputs`. It stays a method the caller
    /// invokes lazily (`rowState(for:)` passes `self.rowRoute(for: result)` into an
    /// `@autoclosure` parameter) rather than a stored value, so building
    /// `RouteInputs` — which calls `canAutoInstall` / `requiresInstaller` /
    /// `defersToSelfUpdater` unconditionally and, when `requiresInstaller` is
    /// true, reads `stagedPackage(for:)` too — only happens for a row that
    /// actually reaches `.updateAvailable`. See `RowActionFacts.route`'s doc
    /// comment, and the note below on what changed inside that boundary.
    private func rowRoute(for result: UpdateResult) -> UpdateRoute {
        // `requiresInstaller` is read twice below (the gate, and the installer
        // rung itself); computed once here rather than reasked. This does NOT
        // narrow when `stagedPackage(for:)` runs — with the ladder collapsed into
        // one struct, it runs whenever `requiresInstaller` is true, including rows
        // that go on to resolve as `.majorUpgrade`, `.selfUpdater`, `.toolbox` or
        // `.testFlight`, none of which reached it in the old short-circuiting
        // `if`/`else if` chain. It stays cheap for a different reason:
        // `stagedPackage(for:)` guards on the `stagedPackages[result.id]`
        // dictionary lookup FIRST, and that is nil for nearly every row (a staged
        // package is rare), so the `fileExists` stat behind it is skipped before
        // it runs, not because this call site is skipped.
        let requiresInstaller = requiresInstaller(result)
        return UpdateRoute.resolve(RouteInputs(
            isToolboxManaged: result.remote?.sourceName == "Toolbox" || result.app.isToolboxManaged,
            isTestFlight: result.remote?.sourceName == "TestFlight",
            defersToSelfUpdater: defersToSelfUpdater(result),
            isMajorUpgrade: result.isMajorUpgrade,
            canAutoInstall: canAutoInstall(result),
            requiresInstaller: requiresInstaller,
            stagedFileName: requiresInstaller ? stagedPackage(for: result)?.url.lastPathComponent : nil,
            hasAppStoreAvailability: result.remote?.appStore != nil,
            appStoreManagedHere: result.app.isiOSAppOnMac && appStoreStrategyIsFullDownload,
            appStoreGate: AppStoreGate.resolve(result.remote?.appStore)))
    }

    /// A pending update the user hasn't ignored or skipped — what the badge counts
    /// and what "Update All" acts on.
    func isActionableUpdate(_ result: UpdateResult) -> Bool {
        guard result.hasUpdate else { return false }
        if prefs.isIgnored(result.app) { return false }
        if prefs.isVersionSkipped(result.app, version: result.remote?.versionSide) { return false }
        return true
    }

    var updateCount: Int { results.filter(isActionableUpdate).count }

    /// A row the popover lists as still having something for the user to do: a
    /// pending update, or a relaunch that finishes one already on disk.
    ///
    /// The badge counts these, not `updateCount`. The version-comparison half of
    /// `needsRestart` is only reached under `if !result.hasUpdate` (a row with
    /// something newer to install shows Update instead), so counting updates alone
    /// put the menu bar at "no updates" while the list underneath it showed apps
    /// running old code with a Relaunch button each. `computeRestartInfo` carries a
    /// landed package forward "to keep the badge lit"; this is what makes that true.
    /// (Only that half: `packageRestartPending` decides on launch TIME and never
    /// reads `hasUpdate`, so a landed pkg CAN coexist with a pending update. It
    /// costs nothing here — this is an OR — but it is why the two are not the
    /// mutually exclusive pair the first version of this comment claimed.)
    ///
    /// The three relaunch terms are gated on the user's verdict, which
    /// `isActionableUpdate` applies for itself and they do not carry: an ignored
    /// row stays in `results` with `remote: nil` and renders as a muted "Ignored"
    /// tag with no button at all (`RowAction.state` puts the ignore rung ahead
    /// of both relaunch rungs, for both windows). Counting one would light the badge with nothing
    /// on the other end of the click, forever — the same "hidden in the app, still
    /// nagging" shape `UpdatePolicy.nudgeableStaged` exists to prevent, which is
    /// also why the staged term goes through `nudgeableStaged` rather than raw
    /// `actionableStaged` (it applies the skipped-version verdict too).
    ///
    /// An uninstalled app cannot strand the badge even though
    /// `reconcilePackageRestarts` carries a `packageRestartPending` entry across a
    /// blind pass indefinitely: the count filters `results`, and a deleted app has
    /// no row there.
    func needsAction(_ result: UpdateResult) -> Bool {
        if isActionableUpdate(result) { return true }
        guard !prefs.isIgnored(result.app) else { return false }
        return needsRestart.contains(result.id)
            || pendingBatchRestart[result.id] != nil
            // Short-circuited on the raw map first: this runs per row on the render
            // path, and `nudgeableStaged` builds sanitised preference keys out of the
            // full bundle path before it can answer "nothing is staged".
            || (pendingSelfUpdate[result.id] != nil && nudgeableStaged(result) != nil)
    }

    /// How many rows `needsAction` marks — the badge's number, and the popover's
    /// "N updates available". A relaunch-pending row counts as an update here: its
    /// new version is an update that happens to be downloaded already. Keeping it
    /// out is what made the badge and the header disagree with the list in the
    /// first place. `updateCount` still answers the narrower "how many are left to
    /// install", which is what the diagnostic log wants.
    var actionCount: Int { results.filter(needsAction).count }

    /// What is in flight across the whole list right now. The whole-list actions
    /// below all gate on this one value rather than re-listing the flags, which is
    /// what let them disagree about the mid-refresh gap (#253).
    var listActivity: ListActivity {
        ListActivity(
            isRefreshing: isRefreshing,
            isScanning: isScanning,
            isChecking: isChecking,
            isInstallingAll: isInstallingAll,
            rowInstallCount: installing.count)
    }

    /// A full networked refresh rewrites the whole result list. Keep it out of
    /// the way while installs are mutating individual rows and replacing bundles.
    var canRefresh: Bool { listActivity.canRefresh }

    /// The count shown on the menu-bar badge. A full refresh briefly blanks every
    /// row to `.unknown` (so `actionCount` dips to 0) before the check repopulates
    /// it — which made the badge flicker to the "no updates" icon and back. While a
    /// scan/check is in flight we hold the last settled count instead; otherwise we
    /// track `actionCount` live (so ignoring/skipping an app updates it at once).
    var badgeCount: Int { (isScanning || isChecking) ? heldBadgeCount : actionCount }
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

    /// Lazily-fetched release notes per formula, loaded only when a formula is
    /// selected in the workbench — so a long outdated list never burns the GitHub
    /// rate limit up front. Version-keyed (see `FormulaReleaseStore`): the version a
    /// formula's notes are wanted for can move under a running session, and the
    /// entry left from the previous one must read as a miss rather than be served
    /// against the new version.
    private var formulaReleases = FormulaReleaseStore()
    private let formulaReleaseService = BrewFormulaReleaseService()

    func formulaReleaseState(name: String, version: String) -> FormulaReleaseStore.State? {
        formulaReleases.state(name: name, version: version)
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
    /// Same for the App Store helper: a batch of App Store updates all fail on the
    /// same unusable helper, and three identical dialogs would be worse than none.
    @ObservationIgnored private var helperApprovalFlowPresentedInBatch = false

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

    /// The most recent GitHub token resolution: the token (nil when none was
    /// found) and the explicit Settings value it was resolved under.
    ///
    /// Per-app rechecks reuse this rather than resolving again. With no explicit
    /// token and no env var — the zero-config `gh` login case, which is the common
    /// one — `GitHubToken.resolve` shells out to `gh auth token`, and one Update
    /// click runs two rechecks (the pre-install guard and the post-install
    /// re-read): two subprocesses per click for an answer the full check a minute
    /// earlier already had (issue #226).
    ///
    /// Invalidation is by comparison, not by event: a recheck reuses the entry only
    /// while `explicit` still equals what Settings holds, so a token pasted or
    /// cleared there takes effect on the very next recheck, and every full refresh
    /// re-resolves regardless and overwrites this. The one change this cannot see
    /// is the `gh` CLI's own login moving underneath us — `gh auth login` after
    /// launch reaches the next full check, not the next install; until then a
    /// recheck runs unauthenticated, exactly as a full check would have before the
    /// login. Not read by the UI; the banner reads `hasGitHubToken`.
    private struct ResolvedGitHubToken {
        let explicit: String?
        let token: String?
    }
    @ObservationIgnored private var resolvedGitHubToken: ResolvedGitHubToken?

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
    /// Watches the preference files behind `ChannelBinding` so flipping a channel
    /// toggle inside the vendor app itself (Surge's "Include beta builds",
    /// Tailscale's Unstable switch) re-checks that row promptly. Separate from
    /// `appDirWatcher` because it watches different roots and runs a different,
    /// much narrower pass — see `ChannelBinding.preferenceWatchPaths`.
    @ObservationIgnored private var channelPrefsWatcher: AppDirectoryWatcher?
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

    /// `NSWorkspace` launch/terminate observers, the *backup* source for
    /// `runningBundleIDs` (see `armRunningAppsMonitor`). Retained for the app's
    /// lifetime (the single model never deallocates), so they stay registered
    /// without explicit teardown.
    @ObservationIgnored private var runningAppObservers: [NSObjectProtocol] = []
    /// KVO on `NSWorkspace.runningApplications` — the primary source. Held because
    /// an `NSKeyValueObservation` unregisters itself when it is released, so
    /// dropping this handle would silently switch the running dot back to the
    /// unreliable notifications and nothing would look broken until an app's dot
    /// went stale.
    @ObservationIgnored private var runningAppsObservation: NSKeyValueObservation?
    /// Symlink-resolved bundle path per running process, remembered across
    /// running-apps events so `refreshRunningApps` resolves only the bundle
    /// that just appeared instead of every running one (see the type's doc for
    /// the measurement). Not observed: it is a memo, `runningAppPaths` is the fact.
    @ObservationIgnored private var runningBundlePaths = RunningBundlePathCache()
    /// Coalesces the terminate+launch burst a manual app restart emits into a single
    /// restart-info recompute (see `handleRunningAppsChange`). Cancel-and-reschedule,
    /// so a flurry of process events collapses to one `lsappinfo` read.
    @ObservationIgnored private var restartRecheckTask: Task<Void, Never>?

    /// Per-app download traffic, tracked to the byte and persisted across runs.
    private let trafficStore = TrafficStore()
    /// Snapshot of per-app traffic for the UI, refreshed after each recorded
    /// download. Sorted heaviest-app-first by the store.
    private(set) var trafficStats: [AppTrafficStat] = []

    /// The aggregate the Traffic window's header reads — grand total, month
    /// buckets, per-source split. Recomputed with the snapshot rather than in the
    /// view, which would redo the whole pass on every redraw.
    private(set) var trafficSummary: TrafficSummary = .empty

    /// `trafficStats` split into apps still installed and entries whose recorded
    /// path no longer resolves. Held rather than derived in the view because the
    /// split stats each path on disk — one filesystem hit per app, which a redraw
    /// must not repeat.
    private(set) var trafficPresent: [AppTrafficStat] = []
    private(set) var trafficRemoved: [AppTrafficStat] = []
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

    // MARK: - "We updated ourselves while you weren't looking"

    /// The version Duo Updater silently updated itself to since the user last saw
    /// release notes, or nil. Drives the bright sparkles beside the menu's version.
    ///
    /// Computed once at launch rather than on every read: the running version
    /// cannot change inside a process, and the record is cleared the moment the
    /// user opens the notes, so a stored value is the honest model.
    private(set) var silentSelfUpdate: String?

    /// The version this build reports. One place, so the menu, the notes window
    /// and the record can never disagree about what "running" means.
    static var runningSelfVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Resolve the unread-release state at launch. Seeds the record silently for a fresh
    /// install or a rollback (see `SelfUpdateNotice`), and otherwise leaves it
    /// alone — the record is what keeps the sparkles bright until it is read, so
    /// it must NOT be cleared here.
    func resolveSilentSelfUpdate() {
        let running = Self.runningSelfVersion
        if SelfUpdateNotice.shouldSeedSilently(running: running, lastSeen: prefs.lastSeenSelfVersion) {
            prefs.lastSeenSelfVersion = running
            silentSelfUpdate = nil
            return
        }
        silentSelfUpdate = SelfUpdateNotice.announcement(
            running: running, lastSeen: prefs.lastSeenSelfVersion)
        if let silentSelfUpdate {
            Log.app.notice(
                "self-update noticed: now \(silentSelfUpdate, privacy: .public), last seen \(self.prefs.lastSeenSelfVersion ?? "—", privacy: .public)")
        }
    }

    /// The user has seen the notes: stop announcing this version.
    func markSelfUpdateSeen() {
        prefs.lastSeenSelfVersion = Self.runningSelfVersion
        silentSelfUpdate = nil
    }

    /// Call from a window's `.onAppear`: keep the badge current and bring the
    /// first surfaced window to the front.
    func windowAppeared() {
        syncDockBadge()
        AppDockBadge.syncSoon(count: badgeCount)
        if NSApp.keyWindow == nil && NSApp.mainWindow == nil {
            NSApp.activate(ignoringOtherApps: true)
        }
        // The user coming back to DuoUpdater is one of the two moments we use to
        // notice a `ChannelBinding` app's channel toggle flipped in the vendor
        // app itself (see `recheckChannelSwitches`) — free unless something
        // actually changed.
        Task { await recheckChannelSwitches(trigger: "window-appeared") }
    }

    /// Call from a window's `.onDisappear`. Kept for symmetric lifecycle sites: the
    /// activation policy now follows `Preferences.hideDockIcon` (see `DockIcon`)
    /// rather than the window lifecycle, so there is nothing to undo here.
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
    ///
    /// Then it **asks the window server whether that actually worked, and asks
    /// again if it did not**, which is the whole of this change. Ordering a window
    /// front is a request, and one assertion is not enough — from the popover's row
    /// menu with the Dock icon hidden (`.accessory`, the default), the first
    /// assertion left the window not in front every single time. Four consecutive
    /// opens, logged from the shipped app:
    ///
    ///     surface[1] workbench visible=true key=true front=false  policy=accessory
    ///     surface[2] workbench visible=true key=true front=true   policy=accessory
    ///
    /// `visible=true key=true front=false` is the shape of the bug: the window is
    /// open, and it is even this app's key window, and it is still not the frontmost
    /// window on screen. AppKit's own state cannot see that — `isVisible` and
    /// `isKeyWindow` both say yes — which is why this asks CoreGraphics instead. The
    /// second attempt, ~110 ms later, was in front on all four. The version that
    /// asserted once and returned failed all four, and to the user that is a menu
    /// item that does nothing.
    ///
    /// Three costs worth knowing before tuning any of the numbers. A window that is
    /// in front on the first look still needs `settledChecks` confirmations, so the
    /// cheapest path is three window-list reads over ~0.2 s — not one, and not free.
    /// A window that never gets there is chased for the full 1.2 s. And once it HAS
    /// been in front, the budget shortens to `holdAfterFront`, because past that
    /// point every re-assertion is as likely to be fighting the user who moved on as
    /// it is to be fixing the popover pushing our window back down.
    ///
    /// One loop at a time, across every scene: opening Settings and then the
    /// workbench within the same second used to leave two loops each insisting on a
    /// different window, trading places until both expired.
    func surfaceWindow(sceneID: String) {
        // Reaching the front once is not the same as being there when the user
        // looks. Logged from the shipped app, five consecutive opens all reported
        // `front on attempt 2` — and the user still saw the window fail to appear on
        // some of them. What the one-shot check cannot see is what happens *after*
        // it returns: the popover dismisses, the app stops being active, and the
        // window it just ordered up goes back down behind whatever was in front.
        //
        // So this holds the order rather than asserting it: keep checking until the
        // window has been in front for `settledChecks` checks in a row, re-asserting
        // whenever it is not, and give up at the deadline either way.
        // A monotonic clock, not `Date`: a wall-clock step (an NTP correction on a
        // machine that just woke, which is exactly when a menu-bar app gets clicked)
        // would either end the loop on its first tick or keep it re-ordering the
        // window for the length of the step.
        var deadline = ContinuousClock.now.advanced(by: .milliseconds(1200))
        let holdAfterFront = Duration.milliseconds(400)
        let settledChecks = 3          // ~0.3 s of staying put
        var attempts = 0
        var consecutiveFront = 0
        var everFront = false

        surfaceGeneration &+= 1
        let generation = surfaceGeneration

        func tick() {
            // Superseded by a later surface request — for this scene or another one.
            guard generation == surfaceGeneration else { return }
            attempts += 1
            guard let window = NSApp.windows.first(where: {
                ($0.identifier?.rawValue.contains(sceneID) ?? false) && $0.isVisible
            }) else {
                // Not visible *yet* is a state to wait through rather than give up
                // on: `openWindow` took 150–480 ms to return in the traces.
                if ContinuousClock.now < deadline { retry() } else {
                    Log.app.notice("surface: \(sceneID, privacy: .public) never became visible")
                }
                return
            }
            let front = Self.isFrontmostOnScreen(window)
            if front {
                if !everFront {
                    everFront = true
                    // It arrived. From here we are only guarding against being
                    // pushed back down, which happens within a few hundred ms; a
                    // full second of insisting past that just takes the front away
                    // from a user who has already moved to another app.
                    deadline = min(deadline, .now.advanced(by: holdAfterFront))
                }
                consecutiveFront += 1
                if consecutiveFront >= settledChecks {
                    // `isFrontmostOnScreen` answers true when it cannot read the
                    // window list at all, which is the right way to stop spinning
                    // and the wrong thing to call "settled": this log line is the
                    // only evidence this code leaves, and it must not claim a window
                    // is in front when nothing was able to look.
                    Log.app.notice("""
                        surface: \(sceneID, privacy: .public) \
                        \(Self.canReadWindowList() ? "settled in front" : "stopped — window list unreadable") \
                        after \(attempts, privacy: .public) checks
                        """)
                    return
                }
            } else if everFront, !NSApp.isActive {
                // The window arrived, the user saw it, and then activated something
                // else. That is not the popover pushing our window down — it is the
                // user, and the front belongs to whoever they just switched to.
                // Without this the loop drags them back for the rest of its budget:
                // reported from use, "if you switch away quickly it pulls you back".
                //
                // Safe as the stopping rule only because the popover now takes
                // activation when it opens (see MenuContentView), so we stay active
                // through its dismissal — the moment this guard exists to survive.
                Log.app.notice("""
                    surface: \(sceneID, privacy: .public) stopped after \
                    \(attempts, privacy: .public) checks — the user activated another app
                    """)
                return
            } else {
                // Either it never got there, or it got there and was pushed back
                // while we are still the active app — the second is the case the
                // one-shot version could not see.
                if consecutiveFront > 0 { consecutiveFront = 0 }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            if ContinuousClock.now < deadline {
                retry()
            } else {
                Log.app.notice("""
                    surface: \(sceneID, privacy: .public) gave up after \
                    \(attempts, privacy: .public) checks, everFront=\(everFront, privacy: .public)
                    """)
            }
        }
        func retry() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: tick) }
        DispatchQueue.main.async(execute: tick)
    }

    /// Which surfacing loop is the live one. Bumped by every `surfaceWindow` call
    /// so an older loop — for this scene or a different one — stops on its next
    /// tick instead of fighting the newer request for the front.
    @ObservationIgnored private var surfaceGeneration = 0

    /// Whether the window server answered at all. Separates "this window is in
    /// front" from "nothing could be read", which `isFrontmostOnScreen` deliberately
    /// collapses so the caller stops retrying.
    private static func canReadWindowList() -> Bool {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                   kCGNullWindowID) as? [[String: Any]] != nil
    }

    /// Whether the window server has this window in front of every other ordinary
    /// on-screen window. The rule itself is `WindowOrder.isFrontmost`, in Core where
    /// it can be tested; this only reads the list.
    private static func isFrontmostOnScreen(_ window: NSWindow) -> Bool {
        // `.optionOnScreenOnly`, NOT `.optionAll`: only the on-screen list is
        // ordered front-to-back. Measured with Claude frontmost —
        //   .optionAll         : Excel > Messages > Finder > Zed > Claude > …
        //   .optionOnScreenOnly: Claude > Excel > App Store > …
        // — so reading `.optionAll` as a z-order is reading a list that isn't one,
        // and this check would answer about window creation order instead. A window
        // that is not on screen is simply absent from the list, which is the right
        // answer here: not visible is not in front.
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]]
        else { return true }   // can't tell → don't spin
        let windows = raw.map {
            WindowInfo(
                number: $0[kCGWindowNumber as String] as? Int ?? -1,
                layer: $0[kCGWindowLayer as String] as? Int ?? -1,
                isOnScreen: $0[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
        return WindowOrder.isFrontmost(window.windowNumber, in: windows)
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
        return results.contains {
            isActionableUpdate($0) && $0.remote?.appStore?.trackID != nil
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
        // Restore installer packages downloaded before this launch, so a relaunch
        // doesn't turn a finished download back into an "Update" that re-fetches it.
        loadStagedPackages()
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
        // kept current by KVO on `NSWorkspace.runningApplications`.
        armRunningAppsMonitor()
        // Did we swap ourselves out from under the user since they last read the
        // notes? Resolved once here: the running version can't change inside a
        // process, and doing it at launch means the banner is right the first time
        // the menu opens rather than after some later event.
        resolveSilentSelfUpdate()
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
        // Logged so a resolve is visible in `log stream`: without an explicit or env
        // token each one is a `gh auth token` subprocess, and this line is how to
        // count them per action (one per full check; none per Update click).
        Log.app.info("GitHub token: resolving (explicit=\(explicit != nil, privacy: .public))")
        let loader = Task.detached(priority: .utility) {
            GitHubToken.resolve(explicit: explicit)
        }
        if let token = await firstResult(of: loader, within: timeout) {
            return token
        }
        Log.app.error("GitHub token resolve timed out — continuing without a token")
        return nil
    }

    /// The token for a per-app recheck: the most recent resolution, unless the
    /// explicit Settings value has changed since — then a fresh resolve, remembered
    /// in turn. See `resolvedGitHubToken` for what this can and cannot notice.
    private func githubTokenForRecheck() async -> String? {
        let explicit = explicitGitHubToken()
        if let cached = resolvedGitHubToken, cached.explicit == explicit {
            return cached.token
        }
        let token = await Self.resolveGitHubToken(explicit: explicit)
        resolvedGitHubToken = ResolvedGitHubToken(explicit: explicit, token: token)
        return token
    }

    /// The ordered source stack, rebuilt per check so it picks up a token change
    /// and the App Store source re-reads the signed-in storefront region.
    private func makeSources(token: String?) -> [any UpdateSource] {
        hasGitHubToken = (token != nil)
        return SourceStack.make(githubToken: token, alcove: alcoveCredentials())
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
        trafficSummary = TrafficSummary(stats: snapshot)
        let partition = TrafficPartition(stats: snapshot)
        trafficPresent = partition.present
        trafficRemoved = partition.removed
    }

    /// Re-read the traffic log from disk. The window calls this on appear: an app
    /// deleted or renamed since the last recorded download moves between the
    /// present and removed groups, and nothing else would notice.
    func reloadTrafficStats() async {
        await refreshTrafficStats()
    }

    /// Record the bytes one install transferred, keyed to its app, then refresh
    /// the UI snapshot. `bytes <= 0` (e.g. an install that did no measured
    /// download) is ignored by the store.
    /// - Parameter applied: the coordinator's own answer to "is the new version on
    ///   disk now". A staged `.pkg` is false — macOS's installer still has a window
    ///   open — and the bundle there is still the build being replaced.
    /// - Parameter fromBuild: the build measured off disk immediately before the
    ///   install started. Passed in rather than read here because by now the swap
    ///   has already happened and the bundle carries the new build.
    private func recordTraffic(
        _ result: UpdateResult, bytes: Int64, applied: Bool, fromBuild: String?,
        usedDelta: Bool
    ) async {
        // The build actually landed on beats the one the source advertised: feeds
        // do misreport (a static appcast overridden by a backend list, a lagging
        // mirror), and this is measured rather than claimed. It is also the only
        // build number available at all for GitHub, Homebrew and the App Store,
        // which publish none.
        // `declared` only stands in when the bundle cannot be read, so it has to be
        // in the same namespace `InstalledBuild.read` answers in — `CFBundleVersion`.
        // A source reporting the vendor's own build id (Mozilla's `BuildID`) has
        // nothing to offer here, and its number beside a `CFBundleVersion` in the
        // traffic log would be worse than the blank this leaves instead.
        let declaredBuild = result.remote.flatMap {
            $0.buildNamespace == .bundle ? $0.version : nil
        }
        let toBuild = InstalledBuild.recorded(
            applied: applied,
            onDisk: { InstalledBuild.read(at: result.app.path) },
            declared: declaredBuild)

        await trafficStore.record(
            appID: result.app.id,
            appName: result.app.name,
            bundleID: result.app.bundleID,
            fromVersion: result.app.shortVersion,
            toVersion: result.remote?.displayVersion,
            sourceName: result.remote?.sourceName,
            bytes: bytes,
            // Several builds can ship under one marketing version — Surge put four
            // releases out as "6.9.0" — and the row reads "6.9.0 → 6.9.0" without
            // these. Both sides are measured off the same bundle, one before the
            // install and one after.
            fromBuild: fromBuild,
            toBuild: toBuild,
            downloadKind: usedDelta ? .delta : .full
        )
        await refreshTrafficStats()
    }

    /// Log every release in `checked` that arrived with a trustworthy vendor
    /// timestamp into the release timeline, then refresh the UI snapshot. The
    /// store dedupes by (app, version), so re-checks are cheap; only a genuinely
    /// new release or changed display metadata writes the timeline file. Results
    /// without a `publishedAt` (vendor probes, MAS, Homebrew) use the observation
    /// path below rather than this exact-timestamp path.
    private func recordReleaseTimeline(for checked: [UpdateResult]) async {
        for result in checked {
            guard let remote = result.remote else { continue }
            // The latest release (when it carries a date)…
            if remote.publishedAt != nil {
                await releaseTimelineStore.record(
                    appID: result.app.id,
                    appName: result.app.name,
                    bundleID: result.app.bundleID,
                    version: remote.displayVersion,
                    sourceName: remote.sourceName,
                    publishedAt: remote.publishedAt
                )
            }
            // …plus any prior releases the source surfaced (Sparkle appcast items,
            // a GitHub releases list), so an app's history backfills in one shot.
            // The store dedupes by version, so the latest overlapping here is free.
            for entry in remote.releaseHistory {
                await releaseTimelineStore.record(
                    appID: result.app.id,
                    appName: result.app.name,
                    bundleID: result.app.bundleID,
                    version: entry.version,
                    sourceName: remote.sourceName,
                    publishedAt: entry.publishedAt
                )
            }
            // Detection-only sources (a vendor probe, a Homebrew cask, the App
            // Store) report a version but no date. We can't know when they shipped,
            // only that a version *change* happened between two checks — so track
            // the reported version and, on a change, log an estimated window.
            // Build-aware, so a vendor that ships many builds under one marketing
            // name records one event per RELEASE rather than one for the whole
            // name. Amp published ten builds as "1.0" in a day; keyed on the
            // marketing string the timeline logged exactly one of them.
            //
            // Events written by earlier builds keep their marketing-only key and
            // are deliberately not rewritten: the history they under-counted
            // cannot be recovered, and re-deriving it would invent dates.
            if remote.publishedAt == nil, remote.releaseHistory.isEmpty,
               case let side = remote.versionSide, !side.isEmpty,
               case let v = side.text(withBuild: true), !v.isEmpty {
                await releaseTimelineStore.observeForChange(
                    appID: result.app.id,
                    appName: result.app.name,
                    bundleID: result.app.bundleID,
                    version: v,
                    sourceName: remote.sourceName
                )
            }
        }
        // One write for the whole check. The store batches every `record` /
        // `observeForChange` above into dirty flags precisely so a 100-app check
        // doesn't turn into 100 full-file atomic rewrites.
        //
        // `flush` reports whether it actually rewrote the timelines, which is the
        // signal to use rather than whether any `record` returned true: a duplicate
        // version that only refreshed an app's name or bundle id is a real change to
        // show and both recording calls correctly report it as "added nothing".
        // Snapshotting unconditionally would sort every timeline and reassign an
        // `@Observable` property on every idle check, redrawing the Release Log for
        // no reason.
        let timelinesChanged = await releaseTimelineStore.flush()
        if timelinesChanged || releaseTimelines.isEmpty {
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

    /// Keys whose notes have been fetched over the network *this session*, as
    /// opposed to painted from the cross-launch disk cache.
    ///
    /// The disk cache is keyed by the version the notes are being shown for, and
    /// `prewarmChangelogs` treats a hit as final because a released version's notes
    /// are immutable. They are — but the entry under that key need not be the
    /// notes for that version at all. CleanShot's 5.0 was offered by the appcast
    /// six minutes before the vendor published its notes, so the fetch stored the
    /// 4.8.10-and-older page under the key `5.0`, and from then on: prewarm hit the
    /// disk, marked the state `.loaded`, and `ensureChangelogLoading` returned at
    /// its first line every time the user opened the app. The pane showed "5.0" over
    /// 4.8.10's notes, permanently, with nothing to re-read it. This set is what
    /// makes a disk hit provisional until the network has confirmed it once.
    @ObservationIgnored private var changelogRevalidated: Set<ChangelogCacheKey> = []

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
            forBundleID: result.app.bundleID, channel: result.app.releaseChannel,
            version: changelogTargetVersion(for: result))
    }

    /// The version whose notes this row is about: the offered update if there is
    /// one, else the installed build.
    ///
    /// One definition rather than four copies, because the recipe LOOKUP now reads
    /// it too. A vendor can fork its notes across two pages that share a bundle id
    /// and a channel (Raycast v1/v2), and the version is what picks between them —
    /// so if the lookup judged a different version than the one being fetched and
    /// cached, we would fetch one train's page and file it under the other's key.
    private func changelogTargetVersion(for result: UpdateResult) -> String? {
        result.remote?.displayVersion ?? result.app.shortVersion
    }

    /// Kick off a background load for an app's recipe-backed changelog if one isn't
    /// already loaded or in flight. Idempotent and non-blocking: the task runs off
    /// the main actor's critical path (it only `await`s the network) and survives
    /// the user navigating to another app, so the result is ready on return.
    /// Re-tries a previous `.failed`.
    func ensureChangelogLoading(for result: UpdateResult) {
        guard let bundleID = result.app.bundleID,
              let recipe = applicableRecipe(for: result) else { return }
        let targetVersion = changelogTargetVersion(for: result)
        let key = ChangelogCacheKey(
            bundleID: bundleID, channel: result.app.releaseChannel, version: targetVersion)
        // A `.loaded` that was only ever painted from the disk cache is not done:
        // it still owes one network read, because the entry filed under this
        // version's key may have been fetched before the vendor published that
        // version's notes (see `changelogRevalidated`). Confirmed once, it is done.
        var alreadyPainted = false
        switch changelogState[key] {
        case .loading: return                        // in flight
        case .loaded:
            if changelogRevalidated.contains(key) { return }
            alreadyPainted = true                    // keep it on screen while re-reading
        case .failed, .none: break                   // (re)start
        }
        if !alreadyPainted { changelogState[key] = .loading }
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
                // Only a fetch that came back confirms the cached notes. Marking the
                // key on the attempt would pin whatever is on screen for the rest of
                // the session the first time the network is down — which is this
                // change's own bug, reintroduced for the offline case.
                self.changelogRevalidated.insert(key)
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
            version: changelogTargetVersion(for: result))
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
        changelogRevalidated = changelogRevalidated.filter { $0.bundleID != bundleID }
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
            let targetVersion = changelogTargetVersion(for: result)
            changelogState[key] = .loading
            changelogTasks[key] = Task { [weak self] in
                var changelog = await ChangelogService.diskCached(recipe, version: targetVersion)
                var fetched = false
                if changelog == nil {
                    // Cap concurrent network prewarms: a cold cache would otherwise
                    // fan out one fetch per recipe-backed app at once. Disk hits above
                    // skip the gate; only genuine network fetches queue through it.
                    await Self.prewarmNetworkGate.wait()
                    changelog = await ChangelogService.load(recipe, version: targetVersion)
                    await Self.prewarmNetworkGate.signal()
                    fetched = changelog != nil
                }
                if Task.isCancelled { return }
                guard let self else { return }
                self.changelogTasks[key] = nil
                // A disk hit is provisional; only a fetch that came back discharges
                // the debt. A failed one leaves the key owing a read, and the open
                // path will take it.
                if fetched { self.changelogRevalidated.insert(key) }
                if let changelog {
                    self.changelogState[key] = .loaded(changelog)
                    self.prewarmImages(in: changelog)
                } else {
                    // Network miss during pre-warm: settle on `.failed` so the pane
                    // shows the web-view fallback rather than stranding on the spinner.
                    // (`changelogState(for:)` maps a *missing* key back to `.loading`,
                    // and the view's `.onAppear` fires once per appearance — so clearing
                    // the key would leave an in-flight-looking spinner that never
                    // re-triggers a fetch. The next refresh of either kind drops
                    // `.failed` entries before re-prewarming — see `performRefresh` —
                    // which is the only retry a failed prewarm gets.)
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
    /// What the in-flight `refreshTask` was started for. A user-present caller that
    /// coalesces onto a silent scheduled refresh would otherwise return with neither
    /// of its consequences delivered — TestFlight tags never applied, release notes
    /// left as they were — so `refresh` checks this and runs one user-present
    /// follow-up (`RefreshIntent.owesFollowUp`).
    @ObservationIgnored private var refreshTaskIntent: RefreshIntent?

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
    /// `intent` says who asked, and `RefreshIntent` spells out what follows from
    /// it: a user-present refresh (menu/window open, the manual button, a re-check
    /// after a permission grant) may take the TestFlight read that triggers the
    /// "access data from other apps" TCC prompt, and starts the release notes over;
    /// the silent scheduler's tick does neither, so a cold launch never prompts
    /// unprompted and an hourly check never blanks the notes being read.
    func refresh(intent: RefreshIntent = .userPresent) async {
        if let existing = refreshTask {
            // A user-present caller that lands on a scheduled refresh would otherwise
            // return with neither of its consequences delivered — TestFlight tags
            // missing until the next refresh, notes untouched. Note the in-flight
            // intent *before* awaiting, since the owning call clears `refreshTask` /
            // `refreshTaskIntent` once it returns.
            let needFollowUp = refreshTaskIntent.map(intent.owesFollowUp(afterCoalescingOnto:)) ?? false
            Log.app.info("refresh: already in flight — coalescing onto it")
            await existing.value
            // Run one fresh user-present refresh. This recurses at most once: that
            // refresh starts as `.userPresent`, so it can't re-trigger this branch
            // and loop. (`reapplyTestFlightWhenGranted` also folds in, so no
            // duplicate prompt.) It is also what makes "refresh" mean fresh notes
            // when the click landed mid-tick: the scheduled pass that just finished
            // left them alone, and this one restarts them.
            if needFollowUp {
                Log.app.info("refresh: coalesced onto a scheduled refresh — running user-present follow-up")
                await refresh(intent: .userPresent)
            }
            return
        }
        guard canRefresh else {
            Log.app.info("refresh: skipped — install/check already in flight")
            return
        }
        // Only this path ever assigns `refreshTask`; coalescing callers above just
        // await it. Clear ownership *inside* the task — before `task.value` resolves
        // — so a user-present caller that coalesced onto a scheduled refresh resumes
        // to find `refreshTask` already nil. Clearing it *after* `await task.value`
        // (out here) left a window where that caller re-entered the follow-up branch
        // above against the same just-finished scheduled task and recursed on
        // `refresh(intent: .userPresent)` forever — a main-thread livelock (ANR).
        let task = Task {
            await self.performRefresh(intent: intent)
            self.refreshTask = nil
            self.refreshTaskIntent = nil
        }
        refreshTask = task
        refreshTaskIntent = intent
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
    ///
    /// `/Applications` is where the privileged, non-atomic whole-bundle swap can
    /// leave an orphan — user-writable locations take the atomic path. The input
    /// method directories are here for a different leftover: those installs
    /// exchange the bundle's `Contents` in place, and an exchange interrupted
    /// between its two renames leaves `<App>.app` with no `Contents` at all, which
    /// is an input method macOS can no longer load. Sweeping only `/Applications`
    /// would have left exactly that state unrecoverable, because a rotation's
    /// leftovers sit INSIDE the bundle rather than beside it.
    private func recoverInterruptedSwapsOnce() {
        guard !didRecoverSwaps else { return }
        didRecoverSwaps = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true),
            home.appendingPathComponent("Library/Input Methods", isDirectory: true),
        ]
        Task.detached(priority: .utility) {
            for root in roots { InPlaceSwap.recoverInterruptedSwaps(in: root) }
        }
    }

    private func performRefresh(intent: RefreshIntent) async {
        let allowTestFlight = intent.readsTestFlight
        Log.app.info("refresh: start (scan + network check, intent=\(String(describing: intent), privacy: .public), testflight=\(allowTestFlight, privacy: .public))")
        isRefreshing = true
        defer { isRefreshing = false }
        // Once per session, before the scan: recover any app left at
        // `<App>.app.duoupdater-old` by a privileged swap that died mid-rename (a
        // power loss / force-quit on the non-admin install path). Restoring it here
        // means the about-to-run scan sees a working app rather than a missing one.
        recoverInterruptedSwapsOnce()
        // A full check rewrites every row from scratch, and only runs when nothing is
        // installing (`canRefresh`), so there is no click to protect: drop any frozen
        // order outright rather than pinning the new list to an old layout. Also the
        // backstop that guarantees a freeze can never outlive its round.
        pinnedOrder = [:]
        // Snapshot the current count before we blank the rows below, so the menu-bar
        // badge holds it steady through the scan/check instead of flickering to 0.
        heldBadgeCount = actionCount
        // Release notes. A user-present refresh starts them over — expire the
        // network-level cache so the next read reaches the vendor, drop every entry
        // and in-flight load so the prewarm below re-reads them, and forget which
        // entries the network had confirmed (`changelogRevalidated`): that memo
        // described states that no longer exist, and a disk hit painted after the
        // user asked for fresh notes owes its confirmation again. The scheduled
        // tick does none of that — until #228 it did, hourly, and the workbench pane
        // the user was reading blinked to a spinner and reloaded — it drops only
        // `.failed` entries, so a prewarm that lost the network gets retried on the
        // next tick (nothing else retries one: `prewarmChangelogs` skips keys with a
        // state, and the pane renders `.failed` as the web fallback without asking
        // for a reload). `.loaded` and `.loading` survive untouched, and a new
        // version discovered by the check lives under a new key anyway.
        if intent.restartsChangelogs {
            await ChangelogCache.shared.invalidateAll()
            changelogRevalidated = []
        }
        for (key, state) in changelogState
        where intent.dropsChangelogEntry(failed: state.isFailed) {
            changelogTasks[key]?.cancel()
            changelogTasks[key] = nil
            changelogState[key] = nil
        }
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
        let explicitToken = explicitGitHubToken()
        async let githubToken = Self.resolveGitHubToken(explicit: explicitToken)
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
                let scanned = found
                let retagged = testflight
                found = await Task.detached(priority: .userInitiated) {
                    AppScanner.applyingTestFlightInventory(retagged, to: scanned)
                }.value
                results = sorted(mergeScanned(found))
            } else {
                Log.scan.info("TestFlight: read pending (TCC prompt unanswered) — proceeding without it")
                reapplyTestFlightWhenGranted(tfLoader)
            }
        }

        // The round's snapshot is accurate as of right here: the scan has been
        // published and TestFlight retagging (if any) has landed. The check below
        // takes minutes, during which the list does NOT hold still — a row install,
        // an app's own updater, a staged relaunch, a quit-handoff swap, a channel
        // switch. Whatever differs from this baseline when the round publishes
        // changed underneath it and must not be reverted to the snapshot (#255).
        let roundBaseline = results
        isChecking = true
        // Remember what resolved, and under which Settings value, so the per-app
        // rechecks that follow this round's rows reuse it instead of asking `gh`
        // again (see `resolvedGitHubToken`).
        let token = await githubToken
        resolvedGitHubToken = ResolvedGitHubToken(explicit: explicitToken, token: token)
        let checker = UpdateChecker(
            sources: makeSources(token: token),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(inventory: toolbox),
            testflight: testflight)
        // Ignored apps are not asked after. Nothing would be said about the answer,
        // so the request is pure cost — and against an unauthenticated GitHub hour
        // it is cost that crowds out the apps the user does watch.
        //
        // They stay in the list as rows, but with no remote at all rather than the
        // one they were last checked with: `mergeScanned` would otherwise carry the
        // old remote forward and keep re-deriving a verdict from it, so "Show all"
        // would show a frozen "3.2 → 3.3" that nothing is refreshing any more —
        // worse than saying nothing, because it reads as current.
        let checkable = found.filter { prefs.deservesCheck($0) }
        let ignored = found.filter { !prefs.deservesCheck($0) }
        Log.app.info(
            "refresh: checking \(checkable.count, privacy: .public) apps, skipping \(ignored.count, privacy: .public) ignored")
        let checked = await checker.check(checkable)
            + ignored.map { UpdateResult(app: $0, remote: nil, status: .unknown) }
        results = sorted(CheckRoundWriteBack.publishing(
            checked, changedSince: roundBaseline, live: results))
        // Pre-warm the disk changelog cache for anything pending, so opening its
        // notes is instant (and a no-op network-wise for versions already cached).
        prewarmChangelogs(for: checked)
        // Log any newly-seen releases (those carrying a real vendor timestamp)
        // into the persistent release timeline.
        await recordReleaseTimeline(for: checked)
        // Reconcile the running set once per completed round. The live monitor is
        // KVO on `runningApplications` and is measured to be prompt and complete
        // (issue #247), but this round just spent minutes on the network, and every
        // verdict below reads `isRunning` — `computeRestartInfo` decides which rows
        // say "Relaunch", `defersToSelfUpdater` decides whether an app is handed to
        // its own updater. A floor under the live path costs one snapshot and a
        // memoized resolve (0.095 ms warm) per round.
        //
        // Through the full handler, not a bare `refreshRunningApps()`. A bare
        // refresh would *absorb* whatever the live path missed — the set would
        // quietly become correct, and the next real event, diffing against the
        // already-corrected set, would see nothing changed and skip the channel
        // recheck that the missed quit was supposed to trigger. Reconciling through
        // the handler means a change this call discovers is still reacted to. Its
        // restart branch is inert here (`isChecking` is still true) and
        // `computeRestartInfo` runs immediately below anyway.
        handleRunningAppsChange()
        await computeRestartInfo()
        await computeSelfUpdateStaging()
        if prefs.pruneOrphanBackups {
            await Task.detached(priority: .utility) { BackupStore.pruneOrphans() }.value
        }
        await refreshBackupIndex()
        isChecking = false
        recordCheckOutcomes(checked)
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

    /// Snapshots of what the pure `UpdatePolicy` decides on — the preferences and
    /// the live model state it must never reach for itself. Read on the main
    /// actor, passed by value, so the policy stays side-effect-free and testable.
    private var policySettings: UpdateSettings {
        UpdateSettings(
            appStoreUpdateStrategy: prefs.appStoreUpdateStrategy,
            vendorInstallPolicy: prefs.vendorInstallPolicy,
            declinedElevationKeys: prefs.declinedElevationKeys)
    }
    /// Whether App Store updates take the mas route. Read by the row views: a
    /// wrapped iPhone/iPad app is a store redirect there and a one-click on the
    /// incremental route, and "`canAutoInstall` is false" alone does not say which
    /// (a declined elevation reaches the same branch).
    var appStoreStrategyIsFullDownload: Bool { prefs.appStoreUpdateStrategy == .full }

    private var policyEnvironment: InstallEnvironment {
        InstallEnvironment(
            isHelperEnabled: helperEnabled,
            runningAppPaths: runningAppPaths,
            stagedSelfUpdates: pendingSelfUpdate,
            elevationRequiredPaths: elevationRequiredPaths,
            runningBundleIDs: runningBundleIDs)
    }

    /// The install paths that need an administrator prompt to replace.
    ///
    /// One `access(2)`-class check per app is cheap in isolation and ruinous at
    /// this call site: `policyEnvironment` is built fresh by every `isRunning` /
    /// `canAutoInstall` / `requiresInstaller` query, and the sidebar asks at least
    /// one of those PER ROW. Measured on this machine with 121 apps: 0.86 ms to
    /// build the set once, so a single list pass spent ~105 ms in the filesystem
    /// on the main actor — arrow-key scrubbing crawled and scrolling dropped
    /// frames. (Regression from `95283bf`, which added the elevation gate.)
    ///
    /// Cached against the app paths the set was computed from, so it is rebuilt
    /// exactly when the list changes — including the case the old comment worried
    /// about, an app moving between `~/Applications` and a root-owned location:
    /// that moves its path, which changes the key. What it no longer does is
    /// recompute for a repaint that changed nothing.
    private var elevationRequiredPaths: Set<String> {
        if let cache = elevationPathsCache { return cache }
        let value = InPlaceSwap.elevationRequiredPaths(for: results.map(\.app.path))
        elevationPathsCache = value
        return value
    }

    /// Memo for `elevationRequiredPaths`. Invalidated solely by `results.didSet`,
    /// which is sufficient: the memo can only survive a stretch in which `results`
    /// was never written, and `results` holds value types, so any change to an app
    /// — including a path moving between `~/Applications` and a root-owned
    /// location — is a write that clears this.
    ///
    /// It used to also carry the app paths as a key and compare them on every read.
    /// That check could never fail (`didSet` had already cleared the memo in the
    /// only case it guarded against) and it was not free: building the key meant
    /// `URL.path` per app, which bridges to `NSURL`, and `policyEnvironment` is
    /// rebuilt by every `isRunning` query — one per row. Scrubbing the workbench
    /// sidebar with the arrow keys spent ~6% of the main thread in `-[NSURL path]`
    /// alone, 124 apps x 124 rows of it per keypress. Reading it must not invalidate
    /// a view, which is what `@ObservationIgnored` buys: `@Observable` instruments
    /// `private` stored properties too, so an un-ignored memo makes every `didSet`
    /// clear invalidate the views that read it.
    @ObservationIgnored private var elevationPathsCache: Set<String>?

    /// True when this update installs seamlessly in place (Sparkle EdDSA, or a
    /// drag-to-Applications Homebrew cask). Excludes `pkg` casks, which need the
    /// system installer — see `requiresInstaller`.
    ///
    /// A Homebrew result only ever reaches us when the app was *actually*
    /// installed via Homebrew (the source gates on the local Caskroom), so
    /// `brew install --cask --force` here updates through the app's real
    /// channel — no cross-channel mixing.
    func canAutoInstall(_ result: UpdateResult) -> Bool {
        UpdatePolicy.canAutoInstall(result, settings: policySettings, environment: policyEnvironment)
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
        UpdatePolicy.requiresInstaller(result, environment: policyEnvironment)
    }

    /// Whether, per the user's `vendorInstallPolicy`, this update should be handed
    /// to the app's OWN updater rather than installed over by us right now. True for
    /// running self-updating apps when the policy is `.deferWhenRunning`. A
    /// not-running app (nothing to disturb) or the `.alwaysOverwrite` policy installs
    /// in place as usual. Detection-only vendor apps (no installable spec) already
    /// just "Open" their update path, so they're excluded here.
    func defersToSelfUpdater(_ result: UpdateResult) -> Bool {
        UpdatePolicy.defersToSelfUpdater(result, settings: policySettings, environment: policyEnvironment)
    }

    /// Hand a running self-updating app off to its own update path instead of
    /// swapping the bundle under it: open an app-scheme deep link (Chrome's
    /// `chrome://settings/help` makes Keystone check+download) when the recipe
    /// carries one, otherwise just bring the app forward so its built-in updater
    /// (MAU, a daemon, Sparkle) applies the update on its own schedule.
    func openSelfUpdater(_ result: UpdateResult, activating: Bool = true) {
        installErrors[result.id] = nil
        if let url = result.remote?.pageURL, let scheme = url.scheme,
           scheme != "http", scheme != "https" {
            NSWorkspace.shared.open(
                [url], withApplicationAt: result.app.path,
                configuration: NSWorkspace.OpenConfiguration())
            let note = String(localized: "Opened \(result.app.name) — its own updater is applying the update.")
            installNotes[result.id] = note
            inFlightNotes[result.id] = note
        } else {
            // Detached from this call so a slow LaunchServices activation doesn't
            // block the main actor (see `AppRestarter.launchApp`); the note below
            // is what the user actually waits on, and it lands immediately either way.
            let path = result.app.path
            Task { await AppRestarter.launchApp(path, activates: activating) }
            let note = String(localized: "\(result.app.name) is running — brought it to the front so its own updater applies the update. Quit it (or switch to “Always replace” in Settings) to install directly.")
            installNotes[result.id] = note
            inFlightNotes[result.id] = note
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
        // Say WHY when we skip. These four guards silently swallowed every FS-watcher
        // event and backstop tick, which made "the list didn't update" indistinguishable
        // from "the watcher never fired" — the exact ambiguity that made a dead FSEvents
        // stream take a live-log session to diagnose. Debug level: one line per skipped
        // rescan, off unless someone is looking.
        guard !results.isEmpty, !isChecking, installing.isEmpty, !isInstallingAll else {
            let reason = results.isEmpty ? "no results yet"
                : isChecking ? "a check is running"
                : isInstallingAll ? "batch install in flight"
                : "install in flight (\(installing.count))"
            Log.app.debug("local rescan: skipped — \(reason, privacy: .public)")
            return
        }
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
        // Re-derive which apps are running. `armRunningAppsMonitor` keeps this live
        // off KVO on `runningApplications`, which is measured to catch what the
        // launch/terminate notifications miss (issue #247) — but a rescan re-reads
        // everything else from disk anyway, and this set is one snapshot plus a
        // memoized resolve (0.095 ms warm). Keeping it is a floor under the live
        // path, not a substitute for it.
        refreshRunningApps()
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
        var outdated: [BrewOutdatedFormula]
        do {
            outdated = try await brewFormulaService.outdated()
        } catch {
            Log.app.info("brew outdated --formula failed: \(error.localizedDescription, privacy: .public)")
            outdated = []
        }
        // Merge the formula badges into the tree BEFORE folding in casks: the tree
        // lists `brew leaves`, which casks are not, so a cask name could only ever
        // fail to match there.
        brewFormulae = BrewFormulaService.merge(brewFormulae, outdated: outdated)
        // App-less casks (CLIs, fonts) have no per-app row and no other home — see
        // `BrewOutdatedFormula`. Best-effort: a failure here must not blank the
        // formula count we already have.
        let casks = (try? await brewFormulaService.outdatedCasks()) ?? []
        if !casks.isEmpty {
            Log.app.info("brew outdated: \(outdated.count, privacy: .public) formulae + \(casks.count, privacy: .public) app-less casks (\(casks.map(\.name).joined(separator: ", "), privacy: .public))")
        }
        brewOutdatedFormulae = outdated + casks
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
            let version = formula.availableVersion ?? formula.installedVersion
            // Cheap synchronous skip for what we already hold at this exact version.
            // NOT the authoritative guard — that is the `claim` below, and it has to
            // stay there so we never hold a slot we might not fill. This only keeps
            // a refresh from spawning a task and a disk read per formula for work
            // that is already done: `refreshBrewFormulae` runs on every menu-bar
            // open, not just after an upgrade.
            guard formulaReleases.state(name: formula.name, version: version) == nil else { continue }
            Task { [weak self] in
                guard let self else { return }
                // Decide whether we will load BEFORE claiming, never the other way
                // round. An earlier revision claimed the slot up front and released
                // it again on the no-token/uncached path; that briefly-held claim
                // was enough to turn away the detail pane's `.task(id:)` — which
                // fires once per version and had no reason to fire again — leaving
                // an open pane spinning on an entry nobody would ever fill.
                let cached = await self.formulaReleaseService.cached(
                    for: formula.name, version: version)
                let token = await tokenTask.value
                // No token and not on disk: stay deliberately lazy/on-select so a
                // screenful of outdated formulae can't burn the 60/hr
                // unauthenticated budget. Claiming nothing leaves the on-select
                // path free to do its job.
                guard cached != nil || token != nil else { return }
                // Claiming is what serializes us against a concurrent
                // `ensureFormulaReleaseLoading` (the user selecting this same
                // formula): exactly one of the two wins the slot and fetches, and
                // the loser simply drops out. Whichever order they arrive in, the
                // `brew info` + GitHub work happens once.
                guard self.formulaReleases.claim(name: formula.name, version: version) else { return }
                if let cached {
                    self.formulaReleases.finish(name: formula.name, version: version, release: cached)
                    return
                }
                // A token means we have budget, so fetch up front. We can't delegate
                // to `ensureFormulaReleaseLoading` — its own guard would reject the
                // slot we just claimed — so do the load it would do.
                let release = await self.formulaReleaseService.release(
                    for: formula.name, version: version, token: token)
                self.formulaReleases.finish(name: formula.name, version: version, release: release)
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
        brewUpgradeNote = String(localized: "Starting…")
        // Snapshot the target set so dependency formulae brew pulls in (which also
        // emit a 🍺 line) don't inflate the count past the user-visible total.
        let targets = Set(brewOutdatedFormulae.map(\.name))
        // Cask tokens are upgraded by name in a second pass — never a bare
        // `brew upgrade --cask`, which would reach GUI casks this surface doesn't own.
        let caskTokens = brewOutdatedFormulae.filter { $0.kind == .cask }.map(\.name)
        brewUpgradeTotal = targets.count
        brewUpgradeDone = 0
        defer { brewUpgrading = false; brewUpgradeNote = nil; brewUpgradeDone = 0; brewUpgradeTotal = 0 }
        do {
            let onOutput: @Sendable (String) -> Void = { [weak self] line in
                Task { @MainActor in
                    self?.brewUpgradeNote = line
                    // One 🍺 Cellar line per poured formula — count only the targeted
                    // ones, clamped so it never reads past the total. Casks don't emit
                    // a Cellar line, so they're counted separately below.
                    if let name = Self.brewPouredFormula(from: line), targets.contains(name),
                       let self, self.brewUpgradeDone < self.brewUpgradeTotal {
                        self.brewUpgradeDone += 1
                    }
                }
            }
            try await brewFormulaService.upgradeAll(onOutput: onOutput)
            if !caskTokens.isEmpty {
                try await brewFormulaService.upgrade(casks: caskTokens, onOutput: onOutput)
                brewUpgradeDone = min(brewUpgradeDone + caskTokens.count, brewUpgradeTotal)
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
        formulaUpgradeNotes[name] = String(localized: "Starting…")
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
        if l.contains("pouring") || l.contains("installing") { return String(localized: "Installing…") }
        if l.contains("downloading") || l.contains("fetching") || l.contains("bottle") { return String(localized: "Downloading…") }
        if l.contains("cleaning") || l.contains("cleanup") { return String(localized: "Cleaning up…") }
        return nil
    }

    /// One-line "x/n" status for an in-flight bulk upgrade — the count of the next
    /// formula being worked on over the total. nil when no bulk run is active.
    var brewBulkProgressText: String? {
        guard brewUpgrading, brewUpgradeTotal > 0 else { return nil }
        let current = min(brewUpgradeDone + 1, brewUpgradeTotal)
        return String(localized: "Upgrading… (\(current)/\(brewUpgradeTotal))")
    }

    /// Fetch a formula's release notes once, on first selection. Idempotent for a
    /// given version: a loaded/loading entry for that same version is left alone, so
    /// reselecting renders the cache instantly. A DIFFERENT version re-fetches — the
    /// caller must pass the version it is about to render, or the pane shows notes
    /// for a version it is no longer displaying.
    func ensureFormulaReleaseLoading(name: String, version: String) {
        guard formulaReleases.claim(name: name, version: version) else { return }
        let explicitToken = explicitGitHubToken()
        Task {
            let token = await Self.resolveGitHubToken(explicit: explicitToken)
            let release = await formulaReleaseService.release(for: name, version: version, token: token)
            formulaReleases.finish(name: name, version: version, release: release)
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
            // Usually the last thing to clear after an install, so this is where the
            // frozen order normally lifts.
            self?.releaseRowOrder()
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
        // Hold the list still for the duration — this row's rank is about to change
        // under whoever is clicking down the list. Every exit below clears
        // `installing[id]` first, so the release check here sees the settled state.
        pinRowOrder()
        defer { releaseRowOrder() }
        // The row was marked `.queued` by the caller before this suspension
        // point, so the UI already shows the wait and the re-entrancy guard
        // already rejects re-clicks; here we just park until a slot frees (the
        // semaphore is FIFO).
        //
        // The actual concurrency authority — the download permit (held only
        // while fetching bytes) and the apply permit (held while
        // extracting/verifying/swapping) — is taken inside `performInstall`,
        // around the phases that need it, NOT here: holding both for the whole
        // install would couple the two stages again, so a slot would sit idle
        // on the network while its install swaps. This function only holds the
        // per-host / App Store gate below, for the whole install.
        //
        // Per-host sub-cap: several apps that download from the *same* host (GitHub
        // releases, one vendor CDN) would otherwise split that host's bandwidth and
        // are the most likely to trip its rate limiter / WAF. Acquired *before* the
        // download permit so a saturated host parks here without burning a download
        // slot (which would starve apps on other, idle hosts).
        //
        // App Store rows are special-cased to a dedicated single-slot gate instead:
        // they drive the one App Store UI (AX/mas), so two at once would fight over
        // it — and `MacAppStoreSource` gives them `apps.apple.com` as a `downloadURL`
        // host, which would otherwise let two share the per-host cap of 2. Homebrew
        // *does* carry a real `downloadURL` host (the cask's source CDN), so it still
        // takes a host gate as a coarse limiter even though brew fetches the bytes.
        let isAppStore = result.remote?.sourceName == "App Store"
        let gate: AsyncSemaphore? = isAppStore
            ? Self.appStoreInstallGate
            : result.remote?.downloadURL?.host.map(hostInstallGate(for:))
        await gate?.wait()
        // A queued item cancelled while waiting — e.g. "Update All" was stopped
        // before this row's turn came up — releases its slots and clears its claim
        // without installing. (`installAll`'s cleanup also sweeps any claim that never
        // reached here at all.)
        if Task.isCancelled {
            installing[id] = nil
            await gate?.signal()
            return false
        }
        // What the host gate protects is a HOST'S BANDWIDTH, so it belongs to the
        // download phase and nothing after it. Held for the whole install, it made
        // two same-host apps serialize across each other's extract, swap, and
        // relaunch too — which is why splitting the permits only paid off for apps
        // on different hosts. `performInstall` hands it back the moment its fetch
        // ends; the handle makes that idempotent so the release below still covers
        // every path that never got that far (an early-out, a throw, a cancel).
        //
        // The App Store gate is NOT handed over: it exists to keep two installs off
        // the single store UI (AX/mas), which spans the whole install, not the fetch.
        let hostGate = GateHandle(gate)
        // Machine-wide exclusion, taken here rather than around the whole batch:
        // a row parked on the host gate must not hold it. Reference-counted
        // inside the process, so this app's own concurrent installs join one
        // claim instead of blocking each other (`flock` is exclusive per open
        // file description, not per process).
        //
        // Refused, not queued: the other holder is `duo install`, which may be
        // part-way through a large download, and a row that spins indefinitely
        // is worse than one that says who has it.
        do {
            try await ProcessInstallLock.shared.claim()
        } catch {
            Log.install.error("install blocked by the machine install lock: \(result.app.name, privacy: .public)")
            installErrors[id] = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            installing[id] = nil
            await hostGate.release()
            return false
        }
        let didInstall = await performInstall(
            result, notify: notify, deferBookkeeping: deferBookkeeping,
            releaseAfterDownload: isAppStore ? nil : hostGate)
        await ProcessInstallLock.shared.release()
        await hostGate.release()
        // If something self-updated externally while this install ran, its rescan was
        // deferred — drain it now that the install is done (no-op in a batch, which
        // drains once at the end of `installAll`, and when nothing was deferred).
        await drainDeferredLocalRescan()
        return didInstall
    }

    /// A semaphore permit that can be handed to a callee to release early, while the
    /// owner keeps a release of its own for the paths the callee never reaches.
    /// Releasing twice is a no-op, so both sides can call it unconditionally —
    /// without that, "release at the end of the download" and "release when the
    /// install returns" would double-signal and inflate the pool.
    ///
    /// Main-actor isolated: it's handed between two main-actor functions, so the
    /// `released` flip needs no locking.
    @MainActor
    final class GateHandle {
        private var gate: AsyncSemaphore?
        init(_ gate: AsyncSemaphore?) { self.gate = gate }
        func release() async {
            guard let gate else { return }
            self.gate = nil
            await gate.signal()
        }
    }

    @discardableResult
    private func performInstall(
        _ result: UpdateResult, notify: Bool, deferBookkeeping: Bool,
        releaseAfterDownload: GateHandle? = nil
    ) async -> Bool {
        let id = result.id
        installErrors[id] = nil
        installNotes[id] = nil
        // Retract the "App Store is waiting on you" note on every exit — the prompt
        // it describes is gone once this returns, whichever way it returns. Matched
        // on the text we wrote so a note someone else put there in the meantime
        // (`backupCurrent`'s missing-rollback-point warning) stands.
        defer {
            if let mine = appStoreQuitNotes.removeValue(forKey: id),
               installNotes[id] == mine {
                installNotes[id] = nil
            }
        }
        Log.install.info("install start: \(result.app.name, privacy: .public) \(result.app.shortVersion ?? "?", privacy: .public) → \(result.remote?.displayVersion ?? "?", privacy: .public) via \(result.remote?.sourceName ?? "?", privacy: .public)")

        // Defensive re-check: the app may already be current — e.g. a manual
        // pkg install we couldn't observe, or it was updated by its own updater
        // since the last scan. Re-read it from disk and re-query before we
        // download or replace anything.
        installing[id] = .checking
        let result = await recheck(result)
        replaceRow(result)
        // Only `.updateAvailable` installs. The other endings all stop here, but
        // they are NOT the same ending, and this used to report them as if they
        // were: a source that timed out while you clicked Update was logged as
        // "already current on disk", which reads as a fact about the bundle and
        // sends the next person to the wrong place. See `PreInstallGate`.
        let decision = PreInstallGate.decision(for: result.status)
        if decision != .proceed {
            switch decision {
            case .alreadyCurrent:
                Log.install.info(
                    "install skipped: \(result.app.name, privacy: .public) already current on disk")
            case .managedElsewhere:
                Log.install.info(
                    "install skipped: \(result.app.name, privacy: .public) is managed elsewhere — nothing to install here")
            case .cannotConfirm(let message):
                // Not a verdict about the app: we never found out. Retryable, and
                // said so, rather than filed as "nothing to do".
                Log.install.error(
                    "install aborted: \(result.app.name, privacy: .public) — the pre-install re-check could not confirm an update: \(message ?? "no source covers this app", privacy: .public)")
            case .proceed:
                break  // unreachable: guarded above
            }
            // Unchanged for every ending: the bundle on disk may still be newer than
            // the running process (a manual install, a self-updater), so the restart
            // state is recomputed either way.
            await computeRestartInfo()
            installing[id] = nil
            return false
        }

        // Install policy: a running self-updating app is handed to its own
        // updater rather than swapped under it — unless the user chose to always
        // overwrite. (Re-checked here, not just in the UI, so any caller honors it.)
        // Re-derive the live running set first: `runningAppPaths` is updated by the
        // running-apps monitor, whose events aren't delivered while this menu-bar
        // app is App-Napped — so a quit that happened during a nap can
        // leave the set stale and make `isRunning` (and thus this defer) lie. This is
        // a consequential decision, so take a fresh `runningApplications` snapshot
        // for it. (`refreshRunningApps` memoizes each path's *resolved form* through
        // `RunningBundlePathCache`, but membership always comes from the live
        // snapshot and a path that has left it is dropped — so what this call is
        // here for is exactly what it still does.)
        refreshRunningApps()
        let wasRunningBeforeInstall = isRunning(result)
        if defersToSelfUpdater(result) {
            Log.install.info("install deferred to self-updater: \(result.app.name, privacy: .public) (running, policy=deferWhenRunning)")
            // Don't pull the app forward when this deferral came from Update All.
            // A single row's Open is something the user just asked for, so the
            // foreground is what they want; a batch can hit this branch for every
            // remaining self-updating app in turn — most easily by switching the
            // policy mid-batch — and activating each one would fight the user for
            // focus repeatedly.
            openSelfUpdater(result, activating: !deferBookkeeping)
            installing[id] = nil
            return false
        }

        // The app's own updater may already have this release in flight. Ours would
        // be a second copy of the same bytes, and for a Sparkle app it is worse than
        // wasteful: whichever finishes second overwrites the first, so a ChatGPT-sized
        // pair of downloads can settle on the OLDER build (observed 2026-08-22 — we
        // installed 6971, its own updater then landed the 6962 its backend was
        // shipping, ~1.8 GB spent to move backwards).
        //
        // Deliberately NOT gated on `vendorInstallPolicy`: this isn't a preference
        // about who should apply updates, it's an unconditional "those bytes are
        // already coming". `.alwaysOverwrite` still means we install rather than
        // hand off — it just doesn't mean racing a transfer already underway.
        //
        // Unconditional in the other direction too: a manual click yields the same
        // way, because the alternative is the user paying twice for one update. The
        // note says so, and the next check installs normally once the transfer has
        // either landed (row goes current) or gone stale (detector stops matching).
        // Its own updater may already have a build unpacked and parked on the next
        // quit. Anything we install now is undone when that lands — including when
        // the staged build is OLDER than ours, which is how the mini ended up back
        // on 6962 after we installed 6971 twice. So this asks for any staged build,
        // not just a newer one.
        if let staged = UpdatePolicy.stagedBlocksInstall(
            result,
            staged: SelfUpdaterStaging.staged(
                for: result.app, requireNewerThanInstalled: false)) {
            Log.install.info("install yielded to staged self-update: \(result.app.name, privacy: .public) has \(staged.version, privacy: .public) waiting for a quit")
            let note = String(localized: "\(result.app.name) has already downloaded \(result.stagedRelaunchLine(staged).to) and will apply it when you quit it — installing now would be undone.")
            installNotes[id] = note
            inFlightNotes[id] = note
            installing[id] = nil
            return false
        }

        if let inFlight = SelfUpdaterStaging.inFlightDownload(for: result.app) {
            Log.install.info("install yielded to in-flight self-update: \(result.app.name, privacy: .public) (\(inFlight.bytes, privacy: .public) bytes staged in \(inFlight.directory.lastPathComponent, privacy: .public))")
            let note = String(localized: "\(result.app.name) is downloading this update itself — left it to finish rather than fetching the same bytes twice.")
            installNotes[id] = note
            inFlightNotes[id] = note
            installing[id] = nil
            return false
        }

        // Back up the current bundle first (when enabled) so this update can be
        // rolled back — every route, App Store included: the store only ever
        // offers an app's current version, so without a copy of our own that
        // update is the one that cannot be undone.
        // Which routes are worth a rollback point is `InstallCoordinator`'s call,
        // shared so `duo install` cannot quietly skip the safety net the app
        // provides — it did, until a real install through the CLI showed the
        // backup timestamp hadn't moved.
        let backupRoute = InstallCoordinator.route(
            for: result, requiresInstaller: requiresInstaller(result))
        if prefs.keepBackups, InstallCoordinator.wantsBackup(backupRoute),
           !(backupRoute == .appStore && appStoreRouteWillNotInstall(result)) {
            await backupCurrent(result, route: backupRoute)
        }

        do {
            // Everything except the App Store is fetched and applied by
            // `InstallCoordinator`, which owns the permit discipline (see there
            // for why the apply permit is handed back the moment the swap lands,
            // before any restart bookkeeping). It shares this class's permit
            // pool, so the App Store branch below still competes for the same
            // budget — a category exempt from it makes the number meaningless.
            //
            // The flag+defer below covers the ERROR path only: a throw between
            // acquisition and the explicit release still hands the permit back.
            // Paths that never acquire it leave the flag false so the release
            // no-ops.
            // Same flag+defer for the download permit, used by the branches that
            // can't take it with `withDownloadPermit` because their fetch isn't a
            // single expression — today that's App Store, whose store-daemon call
            // is spread across the region-locked/AX/mas routes with early-outs of
            // its own. Every install type consumes a permit for the bytes it
            // causes to be fetched, including the ones another process fetches on
            // our behalf: the permits are a budget for this machine's network, and
            // a category exempt from it makes the number meaningless.
            var downloadPermitHeld = false
            defer { if downloadPermitHeld { Self.installPermits.signalDownload() } }
            // Measured here, before any route touches the bundle, so both ends of
            // the recorded transition come from the same place. `result` is a
            // snapshot from the last refresh, and an app with its own updater can
            // replace itself between that refresh and this click — the case the
            // deferred-rescan work around external self-updates exists for. Taking
            // the "from" side from that snapshot while the "to" side is read off
            // disk would write a transition the machine never made.
            let fromBuild = InstalledBuild.read(at: result.app.path)
                ?? result.app.buildVersion

            let route = InstallCoordinator.route(
                for: result, requiresInstaller: requiresInstaller(result))

            switch route {
            case .installer, .homebrew, .vendor, .sparkle:
                // A missing cask token used to reset the spinner and return
                // false here; the coordinator throws instead, which the catch
                // below settles the same way (and now says why).
                let outcome = try await Self.installCoordinator.perform(
                    result, route: route,
                    progress: { stage in Task { @MainActor in self.setStage(id, stage) } },
                    releaseAfterDownload: { await releaseAfterDownload?.release() },
                    beforeInstallerOpen: { await self.retireStagedPackage(for: id) })
                recordEffectiveHost(result, finalHost: outcome.finalHost)
                await recordTraffic(
                    result, bytes: outcome.bytesDownloaded, applied: outcome.applied,
                    fromBuild: fromBuild, usedDelta: outcome.usedDelta)
                if let packageURL = outcome.stagedPackageURL {
                    // pkg casks: the actual install happens in macOS's installer
                    // under the user's control, so we don't mark it up to date —
                    // a later rescan will. Remember what we handed over so the row
                    // can offer "Install" — a re-open of this exact file — instead
                    // of "Update", which would download the same hundreds of
                    // megabytes again. If they dismiss the window the package is
                    // still on disk and still the right version.
                    recordStagedPackage(result, packageURL: packageURL)
                    installing[id] = nil
                    return true
                }
            case .appStore:
                // On the mas route a wrapped iPhone/iPad app can only be updated by
                // the App Store app itself: mas has no Mac-store entry for it and
                // errors "No apps found for ADAM ID". `canAutoInstall` already keeps
                // these out of the one-click and Install-All there, but guard here
                // too so any other caller redirects rather than firing a doomed
                // install. The AX route handles them and is not redirected.
                //
                // Region-locked apps are excluded from the redirect on BOTH routes:
                // their product page reads "App Not Available", so sending anyone
                // there is a dead end. They belong to the `isRegionMismatch` branch
                // below, which drives App Store's Updates list instead — the one
                // place an installed region-locked app can still update. (Before this
                // ordering, a wrapped region-locked app on the mas route got the dead
                // deep link; the branch below was unreachable for it.)
                if result.app.isiOSAppOnMac,
                   prefs.appStoreUpdateStrategy == .full,
                   result.remote?.appStore?.isRegionMismatch != true {
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
                // Arm the reopen before anything can quit the app. On this route
                // the store's own daemon terminates a running app to replace its
                // bundle and never brings it back, whether the user gave consent
                // in our sheet or in App Store's own — and the `mas` path raises
                // no sheet at all. `AppStoreQuitPolicy` carries the evidence and
                // the reason the signal is "was it running", not "did they click".
                if AppStoreQuitPolicy.armsReopen(
                    route: route, wasRunningBeforeInstall: wasRunningBeforeInstall) {
                    reopenAfterQuit[id] = .storeMayCloseIt
                    // Say what is about to happen, because nothing else will.
                    //
                    // The store cannot replace a running bundle, so it raises
                    // "<app> cannot be open during installation" and waits — with no
                    // timeout on our side and none on `mas` either. That prompt is a
                    // small panel inside App Store's own window, which may be showing
                    // some unrelated product page; App Store bounces its Dock icon a
                    // few times and stops; and we are an accessory app with no Dock
                    // icon to bounce. So the whole machine can sit on a prompt nobody
                    // knows exists, holding a download permit and the install gate.
                    //
                    // No timeout is needed to say this, and no Accessibility grant:
                    // the same predicate that arms the reopen — App Store route, app
                    // running — is the one that predicts the prompt, and it is known
                    // here, before anything has started.
                    let note = String(localized: "App Store can't replace \(result.app.name) while it's open. If this looks stuck, switch to App Store and click Continue — it waits until you do. \(result.app.name) reopens when the update lands.")
                    installNotes[id] = note
                    appStoreQuitNotes[id] = note
                    inFlightNotes[id] = note
                }
                installing[id] = .downloading(fraction: 0)
                // Both routes download through the App Store daemon, so we never see
                // those bytes — intentionally not recorded (we only count measured).
                // We still take a download permit for them: the bytes are fetched by
                // another process but over the same connection as everything else, so
                // leaving this route outside the budget would let an App Store update
                // run alongside a full complement of our own downloads. The store's
                // fetch and install are one opaque call, so the permit spans both —
                // like Homebrew's fused upgrade, and unlike the archive routes, which
                // hand the slot back the moment the bytes are down.
                await Self.installPermits.waitForDownload()
                downloadPermitHeld = true
                guard !Task.isCancelled else {
                    // Cancelled while parked on the permit: nothing started. The
                    // defer above hands it back.
                    reopenAfterQuit[id] = nil
                    installing[id] = nil
                    return false
                }
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
                        reopenAfterQuit[id] = nil
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
                    } requestQuit: { [weak self] appName in
                        Task { @MainActor in self?.requestQuit(id: id, appName: appName) }
                    } quitAnswer: { [weak self] in
                        await MainActor.run { self?.quitAnswer(id: id) ?? .pending }
                    } withdrawQuit: { [weak self] in
                        Task { @MainActor in self?.withdrawQuit(id: id) }
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
                    // Pairs: `displayVersion` against a marketing-only disk read
                    // is equal every time for a vendor that freezes its marketing
                    // string, so "already current" was decided by two strings that
                    // could not differ. The `mas outdated` veto below is what kept
                    // this one honest; the pair is what makes it true on its own.
                    if let target = result.remote?.versionSide, !target.isEmpty,
                       case let onDisk = Self.readVersionSide(result.app.path),
                       !onDisk.isEmpty,
                       !VersionComparator.isNewer(target, than: onDisk),
                       await masInstaller.outdatedContains(adamID: adamID) != true {
                        Log.install.notice("App Store: \(result.app.name, privacy: .public) already current (on-disk \(onDisk.text(withBuild: true), privacy: .public) ≥ target \(target.text(withBuild: true), privacy: .public), not outdated per mas) — skipping install before download")
                        await refreshRow(result)
                        reopenAfterQuit[id] = nil
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
                        } requestQuit: { [weak self] appName in
                            Task { @MainActor in self?.requestQuit(id: id, appName: appName) }
                        } quitAnswer: { [weak self] in
                            await MainActor.run { self?.quitAnswer(id: id) ?? .pending }
                        } withdrawQuit: { [weak self] in
                            Task { @MainActor in self?.withdrawQuit(id: id) }
                        }
                    // Not for a wrapped iPhone/iPad app: mas cannot install one at
                    // all, so falling back to it would trade a fixable permission
                    // prompt for a guaranteed "No apps found for ADAM ID". Those fall
                    // to the case below, which asks for the grant the AX route needs.
                    case .incremental where MASInstaller.isAvailable && !result.app.isiOSAppOnMac:
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
                        reopenAfterQuit[id] = nil
                        installing[id] = nil
                        installErrors[id] = AppStoreAXInstaller.AXError.notTrusted.errorDescription
                        presentAccessibilityPermissionFlow()
                        return false
                    }
                }
                // The store is done fetching and installing: release before the
                // restart bookkeeping below, same as the archive routes.
                Self.installPermits.signalDownload()
                downloadPermitHeld = false
            }
            // An App Store update that closed a running app: bring it back. Not
            // only the ones the user OK'd through our own prompt — the store quits
            // the app on this route however consent was given, so the arming above
            // keys off "was it running", not "did they click Relaunch". Reopened in
            // the background (see `reopenIfQuitForUpdate`): App Store has been
            // pulled to the front by then, and whatever the user moved on to
            // shouldn't be interrupted. Apps that weren't running never enter
            // `reopenAfterQuit`, so this only reopens what was closed. Done before
            // the recheck so the running-version probe sees the relaunched process.
            reopenIfQuitForUpdate(result, installSucceeded: true)

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

            // An install that changed nothing is a failure, however quietly it
            // returned. The recheck above already knows: it re-read the bundle and
            // re-ran the source, so a row that still offers the same update while
            // the bytes on disk never moved means the download did not carry the
            // release it was supposed to. Docker shipped exactly that — its appcast
            // lists 4.86.0 before 4.87.0, the first-match asset pattern fetched the
            // older image, 574 MB and a 2.26 GB backup later the app was still
            // 4.86.0, and this code logged "install done" and flashed "Updated ✓".
            //
            // Deliberately narrow, because a false "it didn't work" is its own kind
            // of lie: only routes we apply ourselves and that are finished when
            // `perform` returns. `.installer` hands a pkg to macOS Installer, which
            // the user may not have clicked through yet; `.appStore` lands
            // asynchronously. Comparing against the row's own verdict rather than
            // raw version strings keeps every source's quirks (`versionIsBuild`,
            // build-vs-marketing schemes) out of this decision.
            let appliedNothing = [.vendor, .sparkle, .homebrew].contains(route)
                && updated.app.shortVersion == result.app.shortVersion
                && updated.app.buildVersion == result.app.buildVersion
                && isActionableUpdate(updated)
            if appliedNothing {
                let onDisk = updated.app.shortVersion ?? updated.app.buildVersion ?? "?"
                let target = result.remote?.displayVersion ?? result.remote?.shortVersion ?? "?"
                Log.install.error("install applied nothing: \(updated.app.name, privacy: .public) still \(onDisk, privacy: .public) on disk after installing \(target, privacy: .public)")
                installErrors[id] = String(localized: "The install finished without an error, but \(updated.app.name) on disk is still \(onDisk) — what was downloaded wasn't \(target).")
                reopenIfQuitForUpdate(result, installSucceeded: false)
                installing[id] = nil
                relaunching.remove(id)
                return false
            }

            // Tell the user it landed. If the app was running, its live process
            // is still on the old code (so it's in needsRestart) — point them at
            // the Restart action. Otherwise the in-place swap is already fully in
            // effect and there's nothing left to do.
            let version = updated.app.shortVersion
            let disposition = PostInstallDisposition.resolve(
                defersBookkeeping: deferBookkeeping,
                wasRunningBeforeInstall: wasRunningBeforeInstall,
                needsRestartAfterRescan: needsRestart.contains(updated.id)
            )
            switch disposition {
            case .awaitingBatchRestart:
                let from = result.app.shortVersion ?? result.app.buildVersion ?? "?"
                pendingBatchRestart[updated.id] = from
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public) on disk, waiting for batch restart")

            case .awaitingRestart:
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public) on disk, awaiting restart")
                if notify { UpdateNotifier.readyToRestart(app: updated.app.name, version: version, appID: updated.app.bundleID) }
                // Finish the job the user started: a one-click Update shouldn't leave
                // a second "Relaunch" click dangling. Auto-relaunch unless the user
                // opted out. In a batch we skip here and let `installAll` restart the
                // whole set once at the end (so parallel installs don't quit apps out
                // from under each other mid-run). `restart()` is graceful — it honors
                // save prompts and leaves the badge if the app won't quit.
                if prefs.autoRestartAfterUpdate, !deferBookkeeping {
                    await restart(updated)
                }
            case .complete:
                Log.install.info("install done: \(updated.app.name, privacy: .public) now \(version ?? "?", privacy: .public)")
                if notify { UpdateNotifier.updated(app: updated.app.name, version: version) }
                // The swap is fully in effect and nothing is left to do, so this row is
                // about to filter out of the list. Hold it briefly with an "Updated ✓"
                // confirmation (see `visible` and `RowAction.state`) so completion is legible
                // instead of the row just disappearing mid-progress.
                markJustUpdated(id)
            }
        } catch is CancellationError {
            // The install was cancelled — a stopped batch, or the row's own
            // task torn down. A cancellation isn't a failure: settle the row
            // silently instead of the red "cancelled" error the generic catch
            // would leave. All permits are already back in their pools (the
            // `with*` helpers release on throw; the flag+defer covers the
            // apply side).
            Log.install.info("install cancelled: \(result.app.name, privacy: .public)")
            // The fifth arm/consume site, and the one the earlier sweep missed:
            // this returns before the trailing `reopenIfQuitForUpdate`, so a
            // cancelled App Store install would leave its entry behind for some
            // later install of the same row to consume.
            reopenAfterQuit[id] = nil
            installing[id] = nil
            relaunching.remove(id)
            return false
        } catch let error as AppManagementRequiredError {
            // The swap was blocked by the App Management privacy gate. There's no
            // API to request it, so guide the user to the right Settings pane with
            // the drag-to-authorize panel; the install can be retried once granted.
            Log.install.error("install blocked by App Management: \(result.app.name, privacy: .public)")
            installErrors[id] = error.errorDescription
            presentAppManagementPermissionFlowForInstallFailure()
        } catch is AuthorizationDeclinedError {
            // The user dismissed the administrator panel. Nothing failed and nothing
            // was touched, so this leaves no red error — it records the refusal
            // against this install PATH, which drops the row to "Open" (via
            // `UpdatePolicy.elevationDeclined`) instead of re-raising that panel on
            // every future release. "Ask for administrator access" in the row's
            // context menu is the way back.
            Log.install.notice("install: administrator access declined for \(result.app.name, privacy: .public) — no longer offering a one-click for this copy")
            installErrors[id] = nil
            prefs.setElevationDeclined(true, result.app)
        } catch let error as MASInstaller.MASError where error.isHelperApproval {
            // The App Store route needs the background helper and it isn't usable.
            // Left as a red note this dead-ends a normal user: the fix lives in a
            // System Settings pane they have no reason to know about, and DuoUpdater's
            // own Diagnostics page hides its Enable button once macOS *claims* the
            // item is enabled. So prompt directly, the same way an App Management
            // failure floats its authorize panel.
            Log.install.error("install blocked by helper approval: \(result.app.name, privacy: .public)")
            installErrors[id] = error.errorDescription
            presentHelperApprovalFlowForInstallFailure()
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
               let target = result.remote?.versionSide, !target.isEmpty,
               case let onDisk = Self.readVersionSide(result.app.path), !onDisk.isEmpty,
               // Pairs. Unlike the pre-flight skip above there is NO `mas outdated`
               // veto behind this one, so a marketing-only comparison quietly
               // reclassified a genuinely-failed install as "already current",
               // swallowed the error and cleared the row.
               !VersionComparator.isNewer(target, than: onDisk) {
                Log.install.notice("install: \(result.app.name, privacy: .public) reported a failure but is already at \(onDisk.text(withBuild: true), privacy: .public) on disk (target \(target.text(withBuild: true), privacy: .public)) — treating as already-current, clearing the stale row")
                // `false`: OUR install threw and applied nothing. Something else
                // brought the bundle up to date, and whatever that was is not
                // waiting on a quit from us. An app still running here is one
                // nobody has asked to close, so arming a relay would relaunch it
                // whenever the user next quits it themselves. An app that is
                // already down still gets reopened — that path ignores this flag.
                reopenIfQuitForUpdate(result, installSucceeded: false)
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
        reopenIfQuitForUpdate(result, installSucceeded: false)
        // Read the outcome BEFORE dropping the spinner. `installing[id]` is what
        // holds this row out of `pruneSettledInstallErrors`, so once it is nil the
        // error is something a background rescan is allowed to delete — and this
        // return value is what `installAll` counts as a success. Nothing can
        // interleave between the two lines today (main actor, no suspension
        // point), but a return value that silently depends on that is one `await`
        // away from reporting a failed install as installed.
        let failed = installErrors[id] != nil
        installing[id] = nil
        // Drop the "Relaunching…" indicator a confirmed App Store quit raised, on
        // every exit (success or error) so a failed/cancelled install can't strand it.
        relaunching.remove(id)
        // True only if we reached the install path without throwing.
        return !failed
    }

    /// True when the row's install error is the mas receipt-import dead end — mas
    /// can't finish it (a macOS/CommerceKit limitation), so the row offers a manual
    /// jump to the App Store's Updates page instead of just showing the red note.
    func showsAppStoreUpdatesFallback(_ id: String) -> Bool {
        installErrors[id]?.contains(MASInstaller.MASError.appStoreUpdatesHint) == true
    }

    /// True when the row failed because the App Store helper isn't usable, so the row
    /// offers a direct way in instead of naming a Settings pane the user has to hunt
    /// for. The dialog already fired once for this wave; this is what's left on the
    /// row afterwards, and what a user who dismissed it can still act on.
    func showsHelperApprovalFallback(_ id: String) -> Bool {
        installErrors[id]?.contains(MASInstaller.MASError.helperApprovalHint) == true
    }

    /// The other helper failure: registered and switched on, but the process
    /// answering for it belongs to a bundle we've since replaced. Distinct action
    /// from the approval one — Login Items is the wrong place to send anyone here.
    func showsHelperRestartFallback(_ id: String) -> Bool {
        installErrors[id]?.contains(MASInstaller.MASError.helperRestartHint) == true
    }

    /// Restart the stranded daemon (administrator prompt), then clear the row's
    /// error so the retry is a plain "Update" again rather than a red line the
    /// user has to reason about. Leaves the error in place if they dismiss the
    /// prompt — nothing changed, so the row shouldn't claim otherwise.
    func restartAppStoreHelper(_ id: String) async {
        // One authorization panel at a time, however many times the row is
        // pressed: a second press while the first is up stacks another prompt and
        // kickstarts the daemon twice.
        guard !restartingHelper else { return }
        restartingHelper = true
        defer { restartingHelper = false }
        guard await helperClient.restartDaemon() else { return }
        helperEnabled = helperClient.isEnabled
        installErrors[id] = nil
    }

    /// True while the helper-restart authorization panel is up, so the row's
    /// button can disable itself instead of queueing prompts.
    private(set) var restartingHelper = false

    /// Rebuild the helper's registration and, if it still isn't enabled, open the
    /// Login Items pane. Same two steps as the dialog, minus the dialog.
    func enableAppStoreHelper() {
        helperClient.reregister()
        helperEnabled = helperClient.isEnabled
        if !helperClient.isEnabled { helperClient.openLoginItems() }
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
    /// Resolved bundle path → the launch dates of every running copy at that path.
    /// Keyed by path (not bundle id) for the same reason `runningBuildVersions` is:
    /// two channels can share a bundle id, and only the exact path that's running is
    /// stale. `NSWorkspace.runningApplications` is a cheap main-thread read.
    private func runningLaunchDatesByPath() -> [String: [Date]] {
        var map: [String: [Date]] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let url = app.bundleURL else { continue }
            let key = url.resolvingSymlinksInPath().path
            // `launchDate` is documented nilable (AppKit didn't observe the launch).
            // Treat unknown as the distant past — i.e. as a copy that predates any
            // hand-off — so a running copy we can't date biases toward OFFERING a
            // restart rather than silently deciding it's fresh and dropping the entry.
            // A spurious restart PROMPT is harmless (the user chooses); missing a
            // genuinely-stale process is the failure this feature exists to prevent.
            map[key, default: []].append(app.launchDate ?? .distantPast)
        }
        return map
    }

    /// Turn "a package we handed off has landed and left a stale copy running" into a
    /// Restart affordance + a one-time notification — the pkg counterpart of the
    /// in-place routes' `awaitingRestart` disposition, which the `.installer` route
    /// can't reach because its install finishes asynchronously in macOS's Installer.
    ///
    /// Driven by launch time, not version comparison (see `PackageRestartState`), so
    /// it works even for apps whose reported version never moves, and so a vendor pkg
    /// that relaunches the app itself produces no spurious prompt. Scoped to packages
    /// WE staged, so an unrelated background self-update never trips it.
    ///
    /// Rebuilds `packageRestartPending` from scratch each pass; the caller unions it
    /// into `needsRestart`. Must run before `computeRestartInfo` finalizes that set.
    private func reconcilePackageRestarts() {
        guard !stagedPackages.isEmpty else {
            packageRestartPending.removeAll()
            notifiedPackageRestart.removeAll()
            return
        }
        let launchDates = runningLaunchDatesByPath()
        let onDiskByID = Dictionary(
            results.map { ($0.id, $0.app) }, uniquingKeysWith: { a, _ in a })

        var pending: Set<String> = []
        var settledIDs: [String] = []
        for (id, staged) in stagedPackages {
            guard let app = onDiskByID[id] else {
                // The row is missing from THIS scan — the bundle can be briefly
                // unreadable while Installer swaps it. Decide nothing from a blind
                // pass: carry a restart that was already pending forward so one
                // missed scan can't drop the badge (or let `pruneStagedPackages`
                // reclaim the entry). A genuinely deleted app is reclaimed later by
                // the file-existence backstop in prune.
                if packageRestartPending.contains(id) { pending.insert(id) }
                continue
            }
            let key = app.path.resolvingSymlinksInPath().path
            let state = PackageRestartState.resolve(
                onDiskVersion: app.versionSide,
                stagedVersion: staged.versionSide,
                stagedAt: staged.stagedAt,
                runningLaunchDates: launchDates[key] ?? [],
                buildIsDerived: AppScanner.buildVersionIsOverridden(
                    bundleID: app.bundleID))
            switch state {
            case .pending:
                // Not landed. Normally there's no badge yet; but if one was already
                // lit (landed earlier) and the version momentarily reads old — a
                // partial `package.json` read mid-swap — carry it rather than
                // flickering the badge off and re-notifying on the next good pass.
                if packageRestartPending.contains(id) { pending.insert(id) }
            case .readyToRestart:
                pending.insert(id)
                if notifiedPackageRestart.insert(id).inserted {
                    let version = app.shortVersion
                    // Badge always; banner only if the user keeps update notifications
                    // on — the pkg lands out of a rescan, not a click, so this is an
                    // unsolicited background event like the "new update" nudge.
                    if prefs.notifyOnUpdates {
                        UpdateNotifier.readyToRestart(
                            app: app.name, version: version, appID: app.bundleID)
                    }
                    Log.install.info("package landed, awaiting restart: \(app.name, privacy: .public) \(version ?? "?", privacy: .public)")
                }
            case .settled:
                // Landed with nothing stale running (never open, or already
                // relaunched). The install is fully done — drop the re-open entry.
                settledIDs.append(id)
            }
        }
        packageRestartPending = pending
        for id in settledIDs { stagedPackages[id] = nil }
        // Clear the notify-once guard ONLY when a restart genuinely resolves (settled,
        // or its staged entry is gone) — never merely because the id fell out of
        // `pending` for one pass, which would let the same landing re-notify. (A
        // DuoUpdater relaunch, which doesn't persist this set, can still re-remind
        // once for a restart that was already pending — acceptable, it's real.)
        notifiedPackageRestart.formIntersection(Set(stagedPackages.keys))
        if !settledIDs.isEmpty {
            persistStagedPackages()
        }
    }

    /// The restart happened (or the app was already gone), so a landed pkg has
    /// nothing left to restart: drop its pending state, the one-time-notify guard,
    /// and the now-pointless staged download entry.
    private func settlePackageRestart(_ id: String) {
        packageRestartPending.remove(id)
        notifiedPackageRestart.remove(id)
        if stagedPackages[id] != nil {
            stagedPackages[id] = nil
            persistStagedPackages()
        }
    }

    private func computeRestartInfo() async {
        reconcilePackageRestarts()
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
            // Both sides of the comparison below have to come from the SAME field.
            // `running` is `lsappinfo`, which can only ever report `CFBundleVersion`;
            // for the handful of apps where `AppScanner` stores a DIFFERENT build in
            // `buildVersion` (Xcode's `ProductBuildVersion`, 豆包输入法's
            // `Wave Build Version Number`), the disk side is a foreign namespace and
            // the comparison is meaningless. 豆包输入法 showed exactly that: disk
            // `90602` against a running `CFBundleVersion` of `1` read as newer, so a
            // freshly-launched, perfectly current input method wore a permanent
            // Restart badge and a "0.9.6 (1) → 0.9.6 (90602)" line.
            //
            // Skipping is the honest answer, not a lost feature: an app in this set
            // has a `CFBundleVersion` that `lsappinfo` and the scan would BOTH have to
            // read for the check to mean anything, and where they differ the
            // disk-vs-running signal is blind either way. Landed packages still reach
            // `packageRestartPending` below, which decides on launch TIME instead —
            // the same escape hatch frozen-version apps like WeChat DevTools use.
            if AppScanner.buildVersionIsOverridden(bundleID: result.app.bundleID) { continue }
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
        // Fold in the launch-time signal for landed packages the version pass above
        // can't see (frozen-version apps). `pruneStagedPackages` deliberately skips
        // a row that's in this set, so the entry survives to keep the badge lit.
        needsRestart = ids.union(packageRestartPending)
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
    /// each candidate's staging area off-main — mostly filesystem work (a
    /// plist/json parse per candidate), plus one LaunchServices query for the
    /// parked Sparkle installers, which is why it does not belong on the main
    /// actor.
    private func computeSelfUpdateStaging() async {
        let apps = results.map(\.app).filter(SelfUpdaterStaging.mayHaveStaging)
        let staged = await Task.detached(priority: .utility) {
            // Asked once for the whole sweep rather than per app: the answer is a
            // single global list either way, and `mayHaveStaging` admits every
            // Sparkle app on the machine.
            let parked = SelfUpdaterStaging.liveParkedSparkleInstallers()
            var map: [String: StagedSelfUpdate] = [:]
            for app in apps {
                if let s = SelfUpdaterStaging.staged(
                    for: app, parkedInstallerBundleURLs: parked) { map[app.id] = s }
            }
            return map
        }.value
        pendingSelfUpdate = staged
        // Drop armed staged-swap hand-offs whose staging is gone or now points at a
        // different version: each such marker is bound to the exact build it was
        // armed for, and must not outlive it. (A hand-off already relaying removed
        // its marker synchronously in `settleQuitHandoffs`, so this can't cancel one
        // in flight.) The other landings aren't derived from `pendingSelfUpdate` at
        // all — their build is already on disk, or is App Store's to deliver — so
        // this sweep must not touch them; only the age check retires those.
        // Drop only when the staging is GONE; when it merely MOVED, re-target.
        // Dropping on any difference conflated the two, so a vendor shipping
        // another build inside the marker's ten-minute life destroyed it — and
        // the marker exists precisely to reopen an app that would otherwise stay
        // closed after the swap. See `RelaunchLanding.retargeted(nowStaged:)`.
        quitHandoffs = quitHandoffs.compactMapValues { handoff in
            guard let landing = handoff.landing.retargeted(
                nowStaged: pendingSelfUpdate[handoff.result.id]?.versionSide)
            else { return nil }
            return landing == handoff.landing ? handoff : QuitHandoff(
                result: handoff.result, landing: landing,
                activates: handoff.activates, armedAt: handoff.armedAt)
        }
        // Dismiss delivered "Relaunch to apply it" banners for every row that is not
        // currently offering a Relaunch. The standing question ("who should have a
        // banner right now?"), NOT the transition one ("who left the set since last
        // pass?").
        //
        // The transition form could never fire for the case it was written for. Its
        // "previously" set was re-derived from `results` at the top of this function,
        // and every caller re-reads disk before getting here — `performLocalRescan`
        // rescans wholesale, `refreshRow` rechecks the one row. So by the time it was
        // computed, an applied row's on-disk version had already caught up with the
        // staged build, `actionableStaged` returned nil (it refuses a staged build
        // that isn't newer than what's installed), and the id was missing from BOTH
        // sets — `subtracting` yielded nothing. Relaunching Amp left "Amp downloaded
        // 1.0 (131) on its own. Relaunch to apply it." sitting in Notification Center
        // under the "Now running 1.0." confirmation, because the applied case is
        // exactly the case where the two reads move together. Asking the standing
        // question has no such window, and also covers a build the app applied while
        // we weren't running.
        //
        // The banner goes; the ledger entry stays. The only other thing that can put
        // an id here is the staging read coming back empty, and that read is a live
        // process query (the parked Sparkle updater has to be enumerable) plus an
        // unsynchronised plist read. One blind pass must not be able to forget that
        // this build was already announced: `performLocalRescan` runs this on a
        // 180-second backstop, so forgetting would re-announce the same build faster
        // than the five-minute timer the ledger exists to delete. Withdrawing a banner
        // that was never posted costs nothing; re-posting one the user already
        // dismissed does.
        let nowActionable = Set(results.compactMap { actionableStaged($0) != nil ? $0.id : nil })
        UpdateNotifier.clearSelfDownloaded(
            appIDs: results.map(\.id).filter { !nowActionable.contains($0) })
        if !nowActionable.isEmpty {
            let names = results.filter { nowActionable.contains($0.id) }
                .map { "\($0.app.name)→\(pendingSelfUpdate[$0.id]!.version)" }.joined(separator: ", ")
            Log.app.info("self-update staged (relaunch pending): \(names, privacy: .public)")
        }
        // Move any actionable-staged row into the actionable tier (rank 0).
        results = sorted(results)
        // Announce whatever is newly staged. Nothing here re-announces a build the
        // user has already been told about, so running this every pass is quiet.
        notifyStagedRelaunches()
        // Same bookkeeping pass, same preconditions (`results` is current): drop any
        // downloaded installer package that no longer matches what's on offer.
        pruneStagedPackages()
    }

    // MARK: - Staged installer packages

    /// An installer package already downloaded for this row and handed to macOS's
    /// installer. `version` is its display label; `versionSide` identifies the build
    /// it installs, so a newer release invalidates it rather than silently re-opening
    /// a stale installer.
    struct StagedPackage: Sendable, Equatable {
        let version: String
        /// The comparable pair. Everything asking "is this the version on offer"
        /// or "has it landed" uses this. It is copied from the source rather than
        /// rebuilt from `version`, because `version` is marketing-first DISPLAY:
        /// for a `versionIsBuild` source it contains a build string, and putting
        /// that into `marketing` would compare two different namespaces.
        let versionSide: VersionSide
        let url: URL
        /// When the package was handed to macOS's installer. Used to tell a copy
        /// running the OLD code (launched before this) from one the vendor's own
        /// installer relaunched afterwards — see `PackageRestartState`.
        let stagedAt: Date
    }

    /// Restore the persisted staged packages, dropping anything whose file is gone
    /// (`PackageInstaller` sweeps its work directories after a day). Called once at
    /// launch; the per-version check happens later, in `stagedPackage(for:)`, since
    /// it needs the current check results.
    private func loadStagedPackages() {
        var restored: [String: StagedPackage] = [:]
        for (id, fields) in prefs.stagedPackages {
            guard
                let version = fields[Preferences.stagedPackageVersionField],
                let path = fields[Preferences.stagedPackagePathField],
                FileManager.default.fileExists(atPath: path)
            else { continue }
            // Missing on entries staged before the field existed → distant past, so
            // no already-running copy is ever judged "older than the hand-off".
            let stagedAt = fields[Preferences.stagedPackageStagedAtField]
                .flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
                ?? .distantPast
            // New entries persist the source's marketing half explicitly, using
            // an empty string for "the source reported none". A missing field is a
            // pre-migration entry whose `version` historically served as marketing;
            // preserve that comparison rather than invalidating an in-flight pkg.
            let marketing: String?
            if let stored = fields[Preferences.stagedPackageMarketingField] {
                marketing = stored.isEmpty ? nil : stored
            } else {
                marketing = version
            }
            restored[id] = StagedPackage(
                version: version,
                versionSide: VersionSide(
                    marketing: marketing,
                    build: fields[Preferences.stagedPackageBuildField]),
                url: URL(fileURLWithPath: path), stagedAt: stagedAt)
        }
        stagedPackages = restored
        persistStagedPackages()
    }

    private func recordStagedPackage(_ result: UpdateResult, packageURL: URL) {
        guard let remote = result.remote, let version = remote.displayVersion else { return }
        stagedPackages[result.id] = StagedPackage(
            version: version, versionSide: remote.versionSide,
            url: packageURL, stagedAt: Date())
        persistStagedPackages()
        Log.install.info("package staged: \(result.app.name, privacy: .public) \(version, privacy: .public) → \(packageURL.lastPathComponent, privacy: .public)")
    }

    /// The package staged for this row is about to be superseded: a newer one has
    /// been downloaded, has passed the gate, and is one statement away from being
    /// opened. Close the old Installer window so the two don't pile up (a pkg update
    /// waits on the user, so an ignored one stays on screen indefinitely), and only
    /// then delete its download — while the window is open, Installer is still
    /// reading the file.
    ///
    /// Runs *before* the new package is opened, not after: an AX press that lands
    /// while Installer is opening a document reads blank `AXDocument`s at best, and
    /// at worst joins the race a macOS 26.6 Installer died in (`_volumeAppeared:`
    /// messaging a dead object a second after we opened a third package into it).
    ///
    /// Everything here is best-effort. Without Accessibility trust, or when the
    /// window is busy installing, we leave both the window and the file alone and
    /// the 24-hour sweep reclaims the disk.
    private func retireStagedPackage(for id: String) async {
        guard let superseded = stagedPackages[id] else { return }
        guard await InstallerWindowCloser.closeWindow(showing: superseded.url) else { return }
        guard PackageInstaller.discardWorkDirectory(containing: superseded.url) else { return }
        // The download is gone, so nothing may offer to re-open it; the caller
        // records the replacement the moment its open returns.
        if stagedPackages[id]?.url == superseded.url {
            stagedPackages[id] = nil
            persistStagedPackages()
        }
    }

    /// Throw away the package downloaded for this row, at the user's request: the
    /// row goes back to **Update**, and the next install starts from scratch.
    ///
    /// The counterpart to `retireStagedPackage`, and deliberately not the same
    /// function. That one runs on OUR schedule, one statement before a newer
    /// package is opened, so it bails when it can't close the Installer window
    /// first — pulling the file out from under a window Installer is reading
    /// would be worse than leaving both alone. This one runs because someone
    /// asked, and must not leave the row still offering an Install they've said
    /// they don't want: closing the window and reclaiming the disk are both
    /// best-effort (no Accessibility trust, or a window mid-install, and the
    /// 24-hour sweep gets the file instead), but forgetting the entry is not
    /// conditional on either.
    ///
    /// Not offered while `packageRestartPending` holds the entry: there the
    /// package has already LANDED and the entry is what keeps the Restart badge
    /// lit, so discarding it would drop a prompt the user still needs. The
    /// caller gates on `canDiscardStagedPackage`.
    func discardStagedPackage(_ result: UpdateResult) async {
        guard let staged = stagedPackages[result.id] else { return }
        // Reclaiming the disk is conditional on the window actually closing, and
        // that is not belt-and-braces: `discardWorkDirectory` is a recursive
        // delete whose own contract says the caller MUST have confirmed the
        // Installer window is closed, because pulling the file out from under an
        // open window breaks the install in progress. `closeWindow` returns false
        // without Accessibility trust — which is optional in this app, so for a
        // user who never granted it that was the DEFAULT path, not a race — and
        // also when the window is mid-install or a SecurityAgent prompt is up.
        // The row's menu item stays live throughout an install (`packageRestartPending`
        // only fills once the new version has landed), so "mid-install" is
        // reachable by an ordinary click.
        //
        // Leaving the file is the safe half of the trade and costs nothing: the
        // 24-hour sweep reclaims it. Forgetting the entry below stays
        // unconditional — the user asked, and the row must not go on offering an
        // Install they have said they don't want. The error goes with it for the
        // same reason: the user is abandoning the update this row was attempting,
        // and a lingering red error for an attempt they just called off is not
        // informative, it's noise. Nothing else would ever clear it either — the
        // row is `.updateAvailable` by construction here (`stagedPackage(for:)`
        // requires a remote version on offer), and `pruneSettledInstallErrors`
        // only settles `.upToDate` rows — so without this it would survive every
        // rescan until the user starts another install on this row.
        if await InstallerWindowCloser.closeWindow(showing: staged.url) {
            _ = PackageInstaller.discardWorkDirectory(containing: staged.url)
        }
        // Re-check before forgetting anything: closing the window is a detached
        // AX conversation that can take seconds, and this model is @MainActor, so
        // an install already in flight for this row can reach
        // `recordStagedPackage` while we are suspended. Clearing unconditionally
        // would throw away the entry for a package that was just downloaded —
        // the row would fall back to "Update" and pull the same hundreds of
        // megabytes again, which is the exact waste staging exists to prevent —
        // and would wipe that install's progress note on the way past. Same
        // re-check, for the same reason, as `retireStagedPackage` above.
        guard stagedPackages[result.id]?.url == staged.url else {
            // Said out loud rather than returning in silence: from the user's
            // side their Discard did nothing and the row still offers Install,
            // and without this line there is no way to tell that from a bug.
            Log.install.info("package discard superseded mid-close: \(result.app.name, privacy: .public) — a newer package was staged while the Installer window was closing, and it is kept")
            return
        }
        stagedPackages[result.id] = nil
        persistStagedPackages()
        installNotes[result.id] = nil
        inFlightNotes[result.id] = nil
        installErrors[result.id] = nil
        Log.install.info("package discarded by user: \(result.app.name, privacy: .public) \(staged.version, privacy: .public)")
    }

    /// Whether the row should offer to discard its downloaded package: there is
    /// one, it is still the version on offer, and it isn't the entry holding a
    /// pending Restart open (see `discardStagedPackage`).
    func canDiscardStagedPackage(_ result: UpdateResult) -> Bool {
        stagedPackage(for: result) != nil && !packageRestartPending.contains(result.id)
    }

    /// One line for the row saying what the prominent **Install** button will
    /// actually do — which until now was stated only in a `.help()` tooltip.
    ///
    /// The button reads like the start of the operation; the operation has in
    /// fact half happened, and two people in a row read the row as stuck and
    /// closed the installer expecting the update to restart. Nothing was broken
    /// either time. Saying it on the row is the fix.
    func stagedPackageNote(for result: UpdateResult) -> String? {
        guard let staged = stagedPackage(for: result) else { return nil }
        return String(localized: "\(staged.version) is downloaded — Install re-opens it in macOS’s installer, nothing is downloaded again.")
    }

    private func persistStagedPackages() {
        prefs.setStagedPackages(stagedPackages.mapValues {
            [
                Preferences.stagedPackageVersionField: $0.version,
                Preferences.stagedPackagePathField: $0.url.path,
                Preferences.stagedPackageStagedAtField:
                    String($0.stagedAt.timeIntervalSince1970),
                // Presence distinguishes a new entry whose source has no
                // marketing version (empty) from a legacy entry (missing).
                Preferences.stagedPackageMarketingField:
                    $0.versionSide.marketing ?? "",
            ].merging($0.versionSide.build.map {
                [Preferences.stagedPackageBuildField: $0]
            } ?? [:], uniquingKeysWith: { a, _ in a })
        })
    }

    /// The downloaded package for this row, if it's still usable: the file is on disk
    /// AND it installs exactly the version currently on offer. A newer release makes
    /// the old package wrong, not merely stale, so the row falls back to "Update".
    func stagedPackage(for result: UpdateResult) -> StagedPackage? {
        guard
            let staged = stagedPackages[result.id],
            // Pairs, not marketing strings: a stale package from an earlier build
            // of a frozen-marketing app compared equal to the current offer and was
            // re-opened as if it installed it.
            let offered = result.remote?.versionSide,
            VersionComparator.isSame(staged.versionSide, as: offered),
            FileManager.default.fileExists(atPath: staged.url.path)
        else { return nil }
        return staged
    }

    /// Drop staged packages that are no longer usable — the file was swept, or the
    /// row moved on (installed, or a newer version now on offer). Runs with the
    /// other post-rescan bookkeeping so a swept package doesn't leave an "Install"
    /// button that can't do anything.
    private func pruneStagedPackages() {
        guard !stagedPackages.isEmpty else { return }
        let onDisk = Dictionary(results.map { ($0.id, $0.app) }, uniquingKeysWith: { a, _ in a })
        let offered = Dictionary(
            results.compactMap { r -> (String, VersionSide)? in
                guard let side = r.remote?.versionSide, !side.isEmpty else { return nil }
                return (r.id, side)
            },
            uniquingKeysWith: { a, _ in a })
        let kept = stagedPackages.filter { id, staged in
            // A landed package that left a stale copy running is no longer "on offer"
            // (the app is now current) and its download may have been swept, yet its
            // entry must survive to keep the Restart badge lit until the app is
            // relaunched. `reconcilePackageRestarts` retires it once it settles.
            if packageRestartPending.contains(id) { return true }
            let fileThere = FileManager.default.fileExists(atPath: staged.url.path)
            guard let app = onDisk[id] else {
                // Row missing from THIS scan (bundle mid-swap): don't reclaim on a
                // blind pass — a genuinely deleted app is still bounded by the file
                // backstop once its download is swept.
                return fileThere
            }
            // Landed (the app now IS the staged version): keep so restart tracking
            // survives a one-scan flicker of the launch-time signal, even if the
            // download was swept. Reconcile settles it once the copy is fresh/gone.
            // `buildIsDerived` matches the guard `reconcilePackageRestarts` passes
            // to `PackageRestartState.resolve` — same two inputs, same namespace
            // problem for `AppScanner.buildVersionIsOverridden` apps (#285).
            if VersionComparator.isSame(app.versionSide, as: staged.versionSide,
                buildIsDerived: AppScanner.buildVersionIsOverridden(bundleID: app.bundleID)
            ) { return true }
            // Otherwise it's only usable while still on offer and re-openable.
            return offered[id].map {
                VersionComparator.isSame($0, as: staged.versionSide)
            } == true && fileThere
        }
        guard kept.count != stagedPackages.count else { return }
        stagedPackages = kept
        persistStagedPackages()
    }

    /// Re-open the package we already downloaded for this row. No network: the file
    /// is on disk, re-verified, and handed back to macOS's installer, which brings
    /// its existing window forward if it's still open.
    func openStagedPackage(_ result: UpdateResult) async {
        guard let staged = stagedPackage(for: result) else { return }
        installErrors[result.id] = nil
        do {
            try await packageInstaller.reopen(
                package: staged.url, installedApp: result.app.path)
            let note = String(localized: "Opened the installer for \(result.app.name) \(staged.version) — finish it there.")
            installNotes[result.id] = note
            inFlightNotes[result.id] = note
            Log.install.info("package re-opened: \(result.app.name, privacy: .public) \(staged.version, privacy: .public)")
        } catch {
            // The local copy is unusable (swept, truncated, or it no longer passes the
            // signature gate). Forget it so the row goes back to a clean "Update".
            stagedPackages[result.id] = nil
            persistStagedPackages()
            installErrors[result.id] = error.localizedDescription
            Log.install.error("package re-open failed: \(result.app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A staged self-update worth announcing: the staged build is the latest *and*
    /// the user hasn't hidden the app or that version. `actionableStaged` answers
    /// only the first half — see `nudgeableStaged` for why the second half has to
    /// be applied here.
    private func nudgeableStaged(_ result: UpdateResult) -> StagedSelfUpdate? {
        UpdatePolicy.nudgeableStaged(
            result,
            staged: pendingSelfUpdate[result.id],
            isIgnored: prefs.isIgnored(result.app),
            isVersionSkipped: { prefs.isVersionSkipped(result.app, version: $0) })
    }

    /// Announce staged relaunches — once per (app, staged build), not once per
    /// staging pass.
    ///
    /// This used to be a timer that re-posted a banner for every staged build every
    /// five minutes, for as long as it stayed staged. The stable notification
    /// identifier kept Notification Center to one entry per app, but each repost
    /// still alerted, so an app the user wasn't ready to relaunch nagged twelve
    /// times an hour and never stopped. The ledger replaces the repetition with a
    /// persisted (app → announced version) pair, so the reminder resurfaces exactly
    /// when there is something new to say: a *different* build gets staged. See
    /// `StagedNudgeLedger` for why the key is the version rather than the app.
    ///
    /// Runs from `computeSelfUpdateStaging`, which is the only place
    /// `pendingSelfUpdate` changes, so every path that can newly stage something
    /// (scheduled check, manual refresh, post-install rescan) announces it.
    private func notifyStagedRelaunches() {
        guard prefs.notifyOnUpdates else { return }
        var ledger = StagedNudgeLedger(prefs.notifiedStagedVersions)
        // Guard against an empty/partial pass wiping the ledger before a real scan
        // has populated `results` — that would re-announce everything already staged.
        if !results.isEmpty {
            ledger.prune(liveKeys: Set(results.map { prefs.key(for: $0.app) }))
        }
        for result in results {
            // Only nudge "relaunch to apply X" when X is actually the latest — a
            // staged build that trails a newer release goes through the normal
            // updates-available path instead — and only when the user hasn't
            // ignored the app or skipped that version.
            guard let staged = nudgeableStaged(result) else { continue }
            let key = prefs.key(for: result.app)
            // `buildIdentity`, NOT `staged.version`: the latter is a marketing
            // string an app may leave unchanged across many builds, and keying the
            // ledger on it announces the first of them and silently swallows every
            // one after — Amp shipped ten builds as "1.0" in a day. See
            // `StagedSelfUpdate.buildIdentity`. Entries persisted by an older build
            // hold a marketing version, so the first pass after this ships may
            // re-announce one staged build per app; it self-heals on that write.
            guard ledger.isNew(key: key, version: staged.buildIdentity) else { continue }
            ledger.record(key: key, version: staged.buildIdentity)
            Log.app.info("notify: \(result.app.name, privacy: .public) staged \(staged.version, privacy: .public) — relaunch nudge")
            UpdateNotifier.selfDownloaded(
                app: result.app.name, version: result.stagedRelaunchLine(staged).to, appID: result.id)
        }
        // Only on a real change: this runs on every local rescan (the directory
        // watcher and its 180s backstop), and the neighbouring bookkeeping passes
        // guard their writes the same way.
        if ledger.entries != prefs.notifiedStagedVersions {
            prefs.setNotifiedStagedVersions(ledger.entries)
        }
    }

    /// Withdraw a "relaunch to apply it" nudge: the delivered banner AND the ledger
    /// entry that suppresses a repeat, together — so un-hiding the app can announce
    /// the staged build again instead of being silenced by the record of a banner
    /// that no longer exists.
    ///
    /// Exactly one caller, deliberately: ignoring an app. That is the one place where
    /// the row stops being announceable because the *user* said so, where the hiding
    /// is keyed on the app rather than on a version string, and where the undo
    /// (`toggleIgnore`'s other branch) re-announces synchronously.
    ///
    /// The other places that clear this banner keep their entry, each for its own
    /// reason: the staging sweep in `computeSelfUpdateStaging` (a blind staging read
    /// must not be able to re-announce) and `skipThisVersion` (the skip gate matches
    /// version strings exactly, so the entry covers a mismatch). Hiding an app from
    /// the CLI — `duo ignore` / `duo skip`, which arrive through `Preferences`'s KVO
    /// reload — keeps its entry too: un-hiding then brings back the row and the
    /// badge without a banner, which is the quiet direction to be wrong in.
    private func withdrawStagedNudge(_ result: UpdateResult) {
        UpdateNotifier.clearSelfDownloaded(appID: result.id)
        var ledger = StagedNudgeLedger(prefs.notifiedStagedVersions)
        ledger.forget(key: prefs.key(for: result.app))
        if ledger.entries != prefs.notifiedStagedVersions {
            prefs.setNotifiedStagedVersions(ledger.entries)
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
                    current = UpdatePolicy.runtimeBundlePath(URL(fileURLWithPath: path))
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

    /// Take down a note one of the restart paths wrote — and only if it is still
    /// the text on screen. Shared by the two stores that follow the discipline
    /// `restartHoldBackNotes` documents: if someone replaced the note in between
    /// (`backupCurrent`'s "applied without a rollback point", say), theirs stands.
    private func retractRestartNote(_ id: String, from store: inout [String: String]) {
        guard let mine = store.removeValue(forKey: id), installNotes[id] == mine else { return }
        installNotes[id] = nil
    }

    /// Quit the stale running instance and relaunch it so the new version takes
    /// effect. Graceful only — if it won't quit (unsaved work), we leave it and
    /// keep the Restart prompt for the user to retry. An app that isn't running
    /// at all never reaches here — it has no `needsRestart` entry (the swap is
    /// already fully in effect on disk), so updating it never starts it up.
    ///
    /// The quit/wait/relaunch mechanism itself lives in `AppRestarter` (shared
    /// with `duo restart`); this keeps only the UI-facing state around it — the
    /// in-flight spinner and the badge that clears once it's done.
    func restart(_ result: UpdateResult) async {
        guard let bundleID = result.app.bundleID else { return }
        // Block re-entry and show the in-flight spinner (the `relaunching`
        // indicator replaces the button): the quit→wait→reopen takes a beat, and
        // without feedback the click reads as "nothing happened" even though it
        // worked. A second click would otherwise fire a second quit.
        guard !relaunching.contains(result.id) else { return }
        relaunching.insert(result.id)
        pinRowOrder()
        defer { relaunching.remove(result.id); releaseRowOrder() }
        Log.app.info("restart: \(result.app.name, privacy: .public) [\(bundleID, privacy: .public)]")
        // Sampled before the quit — once the instances are gone, so is the answer —
        // so a hand-off armed below can put the app back where it was. `AppRestarter`
        // samples this itself for the quit it completes; this copy is only for the
        // quit it gives up on.
        let wasFrontmost = AppRestarter.isFrontmost(AppRestarter.runningInstances(of: result.app))
        // A fresh attempt supersedes whatever a previous bail left armed. This has
        // to happen BEFORE the standoff below can return: a stale marker left by
        // an earlier bail fires on the very quit the hold-back note asks the user
        // to perform, relaunching the app straight into the installer we were
        // trying not to disturb.
        quitHandoffs[result.id] = nil
        // …and supersedes what that bail put on screen. The note names a quit the
        // user was asked to unblock; this click IS them coming back to it, so it
        // must not still be sitting there while the retry runs.
        retractRestartNote(result.id, from: &restartWontQuitNotes)
        // Is anyone else waiting for this app to quit? Sparkle parks an installer
        // on exactly that signal, so a restart meant to put OUR build into effect
        // can instead apply THEIRS — see `RestartStandoff` for the timeline. Only
        // a staged build that differs from what is on disk is a problem; matching
        // builds make whoever writes second harmless. The `hasSparkleUpdater`
        // guard keeps every other app off the filesystem work entirely.
        let staged = result.app.hasSparkleUpdater
            ? SelfUpdaterStaging.sparkleStagedBundle(for: result.app) : nil
        // Both fields off the same read of the bundle as it stands NOW. The batch
        // path calls this with a `result` snapshotted before any install ran, so
        // anything taken from `result.app` here is a version or two behind.
        let onDisk = Self.readBundleVersions(result.app.path)
        if case .holdBack(let stagedVersion) = RestartStandoff.decide(
            staged: staged,
            onDiskShortVersion: onDisk.short,
            onDiskBuildVersion: onDisk.build) {
            Log.app.notice(
                "restart held back: \(result.app.name, privacy: .public) — its own updater has \(stagedVersion, privacy: .public) staged and is waiting for the quit")
            // Deliberately says "the version on disk" rather than "the version
            // just installed": this is also reached from the Restart button on a
            // row that updated itself, where we installed nothing.
            let note = String(localized: "\(result.app.name) has its own update (\(stagedVersion)) downloaded and waiting for the app to quit. Relaunching from here would install that one over the version now on disk, so it wasn't relaunched — quit \(result.app.name) yourself when you're ready to take theirs.")
            installNotes[result.id] = note
            restartHoldBackNotes[result.id] = note
            // Deliberately NOT registered in `inFlightNotes`. A row offering a
            // restart has the new build on disk already, so its verdict is
            // normally `.upToDate` the whole time this note is up — the settle
            // rule would take the explanation down on the next rescan while the
            // standoff it describes had not changed at all. The condition that
            // actually ends this one is the staged build going away, and the only
            // reading of that we trust is the one three lines above, taken fresh
            // off the bundle. So this note keeps its own retraction and nothing
            // guesses on its behalf.
            return
        }
        // The standoff is over (or never existed): retract our own explanation if
        // it is still the one showing, and nothing else. If someone replaced the
        // note in between — `backupCurrent`'s "no rollback point", say — theirs
        // stands.
        retractRestartNote(result.id, from: &restartHoldBackNotes)
        switch await AppRestarter.restart(result.app) {
        case .noBundleID, .notRunning:
            needsRestart.remove(result.id)
            pendingBatchRestart[result.id] = nil
            settlePackageRestart(result.id)
        case .stillRunning:
            // Still up (likely a save prompt) — leave the badge, and hand the quit
            // off to the terminate observer. The new build is already on disk (the
            // install finished long before this), so the only thing left is the
            // quit: if the user answers that prompt in the next few minutes we
            // relaunch then, instead of leaving them with an app that quietly
            // stayed closed and a badge that cleared itself on the way out.
            quitHandoffs[result.id] = QuitHandoff(
                result: result, landing: .applied,
                // Re-sample, the way the staged path does: `wasFrontmost` was taken
                // with our own popover in front (the user had just clicked Restart in
                // it), so on its own it says "background" for every menu-initiated
                // restart. By now the app is holding its quit dialog up, which usually
                // means it holds the front spot — and that is where it should return.
                activates: wasFrontmost
                    || AppRestarter.isFrontmost(AppRestarter.runningInstances(of: result.app)),
                armedAt: Date())
            Log.app.info("relaunch-handoff: armed for \(result.app.name, privacy: .public) (won't quit — relaunch if it does)")
            // Say so. Without this the row is indistinguishable from a click that
            // did nothing: 30 seconds of spinner, then the same button back. The
            // sentence has to send the user to the app rather than back to this
            // button, because nothing here can clear the thing that is blocking
            // the quit — AppKit refuses to honour it while a modal window or sheet
            // is up, and that window is the app's, not ours. "A window waiting for
            // you" rather than "unsaved work": the case in hand was Eudic's login
            // sheet, which has nothing to save.
            let note = String(localized: "\(result.app.name) didn’t quit — it has a window waiting for you (a save prompt, a sign-in sheet, a dialog). Switch to it, deal with that window, then quit it or click Relaunch again. Nothing was changed and the new version is already installed.")
            installNotes[result.id] = note
            restartWontQuitNotes[result.id] = note
        case .relaunched(let relaunched):
            needsRestart.remove(result.id)
            pendingBatchRestart[result.id] = nil
            runningVersionByID[result.id] = nil
            settlePackageRestart(result.id)
            Log.app.info("restart: \(result.app.name, privacy: .public) relaunched=\(relaunched, privacy: .public)")
            if relaunched {
                // `onDisk.short`, not `result.app.shortVersion`: the batch path
                // hands this function a row snapshotted before any install ran,
                // so the snapshot names the version we just replaced.
                UpdateNotifier.restarted(
                    app: result.app.name, version: onDisk.short ?? result.app.shortVersion,
                    appID: result.app.bundleID)
            }
        case .nestedOnly(let relaunched):
            // The app itself was never running — only a stranded nested app (e.g.
            // Surge's Dashboard) needed clearing — so the update still applies the
            // moment the app is next opened by hand. Clear the same state
            // `.relaunched` does, but never post `.restarted`: the app is not
            // running, so "Now running X" would be a false notification.
            needsRestart.remove(result.id)
            pendingBatchRestart[result.id] = nil
            runningVersionByID[result.id] = nil
            settlePackageRestart(result.id)
            Log.app.info("restart: \(result.app.name, privacy: .public) was not running itself — nested app(s) cleared, relaunched=\(relaunched, privacy: .public)")
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
        pinRowOrder()
        defer { relaunching.remove(result.id); releaseRowOrder() }
        // A fresh attempt supersedes whatever a previous bail left armed — and the
        // note that bail wrote, which has to go with the marker rather than after
        // it. `settleQuitHandoffs` is the only thing that retracts that note and it
        // iterates `quitHandoffs`, so dropping the marker alone strands the
        // sentence: the row would still say "it didn't quit — deal with that
        // window" after this relaunch had quit it and ShipIt had swapped. Reachable
        // because the two buttons live on one row: a `.stillRunning` bail here
        // leaves the note up, and the moment the app's own updater stages a build
        // (`actionableStaged`) the row switches from Relaunch-to-restart to
        // Relaunch-to-apply, which is this function.
        quitHandoffs[result.id] = nil
        retractRestartNote(result.id, from: &restartWontQuitNotes)
        let running = AppRestarter.runningInstances(of: result.app)
        guard !running.isEmpty else {
            // Not running: the staged swap applies on the app's own next quit, not
            // on demand from us. Leave the badge; a later check clears it once the
            // app itself applies the update.
            Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) not running — ShipIt applies on its own next quit")
            return
        }
        let wasFrontmost = AppRestarter.isFrontmost(running)
        // The PAIR, not `shortVersion ?? buildVersion`. That chain answers "1.0"
        // for an app that ships every build under one marketing version, and the
        // landing test below then compares "1.0" against "1.0" forever — measured
        // on Amp 2026-08-28, where this spun its full 900 ticks (189 s) and
        // reported `applied=false` for a swap that had already succeeded.
        let old = result.app.versionSide
        Log.app.info("relaunch-staged: quitting \(result.app.name, privacy: .public) (\(old.text(withBuild: true), privacy: .public)) — letting its own updater swap & relaunch (no reopen)")
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
            if RelaunchProgress.hasLanded(
                old: old, disk: await Self.readVersionSideOffMain(result.app.path),
                buildIsDerived: AppScanner.buildVersionIsOverridden(
                    bundleID: result.app.bundleID)) {
                applied = true
                break
            }
            if AppRestarter.runningInstances(of: result.app).isEmpty {
                everQuit = true  // quit succeeded — now we're waiting on the swap
            } else if !everQuit && tick >= quitGraceTicks {
                // Never quit → a save prompt (or similar) is keeping it up; the swap
                // can't start, so don't block the long window on it. But giving up
                // on *waiting* must not give up on the *hand-off*: if the user
                // answers that prompt a minute from now, the quit completes, ShipIt
                // swaps — and an app staged with launchAfterInstallation=false
                // stays closed with nobody to relaunch it. Arm the terminate
                // observer to finish the job (`settleQuitHandoffs`).
                Log.app.info("relaunch-staged: \(result.app.name, privacy: .public) won't quit (likely a save prompt) — leaving it staged")
                if let staged = pendingSelfUpdate[result.id] {
                    quitHandoffs[result.id] = QuitHandoff(
                        result: result,
                        landing: .stagedSwap(to: staged.versionSide),
                        // Its quit dialog is up right now, which usually means it
                        // holds the front spot even if it didn't when we started.
                        activates: wasFrontmost
                            || AppRestarter.isFrontmost(AppRestarter.runningInstances(of: result.app)),
                        armedAt: Date())
                    Log.app.info("relaunch-handoff: armed for \(result.app.name, privacy: .public) → \(staged.version, privacy: .public) (relaunch if it quits and the swap lands)")
                }
                break
            }
        }
        // Fallback: if ShipIt swapped but didn't relaunch (or never ran), bring the
        // app back so the user isn't left without it — in the background unless it
        // was the app in front when we quit it. Retried, because this is precisely
        // where a launch fails: we may be racing a swap that's still rewriting the
        // bundle, and LaunchServices can't open one mid-write. A single dropped
        // `false` here left the app closed with nothing else watching.
        if AppRestarter.runningInstances(of: result.app).isEmpty {
            await relaunchAfterSwap(result.app, activates: wasFrontmost)
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

    /// Bring an app back up after its own updater (or App Store) swapped the
    /// bundle, retrying while the bundle may still be being rewritten.
    ///
    /// `launchApp` returns false when LaunchServices can't open the bundle — and a
    /// bundle mid-swap is exactly that. Every caller here runs at the one moment
    /// nobody else is watching: the app is quit, the row's spinner is about to
    /// drop, and a failed launch means the user's app is simply gone. Re-checks
    /// `runningInstances` before each retry so an updater that *does* relaunch (or
    /// a user reopening the app) never gets a second copy.
    @discardableResult
    private func relaunchAfterSwap(_ app: InstalledApp, activates: Bool) async -> Bool {
        for attempt in 1...5 {
            if attempt > 1 {
                try? await Task.sleep(for: .seconds(2))
                guard AppRestarter.runningInstances(of: app).isEmpty else { return true }
            }
            if await AppRestarter.launchApp(app.path, activates: activates) { return true }
            Log.app.error("relaunch: \(app.name, privacy: .public) launch failed (attempt \(attempt, privacy: .public)/5) — bundle may still be mid-swap")
        }
        return false
    }

    /// Pick up any armed quit hand-off whose app has now actually terminated —
    /// the user answered the quit dialog after we gave up waiting on it. Runs on
    /// every NSWorkspace launch/terminate event; a no-op unless a hand-off is
    /// armed, which is rare and short-lived.
    ///
    /// The marker is taken out of the map *synchronously, before any await*: it
    /// must fire at most once, and `computeSelfUpdateStaging`'s sweep (which
    /// drops markers once the staging disappears) must not be able to cancel a
    /// relay that is already under way.
    private func settleQuitHandoffs() {
        guard !quitHandoffs.isEmpty else { return }
        for (id, handoff) in quitHandoffs {
            guard !relaunching.contains(id),
                  AppRestarter.runningInstances(of: handoff.result.app).isEmpty
            else { continue }
            quitHandoffs[id] = nil
            // The app is gone, so the note asking the user to unblock its quit has
            // nothing left to describe. Before the expiry check, not after: an
            // expired marker means we won't relaunch it, not that the sentence
            // about a window blocking the quit is still true.
            retractRestartNote(id, from: &restartWontQuitNotes)
            guard Date().timeIntervalSince(handoff.armedAt) < Self.quitHandoffMaxAge else {
                // Too long since the bail: this quit is the user closing the app,
                // not a late answer to that dialog. ShipIt still swaps — we just
                // don't bring the app back unasked.
                Log.app.info("relaunch-handoff: \(handoff.result.app.name, privacy: .public) marker expired — not relaunching")
                continue
            }
            Task { @MainActor [weak self] in await self?.relayQuitHandoff(handoff) }
        }
    }

    /// Finish a quit we asked for and stopped waiting on: the app has now
    /// terminated, so whatever was going to swap the bundle is (or shortly will
    /// be) doing it. Wait for that landing, then launch the app — the step nobody
    /// else takes here, whether it's a ShipIt staged with
    /// `launchAfterInstallation=false` or an App Store update whose "Continue"
    /// closes the app without reopening it.
    ///
    /// The cardinal rule from `relaunchStagedUpdate` holds for every landing that
    /// waits: never open the app before the swap has landed, or the updater aborts
    /// with "App Still Running" (App Store parks its sheet the same way).
    private func relayQuitHandoff(_ handoff: QuitHandoff) async {
        let app = handoff.result.app
        // Reuse the row spinner + re-entry block for the duration of the relay.
        guard !relaunching.contains(handoff.result.id) else { return }
        relaunching.insert(handoff.result.id)
        pinRowOrder()
        defer { relaunching.remove(handoff.result.id); releaseRowOrder() }
        var landed = !handoff.landing.waitsForDisk  // `.applied` has nothing to wait for
        if handoff.landing.waitsForDisk {
            Log.app.info("relaunch-handoff: \(app.name, privacy: .public) quit after the prompt — waiting for the swap to land")
            for _ in 0..<900 {  // same patience as `relaunchStagedUpdate`'s swap wait (~180s)
                try? await Task.sleep(for: .milliseconds(200))
                guard AppRestarter.runningInstances(of: app).isEmpty else {
                    // Back up without us — the updater relaunched it itself, or the
                    // user reopened it. Either way our job is done; re-read the row.
                    Log.app.info("relaunch-handoff: \(app.name, privacy: .public) reappeared on its own — standing down")
                    await refreshRow(handoff.result)
                    return
                }
                if handoff.landing.isSatisfied(byDisk: await Self.readVersionSideOffMain(app.path)) {
                    landed = true
                    break
                }
            }
        }
        guard landed || handoff.landing.launchesWithoutLanding else {
            // The swap never landed (or disk never reached the version this marker
            // was armed for). Launching now could race a still-working updater, and
            // the marker's promise was specifically "that staged build" — so leave
            // the app quit, exactly as if the user had closed it. (An App Store
            // hand-off doesn't come here: we closed that app ourselves, so it gets
            // reopened regardless — see `Landing.launchesWithoutLanding`.)
            Log.app.info("relaunch-handoff: \(app.name, privacy: .public) swap never landed — leaving it quit")
            await refreshRow(handoff.result)
            return
        }
        // One beat of grace: if this vendor's updater *does* relaunch after
        // installing, its open lands right after the swap — don't double-launch.
        try? await Task.sleep(for: .milliseconds(500))
        guard AppRestarter.runningInstances(of: app).isEmpty else {
            await refreshRow(handoff.result)
            return
        }
        Log.app.info("relaunch-handoff: \(app.name, privacy: .public) relaunching (landed=\(landed, privacy: .public))")
        let relaunched = await relaunchAfterSwap(app, activates: handoff.activates)
        if landed {
            // The update this hand-off was armed for is on disk after all, so a red
            // "timed out" note left by the attempt that gave up is no longer true.
            installErrors[handoff.result.id] = nil
        }
        await refreshRow(handoff.result)
        if landed && relaunched {
            let version = await Self.readShortVersionOffMain(app.path)
            UpdateNotifier.restarted(app: app.name, version: version, appID: app.bundleID)
        }
    }

    /// `readShortVersion` off the main actor. The staged-relaunch poll calls it
    /// five times a second against a bundle the vendor's updater is actively
    /// replacing — a synchronous read of a file mid-swap on a busy disk is
    /// exactly the kind of small stall that adds up to a visible hitch.
    nonisolated private static func readShortVersionOffMain(_ bundle: URL) async -> String? {
        await Task.detached(priority: .utility) { readShortVersion(bundle) }.value
    }

    /// The comparable pair, read off the main thread. Change-detectors use this.
    nonisolated private static func readVersionSideOffMain(_ bundle: URL) async -> VersionSide {
        await Task.detached(priority: .utility) { readVersionSide(bundle) }.value
    }

    /// Read a bundle's `CFBundleShortVersionString` straight off disk.
    ///
    /// **Display only.** Every change-DETECTOR reads `readVersionSide` instead:
    /// discarding the build half is what made four separate landing checks answer
    /// "nothing changed" for an app that ships many builds under one marketing
    /// version. `readBundleVersions` below already returns both from one read, so
    /// dropping one was never a saving.
    nonisolated private static func readShortVersion(_ bundle: URL) -> String? {
        readBundleVersions(bundle).short
    }

    /// Both version fields as a comparable pair — what anything asking "has this
    /// changed / has the swap landed" must use.
    nonisolated private static func readVersionSide(_ bundle: URL) -> VersionSide {
        let both = readBundleVersions(bundle)
        return VersionSide(marketing: both.short, build: both.build)
    }

    /// Both version fields, from **one** read of the bundle.
    ///
    /// Kept together on purpose. `RestartStandoff` compares each field it can
    /// against what the app's own updater has staged, so the two must describe
    /// the same moment: pairing a freshly-read short version with a
    /// `buildVersion` carried over from the pre-install scan made "Update All"
    /// hold back on apps with nothing staged against them, because the marketing
    /// string matched and the stale build did not.
    nonisolated private static func readBundleVersions(
        _ bundle: URL
    ) -> (short: String?, build: String?) {
        let info = BundleLayout.infoPlistURL(for: bundle)
        guard let data = try? Data(contentsOf: info),
              let dict = (try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)) as? [String: Any]
        else { return (nil, nil) }
        func nonEmptyVersion(_ key: String) -> String? {
            guard let value = dict[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        return (nonEmptyVersion("CFBundleShortVersionString"),
                nonEmptyVersion("CFBundleVersion"))
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

    /// Guide the user out of a blocked App Store install: rebuild the helper's
    /// registration first (a record can read as approved yet no longer resolve — see
    /// `HelperShellRunner`), and only if that doesn't restore it, ask.
    ///
    /// Shown at most once per batch, like the App Management flow — an "Update All"
    /// across three App Store apps must not stack three identical dialogs.
    private func presentHelperApprovalFlowForInstallFailure() {
        if isInstallingAll {
            guard !helperApprovalFlowPresentedInBatch else { return }
            helperApprovalFlowPresentedInBatch = true
        }
        helperClient.reregister()
        helperEnabled = helperClient.isEnabled
        // Repaired silently — the record was stale, not unapproved. Nothing to ask;
        // the row keeps its error and the retry is one click away.
        guard !helperClient.isEnabled else {
            Log.install.notice("helper registration repaired without user action")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Turn on DuoUpdater's background helper")
        alert.informativeText = String(localized: """
            App Store updates install through a background item that macOS asks you to \
            approve once. Switch DuoUpdater on under Login Items & Extensions, then run \
            the update again — after that it stays on and never asks for your password.
            """)
        alert.addButton(withTitle: String(localized: "Open Login Items"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            helperClient.openLoginItems()
        }
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
    ///
    /// The suspension is deliberately untimed (waiting on the user must not burn the
    /// installer's poll budget), which makes it the one place an install can sit for
    /// hours — holding the App Store gate, a download permit and, through
    /// `installing`, the whole background check cadence. So it must never be a purely
    /// in-menu prompt: post a banner too, with a Relaunch action that answers it
    /// without the user having to open the popover and find the row.
    /// Put the quit-to-install question on screen. Returns immediately: the answer
    /// is read back through `quitAnswer(id:)`, so the installer keeps polling — and
    /// keeps seeing the world — while the user decides.
    private func requestQuit(id: String, appName: String) {
        UpdateNotifier.needsQuitConfirmation(app: appName, rowID: id)
        awaitingQuitConfirm[id] = appName
        quitAnswers[id] = .pending
    }

    /// What the user has said so far about quitting this app.
    private func quitAnswer(id: String) -> QuitPromptAnswer {
        quitAnswers[id] ?? .pending
    }

    /// Take the question back down — the install no longer needs an answer, because
    /// it got one elsewhere or the swap already happened. Leaving it up would strand
    /// a button whose action has become wrong rather than merely useless.
    private func withdrawQuit(id: String) {
        awaitingQuitConfirm[id] = nil
        quitAnswers[id] = nil
        UpdateNotifier.clearQuitConfirmation(rowID: id)
    }

    /// Resolve a pending quit-to-install prompt: `proceed` true presses the App Store
    /// sheet's Continue (the app quits and the update lands), false presses Cancel.
    /// Wired to the per-row "Relaunch to finish update" affordance and to the banner's
    /// Relaunch action.
    func confirmQuit(_ id: String, proceed: Bool) {
        // Nothing is waiting on an answer — a stale banner tapped after the install
        // already settled. Bail before touching `reopenAfterQuit`/`relaunching`,
        // which nothing would then clear.
        guard quitAnswers[id] != nil else {
            UpdateNotifier.clearQuitConfirmation(rowID: id)
            return
        }
        awaitingQuitConfirm[id] = nil
        UpdateNotifier.clearQuitConfirmation(rowID: id)
        // Quitting the app is what lets App Store swap it, and it does not reopen it
        // afterwards; remember to do that ourselves once the install lands. Show the
        // "Relaunching…" indicator meanwhile (cleared when the install settles in
        // `installApp`). Armed on the answer, not on the quit — the installer may find
        // the update already landed and skip the quit entirely, and reopening an app
        // that was never closed is a no-op.
        if proceed {
            reopenAfterQuit[id] = .userAskedToQuit
            relaunching.insert(id)
        }
        quitAnswers[id] = proceed ? .proceed : .declined
        Log.install.info("confirmQuit: \(id, privacy: .public) proceed=\(proceed)")
    }

    /// Reopen an app we quit for an incremental App Store update (App Store's
    /// Continue closes it without reopening). Idempotent — the set membership
    /// guards against a double reopen — so it's safe to call on both the success
    /// and the error/timeout exit of `install`, ensuring a quit-but-failed update
    /// never strands the user's app closed. Apps that weren't running were never
    /// inserted into `reopenAfterQuit`, so this only reopens what we closed.
    ///
    /// Reopened in the background: by the time this runs the user has been through
    /// the App Store sheet and the install, with App Store itself pulled to the
    /// front — whatever they've moved on to shouldn't be interrupted by their app
    /// popping back up. It's still there, just not in front.
    ///
    /// An app that is *still running* when this fires never got the quit it was
    /// asked for: its own save prompt outlasted the installer's ~12s terminate wait
    /// and then the ~90s post-Continue cap, so we're here on the timeout path with
    /// the app still up. Reopening a running app is a no-op, and consuming the entry
    /// here is what made the late answer an orphan: the user dismisses the prompt
    /// minutes later, the app finally quits, App Store swaps — and by then nothing
    /// remembers that this app is only closed because we asked it to be. So hand it
    /// to the terminate observer instead of dropping it (see `QuitHandoff`).
    private func reopenIfQuitForUpdate(_ result: UpdateResult, installSucceeded: Bool) {
        let id = result.id
        guard let reason = reopenAfterQuit.removeValue(forKey: id) else { return }
        if !AppRestarter.runningInstances(of: result.app).isEmpty {
            // Still up. Whether to hand this to the terminate observer turns on
            // whether a quit is actually coming — not on who asked for one.
            //
            // Gating on `userAskedToQuit` alone looked equivalent and was not:
            // that reason is only ever set by the App Store AX sheet, and the
            // strategy preference coerces every non-region-locked update onto
            // `mas`, which raises no sheet. So the arm was `storeMayCloseIt` in
            // the shipping configuration, this dropped it, and a running app that
            // `storedownloadd` terminated a few seconds after the install
            // returned stayed closed with nothing recorded — the exact failure
            // `AppStoreQuitPolicy` was written to end.
            //
            // A finished install means the store's swap has landed or is landing,
            // so the quit is expected. A failed or cancelled one closed nothing,
            // and arming there is how a cancelled update relaunched an app the
            // user had closed themselves ten minutes later.
            guard reason == .userAskedToQuit || installSucceeded else { return }
            // Only armable against a known pre-install version — that's what tells
            // the relay the store's swap has landed. Without one, fall through to
            // today's behaviour rather than guess at a landing.
            if !result.app.versionSide.isEmpty {
                quitHandoffs[id] = QuitHandoff(
                    result: result, landing: .appStoreSwap(past: result.app.versionSide),
                    activates: false, armedAt: Date())
                Log.install.info("relaunch-handoff: armed for \(result.app.name, privacy: .public) (still up past the App Store quit — reopen once it goes down)")
                return
            }
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(
            at: result.app.path, configuration: config, completionHandler: { _, _ in })
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
    /// True when the `.appStore` route is going to hand off or bail without
    /// installing anything, decided from state we already have here.
    ///
    /// Used for one thing only: skipping the rollback point. The early-outs
    /// themselves stay in the route below, which is where they belong — this
    /// predicts them because the backup runs *first*, and a store bundle is the
    /// most expensive copy we take (DingTalk is 1441 MB, Word 2750 MB; the clone
    /// is cheap but the manifest SHA-256s every byte, measured at 8.7s for Word).
    /// Paying that and then bailing also leaves a rollback point whose stored
    /// version is the one still installed, so the row offers to "roll back" to
    /// where it already is.
    ///
    /// Deliberately a *prediction*, not the guard itself: if the two ever drift
    /// the cost is a wasted backup, never a wrong install. The `mas outdated`
    /// pre-flight is not mirrored here — it costs a subprocess, which is the
    /// thing this is trying to avoid spending.
    private func appStoreRouteWillNotInstall(_ result: UpdateResult) -> Bool {
        // On the mas route these are store-managed by the App Store app itself and
        // we only open a deep link, so there is nothing to roll back from. The AX
        // route installs them like any other store app — and does take a backup,
        // which is why this cannot stay an unconditional true: `BackupStore` would
        // otherwise never have been asked to read a wrapped bundle.
        if result.app.isiOSAppOnMac, prefs.appStoreUpdateStrategy == .full { return true }
        // Nothing to install against.
        if result.remote?.appStore?.trackID == nil { return true }
        // Region-locked apps are AX-only, and the AX route needs the grant first.
        if result.remote?.appStore?.isRegionMismatch == true,
           !AppStoreAXInstaller.isTrusted { return true }
        return false
    }

    private func backupCurrent(_ result: UpdateResult, route: InstallCoordinator.Route) async {
        let outcome = await InstallCoordinator.backUp(result.app, route: route)
        if case .savedWithoutRuntimeState(let omitted) = outcome {
            Log.install.notice("backup: \(result.app.name, privacy: .public) stored without \(omitted, privacy: .public) runtime file(s)")
        }
        if case .unreadable(let path) = outcome {
            Log.install.notice("backup skipped: \(result.app.name, privacy: .public) — \(path, privacy: .public) unreadable")
            installNotes[result.id] = String(
                localized: "No rollback point: parts of this app aren’t readable by you (common for apps installed by a .pkg, which are often root-owned).")
        }
        if outcome == .failed {
            Log.install.error("backup failed: \(result.app.name, privacy: .public) — proceeding without a rollback point")
            // Tell the user their safety net is gone for this update, rather than
            // discovering it only when they later try to roll back and find nothing.
            installNotes[result.id] = String(
                localized: "Couldn’t back up the current version — this update will be applied without a rollback point.")
        }
    }

    /// Settings' "Clean Up Now" button: prunes orphaned backups regardless of the
    /// auto-prune preference, and refreshes the on-screen backup index so any
    /// rollback affordance that pointed at a just-removed orphan disappears.
    /// Returns the bytes freed, for the confirmation the button shows.
    /// Every stored backup, measured, for the delete sheet. Off the main actor:
    /// sizing walks each bundle.
    func backupListing() async -> [BackupStore.Listing] {
        await Task.detached(priority: .utility) { BackupStore.listing() }.value
    }

    /// Delete exactly the backups the user ticked, then re-read the index so the
    /// rows lose their rollback affordance and the total is honest again.
    func deleteBackups(keys: [String]) async {
        await Task.detached(priority: .utility) {
            for key in keys { BackupStore.remove(forKey: key) }
        }.value
        Log.install.notice("backups: deleted \(keys.count, privacy: .public) on request")
        await refreshBackupIndex()
    }


    /// Re-read which apps have a rollback backup on disk (one directory scan),
    /// mapping it onto the current rows.
    func refreshBackupIndex() async {
        let map = await Task.detached(priority: .utility) { BackupStore.allBackups() }.value
        var byID: [String: String] = [:]
        var sides: [String: VersionSide] = [:]
        for result in results {
            for key in BackupStore.keyCandidates(
                bundleID: result.app.bundleID, path: result.app.path)
            where map[key] != nil {
                byID[result.id] = map[key]?.version ?? "previous"
                sides[result.id] = map[key]?.versionSide ?? VersionSide()
                break
            }
        }
        backupVersions = byID
        backupSides = sides
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
        // Read while the backup is still addressable by key, for the note below.
        let wasFromAppStore = BackupStore.backup(forKey: key)?.fromAppStore == true
        installErrors[id] = nil
        installing[id] = .installing
        // Same reason as an install: this row's rank is about to change (it stops
        // being up to date, or picks up a Restart badge) under whoever is clicking.
        pinRowOrder()
        defer { releaseRowOrder() }
        Log.install.info("rollback start: \(result.app.name, privacy: .public)")
        // A rollback replaces a bundle and reads the backup store, so it takes
        // the same machine-wide claim an install does. Without it, `duo backups
        // restore` and this could swap the same app at once — the CLI would
        // stand aside for an install and then walk straight into a rollback.
        do {
            try await ProcessInstallLock.shared.claim()
        } catch {
            Log.install.error("rollback blocked by the machine install lock: \(result.app.name, privacy: .public)")
            installErrors[id] = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
            installing[id] = nil
            return
        }
        do {
            let restored = try await Task.detached(priority: .userInitiated) { () -> String? in
                try BackupStore.restore(forKey: key, over: target)
            }.value
            // The swap has landed; everything below is bookkeeping and needs no
            // exclusion, so hand the claim back rather than holding it through a
            // rescan (same reasoning as the apply permit in `performInstall`).
            await ProcessInstallLock.shared.release()
            AppIconCache.invalidate(target.path)
            let updated = await recheck(result)
            replaceRow(updated)
            await computeRestartInfo()
            await computeSelfUpdateStaging()
            await refreshBackupIndex()
            installing[id] = nil
            // The one rollback that another process can undo without being asked.
            // The store lists the update again the moment the older bundle is back,
            // and re-installs it by itself when automatic app updates are on (the
            // default) — so the row has to say that the version on screen may not
            // stay. Not registered in `inFlightNotes`: like `backupCurrent`'s
            // warning it describes what just finished, so a settled row is exactly
            // when it starts to matter.
            if wasFromAppStore {
                installNotes[id] = String(
                    localized: "Rolled back, but \(updated.app.name) updates through the App Store — it will offer this update again, and re-install it on its own if automatic app updates are on.")
            }
            Log.install.info("rollback done: \(updated.app.name, privacy: .public) → \(restored ?? "?", privacy: .public)")
            if needsRestart.contains(updated.id) {
                UpdateNotifier.readyToRestart(app: updated.app.name, version: restored, appID: updated.app.bundleID)
            }
        } catch {
            await ProcessInstallLock.shared.release()
            Log.install.error("rollback failed: \(result.app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            installErrors[id] = error.localizedDescription
            installing[id] = nil
        }
    }

    // MARK: - Batch update

    /// Keep batch installs parallel without letting a large update wave saturate
    /// the network, Homebrew, and privileged swap prompts all at once. This is
    /// the batch task group's *spawn* bound; the permits below bound how many
    /// installs actually *run* — including manual clicks that land while a
    /// batch is in progress.
    private static let maxParallelInstalls = 3

    /// The two resources an install consumes at different stages, each with its
    /// own permit:
    ///  - **download (4)** — held only while fetching the update's bytes. The
    ///    network is the high-latency, shared resource, so it gets the most
    ///    slots; but not more — every download host is already sub-capped at 2
    ///    (below), and four simultaneous transfers is plenty for a background
    ///    updater on a home uplink.
    ///  - **apply (2)** — held while extracting, verifying, and swapping the
    ///    bundle. That's disk + privileged work, and the swap is the operation
    ///    that can stack App Management auth prompts. Tightened from the old
    ///    single gate's 3 because applies now actually *fill* their slots — the
    ///    download stage no longer competes for the same permits — and they're
    ///    short (seconds) next to downloads (minutes), so 2 doesn't hold up a
    ///    wave.
    /// Splitting the single gate means a slot never sits idle on the network
    /// while its install extracts and swaps, and vice versa: the download
    /// permit is released before the apply one is taken, so the two stages
    /// pipeline across apps. Every install (manual or batch) draws from this
    /// one pool, so a wave of clicks can't all fire at once.
    private static let installPermits = InstallPermits(downloads: 4, applies: 2)

    /// Every route but the App Store runs through here, sharing the pool above
    /// so the store's fetch still competes for the same budget. The CLI builds
    /// its own with its own pool — the cross-process exclusion is
    /// ``InstallLock``, not these permits.
    private static let installCoordinator = InstallCoordinator(permits: installPermits)

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

    /// Feed-URL host → the host that actually served the bytes, learned from a
    /// completed download through that feed host (see `recordEffectiveHost`).
    /// Real bytes frequently come from a CDN after redirects, so the gate must
    /// key on the server that really serves them, not the URL written in the
    /// feed — two "different" hosts that bounce to one CDN should share a cap,
    /// and the cap is about the CDN, not the feed.
    private static var effectiveHostByFeedHost: [String: String] = [:]

    /// Remember which host actually served an install's bytes, so the per-host
    /// gate keys on it from the next download through this feed host on.
    private func recordEffectiveHost(_ result: UpdateResult, finalHost: String?) {
        guard let feedHost = result.remote?.downloadURL?.host, let finalHost,
              feedHost != finalHost else { return }
        Self.effectiveHostByFeedHost[feedHost] = finalHost
    }

    /// One semaphore per download host, created on demand. Main-actor isolated, so
    /// the lookup/insert needs no extra locking. Entries are never evicted — the set
    /// of hosts is tiny and bounded by the installed-app catalog.
    private var hostInstallGates: [String: AsyncSemaphore] = [:]

    private func hostInstallGate(for host: String) -> AsyncSemaphore {
        // Key on the host that actually SERVED the bytes once we've learned it
        // from a previous download through this feed host (see
        // `recordEffectiveHost`). The first download per feed host still keys on
        // the feed URL's host: the redirect target can't be known before the
        // first response, and a HEAD request per install just to learn it is
        // not worth a round trip. So two apps whose feeds bounce to the SAME
        // CDN are throttled together from their second download onward, and an
        // app whose feed host serves different CDNs at different times is
        // throttled on the last-seen one — still better than throttling on a
        // host that never sends a byte.
        let effective = Self.effectiveHostByFeedHost[host] ?? host
        if let gate = hostInstallGates[effective] { return gate }
        let gate = AsyncSemaphore(value: Self.maxPerHostInstalls)
        hostInstallGates[effective] = gate
        return gate
    }

    /// Pending updates "Update All" should act on: in-place installs only, no
    /// confirmation gates, and no row that's already busy. Snapshotted up front
    /// so the re-sorting each install triggers can't reshuffle what we iterate.
    private func installAllTargets() -> [UpdateResult] {
        results.filter { result in
            isActionableUpdate(result)
                // `requiresInstaller` too, not just `canAutoInstall`: a vendor `.pkg`
                // (ToDesk, AweSun) sets `requiresManualInstaller`, which excludes it
                // from `canAutoInstall` — so those apps used to be silently absent
                // from "Update All" and could only be updated one row at a time. The
                // download is unattended like any other; only the final hand-off to
                // the system installer needs the user, and `installAll` runs those
                // last (see its phase ordering).
                && (canAutoInstall(result) || requiresInstaller(result))
                && !defersToSelfUpdater(result)
                && !result.isMajorUpgrade
                && installing[result.id] == nil
        }
    }

    /// Only independent archive/appcast installs run in parallel, and only once
    /// App Management is known granted.
    ///
    /// The switch below is reached ONLY by results `installAllTargets()` already
    /// passed through `canAutoInstall(result) || requiresInstaller(result)` — so
    /// a source `UpdatePolicy` has no case for at all (Xcode Releases, Toolbox,
    /// TestFlight: always `default: false` on both) never reaches `targets` to
    /// begin with, let alone this function. It isn't mis-scheduled here; it's
    /// simply not a candidate. `requiresInstaller` results are peeled off first
    /// by the guard above (a Vendor/GitHub/Electron `.pkg`, a signed Sparkle
    /// `.pkg`, a Homebrew cask needing the manual installer) — those go through
    /// the system installer, the batch's phase 3, never this switch.
    ///
    /// What can still reach `default: false` here, given the above, is exactly
    /// two sources: Homebrew (shells out to the `brew` CLI, one shared process
    /// per invocation) and App Store (drives `mas` or App Store.app's own UI
    /// automation) — both share a system-level resource a second simultaneous
    /// install would contend with, so they stay serial. Sparkle/Vendor/GitHub/
    /// Electron are independent in-place archive swaps (`InPlaceSwap`) with no
    /// such shared resource, so they run in the bounded parallel window —
    /// Electron joined this list in #192's follow-up: it goes through the exact
    /// same `VendorInstaller`+`InPlaceSwap` pipeline as Vendor/GitHub, so by
    /// this function's own criterion it belongs here, not in `default`. (Whether
    /// parallelizing could race an electron-builder app's own self-updater is a
    /// question this switch was never answering: `defersToSelfUpdater` already
    /// excluded a running one from `targets`, and `UpdatePolicy
    /// .stagedBlocksInstall` is enforced inside `runInstall` itself, which the
    /// parallel and serial paths both call — identically either way.)
    private func canBatchInstallInParallel(_ result: UpdateResult) -> Bool {
        guard !requiresInstaller(result) else { return false }
        guard appManagementStatus == .granted else { return false }
        switch result.remote?.sourceName {
        case "Sparkle", "Vendor", "GitHub", "Electron":
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

    /// Install every pending update we can apply without a confirmation gate —
    /// skipping major upgrades (license-boundary warning), Toolbox / TestFlight
    /// (managed elsewhere), and anything ignored or version-skipped. Independent
    /// Sparkle/Vendor/GitHub swaps may run with a bounded parallel window; App Store
    /// and Homebrew entries run serially because they share global tools/UI
    /// automation; vendor `.pkg` updates run last, since they end in a system
    /// installer window that interrupts the user. The shared restart/staging/backup
    /// sweep runs once after the whole batch has settled.
    func installAll() async {
        // Say WHY, like `refresh` and `refreshLocal` do. A notification banner's
        // "Update All" routes straight here, so a tap that lands while a check or a
        // refresh is running is otherwise a banner that dismisses with nothing
        // installed and nothing logged.
        guard listActivity.canInstallAll else {
            Log.app.info("update all: skipped — \(String(describing: self.listActivity), privacy: .public)")
            return
        }
        refreshPermissionStatus()
        // The filter below consults `defersToSelfUpdater`, which reads the running
        // set. That set is only maintained by NSWorkspace launch/terminate
        // notifications, which this menu-bar app misses while App-Napped — so a
        // stale "still running" under `.deferWhenRunning` would drop an app from the
        // batch here, before it ever reaches the live re-check in `performInstall`,
        // and the result would be no install and no diagnostic. Refresh first so the
        // pre-filter and the per-install decision are made on the same facts.
        refreshRunningApps()
        let targets = installAllTargets()
        guard !targets.isEmpty else { return }
        isInstallingAll = true
        appManagementPermissionFlowPresentedInBatch = false
        helperApprovalFlowPresentedInBatch = false
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
            // The batch is the LAST thing to clear `isInstallingAll`, so every
            // `releaseRowOrder` inside it — each `runInstall`'s, each restart's — was
            // still gated by this flag and no-opped. Without a release here the frozen
            // order outlives the batch: a batch of running apps never calls
            // `markJustUpdated` at all (they settle as `.awaitingBatchRestart`), so the
            // two-second confirmation, the usual release point, never exists either.
            releaseRowOrder()
        }

        // Three phases, in this order:
        //   1. parallel  — independent in-place swaps, bounded window
        //   2. serial    — Homebrew / App Store: share global tools and UI automation
        //   3. installer — vendor `.pkg`: hands off to the system installer, which
        //                  opens a window and asks for an admin password
        // Phase 3 goes last so every unattended update is already done before
        // anything interrupts the user. Note the hand-off is fire-and-forget: we
        // can't observe the system installer finishing, so two pkg updates in one
        // batch open two Installer windows back to back rather than queueing.
        // Within each phase, sort smallest download first: a 400 MB update
        // shouldn't occupy a slot while nine 20 MB ones queue behind it. Unknown
        // sizes sort neutrally (see `InstallBatchOrdering`).
        let parallelTargets = InstallBatchOrdering.sortByDownloadSize(targets.filter(canBatchInstallInParallel))
        let rest = targets.filter { !canBatchInstallInParallel($0) }
        let serialTargets = InstallBatchOrdering.sortByDownloadSize(rest.filter { !requiresInstaller($0) })
        let installerTargets = InstallBatchOrdering.sortByDownloadSize(rest.filter(requiresInstaller))
        let limit = min(Self.maxParallelInstalls, parallelTargets.count)
        Log.app.info("update all: \(targets.count, privacy: .public) apps, parallel=\(parallelTargets.count, privacy: .public), serial=\(serialTargets.count, privacy: .public), installer=\(installerTargets.count, privacy: .public), parallelism=\(limit, privacy: .public)")
        // Count only the installs that actually happened (runInstall returns false for
        // already-current/early-out/error), so the summary banner is exact.
        var installed = 0
        installed += await installInParallel(parallelTargets, limit: limit)
        for target in serialTargets + installerTargets {
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
        // The authoritative process-version sweep inside `performLocalRescan` has
        // now converted these provisional states into `needsRestart` (or proved the
        // app stopped meanwhile). From here the normal Restart state owns the row.
        pendingBatchRestart.removeAll()
        // Auto-restart the apps this batch just updated and left awaiting a restart,
        // so "Update All" doesn't leave a pile of "Relaunch" buttons (the per-app
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

    /// Whether to show the batch button: nothing in flight, and more than one app
    /// it would act on. Both halves live in `ListActivity.canOfferUpdateAll`.
    var canUpdateAll: Bool {
        listActivity.canOfferUpdateAll(targetCount: installAllTargets().count)
    }

    // MARK: - Ignore / skip

    /// Toggle whether this app is hidden from update checks entirely.
    func toggleIgnore(_ result: UpdateResult) {
        let nowIgnored = !prefs.isIgnored(result.app)
        prefs.setIgnored(nowIgnored, result.app)
        syncDockBadge()
        if nowIgnored {
            // A "Relaunch to apply it" banner already sitting in Notification Center
            // outlives the ignore on its own — clearing notifications isn't what
            // anyone does next after ignoring an app. Withdrawn, not just cleared,
            // so un-ignoring can announce it again.
            withdrawStagedNudge(result)
        } else {
            // Un-ignoring has to ask. While the app was ignored no refresh spent a
            // request on it, so its row carries no remote at all — without this it
            // would sit at the bare source hint until the next scheduled check, up
            // to an hour of a row that reads as broken right after the user asked
            // to see it again.
            Task { await recheckAfterUnignore(result) }
        }
        // Un-ignoring an app with a staged build brings its relaunch nudge back,
        // once — the ignore withdrew the ledger entry, so this is a real announce
        // rather than a no-op. (Ignoring posts nothing: `nudgeableStaged` gates on
        // it, and the withdrawal above has already run.)
        notifyStagedRelaunches()
        Log.app.info("\(nowIgnored ? "ignore" : "unignore", privacy: .public): \(result.app.name, privacy: .public)")
    }

    /// Re-check one app the moment it stops being ignored, so the row it comes back
    /// to is a real verdict rather than the blank one an ignored app carries.
    private func recheckAfterUnignore(_ result: UpdateResult) async {
        guard installing[result.id] == nil else { return }
        installing[result.id] = .checking
        let updated = await recheck(result)
        installing[result.id] = nil
        replaceRow(updated)
        syncDockBadge()
        Log.app.info(
            "unignore re-check: \(updated.app.name, privacy: .public) → \(String(describing: updated.status), privacy: .public)")
    }

    /// Whether this row is demoted to "Open" purely because the user dismissed its
    /// administrator prompt — the only state the context-menu item below can undo.
    func isElevationDeclined(_ result: UpdateResult) -> Bool {
        UpdatePolicy.elevationDeclined(result, settings: policySettings, environment: policyEnvironment)
    }

    /// Retire a declined administrator prompt, so the row offers Update again and
    /// the next click re-asks. The way back out of the declined state: without it,
    /// one dismissed panel would permanently and silently downgrade the app to
    /// detection-only, with nothing in the UI saying why or how to undo it.
    func allowElevatedInstall(_ result: UpdateResult) {
        prefs.setElevationDeclined(false, result.app)
        installErrors[result.id] = nil
        Log.app.info("re-allowing administrator installs for \(result.app.name, privacy: .public)")
    }

    /// Decline the currently-offered version for this app; a newer one still shows.
    func skipThisVersion(_ result: UpdateResult) {
        // The PAIR, so the record says which build was declined. Recorded as the
        // marketing string alone, a skip on an app that ships many builds under
        // one name silenced every later build of it, permanently and across
        // restarts. See `VisibilityRules.skipKey`.
        let version = result.remote?.versionSide ?? VersionSide()
        guard !version.isEmpty else { return }
        prefs.skipVersion(version, result.app)
        syncDockBadge()
        // A "Relaunch to apply it" banner already in Notification Center is for the
        // version just declined (a banner only exists while the staged build is the
        // latest, i.e. this very version), so it must not outlive the skip.
        //
        // Cleared, NOT withdrawn — unlike ignoring. The skip is recorded against the
        // offered `displayVersion`, while the gate that has to hold afterwards
        // (`VisibilityRules.isVersionSkipped`, through `nudgeableStaged`) is asked
        // about `staged.version`, and it compares strings exactly where
        // `actionableStaged` compares versions. Where those two strings differ — a
        // build suffix, "1.2" against "1.2.0" — forgetting the ledger entry would
        // let the very next staging pass post a banner for the version the user just
        // skipped. The entry is the belt behind those braces. The cost is that
        // un-skipping doesn't bring the banner back; the row and the badge do.
        UpdateNotifier.clearSelfDownloaded(appID: result.id)
        Log.app.info("skip \(VisibilityRules.skipKey(version), privacy: .public): \(result.app.name, privacy: .public)")
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
    /// as `.scheduled`, which skips the TestFlight container read so a silent check
    /// (notably the one a cold launch fires immediately) can't surface the "access
    /// data from other apps" prompt unprompted, and leaves the release notes the
    /// user may be reading in place (`RefreshIntent`).
    private func backgroundRefresh() async {
        await refresh(intent: .scheduled)
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

        // Second stream, different roots: the vendor preferences that hold a
        // `ChannelBinding` app's channel choice. A flip there changes which feed we
        // read but touches no app bundle, so `appDirWatcher` above is blind to it,
        // and the two events we relied on before both miss the ordinary case — see
        // `ChannelBinding.preferenceWatchPaths` for the Surge timeline that made
        // this necessary.
        //
        // A quarter-second debounce, well under the app watcher's 2s: a preference
        // flush is one rename, not a multi-second bundle swap, and the whole point
        // of this stream is to put the row into its checking state before the user
        // can act on a verdict their flip has just invalidated — every millisecond
        // of debounce is time that row spends live and wrong. It used to be 1s,
        // which was the bulk of the measured 2.4s a flip took to settle. Cutting it
        // is only safe now that `recheckChannelSwitches` supersedes its own passes:
        // a burst that fires several times just cancels itself down to the last
        // one, where before each extra event was work we could not take back.
        let prefPaths = ChannelBinding.preferenceWatchPaths
        if !prefPaths.isEmpty {
            let prefsWatcher = AppDirectoryWatcher(paths: prefPaths, debounce: 0.25) { [weak self] in
                Task { @MainActor in
                    await self?.recheckChannelSwitches(trigger: "prefs-watch")
                }
            }
            channelPrefsWatcher = prefsWatcher
            prefsWatcher.start()
            Log.app.info("channel prefs: watching \(prefPaths.joined(separator: ", "), privacy: .public)")
        }

        // Sleep is the one moment we KNOW the stream may have missed writes (a brew
        // upgrade or Keystone swap during sleep lands with no live event) — and it's
        // a plausible way for a stream to be left dead. Rebuild it on wake; the
        // re-arm rescans immediately, so anything swapped while asleep shows up at
        // once instead of waiting for the backstop.
        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Log.app.debug("local rescan: re-arming FS watchers after wake")
            self?.appDirWatcher?.rearm()
            // Same treatment for the channel-preference stream: a toggle flipped
            // just before the machine slept lands with no live event.
            self?.channelPrefsWatcher?.rearm()
        }
        runningAppObservers.append(wakeObserver)

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
                    // The PAIR, so an app that self-updated externally between
                    // builds under one marketing name is not left on screen with a
                    // stale `buildVersion` that later comparisons then trust.
                    || !VersionComparator.isSame(fresh.app.versionSide,
                                                 as: next[i].app.versionSide)
              else { continue }
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

    /// Seed `runningAppPaths` from the current process list and keep it live.
    ///
    /// **The source of truth is KVO on `NSWorkspace.runningApplications`**, which
    /// AppKit's own header prescribes: "Instead of polling, use key-value observing
    /// to be notified of changes to this array property" (`NSRunningApplication.h`).
    /// The launch/terminate notifications are kept as a second, independent
    /// delivery path — they cost one no-op recompute each when both fire.
    ///
    /// **Why not the notifications alone** (issue #247). They are posted per app by
    /// LaunchServices and are, measured on this machine, simply missing for some
    /// apps in both directions, while the array — which cannot fail to lose an
    /// entry when a process exits — always moved. One process, all four observers
    /// plus a 200 ms poll as ground truth, 2026-09-02:
    ///
    ///     Alcove, 4 quits + 4 relaunches   notifications 0/8   KVO 8/8
    ///     UURemote quit (+UURemoteServer)  no didTerminate     KVO caught both
    ///     AppCleaner (control)             both fire           KVO 512 ms earlier
    ///
    /// KVO also beat the 200 ms poll by 26–180 ms on every transition, so the
    /// ~2 s reconcile timer the issue proposed is not needed: there is nothing for
    /// it to catch that this misses sooner.
    ///
    /// **What it does not change.** The property "will only change when the main
    /// run loop is run in a common mode" (same header) — exactly the condition the
    /// notifications already needed, and the reason a snapshot taken without a live
    /// run loop is stale either way.
    ///
    /// What one event costs, on the main thread: one `runningApplications`
    /// snapshot (~140 entries, ~130 with a bundle URL and ~105 of those distinct),
    /// a bundle-id set, and a `realpath` for each bundle path *not seen in the
    /// previous snapshot* — for most events, none; for a launch, the app and
    /// whatever XPC services came up with it. `RunningBundlePathCache` is what
    /// keeps it to that: this used to resolve every running bundle's symlinks on
    /// every event, measured at 1.16 ms against 0.10 ms now (release build, live
    /// snapshot), per launch/quit anywhere on the machine, all day, under a
    /// comment that called it an in-memory walk.
    private func armRunningAppsMonitor() {
        // Seed before observing rather than passing `.initial`: the seed must set
        // the baseline the first real change is diffed against, without running the
        // change handler's side effects (a channel pass over every bound app) at
        // launch.
        refreshRunningApps()
        // Not `[.new]`: the handler re-reads the property itself, and asking KVO to
        // carry a ~140-element array on every process event anywhere on the machine
        // buys nothing.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            // The property mutates on the main run loop, but KVO delivers on
            // whatever thread stores the value; hop rather than assume.
            Task { @MainActor in self?.handleRunningAppsChange() }
        }
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
    /// event is the only live one that marks it. Without recomputing here the
    /// "Relaunch" badge lingered until the 180s backstop (or the user reopening the
    /// popover) — the "I restarted it myself but it still shows Relaunch" report.
    private func handleRunningAppsChange() {
        // Both snapshots, so the channel gate below can tell which identifiers
        // actually appeared or disappeared. Taken here rather than inside
        // `refreshRunningApps` because the install paths call that one too, and
        // they have no event to gate.
        let before = runningBundleIDs
        refreshRunningApps()
        // Off by default (debug level), and the one thing that makes this monitor
        // debuggable at all: issue #247 was a *missing* event, which leaves no
        // trace anywhere. `log stream --debug --predicate 'subsystem == "..."'`
        // while opening and quitting an app answers "did the event reach us" in
        // one step, instead of another standalone observer process.
        if before != runningBundleIDs {
            let appeared = runningBundleIDs.subtracting(before).sorted()
            let left = before.subtracting(runningBundleIDs).sorted()
            Log.app.debug(
                "running apps: +[\(appeared.joined(separator: " "), privacy: .public)] -[\(left.joined(separator: " "), privacy: .public)]")
        }
        // Before the needs-restart early-out below: a quit hand-off fires exactly
        // on a terminate event, and usually with `needsRestart` empty.
        settleQuitHandoffs()
        // A `ChannelBinding` app launching or quitting is the other moment (besides
        // `windowAppeared`) we use to notice its channel toggle flipped in the
        // vendor app itself — the common "open Settings, flip the toggle, quit"
        // flow. Independent of the needs-restart early-out below: a channel switch
        // has nothing to do with a pending restart.
        //
        // Gated on the identifiers that actually changed. This fires for EVERY app
        // on the machine — every helper, every menu-bar utility, all day — and the
        // pass behind it reads one vendor preference per bound app (Surge's is a
        // plist read off disk). Nine of those on every launch/quit event on the
        // system is not what "free unless something changed" meant. The gate also
        // absorbs the duplicate when KVO and a notification both report one event:
        // whichever arrives second sees an unchanged set and does no work.
        if ChannelSwitchDetector.isWorthRechecking(
            runningBundleIDsChangedFrom: before, to: runningBundleIDs) {
            Task { await recheckChannelSwitches(trigger: "running-apps-change") }
        }
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
    /// so the comparison in `isRunning` lines up. The resolution is a `realpath`
    /// per bundle, so it goes through `runningBundlePaths`, which only pays it for
    /// paths that were not in the previous snapshot.
    private func refreshRunningApps() {
        // One snapshot, both readings: a second `runningApplications` call could
        // straddle an app launching or quitting and leave the two disagreeing.
        let running = NSWorkspace.shared.runningApplications
        runningAppPaths = runningBundlePaths.update(with: running.compactMap(\.bundleURL))
        runningBundleIDs = Set(running.compactMap(\.bundleIdentifier))
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
        // Self-staged builds (the app downloaded its own update) get their own
        // "relaunch to apply it" banner from `notifyStagedRelaunches`, on the staging
        // pass rather than here — so they ride along in this count only as much as
        // they always did via `isActionableUpdate`.
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
        await recheckMany([result]).first ?? result
    }

    /// The batch form: one disk read and one `UpdateChecker` for the whole set,
    /// rather than `recheck` per row. `retryFailedChecks` can hand this a hundred
    /// rows after an outage, and per-row it would mean a hundred reads and a hundred
    /// GitHub-token resolves for one answer each.
    ///
    /// The read is scoped to the rows' own bundles (`AppScanner.scan(bundlesAt:)`),
    /// not a sweep of every location: a recheck is only ever asked about rows it
    /// already holds, and sweeping ~145 apps to re-read one was the bulk of an
    /// Update click's disk work — twice per click, before and after the install
    /// (issue #226). Anything a sweep would find that this cannot — an app installed
    /// since, a clone that would now dedupe differently, a row whose custom folder
    /// was removed in Settings — is the next full scan's job. The token comes from
    /// `githubTokenForRecheck` for the same reason.
    ///
    /// Rows that no longer scan (uninstalled between the failure and the retry)
    /// simply come back missing, which is why callers keep their own copy.
    private func recheckMany(_ targets: [UpdateResult]) async -> [UpdateResult] {
        let ids = Set(targets.map(\.id))
        guard !ids.isEmpty else { return [] }
        // Off-main and TestFlight-free: the post-install recheck must never block the
        // UI on the TestFlight container's TCC gate. The next full refresh re-applies
        // TestFlight tagging, so a single-app recheck just scans without it.
        let testflight = TestFlightInventory(macRows: [], accessible: false)
        let toolbox = await Task.detached(priority: .userInitiated) { Self.toolboxInventory() }.value
        let githubToken = await githubTokenForRecheck()
        let bundles = targets.map(\.app.path)
        let apps = await Task.detached(priority: .userInitiated) {
            AppScanner(toolbox: toolbox, testflight: testflight).scan(bundlesAt: bundles)
        }.value
        // Identity is the resolved path, which is what a row already carries, so
        // this normally admits everything. Kept as the guard it always was: a bundle
        // that now resolves elsewhere reads as gone, not as a row under another id.
        let fresh = apps.filter { ids.contains($0.id) }
        guard !fresh.isEmpty else { return [] }
        let checker = UpdateChecker(
            sources: makeSources(token: githubToken),
            maxConcurrency: prefs.maxConcurrency,
            toolbox: ToolboxSource(inventory: toolbox),
            testflight: testflight)
        return await checker.check(fresh)
    }

    // MARK: - Failed checks

    /// Rows whose last check ended in `.error` — every source either missed or
    /// threw, so we do not know whether that app has an update.
    ///
    /// This has to be visible somewhere. A failed check used to be indistinguishable
    /// from a clean one: `.error` rows are filtered out of the popover unless "Show
    /// all" is on, and the header reads its text off `updateCount`, which counts
    /// only actionable updates — so a round where every networked source failed
    /// rendered as "127 apps · up to date". That is the worst possible way to be
    /// wrong: it is the same screen the user gets when everything really is fine.
    ///
    /// `NetworkMonitor` does not cover this. It defers the *scheduled* check while
    /// `NWPathMonitor` reports no path, but the failure that prompted this was a
    /// local proxy dropping connections with the interface up and satisfied — the
    /// path was fine, every request was not.
    /// How many *completed* rounds in a row each row has come back `.error`. Keyed
    /// by `UpdateResult.id` (the install path). In memory only — a fresh launch
    /// starts everyone at zero, which is the right bias: after a relaunch we have no
    /// evidence a failure is chronic and should say so once more.
    ///
    /// This is the ONLY place a chronic streak is tracked. `RowAction.state(for:)`
    /// — the ladder both the popover and the workbench draw a row from — has no
    /// notion of it and is not meant to: see `failedCheckResults` below and
    /// `CheckFailureRules` for why (issue #264).
    @ObservationIgnored private var consecutiveCheckFailures: [String: Int] = [:]

    /// Update the streaks from one completed round, and drop rows that are gone.
    /// Called only from `performRefresh` — deliberately NOT from `retryFailedChecks`,
    /// or a user clicking Retry a few times during an outage would mark the whole
    /// outage chronic and hide the very banner they were responding to.
    private func recordCheckOutcomes(_ checked: [UpdateResult]) {
        var next: [String: Int] = [:]
        for result in checked {
            if case .error = result.status {
                next[result.id] = (consecutiveCheckFailures[result.id] ?? 0) + 1
            }
        }
        let newlyChronic = next.filter {
            $0.value == CheckFailureRules.chronicThreshold
        }.keys.sorted()
        if !newlyChronic.isEmpty {
            Log.app.info(
                "check failures now chronic (hidden from the banner): \(newlyChronic.joined(separator: ", "), privacy: .public)")
        }
        consecutiveCheckFailures = next
    }

    /// Rows this many rounds deep stop driving the *aggregate* surfaces below —
    /// the banner, the header's "N not checked" line, and the bulk-retry target
    /// list. They do NOT stop being `.checkFailed` rows: `RowAction.state(for:)`
    /// never reads `consecutiveCheckFailures` (it has no parameter for it), so a
    /// chronic row keeps its own orange Failed badge — with its own per-row
    /// Retry, which re-checks only this app rather than every failed row the way
    /// the banner's Retry does — for as long as it keeps failing.
    ///
    /// That split is deliberate, not an oversight (issue #264): the banner is one
    /// global claim ("your checks are healthy") that becomes false advice once a
    /// failure is permanent — a vendor that retired its feed fails identically
    /// forever, and Alfred's appcast did exactly that for weeks. Left counted, it
    /// pins the banner up with a Retry that just re-runs the same 404, and stops
    /// the header from ever reading "up to date" again. A row's own badge makes
    /// no such claim; it states one fact about one app, and that fact stays true.
    /// Silencing it would blank the row in the workbench, which shows every
    /// result unconditionally (no "Show all" gate) — and a blank row there reads
    /// as "up to date", which is the specific failure mode `RowActionState`
    /// exists to rule out for every non-quiet state. See `CheckFailureRules`.
    var failedCheckResults: [UpdateResult] {
        results.filter {
            guard case .error = $0.status else { return false }
            return !CheckFailureRules.isChronic(
                consecutiveFailures: consecutiveCheckFailures[$0.id] ?? 0)
        }
    }

    var failedCheckCount: Int { failedCheckResults.count }

    /// The error text the most failed rows share, for the banner's subtitle. One
    /// cause usually explains the whole cluster ("Could not connect to the server."),
    /// and naming it is the difference between "something went wrong" and knowing
    /// to look at the network.
    var failedCheckSummary: String? {
        let texts = failedCheckResults.compactMap { result -> String? in
            if case .error(let message) = result.status { return message }
            return nil
        }
        return Dictionary(grouping: texts, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
    }

    /// True while `retryFailedChecks` is in flight, so the banner can show a spinner
    /// instead of an armed button.
    private(set) var isRetryingFailedChecks = false

    /// Re-check exactly the rows that failed, leaving every settled row alone.
    ///
    /// Deliberately not a plain `refresh()`: a full refresh blanks all ~130 rows to
    /// `.unknown` and re-asks every source, when the thing that needs re-asking is
    /// the handful that errored. Rows already busy with an install are skipped —
    /// their own flow re-checks them.
    func retryFailedChecks() async {
        guard !isRetryingFailedChecks, !isRefreshing, !isInstallingAll, installing.isEmpty else { return }
        // Same rule the full refresh applies: an ignored app is not asked after, so
        // retrying must not spend the request `performRefresh` refuses to spend.
        let targets = failedCheckResults.filter { prefs.deservesCheck($0.app) }
        guard !targets.isEmpty else { return }
        Log.app.info("retry failed: re-checking \(targets.count, privacy: .public) errored rows")

        // `isChecking`, NOT per-row `installing` claims. `installing` is the app's
        // global "something is in flight" predicate — `canRefresh`, `canUpdateAll`,
        // `refreshLocal` and `installAll` all read `installing.isEmpty` — so claiming
        // 120 rows after an outage would make Update All *vanish* from the header and
        // grey out Refresh for minutes with nothing on screen saying why (the header
        // spinner keys off `listActivity.isRoundInFlight`, which those claims never
        // set — but `isChecking` does, so the spinner runs for this too).
        // `isChecking` disables the same controls for the same duration, but it is
        // what a check in flight actually is, and it shows the spinner while it runs.
        // It also keeps the failed rows out of `visible`, which claims would have
        // popped in as ~120 spinner rows and resized the popover twice.
        isRetryingFailedChecks = true
        isChecking = true
        defer {
            isRetryingFailedChecks = false
            isChecking = false
        }
        let updated = await recheckMany(targets)
        for result in updated { replaceRow(result) }
        // A row can come back "already updated on disk, needs a restart"; without this
        // it gets no Restart badge until the next rescan.
        await computeRestartInfo()
        syncDockBadge()
        // `refreshLocal`/`backgroundLocalRescan` skip while `isChecking` and leave
        // `localRescanDeferred` set, exactly as they do during an install. Drain it
        // here for the same reason `install` does, rather than making an FS event
        // that landed mid-retry wait for the 180s backstop.
        await drainDeferredLocalRescan()
        Log.app.info(
            "retry failed: \(updated.count, privacy: .public) re-checked, \(self.failedCheckCount, privacy: .public) still failing")
    }

    // MARK: - Channel-switch recheck

    /// Bound-app id (lowercased bundle id) → fingerprint of the channel we last
    /// resolved for it (see `ChannelSwitchDetector`). Empty until the first call
    /// to `recheckChannelSwitches`; that first call seeds it rather than treating
    /// every bound app as having just "changed".
    @ObservationIgnored private var lastSeenChannelFingerprints: [String: String] = [:]
    /// Guards against overlapping passes — a bound app's launch and terminate
    /// notifications can arrive back to back — queuing duplicate rechecks.
    /// The channel-switch pass currently in flight, so a newer trigger can
    /// supersede it (see `recheckChannelSwitches`).
    @ObservationIgnored private var channelRecheckTask: Task<Void, Never>?

    /// The bound-app ids currently on screen. Main-actor (it reads `results`) but
    /// pure memory — the disk-touching half is `fingerprints(forBoundIDs:)`.
    private func onScreenBoundBundleIDs() -> [String] {
        results.compactMap {
            guard let id = $0.app.bundleID?.lowercased(),
                  ChannelBinding.boundBundleIDs.contains(id)
            else { return nil }
            return id
        }
    }

    /// Resolve each bound app's channel and fingerprint it. Network-free, but NOT
    /// free: `ChannelBinding.resolve` reads another app's preferences, and Surge's
    /// resolver reads a plist off disk with `Data(contentsOf:)`. Every other
    /// `AppScanner`/resolver call site in this file is wrapped in `Task.detached`
    /// for exactly that reason, and this one is called from an event that fires on
    /// every app launch and quit on the machine — so it is `nonisolated` and runs
    /// off the main actor like its neighbours, rather than being the one exception.
    private nonisolated static func fingerprints(forBoundIDs ids: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for id in ids {
            guard let resolved = ChannelBinding.resolve(bundleID: id) else { continue }
            out[id] = ChannelSwitchDetector.fingerprint(resolved)
        }
        return out
    }

    /// Re-check any `ChannelBinding` app (Tailscale, Fork, Surge, …) whose own
    /// channel toggle changed since we last looked — the fix for the bug where
    /// switching Tailscale's Settings from Unstable back to Stable left its row
    /// pinned to the old unstable target until the next scheduled check. The
    /// channel choice lives entirely in the vendor app's own private preference,
    /// so neither our FS watcher (it watches app *bundles*, not another app's
    /// prefs) nor a networked check re-derives it on its own — the row is
    /// otherwise stuck until the next scheduled check, up to an hour away.
    ///
    /// Resolves fresh and compares fingerprints (`ChannelSwitchDetector`) first —
    /// free, no network, no I/O beyond a handful of `CFPreferences`/plist reads —
    /// and only rechecks (a real scan + networked check, same path as
    /// `recheckAfterUnignore`/`retry`) the rows that actually flipped.
    ///
    /// Called from two sites, chosen after checking on this machine that a
    /// cross-process preference-change notification (`NSDistributedNotificationCenter`,
    /// the Darwin notify center) is not reliably delivered here — see the report
    /// alongside this change for the actual test and its output:
    /// `handleRunningAppsChange` (a bound app launching/quitting — the common
    /// "open Settings, flip the toggle, quit" flow) and `windowAppeared` (the
    /// user comes back to DuoUpdater itself — the "leave the vendor app running"
    /// flow). Coalesced against overlapping calls.
    private func recheckChannelSwitches(trigger: String) async {
        guard !results.isEmpty else { return }
        // Latest wins. A pass already on the network was started from a choice the
        // user has since left, so its verdict is not merely late — it is wrong, and
        // letting it finish would write the superseded track into the row. Cancel it
        // and start over rather than queueing behind it. Dropping the new trigger
        // instead (what the old `channelSwitchRecheckRunning` guard did) was worse
        // still: the flip was forgotten entirely, and because the fingerprints had
        // already been booked, nothing compared them again — a row kept offering a
        // prerelease to someone who had just opted out, for up to the watcher's
        // 900s re-arm. See issue #74.
        let previous = channelRecheckTask
        previous?.cancel()
        let task = Task { @MainActor [weak self] in
            // Cancelling only raises a flag. The superseded pass keeps running until
            // its `recheck` returns — `recheckMany` scans on a DETACHED task, which
            // cancellation cannot reach at all — and for that whole time it still
            // holds `installing[id] = .checking` on the rows it claimed. Starting the
            // new pass on top of that made it skip those very rows, because its claim
            // filter is `installing[id] == nil`: it rechecked nothing, the dying pass
            // rechecked nothing either, and the flip was acted on by neither. That is
            // issue #74 moved rather than fixed — two flips half a second apart, or
            // one flip plus any unrelated write to the machine-wide
            // `~/Library/Preferences` during the pass, were enough to hit it.
            //
            // So wait the old pass out. It happens HERE, inside the new task, so that
            // `channelRecheckTask` below is still assigned synchronously: a third
            // trigger then cancels this task and chains behind it, instead of two
            // triggers both getting past a suspension point and running at once.
            _ = await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.runChannelSwitchRecheck(trigger: trigger)
        }
        channelRecheckTask = task
        await task.value
    }

    /// One pass of the above, as a cancellable unit.
    ///
    /// Fingerprints are booked per id, only once that id's recheck has actually
    /// finished (`ChannelSwitchDetector.booked`). A pass cancelled partway leaves
    /// the ids it never reached looking changed, so the pass that superseded it
    /// picks them up instead of inheriting a cache that claims they were handled.
    private func runChannelSwitchRecheck(trigger: String) async {
        let ids = onScreenBoundBundleIDs()
        guard !ids.isEmpty else { return }
        let current = await Task.detached(priority: .utility) {
            Self.fingerprints(forBoundIDs: ids)
        }.value
        guard !Task.isCancelled else { return }
        let (changed, _) = ChannelSwitchDetector.changes(
            current: current, lastSeen: lastSeenChannelFingerprints)
        guard !changed.isEmpty else {
            // Nothing flipped, but still seed first sightings and prune ids that
            // dropped out of the scan — the bookkeeping `changes` would have done.
            lastSeenChannelFingerprints = ChannelSwitchDetector.booked(
                current: current, lastSeen: lastSeenChannelFingerprints,
                changed: [], completed: [])
            return
        }

        let targets = results.filter {
            guard let id = $0.app.bundleID?.lowercased() else { return false }
            return changed.contains(id)
        }
        // Mark every target busy BEFORE the first network call, not one at a time as
        // we reach it. The row's action button is replaced by the checking state, so
        // this is what stops a click landing on a verdict the flip has already
        // invalidated — the window between the toggle and the new answer is ~2.4s,
        // and only the marked part of it is safe.
        var claimed: [UpdateResult] = []
        for result in targets where installing[result.id] == nil {
            installing[result.id] = .checking
            claimed.append(result)
        }
        // Whatever happens below — finished, cancelled, or thrown out of — no row is
        // left wearing a spinner that nothing is driving any more. Narrowly, though:
        // a row leaves `outstanding` the moment its own recheck lands, and the sweep
        // only clears one still wearing the `.checking` THIS pass put on it. Between
        // one row's recheck finishing and the next one's network call returning the
        // user can press Update on the finished row, and a blind
        // `installing[id] = nil` here would strip the stage off that install.
        var outstanding = Set(claimed.map(\.id))
        defer {
            for id in outstanding where installing[id] == .checking { installing[id] = nil }
        }

        var completed = Set<String>()
        for result in claimed {
            guard !Task.isCancelled else { break }
            let updated = await recheck(result)
            // The second check is not redundant with the first, and it must stay: a
            // cancellation that lands *during* the await poisons the answer rather than
            // merely dating it. `UpdateChecker.check` cancels its in-flight source fetches
            // and still returns a result for each, so what comes back here is an `.error`
            // row — "we don't know whether this app has an update" — not the verdict for
            // the channel the user just chose. Booking that would replace a good row with
            // a red one. Drop it instead; the id stays unbooked, so the superseding pass
            // re-claims it.
            guard !Task.isCancelled else { break }
            installing[result.id] = nil
            outstanding.remove(result.id)
            replaceRow(updated)
            if let id = result.app.bundleID?.lowercased() { completed.insert(id) }
            Log.app.info(
                "channel switch re-check (\(trigger, privacy: .public)): \(updated.app.name, privacy: .public) → \(String(describing: updated.status), privacy: .public)")
        }
        lastSeenChannelFingerprints = ChannelSwitchDetector.booked(
            current: current, lastSeen: lastSeenChannelFingerprints,
            changed: changed, completed: completed)
        // Unconditionally, even when cancelled: rows were replaced above, so the badge is
        // now out of step with them. Skipping it here left nothing to correct it — the
        // superseding pass compares against the fingerprints just booked, finds nothing
        // changed, and returns through a branch that never syncs either, so the badge
        // kept its pre-switch count until the next scheduled check.
        syncDockBadge()
    }

    /// Re-run the update check for one app. Two affordances share this, and
    /// deliberately so — they ask the same question and must answer it the same
    /// way: the retry on an `.error` row (a transient GitHub rate-limit, say), and
    /// "Check Again" in the row's context menu, which is how a user asks about one
    /// app without paying for a whole sweep.
    ///
    /// It re-derives the running set first, so it also corrects a row whose
    /// *running* state has gone stale. `NSWorkspace`'s launch/terminate
    /// notifications are the only thing maintaining that set, and some apps never
    /// post one of them — measured: Alcove posts no `didLaunch`, UURemote no
    /// `didTerminate` (issue #247) — which leaves the dot lit for an app that has
    /// quit, or dark for one that is open. That recompute is whole-set and, since
    /// the resolutions are memoized, 0.095 ms; it happens before the network check
    /// rather than after, so the dot is right the moment the row starts checking
    /// instead of when the source answers.
    ///
    /// Reuses the install-stage spinner to show "Checking" on just that row, and
    /// bails if the row is already busy (installing or mid-recheck).
    func retry(_ result: UpdateResult) async {
        let id = result.id
        guard installing[id] == nil else { return }
        Log.app.info("retry: re-checking \(result.app.name, privacy: .public)")
        refreshRunningApps()
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
    ///
    /// …except while the order is frozen (see `pinRowOrder`), when every row the
    /// user can already see keeps the slot it had, whatever its rank has become.
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
            // Frozen: pinned rows hold their recorded slot, and anything that showed
            // up since the freeze goes after them (inserting into the middle would
            // push the pinned rows down, which is the thing being prevented).
            if !pinnedOrder.isEmpty {
                switch (pinnedOrder[a.id], pinnedOrder[b.id]) {
                case let (pa?, pb?): return pa < pb
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): break  // both new — fall through to the normal order
                }
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.app.name.localizedCaseInsensitiveCompare(b.app.name) == .orderedAscending
        }
    }

    // MARK: - Frozen row order
    //
    // The list re-sorts on every rank change, and a row's rank changes the moment
    // its install lands: it drops out of the pending tier, or picks up a Restart
    // badge and jumps to the top. Either way every row below it shifts by one —
    // under the pointer of someone who is working down the list clicking Update,
    // which is how you end up updating the app you did not mean to. A single
    // install fires that re-sort three times over (`replaceRow`,
    // `computeRestartInfo`, `computeSelfUpdateStaging`), and the mid-install
    // rescan that clears externally-updated apps can fire it at any moment on top.
    //
    // So while the user is acting on the list, freeze it: whatever happens to a
    // row's rank, it stays where they last saw it, finishing in place with its
    // "Installed ✓". When the round is over — nothing installing, queued,
    // relaunching, or holding its confirmation — the freeze lifts and the list
    // re-sorts *once*, which is when the finished rows drop to the bottom tier and
    // filter out as they always have. One reflow at the end instead of one per app.

    /// Row id → the slot it occupied when the order was frozen.
    @ObservationIgnored private var pinnedOrder: [String: Int] = [:]

    /// Freeze the current order, if it isn't already. Called wherever work starts
    /// on a row (install, restart, staged relaunch) — the first one freezes and the
    /// rest ride along, so a batch or a run of clicks shares one snapshot.
    private func pinRowOrder() {
        guard pinnedOrder.isEmpty else { return }
        // `uniquingKeysWith:`, not `uniqueKeysWithValues:` — matching how this file
        // builds every other id-keyed map. Duplicate ids should be impossible (the
        // scanner dedupes on resolved path), but a freeze is a cosmetic nicety and
        // must never be the thing that traps.
        pinnedOrder = Dictionary(
            results.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first })
        // A freeze that failed to lift looks exactly like a freeze that never
        // engaged — from outside, both are "the list stopped re-sorting". Say when
        // it starts and when it ends, for the same reason `refreshLocal` says why it
        // skipped: without it, the two are indistinguishable in a live-log session.
        Log.app.debug("row order: frozen (\(self.pinnedOrder.count, privacy: .public) rows)")
    }

    /// Lift the freeze and re-sort once — but only when nothing is left in flight.
    /// Safe to call from every settle point; it no-ops until the last one.
    private func releaseRowOrder() {
        guard !pinnedOrder.isEmpty else { return }
        guard installing.isEmpty, !isInstallingAll, relaunching.isEmpty, justUpdated.isEmpty
        else {
            let holding = !installing.isEmpty ? "installing (\(installing.count))"
                : isInstallingAll ? "batch install"
                : !relaunching.isEmpty ? "relaunching (\(relaunching.count))"
                : "just-updated confirmation"
            Log.app.debug("row order: still frozen — \(holding, privacy: .public)")
            return
        }
        pinnedOrder = [:]
        results = sorted(results)
        Log.app.debug("row order: released — re-sorted")
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
