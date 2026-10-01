import Testing
import Foundation
@testable import DuoUpdaterCore

/// Finding uv installs, reading their receipt, the verdict on each, the busy gate
/// and the versions manifest.
///
/// Installs are plain files in a temporary HOME. A file's signature is what its
/// text says (`# vendor`, `# adhoc`, `# other`) through the injected check, its
/// `--version` is the `VERSION` file beside it through the injected reader, and
/// nothing is ever run, signed or fetched.
@Suite struct UvTests {

    // MARK: - Fixtures

    final class Home {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var uv: URL { bin.appendingPathComponent("uv") }
        var uvx: URL { bin.appendingPathComponent("uvx") }
        let verified: UvVerifiedFiles
        let runs = Counter()

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("uv-tests-\(UUID().uuidString)")
            verified = UvVerifiedFiles(fileURL: root.appendingPathComponent("verified.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func file(_ url: URL, signer: String, version: String? = nil) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n# \(signer)\n".utf8).write(to: url)
            if let version {
                try Data(version.utf8).write(to: url.deletingLastPathComponent().appendingPathComponent("VERSION"))
            }
        }

        func receipt(prefix: String? = nil, version: String = "0.9.18", owner: String = "astral-sh", provider: String = "0.30.2") throws {
            let json = """
                {"binaries":["uv","uvx"],"install_layout":"flat","install_prefix":"\(prefix ?? bin.path)",\
                "modify_path":true,"provider":{"source":"cargo-dist","version":"\(provider)"},\
                "source":{"app_name":"uv","name":"uv","owner":"\(owner)","release_type":"github"},"version":"\(version)"}
                """
            let url = UvReceipt.location(home: home)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url)
        }

