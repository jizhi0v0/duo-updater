import Foundation
import Testing
@testable import DuoUpdaterCore

/// The badge's two rules, which lived in `AppListModel` where nothing executed
/// them. Two tests in this very suite already referred to
/// `AppListModel.needsAction` in prose — Core documenting a rule it could not
/// run — which is what prompted moving them here rather than testing them
/// through the App target.
///
/// Each case names the single-line mutation it must fail under.
struct NeedsActionTests {

    private func app(_ short: String, ignoredMarker: String = "app") -> InstalledApp {
        InstalledApp(
            name: ignoredMarker, bundleID: "com.example.\(ignoredMarker)",
            shortVersion: short, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/\(ignoredMarker).app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    private func row(
        installed: String = "1.0", latest: String? = "2.0"
    ) -> UpdateResult {
        guard let latest else {
            return UpdateResult(app: app(installed), remote: nil, status: .upToDate)
        }
        return UpdateResult(
            app: app(installed),
            remote: RemoteVersion(
                shortVersion: latest, version: nil, downloadURL: nil, sourceName: "GitHub"),
            status: .updateAvailable(latest: latest))
    }

    private func stagedBuild(_ version: String) -> StagedSelfUpdate {
        StagedSelfUpdate(
            version: version, buildVersion: nil,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/staged.app"))
    }

    private func needsAction(
        _ result: UpdateResult,
        ignored: Bool = false,
        skipped: Bool = false,
        needsRestart: Bool = false,
        batchRestart: Bool = false,
        staged: StagedSelfUpdate? = nil
    ) -> Bool {
        UpdatePolicy.needsAction(
            result, isIgnored: ignored, isVersionSkipped: { _ in skipped },
            needsRestart: needsRestart, hasPendingBatchRestart: batchRestart,
            staged: staged)
    }

    // MARK: what counts

    /// Mutation: `guard result.hasUpdate else { return false }` deleted from
    /// `isActionableUpdate`.
    @Test func anOfferableUpdateCounts() {
        #expect(needsAction(row()))
        #expect(!needsAction(row(latest: nil)))
    }

    /// Ignoring an app takes it off the badge even though the update is real.
    ///
    /// Mutation: drop `if isIgnored { return false }` from `isActionableUpdate`
    /// — the outer `guard !isIgnored` does NOT cover this, because the update
    /// returns true on the line above it.
    @Test func anIgnoredAppWithAnUpdateDoesNotCount() {
        #expect(!needsAction(row(), ignored: true))
    }

    /// Mutation: drop the `isVersionSkipped` check from `isActionableUpdate`.
    @Test func askippedVersionDoesNotCount() {
        #expect(!needsAction(row(), skipped: true))
    }

    /// The reason the badge counts more than updates: a row whose update is
    /// already on disk and only needs a relaunch. Counting updates alone put the
    /// menu bar at "no updates" above a list of Relaunch buttons.
    ///
    /// Mutation: drop the `needsRestart` term.
    @Test func aRowWaitingOnlyForARelaunchCounts() {
        #expect(needsAction(row(latest: nil), needsRestart: true))
    }

    /// Mutation: drop the `hasPendingBatchRestart` term.
    @Test func aRowHeldForABatchRelaunchCounts() {
        #expect(needsAction(row(latest: nil), batchRestart: true))
    }

    /// Both relaunch terms are gated on the app not being hidden — this is what
    /// the outer `guard !isIgnored` actually protects, and it is reachable only
    /// for a row with no offerable update.
    ///
    /// Mutation: delete `guard !isIgnored else { return false }`.
    @Test func hidingAnAppAlsoSuppressesItsRelaunchTerms() {
        #expect(!needsAction(row(latest: nil), ignored: true, needsRestart: true))
        #expect(!needsAction(row(latest: nil), ignored: true, batchRestart: true))
    }

    // MARK: the staged self-update term

    /// A staged build newer than what is installed counts, so the badge stays lit
    /// for an update that is downloaded but not yet live.
    ///
    /// Mutation: drop the `staged` term.
    @Test func aStagedNewerBuildCounts() {
        #expect(needsAction(row(latest: nil), staged: stagedBuild("2.0")))
    }

    /// A staged build that is NOT ahead of the installed copy would apply a
    /// downgrade, so it must not light the badge.
    ///
    /// Mutation: `nudgeableStaged(...) != nil` replaced by `staged != nil`.
    @Test func aStagedBuildThatIsNotAheadDoesNotCount() {
        #expect(!needsAction(row(installed: "2.0", latest: nil), staged: stagedBuild("1.0")))
    }

    /// Skipping the version silences a staged build too. This is the ONLY reason
    /// the term goes through `nudgeableStaged` rather than the cheaper
    /// `actionableStaged`, which applies the newer-than-installed gate but not
    /// the user's skip — so without this case, swapping one for the other leaves
    /// every other case green while a hidden version keeps lighting the badge.
    ///
    /// Mutation: `nudgeableStaged(…)` replaced by
    /// `actionableStaged(result, staged: staged)`.
    @Test func askippedVersionSilencesAStagedBuildToo() {
        #expect(!needsAction(row(latest: nil), skipped: true, staged: stagedBuild("2.0")))
        // The same row without the skip does count — otherwise the assertion
        // above would hold for the wrong reason.
        #expect(needsAction(row(latest: nil), skipped: false, staged: stagedBuild("2.0")))
    }

    /// Which version is offered to the skip check: the REMOTE side, not the
    /// installed one. Reading the installed side would silence the app
    /// permanently after a single skip — the failure `VersionSide` exists to
    /// prevent.
    ///
    /// Mutation: `isVersionSkipped(result.app.versionSide)` in
    /// `isActionableUpdate`.
    @Test func theSkipCheckIsAskedAboutTheRemoteVersion() {
        var seen: [VersionSide?] = []
        _ = UpdatePolicy.isActionableUpdate(
            row(installed: "1.0", latest: "2.0"), isIgnored: false,
            isVersionSkipped: { seen.append($0); return false })

        #expect(seen.count == 1)
        #expect(seen.first??.marketing == "2.0")
    }

    /// Nothing staged means nothing to count. Deliberately NOT a test of the
    /// `staged != nil` short-circuit that precedes the `nudgeableStaged` call:
    /// that check is behaviour-neutral (see the note on `needsAction`), so no
    /// assertion can distinguish it, and the first version of this case pretended
    /// otherwise by counting preference reads — of which there are none either
    /// way. Mutation-checked: removing the short-circuit leaves every case here
    /// green, and that is correct rather than a gap.
    @Test func nothingStagedCountsForNothing() {
        #expect(!needsAction(row(latest: nil), staged: nil))
    }
}

/// The badge's hold-during-refresh rule.
struct BadgeReadoutTests {

    /// A settled list tracks the live count, so ignoring or skipping an app
    /// changes the badge at once.
    @Test func aSettledListShowsTheLiveCount() {
        #expect(BadgeReadout.count(live: 3, held: 99, isScanning: false, isChecking: false) == 3)
    }

    /// A refresh blanks every row before the check repopulates it, so the live
    /// count dips to 0 mid-pass — which flickered the badge to the "no updates"
    /// icon and back.
    ///
    /// Mutations: drop `isScanning` from the condition; drop `isChecking`. Both
    /// halves are separately asserted because a refresh passes through scanning
    /// and checking as two phases.
    @Test func aPassInFlightHoldsTheLastSettledCount() {
        #expect(BadgeReadout.count(live: 0, held: 3, isScanning: true, isChecking: false) == 3)
        #expect(BadgeReadout.count(live: 0, held: 3, isScanning: false, isChecking: true) == 3)
    }
}

/// Filling `RowActionFacts` from the UI layer's tables — the wiring that used to
/// sit in `AppListModel`.
///
/// The decision it feeds (`RowAction.state`) has its own suite. What is pinned
/// here is which table answers which fact, and under which key, because that is
/// the half that fails by looking right.
struct RowFactsAssemblyTests {

    private static let path = "/Applications/Example.app"

    private var row: UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "Example", bundleID: "com.example.app",
                shortVersion: "1.0", buildVersion: nil,
                path: URL(fileURLWithPath: Self.path),
                isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil),
            remote: nil, status: .upToDate)
    }

