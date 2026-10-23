import Foundation
import Testing
@testable import DuoUpdaterCore

/// The shared model for "a manager and the many things it keeps"
/// (`CLITools/Managed/`, plans/cli-managers-redesign.md §3): the one place a
/// verdict becomes a row (`ManagedCheck`), the provider every manager runs
/// through (`ManagedProvider`), and the identity a row keeps while its
/// directory moves. Driven by a scripted adapter: nothing here reads the host,
/// spawns anything or reaches the network. Every path is invented.
///
/// Each case names the mutation it fails under.
struct ManagedModelTests {

    // MARK: fixtures

    static let home = URL(fileURLWithPath: "/ZZFixture-home")
    static let rootPath = "/ZZFixture-home/.local/share/zz"
    static let binaryPath = "/ZZFixture-home/.local/bin/zz"

    static let descriptor = ManagerDescriptor(
        id: ManagerID("zz-fake"), displayName: "ZZ Fake tools", signer: "ZZ Corp", logo: nil, tint: .label,
        lane: "zz-fake", updaterSpendsGitHubAPI: .ourTokenIfAny)

    static func root(trust: ManagedRoot.Trust? = .vendorSigned(team: "ZZ123")) -> ManagedRoot {
        ManagedRoot(
            manager: descriptor.id, path: rootPath,
            binary: trust.map { ManagedRoot.Binary(path: binaryPath, version: "1.0.0", trust: $0) })
    }

    static func item(
        key: String = "node@20", name: String = "node", installPath: String = rootPath + "/installs/node/20.10.0",
        request: ManagedItem.Request? = ManagedItem.Request(kind: .range, spelled: "20"),
        installed: String? = "20.10.0", within: String? = "20.20.2", overall: String? = "26.12.1",
        effects: [ManagedItem.Effect] = [.oldKept(for: "24h")]
    ) -> ManagedItem {
        ManagedItem(
            descriptor: descriptor, root: rootPath, key: key, name: name, installPath: installPath,
            shape: .request, request: request, installed: installed, latestWithinRequest: within,
            latestOverall: overall, backend: "core:node", effects: effects, facts: [.source("/ZZFixture-home/.config/zz/config.toml")])
    }

    static func upgrade(_ item: ManagedItem) -> CLIToolCommand {
        CLIToolCommand(executable: binaryPath, arguments: ["upgrade", "-y", item.name], pathPrefix: rootPath + "/shims")
    }

    static func unpin(_ item: ManagedItem) -> CLIToolCommand {
        CLIToolCommand(executable: binaryPath, arguments: ["upgrade", "--bump", item.name], pathPrefix: nil)
    }

    static func status(
        _ item: ManagedItem = item(), vendorWouldUpgrade: Bool? = true, blocker: ManagedVerdict.Blocker? = nil,
        busy: String? = nil, root: ManagedRoot? = root()
    ) -> CLIToolStatus {
        ManagedCheck.status(
            ManagedVerdict(item: item, vendorWouldUpgrade: vendorWouldUpgrade, blocker: blocker, busy: busy),
            root: root, upgrade: upgrade(item), unpin: unpin(item))
    }

    /// One manager, every answer scripted. A class so a test can change what
    /// the next scan finds between the check and the click.
    final class FakeAdapter: ManagerAdapter, @unchecked Sendable {
        let descriptor = ManagedModelTests.descriptor
        var scanResult = ManagedScan(
            roots: [ManagedModelTests.root()], items: [ManagedModelTests.item()],
            states: [ManagedModelTests.item().identity: "core:node|20.10.0"])
        var verdict: (ManagedItem) -> ManagedVerdict = { ManagedVerdict(item: $0, vendorWouldUpgrade: true) }
        var busyLine: String?
        var rereadVersion: String? = "20.20.2"
        var tokenRetry: ManagedTokenRetry?
        var environment = ["ZZ_DATA_DIR": ManagedModelTests.rootPath]
        private(set) var scans = 0

        func scan() async -> ManagedScan { scans += 1; return scanResult }
        func check(_ scan: ManagedScan) async -> [ManagedVerdict] { scan.items.map(verdict) }
        func upgrade(_ item: ManagedItem, root: ManagedRoot) -> (command: CLIToolCommand, environment: [String: String])? {
            (ManagedModelTests.upgrade(item), environment)
        }
        func unpin(_ item: ManagedItem, root: ManagedRoot) -> CLIToolCommand? { ManagedModelTests.unpin(item) }
        func busy(_ item: ManagedItem, root: ManagedRoot, processes: [NpmActivity.Process]) -> String? { busyLine }
        func reread(_ item: ManagedItem) async -> String? { rereadVersion }
    }

