import Testing
import Foundation
@testable import DuoUpdaterCore

/// mise at `~/.local/bin/mise`, built out of plain files: a shell script stands
/// in for the binary, with a `SIGNER:` line the injected signature check reads
/// and a `VERSION:` line standing in for what its `--version` prints. Nothing
/// here runs a real mise or reaches the network.
final class MiseSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var mise: URL { home.appendingPathComponent(".local/bin/mise") }
    let versionRuns = DenoSandbox.Counter()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-mise-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mise.deletingLastPathComponent().path)
        try? FileManager.default.removeItem(at: root)
    }

    var scanner: MiseScanner {
        let runs = versionRuns
        return MiseScanner(
            home: home,
            checkSignature: { url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return text.contains("SIGNER:jdx") ? .vendor : .adHoc
            },
            isQuarantined: { url in
                FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path)
            },
            readVersion: { url in
                runs.bump()
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return text.split(separator: "\n").first { $0.hasPrefix("# VERSION:") }
                    .map { String($0.dropFirst("# VERSION:".count)) }
            })
    }

    static func script(version: String = "2026.10.3", signer: String = "jdx", body: String = "") -> String {
        "#!/bin/sh\n# VERSION:\(version)\n# SIGNER:\(signer)\n\(body)\n"
    }

    func install(_ text: String = MiseSandbox.script()) throws {
        try FileManager.default.createDirectory(at: mise.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: mise)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mise.path)
    }
}

@Suite struct MiseTests {

    static func check(_ latest: String = "2026.10.4") -> MiseCheck { MiseCheck(latest: { latest }) }

    static func status(_ box: MiseSandbox, latest: String = "2026.10.4", busy: MiseActivity.Busy? = nil) async throws -> CLIToolStatus {
        await check(latest).status(of: try #require(await box.scanner.scan()), busy: busy)
    }

    // MARK: - Release index

    /// The head of the real `releases.tsv` (2026-10-09), and the clock 55 minutes
    /// after 2026.10.6 was published.
    static let index = """
    v2026.10.6\t1791540753
    v2026.10.5\t1791492621
    v2026.10.4\t1791390100
    v2026.10.3\t1791196527

    """
    static let now = Date(timeIntervalSince1970: 1_791_544_009)

    /// Mutations: drop the age cutoff (2026.10.6 is reported); compare with `<`
    /// (the release exactly a day old is skipped); take the first line rather
    /// than the highest version.
    @Test func latestIsTheNewestReleaseADayOld() async throws {
        func latest(_ text: String, at now: Date = MiseTests.now) async throws -> String {
            try await MiseRelease(fetch: { _ in (Data(text.utf8), 200) }, now: { now }).latest()
        }
        #expect(try await latest(Self.index) == "2026.10.4")
        // Exactly 24 hours after 2026.10.5: eligible, as mise's `<=` has it.
        #expect(try await latest(Self.index, at: Date(timeIntervalSince1970: 1_791_492_621 + 86_400)) == "2026.10.5")
        // Out of order: the highest version wins, not the first line.
        #expect(try await latest("v2026.9.9\t1700000000\nv2026.10.0\t1700000001\n") == "2026.10.0")
        await #expect(throws: MiseRelease.Failure.noneEligible) { try await latest("v2026.10.6\t1791540753\n") }
        await #expect(throws: MiseRelease.Failure.unreadable) { try await latest("v2026.10.6 1791540753 extra\n") }
        await #expect(throws: MiseRelease.Failure.unreadable) { try await latest("<html>\n") }
        await #expect(throws: MiseRelease.Failure.http(404)) {
            try await MiseRelease(fetch: { _ in (Data(), 404) }, now: { MiseTests.now }).latest()
        }
    }

    @Test func versionOrder() {
        #expect(MiseRelease.compare("2026.10.3", "2026.9.18") == .orderedDescending)
        #expect(MiseRelease.compare("2026.10.3", "2026.10.4") == .orderedAscending)
        #expect(!MiseRelease.isVersion("2026.10.3-DEBUG"))
    }

