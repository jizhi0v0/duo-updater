import Testing
import Foundation
@testable import DuoUpdaterCore

/// Amp built out of plain files, laid out as its installer lays it out
/// (2026-10-04). The binary is a shell script whose text carries the user-agent
/// literal the scanner reads and a `SIGNER:` line the injected check reads.
final class AmpSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var binary: URL { home.appendingPathComponent(".amp/bin/amp") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("amp-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var scanner: AmpScanner {
        AmpScanner(home: home, checkSignature: { url in
            ((try? String(contentsOf: url, encoding: .utf8)) ?? "").contains("SIGNER:amp") ? .vendor : .adHoc
        })
    }

    @discardableResult
    func write(_ url: URL, _ text: String, executable: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    func install(_ version: String = "0.0.1791091069-gb9917f", signer: String = "amp") throws {
        try write(binary, "#!/bin/sh\n# Amp-CLI/\(version)\u{0}\n# SIGNER:\(signer)\ntouch \"$HOME/RAN\"\n", executable: true)
    }
}

@Suite struct AmpTests {

    static func check(_ latest: String = "0.0.1791121193-ge297b9") -> AmpCheck { AmpCheck(latest: { latest }) }

    static func status(
        _ box: AmpSandbox, latest: String = "0.0.1791121193-ge297b9", settings: AmpSettings = AmpSettings(),
        busy: AmpActivity.Busy? = nil
    ) async throws -> CLIToolStatus {
        let install = try #require(box.scanner.scan().map(box.scanner.withSignature))
        return await check(latest).status(of: install, settings: settings, busy: busy)
    }

    @Test func readsTheVersionWithoutRunningIt() throws {
        let box = try AmpSandbox()
        try box.install()
        let install = try #require(box.scanner.scan())
        #expect(install.version == "0.0.1791091069-gb9917f")
        #expect(install.problem == nil)
        #expect(box.scanner.withSignature(install).signature == .vendor)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    /// Mutations: read past the version's end; accept literals that disagree.
    @Test func compiledVersionShapes() {
        func read(_ text: String) -> String? { AmpScanner.compiledVersion(in: Data(text.utf8)) }
        #expect(read("Amp-CLI/0.0.1791121193-ge297b9\u{0}G") == "0.0.1791121193-ge297b9")
        #expect(read("x Amp-CLI/0.0.1791121193-ge297b9 y") == "0.0.1791121193-ge297b9")
        #expect(read("Amp-CLI/0.0.1 a Amp-CLI/0.0.2 b") == nil)
        #expect(read("Amp-CLI/garbage\u{0}") == nil)
        #expect(read("nothing") == nil)
    }

    @Test func nothingAndBroken() throws {
        let box = try AmpSandbox()
        #expect(box.scanner.scan() == nil)
        try box.write(box.binary, "#!/bin/sh\n", executable: true)
        #expect(box.scanner.scan()?.problem == .versionUnreadable)
    }

    @Test func settingsDisabledIsOff() throws {
        let box = try AmpSandbox()
        #expect(AmpSettings.read(home: box.home).autoUpdate)
        try box.write(AmpSettings.location(home: box.home), #"{"amp.mcpServers": {}, "amp.updates.mode": "disabled"}"#)
        #expect(!AmpSettings.read(home: box.home).autoUpdate)
        try box.write(AmpSettings.location(home: box.home), #"{"amp.updates.mode": "warn"}"#)
        #expect(AmpSettings.read(home: box.home).autoUpdate)
    }

    @Test func latestIsCliVersionTxt() async throws {
        let release = AmpRelease(fetch: { url in
            #expect(url == AmpRelease.channel)
            return (Data("0.0.1791121193-ge297b9\n".utf8), 200)
        })
        #expect(try await release.latest() == "0.0.1791121193-ge297b9")
        await #expect(throws: AmpRelease.Failure.unreadable) {
            try await AmpRelease(fetch: { _ in (Data("<html>".utf8), 200) }).latest()
        }
        await #expect(throws: AmpRelease.Failure.http(500)) {
            try await AmpRelease(fetch: { _ in (Data(), 500) }).latest()
        }
        #expect(AmpRelease.compare("0.0.1791091069-gb9917f", "0.0.1791121193-ge297b9") == .orderedAscending)
        #expect(AmpRelease.compare("0.0.1791121193-ge297b9", "0.0.1791091069-gb9917f") == .orderedDescending)
        #expect(AmpRelease.compare("0.0.1791121193-ge297b9", "0.0.1791121193-ge297b9") == .orderedSame)
        #expect(!AmpRelease.isVersion("0.0.1; rm"))
    }

    @Test func outdatedCopyIsOfferedThePinnedInstaller() async throws {
        let box = try AmpSandbox()
        try box.install()
        let status = try await Self.status(box)
        #expect(status.kind == .amp)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick?.display == "curl -fsSL https://ampcode.com/install.sh | AMP_VERSION=0.0.1791121193-ge297b9 bash")
    }

    /// Mutations: drop a gate; offer a click to `.ahead`.
    @Test func gates() async throws {
        let box = try AmpSandbox()
        try box.install()
        #expect(try await Self.status(box, latest: "0.0.1791091069-gb9917f").state == .upToDate)
        #expect(try await Self.status(box, latest: "0.0.1700000000-gaaaaaa").state == .ahead)
        let off = try await Self.status(box, settings: AmpSettings(updatesMode: "disabled"))
        #expect(off.withheld == .autoUpdateOff)
        #expect(off.manualCommand != nil)
        #expect(try await Self.status(box, busy: .download(3)).withheld == .busy)
    }

    /// The installer's files as it leaves them while it works. Mutations: count
    /// a stale file; miss the download.
    @Test func installsInFlight() throws {
        let box = try AmpSandbox()
        try box.install()
        let root = box.home.appendingPathComponent(".amp")
        let now = Date()
        #expect(AmpActivity.busy(root: root, processes: [], now: now) == nil)
        let staged = try box.write(root.appendingPathComponent("bin/tmp.urlwUa"), "")
        #expect(AmpActivity.busy(root: root, processes: [], now: now) == .installing("tmp.urlwUa"))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3600)], ofItemAtPath: staged.path)
        #expect(AmpActivity.busy(root: root, processes: [], now: now) == nil)
        let curl = NpmActivity.Process(
            pid: 5, arguments: ["curl", "-fsSL", "https://static.ampcode.com/cli/0.0.1791121193-ge297b9/amp-darwin-arm64.gz"],
            executable: "/usr/bin/curl")
        #expect(AmpActivity.busy(root: root, processes: [curl], now: now) == .download(5))
    }
}

/// Running Amp's one-click with a stand-in installer that does what the real one
/// does to the sandbox.
@Suite struct AmpUpdaterTests {