        var scanner: UvScanner {
            let runs = self.runs
            return UvScanner(
                home: home,
                checkSignature: { url in
                    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    if text.contains("# vendor") { return .vendor }
                    if text.contains("# adhoc") { return .adHoc }
                    if text.contains("# unsigned") { return .unsigned }
                    return .otherSigner
                },
                readVersion: { url in
                    runs.add()
                    return try? String(contentsOf: url.deletingLastPathComponent().appendingPathComponent("VERSION"),
                                       encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                isQuarantined: { url in
                    FileManager.default.fileExists(
                        atPath: url.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path)
                },
                verified: verified)
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func add() { lock.withLock { n += 1 } }
        var count: Int { lock.withLock { n } }
    }

    static func check(latest: String = "0.12.21", asked: Counter? = nil) -> UvCheck {
        UvCheck(latest: { _ in asked?.add(); return latest })
    }

    static func status(_ install: UvInstall, latest: String = "0.12.21", busy: UvActivity.Busy? = nil) async -> CLIToolStatus {
        await check(latest: latest).statuses(of: [install], busy: busy)[0]
    }

    // MARK: - Receipt

    /// This Mac's receipt, 2026-10-01.
    static let realReceipt = """
        {"binaries":["uv","uvx"],"binary_aliases":{},"cdylibs":[],"cstaticlibs":[],"install_layout":"flat",\
        "install_prefix":"/ZZFixture-uv/.local/bin","modify_path":true,"provider":{"source":"cargo-dist","version":"0.30.2"},\
        "source":{"app_name":"uv","name":"uv","owner":"astral-sh","release_type":"github"},"version":"0.9.18"}
        """

    @Test func readsTheInstallersReceipt() throws {
        #expect(!FileManager.default.fileExists(atPath: "/ZZFixture-uv"))
        let receipt = try #require(UvReceipt.parse(Data(Self.realReceipt.utf8)))
        #expect(receipt.installPrefix == "/ZZFixture-uv/.local/bin")
        #expect(receipt.version == "0.9.18")
        #expect(receipt.isOfficial)
        #expect(receipt.isFor(executable: "/ZZFixture-uv/.local/bin/uv"))
        #expect(!receipt.isFor(executable: "/ZZFixture-uv/.cargo/bin/uv"))
        #expect(UvReceipt.parse(Data("{}".utf8)) == nil)
        #expect(UvReceipt.parse(Data("not json".utf8)) == nil)
    }

    /// Kills: dropping any one of the four `source` comparisons in `parse`.
    @Test func onlyAstralsSourceIsOfficial() throws {
        for (key, value) in [("owner", "someone"), ("name", "uv-fork"), ("app_name", "uvx"), ("release_type", "axodotdev")] {
            let edited = Self.realReceipt.replacingOccurrences(
                of: "\"\(key)\":\"\(key == "release_type" ? "github" : key == "owner" ? "astral-sh" : "uv")\"",
                with: "\"\(key)\":\"\(value)\"")
            #expect(edited != Self.realReceipt)
            #expect(try #require(UvReceipt.parse(Data(edited.utf8))).isOfficial == false, "\(key)")
        }
    }

    /// axoupdater's rule: a trailing `bin` on the file's directory is dropped
    /// when the prefix's own last component is not `bin` — a pre-0.5.0 receipt
    /// names `~/.cargo` for `~/.cargo/bin/uv` — and cargo-dist 0.10–0.15 wrote
    /// the prefix with its `bin`, which axoupdater strips.
    @Test func receiptPrefixRulesFollowAxoupdater() throws {
        func receipt(_ prefix: String, provider: String = "0.30.2") throws -> UvReceipt {
            let json = Self.realReceipt
                .replacingOccurrences(of: "/ZZFixture-uv/.local/bin", with: prefix)
                .replacingOccurrences(of: "\"version\":\"0.30.2\"", with: "\"version\":\"\(provider)\"")
            return try #require(UvReceipt.parse(Data(json.utf8)))
        }
        #expect(try receipt("/ZZFixture-uv/.cargo").isFor(executable: "/ZZFixture-uv/.cargo/bin/uv"))
        #expect(try receipt("/ZZFixture-uv/.cargo/bin", provider: "0.12.0").isFor(executable: "/ZZFixture-uv/.cargo/bin/uv"))
        #expect(try receipt("/ZZFixture-uv/.cargo/bin", provider: "0.12.0").installRoot == "/ZZFixture-uv/.cargo")
        #expect(try receipt("/ZZFixture-uv/.cargo/bin", provider: "0.30.2").installRoot == "/ZZFixture-uv/.cargo/bin")
        #expect(try receipt("/ZZFixture-uv/.cargo/bin", provider: "0.30.2").isFor(executable: "/ZZFixture-uv/.cargo/bin/uv"))
        #expect(try !receipt("/ZZFixture-uv/other").isFor(executable: "/ZZFixture-uv/.local/bin/uv"))
    }

    // MARK: - Scanner

    /// An ad hoc copy is never run: its version is the receipt's.
    @Test func adHocStandaloneCopyIsReadFromItsReceipt() async throws {
        let box = try Home()
        try box.file(box.uv, signer: "adhoc", version: "9.9.9")
        try box.file(box.uvx, signer: "adhoc")
        try box.receipt()
        let install = try #require(await box.scanner.scan().first)
        #expect(install.path == box.uv.path)
        #expect(install.layout == .standalone)
        #expect(install.signature == .adHoc)
        #expect(install.version == "0.9.18")
        #expect(install.receiptVersion == "0.9.18")
        #expect(install.uvx == box.uvx.path)
        #expect(install.uvxSignature == .adHoc)
        #expect(install.hashVerdict == nil)
        #expect(box.runs.count == 0)
    }

    /// Kills: running `--version` without the signature gate in `withVersion`.
    @Test func onlyAVendorSignedCopyIsRun() async throws {
        let box = try Home()
        try box.file(box.uv, signer: "vendor", version: "0.12.21")
        try box.receipt(version: "0.12.21")
        let install = try #require(await box.scanner.scan().first)
        #expect(install.version == "0.12.21")
        #expect(box.runs.count == 1)

        try box.file(box.uv, signer: "other", version: "0.12.21")
        let other = try #require(await box.scanner.scan().first)
        #expect(other.signature == .otherSigner)
        #expect(other.version == nil)
        #expect(box.runs.count == 1)
    }

    /// Kills: dropping `!install.quarantined` from `withVersion`.
    @Test func quarantinedCopyIsNotRun() async throws {
        let box = try Home()
        try box.file(box.uv, signer: "vendor", version: "0.12.21")
        try box.receipt(version: "0.12.21")
        try Data().write(to: box.bin.appendingPathComponent("QUARANTINED"))
        let install = try #require(await box.scanner.scan().first)
        #expect(install.quarantined)
        #expect(install.version == nil)
        #expect(box.runs.count == 0)
        #expect(await Self.status(install).withheld == .versionUnreadable)
    }

    /// `uv tool install uv` and pipx leave a link: never `.standalone`, even
    /// with a receipt naming its directory.
    @Test func aLinkIsNotTheStandaloneCopy() async throws {
        let box = try Home()
        let venv = box.home.appendingPathComponent(".local/share/uv/tools/uv/bin/uv")
        try box.file(venv, signer: "vendor", version: "0.12.20")
        try FileManager.default.createSymbolicLink(at: box.uv, withDestinationURL: venv)
        try box.receipt()
        let install = try #require(await box.scanner.scan().first)
        #expect(install.layout == .link)
        #expect(install.executable == venv.resolvingSymlinksInPath().path)
        #expect(install.version == "0.12.20")
        #expect(install.receiptVersion == nil)
    }

    /// Kills: dropping `receipt.isFor(executable:)` from the layout decision.
    @Test func aReceiptForAnotherDirectoryDoesNotMakeItStandalone() async throws {
        let box = try Home()
        try box.file(box.uv, signer: "adhoc")
        try box.receipt(prefix: box.home.appendingPathComponent("elsewhere").path)
        #expect(try #require(await box.scanner.scan().first).layout == .unreceipted)
        try box.receipt(owner: "someone")
        #expect(try #require(await box.scanner.scan().first).layout == .unreceipted)
        try FileManager.default.removeItem(at: UvReceipt.location(home: box.home))
        let bare = try #require(await box.scanner.scan().first)
        #expect(bare.layout == .unreceipted)
        #expect(bare.version == nil)
    }

    @Test func findsTheCargoBinCopyAndEmptyFiles() async throws {
        let box = try Home()
        try Data().write(to: box.uv)
        try box.file(box.home.appendingPathComponent(".cargo/bin/uv"), signer: "adhoc")
        let installs = await box.scanner.scan()
        #expect(installs.map(\.path) == [box.uv.path, box.home.appendingPathComponent(".cargo/bin/uv").path])
        #expect(installs[0].problem == .executableMissing)
        #expect(await Self.status(installs[0]).withheld == .broken)
    }

    /// A click's verdict is looked up for exactly the files it saw. Kills:
    /// comparing paths only (no identity) in `UvVerifiedFiles.verdict`.
    @Test func aHashVerdictLastsUntilTheFileChanges() async throws {
        let box = try Home()
        try box.file(box.uv, signer: "adhoc")
        try box.file(box.uvx, signer: "adhoc")
        try box.receipt()
        let identity = try #require(UvVerifiedFiles.identity(of: box.uv.path, uvx: box.uvx.path))
        box.verified.remember(.differs, for: box.uv.path, identity: identity)
        #expect(try #require(await box.scanner.scan().first).hashVerdict == .differs)
        // Persisted: a second store on the same file reads it back.
        #expect(UvVerifiedFiles(fileURL: box.verified.fileURL).verdict(for: box.uv.path, uvx: box.uvx.path) == .differs)

        // uvx replaced (a new inode): forgotten.
        try FileManager.default.removeItem(at: box.uvx)
        try box.file(box.uvx, signer: "adhoc")
        #expect(try #require(await box.scanner.scan().first).hashVerdict == nil)
    }

    @Test func parsesUvVersionOutput() {
        #expect(UvScanner.parseVersion("uv 0.12.21 (7af826859 2026-09-29 aarch64-apple-darwin)\n") == "0.12.21")
        #expect(UvScanner.parseVersion("uv 0.9.18 (0cee76417 2025-12-16)\n") == "0.9.18")
        #expect(UvScanner.parseVersion("uvx 0.12.21 (7af826859 2026-09-29 aarch64-apple-darwin)") == "0.12.21")
        #expect(UvScanner.parseVersion("ruff 0.12.21") == nil)
        #expect(UvScanner.parseVersion("uv dev") == nil)
        #expect(UvScanner.parseVersion("") == nil)
    }

    @Test func readsTheExecutablesArchitecture() throws {
        let box = try Home()
        func header(_ bytes: [UInt8]) throws -> String? {
            let url = box.root.appendingPathComponent("bin-\(UUID().uuidString)")
            try Data(bytes + [0, 0, 0, 0]).write(to: url)
            return UvScanner.architecture(of: url)
        }
        #expect(try header([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01]) == "aarch64")
        #expect(try header([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01]) == "x86_64")
        #expect(try header([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02]) == nil)
        #expect(try header(Array("#!/bin/sh".utf8)) == nil)
    }

    // MARK: - Check

    static func standalone(
        signature: CLIToolTrust.Signature = .vendor, version: String? = "0.12.20", receipt: String? = "0.12.20",
        hash: UvInstall.HashVerdict? = nil, layout: UvInstall.Layout = .standalone
    ) -> UvInstall {
        UvInstall(
            path: "/ZZFixture-uv/.local/bin/uv", layout: layout, executable: "/ZZFixture-uv/.local/bin/uv",
            version: version, receiptVersion: receipt, signature: signature, uvx: "/ZZFixture-uv/.local/bin/uvx",
            uvxSignature: signature, hashVerdict: hash)
    }

    @Test func vendorSignedCopyIsOfferedSelfUpdate() async {
        let status = await Self.status(Self.standalone())
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == nil)
        #expect(status.latestVersion == "0.12.21")
        #expect(status.oneClick == CLIToolCommand(
            executable: "/ZZFixture-uv/.local/bin/uv", arguments: ["self", "update"], pathPrefix: "/ZZFixture-uv/.local/bin"))
        #expect(status.releaseNotesKey == "uv")
        #expect(status.channel == nil)

