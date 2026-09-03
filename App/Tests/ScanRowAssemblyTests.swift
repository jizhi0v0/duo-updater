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
    /// Keyed by path AND both version strings, because that is the contract the
    /// only real conformer enforces: `provenChannelSnapshot` requires
    /// `shortVersion` and `buildVersion` to match too, so a proof is about one
    /// copy at one version rather than about a path. A fixture that answered on
    /// the path alone would let a test assert an outcome the shipping code cannot
    /// produce — and this one did, until a review caught it.
    private struct Proofs: ChannelProofSource {
        var byCopy: [String: ReleaseChannel] = [:]
        static func key(_ app: InstalledApp) -> String {
            "\(app.id)|\(app.shortVersion ?? "")|\(app.buildVersion ?? "")"
        }
        func provenChannel(for app: InstalledApp) -> ReleaseChannel? { byCopy[Self.key(app)] }
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
        _ version: String, channel: ReleaseChannel?, source: String = "GitHub",
        build: String? = nil
    ) -> RemoteVersion {
        RemoteVersion(
            shortVersion: version, version: build, downloadURL: nil, sourceName: source,
            releaseChannel: channel)
    }

    /// A proof about exactly the copy passed in — nothing else.
    private func proven(_ channel: ReleaseChannel, for app: InstalledApp) -> Proofs {
        Proofs(byCopy: [Proofs.key(app): channel])
    }
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
        let app = utm("5.0.5", build: "124")
        let rows = ScanRowAssembly.unchecked([app], proofs: proven(.beta, for: app))

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
        let app = utm("5.0.5", build: "124")
        let rows = ScanRowAssembly.merged([app], prior: [], proofs: proven(.beta, for: app))

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
        let prior = ScanRowAssembly.unchecked([app], proofs: proven(.beta, for: app))

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

    /// Toolbox rows return early because their verdict is a Toolbox build
    /// compare, not a compare against `shortVersion` — Toolbox installs the
    /// update itself between our checks, and the cached "update available" would
    /// otherwise stand beside the freshly rescanned version reading
    /// "262.132.21 → 262.132.21".
    ///
    /// The status assertion is the point. A first version of this asserted only
    /// that the channel survived, and **deleting the whole Toolbox branch left
    /// all eight tests green** — the fixture made `evaluateToolbox`, `evaluate`
    /// and `was.status` agree, so the assertion was `f(X) == f(X)` for the half
    /// that matters. Here the CORRECT answer differs from every wrong one: the
    /// marketing versions differ, so `evaluate` and the carried `was.status`
    /// both say an update is available (they agree with each other, and that is
    /// fine), while the Toolbox builds have caught up, so `evaluateToolbox`
    /// settles the row to `.upToDate` and nothing else does.
    ///
    /// Mutations: delete the `if remote.sourceName == "Toolbox"` branch; or
    /// rebuild its return with `UpdateResult(app:remote:status:)`.
    @Test func aToolboxRowSettlesOnItsOwnBuildCompareAndKeepsItsChannel() {
        let app = InstalledApp(
            name: "IDE", bundleID: "com.jetbrains.ide",
            shortVersion: "262.132.20", buildVersion: "262.132.20",
            path: URL(fileURLWithPath: Self.betaPath),
            isMASApp: false, isToolboxManaged: true, sparkleFeedURL: nil,
            toolboxInstalledBuild: "262.132.21")
        let cached = remote("262.132.21", channel: nil, source: "Toolbox", build: "262.132.21")
        let prior = [UpdateResult(
            app: app, remote: cached, status: .updateAvailable(latest: "262.132.21"),
            provenChannel: .beta)]

        let rows = ScanRowAssembly.merged([app], prior: prior, proofs: noProofs)

        #expect(rows[0].status == .upToDate)
        #expect(rows[0].effectiveReleaseChannel == .beta)
    }

    /// TestFlight owns its betas' status — it comes from TestFlight's own cache,
    /// not from a version compare — and the row's label carries the build,
    /// because TF betas keep one marketing string across builds
    /// (`UpdateChecker` builds "1.2 (345)" for exactly that reason). Re-deriving
    /// it here would rewrite that label to a bare "1.2" on every FS-watcher
    /// rescan.
    ///
    /// Mutations: delete the `guard remote.sourceName != "TestFlight"`; or
    /// rebuild its return with `UpdateResult(app:remote:status:)`.
    @Test func aTestFlightRowKeepsItsOwnStatusAndItsChannel() {
        let app = InstalledApp(
            name: "Beta", bundleID: "com.example.beta",
            shortVersion: "1.2", buildVersion: "344",
            path: URL(fileURLWithPath: Self.betaPath),
            isMASApp: false, isToolboxManaged: false, isTestFlightApp: true,
            sparkleFeedURL: nil)
        let cached = remote("1.2", channel: nil, source: "TestFlight", build: "345")
        let prior = [UpdateResult(
            app: app, remote: cached, status: .updateAvailable(latest: "1.2 (345)"),
            provenChannel: .beta)]

        let rows = ScanRowAssembly.merged([app], prior: prior, proofs: noProofs)

        #expect(rows[0].status == .updateAvailable(latest: "1.2 (345)"))
        #expect(rows[0].effectiveReleaseChannel == .beta)
    }

    /// The ordinary path — a GitHub row whose verdict is re-derived against the
    /// freshly scanned bundle — must still settle its status, not just its
    /// identity. Without this the merge could satisfy every case above by never
    /// re-evaluating anything.
    ///
    /// The proof is keyed to the copy now on disk, not to the one the prior row
    /// described: the store was written by the check that just proved 5.0.5, and
    /// its entry for 5.0.4 does not answer for 5.0.5.
    ///
    /// Mutation: `return carrying(remote, was.status)` in place of the
    /// `UpdateChecker.evaluate(...)` call.
    @Test func anOrdinaryRowIsReEvaluatedAgainstTheNewBundle() {
        let scanned = utm("5.0.5", build: "124")
        let prior = [UpdateResult(
            app: utm("5.0.4", build: "123"), remote: remote("5.0.5", channel: .beta),
            status: .updateAvailable(latest: "5.0.5"), provenChannel: .beta)]

        let rows = ScanRowAssembly.merged(
            [scanned], prior: prior, proofs: proven(.beta, for: scanned))

        #expect(rows[0].status == .upToDate)
        #expect(rows[0].effectiveReleaseChannel == .beta)
    }
}
