import Testing
import Foundation
@testable import DuoUpdaterCore

/// OpenCode built out of plain files, laid out as its installer lays it out
/// (2026-10-04). The binary is a shell script whose text carries the user-agent
/// literal the scanner reads and a `SIGNER:` line the injected signature check
/// reads.
final class OpencodeSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var binary: URL { home.appendingPathComponent(".opencode/bin/opencode") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("opencode-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var scanner: OpencodeScanner {
        OpencodeScanner(
            home: home,
            checkSignature: { url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.contains("SIGNER:anomaly") { return .vendor }
                if text.contains("SIGNER:adhoc") { return .adHoc }
                return .otherSigner
            },
            readArchitecture: { _ in "arm64" })
    }

    @discardableResult
    func write(_ url: URL, _ text: String, executable: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    static func script(version: String, signer: String = "adhoc") -> String {
        "#!/bin/sh\n# --user-agent=opencode/\(version) --use-system-ca --\n# SIGNER:\(signer)\necho opencode \(version)\ntouch \"$HOME/RAN\"\n"
    }

    func install(_ version: String = "1.18.33", signer: String = "adhoc") throws {
        try write(binary, Self.script(version: version, signer: signer), executable: true)
    }
}

@Suite struct OpencodeTests {

    static func check(_ latest: String = "1.18.34") -> OpencodeCheck { OpencodeCheck(latest: { _ in latest }) }

    static func status(
        _ box: OpencodeSandbox, latest: String = "1.18.34", settings: OpencodeSettings = OpencodeSettings(),
        busy: OpencodeActivity.Busy? = nil
    ) async throws -> CLIToolStatus {
        let install = try #require(box.scanner.scan().map(box.scanner.withSignature))
        return await check(latest).status(of: install, settings: settings, busy: busy)
    }

    // MARK: - Scanner

    @Test func readsTheVersionWithoutRunningIt() throws {
        let box = try OpencodeSandbox()
        try box.install()
        let install = try #require(box.scanner.scan())
        #expect(install.path == box.binary.path)
        #expect(install.version == "1.18.33")
        #expect(install.architecture == "arm64")
        #expect(install.problem == nil)
        #expect(install.signature == nil)
        #expect(box.scanner.withSignature(install).signature == .adHoc)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    /// Mutations: accept literals that disagree; read past the space.
    @Test func compiledVersionShapes() {
        func read(_ text: String) -> String? { OpencodeScanner.compiledVersion(in: Data(text.utf8)) }
        #expect(read("x --user-agent=opencode/1.18.34 --use-system-ca") == "1.18.34")
        #expect(read("--user-agent=opencode/1.19.0-beta.2\"") == "1.19.0-beta.2")
        #expect(read("--user-agent=opencode/1.18.34 a --user-agent=opencode/1.18.34 b") == "1.18.34")
        #expect(read("--user-agent=opencode/1.18.34 a --user-agent=opencode/1.18.33 b") == nil)
        #expect(read("--user-agent=opencode/garbage x") == nil)
        #expect(read("no literal") == nil)
    }

    @Test func nothingAndBroken() throws {
        let box = try OpencodeSandbox()
        #expect(box.scanner.scan() == nil)
        try box.write(box.binary, "#!/bin/sh\n# no literal\n", executable: true)
        #expect(box.scanner.scan()?.problem == .versionUnreadable)
        try FileManager.default.removeItem(at: box.binary)
        try FileManager.default.createSymbolicLink(atPath: box.binary.path, withDestinationPath: "/nowhere/opencode")
        #expect(box.scanner.scan()?.problem == .executableMissing)
    }

    // MARK: - Settings

    /// Mutations: treat `"notify"` as off; ignore `opencode.jsonc`'s comments.
    @Test func autoupdateFalseIsOffAndOnlyThat() throws {
        #expect(OpencodeSettings.parse(Data(#"{"autoupdate": false}"#.utf8)) == OpencodeSettings(autoUpdate: false))
        #expect(OpencodeSettings.parse(Data(#"{"autoupdate": "notify"}"#.utf8)) == OpencodeSettings(autoUpdate: true))
        #expect(OpencodeSettings.parse(Data(#"{"autoupdate": true}"#.utf8)) == OpencodeSettings(autoUpdate: true))
        #expect(OpencodeSettings.parse(Data(#"{"autoupdate": 0}"#.utf8)) == OpencodeSettings(autoUpdate: true))
        #expect(OpencodeSettings.parse(Data(#"{"model": "x"}"#.utf8)) == nil)
        let box = try OpencodeSandbox()
        #expect(OpencodeSettings.read(home: box.home).autoUpdate)
        try box.write(box.home.appendingPathComponent(".config/opencode/opencode.jsonc"), """
            {
              // keep it pinned
              "$schema": "https://opencode.ai/config.json",
              "autoupdate": false,
            }
            """)
        #expect(!OpencodeSettings.read(home: box.home).autoUpdate)
    }

    // MARK: - Release

    static func latestAnswer(tag: String = "v1.18.34", assets: [String] = ["opencode-darwin-arm64.zip"]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "assets": assets.map { ["name": $0] }])
    }