        #expect(await Self.status(Self.standalone(version: "0.12.21", receipt: "0.12.21")).state == .upToDate)
        let ahead = await Self.status(Self.standalone(version: "0.12.22", receipt: "0.12.22"))
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    /// Kills: dropping the receipt/run comparison.
    @Test func runVersionMustMatchTheReceipt() async {
        let status = await Self.status(Self.standalone(version: "0.12.20", receipt: "0.12.19"))
        #expect(status.withheld == .versionMismatch)
        #expect(status.oneClick == nil)
    }

    /// An unsigned file whose receipt names a signed release cannot be it.
    /// Kills: dropping the `firstSignedVersion` comparison.
    @Test func unsignedCopyClaimingASignedReleaseIsAMismatch() async {
        let status = await Self.status(Self.standalone(signature: .adHoc, version: "0.12.12", receipt: "0.12.12"))
        #expect(status.withheld == .versionMismatch)
        #expect(status.oneClick == nil)
        let older = await Self.status(Self.standalone(signature: .adHoc, version: "0.12.11", receipt: "0.12.11"))
        #expect(older.withheld == nil)
        #expect(older.oneClick != nil)
    }

    /// Unverified until a click checks it; offered meanwhile, since the click is
    /// what checks it. Kills: dropping the `.differs` gate.
    @Test func unsignedCopyFoundNotToBeTheReleaseIsUnverified() async {
        let fresh = await Self.status(Self.standalone(signature: .adHoc, version: "0.9.18", receipt: "0.9.18"))
        #expect(fresh.oneClick != nil)
        #expect(fresh.installedVersion == "0.9.18")
        let unsigned = await Self.status(Self.standalone(signature: .unsigned, version: "0.9.18", receipt: "0.9.18"))
        #expect(unsigned.oneClick != nil)
        let differs = await Self.status(Self.standalone(signature: .adHoc, version: "0.9.18", receipt: "0.9.18", hash: .differs))
        #expect(differs.state == .updateAvailable)
        #expect(differs.withheld == .unverified)
        #expect(differs.oneClick == nil)
    }

