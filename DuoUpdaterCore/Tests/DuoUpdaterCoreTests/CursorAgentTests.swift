import Testing
import Foundation
@testable import DuoUpdaterCore

/// Cursor's CLI built out of plain files, laid out as its installer lays it out
/// (2026.10.01-e373342, 2026-10-04). Each release's `node` and `rg` say who
/// "signed" them in their text, which the injected signature check reads.
final class CursorAgentSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var data: URL { home.appendingPathComponent(".local/share/cursor-agent") }
    var bin: URL { home.appendingPathComponent(".local/bin") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cursor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var scanner: CursorAgentScanner {
        CursorAgentScanner(home: home, checkSignature: { url, team in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return text.contains("SIGNER:\(team)") ? .vendor : .adHoc
        })
    }

    @discardableResult
    func write(_ url: URL, _ text: String, executable: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    func link(_ link: URL, to destination: String) throws {
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: destination)
    }

    func release(_ version: String, signed: Bool = true) throws {
        let dir = data.appendingPathComponent("versions/\(version)")
        try write(dir.appendingPathComponent("cursor-agent"), "#!/usr/bin/env bash\ntouch \"$HOME/RAN\"\n", executable: true)
        try write(dir.appendingPathComponent("node"), signed ? "SIGNER:HX7739G8FX" : "adhoc", executable: true)
        try write(dir.appendingPathComponent("rg"), signed ? "SIGNER:DCNK4UB866" : "adhoc", executable: true)
    }

    /// A release and both launchers on it, absolute, as the installer writes them.
    func install(_ version: String = "2026.05.16-0338208", signed: Bool = true) throws {
        try release(version, signed: signed)
        let target = data.appendingPathComponent("versions/\(version)/cursor-agent").path
        try link(bin.appendingPathComponent("agent"), to: target)
        try link(bin.appendingPathComponent("cursor-agent"), to: target)
    }

    /// The installer as cursor.com serves it, cut to the lines that matter.
    static func installer(_ version: String = "2026.10.01-e373342", body: String = "") -> Data {
        Data("""
            #!/usr/bin/env bash
            TEMP_EXTRACT_DIR="$HOME/.local/share/cursor-agent/versions/.tmp-\(version)-$(date +%s)"
            DOWNLOAD_URL="https://downloads.cursor.com/lab/\(version)/${OS}/${ARCH}/agent-cli-package.tar.gz"
            FINAL_DIR="$HOME/.local/share/cursor-agent/versions/\(version)"
            \(body)
            """.utf8)
    }
}

@Suite struct CursorAgentTests {

    static func check(_ latest: String = "2026.10.01-e373342") -> CursorAgentCheck { CursorAgentCheck(latest: { latest }) }

    static func status(
        _ box: CursorAgentSandbox, latest: String = "2026.10.01-e373342",
        settings: CursorAgentSettings = CursorAgentSettings(), busy: CursorAgentActivity.Busy? = nil
    ) async throws -> CLIToolStatus {
        let install = try #require(box.scanner.scan())
        return await check(latest).status(of: install, settings: settings, busy: busy)
    }

    // MARK: - Scanner

