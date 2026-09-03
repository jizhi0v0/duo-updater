import Foundation
import Testing
@testable import DuoUpdaterCore

/// Which staged package entries survive a pass.
///
/// A staged entry outlives its download, so this is not "is the file there":
/// three of the four rules keep an entry whose file is gone. It lived in
/// `AppListModel` with nothing to execute it, and it decided "has this landed"
/// with its own copy of the expression in `PackageRestartState`, kept in step by
/// a comment saying it matched.
struct StagedPackagePruneTests {

    /// `/Applications`, not a temp dir — see the note in
    /// `PackageRestartReconcilerTests`; the sibling suite keys launch dates
    /// through `resolvingSymlinksInPath`, and keeping both fixtures on the same
    /// footing is what lets the agreement test below compare them.
    private static let path = "/Applications/Example.app"
    private static let stagedAt = Date(timeIntervalSince1970: 1_000)

    private func app(
        _ short: String, build: String? = nil,
        bundleID: String = "com.example.app", path: String = Self.path
    ) -> InstalledApp {
        InstalledApp(
            name: "Example", bundleID: bundleID,
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: path),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    private func staged(_ short: String, build: String? = nil) -> StagedPackageFacts {
        StagedPackageFacts(
            versionSide: VersionSide(marketing: short, build: build), stagedAt: Self.stagedAt)
    }

    private func keep(
        staged stagedMap: [String: StagedPackageFacts],
        onDisk: [String: InstalledApp] = [:],
        offered: [String: VersionSide] = [:],
        pending: Set<String> = [],
        downloadExists: Bool = true
    ) -> Set<String> {
        StagedPackagePrune.keep(
            staged: stagedMap, onDisk: onDisk, offered: offered, pending: pending,
            downloadExists: { _ in downloadExists })
    }

    // MARK: the three rules that keep an entry whose download is gone

    /// A landed package waiting on a relaunch keeps its entry even though the app
    /// is now current (so nothing is "on offer") and the download may have been
    /// swept. Reclaiming it here would drop the Restart badge the reconciler is
    /// holding.
    ///
    /// Mutation: delete the `pending.contains(id)` branch.
    @Test func aRowWaitingOnARelaunchIsKeptWithNoDownloadAndNoOffer() {
        #expect(keep(
            staged: [Self.path: staged("2.0")],
            // Reads as the OLD version — the mid-swap case. With `app("2.0")`
            // here the row also satisfies the landed rule, so deleting the
            // pending branch left this green: it was measuring the wrong branch.
            onDisk: [Self.path: app("1.0")],
            pending: [Self.path],
            downloadExists: false) == [Self.path])
    }

    /// …and it costs no filesystem call, which is why that branch is first.
    ///
    /// Mutation: move the `pending` check below the `downloadExists` read, or
    /// hoist `downloadExists(id)` above it.
    @Test func aPendingRowIsAnsweredWithoutTouchingTheFilesystem() {
        var asked = 0
        _ = StagedPackagePrune.keep(
            staged: [Self.path: staged("2.0")], onDisk: [:], offered: [:],
            pending: [Self.path],
            downloadExists: { _ in asked += 1; return true })

        #expect(asked == 0)
    }

    /// A landed package keeps its entry even with the download swept, so restart
    /// tracking survives a one-scan flicker of the launch-time signal.
    ///
    /// Mutation: delete the `hasLanded` branch.
    @Test func aLandedPackageIsKeptWithItsDownloadSwept() {
        #expect(keep(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("2.0")],
            downloadExists: false) == [Self.path])
    }

    /// A row missing from THIS scan is a bundle mid-swap, not a deletion — decide
    /// nothing from it, and let the file backstop bound it instead.
    ///
    /// Mutation: `return` nothing (drop the id) in the blind branch.
    @Test func aBlindPassKeepsAnEntryWhoseDownloadIsStillThere() {
        #expect(keep(staged: [Self.path: staged("2.0")], onDisk: [:]) == [Self.path])
    }

    /// The backstop half: blind AND the download is gone, so there is nothing
    /// left to install and nothing to wait for.
    ///
    /// Mutation: `kept.insert(id)` unconditionally in the blind branch.
    @Test func aBlindPassDropsAnEntryWhoseDownloadIsGone() {
        #expect(keep(
            staged: [Self.path: staged("2.0")], onDisk: [:],
            downloadExists: false).isEmpty)
    }

    // MARK: the ordinary rule — still offered AND re-openable

    /// Not landed, not pending, still the version on offer and still downloaded:
    /// keep, it is usable.
    @Test func anUnlandedEntryStillOnOfferAndDownloadedIsKept() {
        #expect(keep(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("1.0")],
            offered: [Self.path: VersionSide(marketing: "2.0")]) == [Self.path])
    }

    /// The source has moved past it: installing this would hand the user a
    /// version its own source no longer offers.
    ///
    /// Mutation: drop the `stillOffered` half of the final `&&`.
    @Test func anUnlandedEntryTheSourceNoLongerOffersIsDropped() {
        #expect(keep(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("1.0")],
            offered: [Self.path: VersionSide(marketing: "3.0")]).isEmpty)
    }

    /// Nothing offered at all is not the same as "offered and matching". A source
    /// that said nothing this pass must not be read as agreement.
    ///
    /// Mutation: `offered[id].map { … } != false` — nil then reads as a match.
    @Test func anUnlandedEntryWithNothingOnOfferIsDropped() {
        #expect(keep(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("1.0")]).isEmpty)
    }

    /// …and the download half of that same rule.
    ///
    /// Mutation: drop the `downloadExists(id)` half of the final `&&`.
    @Test func anUnlandedEntryWhoseDownloadIsGoneIsDropped() {
        #expect(keep(
            staged: [Self.path: staged("2.0")],
            onDisk: [Self.path: app("1.0")],
            offered: [Self.path: VersionSide(marketing: "2.0")],
            downloadExists: false).isEmpty)
    }

    // MARK: more than one entry

    /// Every other case has a single entry, which makes `insert` indistinguishable
    /// from assignment.
    ///
    /// Mutation: `kept = [id]` in any branch.
    @Test func eachEntryIsJudgedOnItsOwn() {
        let keeper = "/Applications/Alpha.app"
        let goner = "/Applications/Beta.app"

        let out = keep(
            staged: [keeper: staged("2.0"), goner: staged("2.0")],
            onDisk: [keeper: app("2.0", path: keeper), goner: app("1.0", path: goner)])

        #expect(out == [keeper], "the landed one stays, the stale unoffered one goes")
    }

    /// Two entries kept through DIFFERENT branches, with the later one taking the
    /// branch under test. The case above cannot see `kept = [id]` in the landed
    /// branch, because its landed row sorts first and the row after it is dropped
    /// anyway — so the assignment happens to produce the right answer.
    ///
    /// Mutation: `kept = [id]` in place of `kept.insert(id)` in any branch.
    @Test func entriesKeptThroughDifferentBranchesAllSurvive() {
        let blind = "/Applications/Alpha.app"      // kept: blind, download present
        let landed = "/Applications/Beta.app"      // kept: landed
        let waiting = "/Applications/Delta.app"    // kept: pending a relaunch
        let offeredRow = "/Applications/Zeta.app"  // kept: on offer + downloaded

        let out = keep(
            staged: [blind: staged("2.0"), landed: staged("2.0"),
                     waiting: staged("2.0"), offeredRow: staged("2.0")],
            onDisk: [landed: app("2.0", path: landed), waiting: app("2.0", path: waiting),
                     offeredRow: app("1.0", path: offeredRow)],
            offered: [offeredRow: VersionSide(marketing: "2.0")],
            pending: [waiting])

        #expect(out == [blind, landed, waiting, offeredRow])
    }

    /// The blind branch sorts FIRST in every other multi-entry case, so an
    /// assignment there happens to give the right answer — the rows after it put
    /// themselves back. Here it sorts last, so it has something to displace.
    ///
    /// Mutation: `kept = [id]` in the blind branch.
    @Test func aBlindEntryDoesNotDisplaceAnEarlierKeeper() {
        let landed = "/Applications/Beta.app"
        let blind = "/Applications/Zeta.app"

        #expect(keep(
            staged: [landed: staged("2.0"), blind: staged("2.0")],
            onDisk: [landed: app("2.0", path: landed)]) == [landed, blind])
    }
}

