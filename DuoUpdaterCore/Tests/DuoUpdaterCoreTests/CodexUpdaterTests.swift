import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running Codex's one-click update: which installer is fetched and run, with
/// which environment, and what the row is told.
///
/// The "installer" is a POSIX shell script handed to the updater instead of the
/// download. It does to the sandbox what `install.sh` does (`rust-v0.160.0`):
/// prints its lines, lays out `releases/<new>-<target>`, swaps `current` and the
/// launcher — and records the environment it saw. The busy check, the channel,
/// the signature check (the binary's text, `CodexSandbox.scanner`) and the base
/// environment are injected: nothing here runs Codex or reaches the network.
@Suite struct CodexUpdaterTests {

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    /// A stand-in for `install.sh` that installs `version` signed as `signer`.
    /// `extra` runs first.
    static func installer(version: String = "0.160.0", signer: String = "openai", extra: String = "") -> Data {
        Data("""
            #!/bin/sh
            set -eu
            RELEASES_BASE_URL="https://releases.openai.com/codex"
            CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
            STANDALONE_ROOT="$CODEX_HOME_DIR/packages/standalone"
            env > "$HOME/ENV"
            \(extra)
            echo "==> Updating Codex CLI from 0.143.0 to \(version)"
            echo "==> Detected platform: macOS (Apple Silicon)"
            echo "==> Resolved version: \(version)"
            echo "==> Downloading Codex CLI"
            R="$STANDALONE_ROOT/releases/\(version)-aarch64-apple-darwin"
            mkdir -p "$R/bin" "$R/codex-path"
            echo "\(signer)" > "$R/bin/codex"
            chmod +x "$R/bin/codex"
            printf '{"layoutVersion":1,"version":"\(version)","target":"aarch64-apple-darwin"}' > "$R/codex-package.json"
            ln -s bin/codex "$R/codex"
            ln -sfn "$R" "$STANDALONE_ROOT/.current.$$" && mv -hf "$STANDALONE_ROOT/.current.$$" "$STANDALONE_ROOT/current"
            ln -sfn "$STANDALONE_ROOT/current/bin/codex" "$HOME/.local/bin/codex"
            echo "==> $HOME/.local/bin is already on PATH"
            echo "Codex CLI \(version) installed successfully."
            """.utf8)
    }

    static func oldInstall() throws -> CodexSandbox {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        return box
    }

    static func status(_ box: CodexSandbox) async throws -> CLIToolStatus {
        let status = try await CodexTests.status(box)
        _ = try #require(status.oneClick)
        return status
    }