    @Test func otherSignersAreNotRun() async {
        for signature in [CLIToolTrust.Signature.otherSigner, .invalid] {
            let status = await Self.status(Self.standalone(signature: signature, version: nil))
            #expect(status.withheld == .wrongSigner)
            #expect(status.state == .unknown)
        }
    }

    /// Kills: dropping the layout gate (a link offered `self update`).
    @Test func linksAndUnreceiptedCopiesAreReportedOnly() async {
        let link = await Self.status(Self.standalone(receipt: nil, layout: .link))
        #expect(link.state == .updateAvailable)
        #expect(link.withheld == .unsupportedInstaller)
        #expect(link.oneClick == nil)
        let bare = await Self.status(Self.standalone(signature: .adHoc, version: nil, receipt: nil, layout: .unreceipted))
        #expect(bare.state == .unknown)
        #expect(bare.withheld == .unsupportedInstaller)
    }

    /// Kills: dropping the busy gate.
    @Test func busyWithholdsTheClick() async {
        let status = await Self.status(Self.standalone(), busy: .selfUpdate(42))
        #expect(status.withheld == .busy)
        #expect(status.oneClick == nil)
        #expect(status.note == "uv self update is running (pid 42)")
    }

    @Test func channelFailureIsReported() async {
        let status = await UvCheck(latest: { _ in throw UvRelease.Failure.http(503) })
            .statuses(of: [Self.standalone()], busy: nil)[0]
        #expect(status.withheld == .channelUnreadable)
        #expect(status.state == .unknown)
    }

    @Test func manifestIsAskedOncePerArchitecture() async {
        let asked = Counter()
        let check = Self.check(asked: asked)
        let statuses = await check.statuses(of: [Self.standalone(), Self.standalone(layout: .link)], busy: nil)
        #expect(statuses.count == 2)
        #expect(asked.count == 1)
    }