    /// What 2026.10.3's `--version` printed in a scratch HOME.
    @Test func parsesVersionOutput() {
        #expect(MiseScanner.parseVersion("2026.10.3 macos-arm64 (2026-10-05)\n") == "2026.10.3")
        #expect(MiseScanner.parseVersion("2026.10.3-DEBUG macos-arm64 (2026-10-05)") == nil)
        #expect(MiseScanner.parseVersion("") == nil)
    }

    // MARK: - Scanner

    /// Mutation: run `--version` before the signature test.
    @Test func runsOnlyAVendorSignedFile() async throws {
        let box = try MiseSandbox()
        try box.install()
        let install = try #require(await box.scanner.scan())
        #expect(install.version == "2026.10.3" && install.signature == .vendor && install.writable)
        #expect(box.versionRuns.count == 1)

        let adhoc = try MiseSandbox()
        try adhoc.install(MiseSandbox.script(signer: "someone"))
        let other = try #require(await adhoc.scanner.scan())
        #expect(other.version == nil && other.signature == .adHoc)
        #expect(adhoc.versionRuns.count == 0)
    }

    @Test func nothingWithoutMise() async throws {
        #expect(await (try MiseSandbox()).scanner.scan() == nil)
    }

    /// Mutation: drop the `node_modules` test (npm's copy is tracked).
    @Test func aLinkIntoAnotherOwnerIsNotTracked() async throws {
        let box = try MiseSandbox()
        let npm = box.root.appendingPathComponent("prefix/lib/node_modules/@jdxcode/mise/bin/mise")
        try FileManager.default.createDirectory(at: npm.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(MiseSandbox.script().utf8).write(to: npm)
        try FileManager.default.createDirectory(at: box.mise.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: box.mise.path, withDestinationPath: npm.path)
        #expect(await box.scanner.scan() == nil)
        #expect(MiseScanner.isOwnedElsewhere("/opt/homebrew/Cellar/mise/2026.10.3/bin/mise"))
        #expect(MiseScanner.isOwnedElsewhere("/Users/ann/.cargo/bin/mise"))
        #expect(MiseScanner.isOwnedElsewhere("/Users/ann/.local/share/mise/installs/mise/2026.10.3/bin/mise"))
        #expect(!MiseScanner.isOwnedElsewhere("/Users/ann/.local/bin/mise"))
    }

    /// mise's own places, two levels above the binary (`mise_install_base`).
    /// Mutation: drop a candidate path.
    @Test func packagerMarkers() throws {
        for marker in ["lib/.disable-self-update", "lib/mise/.disable-self-update",
                       "lib64/mise/mise-self-update-instructions.toml"] {
            let box = try MiseSandbox()
            try box.install()
            let file = box.home.appendingPathComponent(".local/" + marker)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: Data())
            #expect(MiseScanner.disableMarker(binary: box.mise.path) == file.path)
        }
        let box = try MiseSandbox()
        try box.install()
        #expect(MiseScanner.disableMarker(binary: box.mise.path) == nil)
    }

    // MARK: - Check

