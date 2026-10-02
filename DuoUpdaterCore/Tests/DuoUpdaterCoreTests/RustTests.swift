import Testing
import Foundation
@testable import DuoUpdaterCore

/// Finding rustup and its toolchains, and the verdict on each row.
///
/// Installs are built in a temporary directory: a "rustup" that is any file
/// (its sha256 is what counts), toolchain directories with a manifest holding
/// just the `[pkg.rust]` table, `update-hashes` beside them. rust-lang's server
/// is a dictionary of URL → body (`Server`); the target triple, quarantine and
/// the process table are injected. Nothing reads the host's `~/.cargo` or
/// `~/.rustup`, or reaches the network.
@Suite struct RustTests {

    // MARK: - Fixtures

    final class Sandbox {
        let root: URL
        var cargo: URL { root.appendingPathComponent("cargo") }
        var rustupHome: URL { root.appendingPathComponent("rustup") }
        var rustup: URL { cargo.appendingPathComponent("bin/rustup") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("rust-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: rustup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: rustupHome.appendingPathComponent("update-hashes"), withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// A rustup whose bytes are `body`; returns its sha256.
        @discardableResult
        func rustup(_ body: String) throws -> String {
            try Data(body.utf8).write(to: rustup)
            return try #require(CLIToolTrust.sha256(of: rustup))
        }

        func toolchain(_ name: String, label: String?, updateHash: String? = nil) throws {
            let lib = rustupHome.appendingPathComponent("toolchains/\(name)/lib/rustlib")
            try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
            if let label {
                try Data(RustTests.manifest(label).utf8)
                    .write(to: lib.appendingPathComponent("multirust-channel-manifest.toml"))
            }
            if let updateHash {
                try Data(updateHash.utf8).write(to: rustupHome.appendingPathComponent("update-hashes/\(name)"))
            }
        }

        func scanner(triple: String? = "aarch64-apple-darwin", quarantined: Bool = false) -> RustScanner {
            RustScanner(cargoHome: cargo, rustupHome: rustupHome,
                        readHostTriple: { _ in triple }, isQuarantined: { _ in quarantined })
        }
    }

    /// A channel manifest with the tables around `[pkg.rust]` the real one has:
    /// `[pkg.rust-std]` sorts before it and must not be read as it.
    static func manifest(_ label: String) -> String {
        """
        manifest-version = "2"
        date = "2026-10-01"

        [pkg.cargo]
        version = "0.100.0 (0123456789 2026-09-20)"

        [pkg.rust-std]
        version = "9.9.9 (aaaaaaaaa 2026-01-01)"

        [pkg.rust]
        version = "\(label)"
        git_commit_hash = "b940084d7eb6a299eb4bfeb8e34901bc051e7ac4"

        [pkg.rust.target.aarch64-apple-darwin]
        available = true

        """
    }

    /// rust-lang's server: URL path → body, anything else 404. Counts requests.
    final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [String: Data] = [:]
        private var hits: [String: Int] = [:]
        var failing = false

        subscript(path: String) -> String? {
            get { lock.withLock { bodies[path].map { String(decoding: $0, as: UTF8.self) } } }
            set { lock.withLock { bodies[path] = newValue.map { Data($0.utf8) } } }
        }

        func requests(_ path: String) -> Int { lock.withLock { hits[path, default: 0] } }

        var release: RustRelease {
            RustRelease(fetch: { url in
                try self.lock.withLock {
                    if self.failing { throw URLError(.notConnectedToInternet) }
                    self.hits[url.path, default: 0] += 1
                    guard let body = self.bodies[url.path] else { throw RustRelease.Failure.http(404) }
                    return body
                }
            })
        }

        func publishRustup(_ version: String, sha: String, latest: Bool = false, triple: String = "aarch64-apple-darwin") {
            self["/rustup/archive/\(version)/\(triple)/rustup-init.sha256"] = "\(sha) *./rustup-init\n"
            if latest { self["/rustup/release-stable.toml"] = "schema-version = '1'\nversion = '\(version)'\n" }
        }

        /// Publishes `label` as `channel`'s manifest and returns its full hash.
        @discardableResult
        func publishChannel(_ channel: String, label: String) -> String {
            let manifest = RustTests.manifest(label)
            self["/dist/channel-rust-\(channel).toml"] = manifest
            let hash = RustTests.sha256(manifest)
            self["/dist/channel-rust-\(channel).toml.sha256"] = "\(hash)  channel-rust-\(channel).toml\n"
            return hash
        }
    }

