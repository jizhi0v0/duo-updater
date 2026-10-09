import Testing
import Foundation
@testable import DuoUpdaterCore

/// Deno at `~/.deno/bin/deno`, built out of plain files: a shell script stands in
/// for the binary, carrying the `Deno/<version>+<hash>` literal the scanner
/// reads, a `SIGNER:` line the injected signature check reads, and a `REPORT:`
/// line standing in for what its `--version` prints. Nothing here runs a real
/// deno or reaches the network.
final class DenoSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var deno: URL { home.appendingPathComponent(".deno/bin/deno") }
    let versionRuns = Counter()

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var count: Int { lock.withLock { n } }
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-deno-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deno.deletingLastPathComponent().path)
        try? FileManager.default.removeItem(at: root)
    }

    var scanner: DenoScanner {
        let runs = versionRuns
        return DenoScanner(
            home: home,
            checkSignature: { url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return text.contains("SIGNER:deno") ? .vendor : (text.contains("SIGNER:adhoc") ? .adHoc : .otherSigner)
            },
            isQuarantined: { url in
                FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path)
            },
            readVersion: { url in
                runs.bump()
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("# REPORT:") }) else { return nil }
                let parts = line.dropFirst("# REPORT:".count).split(separator: ":").map(String.init)
                return parts.count == 2 ? DenoInstall.Reported(version: parts[0], channel: parts[1]) : nil
            })
    }

    static func script(
        version: String = "2.9.6", hash: String = "e518fbd", signer: String = "deno", channel: String? = "stable",
        body: String = ""
    ) -> String {
        "#!/bin/sh\n# Deno/\(version)+\(hash)\n# SIGNER:\(signer)\n"
            + (channel.map { "# REPORT:\(version):\($0)\n" } ?? "") + body + "\n"
    }

    func install(_ text: String = DenoSandbox.script()) throws {
        try FileManager.default.createDirectory(at: deno.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: deno)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deno.path)
    }

    func checked() async throws -> DenoInstall {
        await scanner.checked(try #require(scanner.scan()))
    }
}

@Suite struct DenoTests {

    static func check(_ latest: String = "2.9.7") -> DenoCheck { DenoCheck(latest: { latest }) }

    static func status(_ box: DenoSandbox, latest: String = "2.9.7", busy: DenoActivity.Busy? = nil) async throws -> CLIToolStatus {
        await check(latest).status(of: try await box.checked(), busy: busy)
    }

    // MARK: - Scanner

    @Test func readsTheVersionOutOfTheFileWithoutRunningIt() throws {
        let box = try DenoSandbox()
        try box.install(DenoSandbox.script(body: "touch \"$HOME/RAN\""))
        let install = try #require(box.scanner.scan())
        #expect(install.path == box.deno.path)
        #expect(install.version == "2.9.6")
        #expect(install.revision == "e518fbd")
        #expect(install.signature == nil && install.reported == nil)
        #expect(box.versionRuns.count == 0)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    @Test func nothingWithoutDeno() throws {
        #expect(try DenoSandbox().scanner.scan() == nil)
    }

    /// The shapes seen in real builds (2026-10-09). Mutations: accept a
    /// `Deno/<v>` with no `+<hash>`; accept two literals that disagree.
    @Test func compiledVersionShapes() {
        func read(_ text: String) -> String? {
            let windows = text.components(separatedBy: "Deno/").dropFirst().map { Data(("Deno/" + $0).utf8) }
            return DenoScanner.compiledVersion(in: windows).map { "\($0.version)+\($0.revision)" }
        }
        // 2.9.6: a decoy user agent of another component, and the plain one.
        #expect(read("Deno/0.80.0grpc-timeout … Deno/2.9.6Deno/2.9.6+e518fbdDeno") == "2.9.6+e518fbd")
        // 2.5.0: `denover` runs into the version twice.
        #expect(read("denover2.5.02.5.0+c6adba1Deno/2.5.0+c6adba1x") == "2.5.0+c6adba1")
        #expect(read("Deno/2.0.0-rc.10+c7cba4eDeno/2.0.0-rc.10Failed") == "2.0.0-rc.10+c7cba4e")
        #expect(read("Deno/2.9.7Deno") == nil)
        #expect(read("Deno/2.9.7abcdef1") == nil)
        #expect(read("Deno/2.9.7+0c07124 … Deno/2.9.6+e518fbd") == nil)
        #expect(read("Deno/2.9.7+0c0712") == nil)
        #expect(read("Deno/2.9.7+XYZ1234") == nil)
    }