    @Test func latestIsTheReleaseWithThisMacsZip() async throws {
        let release = OpencodeRelease(fetch: { url, _ in
            #expect(url == OpencodeRelease.latestURL)
            return (Self.latestAnswer(), 200)
        })
        #expect(try await release.latest(architecture: "arm64") == "1.18.34")
        await #expect(throws: OpencodeRelease.Failure.noBuild("opencode-darwin-x64.zip")) {
            try await release.latest(architecture: "x64")
        }
        await #expect(throws: OpencodeRelease.Failure.unreadable) {
            try await OpencodeRelease(fetch: { _, _ in (Self.latestAnswer(tag: "1.18.34"), 200) }).latest(architecture: "arm64")
        }
        await #expect(throws: OpencodeRelease.Failure.http(403)) {
            try await OpencodeRelease(fetch: { _, _ in (Data(), 403) }).latest(architecture: "arm64")
        }
    }

    /// v1.18.34's body, shortened. Mutation: keep the credits.
    @Test func notesDropTheCreditsAndPrereleases() throws {
        let body = """
            ## Core

            ### Bugfixes
            - Send namespaced session and parent-session identity headers with model requests.
            - Sign macOS CLI release binaries with a Developer ID.

            **Thank you to 3 community contributors:**
            - @dc85:
              - docs(web): correct GPT 6.1 Sol cache pricing (#52176)
            """
        let list: [[String: Any]] = [
            ["tag_name": "v1.18.33", "body": "- Fix a crash.", "published_at": "2026-09-29T10:00:00Z"],
            ["tag_name": "v1.18.34", "body": body, "published_at": "2026-09-30T22:39:45Z"],
            ["tag_name": "v1.19.0-beta.1", "prerelease": true, "body": "- beta"],
            ["tag_name": "v1.18.32", "body": "**Thank you to 1 community contributor:**\n- @x"],
        ]
        let changelog = try #require(OpencodeRelease.parseNotes(try JSONSerialization.data(withJSONObject: list)))
        #expect(changelog.entries.map(\.version) == ["1.18.34", "1.18.33"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.date == "2026-09-30")
        #expect(newest.items == [
            "Send namespaced session and parent-session identity headers with model requests.",
            "Sign macOS CLI release binaries with a Developer ID.",
        ])
        #expect(OpencodeRelease.parseNotes(Data("{}".utf8)) == nil)
    }

    // MARK: - Check

    @Test func anAdHocCopyIsOfferedThePinnedInstaller() async throws {
        let box = try OpencodeSandbox()
        try box.install("1.18.15")
        let status = try await Self.status(box)
        #expect(status.kind == .opencode)
        #expect(status.state == .updateAvailable)
        #expect(status.channel == "latest")
        #expect(status.oneClick?.display
            == "curl -fsSL https://opencode.ai/install | bash -s -- --version 1.18.34 --no-modify-path")
    }

    /// Mutations: drop a gate; offer a click to `.ahead`.
    @Test func gates() async throws {
        let box = try OpencodeSandbox()
        try box.install("1.18.33")
        #expect(try await Self.status(box, latest: "1.18.33").state == .upToDate)
        #expect(try await Self.status(box, latest: "1.18.20").state == .ahead)
        #expect(try await Self.status(box, latest: "1.18.20").oneClick == nil)
        let off = try await Self.status(box, settings: OpencodeSettings(autoUpdate: false))
        #expect(off.withheld == .autoUpdateOff)
        #expect(off.oneClick == nil)
        #expect(off.manualCommand?.display
            == "curl -fsSL https://opencode.ai/install | bash -s -- --version 1.18.34 --no-modify-path")
        #expect(try await Self.status(box, busy: .download(3)).withheld == .busy)
        let install = try #require(box.scanner.scan())
        let unreadable = await OpencodeCheck(latest: { _ in throw OpencodeRelease.Failure.http(502) })
            .status(of: install, settings: OpencodeSettings(), busy: nil)
        #expect(unreadable.withheld == .channelUnreadable)
    }

    // MARK: - Activity

    static func process(_ pid: pid_t, _ arguments: [String]) -> NpmActivity.Process {
        NpmActivity.Process(pid: pid, arguments: arguments, executable: nil)
    }

    /// The installer's download as its curl ran on 2026-10-04, its temporary
    /// directory, and DuoUpdater's own run. Mutations: drop any one signal;
    /// count a directory whose pid is gone.
    @Test func theInstallerIsBusy() throws {
        let box = try OpencodeSandbox()
        let tmp = box.root.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        #expect(OpencodeActivity.busy(processes: [], temporaryDirectories: [tmp]) == nil)
        #expect(OpencodeActivity.busy(processes: [Self.process(4, [
            "curl", "-#", "-L", "-o", "/var/folders/x/T/opencode_install_99/opencode-darwin-arm64.zip",
            "https://github.com/anomalyco/opencode/releases/download/v1.18.34/opencode-darwin-arm64.zip",
        ])], temporaryDirectories: []) == .download(4))
        #expect(OpencodeActivity.busy(processes: [Self.process(5, ["curl", "https://example.com/opencode"])],
                                      temporaryDirectories: []) == nil)
        #expect(OpencodeActivity.busy(processes: [Self.process(6, ["/bin/bash", "/tmp/duo/opencode-install.sh", "--version"])],
                                      temporaryDirectories: []) == .installer(6))
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("opencode_install_77"), withIntermediateDirectories: true)
        #expect(OpencodeActivity.busy(processes: [], temporaryDirectories: [tmp], isAlive: { $0 == 77 }) == .installer(77))
        #expect(OpencodeActivity.busy(processes: [], temporaryDirectories: [tmp], isAlive: { _ in false }) == nil)
    }
}
