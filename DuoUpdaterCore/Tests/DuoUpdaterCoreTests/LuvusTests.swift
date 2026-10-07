import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Luvus: finding it where its installer puts it, its verdict, the archive check
/// the trust rule rests on, its one-click update and its release notes.
///
/// "luvus" here is a `#!/bin/sh` script in a temporary directory, carrying the
/// `luvus <version>` literal every real build carries (measured 2026-10-07 on
/// 0.11.0 to 0.14.3). Its `update` does what the real one does to the disk —
/// stages a copy beside the file and renames it over it. The manifest, the
/// release downloads and their unpacking are injected: nothing here reads the
/// host's process table, runs a Luvus build or reaches the network.
@Suite struct LuvusTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var userBin: URL { home.appendingPathComponent(".local/bin") }
        var systemBin: URL { root.appendingPathComponent("ZZFixture-usr-local-bin") }
        let digests: LuvusPublishedDigests
        private let lock = NSLock()
        /// version → the `luvus` its release archive holds.
        private var published: [String: String] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("luvus-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            // Canonical, as luvus compares paths: `/var/folders` is `/private/var/folders`.
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = LuvusPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: userBin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: systemBin, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: userBin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func script(version: String, update: String = "exit 0") -> String {
            """
            #!/bin/sh
            # luvus \(version) (as `--version` prints it), and again: luvus \(version)
            if [ "$1" = update ]; then
            \(update)
            fi
            """
        }

        /// A luvus at `dir/luvus`, published for its version unless `publish` is false.
        @discardableResult
        func install(at dir: URL, version: String, update: String = "exit 0", publish: Bool = true) throws -> URL {
            let text = Self.script(version: version, update: update)
            let file = dir.appendingPathComponent("luvus")
            try Data(text.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            if publish { self.publish(version, text) }
            return file
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        var downloadCount: Int { lock.withLock { downloads } }

        /// What `luvus update` does to `dir`: stage the new build beside the old
        /// one and rename it into place. Published unless `publishNew` is false.
        func updateBody(in dir: URL, to version: String, publishNew: Bool = true) throws -> String {
            let next = Self.script(version: version)
            if publishNew { publish(version, next) }
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            return """
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$PATH" > "\(root.path)/PATHLS"
                /bin/cp "\(staged.path)" "\(dir.path)/.luvus-update-$$" || exit 1
                /bin/chmod 755 "\(dir.path)/.luvus-update-$$"
                /bin/mv -f "\(dir.path)/.luvus-update-$$" "\(dir.path)/luvus"
                echo "Updated Luvus"
                """
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        var scanner: LuvusScanner {
            LuvusScanner(home: home, systemDirectory: systemBin, isQuarantined: { _ in false },
                         readTarget: { _ in "aarch64-apple-darwin" })
        }

        static func archive(_ version: String) -> Data { Data("tgz-\(version)".utf8) }

        /// The release assets: `<stem>.sha256` and `<stem>.tar.gz` of every
        /// published version, `tamper` serving an archive its digest does not name.
        func verifier(tamper: Bool = false) -> LuvusVerifier {
            LuvusVerifier(
                download: { url in
                    let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                    guard self.lock.withLock({ self.published[version] }) != nil else {
                        throw LuvusRelease.Failure.http(404)
                    }
                    if url.pathExtension == "sha256" {
                        let hex = SHA256.hash(data: Self.archive(version)).map { String(format: "%02x", $0) }.joined()
                        return Data("\(hex)  luvus-v\(version)-aarch64-apple-darwin.tar.gz\n".utf8)
                    }
                    self.lock.withLock { self.downloads += 1 }
                    return tamper ? Data("other".utf8) : Self.archive(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
                        .replacingOccurrences(of: "tgz-", with: "")
                    let text = self.lock.withLock { self.published[version] } ?? ""
                    try Data(text.utf8).write(to: directory.appendingPathComponent("luvus"))
                },
                digests: digests)
        }

        func release(latest: String = "0.14.3", fails: Bool = false) -> LuvusRelease {
            LuvusRelease(fetch: { url in
                if fails { throw LuvusRelease.Failure.http(503) }
                #expect(url == LuvusRelease.manifest)
                return (Data(#"{"version": "\#(latest)", "date": "2026-09-30", "notes": "…"}"#.utf8), 200)
            })
        }

        func check(latest: String = "0.14.3", fails: Bool = false) -> LuvusCheck {
            let release = release(latest: latest, fails: fails)
            let verifier = verifier()
            return LuvusCheck(latest: { try await release.latest() },
                              knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
        }

        func updater(latest: String = "0.14.3", busy: @escaping LuvusUpdater.BusyCheck = { nil }) -> LuvusUpdater {
            LuvusUpdater(
                busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(),
                environment: {
                    ["LUVUS_UPDATE_MANIFEST": "file:///elsewhere/latest.json",
                     "LUVUS_UPDATE_RELEASE_BASE": "https://elsewhere.example", "KEEP": "1"]
                })
        }

        func status(latest: String = "0.14.3", busy: LuvusActivity.Busy? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(latest: latest).status(of: install, busy: busy)
        }
    }

    // MARK: - Finding it

    /// Both of the installer's places, each read from its own bytes.
    /// Mutation: look only in `~/.local/bin`.
    @Test func findsBothInstallerLocations() throws {
        let box = try Sandbox()
        let system = try box.install(at: box.systemBin, version: "0.14.1")
        let user = try box.install(at: box.userBin, version: "0.14.2")
        #expect(box.scanner.scan() == [
            LuvusInstall(path: system.path, binary: system.path, version: "0.14.1"),
            LuvusInstall(path: user.path, binary: user.path, version: "0.14.2"),
        ])
    }

    /// The version literal as it sits in a real build: between other literals,
    /// with `luvus ` before words that are not versions. Mutations: take the
    /// first `luvus ` only; accept disagreeing versions.
    @Test func readsTheCompiledVersion() {
        func windows(_ text: String) -> [Data] {
            let data = Data(text.utf8)
            var out: [Data] = []
            var start = data.startIndex
            while let range = data.range(of: LuvusScanner.marker, in: start..<data.endIndex) {
                out.append(Data(data[range.lowerBound..<min(data.endIndex, range.upperBound + 48)]))
                start = range.upperBound
            }
            return out
        }
        #expect(LuvusScanner.compiledVersion(in: windows(
            "usage: luvus update\0invocationluvus 0.14.3\0handshakeluvus 0.14.3running")) == "0.14.3")
        #expect(LuvusScanner.compiledVersion(in: windows("luvus 1.0.0-rc.1\0")) == "1.0.0-rc.1")
        #expect(LuvusScanner.compiledVersion(in: windows("luvus 0.14.3 and luvus 0.14.2")) == nil)
        #expect(LuvusScanner.compiledVersion(in: windows("usage: luvus update")) == nil)
    }

    /// A link from one place to the other is one install, under the file's own
    /// path; Homebrew's is the brew group's; a link anywhere else is reported,
    /// since `luvus update` refuses it; a dangling one is broken.
    @Test func linksAreClassifiedAsLuvusDoes() throws {
        let box = try Sandbox()
        let user = try box.install(at: box.userBin, version: "0.14.2")
        try FileManager.default.createSymbolicLink(atPath: box.systemBin.appendingPathComponent("luvus").path,
                                                   withDestinationPath: user.path)
        #expect(box.scanner.scan().map(\.path) == [user.path])

        try FileManager.default.removeItem(at: box.systemBin.appendingPathComponent("luvus"))
        try FileManager.default.removeItem(at: user)
        let cellar = box.root.appendingPathComponent("opt/homebrew/Cellar/luvus/0.14.3/bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        let brewed = try box.install(at: cellar, version: "0.14.3")
        try FileManager.default.createSymbolicLink(atPath: user.path, withDestinationPath: brewed.path)
        #expect(box.scanner.scan().isEmpty)

        try FileManager.default.removeItem(at: user)
        let elsewhere = box.root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let loose = try box.install(at: elsewhere, version: "0.14.2")
        try FileManager.default.createSymbolicLink(atPath: user.path, withDestinationPath: loose.path)
        #expect(box.scanner.scan().first?.problem == .unknownLocation)

        try FileManager.default.removeItem(at: loose)
        #expect(box.scanner.scan().first?.problem == .executableMissing)
    }

    /// The two system paths luvus names are direct installs whatever their case,
    /// `/opt/local/bin/luvus` included though the installer never writes it, so a
    /// link to it is not reported as one `luvus update` refuses. Mutation: drop
    /// the `/opt/local/bin` path.
    @Test func systemPathsAreDirectAsLuvusSays() throws {
        let box = try Sandbox()
        #expect(box.scanner.classify("/opt/local/bin/luvus") == .direct)
        #expect(box.scanner.classify("/USR/LOCAL/BIN/luvus") == .direct)
        #expect(box.scanner.classify("/opt/local/bin/luvus-old") == .unknown)
    }

    /// luvus compares its canonical path with `$HOME/.local/bin/luvus` as
    /// `$HOME` is written, so a home reached through a link is not a direct
    /// install to it. Mutation: canonicalize the home too.
    @Test func homeIsTakenAsWritten() throws {
        let box = try Sandbox()
        try box.install(at: box.userBin, version: "0.14.2")
        let linkedHome = box.root.appendingPathComponent("linked-home")
        try FileManager.default.createSymbolicLink(atPath: linkedHome.path, withDestinationPath: box.home.path)
        let scanner = LuvusScanner(home: linkedHome, systemDirectory: box.systemBin, isQuarantined: { _ in false },
                                   readTarget: { _ in "aarch64-apple-darwin" })
        #expect(scanner.scan().first?.problem == .unknownLocation)
    }

    @Test func nothingInstalledIsNothing() throws {
        let box = try Sandbox()
        #expect(box.scanner.scan().isEmpty)
    }

    // MARK: - The verdict

    /// An update is `luvus update` on the file itself.
    @Test func offersLuvusUpdate() async throws {
        let box = try Sandbox()
        let luvus = try box.install(at: box.userBin, version: "0.14.2")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "0.14.3")
        #expect(status.channel == nil)
        #expect(status.oneClick == CLIToolCommand(executable: luvus.path, arguments: ["update"], pathPrefix: nil))
        // Nothing was downloaded to decide it.
        #expect(box.downloadCount == 0)
    }

    @Test func comparesBySemver() async throws {
        let box = try Sandbox()
        try box.install(at: box.userBin, version: "0.14.3")
        #expect(try await box.status().state == .upToDate)
        try box.install(at: box.userBin, version: "0.15.0")
        let ahead = try await box.status()
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    /// Mutations: drop any one gate.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install(at: box.userBin, version: "0.11.0")
        let old = try await box.status()
        #expect(old.withheld == .unsupportedInstaller)
        #expect(old.oneClick == nil)

        try box.install(at: box.userBin, version: "0.14.2")
        #expect(try await box.status(busy: .update(42)).withheld == .busy)
        #expect(await box.check(fails: true).status(of: try #require(box.scanner.scan().first), busy: nil)
            .withheld == .channelUnreadable)

        let path = box.userBin.appendingPathComponent("luvus").path
        let quarantined = LuvusInstall(path: path, binary: path, version: "0.14.2", quarantined: true)
        #expect(await box.check().status(of: quarantined, busy: nil).withheld == .unverified)

        // A folder `luvus update` could only write to with sudo.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.userBin.path)
        let readOnly = try await box.status()
        #expect(readOnly.withheld == .unsupportedInstaller)
        #expect(readOnly.oneClick == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.userBin.path)
    }

    /// Once the release's digest is known, a copy that is not the published
    /// build is withheld by the check itself. Mutation: ignore the known digest.
    @Test func aKnownDigestThatDiffersIsWithheld() async throws {
        let box = try Sandbox()
        box.publish("0.14.2", Sandbox.script(version: "0.14.2"))
        let luvus = try box.install(at: box.userBin, version: "0.14.2", update: "echo altered", publish: false)
        let result = await box.verifier().verify(binary: luvus.path, version: "0.14.2", target: "aarch64-apple-darwin")
        guard case .differs = result else { Issue.record("expected differs, got \(result)"); return }
        let status = try await box.status()
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)

        // Replaced by the published build: the same known digest now matches.
        try box.install(at: box.userBin, version: "0.14.2", publish: false)
        #expect(try await box.status().oneClick != nil)
        #expect(box.downloadCount == 1)
    }

    // MARK: - The archive check

    /// The archive must match the digest published beside it; its `luvus` is
    /// compared with the file, and that digest is remembered so the archive is
    /// downloaded once per version. Mutations: skip the archive's digest; compare
    /// nothing; never remember.
    @Test func verifiesAgainstTheReleaseArchive() async throws {
        let box = try Sandbox()
        let luvus = try box.install(at: box.userBin, version: "0.14.2").path
        #expect(await box.verifier().verify(binary: luvus, version: "0.14.2", target: "aarch64-apple-darwin") == .matches)
        #expect(await box.verifier().verify(binary: luvus, version: "0.14.2", target: "aarch64-apple-darwin") == .matches)
        #expect(box.downloadCount == 1)
        #expect(box.digests.digest(version: "0.14.2", target: "aarch64-apple-darwin")
            == CLIToolTrust.sha256(of: URL(fileURLWithPath: luvus)))

        let tampered = await box.verifier(tamper: true).verify(binary: luvus, version: "0.14.1", target: "aarch64-apple-darwin")
        guard case .couldNotVerify = tampered else { Issue.record("expected couldNotVerify, got \(tampered)"); return }
        box.publish("0.14.1", "x")
        let tamperedPublished = await box.verifier(tamper: true).verify(binary: luvus, version: "0.14.1", target: "aarch64-apple-darwin")
        guard case .couldNotVerify = tamperedPublished else { Issue.record("expected couldNotVerify, got \(tamperedPublished)"); return }
        #expect(box.digests.digest(version: "0.14.1", target: "aarch64-apple-darwin") == nil)

        let badTarget = await box.verifier().verify(binary: luvus, version: "0.14.2", target: "x86_64-unknown-linux-musl")
        guard case .couldNotVerify = badTarget else { Issue.record("expected couldNotVerify, got \(badTarget)"); return }
    }

    /// The manifest's version, with luvus's leading `v` trimmed; anything else
    /// is unreadable.
    @Test func readsTheManifest() async throws {
        let ok = LuvusRelease(fetch: { _ in (Data(#"{"version": "v0.14.3"}"#.utf8), 200) })
        #expect(try await ok.latest() == "0.14.3")
        let bad = LuvusRelease(fetch: { _ in (Data(#"{"version": "../../x"}"#.utf8), 200) })
        await #expect(throws: LuvusRelease.Failure.self) { try await bad.latest() }
        let down = LuvusRelease(fetch: { _ in (Data(), 502) })
        await #expect(throws: LuvusRelease.Failure.http(502)) { try await down.latest() }
        #expect(LuvusRelease.archiveURL(version: "0.14.3", target: "aarch64-apple-darwin").absoluteString
            == "https://github.com/RizRiyz/luvus/releases/download/v0.14.3/luvus-v0.14.3-aarch64-apple-darwin.tar.gz")
    }

    // MARK: - The update

    /// The click checks the old file against its release, runs `luvus update`
    /// without the manifest and download overrides and with only curl and tar
    /// on PATH, and checks what it left.
    @Test func updatesAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(at: box.userBin, version: "0.14.2", update: try box.updateBody(in: box.userBin, to: "0.14.3"))
        let outcome = await box.updater().update(try await box.status())
        #expect(outcome == .updated(version: "0.14.3"))
        #expect(box.read("ARGS") == "update\n")
        let env = box.read("ENV") ?? ""
        #expect(!env.contains("LUVUS_UPDATE_MANIFEST="))
        #expect(!env.contains("LUVUS_UPDATE_RELEASE_BASE="))
        #expect(env.contains("KEEP=1"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        // No sudo for luvus's fallback to find.
        #expect(box.read("PATHLS") == "curl\ntar\n")
        // The old version's archive and the new one's: once each.
        #expect(box.downloadCount == 2)
        #expect(box.scanner.scan().first?.version == "0.14.3")
    }

    /// What the update left must be the published build of a newer version.
    /// Mutation: report `.updated` without verifying the new file.
    @Test func anUnpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(at: box.userBin, version: "0.14.2",
                        update: try box.updateBody(in: box.userBin, to: "0.14.3", publishNew: false))
        box.publish("0.14.3", "the real 0.14.3")
        let outcome = await box.updater().update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(message.contains("is not the luvus 0.14.3 RizRiyz published"))
    }

    /// An update that exits 0 having changed nothing is not "updated".
    @Test func anUnchangedFileIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(at: box.userBin, version: "0.14.2", update: "echo 'Luvus 0.14.2 is already up to date.'")
        let outcome = await box.updater().update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(message.contains("is still luvus 0.14.2"))
    }

    /// Nothing runs when the old file is not the published build, when the
    /// manifest moved back, when the folder stopped being writable, or when an
    /// update is already running.
    @Test func gatesAreAskedAgainAtTheClick() async throws {
        let box = try Sandbox()
        try box.install(at: box.userBin, version: "0.14.2", update: try box.updateBody(in: box.userBin, to: "0.14.3"))
        let status = try await box.status()

        #expect(await box.updater(busy: { .update(7) }).update(status) == .busy("luvus update is running (pid 7)"))
        guard case .failed(let moved, _) = await box.updater(latest: "0.14.2").update(status) else {
            Issue.record("ran on a manifest that moved back"); return
        }
        #expect(moved.hasPrefix("not run:"))

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.userBin.path)
        guard case .failed(let sudo, _) = await box.updater().update(status) else { Issue.record("ran toward sudo"); return }
        #expect(sudo.contains("would need sudo"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.userBin.path)

        box.publish("0.14.2", "not this file")
        guard case .failed(let message, _) = await box.updater().update(status) else { Issue.record("ran unverified"); return }
        #expect(message.hasPrefix("not run:"))
        #expect(!box.ran)
    }

    /// The row's line is anyhow's `Error:` with its first cause, as luvus printed
    /// it for a read-only folder with no sudo on PATH (2026-10-07).
    @Test func failureLineIsLuvussOwnError() {
        let outcome = ChildProcess.Outcome(
            terminationStatus: 1, uncaughtSignal: false, timedOut: false, standardOutput: Data(), standardError: Data())
        let lines = [
            "Checking for Luvus updates...", "Luvus 0.14.3 is available (current: 0.14.2).",
            "Error: stage an update beside /Users/ann/.local/bin/luvus with administrator permission",
            "Caused by:", "    No such file or directory (os error 2)",
        ]
        #expect(LuvusUpdater.failureMessage(lines, outcome, deadline: LuvusUpdater.defaultDeadline)
            == "stage an update beside /Users/ann/.local/bin/luvus with administrator permission: No such file or directory (os error 2)")
        #expect(LuvusUpdater.failureMessage(
            ["Error: could not check https://luvus.dev/latest.json; check your connection and try again"],
            outcome, deadline: LuvusUpdater.defaultDeadline)
            == "could not check https://luvus.dev/latest.json; check your connection and try again")
    }

    // MARK: - Busy

    /// `update` as the word luvus dispatches on; a subcommand's own `update`
    /// is not. Mutation: match any argument.
    @Test func busyIsLuvusReplacingItself() {
        #expect(LuvusActivity.isUpdate(["luvus", "update"]))
        #expect(LuvusActivity.isUpdate(["/Users/ann/.local/bin/luvus", "update"]))
        #expect(!LuvusActivity.isUpdate(["luvus", "task", "update", "3"]))
        #expect(!LuvusActivity.isUpdate(["luvus", "server", "update-manifest"]))
        #expect(!LuvusActivity.isUpdate(["luvusx", "update"]))
        let curl = ClaudeCodeActivity.Process(pid: 9, arguments: [
            "curl", "-fsSL", "-o", "/tmp/x/luvus-v0.14.3-aarch64-apple-darwin.tar.gz",
            "https://github.com/RizRiyz/luvus/releases/download/v0.14.3/luvus-v0.14.3-aarch64-apple-darwin.tar.gz",
        ])
        #expect(LuvusActivity.busy(processes: [curl]) == .download(9))
        #expect(LuvusActivity.busy(processes: [.init(pid: 3, arguments: ["luvus", "update"])]) == .update(3))
        #expect(LuvusActivity.busy(processes: [.init(pid: 4, arguments: ["curl", "https://luvus.dev/latest.json"])]) == nil)
    }

    // MARK: - Release notes

    /// GitHub releases through the production decoder, without the issue
    /// reporters and contributors every recent release ends with. The body is an
    /// excerpt of 0.14.3's (fetched 2026-10-07), byte for byte in the lines kept.
    /// Mutation: drop `skipSections`.
    @Test func releaseNotesLeaveOutTheCredits() throws {
        let body = """
            Luvus v0.14.3 adds Luvus Web, Commander, pane-local search, Arc Studio CLI support, and more extensible modules, with safer agent control and smoother session handling. Existing v0.14.2 settings and sessions remain compatible; restart running servers after upgrading.

            ## Features

            - **Web:** Open your workspaces and terminals in a browser with one-use pairing, read-only access by default, and optional control ([`eea2b2c`](https://github.com/RizRiyz/luvus/commit/eea2b2ce539a7509815e3c311648115b0f52885c), [#403](https://github.com/RizRiyz/luvus/pull/403)).

            ## Fixes

            - **Search:** Find and highlight text within terminal scrollback, files, DIFF, Markdown, and Mermaid views ([`0c5ac30`](https://github.com/RizRiyz/luvus/commit/0c5ac30cb9e3686a498521fccdafe99feec1bef0), [#414](https://github.com/RizRiyz/luvus/pull/414)).

            ## Contributors

            <p>
            <a href="https://github.com/adexaja" title="Rezki Nasrullah (@adexaja)"><img src="https://github.com/adexaja.png?size=80" alt="Rezki Nasrullah (@adexaja)" width="40" height="40"></a>
            </p>

            - [Rezki Nasrullah (@adexaja)](https://github.com/adexaja)

            ## Issue reporters

            - [Kielas (@Kielas520)](https://github.com/Kielas520)

            ## Full changelog

            https://github.com/RizRiyz/luvus/compare/v0.14.2...v0.14.3
            """
        let releases: [[String: Any]] = [
            ["tag_name": "v0.14.3", "prerelease": false, "draft": false, "published_at": "2026-09-30T14:38:11Z", "body": body],
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: releases), as: UTF8.self)
        let log = try #require(LuvusChangelog.parse(json))
        #expect(log.entries.map(\.version) == ["0.14.3"])
        let entry = try #require(log.entries.first)
        #expect(entry.content.contains(.heading("Features")))
        #expect(entry.content.contains(.heading("Fixes")))
        #expect(!entry.content.contains(.heading("Issue reporters")))
        #expect(entry.items.count == 2)
        #expect(entry.items.first?.hasPrefix("**Web:** Open your workspaces") == true)
        #expect(!entry.items.contains { $0.contains("Kielas") || $0.contains("adexaja") })
    }
}