    @Test func aSignedCopyBehindIsOffered() async throws {
        let box = try MiseSandbox()
        try box.install()
        let status = try await Self.status(box)
        #expect(status.state == .updateAvailable && status.latestVersion == "2026.10.4")
        #expect(status.oneClick == CLIToolCommand(
            executable: box.mise.path, arguments: ["self-update", "-y", "--no-plugins"], pathPrefix: nil))
        #expect(try await Self.status(box, latest: "2026.10.3").state == .upToDate)
        let ahead = try await Self.status(box, latest: "2026.10.2")
        #expect(ahead.state == .ahead && ahead.oneClick == nil)
    }

    /// Mutations: drop the marker gate; drop the signature gate.
    @Test func gates() async throws {
        let marked = try MiseSandbox()
        try marked.install()
        let marker = marked.home.appendingPathComponent(".local/lib/.disable-self-update")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        let disabled = try await Self.status(marked)
        #expect(disabled.state == .updateAvailable && disabled.oneClick == nil && disabled.withheld == .unsupportedInstaller)

        let unsigned = try MiseSandbox()
        try unsigned.install(MiseSandbox.script(signer: "someone"))
        let wrong = try await Self.status(unsigned)
        #expect(wrong.withheld == .wrongSigner && wrong.oneClick == nil && wrong.state == .unknown)

        let quarantined = try MiseSandbox()
        try quarantined.install()
        FileManager.default.createFile(atPath: quarantined.mise.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path, contents: nil)
        #expect(try await Self.status(quarantined).withheld == .unverified)
        #expect(quarantined.versionRuns.count == 0)

        let busy = try MiseSandbox()
        try busy.install()
        #expect(try await Self.status(busy, busy: .selfUpdate(pid: 3)).withheld == .busy)

        let locked = try MiseSandbox()
        try locked.install()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.mise.deletingLastPathComponent().path)
        let readOnly = try await Self.status(locked)
        #expect(readOnly.withheld == .unsupportedInstaller && readOnly.oneClick == nil)
    }

    @Test func activity() {
        let mise = "/Users/ann/.local/bin/mise"
        let updating = NpmActivity.Process(pid: 5, arguments: [mise, "self-update", "-y"], executable: mise)
        let install = NpmActivity.Process(pid: 6, arguments: [mise, "install", "node"], executable: mise)
        #expect(MiseActivity.selfUpdating(mise: mise, processes: [install]) == nil)
        #expect(MiseActivity.selfUpdating(mise: mise, processes: [install, updating]) == .selfUpdate(pid: 5))
    }

    // MARK: - Release notes

    /// The real 2026.10.6 body's shape, cut down: summary, sections, a bullet
    /// with a fenced example, contributors, the full-changelog link and the
    /// sponsorship appeal. Mutations: drop `skipSections` and the appeal's
    /// heading is styled; parse without `UvChangelog.releaseBody` and the
    /// summary is lost.
    @Test func releaseNotesKeepSectionsAndDropTheTail() throws {
        let body = """
        `[vars]` entries can now ask once per machine.

        ## Added

        - **Per-machine `[vars]` prompts.** Give a var a `prompt`. [#14190](https://github.com/jdx/mise/pull/14190)

          ```toml
          [vars.git_name]
          prompt = "Git author name"
          ```

        - **Local paths in `include`.** `include` now accepts local TOML
          files. [#14178](https://github.com/jdx/mise/pull/14178)

        ## Fixed

        - **Rollback messages.** Name the checkpoint. [#14207](https://github.com/jdx/mise/pull/14207)

        ## New Contributors

        * @someone made their first contribution in [#14184](https://github.com/jdx/mise/pull/14184)

        **Full Changelog**: https://github.com/jdx/mise/compare/v2026.10.5...v2026.10.6

        ## 💚 Sponsor mise

        - If mise saves you time, please consider becoming a sponsor.
        """
        let json: [[String: Any]] = [
            ["tag_name": "v2026.10.6", "prerelease": false, "draft": false, "published_at": "2026-10-09T10:12:33Z", "body": body],
        ]
        let entry = try #require(MiseChangelog.parse(try JSONSerialization.data(withJSONObject: json))?.entries.first)
        #expect(entry.version == "2026.10.6" && entry.date == "2026-10-09")
        let headings = entry.content.compactMap { block -> String? in if case .heading(let h) = block { return h } else { return nil } }
        #expect(headings == ["Added", "Fixed"])
        #expect(entry.items.count == 4)
        #expect(entry.items.first == "`[vars]` entries can now ask once per machine.")
        #expect(entry.items.contains { $0.contains("`include` now accepts local TOML files.") })
        #expect(!entry.items.contains { $0.contains("sponsor") || $0.contains("first contribution") || $0.contains("git_name") })
    }
}