    @Test func readsTheVersionTheLauncherNames() throws {
        let box = try CursorAgentSandbox()
        try box.release("2026.04.01-aaaaaaa")
        try box.install()
        let install = try #require(box.scanner.scan())
        #expect(install.path == box.bin.appendingPathComponent("agent").path)
        #expect(install.root == box.data.path)
        #expect(install.version == "2026.05.16-0338208")
        #expect(install.problem == nil)
        #expect(box.scanner.isTrusted(URL(fileURLWithPath: try #require(install.directory))))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    /// Mutations: accept a launcher outside `versions`; skip the node check.
    @Test func brokenLayouts() throws {
        let none = try CursorAgentSandbox()
        #expect(none.scanner.scan() == nil)

        let elsewhere = try CursorAgentSandbox()
        try elsewhere.install()
        try elsewhere.link(elsewhere.bin.appendingPathComponent("agent"), to: "/opt/homebrew/bin/cursor-agent")
        #expect(elsewhere.scanner.scan()?.problem == .launcherElsewhere)

        let legacy = try CursorAgentSandbox()
        try legacy.install()
        try FileManager.default.removeItem(at: legacy.bin.appendingPathComponent("agent"))
        #expect(legacy.scanner.scan()?.path == legacy.bin.appendingPathComponent("cursor-agent").path)
        #expect(legacy.scanner.scan()?.problem == nil)

        let incomplete = try CursorAgentSandbox()
        try incomplete.install()
        try FileManager.default.removeItem(at: incomplete.data.appendingPathComponent("versions/2026.05.16-0338208/node"))
        #expect(incomplete.scanner.scan()?.problem == .versionIncomplete)

        let odd = try CursorAgentSandbox()
        try odd.release("dev")
        try odd.link(odd.bin.appendingPathComponent("agent"), to: odd.data.appendingPathComponent("versions/dev/cursor-agent").path)
        #expect(odd.scanner.scan()?.problem == .versionUnreadable)
    }

    @Test func untrustedReleases() throws {
        let box = try CursorAgentSandbox()
        try box.release("2026.10.01-e373342", signed: false)
        #expect(!box.scanner.isTrusted(box.data.appendingPathComponent("versions/2026.10.01-e373342")))
    }

    // MARK: - Settings

    @Test func staticChannelTurnsUpdatesOff() throws {
        let box = try CursorAgentSandbox()
        #expect(CursorAgentSettings.read(home: box.home) == CursorAgentSettings())
        try box.write(box.home.appendingPathComponent(".cursor/cli-config.json"),
                      #"{"version":1,"channel":"static","permissions":{"allow":[]}}"#)
        #expect(CursorAgentSettings.read(home: box.home).updatesDisabled)
        try box.write(box.home.appendingPathComponent(".cursor/cli-config.json"), #"{"channel":"lab"}"#)
        #expect(!CursorAgentSettings.read(home: box.home).updatesDisabled)
    }

    // MARK: - Release

    /// Mutations: accept a script whose download names another version; accept
    /// two `FINAL_DIR` lines.
    @Test func theInstallerNamesItsVersion() async throws {
        #expect(CursorAgentRelease.version(inInstaller: CursorAgentSandbox.installer()) == "2026.10.01-e373342")
        let mismatched = Data(String(decoding: CursorAgentSandbox.installer(), as: UTF8.self)
            .replacingOccurrences(of: "lab/2026.10.01-e373342", with: "lab/2026.09.30-abcdef0").utf8)
        #expect(CursorAgentRelease.version(inInstaller: mismatched) == nil)
        let twice = CursorAgentSandbox.installer(body: #"FINAL_DIR="$HOME/.local/share/cursor-agent/versions/2026.10.02-bbbbbbb""#)
        #expect(CursorAgentRelease.version(inInstaller: twice) == nil)
        #expect(CursorAgentRelease.version(inInstaller: Data("<html>FINAL_DIR=</html>".utf8)) == nil)

        let release = CursorAgentRelease(fetch: { url, _ in
            #expect(url == CursorAgentRelease.installerURL)
            return (CursorAgentSandbox.installer(), 200)
        })
        #expect(try await release.latest() == "2026.10.01-e373342")
        await #expect(throws: CursorAgentRelease.Failure.http(503)) {
            try await CursorAgentRelease(fetch: { _, _ in (Data(), 503) }).latest()
        }
    }

    /// The CLI's own rule: the date orders; one day's two releases differ.
    @Test func versionOrder() {
        #expect(CursorAgentRelease.compare("2026.05.16-0338208", "2026.10.01-e373342") == .orderedAscending)
        #expect(CursorAgentRelease.compare("2026.10.01-e373342", "2026.05.16-0338208") == .orderedDescending)
        #expect(CursorAgentRelease.compare("2026.10.01-e373342", "2026.10.01-e373342") == .orderedSame)
        #expect(CursorAgentRelease.compare("2026.10.01-aaaaaaa", "2026.10.01-e373342") == .orderedAscending)
        #expect(CursorAgentRelease.isVersion("2026.10.01-e373342"))
        #expect(!CursorAgentRelease.isVersion("2026.10.1-e373342"))
        #expect(!CursorAgentRelease.isVersion("2026.10.01"))
        #expect(!CursorAgentRelease.isVersion("2026.10.01-xyz;rm"))
    }

    // MARK: - Check

    @Test func anOldCopyIsOfferedTheInstaller() async throws {
        let box = try CursorAgentSandbox()
        try box.install()
        let status = try await Self.status(box)
        #expect(status.kind == .cursorAgent)
        #expect(status.state == .updateAvailable)
        #expect(status.channel == "prod")
        #expect(status.oneClick?.display == "curl https://cursor.com/install -fsS | bash")
    }

    /// Mutations: drop a gate; offer a click to `.ahead`.
    @Test func gates() async throws {
        let box = try CursorAgentSandbox()
        try box.install("2026.10.01-e373342")
        #expect(try await Self.status(box).state == .upToDate)
        #expect(try await Self.status(box, latest: "2026.09.01-aaaaaaa").state == .ahead)
        let old = try CursorAgentSandbox()
        try old.install()
        let off = try await Self.status(old, settings: CursorAgentSettings(channel: "static"))
        #expect(off.withheld == .updatesDisabled)
        #expect(off.oneClick == nil)
        #expect(off.channel == "static")
        #expect(try await Self.status(old, busy: .updating).withheld == .busy)
        let install = try #require(old.scanner.scan())
        let unreadable = await CursorAgentCheck(latest: { throw CursorAgentRelease.Failure.unreadable })
            .status(of: install, settings: CursorAgentSettings(), busy: nil)
        #expect(unreadable.withheld == .channelUnreadable)
    }

    // MARK: - Activity

    /// Mutations: count a stale lock or a stale `.tmp-` directory; miss the download.
    @Test func installsInFlight() throws {
        let box = try CursorAgentSandbox()
        try box.install()
        let now = Date()
        #expect(CursorAgentActivity.busy(root: box.data, processes: [], now: now) == nil)
        let lock = try box.write(box.data.appendingPathComponent(".install.lock"), "")
        #expect(CursorAgentActivity.busy(root: box.data, processes: [], now: now) == .updating)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: lock.path)
        #expect(CursorAgentActivity.busy(root: box.data, processes: [], now: now) == nil)
        let fresh = ".tmp-2026.10.01-e373342-\(Int(now.timeIntervalSince1970) - 30)"
        try FileManager.default.createDirectory(at: box.data.appendingPathComponent("versions/\(fresh)"), withIntermediateDirectories: true)
        #expect(CursorAgentActivity.busy(root: box.data, processes: [], now: now) == .installing(fresh))
        #expect(CursorAgentActivity.busy(root: box.data, processes: [], now: now.addingTimeInterval(3600)) == nil)
        let curl = NpmActivity.Process(
            pid: 12, arguments: ["curl", "-fSL", "--progress-bar",
                                 "https://downloads.cursor.com/lab/2026.10.01-e373342/darwin/arm64/agent-cli-package.tar.gz"],
            executable: "/usr/bin/curl")
        #expect(CursorAgentActivity.busy(root: box.root, processes: [curl], now: now) == .download(12))
    }
}

/// Running the one-click: the installer fetched, read and run, and what it left judged.
@Suite struct CursorAgentUpdaterTests {

    /// A stand-in installer: the served script's lines, then what it does to the
    /// sandbox — a new release, both launchers on it.
    static func installer(_ version: String = "2026.10.01-e373342", signed: Bool = true, extra: String = "") -> Data {
        CursorAgentSandbox.installer(version, body: """
            env > "$HOME/ENV"
            \(extra)
            D="$HOME/.local/share/cursor-agent/versions/\(version)"
            mkdir -p "$D"
            printf '#!/usr/bin/env bash\\n' > "$D/cursor-agent"; chmod +x "$D/cursor-agent"
            echo '\(signed ? "SIGNER:HX7739G8FX" : "adhoc")' > "$D/node"; chmod +x "$D/node"
            echo '\(signed ? "SIGNER:DCNK4UB866" : "adhoc")' > "$D/rg"; chmod +x "$D/rg"
            mkdir -p "$HOME/.local/bin"
            rm -f "$HOME/.local/bin/agent" "$HOME/.local/bin/cursor-agent"
            ln -s "$D/cursor-agent" "$HOME/.local/bin/agent"
            ln -s "$D/cursor-agent" "$HOME/.local/bin/cursor-agent"
            echo "✓ Package installed successfully"
            """)
    }

    static func updater(
        _ box: CursorAgentSandbox, script: Data = installer(), busy: CursorAgentActivity.Busy? = nil,
        settings: CursorAgentSettings = CursorAgentSettings(), environment: [String: String] = [:]
    ) -> CursorAgentUpdater {
        CursorAgentUpdater(
            busy: { busy }, scanner: box.scanner, release: CursorAgentRelease(fetch: { _, _ in (script, 200) }),
            environment: { environment }, settings: { settings })
    }

    static func environment(_ box: CursorAgentSandbox) -> [String: String] {
        let text = (try? String(contentsOf: box.home.appendingPathComponent("ENV"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    @Test func runsTheInstallerAndChecksWhatItLeft() async throws {
        let box = try CursorAgentSandbox()
        try box.install()
        let status = try await CursorAgentTests.status(box)
        let outcome = await Self.updater(box, environment: ["HOME": "/elsewhere", "PATH": "/x", "https_proxy": "http://127.0.0.1:9"])
            .update(status)
        #expect(outcome == .updated(version: "2026.10.01-e373342"))
        let env = Self.environment(box)
        #expect(env["HOME"] == box.home.path)
        #expect(env["PATH"] == CLIToolCommandRunner.systemPath)
        #expect(env["NO_COLOR"] == "1")
        #expect(env["https_proxy"] == "http://127.0.0.1:9")
        // The old release stays, as the installer leaves it; the agent never ran.
        #expect(FileManager.default.fileExists(atPath: box.data.appendingPathComponent("versions/2026.05.16-0338208").path))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    /// Mutation: dropping the trust guard reports `.updated`.
    @Test func aReleaseNotTheVendorsIsAFailure() async throws {
        let box = try CursorAgentSandbox()
        try box.install()
        let outcome = await Self.updater(box, script: Self.installer(signed: false)).update(try await CursorAgentTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.hasPrefix("2026.10.01-e373342 is not the vendors' build"))
    }

    @Test func aFailedInstallerSaysWhy() async throws {
        let box = try CursorAgentSandbox()
        try box.install()
        let script = Self.installer(extra: "echo '✗ Download failed. Please check your internet connection and try again.'; exit 1")
        let outcome = await Self.updater(box, script: script).update(try await CursorAgentTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "Download failed. Please check your internet connection and try again.")
        #expect(box.scanner.scan()?.version == "2026.05.16-0338208")
    }

    /// Mutations: drop the click-time script version check, busy, settings or re-scan.
    @Test func clickTimeGatesRunNothing() async throws {
        let box = try CursorAgentSandbox()
        try box.install()
        let status = try await CursorAgentTests.status(box)
        #expect(await Self.updater(box, script: Self.installer("2026.05.16-0338208")).update(status) == .failed(
            message: "not run: the installer now installs 2026.05.16-0338208, not a version newer than 2026.05.16-0338208",
            output: ""))
        #expect(await Self.updater(box, script: Data("<html>".utf8)).update(status) == .failed(
            message: "could not download https://cursor.com/install: cursor.com/install did not answer with the installer",
            output: ""))
        #expect(await Self.updater(box, busy: .updating).update(status) == .busy("Cursor's CLI is updating itself (.install.lock)"))
        #expect(await Self.updater(box, settings: CursorAgentSettings(channel: "static")).update(status) == .notOffered)
        try box.install("2026.06.01-ccccccc")
        #expect(await Self.updater(box).update(status) == .failed(
            message: "not run: \(box.bin.appendingPathComponent("agent").path) is no longer the Cursor CLI that was checked",
            output: ""))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }
}