    static func sha256(_ text: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rust-sha-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data(text.utf8).write(to: url)
        return CLIToolTrust.sha256(of: url) ?? ""
    }

    static let fixtureRustup = "/ZZFixture-rust/cargo/bin/rustup"

    @Test func fixturePathsAreNotOnTheHost() {
        #expect(!FileManager.default.fileExists(atPath: Self.fixtureRustup))
        #expect(!FileManager.default.fileExists(atPath: "/ZZFixture-rust"))
    }

    // MARK: - Toolchain names

    /// Kills the mutation that lets a pinned toolchain through: let `X.Y.Z`
    /// match the `X.Y` pattern, or let a target's parts hold dots, and a pinned
    /// name parses.
    @Test func onlyToolchainsThatFollowAChannelAreKept() {
        for name in ["stable-aarch64-apple-darwin", "beta-aarch64-apple-darwin", "nightly-x86_64-apple-darwin",
                     "1.98-aarch64-apple-darwin", "stable-x86_64-unknown-linux-gnu"] {
            #expect(RustToolchainName.parse(name) != nil, "\(name)")
        }
        #expect(RustToolchainName.parse("1.98-aarch64-apple-darwin")?.channel == "1.98")
        #expect(RustToolchainName.parse("stable-aarch64-apple-darwin")?.target == "aarch64-apple-darwin")
        for name in ["1.98.0-aarch64-apple-darwin", "1.95.0-aarch64-apple-darwin", "nightly-2026-09-01-aarch64-apple-darwin",
                     "stable-2026-09-03-aarch64-apple-darwin", "1.70-beta-aarch64-apple-darwin",
                     "1.70-beta.2-aarch64-apple-darwin", "1.5-aarch64-apple-darwin", "stable", "my-build",
                     "nightly-2026-09-01", "beta-beta-aarch64-apple-darwin"] {
            #expect(RustToolchainName.parse(name) == nil, "\(name)")
        }
    }

    @Test func toolchainVersionLabels() throws {
        let stable = try #require(RustToolchainVersion(label: "1.99.0 (b940084d7 2026-09-28)"))
        #expect(stable.number == "1.99.0")
        #expect(stable.commit == "b940084d7")
        #expect(stable.date == "2026-09-28")
        #expect(stable.display == "1.99.0")
        let nightly = try #require(RustToolchainVersion(label: "1.101.0-nightly (21b707e3f 2026-09-30)"))
        #expect(nightly.display == "1.101.0-nightly (21b707e3f 2026-09-30)")
        #expect(RustToolchainVersion(label: "1.100.0-beta.1 (e3feeb59c 2026-09-27)")?.number == "1.100.0-beta.1")
        #expect(RustToolchainVersion(label: "1.99.0")?.display == "1.99.0")
        #expect(RustToolchainVersion(label: "not a version") == nil)
    }

    // MARK: - Settings

