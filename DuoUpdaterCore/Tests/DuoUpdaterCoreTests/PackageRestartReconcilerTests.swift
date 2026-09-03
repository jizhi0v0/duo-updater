import Foundation
import Testing
@testable import DuoUpdaterCore

/// The reconciliation pass that decides which landed packages still need a
/// relaunch. It lived in `AppListModel`, where nothing executed it, and its
/// rules are one-liners whose wrong version is a user-visible defect: a badge
/// that drops on a blind pass, a badge that flickers off mid-swap, a landing
/// that announces itself twice.
///
/// Each case names the single-line mutation it must fail under.
struct PackageRestartReconcilerTests {

    private static let path = "/Applications/Example.app"
    private static let stagedAt = Date(timeIntervalSince1970: 1_000)

    private func app(_ short: String, build: String? = nil) -> InstalledApp {
        InstalledApp(
            name: "Example", bundleID: "com.example.app",
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: Self.path),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    private func staged(_ short: String, build: String? = nil) -> StagedPackageFacts {
        StagedPackageFacts(
            versionSide: VersionSide(marketing: short, build: build),
            stagedAt: Self.stagedAt)
    }

    /// A copy launched BEFORE the package was staged is the stale one.
    private static let staleLaunch = [Date(timeIntervalSince1970: 500)]
    /// A copy launched after it has already picked up the new code.
    private static let freshLaunch = [Date(timeIntervalSince1970: 2_000)]

    private func reconcile(
        staged stagedMap: [String: StagedPackageFacts],
        onDisk: [String: InstalledApp],
        launches: [Date] = [],
        pending: Set<String> = [],
        notified: Set<String> = []
    ) -> PackageRestartReconciliation {
        PackageRestartReconciler.reconcile(
            staged: stagedMap, onDisk: onDisk,
            launchDates: launches.isEmpty ? [:] : [Self.path: launches],
            previouslyPending: pending, previouslyNotified: notified)
    }

    // MARK: the three states

    /// Landed, and a copy that predates the hand-off is still running: light the
    /// badge and announce it.
    @Test func aLandedPackageWithAStaleCopyRunningIsReadyToRestart() {
        let out = reconcile(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("2.0")],
            launches: Self.staleLaunch)

        #expect(out.pending == [Self.path])
        #expect(out.toNotify == [Self.path])
        #expect(out.settled.isEmpty)
    }

    /// Landed with nothing stale running — never opened, or already relaunched.
    /// The staged entry is dropped and no badge is lit.
    @Test func aLandedPackageWithNothingStaleRunningSettles() {
        let out = reconcile(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("2.0")],
            launches: Self.freshLaunch)

        #expect(out.settled == [Self.path])
        #expect(out.pending.isEmpty)
        #expect(out.toNotify.isEmpty)
    }

    /// Not landed yet — the disk still reads the old version — and no badge was
    /// lit before, so none is lit now.
    @Test func aPackageThatHasNotLandedLightsNothing() {
        let out = reconcile(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("1.0")],
            launches: Self.staleLaunch)

        #expect(out.pending.isEmpty)
        #expect(out.settled.isEmpty)
        #expect(out.toNotify.isEmpty)
    }

    // MARK: the two carry-forward rules

    /// A pass that cannot see the bundle decides NOTHING. A bundle is briefly
    /// unreadable while Installer swaps it, and one missed scan must not drop
    /// the badge or let the staged entry be reclaimed.
    ///
    /// Mutation: delete `if previouslyPending.contains(id) { pending.insert(id) }`
    /// from the `onDisk[id] == nil` branch.
    @Test func aBlindPassCarriesAnAlreadyLitBadgeAndSettlesNothing() {
        let out = reconcile(
            staged: [Self.path: staged("2.0")], onDisk: [:], pending: [Self.path])

        #expect(out.pending == [Self.path])
        #expect(out.settled.isEmpty, "a pass that cannot see the app must not reclaim it")
    }

    /// …but a blind pass does not INVENT a badge either.
    ///
    /// Mutation: `pending.insert(id)` unconditionally in that branch.
    @Test func aBlindPassDoesNotLightABadgeThatWasNotLit() {
        let out = reconcile(staged: [Self.path: staged("2.0")], onDisk: [:])

        #expect(out.pending.isEmpty)
    }

    /// A momentary old read mid-swap — a partial `package.json` — must not
    /// flicker a lit badge off, because the next good pass would re-announce it.
    ///
    /// Mutation: delete `if previouslyPending.contains(id) { pending.insert(id) }`
    /// from the `.pending` branch.
    @Test func anAlreadyLitBadgeSurvivesAMomentaryOldRead() {
        let out = reconcile(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("1.0")],
            launches: Self.staleLaunch,
            pending: [Self.path])

        #expect(out.pending == [Self.path])
        #expect(out.toNotify.isEmpty, "carrying a badge is not announcing it again")
    }

    // MARK: the notify-once guard

    /// Announced once, not once per pass.
    ///
    /// Mutation: `toNotify.append(id)` unconditionally instead of behind
    /// `notified.insert(id).inserted`.
    @Test func aLandingIsAnnouncedOnlyOnce() {
        let first = reconcile(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("2.0")],
            launches: Self.staleLaunch)
        #expect(first.toNotify == [Self.path])

        let second = reconcile(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("2.0")],
            launches: Self.staleLaunch,
            pending: first.pending, notified: first.notified)
        #expect(second.toNotify.isEmpty)
        #expect(second.pending == [Self.path], "still lit, just not re-announced")
    }

    /// The guard is released only when the restart genuinely resolves — never
    /// because the id merely fell out of `pending` for one pass. This is what
    /// stops the same landing announcing itself again.
    ///
    /// Mutation: `notified.formIntersection(Set(staged.keys))` without
    /// `.subtracting(settled)`, or intersecting with `pending` instead.
    @Test func theGuardIsReleasedOnlyWhenTheRestartResolves() {
        // Fell out of pending for a pass (a blind pass), staged entry still
        // there: the guard must be KEPT, or the next good pass re-announces.
        let blind = reconcile(
            staged: [Self.path: staged("2.0")], onDisk: [:], notified: [Self.path])
        #expect(blind.notified == [Self.path])

        // Actually settled: the guard goes, so a future staging of the same app
        // can announce again.
        let done = reconcile(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("2.0")],
            launches: Self.freshLaunch,
            notified: [Self.path])
        #expect(done.settled == [Self.path])
        #expect(done.notified.isEmpty)
    }

    /// An empty queue clears both sets outright rather than intersecting, so a
    /// cleared queue cannot leave a row lit.
    ///
    /// Mutation: return `previouslyPending` / `previouslyNotified` instead of
    /// empty sets from the early return.
    @Test func anEmptyQueueClearsEverything() {
        let out = reconcile(
            staged: [:], onDisk: [Self.path: app("2.0")],
            pending: [Self.path], notified: [Self.path])

        #expect(out.pending.isEmpty && out.notified.isEmpty)
    }
}

