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

    /// OpenCode 2's literal: channel, version, product (2.2.5's darwin-arm64
    /// build, 2026-10-31).
    static func secondScript(version: String, signer: String = "adhoc") -> String {
        "#!/bin/sh\n# --user-agent=opencode/latest/\(version)/cli --use-system-ca --\n# SIGNER:\(signer)\necho opencode \(version)\ntouch \"$HOME/RAN\"\n"
    }

    /// What each line's binary carries, by the version asked for.
    func install(_ version: String = "1.18.33", signer: String = "adhoc") throws {
        let script = version.hasPrefix("2.")
            ? Self.secondScript(version: version, signer: signer)
            : Self.script(version: version, signer: signer)
        try write(binary, script, executable: true)
    }
}

@Suite struct OpencodeTests {

    static func check(_ latest: String = "1.18.34", two: String? = nil) -> OpencodeCheck {
        OpencodeCheck(latest: { latest }, second: { two })
    }

    static func status(
        _ box: OpencodeSandbox, latest: String = "1.18.34", two: String? = nil,
        settings: OpencodeSettings = OpencodeSettings(), busy: OpencodeActivity.Busy? = nil
    ) async throws -> CLIToolStatus {
        let install = try #require(box.scanner.scan().map(box.scanner.withSignature))
        return await check(latest, two: two).status(of: install, settings: settings, busy: busy)
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

    /// A copy of OpenCode 2 reads too, off its own literal.
    @Test func readsOpenCodeTwosVersionWithoutRunningIt() throws {
        let box = try OpencodeSandbox()
        try box.install("2.2.5")
        let install = try #require(box.scanner.scan())
        #expect(install.version == "2.2.5")
        #expect(install.problem == nil)
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
        // OpenCode 2's: channel, version, product — anchored on "cli", so a path
        // or another product's literal is not read as a version.
        #expect(read("--user-agent=opencode/latest/2.2.5/cli --use-system-ca") == "2.2.5")
        #expect(read("--user-agent=opencode/latest/2.2.5/cli a --user-agent=opencode/1.19.5 b") == nil)
        #expect(read("--user-agent=opencode/latest/x/cli x") == nil)
        #expect(read("--user-agent=opencode/latest/2.2.5/desktop x") == nil)
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

    /// The registry's dist-tag document, as `registry.npmjs.org/opencode-ai/latest`
    /// answers it (2026-10-31).
    static func latestAnswer(version: String = "1.19.5") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "name": "opencode-ai", "version": version, "dist-tags": ["latest": version],
        ])
    }

    @Test func latestIsOpenCodeOnesDistTag() async throws {
        let release = OpencodeRelease(fetch: { url, _ in
            #expect(url == OpencodeRelease.latestURL)
            return (Self.latestAnswer(), 200, nil)
        })
        #expect(try await release.latest() == "1.19.5")
        // Only OpenCode 1's line: a 2.x under this name is the other product, and
        // must not be offered through the 1.x installer, which refuses it.
        await #expect(throws: OpencodeRelease.Failure.unreadable) {
            try await OpencodeRelease(fetch: { _, _ in (Self.latestAnswer(version: "2.2.5"), 200, nil) }).latest()
        }
        await #expect(throws: OpencodeRelease.Failure.unreadable) {
            try await OpencodeRelease(fetch: { _, _ in (Data("{}".utf8), 200, nil) }).latest()
        }
        await #expect(throws: OpencodeRelease.Failure.http(502)) {
            try await OpencodeRelease(fetch: { _, _ in (Data(), 502, nil) }).latest()
        }
    }

    /// `opencode.ai/update/api/latest/cli/npm`, as OpenCode 2's installer reads it.
    /// Mutations: drop a field from the anchor; turn a failure into a version.
    static func secondAnswer(
        version: String = "2.2.5", name: String = "cli", distribution: String = "npm"
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "channel": "latest", "name": name, "distribution": distribution, "version": version, "active": true,
        ])
    }

    @Test func secondLineIsTheVendorsOwnUpdateDocument() async throws {
        let release = OpencodeRelease(fetch: { url, _ in
            #expect(url == OpencodeRelease.secondURL)
            return (Self.secondAnswer(), 200, nil)
        })
        #expect(await release.second() == "2.2.5")
        // Best-effort: anything but a 2.x answer from this endpoint is "no 2.x",
        // never a version the notice would name.
        #expect(await OpencodeRelease(fetch: { _, _ in (Self.secondAnswer(), 500, nil) }).second() == nil)
        #expect(await OpencodeRelease(fetch: { _, _ in throw OpencodeRelease.Failure.http(502) }).second() == nil)
        #expect(await OpencodeRelease(fetch: { _, _ in (Data("{}".utf8), 200, nil) }).second() == nil)
        for stale in [
            Self.secondAnswer(version: "1.19.5"),
            Self.secondAnswer(name: "desktop"),
            Self.secondAnswer(distribution: "github"),
            Self.secondAnswer(version: "latest"),
        ] {
            #expect(await OpencodeRelease(fetch: { _, _ in (stale, 200, nil) }).second() == nil)
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
        let unreadable = await OpencodeCheck(latest: { throw OpencodeRelease.Failure.http(502) })
            .status(of: install, settings: OpencodeSettings(), busy: nil)
        #expect(unreadable.withheld == .channelUnreadable)
        #expect(unreadable.state == .unknown)
    }

    // MARK: - OpenCode 2

    /// 2026-10-31, this machine: 1.19.5 installed, the 1.x channel current, and
    /// OpenCode 2 out — the case the notice exists for. Mutation: give it a
    /// one-click (the 1.x installer exits 1 on a 2.x version).
    @Test func openCodeTwoIsReportedAndNeverClicked() async throws {
        let box = try OpencodeSandbox()
        try box.install("1.19.5")
        let status = try await Self.status(box, latest: "1.19.5", two: "2.2.5")
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "2.2.5")
        #expect(status.installedVersion == "1.19.5")
        #expect(status.oneClick == nil)
        #expect(status.withheld == .ownUpgrade)
        #expect(status.manualCommand?.display == "opencode upgrade --major")
        #expect(status.commandToCopy?.display == "opencode upgrade --major")
        #expect(status.note?.contains("https://opencode.ai/v2/docs/migrate-v1/") == true)
        #expect(!status.joinsUpdateAll)
        // Nothing on the 2.x channel: the row stays what it was.
        let none = try await Self.status(box, latest: "1.19.5")
        #expect(none.state == .upToDate)
        #expect(none.withheld == nil)
    }

    /// A 1.x release is the row's update while one is pending: it is what the
    /// channel and the one-click install.
    @Test func aPendingOneXReleaseComesFirst() async throws {
        let box = try OpencodeSandbox()
        try box.install("1.19.4")
        let status = try await Self.status(box, latest: "1.19.5", two: "2.2.5")
        #expect(status.latestVersion == "1.19.5")
        #expect(status.oneClick != nil)
        #expect(status.withheld == nil)
    }

    /// `"autoupdate": false` turns the vendor's own notice off: the major is
    /// reported with the command, never as a click — every check's rule.
    @Test func autoupdateOffReportsTheMajorOnly() async throws {
        let box = try OpencodeSandbox()
        try box.install("1.19.5")
        let status = try await Self.status(box, latest: "1.19.5", two: "2.2.5",
                                           settings: OpencodeSettings(autoUpdate: false))
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .autoUpdateOff)
        #expect(status.manualCommand?.display == "opencode upgrade --major")
        #expect(status.oneClick == nil)
    }

    /// Once on OpenCode 2, the row follows 2.x's channel: the 1.x one would read
    /// as "ahead" forever, and its installer cannot carry a 2.x install.
    @Test func anInstallOnOpenCodeTwoFollowsItsOwnChannel() async throws {
        let box = try OpencodeSandbox()
        try box.install("2.2.4")
        let status = try await Self.status(box, latest: "1.19.5", two: "2.2.5")
        #expect(status.installedVersion == "2.2.4")
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "2.2.5")
        #expect(status.withheld == .ownUpgrade)
        #expect(status.manualCommand?.display == "opencode upgrade")
        #expect(status.oneClick == nil)
        // The reason and the command say it: no second sentence repeating them.
        #expect(status.note == nil)

        try box.install("2.2.5")
        #expect(try await Self.status(box, latest: "1.19.5", two: "2.2.5").state == .upToDate)

        // 2.x's channel unreadable: unknown, not "ahead" of a line it is not on.
        let install = try #require(box.scanner.scan())
        let unreadable = await OpencodeCheck(latest: { "1.19.5" }).status(
            of: install, settings: OpencodeSettings(), busy: nil)
        #expect(unreadable.state == .unknown)
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