    /// Kills the mutation that reads `auto_self_update` wherever it appears: a
    /// key inside `[overrides]` is a directory path, not the setting.
    @Test func autoSelfUpdateSetting() {
        #expect(RustupSettings.parse("version = \"12\"\nprofile = \"default\"\n\n[overrides]\n").selfUpdateEnabled)
        let disabled = RustupSettings.parse("auto_self_update = \"disable\"\nversion = \"12\"\n")
        #expect(disabled.autoSelfUpdate == "disable")
        #expect(!disabled.selfUpdateEnabled)
        #expect(!RustupSettings.parse("auto_self_update = 'check-only'").selfUpdateEnabled)
        #expect(RustupSettings.parse("auto_self_update = \"enable\" # set by rustup").selfUpdateEnabled)
        #expect(RustupSettings.parse("[overrides]\nauto_self_update = \"disable\"\n").selfUpdateEnabled)
    }

    // MARK: - Reading the disk

    @Test func claimedVersionIsTheUserAgentString() {
        let bytes = Data("xx rustup/abc rustup/1.2 x rustup/ rustup/1.29.1 (aarch64-apple-darwin) rustup/9.9.9 (".utf8)
        #expect(RustScanner.claimedVersion(in: bytes) == "1.29.1")
        #expect(RustScanner.claimedVersion(in: Data("rustup/1.29.1".utf8)) == nil)
    }

    /// Kills the mutation that takes the first `version =` after any `[pkg.rust`
    /// prefix (`[pkg.rust-std]` comes first). A version line cut off by a
    /// partial read is not taken.
    @Test func manifestVersionComesFromPkgRust() throws {
        let manifest = Data(Self.manifest("1.98.1 (48a229cea 2026-09-01)").utf8)
        #expect(RustRelease.packageVersion(in: manifest)?.label == "1.98.1 (48a229cea 2026-09-01)")
        let cut = try #require(String(decoding: manifest, as: UTF8.self).range(of: "1.98.1 (48a"))
        let partial = Data(String(decoding: manifest, as: UTF8.self)[..<cut.upperBound].utf8)
        #expect(RustRelease.packageVersion(in: partial) == nil)
        #expect(RustRelease.packageVersion(in: Data("[pkg.rust-std]\nversion = \"1.0.0\"\n".utf8)) == nil)
    }