    private func facts(
        _ tables: RowStateTables, route: @escaping @autoclosure () -> UpdateRoute = .autoInstall
    ) -> RowActionFacts {
        RowActionFacts.assemble(
            for: row, tables: tables, isIgnored: false, isVersionSkipped: false,
            route: route())
    }

    /// Each table populated ALONE, asserting the one fact it owns is set and its
    /// neighbours are not. This is the shape that catches a fact fed from the
    /// table next to it — the failure this extraction exists for — which an
    /// assertion per fact over a fully-populated fixture would not.
    ///
    /// Mutation: swap any two table reads in `assemble`, e.g.
    /// `justUpdated: tables.needsRestart.contains(result.id)`.
    @Test func eachTableAnswersOnlyItsOwnFact() {
        let id = Self.path

        let relaunching = facts(RowStateTables(relaunching: [id]))
        #expect(relaunching.isRelaunching)
        #expect(!relaunching.justUpdated && !relaunching.needsRestart)
        #expect(relaunching.awaitingQuitConfirm == nil && relaunching.installStage == nil)

        let restart = facts(RowStateTables(needsRestart: [id]))
        #expect(restart.needsRestart)
        #expect(!restart.isRelaunching && !restart.justUpdated)

        let updated = facts(RowStateTables(justUpdated: [id]))
        #expect(updated.justUpdated)
        #expect(!updated.needsRestart && !updated.isRelaunching)

        let batch = facts(RowStateTables(pendingBatchRestart: [id: "2.0"]))
        #expect(batch.hasPendingBatchRestart)
        #expect(batch.awaitingQuitConfirm == nil)

        let quit = facts(RowStateTables(awaitingQuitConfirm: [id: "Example"]))
        #expect(quit.awaitingQuitConfirm == "Example")
        #expect(!quit.hasPendingBatchRestart)

        let installing = facts(RowStateTables(installing: [id: .queued]))
        #expect(installing.installStage == .queued)
        #expect(!installing.isRelaunching)
    }

