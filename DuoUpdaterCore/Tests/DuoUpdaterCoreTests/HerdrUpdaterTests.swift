import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Running herdr's one-click update: what is asked again at the click, what is
/// run with which environment and stdin, and the check of what the update left.
///
/// "herdr" here is a `#!/bin/sh` script in a temporary HOME. Its `update` does
/// what the real one does to the disk — a new file renamed into place — or
/// prints what the real one prints when a running session would have to stop
/// ("Herdr was not updated.", exit 0; `src/update.rs`). The busy check, the base
/// environment and which sha256 is which published build are injected: nothing
/// here reads the host's process table, runs a herdr build or reaches the
/// network.
@Suite struct HerdrUpdaterTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var herdr: URL { bin.appendingPathComponent("herdr") }
        private let lock = NSLock()
        /// sha256 → build, as herdr's manifests and GitHub would say.
        private var published: [String: HerdrBuild] = [:]
        private var offers: [String: HerdrBuild] = ["stable": HerdrBuild(base: "0.9.3")]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("herdr-updater-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        static func script(_ name: String, update: String) -> String {
            """
            #!/bin/sh
            # herdr \(name)
            if [ "$1" = update ]; then
            \(update)
            fi
            """
        }

        static func sha256(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        /// The installed file, published as `build` unless that is nil.
        func install(_ build: HerdrBuild?, update: String, name: String = "installed") throws {
            let text = Self.script(name, update: update)
            try Data(text.utf8).write(to: herdr)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: herdr.path)
            if let build { publish(Self.sha256(text), build) }
        }

        func publish(_ sha: String, _ build: HerdrBuild) { lock.withLock { published[sha] = build } }
        func offer(_ channel: String, _ build: HerdrBuild) { lock.withLock { offers[channel] = build } }

        /// What `herdr update` does when it installs: the new build renamed into
        /// place over the old file. Published as `build` unless that is nil.
        func updateBody(to build: HerdrBuild?, name: String = "next") -> String {
            let next = Self.script(name, update: "exit 0")
            if let build { publish(Self.sha256(next), build) }
            let file = root.appendingPathComponent("next-\(name)")
            try? Data(next.utf8).write(to: file)
            return """
                echo "$@" > "\(root.path)/ARGS"
                env > "\(root.path)/ENV"
                if [ -p /dev/stdin ]; then echo "pipe:$(cat)" > "\(root.path)/STDIN"; elif [ -t 0 ]; then echo tty > "\(root.path)/STDIN"; else echo other > "\(root.path)/STDIN"; fi
                echo "checking stable channel for updates..."
                cp "\(file.path)" "\(bin.path)/.herdr-update-$$.tmp" && chmod 755 "\(bin.path)/.herdr-update-$$.tmp"
                mv "\(bin.path)/.herdr-update-$$.tmp" "\(bin.path)/herdr"
                echo "installed herdr v\(build?.version ?? "?")"
                """
        }

        func config(_ toml: String) throws {
            let url = HerdrSettings.location(home: home, environment: [:])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(toml.utf8).write(to: url)
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }

        func read(_ name: String) -> String? {
            try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        }

        var scanner: HerdrScanner {
            HerdrScanner(home: home, environment: [:], isQuarantined: { _ in false }, readTarget: { _ in "macos-aarch64" })
        }

        var check: HerdrCheck {
            HerdrCheck(
                resolve: { channel, _, sha in
                    self.lock.withLock {
                        HerdrRelease.Resolution(
                            offered: self.offers[channel] ?? HerdrBuild(base: "0.0.0"),
                            installed: self.published[sha].map { .published($0) } ?? .unpublished)
                    }
                },
                hash: { CLIToolTrust.sha256(of: $0) })
        }

        func status() async throws -> CLIToolStatus {
            let install = try #require(await scanner.scan().first)
            return await check.status(of: install, busy: nil)
        }
    }

    func updater(
        _ box: Sandbox, busy: @escaping HerdrUpdater.BusyCheck = { _ in nil }, environment: [String: String] = [:]
    ) -> HerdrUpdater {
        HerdrUpdater(busy: busy, scanner: box.scanner, check: box.check, environment: { environment },
                     deadline: ChildProcess.Deadline(terminateAfter: .seconds(20), killAfter: .seconds(25)))
    }

    /// The child reads the config the check read and sees every session: `HOME`
    /// is the scanner's, the session-narrowing and testing variables are gone,
    /// the proxy passes through, `PATH` is the system's, stdin is empty — never
    /// a terminal. Kills: keeping `HERDR_SOCKET_PATH`, `HERDR_SESSION` or
    /// `HERDR_FAKE_UPDATE_VERSION`; the caller's `PATH`; an inherited stdin.
    @Test func runsUpdateAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(HerdrBuild(base: "0.9.2"), update: box.updateBody(to: HerdrBuild(base: "0.9.3")))
        let status = try await box.status()
        #expect(status.oneClick?.arguments == ["update"])
        let outcome = await updater(box, environment: [
            "HOME": "/ZZFixture-elsewhere", "PATH": "/somewhere/else", "HERDR_SOCKET_PATH": "/ZZFixture/herdr.sock",
            "HERDR_SESSION": "work", "HERDR_FAKE_UPDATE_VERSION": "9.9.9", "HTTPS_PROXY": "http://127.0.0.1:6152",
            "XDG_CONFIG_HOME": "",
        ]).update(status)
        #expect(outcome == .updated(version: "0.9.3"))
        #expect(box.read("ARGS") == "update\n")
        // An empty pipe: herdr's `is_terminal()` is false and any prompt reads EOF.
        // (Where the test runner's own stdin is an empty pipe too, an inherited
        // stdin reads the same here — measured under `swift test` 2026-10-07 — so
        // this kills the mutation only when the tests run from a terminal.)
        #expect(box.read("STDIN") == "pipe:\n")
        let env = try #require(box.read("ENV")).split(separator: "\n").map(String.init)
        #expect(env.contains("HOME=\(box.home.path)"))
        #expect(env.contains("PATH=\(CLIToolCommandRunner.systemPath)"))
        #expect(env.contains("HTTPS_PROXY=http://127.0.0.1:6152"))
        #expect(!env.contains { $0.hasPrefix("HERDR_SOCKET_PATH=") || $0.hasPrefix("HERDR_SESSION=") })
        #expect(!env.contains { $0.hasPrefix("HERDR_FAKE_UPDATE_VERSION=") || $0.hasPrefix("XDG_CONFIG_HOME=") })
    }

    /// A session that must stop: herdr exits 0 having installed nothing. The
    /// row says what herdr said, and nothing is called updated.
    @Test func aSessionThatMustStopIsHerdrsOwnFailure() async throws {
        let box = try Sandbox()
        try box.install(HerdrBuild(base: "0.9.2"), update: """
            echo "checking stable channel for updates..."
            echo "downloading v0.9.3..."
            echo "downloaded v0.9.3"
            echo "Herdr was not updated."
            echo "Stop running Herdr sessions when ready, then run \\`herdr update\\` again."
            exit 0
            """)
        let outcome = await updater(box).update(try await box.status())
        guard case .failed(let message, let output) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "Herdr was not updated. Stop running Herdr sessions when ready, then run `herdr update` again.")
        #expect(output.contains("downloaded v0.9.3"))
    }

    @Test func aFailedUpdateSaysWhy() async throws {
        let box = try Sandbox()
        try box.install(HerdrBuild(base: "0.9.2"), update: """
            echo "checking stable channel for updates..." >&2
            echo "update failed: failed to fetch update manifest" >&2
            exit 1
            """)
        let outcome = await updater(box).update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "update failed: failed to fetch update manifest")
    }

    /// The file the update left must be a published build, newer.
    @Test func whatTheUpdateLeftMustBePublishedAndNewer() async throws {
        let box = try Sandbox()
        try box.install(HerdrBuild(base: "0.9.2"), update: box.updateBody(to: nil))
        let unpublished = await updater(box).update(try await box.status())
        guard case .failed(let message, _) = unpublished else { Issue.record("\(unpublished)"); return }
        #expect(message.contains("no build herdr published"))

        let older = try Sandbox()
        try older.install(HerdrBuild(base: "0.9.2"), update: older.updateBody(to: HerdrBuild(base: "0.9.1")))
        let downgrade = await updater(older).update(try await older.status())
        guard case .failed(let what, _) = downgrade else { Issue.record("\(downgrade)"); return }
        #expect(what.contains("went from herdr 0.9.2 to 0.9.1"))
    }

    /// Asked again at the click. Mutations: drop the busy check, the identity
    /// check, the settings check, the re-hash, or the channel's re-read.
    @Test func gatesAreAskedAgainAtTheClick() async throws {
        // Busy.
        let busy = try Sandbox()
        try busy.install(HerdrBuild(base: "0.9.2"), update: busy.updateBody(to: HerdrBuild(base: "0.9.3")))
        #expect(await updater(busy, busy: { _ in .update(9) }).update(try await busy.status()) == .busy("herdr update is running (pid 9)"))
        #expect(!busy.ran)

        // Another file in place since the check.
        let replaced = try Sandbox()
        try replaced.install(HerdrBuild(base: "0.9.2"), update: replaced.updateBody(to: HerdrBuild(base: "0.9.3")))
        let status = try await replaced.status()
        try replaced.install(HerdrBuild(base: "0.9.2"), update: replaced.updateBody(to: HerdrBuild(base: "0.9.3")), name: "other")
        guard case .failed = await updater(replaced).update(status) else { Issue.record("ran on another file"); return }
        #expect(!replaced.ran)

        // The channel switched in herdr's config since the check.
        let switched = try Sandbox()
        try switched.install(HerdrBuild(base: "0.9.2"), update: switched.updateBody(to: HerdrBuild(base: "0.9.3")))
        let before = try await switched.status()
        try switched.config("[update]\nchannel = \"preview\"\n")
        guard case .failed = await updater(switched).update(before) else { Issue.record("ran on a switched channel"); return }
        #expect(!switched.ran)

        // The channel moved back: 0.9.2 is all it offers now.
        let movedBack = try Sandbox()
        try movedBack.install(HerdrBuild(base: "0.9.2"), update: movedBack.updateBody(to: HerdrBuild(base: "0.9.3")))
        let offered = try await movedBack.status()
        movedBack.offer("stable", HerdrBuild(base: "0.9.2"))
        let outcome = await updater(movedBack).update(offered)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.contains("now offers 0.9.2"))
        #expect(!movedBack.ran)

        // Not offered: nothing runs.
        let current = try Sandbox()
        try current.install(HerdrBuild(base: "0.9.3"), update: current.updateBody(to: HerdrBuild(base: "0.9.4")))
        #expect(await updater(current).update(try await current.status()) == .notOffered)
        #expect(!current.ran)
    }

    /// The published hash was withdrawn between check and click (or the file
    /// was edited in place with its inode, size and time kept): not run.
    @Test func theHashIsAskedAgainAtTheClick() async throws {
        let box = try Sandbox()
        try box.install(HerdrBuild(base: "0.9.2"), update: box.updateBody(to: HerdrBuild(base: "0.9.3")))
        let status = try await box.status()
        let unpublished = HerdrCheck(
            resolve: { _, _, _ in HerdrRelease.Resolution(offered: HerdrBuild(base: "0.9.3"), installed: .unpublished) },
            hash: { CLIToolTrust.sha256(of: $0) })
        let outcome = await HerdrUpdater(busy: { _ in nil }, scanner: box.scanner, check: unpublished, environment: { [:] })
            .update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.contains("not byte for byte"))
        #expect(!box.ran)
    }

    @Test func declinedReadsHerdrsTwoLines() {
        #expect(HerdrUpdater.declined(["a", "Herdr was not updated.", "Stop it, then run again.", "more"])
            == "Herdr was not updated. Stop it, then run again.")
        #expect(HerdrUpdater.declined(["installed herdr v0.9.3"]) == nil)
    }
}