    /// Kills the mutation that drops the symlink check: a linked toolchain
    /// named like a channel would be listed.
    @Test func scannerKeepsTrackingToolchainsOnly() throws {
        let box = try Sandbox()
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)",
                          updateHash: "a7c8774a5fd8441c997d\n")
        try box.toolchain("1.98.0-aarch64-apple-darwin", label: "1.98.0 (88d9e12ae 2026-08-18)")
        try box.toolchain("beta-aarch64-apple-darwin", label: nil)
        try box.toolchain("1.97-aarch64-apple-darwin", label: "1.97.1 (aaaaaaaaa 2026-07-15)")
        try box.toolchain("1.99-aarch64-apple-darwin", label: "1.99.0 (b940084d7 2026-09-28)")
        let elsewhere = box.root.appendingPathComponent("local-build")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: box.rustupHome.appendingPathComponent("toolchains/nightly-aarch64-apple-darwin"),
            withDestinationURL: elsewhere)

        let found = box.scanner().toolchains()
        #expect(found.map(\.name.name) == [
            "stable-aarch64-apple-darwin", "beta-aarch64-apple-darwin",
            "1.99-aarch64-apple-darwin", "1.97-aarch64-apple-darwin"])
        #expect(found[0].version?.label == "1.98.1 (48a229cea 2026-09-01)")
        #expect(found[0].updateHash == "a7c8774a5fd8441c997d")
        #expect(found[1].problem == .versionUnreadable)
        #expect(found[1].updateHash == nil)
    }

    @Test func scannerReadsRustup() throws {
        let box = try Sandbox()
        #expect(box.scanner().rustup() == nil)
        let sha = try box.rustup("binary rustup/1.29.0 (aarch64-apple-darwin) more")
        let rustup = try #require(box.scanner().rustup())
        #expect(rustup.path == box.rustup.path)
        #expect(rustup.sha256 == sha)
        #expect(rustup.claimedVersion == "1.29.0")
        #expect(rustup.hostTriple == "aarch64-apple-darwin")
        #expect(rustup.problem == nil)
        try Data().write(to: box.rustup)
        #expect(box.scanner().rustup()?.problem == .notAFile)
    }

    @Test func hostTripleFromMachOHeader() throws {
        let box = try Sandbox()
        func header(_ cpu: UInt32) -> Data {
            var magic = UInt32(0xFEEDFACF), type = cpu
            return Data(bytes: &magic, count: 4) + Data(bytes: &type, count: 4) + Data(count: 24)
        }
        try header(0x0100_000C).write(to: box.rustup)
        #expect(RustScanner.hostTriple(of: box.rustup) == "aarch64-apple-darwin")
        try header(0x0100_0007).write(to: box.rustup)
        #expect(RustScanner.hostTriple(of: box.rustup) == "x86_64-apple-darwin")
        try Data("#!/bin/sh\n".utf8).write(to: box.rustup)
        #expect(RustScanner.hostTriple(of: box.rustup) == nil)
    }

    // MARK: - Busy

    /// Kills the mutation that reads only argv[1]: options before the
    /// subcommand would hide an update.
    @Test func busyMeansARustupCommandThatChangesSomething() {
        func busy(_ argv: [String]) -> RustActivity.Busy? {
            RustActivity.busy(processes: [ClaudeCodeActivity.Process(pid: 42, arguments: argv)])
        }
        #expect(busy(["/Users/u/.cargo/bin/rustup", "update"]) == .rustup("rustup update", pid: 42))
        #expect(busy(["rustup", "-v", "update", "stable"]) == .rustup("rustup update", pid: 42))
        #expect(busy(["rustup", "toolchain", "install", "nightly"]) == .rustup("rustup toolchain install", pid: 42))
        #expect(busy(["rustup", "component", "add", "clippy"]) == .rustup("rustup component add", pid: 42))
        #expect(busy(["rustup", "+nightly", "target", "add", "wasm32-unknown-unknown"]) != nil)
        #expect(busy(["rustup", "self", "update"]) == .rustup("rustup self update", pid: 42))
        #expect(busy(["/Users/u/.cargo/bin/rustup-init", "--self-replace"]) == .rustup("rustup-init", pid: 42))
        #expect(busy(["rustup", "show"]) == nil)
        #expect(busy(["rustup", "check"]) == nil)
        #expect(busy(["rustup", "run", "nightly", "cargo", "update"]) == nil)
        #expect(busy(["rustup", "component", "list"]) == nil)
        #expect(busy(["/Users/u/.cargo/bin/cargo", "update"]) == nil)
    }

    // MARK: - rustup's verdict

    func check(_ server: Server) -> RustCheck { RustCheck(release: server.release) }

    @Test func rustupUpToDateByHash() async throws {
        let box = try Sandbox()
        let server = Server()
        let sha = try box.rustup("rustup 1.29.1 rustup/1.29.1 (")
        server.publishRustup("1.29.1", sha: sha, latest: true)
        let (status, trusted) = await check(server).rustupStatus(
            try #require(box.scanner().rustup()), settings: RustupSettings(), busy: nil)
        #expect(status.state == .upToDate)
        #expect(status.installedVersion == "1.29.1")
        #expect(status.latestVersion == "1.29.1")
        #expect(status.name == "rustup")
        #expect(status.releaseNotesKey == "rustup")
        #expect(status.oneClick == nil)
        #expect(trusted?.version == "1.29.1")
        #expect(trusted?.sha256 == sha)
        // The claim is not consulted when the latest hash already matches.
        #expect(server.requests("/rustup/archive/1.29.0/aarch64-apple-darwin/rustup-init.sha256") == 0)
    }

    @Test func rustupOutdatedIsProvedByItsClaimedVersionsHash() async throws {
        let box = try Sandbox()
        let server = Server()
        let sha = try box.rustup("rustup 1.29.0 rustup/1.29.0 (")
        server.publishRustup("1.29.1", sha: String(repeating: "b", count: 64), latest: true)
        server.publishRustup("1.29.0", sha: sha)
        let (status, trusted) = await check(server).rustupStatus(
            try #require(box.scanner().rustup()), settings: RustupSettings(), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "1.29.0")
        #expect(status.latestVersion == "1.29.1")
        #expect(status.oneClick == CLIToolCommand(executable: box.rustup.path, arguments: ["self", "update"], pathPrefix: nil))
        #expect(trusted?.version == "1.29.0")
        guard case .rust(let item) = status.detail else { Issue.record("not a rust detail"); return }
        #expect(item.kind == .rustup)
        #expect(item.trustedRustup == trusted)
    }

    /// The trust rule. Kills the mutation that takes the claimed version on its
    /// word (or skips the hash comparison): this file says it is 1.29.0, and is
    /// not rust-lang's 1.29.0.
    @Test func rustupThatMatchesNoPublishedHashIsNeverOffered() async throws {
        let box = try Sandbox()
        let server = Server()
        try box.rustup("patched rustup rustup/1.29.0 (")
        server.publishRustup("1.29.1", sha: String(repeating: "b", count: 64), latest: true)
        server.publishRustup("1.29.0", sha: String(repeating: "c", count: 64))
        let (status, trusted) = await check(server).rustupStatus(
            try #require(box.scanner().rustup()), settings: RustupSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .unverified)
        #expect(status.installedVersion == nil)
        #expect(status.oneClick == nil)
        #expect(trusted == nil)
        #expect(status.note?.contains("1.29.0") == true)
    }

    @Test func rustupClaimingAnUnpublishedVersionIsUnverified() async throws {
        let box = try Sandbox()
        let server = Server()
        try box.rustup("rustup/7.7.7 (")
        server.publishRustup("1.29.1", sha: String(repeating: "b", count: 64), latest: true)
        let (status, _) = await check(server).rustupStatus(
            try #require(box.scanner().rustup()), settings: RustupSettings(), busy: nil)
        #expect(status.withheld == .unverified)
        #expect(server.requests("/rustup/archive/7.7.7/aarch64-apple-darwin/rustup-init.sha256") == 1)
    }

    @Test func rustupWithoutAKnownArchitectureIsUnverified() async throws {
        let box = try Sandbox()
        let server = Server()
        let sha = try box.rustup("rustup/1.29.1 (")
        server.publishRustup("1.29.1", sha: sha, latest: true)
        let (status, trusted) = await check(server).rustupStatus(
            try #require(box.scanner(triple: nil).rustup()), settings: RustupSettings(), busy: nil)
        #expect(status.withheld == .unverified)
        #expect(trusted == nil)
    }

    /// Kills the mutation that drops the quarantine gate: this file is
    /// rust-lang's, but quarantined, and is not run.
    @Test func quarantinedRustupIsNotRun() async throws {
        let box = try Sandbox()
        let server = Server()
        let sha = try box.rustup("rustup/1.29.0 (")
        server.publishRustup("1.29.1", sha: String(repeating: "b", count: 64), latest: true)
        server.publishRustup("1.29.0", sha: sha)
        let (status, trusted) = await check(server).rustupStatus(
            try #require(box.scanner(quarantined: true).rustup()), settings: RustupSettings(), busy: nil)
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)
        #expect(trusted == nil)
    }

    @Test func unreachableServerIsNotUnverified() async throws {
        let box = try Sandbox()
        let server = Server()
        server.failing = true
        try box.rustup("rustup/1.29.0 (")
        let (status, _) = await check(server).rustupStatus(
            try #require(box.scanner().rustup()), settings: RustupSettings(), busy: nil)
        #expect(status.withheld == .channelUnreadable)
    }

    /// Kills the mutation that ignores `auto_self_update`.
    @Test func selfUpdateOffIsReportedWithTheCommand() async throws {
        let box = try Sandbox()
        let server = Server()
        let sha = try box.rustup("rustup/1.29.0 (")
        server.publishRustup("1.29.1", sha: String(repeating: "b", count: 64), latest: true)
        server.publishRustup("1.29.0", sha: sha)
        for mode in ["disable", "check-only"] {
            let (status, _) = await check(server).rustupStatus(
                try #require(box.scanner().rustup()), settings: RustupSettings(autoSelfUpdate: mode), busy: nil)
            #expect(status.state == .updateAvailable)
            #expect(status.withheld == .autoUpdateOff)
            #expect(status.oneClick == nil)
            #expect(status.manualCommand == RustCheck.selfUpdate(box.rustup.path))
        }
    }

    /// Kills the mutation that drops the busy gate.
    @Test func busyRustupIsNotOffered() async throws {
        let box = try Sandbox()
        let server = Server()
        let sha = try box.rustup("rustup/1.29.0 (")
        server.publishRustup("1.29.1", sha: String(repeating: "b", count: 64), latest: true)
        server.publishRustup("1.29.0", sha: sha)
        let (status, _) = await check(server).rustupStatus(
            try #require(box.scanner().rustup()), settings: RustupSettings(),
            busy: .rustup("rustup update", pid: 7))
        #expect(status.withheld == .busy)
        #expect(status.oneClick == nil)
    }

    // MARK: - A toolchain's verdict

    static let trusted = RustItem.TrustedRustup(
        path: fixtureRustup, sha256: String(repeating: "a", count: 64), version: "1.29.1",
        hostTriple: "aarch64-apple-darwin")

    func toolchain(_ box: Sandbox, _ name: String = "stable-aarch64-apple-darwin") throws -> RustScanner.Toolchain {
        try #require(box.scanner().toolchains().first { $0.name.name == name })
    }

    /// rustup's own test. Kills the mutation that compares the whole hash (or
    /// none of it): with the first 20 digits equal the channel is unchanged, and
    /// its 900 KB manifest is never downloaded.
    @Test func unchangedChannelHashMeansUpToDateWithoutTheManifest() async throws {
        let box = try Sandbox()
        let server = Server()
        let hash = server.publishChannel("stable", label: "1.98.1 (48a229cea 2026-09-01)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)",
                          updateHash: String(hash.prefix(20)))
        let status = await check(server).toolchainStatus(try toolchain(box), updater: .trusted(Self.trusted), busy: nil)
        #expect(status.state == .upToDate)
        #expect(status.installedVersion == "1.98.1")
        #expect(status.latestVersion == "1.98.1")
        #expect(server.requests("/dist/channel-rust-stable.toml") == 0)
    }

    @Test func movedChannelIsAnUpdateWithRustupsCommand() async throws {
        let box = try Sandbox()
        let server = Server()
        server.publishChannel("stable", label: "1.99.0 (b940084d7 2026-09-28)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)",
                          updateHash: "a7c8774a5fd8441c997d")
        let status = await check(server).toolchainStatus(try toolchain(box), updater: .trusted(Self.trusted), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "1.98.1")
        #expect(status.latestVersion == "1.99.0")
        #expect(status.channel == "stable")
        #expect(status.name == "stable-aarch64-apple-darwin")
        #expect(status.releaseNotesKey == "rust")
        #expect(status.oneClick == CLIToolCommand(
            executable: Self.fixtureRustup, arguments: ["update", "stable-aarch64-apple-darwin", "--no-self-update"],
            pathPrefix: nil))
        guard case .rust(let item) = status.detail else { Issue.record("not a rust detail"); return }
        #expect(item.trustedRustup == Self.trusted)
        #expect(item.path == box.rustupHome.appendingPathComponent("toolchains/stable-aarch64-apple-darwin").path)
    }

    /// A nightly reads as its whole label, so the next night's build is an
    /// update although the number is the same.
    @Test func nightlyComparesWholeLabels() async throws {
        let box = try Sandbox()
        let server = Server()
        server.publishChannel("nightly", label: "1.101.0-nightly (21b707e3f 2026-10-01)")
        try box.toolchain("nightly-aarch64-apple-darwin", label: "1.101.0-nightly (0a1b2c3d4 2026-09-30)",
                          updateHash: "00000000000000000000")
        let status = await check(server).toolchainStatus(
            try toolchain(box, "nightly-aarch64-apple-darwin"), updater: .trusted(Self.trusted), busy: nil)
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "1.101.0-nightly (0a1b2c3d4 2026-09-30)")
        #expect(status.latestVersion == "1.101.0-nightly (21b707e3f 2026-10-01)")
    }

    @Test func reissuedManifestWithTheSameRustIsUpToDate() async throws {
        let box = try Sandbox()
        let server = Server()
        server.publishChannel("1.98", label: "1.98.1 (48a229cea 2026-09-01)")
        try box.toolchain("1.98-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)",
                          updateHash: "ffffffffffffffffffff")
        let status = await check(server).toolchainStatus(
            try toolchain(box, "1.98-aarch64-apple-darwin"), updater: .trusted(Self.trusted), busy: nil)
        #expect(status.state == .upToDate)
        #expect(status.channel == "1.98")
    }

    /// Kills the mutation that offers a toolchain without a trusted rustup.
    @Test func toolchainIsWithheldWithoutATrustedRustup() async throws {
        let box = try Sandbox()
        let server = Server()
        server.publishChannel("stable", label: "1.99.0 (b940084d7 2026-09-28)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)")
        let expectations: [(RustCheck.Updater, CLIToolWithheld)] = [
            (.missing, .updaterMissing), (.untrusted, .unverified), (.unchecked, .channelUnreadable)]
        for (updater, withheld) in expectations {
            let status = await check(server).toolchainStatus(try toolchain(box), updater: updater, busy: nil)
            #expect(status.state == .updateAvailable)
            #expect(status.withheld == withheld)
            #expect(status.oneClick == nil)
        }
        let busy = await check(server).toolchainStatus(
            try toolchain(box), updater: .trusted(Self.trusted), busy: .rustup("rustup-init", pid: 3))
        #expect(busy.withheld == .busy)
        #expect(busy.oneClick == nil)
    }

    /// A channel that stays ahead of the install is downloaded once per
    /// manifest, not on every check. Kills the mutation that files the label
    /// under a hash the downloaded manifest does not have.
    @Test func channelVersionIsKeptByManifestHash() async throws {
        let box = try Sandbox()
        let server = Server()
        server.publishChannel("stable", label: "1.99.0 (b940084d7 2026-09-28)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)")
        let release = server.release
        let check = RustCheck(release: release)
        _ = await check.toolchainStatus(try toolchain(box), updater: .trusted(Self.trusted), busy: nil)
        _ = await check.toolchainStatus(try toolchain(box), updater: .trusted(Self.trusted), busy: nil)
        #expect(server.requests("/dist/channel-rust-stable.toml") == 1)

        // The hash file names one manifest, the server hands out another (the
        // channel moved between the two requests): used, never kept.
        let other = Server()
        other.publishChannel("beta", label: "1.100.0-beta.1 (e3feeb59c 2026-09-27)")
        other["/dist/channel-rust-beta.toml.sha256"] = String(repeating: "d", count: 64) + "  channel-rust-beta.toml"
        try box.toolchain("beta-aarch64-apple-darwin", label: "1.100.0-beta.0 (aaaaaaaaa 2026-09-20)")
        let otherCheck = RustCheck(release: other.release)
        let first = await otherCheck.toolchainStatus(
            try toolchain(box, "beta-aarch64-apple-darwin"), updater: .trusted(Self.trusted), busy: nil)
        #expect(first.latestVersion == "1.100.0-beta.1 (e3feeb59c 2026-09-27)")
        _ = await otherCheck.toolchainStatus(
            try toolchain(box, "beta-aarch64-apple-darwin"), updater: .trusted(Self.trusted), busy: nil)
        #expect(other.requests("/dist/channel-rust-beta.toml") == 2)
    }

    @Test func unreadableToolchainOrChannel() async throws {
        let box = try Sandbox()
        let server = Server()
        try box.toolchain("beta-aarch64-apple-darwin", label: nil)
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)")
        let unreadable = await check(server).toolchainStatus(
            try toolchain(box, "beta-aarch64-apple-darwin"), updater: .trusted(Self.trusted), busy: nil)
        #expect(unreadable.withheld == .versionUnreadable)
        let offline = await check(server).toolchainStatus(try toolchain(box), updater: .trusted(Self.trusted), busy: nil)
        #expect(offline.withheld == .channelUnreadable)
        #expect(offline.state == .unknown)
    }

    // MARK: - The whole report

    @Test func reportHasRustupThenToolchainsAndTheScansSightings() async throws {
        let box = try Sandbox()
        let server = Server()
        let sha = try box.rustup("rustup/1.29.1 (")
        server.publishRustup("1.29.1", sha: sha, latest: true)
        server.publishChannel("stable", label: "1.99.0 (b940084d7 2026-09-28)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)",
                          updateHash: "a7c8774a5fd8441c997d")
        try box.toolchain("1.95.0-aarch64-apple-darwin", label: "1.95.0 (59807616e 2026-04-14)")
        let provider = RustProvider(scanner: box.scanner(), release: server.release, processes: { [] })
        let report = await provider.check()
        #expect(report.statuses.map(\.name) == ["rustup", "stable-aarch64-apple-darwin"])
        #expect(report.statuses.map(\.state) == [.upToDate, .updateAvailable])
        #expect(report.statuses[1].oneClick?.executable == box.rustup.path)
        #expect(report.context == .rust(RustupSettings()))
        #expect(Set(report.sightings) == Set(await provider.scan()))
    }

    /// Kills the mutation that offers toolchains when rustup failed the check.
    @Test func reportWithholdsToolchainsBehindAnUnverifiedRustup() async throws {
        let box = try Sandbox()
        let server = Server()
        try box.rustup("not rust-lang's rustup/1.29.1 (")
        server.publishRustup("1.29.1", sha: String(repeating: "b", count: 64), latest: true)
        server.publishChannel("stable", label: "1.99.0 (b940084d7 2026-09-28)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)")
        let report = await RustProvider(scanner: box.scanner(), release: server.release, processes: { [] }).check()
        #expect(report.statuses.map(\.withheld) == [.unverified, .unverified])
        #expect(report.statuses.allSatisfy { $0.oneClick == nil })
    }

    @Test func reportWithoutRustupWithholdsAsUpdaterMissing() async throws {
        let box = try Sandbox()
        let server = Server()
        server.publishChannel("stable", label: "1.99.0 (b940084d7 2026-09-28)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)")
        let report = await RustProvider(
            scanner: box.scanner(), release: server.release,
            processes: { [ClaudeCodeActivity.Process(pid: 9, arguments: ["rustup", "update"])] }
        ).check()
        #expect(report.statuses.map(\.name) == ["stable-aarch64-apple-darwin"])
        #expect(report.statuses[0].withheld == .updaterMissing)
    }

    @Test func emptyHomesReportNothing() async throws {
        let box = try Sandbox()
        let report = await RustProvider(scanner: box.scanner(), release: Server().release, processes: { [] }).check()
        #expect(report.statuses.isEmpty)
        #expect(report.sightings.isEmpty)
    }
}