/// The one rule both halves of the package-restart machinery depend on.
///
/// `StagedPackagePrune.keep` and `PackageRestartState.resolve` each need to know
/// whether the app on disk IS the staged version. They used to decide it with
/// two copies of one expression in two files, and the only thing holding them
/// together was a comment in one saying it matched the other. These cases assert
/// the agreement directly, so a change to one side that does not reach the other
/// fails here rather than in the field.
struct LandedAgreementTests {

    private func app(_ short: String, build: String?, bundleID: String) -> InstalledApp {
        InstalledApp(
            name: "Example", bundleID: bundleID, shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/Example.app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    /// No on-disk version at all is NOT landing. `resolve` returns `.pending`
    /// for it, and prune must not keep an entry on the strength of it either —
    /// a row we cannot read a version for has told us nothing.
    ///
    /// Mutation: `guard let onDiskVersion else { return true }` in `hasLanded`.
    @Test func anAbsentOnDiskVersionIsNotLanded() {
        let stagedSide = VersionSide(marketing: "2.0", build: "20")

        #expect(!PackageRestartState.hasLanded(
            onDiskVersion: nil, stagedVersion: stagedSide, buildIsDerived: false))
        #expect(PackageRestartState.resolve(
            onDiskVersion: nil, stagedVersion: stagedSide,
            stagedAt: Date(timeIntervalSince1970: 1_000),
            runningLaunchDates: [Date(timeIntervalSince1970: 500)]) == .pending)
    }

    /// The inputs where the two copies were most likely to drift: a derived
    /// build, where landing must fall back to marketing alone. Judged "not
    /// landed" by either side, the badge never lights and the entry never
    /// settles (#285).
    @Test func bothSidesAgreeOnLandingIncludingDerivedBuilds() {
        let stagedAt = Date(timeIntervalSince1970: 1_000)
        let stale = [Date(timeIntervalSince1970: 500)]
        let cases: [(String, InstalledApp, VersionSide, Bool)] = [
            ("plain, same",
             app("2.0", build: "20", bundleID: "com.example.app"),
             VersionSide(marketing: "2.0", build: "20"), true),
            ("plain, still old",
             app("1.0", build: "10", bundleID: "com.example.app"),
             VersionSide(marketing: "2.0", build: "20"), false),
            // Separates the flag's two values in the OTHER direction: an
            // ordinary app whose marketing matches but whose build moved has not
            // landed. Hardcoding `buildIsDerived: true` throws the build away,
            // calls it landed, and passed everything until this case existed.
            ("plain, marketing matches but the build moved",
             app("2.0", build: "21", bundleID: "com.example.app"),
             VersionSide(marketing: "2.0", build: "20"), false),
            ("derived build, marketing matches, builds differ",
             app("27.0", build: "27A5237l", bundleID: AppScanner.xcodeBundleID),
             VersionSide(marketing: "27.0", build: "27A5300x"), true),
            ("derived build, marketing differs",
             app("26.0", build: "26A100", bundleID: AppScanner.doubaoImeBundleID),
             VersionSide(marketing: "27.0", build: "27A5300x"), false),
        ]

        for (label, installed, stagedSide, expectedLanded) in cases {
            let landed = PackageRestartState.hasLanded(
                onDiskVersion: installed.versionSide, stagedVersion: stagedSide,
                buildIsDerived: AppScanner.buildVersionIsOverridden(
                    bundleID: installed.bundleID))
            #expect(landed == expectedLanded, "hasLanded disagrees for \(label)")

            // resolve() must classify a landed row as anything but `.pending`,
            // and an unlanded one as exactly `.pending`.
            let state = PackageRestartState.resolve(
                onDiskVersion: installed.versionSide, stagedVersion: stagedSide,
                stagedAt: stagedAt, runningLaunchDates: stale,
                buildIsDerived: AppScanner.buildVersionIsOverridden(
                    bundleID: installed.bundleID))
            #expect((state != .pending) == expectedLanded, "resolve disagrees for \(label)")

            // prune keeps a landed entry with no offer and no download — which it
            // can only do by agreeing that it landed.
            let kept = StagedPackagePrune.keep(
                staged: ["/Applications/Example.app":
                    StagedPackageFacts(versionSide: stagedSide, stagedAt: stagedAt)],
                onDisk: ["/Applications/Example.app": installed],
                offered: [:], pending: [], downloadExists: { _ in false })
            #expect(
                kept == (expectedLanded ? ["/Applications/Example.app"] : []),
                "prune disagrees for \(label)")
        }
    }
}
