import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running OpenCode's one-click update: which installer is fetched and run, with
/// which arguments and environment, and what the row is told.
///
/// The "installer" is a bash script handed to the updater instead of the
/// download. It does to the sandbox what the vendor's does (2026-10-04): asks
/// `opencode --version` of whatever `PATH` finds, makes
/// `$TMPDIR/opencode_install_$$`, `mv`s a new binary into `~/.opencode/bin` —
/// and records its arguments and environment. Nothing here reaches the network.
@Suite struct OpencodeUpdaterTests {

    /// A stand-in installer that installs `--version`'s version signed as `signer`.
    static func installer(signer: String = "anomaly", installs: String? = nil, extra: String = "") -> Data {
        Data("""
            #!/usr/bin/env bash
            set -euo pipefail
            APP=opencode
            # --no-modify-path    Don't modify shell config files
            INSTALL_DIR=$HOME/.opencode/bin
            env > "$HOME/ENV"
            echo "$@" > "$HOME/ARGS"
            \(extra)
            version="$2"
            installed=$(opencode --version 2>/dev/null || echo "")
            echo "installed:$installed" > "$HOME/SAW"
            tmp_dir="${TMPDIR:-/tmp}/opencode_install_$$"
            mkdir -p "$tmp_dir"
            echo "Installing opencode version: $version"
            printf '#!/bin/sh\\n# --user-agent=opencode/%s --use-system-ca --\\n# SIGNER:%s\\n' "\(installs ?? "$version")" "\(signer)" > "$tmp_dir/opencode"
            mv "$tmp_dir/opencode" "$INSTALL_DIR"
            chmod 755 "$INSTALL_DIR/opencode"
            rm -rf "$tmp_dir"
            echo "OpenCode includes free models, to start:"
            """.utf8)
    }

    final class Fetched: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [URL] = []
        func add(_ item: URL) { lock.withLock { items.append(item) } }
        var all: [URL] { lock.withLock { items } }
    }

    static func updater(
        _ box: OpencodeSandbox, script: Data = installer(), latest: String = "1.18.34", fetched: Fetched = Fetched(),
        busy: OpencodeActivity.Busy? = nil, environment: [String: String] = [:],
        settings: OpencodeSettings = OpencodeSettings()
    ) -> OpencodeUpdater {
        OpencodeUpdater(
            busy: { busy }, scanner: box.scanner, check: OpencodeTests.check(latest), environment: { environment },
            settings: { settings },
            fetchScript: { url in
                fetched.add(url)
                return script
            })
    }

    static func read(_ box: OpencodeSandbox, _ name: String) -> String {
        (try? String(contentsOf: box.home.appendingPathComponent(name), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func environment(_ box: OpencodeSandbox) -> [String: String] {
        var result: [String: String] = [:]
        for line in read(box, "ENV").split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    @Test func runsThePinnedInstallerAndChecksWhatItLeft() async throws {
        let box = try OpencodeSandbox()
        try box.install("1.18.15")
        // An `opencode` on the caller's PATH must not be what the installer finds.
        let decoy = try box.write(box.root.appendingPathComponent("decoy/opencode"), "#!/bin/sh\necho DECOY\n", executable: true)
        let status = try await OpencodeTests.status(box)
        let fetched = Fetched()
        let outcome = await Self.updater(
            box, fetched: fetched,
            environment: ["HOME": "/elsewhere", "PATH": decoy.deletingLastPathComponent().path, "VERSION": "1.0.180",
                          "GITHUB_ACTIONS": "true", "https_proxy": "http://127.0.0.1:9"]
        ).update(status)
        #expect(outcome == .updated(version: "1.18.34"))
        #expect(fetched.all.map(\.absoluteString) == ["https://opencode.ai/install"])
        #expect(Self.read(box, "ARGS") == "--version 1.18.34 --no-modify-path")
        // Nothing of OpenCode ran: the installer found none on PATH.
        #expect(Self.read(box, "SAW") == "installed:")
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
        let env = Self.environment(box)
        #expect(env["HOME"] == box.home.path)
        #expect(env["PATH"] == CLIToolCommandRunner.systemPath)
        #expect(env["VERSION"] == nil)
        #expect(env["GITHUB_ACTIONS"] == nil)
        #expect(env["https_proxy"] == "http://127.0.0.1:9")
        let tmp = try #require(env["TMPDIR"])
        #expect(tmp.contains("duo-opencode-"))
        #expect(!FileManager.default.fileExists(atPath: tmp))
    }

    /// Mutation: dropping the signature guard reports `.updated`.
    @Test func aNewBinaryNotSignedByAnomalyIsAFailure() async throws {
        let box = try OpencodeSandbox()
        try box.install()
        let outcome = await Self.updater(box, script: Self.installer(signer: "adhoc")).update(try await OpencodeTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "OpenCode 1.18.34 is not signed by Anomaly (Team 5NZ4Q7NXJ4): adHoc")
    }

    /// Mutation: dropping the version guard reports `.updated("1.18.20")`.
    @Test func anotherVersionThanAskedIsAFailure() async throws {
        let box = try OpencodeSandbox()
        try box.install()
        let outcome = await Self.updater(box, script: Self.installer(installs: "1.18.20")).update(try await OpencodeTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "the installer finished, but OpenCode is 1.18.20, not 1.18.34")
    }

    @Test func aFailedInstallerSaysWhy() async throws {
        let box = try OpencodeSandbox()
        try box.install()
        let script = Self.installer(extra: "echo 'Error: Release v1.18.34 not found'; exit 1")
        let outcome = await Self.updater(box, script: script).update(try await OpencodeTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "Release v1.18.34 not found")
        #expect(box.scanner.scan()?.version == "1.18.33")
    }

    /// Mutation: dropping `isInstaller` runs it.
    @Test func aScriptThatIsNotTheInstallerIsNotRun() async throws {
        let box = try OpencodeSandbox()
        try box.install()
        let status = try await OpencodeTests.status(box)
        let refused = CLIToolUpdateOutcome.failed(
            message: "https://opencode.ai/install did not answer with the OpenCode installer", output: "")
        #expect(await Self.updater(box, script: Data("<!DOCTYPE html>APP=opencode".utf8)).update(status) == refused)
        #expect(await Self.updater(box, script: Data("#!/usr/bin/env bash\ntouch \"$HOME/RAN\"\n".utf8)).update(status) == refused)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }

    /// Mutations: drop the click-time channel read, the busy check, the settings
    /// read, or the re-scan.
    @Test func clickTimeGatesRunNothing() async throws {
        let box = try OpencodeSandbox()
        try box.install()
        let status = try await OpencodeTests.status(box)
        let fetched = Fetched()
        #expect(await Self.updater(box, latest: "1.18.33", fetched: fetched).update(status) == .failed(
            message: "not run: OpenCode's latest release is now 1.18.33, not a version newer than 1.18.33", output: ""))
        #expect(await Self.updater(box, fetched: fetched, busy: .download(8)).update(status)
            == .busy("the OpenCode installer is downloading (pid 8)"))
        #expect(await Self.updater(box, fetched: fetched, settings: OpencodeSettings(autoUpdate: false)).update(status)
            == .notOffered)
        try box.install("1.18.30")
        #expect(await Self.updater(box, fetched: fetched).update(status) == .failed(
            message: "not run: \(box.binary.path) is no longer the OpenCode that was checked", output: ""))
        #expect(fetched.all.isEmpty)
    }

    @Test func installerRecognition() {
        #expect(OpencodeUpdater.isInstaller(Self.installer()))
        #expect(!OpencodeUpdater.isInstaller(Data("#!/usr/bin/env bash\nAPP=opencode\n".utf8)))
        #expect(!OpencodeUpdater.isInstaller(Data("#!/bin/sh\nAPP=opencode\nINSTALL_DIR=$HOME/.opencode/bin\n--no-modify-path".utf8)))
    }
}