    /// What the provider asked the runner to run, in order.
    actor Runs {
        struct Run: Sendable { let command: CLIToolCommand; let environment: [String: String] }
        private(set) var runs: [Run] = []
        var results: [ManagedProvider.RunResult] = [ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: ["Updated"])]
        func record(_ command: CLIToolCommand, _ environment: [String: String]) -> ManagedProvider.RunResult {
            runs.append(Run(command: command, environment: environment))
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        func set(_ results: [ManagedProvider.RunResult]) { self.results = results }
    }

    static func provider(
        _ adapter: FakeAdapter, runs: Runs, token: String? = nil, processes: [NpmActivity.Process] = []
    ) -> ManagedProvider {
        ManagedProvider(
            adapter, home: home,
            proxyEnvironment: { ["https_proxy": "http://zz.invalid:3128"] },
            processes: { processes },
            token: { token },
            runner: { command, environment, _, _, progress in
                let result = await runs.record(command, environment)
                for line in result.lines { progress(line) }
                return result
            })
    }

    // MARK: identity

    /// A managed row is named by manager, root and key, not by the directory
    /// it sits in now: two scans of one line, its newest patch in two
    /// directories, are one row. Mutation: build `identity` from `installPath`.
    @Test func identityIsManagerRootAndKeyNotTheDirectory() {
        let before = Self.item(installPath: Self.rootPath + "/installs/node/20.10.0")
        let after = Self.item(installPath: Self.rootPath + "/installs/node/20.20.2", installed: "20.20.2")
        #expect(before.identity == after.identity)
        #expect(before.identity == "zz-fake|\(Self.rootPath)|node@20")
        #expect(Self.status(before).identity == Self.status(after).identity)
        #expect(Self.status(before).path != Self.status(after).path)
        let parts = ManagedItem.parse(identity: before.identity)
        #expect(parts?.manager == Self.descriptor.id)
        #expect(parts?.root == Self.rootPath)
        #expect(parts?.key == "node@20")
        #expect(ManagedItem.parse(identity: "/ZZFixture-home/.local/bin/fx") == nil)
    }

    /// A status of kind `.managed` names its provider by its manager, not by
    /// the kind every manager shares; every other kind by its raw value.
    /// Mutation: `providerID` returns `kind.rawValue` for `.managed`.
    @Test func aManagedStatusNamesItsManagersProvider() {
        #expect(Self.status().providerID == "managed:zz-fake")
        #expect(Self.descriptor.providerID == "managed:zz-fake")
        #expect(CLIToolsTests.status().providerID == "fx")
        #expect(ManagedProvider(FakeAdapter()).id == "managed:zz-fake")
        #expect(ManagedProvider(FakeAdapter()).attributionName == "ZZ Fake tools")
    }

    /// Two managed providers keep the order given, after every standalone kind
    /// (`CLITools.inKindOrder`, D12). Mutation: sort by kind alone.
    @Test func managedProvidersKeepRegistryOrderAfterTheStandaloneKinds() {
        let a = ManagedProvider(FakeAdapter())
        let b = ManagedProvider(FakeAdapter())
        let ordered = CLITools.inKindOrder([b, FxProvider(), a] as [any CLIToolProvider])
        #expect(ordered.map(\.kind) == [.fx, .managed, .managed])
        #expect(ordered[1].adapterIs(b.adapter))
        #expect(ordered[2].adapterIs(a.adapter))
    }

    // MARK: ManagedCheck — one case per row of §3.2