/// The "from" side of a restart line.
struct RestartLineTests {

    /// Nothing running means no line at all.
    @Test func nothingRunningHasNoFromSide() {
        #expect(RestartLine.fromSide(
            runningBuild: nil, backupMarketing: "1.0", recoveredMarketing: "1.0") == nil)
    }

    /// The backup wins: it was written by us at swap time, so it is
    /// authoritative over the scanned history.
    ///
    /// Mutation: `recoveredMarketing ?? backupMarketing`.
    @Test func theRollbackBackupOutranksTheScannedHistory() {
        let side = RestartLine.fromSide(
            runningBuild: "3965", backupMarketing: "26.609.71450",
            recoveredMarketing: "26.500.00000")

        #expect(side?.marketing == "26.609.71450")
        #expect(side?.build == "3965")
    }

    /// With no backup, the scanned build→marketing history fills in — that is
    /// the case for apps that updated through their own updater.
    ///
    /// Mutation: drop the `?? recoveredMarketing` fallback.
    @Test func theScannedHistoryFillsInWhenThereIsNoBackup() {
        #expect(RestartLine.fromSide(
            runningBuild: "3965", backupMarketing: nil,
            recoveredMarketing: "26.500.00000")?.marketing == "26.500.00000")
    }

    /// A marketing string that is just the build again adds nothing, and saying
    /// it twice would cost the target's build the space it needs for the two
    /// sides to be comparable at all.
    ///
    /// Mutation: `marketing: marketing` without the `== build` test.
    @Test func aMarketingStringEqualToTheBuildIsDropped() {
        let side = RestartLine.fromSide(
            runningBuild: "3965", backupMarketing: "3965", recoveredMarketing: nil)

        #expect(side?.marketing == nil)
        #expect(side?.build == "3965")
    }

    /// JetBrains stamps `CFBundleVersion` as "IU-262.6653.22" while the build id
    /// everything else speaks has no prefix, so the running build is stripped
    /// into that one namespace — and the "is the marketing string just the build
    /// again" test has to be made AFTER stripping, or a recovered "262.6653.22"
    /// stops matching a running "IU-262.6653.22" and gets shown twice.
    ///
    /// The fixture needs a build that actually carries a prefix: with a plain
    /// "3965" the raw and stripped forms are the same string, and comparing
    /// against either passes. The first version of this case did exactly that
    /// and let the mutation through.
    ///
    /// Mutation: compare against the raw `runningBuild` rather than the stripped
    /// `build`; or drop `strippingBuildPrefix` entirely.
    @Test func theBuildIsStrippedBeforeItIsComparedAndShown() {
        let side = RestartLine.fromSide(
            runningBuild: "IU-262.6653.22", backupMarketing: "262.6653.22",
            recoveredMarketing: nil)

        #expect(side?.build == "262.6653.22", "the prefix is not part of the number")
        #expect(side?.marketing == nil, "and the comparison is made after stripping")
    }
}