    /// The tables are keyed by install PATH, not bundle id: two copies of one app
    /// share a bundle id, and must not share a row's install stage or relaunch
    /// flag. A lookup-key mix-up is a defect shape this repo has already shipped
    /// once (`computeRestartInfo`'s key, #242).
    ///
    /// Mutation: `tables.installing[result.app.bundleID ?? ""]`, or
    /// `.contains(result.app.bundleID ?? "")`. The `?? ""` is needed to make the
    /// mutation compile at all — `bundleID` is `String?`, so the naive form is a
    /// type error, and the type system is already half of this guard. The half it
    /// does not cover is someone reaching for `?? ""` to silence it.
    @Test func theTablesAreKeyedByInstallPathNotBundleID() {
        let byBundleID = RowStateTables(
            installing: ["com.example.app": .queued],
            needsRestart: ["com.example.app"],
            relaunching: ["com.example.app"],
            justUpdated: ["com.example.app"])
        let f = facts(byBundleID)

        #expect(f.installStage == nil)
        #expect(!f.needsRestart && !f.isRelaunching && !f.justUpdated)
    }

    /// The five facts that come from somewhere other than a table. The fixture
    /// used by every other case here is all-false and all-nil, so a transposition
    /// among them is invisible: `isIgnored: isVersionSkipped` renders a skipped
    /// row as Ignored (`RowAction.state` ranks ignored first), and the three
    /// source hints feed the `.unknown`/`.upToDate` rungs' badges.
    ///
    /// Same fixture-distribution trap CLAUDE.md records twice for the gallery —
    /// a fixture that is constant across a set of branches measures one branch
    /// and reports on all of them.
    ///
    /// Mutations: transpose `isIgnored` with `isVersionSkipped`; feed any one of
    /// the three hints from either of the other two.
    @Test func theNonTableFactsEachComeFromTheirOwnSource() {
        let ignored = RowActionFacts.assemble(
            for: row, tables: RowStateTables(), isIgnored: true,
            isVersionSkipped: false, route: .autoInstall)
        #expect(ignored.isIgnored && !ignored.isVersionSkipped)

        let skipped = RowActionFacts.assemble(
            for: row, tables: RowStateTables(), isIgnored: false,
            isVersionSkipped: true, route: .autoInstall)
        #expect(skipped.isVersionSkipped && !skipped.isIgnored)

        for (label, app) in [
            ("mas", hinted(isMASApp: true)),
            ("testflight", hinted(isTestFlightApp: true)),
            ("sparkle", hinted(sparkle: URL(string: "https://example.com/appcast.xml"))),
        ] {
            let f = RowActionFacts.assemble(
                for: UpdateResult(app: app, remote: nil, status: .upToDate),
                tables: RowStateTables(), isIgnored: false, isVersionSkipped: false,
                route: .autoInstall)
            let hits = [f.isMASApp, f.isTestFlightApp, f.hasSparkleFeed].filter { $0 }.count
            #expect(hits == 1, "\(label) set \(hits) hints")
            switch label {
            case "mas": #expect(f.isMASApp)
            case "testflight": #expect(f.isTestFlightApp)
            default: #expect(f.hasSparkleFeed)
            }
        }
    }

