import Testing
import Foundation
@testable import DuoUpdaterCore

/// bun and its global install built out of plain files, laid out as bun's
/// installer and `bun add -g` lay them out (1.3.10 / 1.4.1, 2026-10-04), with a
/// Homebrew-shaped node beside them. Shared by the bun suites.
final class BunSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var bun: URL { home.appendingPathComponent(".bun/bin/bun") }
    var global: URL { home.appendingPathComponent(".bun/install/global") }
    var homebrew: URL { root.appendingPathComponent("homebrew") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bun-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// The file's text is what the injected signature check reads.
    var scanner: BunScanner {
        BunScanner(
            home: home,
            checkSignature: { url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.contains("SIGNER:oven") { return .vendor }
                if text.contains("SIGNER:adhoc") { return .adHoc }
                return .otherSigner
            },
            isQuarantined: { url in
                FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path)
            })
    }

    var packages: BunPackages {
        BunPackages(home: home, systemPrefixes: [homebrew], checkNodeSignature: { _ in .adHoc })
    }

    @discardableResult
    func write(_ url: URL, _ text: String, executable: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    /// A stand-in bun: a shell script whose text carries the user-agent literal
    /// the scanner reads, and `body` after it.
    static func script(version: String, revision: String? = "4661e494f", signer: String = "oven", body: String = "") -> String {
        let literal = "bun/\(version)\(revision.map { "+\($0)" } ?? "") npm/? node/v24.3.0"
        return "#!/bin/sh\n# \(literal)\n# SIGNER:\(signer)\n\(body)\n"
    }

    func installBun(_ version: String = "1.4.1", signer: String = "oven", body: String = "") throws {
        try write(bun, Self.script(version: version, signer: signer, body: body), executable: true)
    }

    /// `bun add -g` of each `(name, version)`: the global `package.json`, and each
    /// package's own under `node_modules`, with a `bin`.
    func add(_ packages: [(String, String)], extra: [String: Any] = [:]) throws {
        let dependencies = Dictionary(uniqueKeysWithValues: packages)
        try JSONSerialization.data(withJSONObject: ["dependencies": dependencies]).write(to: {
            try? FileManager.default.createDirectory(at: global, withIntermediateDirectories: true)
            return global.appendingPathComponent("package.json")
        }())
        for (name, version) in packages {
            var manifest: [String: Any] = ["name": name, "version": version, "bin": ["\(name)": "cli.js"]]
            manifest.merge(extra) { $1 }
            let directory = global.appendingPathComponent("node_modules/\(name)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("package.json"))
        }
    }

    /// A dependency's dependency, flattened into `node_modules` as bun does.
    func transitive(_ name: String) throws {
        try write(global.appendingPathComponent("node_modules/\(name)/package.json"),
                  #"{"name":"\#(name)","version":"1.0.0","bin":{"x":"x.js"}}"#)
    }

    /// `<homebrew>/bin/node` → `../Cellar/node/<version>/bin/node`, with brew's receipt.
    func homebrewNode(_ version: String = "26.8.2") throws {
        let keg = homebrew.appendingPathComponent("Cellar/node/\(version)")
        try write(keg.appendingPathComponent("bin/node"), "#!/bin/sh\necho v\(version)\n", executable: true)
        try write(keg.appendingPathComponent("INSTALL_RECEIPT.json"), "{}")
        try FileManager.default.createDirectory(at: homebrew.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: homebrew.appendingPathComponent("bin/node").path, withDestinationPath: "../Cellar/node/\(version)/bin/node")
    }
}

@Suite struct BunTests {

    // MARK: - Scanner

    @Test func readsTheVersionOutOfTheFileWithoutRunningIt() throws {
        let box = try BunSandbox()
        try box.installBun("1.3.10", body: "touch \"$HOME/RAN\"")
        let install = try #require(box.scanner.scan())
        #expect(install.path == box.bun.path)
        #expect(install.version == "1.3.10")
        #expect(install.revision == "4661e494f")
        #expect(install.problem == nil)
        // Measured by the check.
        #expect(install.signature == nil)
        #expect(box.scanner.withSignature(install).signature == .vendor)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    @Test func nothingWithoutBun() throws {
        let box = try BunSandbox()
        #expect(box.scanner.scan() == nil)
    }

    /// Mutations: accept two literals that disagree; keep the `+revision` in the version.
    @Test func compiledVersionShapes() {
        func read(_ text: String) -> String? { BunScanner.compiledVersion(in: Data(text.utf8))?.version }
        #expect(read("x bun/1.4.2+abc123 npm/? node/v24.3.0 y") == "1.4.2")
        #expect(read("bun/1.4.2 npm/? node/v24") == "1.4.2")
        #expect(read("bun/1.4.3-canary.20+abc npm/? node/v24") == "1.4.3-canary.20")
        #expect(read("bun/1.4.2+abc npm/? node/ … bun/1.4.2+abc npm/? node/") == "1.4.2")
        #expect(read("bun/1.4.2 npm/? node/ … bun/1.4.1 npm/? node/") == nil)
        #expect(read("bun/garbage npm/? node/") == nil)
        #expect(read("bun/1.4.2+not-hex! npm/? node/") == nil)
        #expect(read("no literal here") == nil)
    }

    @Test func brokenFiles() throws {
        let box = try BunSandbox()
        try box.write(box.bun, "#!/bin/sh\n# no literal\n", executable: true)
        #expect(box.scanner.scan()?.problem == .versionUnreadable)
        try FileManager.default.removeItem(at: box.bun)
        try FileManager.default.createSymbolicLink(atPath: box.bun.path, withDestinationPath: "/nowhere/bun")
        #expect(box.scanner.scan()?.problem == .executableMissing)
    }

    // MARK: - Packages

    /// Mutations: list `node_modules` instead of `dependencies`; read the node
    /// from the package's own prefix.
    @Test func packagesAreTheGlobalDependenciesHeldAgainstHomebrewsNode() throws {
        let box = try BunSandbox()
        try box.installBun()
        try box.homebrewNode()
        try box.add([("openclaw", "2026.9.7"), ("cowsay", "1.5.0")])
        try box.transitive("left-pad")
        let bun = try #require(box.scanner.scan().map(box.scanner.withSignature))
        let installs = box.packages.scan(bun: bun)
        #expect(installs.map(\.name) == ["cowsay", "openclaw"])
        let openclaw = try #require(installs.last)
        #expect(openclaw.version == "2026.9.7")
        #expect(openclaw.prefix.source == .bun)
        #expect(openclaw.prefix.path == box.global.path)
        #expect(openclaw.bun == BunManager(path: box.bun.path, signature: .vendor))
        #expect(openclaw.runtime.node == box.homebrew.appendingPathComponent("bin/node").path)
        #expect(openclaw.runtime.nodeVersion == "26.8.2")
        #expect(openclaw.runtime.npm == nil)
        #expect(openclaw.runtime.nodeIsTrusted)
        if case .openclaw = openclaw.ownUpdate {} else { Issue.record("openclaw's own update not read") }
    }

    @Test func noNodeOnDiskLeavesTheRuntimeEmpty() throws {
        let box = try BunSandbox()
        try box.installBun()
        try box.add([("cowsay", "1.5.0")])
        let bun = try #require(box.scanner.scan())
        let install = try #require(box.packages.scan(bun: bun).first)
        #expect(install.runtime.node == nil)
        #expect(install.prefix.layoutNodeVersion == nil)
    }

    /// Only the registry keys, never a token; the last one in a file wins.
    @Test func bunfigAndNpmrcRegistries() throws {
        let box = try BunSandbox()
        try box.write(box.home.appendingPathComponent(".bunfig.toml"), """
            [install]
            registry = "https://first.example/"
            registry = "https://registry.example.com/" # ours
            [install.scopes]
            "@acme" = { url = "https://npm.acme.dev/", token = "SECRET" }
            other = "https://other.example/"
            [run]
            registry = "https://not-install.example/"
            """)
        try box.write(box.home.appendingPathComponent(".npmrc"), "registry=https://npmrc.example/\n//x/:_authToken=SECRET\n")
        let entries = BunPackages.registryConfig(home: box.home)
        #expect(entries.map(\.key) == ["@other:registry", "@acme:registry", "registry", "registry", "registry"])
        #expect(entries.map(\.value) == [
            "https://other.example/", "https://npm.acme.dev/", "https://registry.example.com/", "https://first.example/",
            "https://npmrc.example/",
        ])
        #expect(!entries.contains { $0.value.contains("SECRET") })
        #expect(NpmScanner.customRegistry(for: "@acme/cli", in: entries)?.url == "https://npm.acme.dev/")
        #expect(NpmScanner.customRegistry(for: "cowsay", in: entries)?.url == "https://registry.example.com/")
        #expect(BunPackages.registryURL("{ token = \"x\" }") == "(a table)")
    }

    // MARK: - Release

    static func channel(tag: String = "bun-v1.4.2", assets: [String] = ["bun-darwin-aarch64.zip", "bun-darwin-x64.zip"]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "assets": assets.map { ["name": $0] }])
    }

    @Test func latestIsTheUpdaterChannelsTag() async throws {
        let release = BunRelease(fetch: { url in
            #expect(url == BunRelease.channel)
            return (Self.channel(), 200)
        })
        #expect(try await release.latest() == "1.4.2")
        await #expect(throws: BunRelease.Failure.noBuild("bun-darwin-aarch64.zip")) {
            try await BunRelease(fetch: { _ in (Self.channel(assets: ["bun-linux-x64.zip"]), 200) }).latest()
        }
        await #expect(throws: BunRelease.Failure.unreadable) {
            try await BunRelease(fetch: { _ in (Self.channel(tag: "v1.4.2"), 200) }).latest()
        }
        await #expect(throws: BunRelease.Failure.http(403)) {
            try await BunRelease(fetch: { _ in (Data(), 403) }).latest()
        }
        #expect(BunRelease.assetName(.arm64) == "bun-darwin-aarch64.zip")
        #expect(BunRelease.compare("1.4.2-canary.1", "1.4.2") == .orderedAscending)
        #expect(BunRelease.compare("1.10.0", "1.9.9") == .orderedDescending)
    }

    // MARK: - bun's own row

    static func check(_ latest: String = "1.4.2") -> BunCheck { BunCheck(latest: { latest }) }

    static func status(_ box: BunSandbox, latest: String = "1.4.2", busy: BunActivity.Busy? = nil) async throws -> CLIToolStatus {
        let install = try #require(box.scanner.scan().map(box.scanner.withSignature))
        return await check(latest).status(of: install, busy: busy)
    }

    @Test func outdatedSignedBunIsOfferedItsUpgrade() async throws {
        let box = try BunSandbox()
        try box.installBun("1.3.10")
        let status = try await Self.status(box)
        #expect(status.kind == .bun)
        #expect(status.name == "bun")
        #expect(status.state == .updateAvailable)
        #expect(status.channel == "stable")
        #expect(status.oneClick == CLIToolCommand(executable: box.bun.path, arguments: ["upgrade"], pathPrefix: nil))
    }

    /// Mutations: drop any gate; offer a click to `.ahead`.
    @Test func gatesOnBunsOwnRow() async throws {
        let box = try BunSandbox()
        try box.installBun("1.4.2")
        #expect(try await Self.status(box).state == .upToDate)
        #expect(try await Self.status(box, latest: "1.4.1").state == .ahead)
        #expect(try await Self.status(box, latest: "1.4.1").oneClick == nil)

        let adhoc = try BunSandbox()
        try adhoc.installBun("1.3.10", signer: "adhoc")
        #expect(try await Self.status(adhoc).withheld == .wrongSigner)

        let quarantined = try BunSandbox()
        try quarantined.installBun("1.3.10")
        try quarantined.write(quarantined.bun.deletingLastPathComponent().appendingPathComponent("QUARANTINED"), "")
        #expect(try await Self.status(quarantined).withheld == .unverified)

        let busy = try BunSandbox()
        try busy.installBun("1.3.10")
        #expect(try await Self.status(busy, busy: .bun("bun upgrade", pid: 9)).withheld == .busy)

        let canary = try BunSandbox()
        try canary.write(canary.bun, BunSandbox.script(version: "1.4.3-canary.20"), executable: true)
        let row = try await Self.status(canary)
        #expect(row.channel == "canary")
        #expect(row.withheld == .unsupportedInstaller)
        #expect(row.oneClick == nil)
    }

    // MARK: - Package rows

    static let packument = NpmPackument(
        distTags: ["latest": "2026.9.8"],
        versions: ["2026.9.7": .init(node: ">=22"), "2026.9.8": .init(node: ">=24.16.0 <25 || >=26.1.0")])

    static func packageStatus(_ install: NpmInstall, packument: NpmPackument = packument) async -> CLIToolStatus {
        await NpmCheck(packument: { _ in packument }).status(of: install, busy: nil)
    }

    static func cowsay(_ box: BunSandbox, version: String = "1.5.0") throws -> NpmInstall {
        try box.installBun()
        try box.homebrewNode()
        try box.add([("cowsay", version)])
        let bun = try #require(box.scanner.scan().map(box.scanner.withSignature))
        return try #require(box.packages.scan(bun: bun).first)
    }

    /// Mutations: build the npm command for a bun package; report it under `.npm`.
    @Test func aPackageIsInstalledByItsBunAtTheCheckedVersion() async throws {
        let box = try BunSandbox()
        let install = try Self.cowsay(box)
        let status = await Self.packageStatus(install, packument: NpmPackument(
            distTags: ["latest": "1.6.0"], versions: ["1.5.0": .init(), "1.6.0": .init()]))
        #expect(status.kind == .bun)
        #expect(status.name == "cowsay")
        #expect(status.latestVersion == "1.6.0")
        #expect(status.oneClick == CLIToolCommand(
            executable: box.bun.path, arguments: ["add", "-g", "cowsay@1.6.0"],
            pathPrefix: box.bun.deletingLastPathComponent().path))
        guard case .npm(let package) = status.detail else { Issue.record("detail"); return }
        #expect(package.updater == .bun)
    }

    /// openclaw keeps its own update, run by the node found on disk.
    @Test func openclawUnderBunRunsItsOwnUpdate() async throws {
        let box = try BunSandbox()
        try box.installBun()
        try box.homebrewNode()
        try box.add([("openclaw", "2026.9.7")])
        try box.write(box.global.appendingPathComponent("node_modules/openclaw/docs/cli/update.md"),
                      "| `--tag <dist-tag\\|version\\|spec>` | Override the package target |\n")
        let bun = try #require(box.scanner.scan().map(box.scanner.withSignature))
        let install = try #require(box.packages.scan(bun: bun).first)
        let status = await Self.packageStatus(install)
        let node = box.homebrew.appendingPathComponent("bin/node").path
        #expect(status.oneClick == CLIToolCommand(
            executable: node,
            arguments: [box.global.appendingPathComponent("node_modules/openclaw/openclaw.mjs").path, "update", "--tag", "2026.9.8"],
            pathPrefix: box.bun.deletingLastPathComponent().path))
    }

    /// Mutations: drop the node gate (engines would go unchecked); drop the bun
    /// signature or quarantine gate.
    @Test func packageGates() async throws {
        let noNode = try BunSandbox()
        try noNode.installBun()
        try noNode.add([("openclaw", "2026.9.7")])
        let noNodeBun = try #require(noNode.scanner.scan().map(noNode.scanner.withSignature))
        let bare = try #require(noNode.packages.scan(bun: noNodeBun).first)
        let unchecked = await Self.packageStatus(bare)
        #expect(unchecked.withheld == .versionUnreadable)
        #expect(unchecked.oneClick == nil)

        let box = try BunSandbox()
        let install = try Self.cowsay(box)
        let packument = NpmPackument(distTags: ["latest": "1.6.0"], versions: ["1.5.0": .init(), "1.6.0": .init()])
        func with(_ bun: BunManager) -> NpmInstall {
            NpmInstall(path: install.path, name: install.name, version: install.version, manifestName: install.manifestName,
                       prefix: install.prefix, runtime: install.runtime, bun: bun)
        }
        #expect(await Self.packageStatus(with(BunManager(path: box.bun.path, signature: .adHoc)), packument: packument)
            .withheld == .wrongSigner)
        #expect(await Self.packageStatus(with(BunManager(path: box.bun.path, signature: .vendor, quarantined: true)),
                                         packument: packument).withheld == .unverified)
    }

    /// The tag's version needs a newer node than the one found: held back, the
    /// gap said, exactly as for npm.
    @Test func enginesAreHeldAgainstTheNodeFound() async throws {
        let box = try BunSandbox()
        try box.installBun()
        try box.homebrewNode("24.13.0")
        try box.add([("openclaw", "2026.9.7")])
        let bun = try #require(box.scanner.scan().map(box.scanner.withSignature))
        let install = try #require(box.packages.scan(bun: bun).first)
        let status = await Self.packageStatus(install)
        #expect(status.withheld == .runtimeTooOld)
        #expect(status.oneClick == nil)
    }

    // MARK: - Activity

    static func process(_ pid: pid_t, _ arguments: [String], executable: String?) -> NpmActivity.Process {
        NpmActivity.Process(pid: pid, arguments: arguments, executable: executable)
    }

    /// argv as `openclaw update` ran bun on 2026-10-04: `["bun", "add", "-g",
    /// "--trust", "openclaw@2026.9.8"]`, executable the bun binary. Mutations:
    /// match on argv[0]'s name; ignore `-g`.
    @Test func bunChangingTheGlobalInstallIsBusy() throws {
        let box = try BunSandbox()
        let install = try Self.cowsay(box)
        let bun = box.bun.path
        #expect(BunActivity.busy(install, processes: [
            Self.process(5, ["bun", "add", "-g", "--trust", "openclaw@2026.9.8"], executable: bun),
        ]) == .ownUpdater("bun add -g", pid: 5))
        #expect(BunActivity.busy(install, processes: [
            Self.process(6, ["bun", "install"], executable: bun),
            Self.process(7, ["bun", "add", "-g", "x"], executable: "/opt/homebrew/bin/bun"),
            Self.process(8, ["bun", "run", "-g"], executable: bun),
        ]) == nil)
        #expect(BunActivity.upgrading(bun: bun, processes: [Self.process(9, ["bun", "upgrade"], executable: bun)])
            == .bun("bun upgrade", pid: 9))
        #expect(BunActivity.upgrading(bun: bun, processes: [Self.process(9, ["bun", "add", "-g", "upgrade"], executable: bun)])
            == nil)
    }

    // MARK: - Provider

    @Test func reportPutsBunFirstAndItsPackagesUnderItsKind() async throws {
        let box = try BunSandbox()
        let install = try Self.cowsay(box)
        let bun = try #require(box.scanner.scan().map(box.scanner.withSignature))
        let report = await BunProvider.report(
            bun: bun, packages: [install], processes: [], check: Self.check(),
            npm: NpmCheck(packument: { _ in NpmPackument(distTags: ["latest": "1.6.0"], versions: ["1.5.0": .init(), "1.6.0": .init()]) }))
        #expect(report.kind == .bun)
        #expect(report.statuses.map(\.name) == ["bun", "cowsay"])
        #expect(report.statuses.allSatisfy { $0.kind == .bun })
        #expect(report.sightings.map(\.kind) == [.bun, .bun])
        let empty = await BunProvider.report(bun: nil, packages: [], processes: [], check: Self.check(), npm: NpmCheck())
        #expect(empty.statuses.isEmpty)
    }

    // MARK: - openclaw, as both groups read it

    /// Mutation: only the 2026.3 spelling is accepted.
    @Test func openclawDocumentsTagInEitherSpelling() throws {
        let box = try BunSandbox()
        let package = box.root.appendingPathComponent("openclaw")
        try box.write(package.appendingPathComponent("docs/cli/update.md"), "- `--tag <dist-tag|version|spec>`: override\n")
        #expect(OpenClawSettings.read(home: box.home, package: package).supportsTag)
        try box.write(package.appendingPathComponent("docs/cli/update.md"), "| `--tag <dist-tag\\|version\\|spec>` | Override |\n")
        #expect(OpenClawSettings.read(home: box.home, package: package).supportsTag)
        try box.write(package.appendingPathComponent("docs/cli/update.md"), "openclaw update --tag beta\n")
        #expect(!OpenClawSettings.read(home: box.home, package: package).supportsTag)
    }

    /// 2026.9's summary, as a scratch-HOME update printed it.
    @Test func openclawsStagedUpdateFailureIsItsReason() {
        let lines = [
            "Phase: activating",
            "⚠️ OpenClaw update failed: source-rollback-failed.",
            "Phases: requested (17.53s) → staging (6ms) → validating (38.66s) → activating (16.19s)",
            "Failed: package-swap — Exit code: 1; State schema inspection failed (exit) after 0.680 seconds",
            "Failed: gateway recovery verification — Exit code: 1; service management skipped",
            "Next step:",
            "  env OPENCLAW_STATE_DIR='/x' openclaw update status",
        ]
        #expect(NpmUpdater.openclawReason(lines) == "openclaw update: source-rollback-failed (package-swap failed)")
        #expect(NpmUpdater.openclawReason(["Update Result: ERROR", "  Reason: global install verify"])
            == "openclaw update: global install verify")
    }
}