    @Test func brokenFiles() throws {
        let box = try DenoSandbox()
        try box.install("#!/bin/sh\n# no literal\n")
        #expect(box.scanner.scan()?.problem == .versionUnreadable)
        try FileManager.default.removeItem(at: box.deno)
        try FileManager.default.createSymbolicLink(atPath: box.deno.path, withDestinationPath: "/nowhere/ZZFixture-deno")
        #expect(box.scanner.scan()?.problem == .executableMissing)
    }

    /// Mutation: dropping the `Cellar` (or `.app`) test in `isOwnedElsewhere`
    /// tracks brew's copy as the installer's.
    @Test func aLinkIntoAnotherOwnerIsNotTracked() throws {
        let box = try DenoSandbox()
        let keg = box.root.appendingPathComponent("homebrew/Cellar/deno/2.9.6/bin/deno")
        try FileManager.default.createDirectory(at: keg.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(DenoSandbox.script().utf8).write(to: keg)
        try FileManager.default.createDirectory(at: box.deno.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: box.deno.path, withDestinationPath: keg.path)
        #expect(box.scanner.scan() == nil)
        #expect(DenoScanner.isOwnedElsewhere("/Applications/ZZFixture.app/Contents/MacOS/deno"))
        #expect(DenoScanner.isOwnedElsewhere("/Users/ann/.local/share/mise/installs/deno/2.9.6/bin/deno"))
        #expect(DenoScanner.isOwnedElsewhere("/nix/store/abc-deno/bin/deno"))
        #expect(!DenoScanner.isOwnedElsewhere("/Users/ann/.deno/bin/deno"))
    }

    /// `--version`'s first line, as 2.9.7 printed it in a scratch HOME.
    @Test func parsesVersionOutput() {
        #expect(DenoScanner.parseVersion("deno 2.9.6 (stable, release, aarch64-apple-darwin)\nv8 14.9\ntypescript 6.0.3\n")
            == DenoInstall.Reported(version: "2.9.6", channel: "stable"))
        #expect(DenoScanner.parseVersion("deno 2.9.7+a18ce33 (canary, release, aarch64-apple-darwin)")
            == DenoInstall.Reported(version: "2.9.7", channel: "canary"))
        #expect(DenoScanner.parseVersion("deno 2.9.3 (lts, release, aarch64-apple-darwin)")?.channel == "lts")
        #expect(DenoScanner.parseVersion("deno 2.9.6") == nil)
        #expect(DenoScanner.parseVersion("error: something") == nil)
    }

    @Test func releaseChannelFile() {
        #expect(DenoRelease.parse(Data("v2.9.7\n".utf8)) == "2.9.7")
        #expect(DenoRelease.parse(Data("v2.0.0-rc.10".utf8)) == nil)
        #expect(DenoRelease.parse(Data("<html>".utf8)) == nil)
        #expect(DenoRelease.parse(Data("2.9.7".utf8)) == nil)
    }

    // MARK: - Check

    @Test func aStableSignedBuildBehindIsOffered() async throws {
        let box = try DenoSandbox()
        try box.install()
        let status = try await Self.status(box)
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "2.9.7")
        #expect(status.channel == "stable")
        #expect(status.oneClick == CLIToolCommand(executable: box.deno.path, arguments: ["upgrade"], pathPrefix: nil))
    }

    @Test func upToDateAndAhead() async throws {
        let box = try DenoSandbox()
        try box.install()
        #expect(try await Self.status(box, latest: "2.9.6").state == .upToDate)
        let ahead = try await Self.status(box, latest: "2.9.5")
        #expect(ahead.state == .ahead && ahead.oneClick == nil)
    }

    /// `deno upgrade` would move these to stable. Mutation: drop the channel
    /// guard and the LTS build is offered.
    @Test func otherChannelsAreReportedOnly() async throws {
        for channel in ["lts", "canary"] {
            let box = try DenoSandbox()
            try box.install(DenoSandbox.script(channel: channel))
            let status = try await Self.status(box)
            #expect(status.state == .updateAvailable)
            #expect(status.oneClick == nil)
            #expect(status.withheld == .unsupportedInstaller)
            #expect(status.channel == channel)
        }
        let box = try DenoSandbox()
        try box.install(DenoSandbox.script(version: "2.0.0-rc.10", hash: "c7cba4e", channel: "rc"))
        let rc = try await Self.status(box)
        #expect(rc.withheld == .unsupportedInstaller && rc.oneClick == nil)
    }

    /// Mutation: drop the signature guard and an ad hoc file is offered.
    @Test func trustGates() async throws {
        let signer = try DenoSandbox()
        try signer.install(DenoSandbox.script(signer: "adhoc"))
        let wrong = try await Self.status(signer)
        #expect(wrong.withheld == .wrongSigner && wrong.oneClick == nil)
        #expect(signer.versionRuns.count == 0)

        let quarantined = try DenoSandbox()
        try quarantined.install()
        FileManager.default.createFile(atPath: quarantined.deno.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path, contents: nil)
        let q = try await Self.status(quarantined)
        #expect(q.withheld == .unverified && q.oneClick == nil)
        #expect(quarantined.versionRuns.count == 0)
    }

    /// Mutation: drop the `reported.version == installed` test.
    @Test func versionOutputMustAgreeWithTheBytes() async throws {
        let box = try DenoSandbox()
        try box.install("#!/bin/sh\n# Deno/2.9.6+e518fbd\n# SIGNER:deno\n# REPORT:2.9.5:stable\n")
        let status = try await Self.status(box)
        #expect(status.withheld == .versionMismatch && status.oneClick == nil)
        let silent = try DenoSandbox()
        try silent.install(DenoSandbox.script(channel: nil))
        #expect(try await Self.status(silent).withheld == .versionMismatch)
    }

    @Test func busyAndUnwritableFolder() async throws {
        let box = try DenoSandbox()
        try box.install()
        let busy = try await Self.status(box, busy: .upgrade(pid: 42))
        #expect(busy.withheld == .busy && busy.oneClick == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.deno.deletingLastPathComponent().path)
        let locked = try await Self.status(box)
        #expect(locked.withheld == .unsupportedInstaller && locked.oneClick == nil)
    }

    @Test func channelUnreadable() async throws {
        let box = try DenoSandbox()
        try box.install()
        let status = await DenoCheck(latest: { throw DenoRelease.Failure.http(503) }).status(of: try await box.checked(), busy: nil)
        #expect(status.withheld == .channelUnreadable && status.state == .unknown)
    }

    /// Mutation: match any process of the same binary, not only `upgrade`.
    @Test func activity() {
        let deno = "/Users/ann/.deno/bin/deno"
        let upgrading = NpmActivity.Process(pid: 7, arguments: [deno, "upgrade", "--version", "2.9.7"], executable: deno)
        let running = NpmActivity.Process(pid: 8, arguments: [deno, "run", "main.ts"], executable: deno)
        let other = NpmActivity.Process(pid: 9, arguments: ["deno", "upgrade"], executable: "/opt/homebrew/bin/deno")
        #expect(DenoActivity.upgrading(deno: deno, processes: [running, other]) == nil)
        #expect(DenoActivity.upgrading(deno: deno, processes: [running, upgrading]) == .upgrade(pid: 7))
    }

    // MARK: - Release notes

    /// The real 2.9.7 body's shape, cut down: the wrapped bullets come out
    /// whole, the blog link is not an item, the prerelease is left out.
    @Test func releaseNotesJoinWrappedBullets() throws {
        let body = """
        ### 2.9.7 / 2026.09.16

        Read more: http://deno.com/blog/v2.9

        - fix(audit): honor configured CA stores (#36728)
        - fix(cli): restore optional-value semantics for deno bundle --sourcemap
          (#36723)
        - fix(desktop): complete deferred window close and fix NAPI symbol export on
          Linux (#36718)
        """
        let json: [[String: Any]] = [
            ["tag_name": "v2.9.7", "prerelease": false, "draft": false, "published_at": "2026-09-17T09:04:55Z", "body": body],
            ["tag_name": "v2.9.8-rc.1", "prerelease": true, "draft": false, "body": "- x (#1)"],
        ]
        let changelog = try #require(DenoChangelog.parse(try JSONSerialization.data(withJSONObject: json)))
        #expect(changelog.entries.count == 1)
        let entry = try #require(changelog.entries.first)
        #expect(entry.version == "2.9.7" && entry.date == "2026-09-17")
        #expect(entry.items.count == 3)
        #expect(entry.items.contains { $0.hasPrefix("fix(desktop): complete deferred window close and fix NAPI symbol export on Linux") })
        #expect(!entry.items.contains { $0.contains("Read more") })
    }
}