    final class Fetched: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [URL] = []
        func add(_ item: URL) { lock.withLock { items.append(item) } }
        var all: [URL] { lock.withLock { items } }
    }

    static func updater(
        _ box: CodexSandbox, script: Data = installer(), latest: String = "0.160.0", fetched: Fetched = Fetched(),
        busy: @escaping CodexUpdater.BusyCheck = { _ in nil }, environment: [String: String] = [:],
        settings: CodexSettings = CodexSettings()
    ) -> CodexUpdater {
        CodexUpdater(
            busy: busy, scanner: box.scanner, check: CodexTests.check(latest), environment: { environment },
            settings: { settings },
            fetchScript: { url in
                fetched.add(url)
                return script
            })
    }

    func seenEnvironment(_ box: CodexSandbox) -> [String: String] {
        let text = (try? String(contentsOf: box.home.appendingPathComponent("ENV"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    @Test func runsTheInstallerAndChecksWhatItLeft() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let lines = Lines()
        let outcome = await Self.updater(
            box, fetched: fetched,
            environment: ["HOME": "/ZZFixture-codex/elsewhere", "PATH": "/somewhere/else", "CODEX_RELEASE": "0.150.0",
                          "CODEX_HOME": "/elsewhere/.codex", "CODEX_INSTALL_DIR": "/elsewhere/bin",
                          "CODEX_INSTALL_IF_LATEST": "1", "https_proxy": "http://127.0.0.1:9"]
        ).update(status) { lines.add($0) }
        #expect(outcome == .updated(version: "0.160.0"))
        #expect(fetched.all.map(\.absoluteString) == ["https://chatgpt.com/codex/install.sh"])
        let env = seenEnvironment(box)
        // Where the scan reads, with ~/.local/bin first so no profile is edited.
        #expect(env["HOME"] == box.home.path)
        #expect(env["PATH"] == box.home.path + "/.local/bin:" + CLIToolCommandRunner.systemPath)
        #expect(env["CODEX_NON_INTERACTIVE"] == "1")
        // A pin, another home or launcher directory, a guarded update: none of
        // them DuoUpdater's to pass on.
        for key in CodexUpdater.installerOverrides { #expect(env[key] == nil, "\(key)") }
        #expect(env["https_proxy"] == "http://127.0.0.1:9")
        let tmp = try #require(env["TMPDIR"])
        #expect(tmp.contains("duo-codex-"))
        #expect(!FileManager.default.fileExists(atPath: tmp))
        #expect(lines.all.contains("Codex CLI 0.160.0 installed successfully."))
        // The old release stays beside the new one, as the installer leaves it.
        #expect(FileManager.default.fileExists(
            atPath: box.standalone.appendingPathComponent("releases/0.143.0-aarch64-apple-darwin/bin/codex").path))
        #expect(box.scanner.scan().first?.version == "0.160.0")
    }

    /// The release left behind must be OpenAI's. Mutation: dropping the
    /// signature guard in `verdict` reports `.updated`.
    @Test func aNewReleaseNotSignedByOpenAIIsAFailure() async throws {
        let box = try Self.oldInstall()
        let outcome = await Self.updater(box, script: Self.installer(signer: "adhoc")).update(try await Self.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "0.160.0 is not signed by OpenAI (Team 2DC432GLL2): adHoc")
    }

    /// Exit 0 is not proof. Mutation: dropping the newer-version guard reports
    /// `.updated("0.143.0")`.
    @Test func anInstallerThatChangedNothingIsAFailure() async throws {
        let box = try Self.oldInstall()
        let script = Data("""
            #!/bin/sh
            RELEASES_BASE_URL="https://releases.openai.com/codex"
            STANDALONE_ROOT="$CODEX_HOME_DIR/packages/standalone"
            echo 'Codex CLI 0.143.0 installed successfully.'
            """.utf8)
        let outcome = await Self.updater(box, script: script).update(try await Self.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "the installer finished, but Codex is still 0.143.0")
    }

    @Test func aFailedInstallerSaysWhy() async throws {
        let box = try Self.oldInstall()
        let script = Self.installer(extra: """
            echo "==> Downloading Codex CLI"
            echo "Downloaded Codex archive checksum did not match expected digest." >&2
            exit 1
            """)
        let outcome = await Self.updater(box, script: script).update(try await Self.status(box))
        guard case .failed(let message, let output) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "Downloaded Codex archive checksum did not match expected digest.")
        #expect(output.contains("==> Downloading Codex CLI"))
        #expect(box.scanner.scan().first?.version == "0.143.0")
    }

    /// An error page, a captive portal's answer or another script is refused
    /// before anything runs. Mutation: dropping `isInstaller` runs it.
    @Test func aScriptThatIsNotTheInstallerIsNotRun() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let refused = CLIToolUpdateOutcome.failed(
            message: "https://chatgpt.com/codex/install.sh did not answer with the Codex installer", output: "")
        let html = Data("<!DOCTYPE html><html>STANDALONE_ROOT=\"$CODEX_HOME_DIR/packages/standalone\"</html>".utf8)
        #expect(await Self.updater(box, script: html).update(status) == refused)
        let other = Data("#!/bin/sh\ntouch \"$HOME/RAN\"\n".utf8)
        #expect(await Self.updater(box, script: other).update(status) == refused)
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("RAN").path))
    }

    /// Mutation: dropping the click-time channel read runs the installer, which
    /// installs whatever `latest` names.
    @Test func aChannelThatNoLongerNamesANewerVersionRunsNothing() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let outcome = await Self.updater(box, latest: "0.143.0", fetched: fetched).update(status)
        #expect(outcome == .failed(
            message: "not run: Codex's latest channel now names 0.143.0, not a version newer than 0.143.0", output: ""))
        #expect(fetched.all.isEmpty)
    }

    @Test func busyAtTheClickRunsNothing() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let outcome = await Self.updater(box, fetched: fetched, busy: { _ in .installer(77) }).update(status)
        #expect(outcome == .busy("the Codex installer is running (pid 77)"))
        #expect(fetched.all.isEmpty)
    }

    /// Mutation: dropping the click-time settings read runs the installer.
    @Test func updateCheckTurnedOffSinceTheCheckRunsNothing() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        let outcome = await Self.updater(box, fetched: fetched, settings: CodexSettings(checkForUpdates: false)).update(status)
        #expect(outcome == .notOffered)
        #expect(fetched.all.isEmpty)
    }

    /// Mutations: dropping the re-scan; dropping the signature re-check.
    @Test func anInstallThatChangedSinceTheCheckIsLeftAlone() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let fetched = Fetched()
        try box.install("0.159.3")
        #expect(await Self.updater(box, fetched: fetched).update(status) == .failed(
            message: "not run: \(box.launcher.path) is no longer the Codex install that was checked", output: ""))

        let swapped = try Self.oldInstall()
        let checked = try await Self.status(swapped)
        try swapped.release("0.143.0", signer: "adhoc")
        guard case .failed(let message, _) = await Self.updater(swapped, fetched: fetched).update(checked) else {
            Issue.record("ran"); return
        }
        #expect(message.hasSuffix("is not signed by OpenAI (Team 2DC432GLL2)"))
        #expect(fetched.all.isEmpty)
    }

    @Test func aDownloadFailureRunsNothing() async throws {
        let box = try Self.oldInstall()
        let status = try await Self.status(box)
        let updater = CodexUpdater(
            busy: { _ in nil }, scanner: box.scanner, check: CodexTests.check(), environment: { [:] },
            fetchScript: { _ in throw CodexRelease.Failure.http(503) })
        #expect(await updater.update(status)
            == .failed(message: "could not download https://chatgpt.com/codex/install.sh: HTTP 503", output: ""))
    }

    @Test func noOneClickNoRun() async throws {
        let box = try Self.oldInstall()
        let status = try await CodexTests.status(box, settings: CodexSettings(checkForUpdates: false))
        let fetched = Fetched()
        #expect(await Self.updater(box, fetched: fetched).update(status) == .notOffered)
        #expect(fetched.all.isEmpty)
    }

    @Test func installerRecognition() {
        #expect(CodexUpdater.isInstaller(Self.installer()))
        #expect(!CodexUpdater.isInstaller(Data("#!/bin/bash\nRELEASES_BASE_URL=\"https://releases.openai.com/codex\"\n".utf8)))
        #expect(!CodexUpdater.isInstaller(Data("#!/bin/sh\n# STANDALONE_ROOT=\"$CODEX_HOME_DIR/packages/standalone\"\n".utf8)))
    }
}
