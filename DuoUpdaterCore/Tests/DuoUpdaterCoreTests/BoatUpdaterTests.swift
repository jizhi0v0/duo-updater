import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Running Boat's one-click update: the hash checked at the click, what is run
/// with which environment, and the check of what the update left.
///
/// "boat" here is a `#!/bin/sh` script in a temporary HOME carrying the
/// `&current=<version>` literal the real binary carries. Its `self-update` does
/// what the real one does to the disk — a new file by rename — and prints the
/// JSON line the real one prints to a pipe (measured 2026-10-04). The busy
/// check, the base environment and the published hashes are injected: nothing
/// here reads the host's process table, runs a Boat build or reaches the
/// network.
@Suite struct BoatUpdaterTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".ascii/bin") }
        var boat: URL { bin.appendingPathComponent("boat") }
        /// version → sha256, as each release's SHA256SUMS would say.
        private let lock = NSLock()
        private var published: [String: String] = [:]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("boat-updater-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        static func script(version: String, selfUpdate: String) -> String {
            """
            #!/bin/sh
            # &current=\(version)
            if [ "$1" = self-update ]; then
            \(selfUpdate)
            fi
            """
        }

        static func sha256(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        /// The installed file at `version`, published as such unless `publish`
        /// is false.
        func install(version: String, selfUpdate: String, publish: Bool = true) throws {
            let text = Self.script(version: version, selfUpdate: selfUpdate)
            try Data(text.utf8).write(to: boat)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: boat.path)
            if publish { self.publish(version, Self.sha256(text)) }
        }

        func publish(_ version: String, _ sha: String) { lock.withLock { published[version] = sha } }
        func digest(_ version: String) -> String? { lock.withLock { published[version] } }

        /// What `self-update` does: the new build moved into place, one JSON line.
        /// The new file is published unless `publishNew` is false.
        func selfUpdateBody(to version: String, publishNew: Bool = true) -> String {
            let next = Self.script(version: version, selfUpdate: "exit 0")
            if publishNew { publish(version, Self.sha256(next)) }
            let file = root.appendingPathComponent("next-\(version)")
            try? Data(next.utf8).write(to: file)
            return """
                echo "$@" > "\(root.path)/ARGS"
                env > "\(root.path)/ENV"
                cp "\(file.path)" "\(bin.path)/boat.new" && chmod 755 "\(bin.path)/boat.new"
                mv "\(bin.path)/boat.new" "\(bin.path)/boat"
                echo '{"event":"updated","version":"\(version)"}'
                """
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }

        func read(_ name: String) -> String? {
            try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        }

        var scanner: BoatScanner {
            BoatScanner(home: home, checkSignature: { _ in .adHoc }, isQuarantined: { _ in false },
                        readArchitecture: { _ in "arm64" })
        }

        func check(latest: String = "1.0.38", digestFails: Bool = false) -> BoatCheck {
            BoatCheck(
                latest: { _, _ in latest },
                digest: { version, _ in
                    if digestFails { throw BoatRelease.Failure.http(503) }
                    guard let sha = self.digest(version) else { throw BoatRelease.Failure.http(404) }
                    return sha
                },
                hash: { CLIToolTrust.sha256(of: $0) })
        }

        func status() async throws -> CLIToolStatus {
            let install = try #require(await scanner.scan().first)
            return await check().status(of: install, busy: nil)
        }
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    func updater(
        _ box: Sandbox, check: BoatCheck? = nil, busy: @escaping BoatUpdater.BusyCheck = { nil },
        environment: [String: String] = [:]
    ) -> BoatUpdater {
        BoatUpdater(busy: busy, scanner: box.scanner, check: check ?? box.check(), environment: { environment })
    }

    /// The child reads the config the check read: `HOME` is the scanner's,
    /// `BOAT_API_URL` is gone, the proxy is passed through. Kills: keeping
    /// `BOAT_API_URL`, or a `PATH` from the caller.
    @Test func runsSelfUpdateAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(version: "1.0.37", selfUpdate: box.selfUpdateBody(to: "1.0.38"))
        let status = try await box.status()
        #expect(status.oneClick?.arguments == ["self-update"])
        let lines = Lines()
        let outcome = await updater(box, environment: [
            "HOME": "/ZZFixture-elsewhere", "PATH": "/somewhere/else", "BOAT_API_URL": "https://ZZFixture.example",
            "HTTPS_PROXY": "http://127.0.0.1:6152",
        ]).update(status) { lines.add($0) }
        #expect(outcome == .updated(version: "1.0.38"))
        #expect(box.read("ARGS") == "self-update\n")
        let env = try #require(box.read("ENV"))
        #expect(env.contains("\nHOME=\(box.home.path)\n") || env.hasPrefix("HOME=\(box.home.path)\n"))
        #expect(env.contains("PATH=\(CLIToolCommandRunner.systemPath)\n"))
        #expect(env.contains("HTTPS_PROXY=http://127.0.0.1:6152"))
        #expect(!env.contains("BOAT_API_URL"))
        #expect(lines.all == [#"{"event":"updated","version":"1.0.38"}"#])
    }

    /// The file changed between the check and the click: its new bytes are not
    /// the published build. Kills: trusting the check's verdict at the click.
    @Test func fileReplacedAfterTheCheckIsNotRun() async throws {
        let box = try Sandbox()
        try box.install(version: "1.0.37", selfUpdate: box.selfUpdateBody(to: "1.0.38"))
        let status = try await box.status()
        #expect(status.oneClick != nil)
        try box.install(version: "1.0.37", selfUpdate: box.selfUpdateBody(to: "1.0.38") + "\n# tampered", publish: false)
        let outcome = await updater(box).update(status)
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(message.contains("not byte for byte"))
        #expect(!box.ran)
    }

    /// Another version on disk than the one checked: not run.
    @Test func versionMovedSinceTheCheckIsNotRun() async throws {
        let box = try Sandbox()
        try box.install(version: "1.0.37", selfUpdate: box.selfUpdateBody(to: "1.0.38"))
        let status = try await box.status()
        try box.install(version: "1.0.36", selfUpdate: box.selfUpdateBody(to: "1.0.38"))
        let outcome = await updater(box).update(status)
        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(!box.ran)
    }

    @Test func busyAtTheClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.install(version: "1.0.37", selfUpdate: box.selfUpdateBody(to: "1.0.38"))
        let status = try await box.status()
        let outcome = await updater(box, busy: { .selfUpdate(7) }).update(status)
        #expect(outcome == .busy("boat self-update is running (pid 7)"))
        #expect(!box.ran)
    }

    /// The update ran but left a file that is not the published build of the
    /// version it now reads as. Kills: reporting "updated" on the exit status.
    @Test func unpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "1.0.37", selfUpdate: box.selfUpdateBody(to: "1.0.38", publishNew: false))
        let status = try await box.status()
        let outcome = await updater(box).update(status)
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(message.contains("boat self-update finished"))
        #expect(box.ran)
    }

    /// Exit 0 with the same version on disk: Boat said it was up to date, or
    /// the swap did not happen. Not "updated".
    @Test func sameVersionAfterwardsIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "1.0.37", selfUpdate: #"echo '{"event":"up_to_date"}'"#)
        let status = try await box.status()
        let outcome = await updater(box).update(status)
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(message.contains("still boat 1.0.37"))
    }

    /// The JSON error line Boat prints to a pipe, measured with a dead proxy.
    @Test func failureIsBoatsOwnErrorLine() async throws {
        let box = try Sandbox()
        let error = #"{"error":"error sending request for url (https://boat.dev/api/boat/cli/version?platform=darwin-arm64&channel=prod&current=1.0.37): client error (Connect): tunnel error: failed to create underlying connection: tcp connect error: Connection refused (os error 61)","event":"error"}"#
        try box.install(version: "1.0.37", selfUpdate: "echo '\(error)'\nexit 1")
        let status = try await box.status()
        let outcome = await updater(box).update(status)
        guard case .failed(let message, let output) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(message.hasPrefix("error sending request for url (https://boat.dev/api/boat/cli/version?"))
        #expect(message.hasSuffix("Connection refused (os error 61)"))
        #expect(output.contains(#""event":"error""#))
    }

    @Test func notOfferedRunsNothing() async throws {
        let box = try Sandbox()
        try box.install(version: "1.0.38", selfUpdate: box.selfUpdateBody(to: "1.0.39"))
        let status = try await box.status()
        #expect(status.state == .upToDate)
        #expect(await updater(box).update(status) == .notOffered)
        #expect(!box.ran)
    }
}