/// Reading an executable's literals in chunks finds what a whole-file search
/// found, wherever the chunk boundaries fall.
@Suite struct ExecutableBytesTests {

    static func file(_ bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("exebytes-\(UUID().uuidString)")
        try bytes.write(to: url)
        return url
    }

    /// Every chunk size from 1 to past the file, so the marker, its `before` and
    /// its `after` each straddle a boundary somewhere. Mutation: drop the carried
    /// tail, or the wait for `after` bytes.
    @Test func everyChunkSizeFindsTheSameWindows() throws {
        let text = "xxbun/1.4.2+abc npm/? node/v24 yyyyyy bun/1.4.2+abc npm/? node/v24 zz npm/? node/"
        let url = try Self.file(Data(text.utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let marker = Data(" npm/? node/".utf8)
        let expected = [
            "xxbun/1.4.2+abc npm/? node/v2", "y bun/1.4.2+abc npm/? node/v2", "m/? node/v24 zz npm/? node/",
        ].map { Data($0.utf8) }
        for size in 1...(text.utf8.count + 3) {
            let windows = ExecutableBytes.windows(in: url, marker: marker, before: 15, after: 2, chunkSize: size)
            #expect(windows == expected, "chunk size \(size)")
        }
    }

    @Test func noMarkerAndNoFile() throws {
        let url = try Self.file(Data(repeating: 0x41, count: 10_000))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ExecutableBytes.windows(in: url, marker: Data("needle".utf8), before: 4, after: 4, chunkSize: 7) == [])
        #expect(ExecutableBytes.windows(in: URL(fileURLWithPath: "/nowhere/x"), marker: Data("a".utf8), before: 0, after: 0) == nil)
        #expect(ExecutableBytes.head(of: url, count: 3) == Data("AAA".utf8))
    }

    /// A version read through the windows is the one a whole-file read gave.
    @Test func joinedWindowsFeedTheScannersAsBefore() throws {
        let text = String(repeating: "junk ", count: 3000) + "--user-agent=opencode/1.18.34 --use-system-ca" + String(repeating: " pad", count: 2000)
        let url = try Self.file(Data(text.utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let joined = try #require(ExecutableBytes.joinedWindows(in: url, marker: OpencodeScanner.marker, before: 0, after: 40))
        #expect(OpencodeScanner.compiledVersion(in: joined) == OpencodeScanner.compiledVersion(in: Data(text.utf8)))
        #expect(OpencodeScanner.compiledVersion(in: joined) == "1.18.34")
    }
}
