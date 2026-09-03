import Testing
@testable import DuoUpdaterCore

/// One ladder, rendered by both the popover and the workbench. These tests are the
/// specification: what a row asks of the user in each state, and — the point of the
/// type — which condition wins when several are true at once.
@Suite("RowActionState")
struct RowActionStateTests {

    // MARK: - Precedence, which is the entire content of the ladder

    /// The divergence that motivated this. An App Store install waiting for the
    /// user to quit the app has BOTH a quit prompt and an install stage. The
    /// popover showed the prompt, the workbench showed a progress bar — same row,
    /// two windows, two different things.
    @Test("a quit prompt outranks the install stage it belongs to")
    func quitConfirmBeatsStage() {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            awaitingQuitConfirm: "Things",
            installStage: .installing))
        #expect(state == .awaitingQuitConfirm("Things"))
    }

    /// A relaunch in flight outranks everything below it: the row must not offer a
    /// second action while a swap is happening.
    @Test("relaunching outranks a pending update")
    func relaunchingBeatsUpdate() {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            isRelaunching: true))
        #expect(state == .relaunching)
        #expect(state.offersUpdate == false)
    }

    /// An install of ours outranks the update it is installing — otherwise the row
    /// would offer Update again mid-download and take a second click.
    @Test("an install in flight outranks the update it is applying")
    func stageBeatsUpdate() {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            installStage: .downloading(fraction: 0.4)))
        #expect(state == .installing(.downloading(fraction: 0.4)))
        #expect(state.offersUpdate == false)
    }

    /// The user's own verdicts outrank the update they are about. An ignored app
    /// must never grow an Update button, whatever the check found.
    @Test("the user's verdict outranks the update", arguments: [
        (true, false, RowActionState.ignored),
        (false, true, RowActionState.versionSkipped),
    ])
    func userVerdictWins(ignored: Bool, skipped: Bool, expected: RowActionState) {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            isIgnored: ignored,
            isVersionSkipped: skipped))
        #expect(state == expected)
        #expect(state.offersUpdate == false)
    }

    /// Mutation guard for the `hasUpdate &&` half of the skip rung. Every case in
    /// `userVerdictWins` carries an update, so that conjunct is unreachable there —
    /// delete it and the whole suite still passes. A skip is a verdict ABOUT a
    /// specific version: once the row no longer has that update to offer, the skip
    /// has nothing left to suppress and must stop speaking, or a current app reads
    /// as "Skipped" forever.
    @Test("a skip with no update left to skip says nothing")
    func skipNeedsAnUpdateToSuppress() {
        #expect(RowAction.state(for: RowActionFacts(status: .upToDate, isVersionSkipped: true))
                == .upToDate(channel: .none))
        // Ignored is NOT conditioned the same way on purpose: ignoring is a verdict
        // about the app, not about a version, so it still speaks when nothing is
        // pending. Pinned here so the asymmetry is deliberate rather than a typo.
        #expect(RowAction.state(for: RowActionFacts(status: .upToDate, isIgnored: true))
                == .ignored)
    }

    /// The four "something is already happening to this row" rungs, pinned pairwise
    /// against the rung directly below. Each `#expect` fails if that rung is moved
    /// down one place, which a single all-flags-true case would not catch.
    @Test("the in-flight rungs keep their order")
    func inFlightPrecedence() {
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            awaitingQuitConfirm: "Pages",
            isRelaunching: true)) == .awaitingQuitConfirm("Pages"))
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            isRelaunching: true,
            hasPendingBatchRestart: true)) == .relaunching)
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            hasPendingBatchRestart: true,
            justUpdated: true)) == .pendingBatchRestart)
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            justUpdated: true,
            installStage: .installing)) == .justUpdated)
        // An install in flight outranks the user's ignore: the bytes are already
        // moving, and showing "Ignored" over a running install would describe the
        // row as idle while a progress bar is the truth.
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            installStage: .installing,
            isIgnored: true)) == .installing(.installing))
    }

    /// The three rungs between the user's verdicts and the relaunch pair, which
    /// `inFlightPrecedence` stops short of. The ignore-over-relaunch one is not
    /// cosmetic: `AppListModel.needsAction` gates its relaunch terms on
    /// `!prefs.isIgnored` and its doc cites THIS order as the reason. Reverse it and
    /// the badge counts a row the list renders as "Ignored", so the badge lights
    /// with nothing on the other end of the click — and every other test stays green.
    @Test("the verdict rungs outrank the relaunch rungs")
    func verdictPrecedence() {
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            isIgnored: true,
            isVersionSkipped: true)) == .ignored)
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            isIgnored: true,
            stagedRelaunchTarget: "2.0")) == .ignored)
        #expect(RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            isVersionSkipped: true,
            stagedRelaunchTarget: "2.0")) == .versionSkipped)
        // A staged build is a specific thing already on disk; a bare restart is not.
        #expect(RowAction.state(for: RowActionFacts(
            status: .unknown,
            stagedRelaunchTarget: "2.0",
            needsRestart: true)) == .relaunchToApplyStaged(to: "2.0"))
    }

    /// The route must stay unevaluated for rows that never reach the
    /// `.updateAvailable` rung. Resolving it is the expensive half of assembling
    /// the facts — the caller rebuilds an install environment several times and can
    /// stat the disk — and it runs per row on every repaint, so an eager argument
    /// costs that on rows showing a progress bar. Deleting `@autoclosure` from
    /// `RowActionFacts.init` makes this fail and nothing else.
    @Test("the route is not resolved for a row that cannot use it")
    func routeIsDeferred() {
        final class Counter: @unchecked Sendable { var n = 0 }
        let calls = Counter()
        _ = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            installStage: .installing,
            route: { calls.n += 1; return .autoInstall }()))
        #expect(calls.n == 0)

        _ = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            isIgnored: true,
            route: { calls.n += 1; return .autoInstall }()))
        #expect(calls.n == 0)

        // ...and it IS resolved when the row actually offers an update, so the
        // deferral cannot be "never called".
        _ = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            route: { calls.n += 1; return .autoInstall }()))
        #expect(calls.n == 1)
    }

    /// A staged build the app already downloaded outranks our own Update:
    /// re-downloading the same bytes would collide with the pending swap.
    @Test("an already-staged build outranks downloading it again")
    func stagedBeatsUpdate() {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"),
            stagedRelaunchTarget: "2.0"))
        #expect(state == .relaunchToApplyStaged(to: "2.0"))
    }

    /// Restart is answered before the status switch so it stays steady across a
    /// refresh's transient `.unknown`, and only when there is nothing newer to
    /// install — a row with an update shows Update instead.
    @Test("restart is answered outside the status switch")
    func restartIsSteadyAcrossTransientStatus() {
        #expect(RowAction.state(for: RowActionFacts(status: .unknown, needsRestart: true))
                == .restartToApply)
        #expect(RowAction.state(for: RowActionFacts(status: .updateAvailable(latest: "2"), needsRestart: true))
                == .updateAvailable(.autoInstall))
    }

    // MARK: - The failure states, which the workbench used to render as blank

    /// A failed check is not "nothing to do". It carries its reason and is
    /// retryable, and every surface must say so rather than going quiet.
    @Test("a failed check explains itself and is not silent")
    func checkFailureIsExplained() {
        let state = RowAction.state(for: RowActionFacts(status: .error("The request timed out.")))
        #expect(state == .checkFailed(message: "The request timed out.", rateLimited: false))
        #expect(state.needsExplanation)
        #expect(state.offersUpdate == false)

        // The rate limit is classified HERE, once, because both surfaces label it
        // differently ("Rate-limited" vs "Failed") and neither may re-derive it
        // from `UpdateStatus` — a second opinion is how the two drifted apart.
        let limited = RowAction.state(for: RowActionFacts(
            status: .error("GitHub API rate limit exceeded — add a token in Settings.")))
        #expect(limited == .checkFailed(
            message: "GitHub API rate limit exceeded — add a token in Settings.",
            rateLimited: true))
    }

    /// "Nothing covers this app" and "a source failed" are different answers and
    /// stay different — only one is worth retrying.
    @Test("no covering source is distinct from a failure")
    func unknownIsNotFailure() {
        let state = RowAction.state(for: RowActionFacts(status: .unknown))
        #expect(state == .noSourceCovers(hint: .none))
        #expect(state != .checkFailed(message: "", rateLimited: false))
        #expect(state.needsExplanation)
    }

    @Test("managed apps name their manager", arguments: [
        (UpdateStatus.appStoreManaged, RowActionState.Manager.appStore),
        (.toolboxManaged, .toolbox),
        (.testFlightManaged, .testFlight),
    ])
    func managedNamesItsManager(status: UpdateStatus, manager: RowActionState.Manager) {
        #expect(RowAction.state(for: RowActionFacts(status: status)) == .managedElsewhere(manager))
    }

    /// The invariant both surfaces are held to: no state may render as blank. A
    /// row that is quiet must be quiet because it is `upToDate`, not because the
    /// surface had no branch for what it actually is.
    @Test("only an up-to-date row is silent", arguments: [
        UpdateStatus.error("boom"), .unknown, .appStoreManaged, .toolboxManaged,
        .testFlightManaged, .updateAvailable(latest: "2.0"), .upToDate,
    ])
    func onlyUpToDateIsSilent(_ status: UpdateStatus) {
        let state = RowAction.state(for: RowActionFacts(status: status))
        if state == .upToDate(channel: .none) {
            #expect(state.needsExplanation == false)
        } else {
            #expect(state.needsExplanation || state.offersUpdate || state == .managedElsewhere(.appStore)
                    || state == .managedElsewhere(.toolbox) || state == .managedElsewhere(.testFlight),
                    "\(state) would render as blank")
        }
    }

    // MARK: - Which routes actually install

    /// The rule the two windows must agree on exactly: pressing the control starts
    /// an install we perform, or it does not. A window offering Update while the
    /// other does not, for the same row, is the bug this makes impossible.
    @Test("only routes we apply ourselves offer Update", arguments: [
        (UpdateRoute.autoInstall, true),
        (.installer(stagedFileName: nil), true),
        (.installer(stagedFileName: "Foo.pkg"), true),
        (.toolbox, false),
        (.testFlight, false),
        (.selfUpdater, false),
        (.majorUpgrade, false),
        (.appStore(managedHere: false, gate: .none), false),
        (.appStore(managedHere: true, gate: .none), false),
        (.detectionOnly, false),
    ])
    func onlyOurRoutesInstall(route: UpdateRoute, installs: Bool) {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"), route: route))
        #expect(state.offersUpdate == installs)
    }

    /// A route we cannot one-click still has to say something — that is what made
    /// the workbench's blank rows wrong.
    @Test("a non-installable route still explains itself", arguments: [
        UpdateRoute.toolbox, .testFlight, .selfUpdater, .majorUpgrade,
        .appStore(managedHere: false, gate: .none), .detectionOnly,
    ])
    func nonInstallableRoutesExplain(_ route: UpdateRoute) {
        let state = RowAction.state(for: RowActionFacts(
            status: .updateAvailable(latest: "2.0"), route: route))
        #expect(state.needsExplanation)
    }

    @Test("a quiet row is up to date")
    func upToDateIsQuiet() {
        let state = RowAction.state(for: RowActionFacts(status: .upToDate))
        #expect(state == .upToDate(channel: .none))
        #expect(state.needsExplanation == false)
        #expect(state.offersUpdate == false)
    }

    // MARK: - The two opinions moved out of the views (issue #260)

    /// Same priority the popover's `.upToDate` branch used to apply itself:
    /// `isMASApp` beats `isTestFlightApp`. A store-managed app that also happens
    /// to be TestFlight-flagged (shouldn't normally happen, but nothing enforced
    /// it) keeps naming the App Store.
    @Test("a current row's channel: App Store beats TestFlight beats neither")
    func upToDateChannelPriority() {
        #expect(RowAction.state(for: RowActionFacts(status: .upToDate, isMASApp: true))
                == .upToDate(channel: .appStore))
        #expect(RowAction.state(for: RowActionFacts(status: .upToDate, isTestFlightApp: true))
                == .upToDate(channel: .testFlight))
        #expect(RowAction.state(for: RowActionFacts(
            status: .upToDate, isMASApp: true, isTestFlightApp: true))
                == .upToDate(channel: .appStore))
        #expect(RowAction.state(for: RowActionFacts(status: .upToDate))
                == .upToDate(channel: .none))
    }

    /// Same priority `sourceHint(for:)` used to apply itself: App Store beats
    /// Sparkle beats a bare em dash.
    @Test("a source hint: App Store beats Sparkle beats none")
    func noSourceCoversHintPriority() {
        #expect(RowAction.state(for: RowActionFacts(status: .unknown, isMASApp: true))
                == .noSourceCovers(hint: .appStore))
        #expect(RowAction.state(for: RowActionFacts(status: .unknown, hasSparkleFeed: true))
                == .noSourceCovers(hint: .sparkle))
        #expect(RowAction.state(for: RowActionFacts(
            status: .unknown, isMASApp: true, hasSparkleFeed: true))
                == .noSourceCovers(hint: .appStore))
        #expect(RowAction.state(for: RowActionFacts(status: .unknown))
                == .noSourceCovers(hint: .none))
    }
}