    // MARK: - Activity

    static func process(_ pid: pid_t, _ arguments: String...) -> ClaudeCodeActivity.Process {
        ClaudeCodeActivity.Process(pid: pid, arguments: arguments)
    }

    /// The two shapes in the process table while `uv self update` runs.
    /// Kills: dropping either arm of `busy`.
    @Test func selfUpdateAndItsInstallerAreBusy() {
        #expect(UvActivity.busy(processes: [Self.process(1, "/ZZFixture-uv/.local/bin/uv", "self", "update")]) == .selfUpdate(1))
        #expect(UvActivity.busy(processes: [Self.process(2, "uv", "--verbose", "self", "update")]) == .selfUpdate(2))
        #expect(UvActivity.busy(processes: [Self.process(3, "/bin/sh", "/ZZFixture-tmp/.tmpAbc/uv-installer.sh")]) == .installer(3))
        #expect(UvActivity.busy(processes: [
            Self.process(4, "uv", "pip", "install", "self"),
            Self.process(5, "/ZZFixture-uv/.local/bin/uvx", "self", "update"),
            Self.process(6, "uv", "self", "version"),
            Self.process(7, "/bin/sh", "/ZZFixture/install.sh"),
        ]) == nil)
    }

    @Test func reportAsksTheProcessTableOnlyWhenThereIsAnInstall() async {
        let asked = Counter()
        let empty = await UvProvider.report(installs: [], processes: { asked.add(); return [] }, check: Self.check())
        #expect(empty.statuses.isEmpty)
        #expect(asked.count == 0)
        let one = await UvProvider.report(
            installs: [Self.standalone()],
            processes: { asked.add(); return [Self.process(9, "uv", "self", "update")] }, check: Self.check())
        #expect(asked.count == 1)
        #expect(one.statuses[0].withheld == .busy)
        #expect(one.context == .uv)
        #expect(one.sightings[0].state.hasPrefix("standalone|vendor|vendor|-|-|0.12.20|-|"))
    }

    // MARK: - Versions manifest

    static func line(_ version: String, platforms: [String] = ["aarch64-apple-darwin", "x86_64-apple-darwin"]) -> String {
        let artifacts = platforms.map {
            "{\"platform\":\"\($0)\",\"variant\":\"default\",\"url\":\"https://ZZFixture/\($0).tar.gz\",\"sha256\":\"00\"}"
        }
        return "{\"version\":\"\(version)\",\"date\":\"2026-09-29T21:14:06Z\",\"artifacts\":[\(artifacts.joined(separator: ","))]}"
    }

    /// uv's own rule. Kills: taking the first line whatever its artifacts.
    @Test func manifestFirstLineWithThePlatformWins() {
        let data = Data((Self.line("0.12.21", platforms: ["x86_64-unknown-linux-gnu"]) + "\n"
            + Self.line("0.12.20") + "\n" + Self.line("0.12.19") + "\n").utf8)
        #expect(UvRelease.firstVersion(in: data, platform: "aarch64-apple-darwin") == "0.12.20")
        #expect(UvRelease.firstVersion(in: Data((Self.line("0.12.21") + "\n").utf8), platform: "x86_64-apple-darwin") == "0.12.21")
        // Cut off by the byte limit mid-line: not read.
        let cut = Data((Self.line("0.12.21", platforms: []) + "\n" + String(Self.line("0.12.20").prefix(40))).utf8)
        #expect(UvRelease.firstVersion(in: cut, platform: "aarch64-apple-darwin") == nil)
        #expect(UvRelease.firstVersion(in: Data("<html>".utf8), platform: "aarch64-apple-darwin") == nil)
        #expect(UvRelease.firstVersion(in: Data((Self.line("0.13.0rc1") + "\n").utf8), platform: "aarch64-apple-darwin") == nil)
    }

    @Test func manifestFallsBackToGitHub() async throws {
        let asked = Counter()
        let release = UvRelease(head: { url in
            asked.add()
            if url == UvRelease.manifests[0] { throw UvRelease.Failure.http(522) }
            return Data((Self.line("0.12.21") + "\n").utf8)
        })
        #expect(try await release.latest(arch: "aarch64") == "0.12.21")
        #expect(asked.count == 2)
        let broken = UvRelease(head: { _ in Data("nope".utf8) })
        await #expect(throws: UvRelease.Failure.unreadable) { try await broken.latest(arch: "aarch64") }
    }
}
