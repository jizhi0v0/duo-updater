import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running fx's one-click update: what is run, with which environment, and what
/// the row is told.
///
/// "fx" here is a `#!/bin/sh` script in a temporary directory that prints what
/// the real `fx upgrade` prints (lines measured 2026-10-01) and writes the
/// version it "installed" to a file beside itself, which the injected
/// `--version` reader reads back. The busy check, the signature check and the
/// base environment are injected — nothing here reads the host's process table
/// or settings, runs the real fx or reaches the network.
@Suite struct FxUpdaterTests {

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var fx: URL { home.appendingPathComponent(".local/bin/fx") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("fx-updater-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: fx.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// The fake fx. Its first line marks it Vercel's for the injected check;
        /// `VERSION` beside it is what `--version` answers.
        func fake(_ body: String, version: String = "0.0.11", signer: String = "vercel") throws {
            try Data("#!/bin/sh\n# \(signer)\n\(body)\n".utf8).write(to: fx)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fx.path)
            try Data(version.utf8).write(to: fx.deletingLastPathComponent().appendingPathComponent("VERSION"))
        }

        func exists(_ relative: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
        }

        func read(_ relative: String) -> String? {
            try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        }

        var scanner: FxScanner {
            FxScanner(
                home: home,
                checkSignature: { url in
                    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    return text.contains("# vercel") ? .vercel : .otherSigner
                },
                readVersion: { url in
                    try? String(contentsOf: url.deletingLastPathComponent().appendingPathComponent("VERSION"), encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                },
                isQuarantined: { url in
                    FileManager.default.fileExists(
                        atPath: url.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path)
                })
        }

        /// What the check would have said about the fake install.
        func status() async throws -> CLIToolStatus {
            let install = try #require(await scanner.scan().first)
            let status = await FxCheck(latest: { _ in .stable(version: "0.0.12") })
                .status(of: install, settings: FxSettings(), busy: nil)
            _ = try #require(status.oneClick)
            return status
        }
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    func updater(
        _ box: Sandbox, busy: @escaping FxUpdater.BusyCheck = { _ in nil }, environment: [String: String] = [:]
    ) -> FxUpdater {
        FxUpdater(busy: busy, scanner: box.scanner, environment: { environment })
    }

    @Test func runsFxUpgradeAndRereadsTheVersion() async throws {
        let box = try Sandbox()
        // What 0.0.11 → 0.0.12 printed, progress redraws and all (2026-10-01).
        try box.fake("""
            echo "$@" > "$(dirname "$0")/ARGS"
            echo "$PATH" > "$(dirname "$0")/PATHSEEN"
            echo "$HOME" > "$(dirname "$0")/HOMESEEN"
            printf 'fx 0.0.11 -> 0.0.12\\r\\033[K48%%\\r\\033[K100%%\\r\\033[K' >&2
            echo 0.0.12 > "$(dirname "$0")/VERSION"
            echo 'upgraded to v0.0.12'
            echo 'notes: https://fx.sh/changelog#v0.0.12'
            """)
        let status = try await box.status()
        let lines = Lines()
        let outcome = await updater(box, environment: ["HOME": box.home.path, "PATH": "/somewhere/else"])
            .update(status) { lines.add($0) }
        #expect(outcome == .updated(version: "0.0.12"))
        #expect(box.read("home/.local/bin/ARGS") == "upgrade\n")
        #expect(box.read("home/.local/bin/PATHSEEN") == CLIToolCommandRunner.systemPath + "\n")
        #expect(box.read("home/.local/bin/HOMESEEN") == box.home.path + "\n")
        #expect(lines.all.contains("upgraded to v0.0.12"))
        #expect(lines.all.contains("fx 0.0.11 -> 0.0.12"))
    }

    /// fx's own failure line, without its `error: ` prefix.
    @Test func failureIsFxsReason() async throws {
        let box = try Sandbox()
        try box.fake("""
            echo 'error: failed to fetch latest version from CDN'
            exit 1
            """)
        let outcome = await updater(box).update(try await box.status())
        #expect(outcome == .failed(
            message: "failed to fetch latest version from CDN",
            output: "error: failed to fetch latest version from CDN"))
    }