    /// The vendor would upgrade → offered, the latest within the request on the
    /// row (not the one beyond it). Mutation: put `latestOverall` on the row.
    @Test func vendorWouldUpgradeIsOffered() {
        let status = Self.status()
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == Self.upgrade(Self.item()))
        #expect(status.latestVersion == "20.20.2")
        #expect(status.installedVersion == "20.10.0")
        #expect(status.withheld == nil)
        #expect(status.name == "node")
        #expect(status.kind == .managed)
        #expect(status.releaseNotesKey == "managed:zz-fake:node@20")
        #expect(status.joinsUpdateAll)
    }

    /// An exact request below a newer release is pinned: reported with the
    /// unpin command to copy, never offered, not counted (the 2026-10-13
    /// rule). Mutation: offer a pinned row; use `latestWithinRequest`.
    @Test func anExactRequestBelowANewerReleaseIsPinned() {
        let jq = Self.item(key: "jq@1.6", name: "jq", request: .init(kind: .exact, spelled: "1.6"),
                           installed: "1.6", within: nil, overall: "1.8.1")
        let status = Self.status(jq, vendorWouldUpgrade: false)
        #expect(status.state == .pinned)
        #expect(status.oneClick == nil)
        #expect(status.latestVersion == "1.8.1")
        #expect(status.commandToCopy == Self.unpin(jq))
        #expect(!status.joinsUpdateAll)
        #expect(CLIToolWording.pinned(status) != nil)
    }

    /// A range held at its top with newer beyond it is current (D2); what lies
    /// beyond is a fact, read by `beyondRequest`, with the unpin command on
    /// `manualCommand` — and nothing to copy on the row, since it is current.
    /// Mutations: count it as outdated; read `latestOverall` as the row's
    /// latest; set `manualCommand` only on `.pinned` (review round 1).
    @Test func aRangeAtItsTopIsCurrentWithTheGapAsAFact() {
        let node = Self.item(installed: "20.20.2", within: "20.20.2", overall: "26.12.1")
        let status = Self.status(node, vendorWouldUpgrade: false)
        #expect(status.state == .upToDate)
        #expect(status.latestVersion == "20.20.2")
        #expect(status.oneClick == nil)
        #expect(status.manualCommand == Self.unpin(node))
        #expect(status.commandToCopy == nil)
        #expect(ManagedCheck.beyondRequest(status) == "26.12.1")
        #expect(ManagedCheck.beyondRequest(Self.status()) == nil)
        // Nothing beyond: no command rides along.
        let flat = Self.status(Self.item(installed: "20.20.2", within: "20.20.2", overall: "20.20.2"), vendorWouldUpgrade: false)
        #expect(flat.manualCommand == nil)
    }

    /// Installed equals the latest → current; above it → ahead.
    @Test func equalIsCurrentAndAboveIsAhead() {
        let same = Self.status(Self.item(installed: "20.20.2", within: "20.20.2", overall: nil), vendorWouldUpgrade: false)
        #expect(same.state == .upToDate)
        let ahead = Self.status(Self.item(installed: "20.30.0", within: "20.20.2", overall: nil), vendorWouldUpgrade: false)
        #expect(ahead.state == .ahead)
        #expect(ahead.latestVersion == "20.20.2")
    }

    /// The vendor said nothing to upgrade and named no latest: current at the
    /// installed version. Mutation: `.unknown` for a missing latest.
    @Test func vendorsNoWithoutALatestIsCurrent() {
        let status = Self.status(Self.item(within: nil, overall: nil), vendorWouldUpgrade: false)
        #expect(status.state == .upToDate)
        #expect(status.latestVersion == "20.10.0")
    }

    /// A ranged specifier the adapter cannot match (D9): reported only, with
    /// the reason, never offered. Mutation: treat nil as true.
    @Test func anUnmatchedRangeIsReportedNotOffered() {
        let black = Self.item(key: "black", name: "black", request: .init(kind: .range, spelled: ">=23,<24"),
                              installed: "23.1.0", within: nil, overall: "24.2.0")
        let status = Self.status(black, vendorWouldUpgrade: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
        #expect(status.note?.contains("could not say") == true)
    }

    /// A blocker is a row with no verdict, the gate named, the row kept
    /// (a git crate, an editable venv, a pseudo-version Go binary stay
    /// visible). Mutation: drop the row; map every blocker to one gate.
    @Test func aBlockerKeepsTheRowWithoutAVerdict() {
        let git = Self.status(blocker: .notIndexed("installed from git+https://zz.invalid/x.git"))
        #expect(git.state == .unknown)
        #expect(git.withheld == .unsupportedInstaller)
        #expect(git.note == "not on an index: installed from git+https://zz.invalid/x.git")
        #expect(git.oneClick == nil)
        #expect(Self.status(blocker: .channelUnreadable("timed out")).withheld == .channelUnreadable)
        #expect(Self.status(blocker: .rateLimited).withheld == .rateLimited)
        #expect(Self.status(blocker: .rateLimited).isRateLimitError)
        #expect(Self.status(blocker: .versionUnreadable).withheld == .versionUnreadable)
        let msrv = Self.status(blocker: .runtimeTooOld("rustc 1.85"))
        #expect(msrv.withheld == .runtimeTooOld)
        // Worded from the verdict, not as npm's "Needs a newer Node" (review round 1).
        #expect(CLIToolWording.reason(.runtimeTooOld, of: msrv) == "the newest release needs rustc 1.85")
        #expect(Self.status(blocker: .notRequested("mise outdated reports one request per tool")).withheld == .unsupportedInstaller)
    }

    /// No installed version: unknown, unreadable — before any blocker.
    @Test func noInstalledVersionIsUnreadable() {
        let status = Self.status(Self.item(installed: nil))
        #expect(status.state == .unknown)
        #expect(status.withheld == .versionUnreadable)
    }

    /// The root's binary decides the click, never the verdict: another signer's
    /// build withholds as `.wrongSigner`; an unsigned, ad hoc or quarantined one
    /// as `.unverified`, which hands the command out to copy (D5.2, as bub's
    /// row does); no binary as `.updaterMissing`. The update stays reported.
    /// Mutation: make the trust gate `.unknown`; run an untrusted binary.
    @Test func anUntrustedBinaryTakesOnlyTheClickAway() {
        let other = Self.status(root: Self.root(trust: .untrusted(.otherSigner)))
        #expect(other.state == .updateAvailable)
        #expect(other.oneClick == nil)
        #expect(other.withheld == .wrongSigner)
        #expect(CLIToolWording.reason(.wrongSigner, of: other) == "Not signed by ZZ Corp")

        let unsigned = Self.status(root: Self.root(trust: .untrusted(.unsigned)))
        #expect(unsigned.withheld == .unverified)
        #expect(unsigned.commandToCopy == Self.upgrade(Self.item()))
        #expect(!unsigned.joinsUpdateAll)

        let quarantined = Self.status(root: Self.root(trust: .quarantined))
        #expect(quarantined.withheld == .unverified)
        #expect(quarantined.note?.contains("quarantined") == true)
        #expect(quarantined.managedItem?.binaryTrust == .quarantined)
        // Only the flag held it back, so it is not "not ZZ Corp's build" (review round 1).
        #expect(CLIToolWording.reason(.unverified, of: quarantined) == "Quarantined, so not run")
        #expect(CLIToolWording.reason(.unverified, of: unsigned) == "Not the build ZZ Corp published")

        let missing = Self.status(root: Self.root(trust: nil))
        #expect(missing.withheld == .updaterMissing)
        #expect(missing.oneClick == nil)
        #expect(CLIToolWording.reason(.updaterMissing, of: missing) == "ZZ Fake tools’s program wasn’t found")

        for trust in [ManagedRoot.Trust.homebrewKeg, .verifiedHash, .exempt(reason: "nvm.sh is bash")] {
            #expect(Self.status(root: Self.root(trust: trust)).oneClick != nil, "\(trust)")
        }
        // A current row needs no binary: nothing is withheld from it.
        let current = Self.status(Self.item(installed: "20.20.2", within: "20.20.2", overall: nil),
                                  vendorWouldUpgrade: false, root: Self.root(trust: nil))
        #expect(current.state == .upToDate)
        #expect(current.withheld == nil)
    }

    /// The manager already moving the item: offered state, click withheld as
    /// busy, the manager named. Mutation: busy before the trust gate loses the
    /// copy command; busy on a current row.
    @Test func aBusyManagerWithholdsTheClick() {
        let status = Self.status(busy: "zz upgrade is running (pid 7)")
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.withheld == .busy)
        #expect(status.note == "zz upgrade is running (pid 7)")
        #expect(CLIToolWording.reason(.busy, of: status) == "ZZ Fake tools is already changing its items")
        let current = Self.status(Self.item(installed: "20.20.2", within: "20.20.2", overall: nil),
                                  vendorWouldUpgrade: false, busy: "zz upgrade is running (pid 7)")
        #expect(current.withheld == nil)
    }

    /// The GitHub pause reads the manager's rule, not the kind's: a mise-like
    /// manager (`.ourTokenIfAny`) is held back while the token's budget is
    /// closed; a manager with no rule never. Mutation: read
    /// `kind.updaterSpendsGitHubAPI` (nil for `.managed`: never held).
    @Test func theGitHubPauseReadsTheManagersRule() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = now.addingTimeInterval(600)
        let status = Self.status()
        #expect(status.updaterSpendsGitHubAPI == .ourTokenIfAny)
        let held = status.applyingGitHubPause([.token: later], updatersGetOurToken: true, now: now)
        #expect(held.oneClick == nil)
        #expect(held.withheld == .rateLimited)
        #expect(held.identity == status.identity)
        let open = status.applyingGitHubPause([.anonymous: later], updatersGetOurToken: true, now: now)
        #expect(open.oneClick != nil)
        let quiet = ManagerDescriptor(id: ManagerID("zz-quiet"), displayName: "ZZ quiet", signer: nil, logo: nil,
                                      tint: .label, lane: "zz-quiet")
        let item = ManagedItem(descriptor: quiet, root: Self.rootPath, key: "x", name: "x", installPath: Self.rootPath + "/x",
                               shape: .package, installed: "1", latestWithinRequest: "2")
        let quietStatus = ManagedCheck.status(ManagedVerdict(item: item, vendorWouldUpgrade: true), root: Self.root(),
                                              upgrade: Self.upgrade(item), unpin: nil)
        #expect(quietStatus.applyingGitHubPause([.token: later, .anonymous: later], updatersGetOurToken: true, now: now).oneClick != nil)
    }

    // MARK: ManagedProvider

    /// The scan is the adapter's, one sighting per item by identity, with the
    /// item's name and state. Mutation: sight by `installPath`; drop `name`.
    @Test func theScanSightsEachItemByIdentity() async {
        let adapter = FakeAdapter()
        let sightings = await Self.provider(adapter, runs: Runs()).scan()
        #expect(sightings.count == 1)
        #expect(sightings[0].kind == .managed)
        #expect(sightings[0].identity == Self.item().identity)
        #expect(sightings[0].path == Self.item().installPath)
        #expect(sightings[0].name == "node")
        #expect(sightings[0].version == "20.10.0")
        #expect(sightings[0].state == "core:node|20.10.0")
    }

    /// The check puts the adapter's verdicts through `ManagedCheck`, under the
    /// manager's context, with the scan's own sightings — so an open of the
    /// popover compares like with like. Mutation: build the report's sightings
    /// from the statuses (no state, no name).
    @Test func theCheckReportsUnderTheManagersContext() async {
        let adapter = FakeAdapter()
        let provider = Self.provider(adapter, runs: Runs())
        let report = await provider.check()
        #expect(report.kind == .managed)
        #expect(report.statuses.map(\.identity) == [Self.item().identity])
        #expect(report.statuses[0].state == .updateAvailable)
        #expect(report.statuses[0].oneClick == Self.upgrade(Self.item()))
        let scanned = await provider.scan()
        #expect(report.sightings == scanned)
        guard case .managed(let context) = report.context else { Issue.record("not a managed context"); return }
        #expect(context.descriptor == Self.descriptor)
        #expect(context.roots == [Self.root()])
        #expect(context.headerSummary(home: Self.home.path) == "zz 1.0.0 · ~/.local/share/zz")

        adapter.scanResult = .empty
        let empty = await provider.check()
        #expect(empty.statuses.isEmpty)
        #expect(empty.sightings.isEmpty)
    }

    /// The update runs the adapter's command in an environment built from
    /// scratch — `HOME`, the command's `PATH`, `NO_COLOR`, the proxy, the
    /// adapter's own variables — never the inherited one, and settles on the
    /// adapter's re-read. Mutations: start from `ProcessInfo.environment`;
    /// drop the adapter's variables; settle on nil.
    @Test func theUpdateRunsTheCommandInAnEnvironmentBuiltFromScratch() async throws {
        let adapter = FakeAdapter()
        let runs = Runs()
        let provider = Self.provider(adapter, runs: runs)
        let status = try #require(await provider.check().statuses.first)
        let outcome = await provider.update(status) { _ in }
        #expect(outcome == .updated(version: "20.20.2"))
        let ran = await runs.runs
        #expect(ran.count == 1)
        #expect(ran[0].command == Self.upgrade(Self.item()))
        let environment = ran[0].environment
        #expect(environment["HOME"] == Self.home.path)
        #expect(environment["PATH"] == CLIToolCommandRunner.path(prefix: Self.rootPath + "/shims"))
        #expect(environment["NO_COLOR"] == "1")
        #expect(environment["ZZ_DATA_DIR"] == Self.rootPath)
        #expect(environment["https_proxy"] == "http://zz.invalid:3128")
        #expect(Set(environment.keys) == ["HOME", "PATH", "NO_COLOR", "ZZ_DATA_DIR", "https_proxy"])
    }

    /// The gates are re-asked at the click: the item moved since the check,
    /// the manager busy, the binary no longer trusted, the command no longer
    /// the one checked — nothing runs. Mutation: drop any one guard.
    @Test func theUpdateReasksEveryGateAtTheClick() async throws {
        let adapter = FakeAdapter()
        let runs = Runs()
        let provider = Self.provider(adapter, runs: runs)
        let status = try #require(await provider.check().statuses.first)

        adapter.scanResult = ManagedScan(roots: [Self.root()], items: [Self.item(installed: "20.20.2")])
        guard case .failed(let moved, _) = await provider.update(status, progress: { _ in }) else {
            Issue.record("ran on a moved version"); return
        }
        #expect(moved.hasPrefix("not run:"))

        adapter.scanResult = ManagedScan(roots: [Self.root(trust: .quarantined)], items: [Self.item()])
        guard case .failed(let untrusted, _) = await provider.update(status, progress: { _ in }) else {
            Issue.record("ran a quarantined binary"); return
        }
        #expect(untrusted.hasPrefix("not run:"))

        adapter.scanResult = ManagedScan(roots: [], items: [Self.item()])
        guard case .failed = await provider.update(status, progress: { _ in }) else {
            Issue.record("ran without a root"); return
        }

        adapter.scanResult = ManagedScan(roots: [Self.root()], items: [Self.item()])
        adapter.busyLine = "zz upgrade is running (pid 7)"
        #expect(await provider.update(status, progress: { _ in }) == .busy("zz upgrade is running (pid 7)"))
        adapter.busyLine = nil

        adapter.environment = [:]
        let stale = CLIToolStatus(
            kind: .managed, path: status.path, identity: status.identity, installedVersion: status.installedVersion,
            latestVersion: status.latestVersion, channel: nil, state: .updateAvailable,
            oneClick: CLIToolCommand(executable: Self.binaryPath, arguments: ["upgrade", "node@latest"], pathPrefix: nil),
            withheld: nil, note: nil, name: "node", detail: status.detail)
        guard case .failed = await provider.update(stale, progress: { _ in }) else {
            Issue.record("ran a command other than the adapter's"); return
        }
        #expect(await provider.update(CLIToolsTests.status(), progress: { _ in }) == .notOffered)
        #expect(await runs.runs.isEmpty)
    }

    /// A failed command is the vendor's line, the whole output kept.
    @Test func aFailedCommandCarriesTheVendorsLine() async throws {
        let adapter = FakeAdapter()
        let runs = Runs()
        await runs.set([ManagedProvider.RunResult(succeeded: false, failureMessage: "zz: no such tool (exit 1)", lines: ["a", "zz: no such tool"])])
        let provider = Self.provider(adapter, runs: runs)
        let status = try #require(await provider.check().statuses.first)
        #expect(await provider.update(status, progress: { _ in }) == .failed(message: "zz: no such tool (exit 1)", output: "a\nzz: no such tool"))
    }

    /// A run that exits well but leaves the version where it was is a failure,
    /// with the vendor's output kept — not "updated to" the same version.
    /// Mutation: drop the guard, and this reads `.updated` with the old version.
    @Test func aRunThatMovesNothingIsNotAnUpdate() async throws {
        let adapter = FakeAdapter()
        let runs = Runs()
        await runs.set([ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: ["All tools are up to date"])])
        let provider = Self.provider(adapter, runs: runs)
        let status = try #require(await provider.check().statuses.first)
        let installed = try #require(status.installedVersion)
        adapter.rereadVersion = installed
        guard case .failed(let message, let output) = await provider.update(status, progress: { _ in }) else {
            Issue.record("an unchanged version read as updated"); return
        }
        #expect(message.hasPrefix("not updated: \(status.name ?? "") is still \(installed)"))
        #expect(output == "All tools are up to date")
    }

    /// mise's handoff, shared: a second run with the app's token only when the
    /// adapter opts in, the first run failed and printed the marker, and a
    /// token resolves. Mutations: retry on any failure; hand the token on up
    /// front; retry without a token.
    @Test func theTokenRetryRunsOnceMoreOnlyOnTheVendorsMarker() async throws {
        let marker = "No ZZ token was found"
        let refused = ManagedProvider.RunResult(succeeded: false, failureMessage: "403 (exit 1)", lines: ["WARN " + marker, "ERROR 403"])
        let ok = ManagedProvider.RunResult(succeeded: true, failureMessage: nil, lines: ["Updated"])

        let adapter = FakeAdapter()
        adapter.tokenRetry = ManagedTokenRetry(variable: "ZZ_GITHUB_TOKEN", marker: marker)
        let runs = Runs()
        await runs.set([refused, ok])
        let provider = Self.provider(adapter, runs: runs, token: "ghp_zz")
        let status = try #require(await provider.check().statuses.first)
        #expect(await provider.update(status, progress: { _ in }) == .updated(version: "20.20.2"))
        let ran = await runs.runs
        #expect(ran.count == 2)
        #expect(ran[0].environment["ZZ_GITHUB_TOKEN"] == nil)
        #expect(ran[1].environment["ZZ_GITHUB_TOKEN"] == "ghp_zz")

        // No token resolves: the failure stands, nothing runs again.
        let noToken = Runs()
        await noToken.set([refused, ok])
        let withoutToken = Self.provider(adapter, runs: noToken, token: nil)
        guard case .failed = await withoutToken.update(status, progress: { _ in }) else { Issue.record("retried without a token"); return }
        #expect(await noToken.runs.count == 1)

        // A failure without the marker, or an adapter without the rule: once.
        let other = Runs()
        await other.set([ManagedProvider.RunResult(succeeded: false, failureMessage: "boom", lines: ["boom"]), ok])
        guard case .failed = await Self.provider(adapter, runs: other, token: "ghp_zz").update(status, progress: { _ in }) else { Issue.record("retried on another failure"); return }
        #expect(await other.runs.count == 1)
        adapter.tokenRetry = nil
        let optedOut = Runs()
        await optedOut.set([refused, ok])
        guard case .failed = await Self.provider(adapter, runs: optedOut, token: "ghp_zz").update(status, progress: { _ in }) else { Issue.record("retried without opting in"); return }
        #expect(await optedOut.runs.count == 1)
    }

    /// Release notes go to the adapter by item; a status of another kind gets none.
    @Test func releaseNotesAreTheAdapters() async throws {
        let provider = Self.provider(FakeAdapter(), runs: Runs())
        let status = try #require(await provider.check().statuses.first)
        #expect(try await provider.releaseNotes(for: status, force: false).entries.isEmpty)
    }

    // MARK: ManagedActivity

    /// A running `<binary> <subcommand>` is told by its executable and argv, a
    /// global option before the subcommand looked past; another binary's or
    /// another subcommand's process is not it. Mutation: match by name alone.
    @Test func aRunningSubcommandOfTheBinaryIsBusy() {
        let zz = Self.binaryPath
        let upgrading = NpmActivity.Process(pid: 7, arguments: [zz, "-C", "/x", "upgrade", "node"], executable: zz)
        let listing = NpmActivity.Process(pid: 8, arguments: [zz, "ls", "--json"], executable: zz)
        let other = NpmActivity.Process(pid: 9, arguments: ["/ZZFixture-other/zz", "upgrade"], executable: "/ZZFixture-other/zz")
        let subcommands: Set<String> = ["install", "upgrade", "use"]
        #expect(ManagedActivity.running(binary: zz, subcommands: subcommands, processes: [listing, other, upgrading])
            == "zz upgrade is running (pid 7)")
        #expect(ManagedActivity.running(binary: zz, subcommands: subcommands, processes: [listing, other]) == nil)
    }
}

extension CLIToolProvider {
    /// Whether this is the `ManagedProvider` of `adapter`, for an order test.
    fileprivate func adapterIs(_ adapter: any ManagerAdapter) -> Bool {
        guard let managed = self as? ManagedProvider, let mine = managed.adapter as? ManagedModelTests.FakeAdapter,
              let theirs = adapter as? ManagedModelTests.FakeAdapter else { return false }
        return mine === theirs
    }
}