    private func hinted(
        isMASApp: Bool = false, isTestFlightApp: Bool = false, sparkle: URL? = nil
    ) -> InstalledApp {
        InstalledApp(
            name: "Example", bundleID: "com.example.app",
            shortVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: Self.path),
            isMASApp: isMASApp, isToolboxManaged: false,
            isTestFlightApp: isTestFlightApp, sparkleFeedURL: sparkle)
    }

    /// A staged build not ahead of what is installed is not a relaunch target —
    /// the target goes through `UpdatePolicy.actionableStaged`, not straight off
    /// the table.
    ///
    /// Mutation: `stagedRelaunchTarget` taken from
    /// `tables.pendingSelfUpdate[result.id]` directly.
    @Test func theRelaunchTargetGoesThroughTheStagedPolicy() {
        let behind = StagedSelfUpdate(
            version: "0.9", buildVersion: nil,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/staged.app"))
        #expect(facts(RowStateTables(pendingSelfUpdate: [Self.path: behind]))
            .stagedRelaunchTarget == nil)

        let ahead = StagedSelfUpdate(
            version: "2.0", buildVersion: nil,
            stagedBundlePath: URL(fileURLWithPath: "/tmp/staged.app"))
        #expect(facts(RowStateTables(pendingSelfUpdate: [Self.path: ahead]))
            .stagedRelaunchTarget != nil)
    }

    /// `assemble` must not evaluate the route. Computing it rebuilds an
    /// `InstallEnvironment` and stats the disk for pkg rows, and only the
    /// `.updateAvailable` rung ever reads it — the cost this `@autoclosure`
    /// exists to avoid for every installing, ignored or quit-confirming row.
    ///
    /// Mutation: change `route` to a plain (non-autoclosure) parameter, or store
    /// `route()` into a local inside `assemble`.
    @Test func assemblingFactsDoesNotComputeTheRoute() {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()

        let facts = RowActionFacts.assemble(
            for: row, tables: RowStateTables(), isIgnored: false,
            isVersionSkipped: false,
            route: { counter.calls += 1; return UpdateRoute.majorUpgrade }())

        #expect(counter.calls == 0)

        // Deferred is only half of it: `RowActionFacts.route` has a DEFAULT, so
        // dropping the argument from `assemble` altogether compiles and leaves a
        // deferral-only assertion green — while every `.updateAvailable` row in
        // production renders whatever that default happens to be. Read it once
        // and check the value arrived. (`routeIsDeferred` in RowActionStateTests
        // carries the same positive pole for the same reason.)
        #expect(facts.route() == .majorUpgrade)
        #expect(counter.calls == 1)
    }
}
