import Foundation
import Testing
import DuoUpdaterCore

/// The first tests to execute anything in `App/Sources`.
///
/// Every case here is anchored to a defect that shipped past `make test` and a
/// human reviewer, in the layer that had no test target. Each one names the
/// single-line mutation it must fail under; a case that survives its own
/// mutation is decoration, and this file has already caught one of those
/// (`aDraftIsNeverTheCeiling`, which was `f(X) == f(X)`).
struct ScanRowAssemblyTests {

    // MARK: fixtures

    /// Proofs as a plain dictionary. `ResolvedChannelStore.Snapshot` drops every
    /// entry whose path is not on disk, so using the real type here would mean
    /// minting bundles in the filesystem to test an in-memory decision.
    private struct Proofs: ChannelProofSource {
        var byPath: [String: ReleaseChannel] = [:]
        func provenChannel(for app: InstalledApp) -> ReleaseChannel? { byPath[app.id] }
    }

    private static let betaPath = "/Applications/UTM.app"

    private func utm(_ short: String, build: String?) -> InstalledApp {
        InstalledApp(
            name: "UTM", bundleID: "com.utmapp.UTM",
            shortVersion: short, buildVersion: build,
            path: URL(fileURLWithPath: Self.betaPath),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    private func remote(
        _ version: String, channel: ReleaseChannel?, source: String = "GitHub"
    ) -> RemoteVersion {
        RemoteVersion(
            shortVersion: version, version: nil, downloadURL: nil, sourceName: source,
            releaseChannel: channel)
    }

    private var provenBeta: Proofs { Proofs(byPath: [Self.betaPath: .beta]) }
    private var noProofs: Proofs { Proofs() }

    // MARK: unchecked rows

    /// Cold start and the ignored-rows path both build rows for copies nothing
    /// has checked in this process. UTM's bundle cannot name its own track, so
    /// without the store those rows paint a Beta install as Stable — on the
    /// ignored path permanently, since no check ever comes to repair it.
    ///
    /// Mutation: drop `provenChannel:` from `ScanRowAssembly.unchecked` (it has a
    /// default — that is exactly why the omission used to compile).
    @Test func anUncheckedRowTakesItsChannelFromTheStore() {
        let rows = ScanRowAssembly.unchecked([utm("5.0.5", build: "124")], proofs: provenBeta)

        #expect(rows.count == 1)
        #expect(rows[0].effectiveReleaseChannel == .beta)
    }

    /// The store is version-scoped, so a copy it has nothing to say about must
    /// fall back to the bundle's own signals rather than to some other copy's
    /// answer. Guards the fixture as much as the code: if `Proofs` answered
    /// unconditionally, the case above would pass for the wrong reason.
    @Test func anUnprovenCopyFallsBackToItsBundle() {
        let rows = ScanRowAssembly.unchecked([utm("4.7.5", build: "118")], proofs: noProofs)

        #expect(rows[0].effectiveReleaseChannel == .stable)
    }

    // MARK: merge — rows new to this pass

    /// An app that appears while DuoUpdater is running (installed just now, or a
    /// second copy that a previous scan de-duplicated away) has no prior row, so
    /// the merge builds it from scratch — and that branch was still constructing
    /// a bare `UpdateResult` while `proofs` sat in scope three lines below it,
    /// after five review rounds over this exact rule.
    ///
    /// Mutation: `guard let was = byID[app.id] else { return UpdateResult(app: app,
    /// remote: nil, status: .unknown) }`.
    @Test func anAppWithNoPriorRowStillTakesItsProvenChannel() {
        let rows = ScanRowAssembly.merged(
            [utm("5.0.5", build: "124")], prior: [], proofs: provenBeta)

        #expect(rows[0].effectiveReleaseChannel == .beta)
    }

    // MARK: merge — carrying an existing row forward

    /// The case the store exists for: a check failed, so the row has no remote at
    /// all, and the proven channel is the only thing left holding its identity. A
    /// rescan must not quietly rebuild it as Stable.
    ///
    /// The `remote == nil` shape is load-bearing. The Core tests for
    /// `carriedForward` all carried a remote whose channel happened to satisfy
    /// them, so replacing the whole expression with a bare `proven` left them
    /// green; a case that goes through `remote` proves nothing about this path.
    ///
    /// Mutation: in `merged`, `return UpdateResult(app: app, remote: nil, status:
    /// was.status)` in place of `carrying(nil, was.status)`.
    @Test func aFailedCheckKeepsItsChannelAcrossARescan() {
        let app = utm("5.0.5", build: "124")
        let prior = ScanRowAssembly.unchecked([app], proofs: provenBeta)

        let rows = ScanRowAssembly.merged([app], prior: prior, proofs: noProofs)

        #expect(rows[0].remote == nil)
        #expect(rows[0].effectiveReleaseChannel == .beta)
    }

    /// The other half of the same rule: when the copy on disk has been REPLACED,
    /// the old answer is about an app that is gone. Asserting on
    /// `effectiveReleaseChannel` rather than on `provenChannel` is the point —
    /// the first fix for this gated `provenChannel` alone and the same claim rode
    /// on the carried `remote`, so a `provenChannel`-only assertion passes on the
    /// broken code.
    ///
    /// Mutation: delete `if !sameCopy { carried?.releaseChannel = nil }` from
    /// `UpdateResult.carriedForward`.
    @Test func replacingTheCopyOnDiskDropsTheOldChannel() {
        let before = utm("5.0.5", build: "124")
        let prior = [UpdateResult(
            app: before, remote: remote("5.0.5", channel: .beta), status: .upToDate,
            provenChannel: .beta)]

        let rows = ScanRowAssembly.merged(
            [utm("4.7.5", build: "118")], prior: prior, proofs: noProofs)

        #expect(rows[0].effectiveReleaseChannel == .stable)
    }

    /// Same, for an app that only ever moves its build number — UTM's previews
    /// share a marketing string across a line, and so do Amp, Surge and the
    /// JetBrains previews. A same-copy test that compares marketing alone is
    /// permanently true for them.
    ///
    /// Mutation: `carriedForward`'s `sameCopy` comparing `shortVersion` only.
    @Test func aBuildOnlyChangeAlsoCountsAsADifferentCopy() {
        let before = utm("5.0.5", build: "124")
        let prior = [UpdateResult(
            app: before, remote: remote("5.0.5", channel: .beta), status: .upToDate,
            provenChannel: .beta)]

        let rows = ScanRowAssembly.merged(
            [utm("5.0.5", build: "125")], prior: prior, proofs: noProofs)

        #expect(rows[0].effectiveReleaseChannel == .stable)
    }

    /// Toolbox and TestFlight rows return early from the merge, each through its
    /// own `return`, which is precisely how the carry got dropped on one branch
    /// while the others kept it.
    ///
    /// Mutation: either early return rebuilt with `UpdateResult(app:remote:status:)`.
    @Test func theEarlyReturningSourcesCarryTheChannelToo() {
        for source in ["Toolbox", "TestFlight"] {
            let app = utm("5.0.5", build: "124")
            let prior = [UpdateResult(
                app: app, remote: remote("5.0.5", channel: nil, source: source),
                status: .upToDate, provenChannel: .beta)]

            let rows = ScanRowAssembly.merged([app], prior: prior, proofs: noProofs)

            #expect(rows[0].effectiveReleaseChannel == .beta, "\(source) dropped the channel")
        }
    }

    /// The ordinary path — a GitHub row whose verdict is re-derived against the
    /// freshly scanned bundle — must still settle its status, not just its
    /// identity. Without this the merge could satisfy every case above by never
    /// re-evaluating anything.
    @Test func anOrdinaryRowIsReEvaluatedAgainstTheNewBundle() {
        let prior = [UpdateResult(
            app: utm("5.0.4", build: "123"), remote: remote("5.0.5", channel: .beta),
            status: .updateAvailable(latest: "5.0.5"), provenChannel: .beta)]

        let rows = ScanRowAssembly.merged(
            [utm("5.0.5", build: "124")], prior: prior, proofs: provenBeta)

        #expect(rows[0].status == .upToDate)
        #expect(rows[0].effectiveReleaseChannel == .beta)
    }
}
