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

    // MARK: merge — TestFlight rows settle on a rescan

    /// Invented path, like `planApp` below.
    private func tfBeta(build: String) -> InstalledApp {
        InstalledApp(
            name: "Beta", bundleID: "com.example.beta",
            shortVersion: "1.2", buildVersion: build,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Beta.app"),
            isMASApp: false, isToolboxManaged: false, isTestFlightApp: true,
            sparkleFeedURL: nil)
    }
    /// What the last check read from TestFlight's store: 1.2 (345) on offer.
    private var tfOffer: RemoteVersion {
        remote("1.2", channel: nil, source: "TestFlight", build: "345")
    }

    /// Nothing moved on disk: the offer stands, and so does the row's channel.
    /// Mutation: rebuild the TestFlight branch's return with
    /// `UpdateResult(app:remote:status:)` — the channel goes.
    @Test func anUnmovedTestFlightRowKeepsItsOfferAndItsChannel() {
        let app = tfBeta(build: "344")
        let prior = [UpdateResult(
            app: app, remote: tfOffer, status: .updateAvailable(latest: "1.2"),
            provenChannel: .beta)]

        let rows = ScanRowAssembly.merged([app], prior: prior, proofs: noProofs)

        #expect(rows[0].status == .updateAvailable(latest: "1.2"))
        #expect(rows[0].effectiveReleaseChannel == .beta)
    }

    /// TestFlight installed the build it was offering, between our checks — it
    /// does that on its own. The row must stop offering it. Mutation: carry
    /// `was.status` as before — the row keeps offering 1.2 beside a copy that
    /// already is 1.2 (345).
    @Test func aTestFlightRowSettlesOnceTheOfferIsInstalled() {
        let prior = [UpdateResult(
            app: tfBeta(build: "344"), remote: tfOffer, status: .updateAvailable(latest: "1.2"))]

        let rows = ScanRowAssembly.merged([tfBeta(build: "345")], prior: prior, proofs: noProofs)

        #expect(rows[0].status == .upToDate)
    }

    /// TestFlight installed a build newer than the one its store named — the
    /// #478 shape. The store cannot bound this copy, so neither the carried
    /// "update available" nor the "up to date" a plain version compare gives a
    /// copy ahead of its source may stand. Mutations: carry `was.status`; answer
    /// through `UpdateChecker.evaluate`; keep the remote on the unbounded verdict
    /// — each fails a line below.
    @Test func aTestFlightRowAheadOfTheStoreIsNotCalledCurrent() {
        let prior = [UpdateResult(
            app: tfBeta(build: "344"), remote: tfOffer, status: .updateAvailable(latest: "1.2"))]

        let rows = ScanRowAssembly.merged([tfBeta(build: "346")], prior: prior, proofs: noProofs)

        #expect(rows[0].status == .testFlightManaged)
        #expect(rows[0].remote == nil)
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

// MARK: - roundPlan: what a round that cannot read TestFlight does with its rows

extension ScanRowAssemblyTests {
    /// Invented paths: `roundPlan` keys on the path string and resolves nothing.
    private func planApp(_ name: String, testFlight: Bool) -> InstalledApp {
        InstalledApp(
            name: name, bundleID: "com.example.\(name.lowercased())",
            shortVersion: "1.0", buildVersion: "64",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-\(name).app"),
            isMASApp: false, isToolboxManaged: false, isTestFlightApp: testFlight,
            sparkleFeedURL: nil)
    }

    /// The scheduler's tick keeps a TestFlight row's verdict. Mutation: return
    /// `(checkable, [])` unconditionally — the beta goes back to the checker,
    /// which answers "no cached build" from an empty store, and its update is
    /// gone within one tick.
    @Test func aRoundThatCannotReadTestFlightKeepsItsRows() {
        let beta = planApp("Beta", testFlight: true)
        let plain = planApp("Plain", testFlight: false)
        let onScreen = [
            UpdateResult(app: beta, remote: nil, status: .updateAvailable(latest: "1.0")),
            UpdateResult(app: plain, remote: nil, status: .upToDate),
        ]
        let plan = ScanRowAssembly.roundPlan([beta, plain], keepsTestFlightRows: true, onScreen: onScreen)
        #expect(plan.check.map(\.id) == [plain.id])
        #expect(plan.carried.map(\.id) == [beta.id])
        if case .updateAvailable = plan.carried.first?.status {} else {
            Issue.record("the carried row lost its verdict: \(String(describing: plan.carried.first?.status))")
        }
    }

    /// A round that keeps no rows checks everything — one that reads the store,
    /// and one without the grant, whose rows must say they cannot tell. Mutation:
    /// drop the `keepsTestFlightRows` guard — then a refresh the user asked for
    /// carries the old verdict too and never learns a build the store has, and a
    /// revoked grant keeps "up to date" rows nothing can refresh.
    @Test func aRoundThatReadsTestFlightChecksEverything() {
        let beta = planApp("Beta", testFlight: true)
        let plain = planApp("Plain", testFlight: false)
        let onScreen = [UpdateResult(app: beta, remote: nil, status: .updateAvailable(latest: "1.0"))]
        let plan = ScanRowAssembly.roundPlan([beta, plain], keepsTestFlightRows: false, onScreen: onScreen)
        #expect(plan.check.map(\.id) == [beta.id, plain.id])
        #expect(plan.carried.isEmpty)
    }

    /// With no row on screen there is nothing to keep, so the beta is checked.
    /// Mutation: skip a TestFlight app that has no row instead of checking it —
    /// then a beta installed since the last round never reaches the checker.
    @Test func aBetaWithNoRowYetIsStillChecked() {
        let beta = planApp("Beta", testFlight: true)
        let plan = ScanRowAssembly.roundPlan([beta], keepsTestFlightRows: true, onScreen: [])
        #expect(plan.check.map(\.id) == [beta.id])
        #expect(plan.carried.isEmpty)
    }
}

// MARK: - roundPlan: the shape production actually puts on screen

extension ScanRowAssemblyTests {
    /// A cold launch's first round, and an app installed since the last one, both
    /// put this round's own unchecked placeholder on screen before the check — so
    /// "no row yet" (`aBetaWithNoRowYetIsStillChecked`) is a shape production never
    /// has, and this is the one it does. Mutation: drop `row.status != .unknown`
    /// from `roundPlan` — the placeholder is carried, the beta stays blank until a
    /// round reads TestFlight, and this fails.
    @Test func aPlaceholderRowIsNotAVerdict() {
        let beta = planApp("Beta", testFlight: true)
        let onScreen = [ScanRowAssembly.unchecked(beta, proofs: noProofs)]
        let plan = ScanRowAssembly.roundPlan([beta], keepsTestFlightRows: true, onScreen: onScreen)
        #expect(plan.check.map(\.id) == [beta.id])
        #expect(plan.carried.isEmpty)
    }
}

// MARK: - recheck: what a per-row recheck answers a TestFlight row from

@MainActor
extension ScanRowAssemblyTests {
    /// A store that opened, offering 1.2 (345) for the beta — `tfOffer`'s build.
    private var openStore: TestFlightInventory {
        TestFlightInventory(macRows: [(bundleID: "com.example.beta", shortVersion: "1.2", build: "345")])
    }

    /// Records what `recheck` asked for, and answers each app from the store it
    /// was handed: a build there is an offer, none is "no cached build". That is
    /// the one respect in which `UpdateChecker`'s TestFlight branch matters here.
    private final class Probe {
        var grantAsked = 0
        var reads = 0
        var checked: [String] = []
        var checkedApps: [InstalledApp] = []
        func grant(_ granted: Bool) -> Bool {
            grantAsked += 1
            return granted
        }
        func check(_ apps: [InstalledApp], _ store: TestFlightInventory) -> [UpdateResult] {
            checked += apps.map(\.id)
            checkedApps += apps
            return apps.map { app in
                guard let build = store.latest(forBundleID: app.bundleID)?.latestBuild else {
                    return UpdateResult(app: app, remote: nil, status: .testFlightManaged)
                }
                return UpdateResult(app: app, remote: nil, status: .updateAvailable(latest: build))
            }
        }
    }

    private var offered: UpdateResult {
        UpdateResult(app: tfBeta(build: "344"), remote: tfOffer, status: .updateAvailable(latest: "1.2"))
    }

    /// A wrapped iPhone/iPad beta that only the store recognizes (#456): there is
    /// no receipt to read, so the scan taken without the store does not call it
    /// one, while its row — from the last round that read the store — does.
    /// Mutation: skip the retag (`? scanned : scanned`) — `check` is handed a copy
    /// that is not a TestFlight app, which a real checker answers from the App
    /// Store instead.
    @Test func aWrappedBetaIsRetaggedFromTheStoreItRead() async {
        let probe = Probe()
        func wrapped(testFlight: Bool) -> InstalledApp {
            InstalledApp(
                name: "Wrapped", bundleID: "com.example.wrapped",
                shortVersion: "2.0", buildVersion: "7",
                path: URL(fileURLWithPath: "/Applications/ZZFixture-Wrapped.app"),
                isMASApp: !testFlight, isiOSAppOnMac: true, isTestFlightApp: testFlight,
                sparkleFeedURL: nil)
        }
        let store = TestFlightInventory(
            macRows: [], installedIOSRows: [(bundleID: "com.example.wrapped", shortVersion: "2.0", build: "7")])
        _ = await ScanRowAssembly.recheck(
            [UpdateResult(app: wrapped(testFlight: true), remote: nil, status: .upToDate)],
            scanned: [wrapped(testFlight: false)], mayRead: probe.grant(true),
            read: { store }, proofs: noProofs, check: { probe.check($0, $1) })
        #expect(probe.checkedApps.map(\.isTestFlightApp) == [true])
    }

    /// Check Again on a beta answers it from the store it read. Mutations: skip
    /// the read — what the recheck did until 2026-09-11 — or hand `check` the
    /// empty store; either way the beta is "no cached build".
    @Test func checkAgainAnswersABetaFromTheStore() async {
        let probe = Probe()
        let (rows, kept) = await ScanRowAssembly.recheck(
            [offered], scanned: [tfBeta(build: "344")], mayRead: probe.grant(true),
            read: { probe.reads += 1; return self.openStore },
            proofs: noProofs, check: { probe.check($0, $1) })
        #expect(probe.reads == 1)
        #expect(rows.map(\.status) == [.updateAvailable(latest: "345")])
        #expect(kept.isEmpty)
    }

    /// Granted, but the store did not open — no answer in time, or one that never
    /// got in: the beta is kept, not answered from nothing. Mutations: keep only
    /// when the read returned nothing (`opened == nil`); check every scanned app
    /// instead of `plan.check`; drop `+ plan.carried` — each fails a line below.
    @Test func aRecheckWhoseReadFailedKeepsTheBeta() async {
        for failed in [nil, TestFlightInventory(macRows: [], accessible: false)] {
            let probe = Probe()
            let (rows, kept) = await ScanRowAssembly.recheck(
                [offered], scanned: [tfBeta(build: "344")], mayRead: probe.grant(true),
                read: { failed }, proofs: noProofs, check: { probe.check($0, $1) })
            #expect(probe.checked.isEmpty)
            #expect(rows.map(\.status) == [.updateAvailable(latest: "1.2")])
            #expect(kept.map(\.id) == [offered.id])
        }
    }

    /// TestFlight installed the offered build since the last check, and the read
    /// failed: the kept row settles against the copy on disk instead of still
    /// offering it. Mutation: `onScreen: rows` — the row as it was, not re-derived
    /// — and it offers 1.2 (345) beside a copy that is 1.2 (345).
    @Test func aKeptBetaSettlesAgainstTheCopyOnDisk() async {
        let probe = Probe()
        let (rows, _) = await ScanRowAssembly.recheck(
            [offered], scanned: [tfBeta(build: "345")], mayRead: probe.grant(true),
            read: { nil }, proofs: noProofs, check: { probe.check($0, $1) })
        #expect(rows.map(\.status) == [.upToDate])
    }

    /// An install's recheck never has a beta, and neither probes the grant nor
    /// reads the store. Mutations: ask `mayRead` before the TestFlight-row test;
    /// drop that test — each fails a line below.
    @Test func aRecheckWithoutABetaAsksNothing() async {
        let probe = Probe()
        let plain = planApp("Plain", testFlight: false)
        _ = await ScanRowAssembly.recheck(
            [UpdateResult(app: plain, remote: nil, status: .upToDate)], scanned: [plain],
            mayRead: probe.grant(true),
            read: { probe.reads += 1; return self.openStore },
            proofs: noProofs, check: { probe.check($0, $1) })
        #expect(probe.grantAsked == 0)
        #expect(probe.reads == 0)
        #expect(probe.checked == [plain.id])
    }

    /// Without the grant the store is not read and the beta not kept: it is
    /// checked, and says it cannot tell, as in a round without the grant.
    /// Mutations: drop `mayRead` — the read runs where it cannot succeed
    /// (`TCCPreflight.admitsOtherAppsData`); keep the beta anyway — a kept verdict
    /// nothing will ever refresh.
    @Test func withoutTheGrantABetaIsCheckedNotKept() async {
        let probe = Probe()
        let (rows, kept) = await ScanRowAssembly.recheck(
            [offered], scanned: [tfBeta(build: "344")], mayRead: probe.grant(false),
            read: { probe.reads += 1; return self.openStore },
            proofs: noProofs, check: { probe.check($0, $1) })
        #expect(probe.reads == 0)
        #expect(rows.map(\.status) == [.testFlightManaged])
        #expect(kept.isEmpty)
    }

    /// The row was not a beta at the last check; the copy on disk now is one,
    /// because TestFlight replaced it. The store is still read. Mutation: decide
    /// on the rows' old tags alone — the new beta is answered from an empty store,
    /// the bug this path fixes, reached by another door.
    @Test func aCopyThatBecameABetaReadsTheStore() async {
        let probe = Probe()
        let before = planApp("Beta", testFlight: false)
        let (rows, _) = await ScanRowAssembly.recheck(
            [UpdateResult(app: before, remote: nil, status: .upToDate)],
            scanned: [tfBeta(build: "344")], mayRead: probe.grant(true),
            read: { probe.reads += 1; return self.openStore },
            proofs: noProofs, check: { probe.check($0, $1) })
        #expect(probe.reads == 1)
        #expect(rows.map(\.status) == [.updateAvailable(latest: "345")])
    }

    /// The same new beta when the read fails: its row carries another source's
    /// verdict, which a kept row would pass off as the beta's. It is checked
    /// instead, and says it cannot tell. Mutation: drop the `wereTestFlight`
    /// filter — the row is kept, still "up to date" on the old source's word.
    @Test func aCopyThatBecameABetaIsNotKeptOnAFailedRead() async {
        let probe = Probe()
        let before = planApp("Beta", testFlight: false)
        let (rows, kept) = await ScanRowAssembly.recheck(
            [UpdateResult(app: before, remote: nil, status: .upToDate)],
            scanned: [tfBeta(build: "344")], mayRead: probe.grant(true),
            read: { nil }, proofs: noProofs, check: { probe.check($0, $1) })
        #expect(kept.isEmpty)
        #expect(rows.map(\.status) == [.testFlightManaged])
    }
}