    @Test func busyAtTheClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.fake("touch \"$(dirname \"$0\")/RAN\"")
        let status = try await box.status()
        let outcome = await updater(box, busy: { _ in .upgradeCommand(99) }).update(status)
        #expect(outcome == .busy("fx upgrade is running (pid 99)"))
        #expect(!box.exists("home/.local/bin/RAN"))
    }

    /// Rule 1 at the click: a file replaced since the check by one that is not
    /// Vercel's is not run.
    @Test func fileNoLongerVercelsIsNotRun() async throws {
        let box = try Sandbox()
        try box.fake("touch \"$(dirname \"$0\")/RAN\"")
        let status = try await box.status()
        try box.fake("touch \"$(dirname \"$0\")/RAN\"", signer: "adhoc")
        let outcome = await updater(box).update(status)
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("not run:"))
        #expect(!box.exists("home/.local/bin/RAN"))
    }

    @Test func fileQuarantinedSinceTheCheckIsNotRun() async throws {
        let box = try Sandbox()
        try box.fake("touch \"$(dirname \"$0\")/RAN\"")
        let status = try await box.status()
        try Data().write(to: box.fx.deletingLastPathComponent().appendingPathComponent("QUARANTINED"))
        let outcome = await updater(box).update(status)
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("not run:"))
        #expect(!box.exists("home/.local/bin/RAN"))
    }

    /// A symlink pointed somewhere else since the check: not the file checked.
    @Test func retargetedLinkIsNotRun() async throws {
        let box = try Sandbox()
        let first = box.root.appendingPathComponent("a/fx")
        let second = box.root.appendingPathComponent("b/fx")
        for url in [first, second] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n# vercel\ntouch \"$(dirname \"$0\")/RAN\"\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try Data("0.0.11".utf8).write(to: url.deletingLastPathComponent().appendingPathComponent("VERSION"))
        }
        try FileManager.default.createSymbolicLink(atPath: box.fx.path, withDestinationPath: first.path)
        let status = try await box.status()
        try FileManager.default.removeItem(at: box.fx)
        try FileManager.default.createSymbolicLink(atPath: box.fx.path, withDestinationPath: second.path)
        let outcome = await updater(box).update(status)
        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(!box.exists("a/RAN") && !box.exists("b/RAN"))
    }

    @Test func noOneClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.fake("touch \"$(dirname \"$0\")/RAN\"")
        let install = try #require(await box.scanner.scan().first)
        let upToDate = await FxCheck(latest: { _ in .stable(version: "0.0.11") })
            .status(of: install, settings: FxSettings(), busy: nil)
        #expect(await updater(box).update(upToDate) == .notOffered)
        #expect(!box.exists("home/.local/bin/RAN"))
    }

    @Test func failureLineRules() {
        let ok = ChildProcess.Outcome(terminationStatus: 1, uncaughtSignal: false, timedOut: false, standardOutput: Data(), standardError: Data())
        let deadline = FxUpdater.defaultDeadline
        #expect(FxUpdater.failureMessage(["fx 0.0.11 -> 0.0.12", "error: failed to download release archive"], ok, deadline: deadline)
            == "failed to download release archive")
        #expect(FxUpdater.failureMessage(["fx upgrade: failed to load update settings"], ok, deadline: deadline)
            == "fx upgrade: failed to load update settings")
        #expect(FxUpdater.failureMessage(["100%"], ok, deadline: deadline) == "exited with status 1")
        let late = ChildProcess.Outcome(terminationStatus: 15, uncaughtSignal: true, timedOut: true, standardOutput: Data(), standardError: Data())
        #expect(FxUpdater.failureMessage(["48%"], late, deadline: deadline) == "stopped: still running after 10 min")
    }
}