    static func installer(signer: String = "amp", installs: String? = nil, extra: String = "") -> Data {
        Data("""
            #!/usr/bin/env bash
            set -euo pipefail
            AMP_HOME="${AMP_HOME:-$HOME/.amp}"
            BIN_DIR="$AMP_HOME/bin"
            AMP_STORAGE_BASE="${AMP_STORAGE_BASE:-https://static.ampcode.com}"
            env > "$HOME/ENV"
            \(extra)
            v="\(installs ?? "${AMP_VERSION}")"
            printf '#!/bin/sh\\n# Amp-%s/%s\\0\\n# %s:%s\\n' CLI "$v" SIGNER '\(signer)' > "$BIN_DIR/tmp.x"
            mv "$BIN_DIR/tmp.x" "$BIN_DIR/amp"
            echo "<--  Amp CLI installed"
            """.utf8)
    }

    static func updater(
        _ box: AmpSandbox, script: Data = installer(), latest: String = "0.0.1791121193-ge297b9",
        busy: AmpActivity.Busy? = nil, settings: AmpSettings = AmpSettings(), environment: [String: String] = [:]
    ) -> AmpUpdater {
        AmpUpdater(busy: { busy }, scanner: box.scanner, check: AmpTests.check(latest), environment: { environment },
                   settings: { settings }, fetchScript: { _ in script })
    }

    static func environment(_ box: AmpSandbox) -> [String: String] {
        let text = (try? String(contentsOf: box.home.appendingPathComponent("ENV"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    @Test func runsThePinnedInstaller() async throws {
        let box = try AmpSandbox()
        try box.install()
        let status = try await AmpTests.status(box)
        let outcome = await Self.updater(box, environment: [
            "HOME": "/elsewhere", "AMP_STORAGE_BASE": "https://mirror.example", "AMP_URL": "https://x.example",
            "AMP_HOME": "/elsewhere/.amp", "https_proxy": "http://127.0.0.1:9",
        ]).update(status)
        #expect(outcome == .updated(version: "0.0.1791121193-ge297b9"))
        let env = Self.environment(box)
        #expect(env["AMP_VERSION"] == "0.0.1791121193-ge297b9")
        #expect(env["HOME"] == box.home.path)
        #expect(env["PATH"] == box.home.path + "/.local/bin:" + CLIToolCommandRunner.systemPath)
        #expect(env["AMP_STORAGE_BASE"] == nil)
        #expect(env["AMP_URL"] == nil)
        #expect(env["AMP_HOME"] == nil)
        #expect(env["https_proxy"] == "http://127.0.0.1:9")
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    /// Mutations: drop the signature or version guard.
    @Test func whatTheInstallerLeftIsJudged() async throws {
        let box = try AmpSandbox()
        try box.install()
        let status = try await AmpTests.status(box)
        guard case .failed(let unsigned, _) = await Self.updater(box, script: Self.installer(signer: "adhoc")).update(status) else {
            Issue.record("unsigned"); return
        }
        #expect(unsigned == "Amp 0.0.1791121193-ge297b9 is not signed by Amp Frontier (Team PZT9BJUAA5): adHoc")
        let again = try AmpSandbox()
        try again.install()
        let status2 = try await AmpTests.status(again)
        guard case .failed(let other, _) = await Self.updater(again, script: Self.installer(installs: "0.0.1791100000-gccccc")).update(status2) else {
            Issue.record("other"); return
        }
        #expect(other == "the installer finished, but Amp is 0.0.1791100000-gccccc, not 0.0.1791121193-ge297b9")
    }

    /// Mutations: drop the click-time channel read, busy, settings, re-scan or
    /// installer recognition.
    @Test func clickTimeGatesRunNothing() async throws {
        let box = try AmpSandbox()
        try box.install()
        let status = try await AmpTests.status(box)
        #expect(await Self.updater(box, latest: "0.0.1791091069-gb9917f").update(status) == .failed(
            message: "not run: Amp's latest is now 0.0.1791091069-gb9917f, not a version newer than 0.0.1791091069-gb9917f",
            output: ""))
        #expect(await Self.updater(box, busy: .download(9)).update(status) == .busy("the Amp installer is downloading (pid 9)"))
        #expect(await Self.updater(box, settings: AmpSettings(updatesMode: "disabled")).update(status) == .notOffered)
        #expect(await Self.updater(box, script: Data("#!/usr/bin/env bash\ntouch $HOME/RAN\n".utf8)).update(status)
            == .failed(message: "https://ampcode.com/install.sh did not answer with the Amp installer", output: ""))
        try box.install("0.0.1791100000-gccccc")
        #expect(await Self.updater(box).update(status) == .failed(
            message: "not run: \(box.binary.path) is no longer the Amp that was checked", output: ""))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }
}
