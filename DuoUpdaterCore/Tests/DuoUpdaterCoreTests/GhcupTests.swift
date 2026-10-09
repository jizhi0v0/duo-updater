import Testing
import Foundation
@testable import DuoUpdaterCore

/// GHCup's own binary: finding it, the version it claims and the hash that
/// confirms it, its metadata, its verdict, its one-click update and its release
/// notes.
///
/// "ghcup" here is a `#!/bin/sh` script in a temporary home carrying the
/// `ghcup-<version>-inplace` package ids every real build carries (measured
/// 2026-10-09 on 0.2.6.1 and 0.2.6.2). Its `upgrade` does what the real one does
/// to the disk — deletes the file and copies the new one in. The metadata and
/// `SHA256SUMS` are injected: nothing here reads the host's process table, runs
/// a ghcup build or reaches the network.
@Suite struct GhcupTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".ghcup/bin") }
        var ghcup: URL { bin.appendingPathComponent("ghcup") }
        let digests: GhcupPublishedDigests
        let facts: GhcupFileFacts
        private let lock = NSLock()
        /// version → the published binary's text.
        private var published: [String: String] = [:]
        private var reads = 0
        private var sumsFetched = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-ghcup-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = GhcupPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            facts = GhcupFileFacts(fileURL: root.appendingPathComponent("facts.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func script(version: String, upgrade: String = "exit 0") -> String {
            """
            #!/bin/sh
            # base-4.18-inplace ghcup-\(version)-inplace\u{0}ghcup-\(version)-inplace-ghcup
            if [ "$1" = upgrade ]; then
            \(upgrade)
            fi
            """
        }

        @discardableResult
        func install(version: String, upgrade: String = "exit 0", publish: Bool = true) throws -> URL {
            let text = Self.script(version: version, upgrade: upgrade)
            try Data(text.utf8).write(to: ghcup)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghcup.path)
            if publish { self.publish(version, text) }
            return ghcup
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        var readCount: Int { lock.withLock { reads } }
        var sumsCount: Int { lock.withLock { sumsFetched } }

        /// What `ghcup upgrade` does: delete the file, copy the new one in.
        func upgradeBody(to version: String, publishNew: Bool = true) throws -> String {
            let next = Self.script(version: version)
            if publishNew { publish(version, next) }
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            return """
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "\(root.path)" > /dev/null
                for d in $(echo "$PATH" | /usr/bin/tr ':' ' '); do /bin/ls "$d"; done > "\(root.path)/PATHLS"
                /bin/rm -f "\(ghcup.path)"
                /bin/cp "\(staged.path)" "\(ghcup.path)"
                /bin/chmod 755 "\(ghcup.path)"
                echo "[ Info  ] Successfully upgraded GHCup to version \(version)"
                """
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        var scanner: GhcupScanner {
            GhcupScanner(home: home, isQuarantined: { _ in false }, readTarget: { _ in "aarch64-apple-darwin" },
                         readFile: { url in
                             self.lock.withLock { self.reads += 1 }
                             return GhcupScanner.readFile(url)
                         },
                         facts: facts)
        }

        /// `SHA256SUMS` of every published version, with the `.sig` and `test-`
        /// lines a real one has around the binary's.
        func verifier() -> GhcupVerifier {
            GhcupVerifier(
                download: { url in
                    let version = url.deletingLastPathComponent().lastPathComponent
                    guard let text = self.lock.withLock({ self.published[version] }) else {
                        throw GhcupRelease.Failure.http(404)
                    }
                    self.lock.withLock { self.sumsFetched += 1 }
                    let file = self.root.appendingPathComponent("sums-\(UUID().uuidString)")
                    try Data(text.utf8).write(to: file)
                    let hex = CLIToolTrust.sha256(of: file) ?? ""
                    let zeros = String(repeating: "0", count: 64)
                    return Data("""
                        \(zeros)  ./test-aarch64-apple-darwin-ghcup-\(version)
                        \(hex)  ./aarch64-apple-darwin-ghcup-\(version)
                        \(zeros)  ./aarch64-apple-darwin-ghcup-\(version).sig

                        """.utf8)
                },
                digests: digests)
        }

        func check(latest: String = "0.2.6.2", fails: Bool = false) -> GhcupCheck {
            let verifier = verifier()
            return GhcupCheck(
                latest: { if fails { throw GhcupRelease.Failure.http(429) }; return latest },
                verify: { await verifier.verify(sha256: $0, version: $1, target: $2) })
        }

        func updater(latest: String = "0.2.6.2", busy: @escaping GhcupUpdater.BusyCheck = { nil }) -> GhcupUpdater {
            GhcupUpdater(
                busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(),
                environment: {
                    ["GHCUP_INSTALL_BASE_PREFIX": "/elsewhere", "GHCUP_USE_XDG_DIRS": "1", "XDG_BIN_HOME": "/elsewhere",
                     "KEEP": "1"]
                })
        }

        func status(latest: String = "0.2.6.2", busy: GhcupActivity.Busy? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(latest: latest).status(of: install, busy: busy)
        }
    }

    // MARK: - Finding it

    /// The claimed version, and the file hashed once per change of the file.
    /// Mutation: never remember the facts.
    @Test func readsTheFileOncePerChange() throws {
        let box = try Sandbox()
        let ghcup = try box.install(version: "0.2.6.1")
        let first = try #require(box.scanner.scan().first)
        #expect(first.version == "0.2.6.1")
        #expect(first.sha256 == CLIToolTrust.sha256(of: ghcup))
        _ = box.scanner.scan()
        #expect(box.readCount == 1)
        // A new file (new inode) is read again.
        try FileManager.default.removeItem(at: ghcup)
        try box.install(version: "0.2.6.2")
        #expect(box.scanner.scan().first?.version == "0.2.6.2")
        #expect(box.readCount == 2)
    }

    /// Only `ghcup-<version>-inplace` package ids, and only when they agree.
    /// Mutations: accept another package's id; accept disagreeing versions.
    @Test func claimedVersionIsGhcupsPackageId() {
        func windows(_ text: String) -> [Data] {
            let data = Data(text.utf8)
            var out: [Data] = []
            var start = data.startIndex
            while let range = data.range(of: GhcupScanner.marker, in: start..<data.endIndex) {
                out.append(Data(data[max(data.startIndex, range.lowerBound - 32)..<range.upperBound]))
                start = range.upperBound
            }
            return out
        }
        #expect(GhcupScanner.claimedVersion(in: windows("base-4.18-inplace\0ghcup-0.2.6.2-inplace")) == "0.2.6.2")
        #expect(GhcupScanner.claimedVersion(in: windows("notghcup-1.0-inplace")) == nil)
        #expect(GhcupScanner.claimedVersion(in: windows("libghcup-2.0-inplace\0ghcup-0.2.6.2-inplace")) == "0.2.6.2")
        #expect(GhcupScanner.claimedVersion(in: windows("ghcup-0.2.6.2-inplace ghcup-0.2.6.1-inplace")) == nil)
    }

    /// A link is reported: `ghcup upgrade` would replace it with a file.
    @Test func aLinkIsReported() async throws {
        let box = try Sandbox()
        let elsewhere = box.root.appendingPathComponent("ghcup-real")
        try Data(Sandbox.script(version: "0.2.6.1").utf8).write(to: elsewhere)
        try FileManager.default.createSymbolicLink(atPath: box.ghcup.path, withDestinationPath: elsewhere.path)
        #expect(box.scanner.scan().first?.problem == .link)
        #expect(try await box.status().withheld == .unsupportedInstaller)
    }

    @Test func nothingInstalledIsNothing() throws {
        #expect(try Sandbox().scanner.scan().isEmpty)
    }

    // MARK: - Metadata

    /// The `GHCup` tool's version tagged `Latest`, whatever indentation its
    /// `viTags` list takes; other tools' tags are not its. Mutations: read only
    /// the deeper indentation; take the first tool's `Latest`.
    @Test func readsTheMetadata() {
        let yaml = """
            ghcupDownloads:
              GHC:
                toolVersions:
                  9.14.1:
                    viTags:
                      - Latest
              GHCup:
                toolDetails:
                  toolHomepage: "https://www.haskell.org/ghcup/"
                toolVersions:
                  0.2.6.1:
                    viTags: []
                  0.2.6.2:
                    viTags:
                    - Recommended
                    - Latest
                    viArch:
                      A_ARM64:
                        Darwin:
                          unknown_versioning:
                            dlHash: 4e521e008fe0813db6db4b91cfeebd0c44c80c68afb458ea32a1c94cf5c7cc1d
              HLS:
                toolVersions:
                  2.13.0.0:
                    viTags: [Latest]
            """
        #expect(GhcupRelease.latest(inMetadata: yaml) == "0.2.6.2")
        let deeper = yaml.replacingOccurrences(of: "        - Recommended\n        - Latest", with: "          - Latest")
        #expect(GhcupRelease.latest(inMetadata: deeper) == "0.2.6.2")
        let inline = yaml.replacingOccurrences(of: "        viTags:\n        - Recommended\n        - Latest",
                                               with: "        viTags: [Recommended, Latest]")
        #expect(GhcupRelease.latest(inMetadata: inline) == "0.2.6.2")
        #expect(GhcupRelease.latest(inMetadata: yaml.replacingOccurrences(of: "    - Latest\n        viArch", with: "    viArch")) == nil)
    }

    /// The binary's own line, not its `.sig` or the `test-` build.
    @Test func readsSHA256SUMS() {
        let sums = """
            1111111111111111111111111111111111111111111111111111111111111111  ./test-aarch64-apple-darwin-ghcup-0.2.6.2
            4e521e008fe0813db6db4b91cfeebd0c44c80c68afb458ea32a1c94cf5c7cc1d  ./aarch64-apple-darwin-ghcup-0.2.6.2
            2222222222222222222222222222222222222222222222222222222222222222  ./aarch64-apple-darwin-ghcup-0.2.6.2.sig
            """
        #expect(GhcupRelease.digest(inSums: sums, asset: "aarch64-apple-darwin-ghcup-0.2.6.2")
            == "4e521e008fe0813db6db4b91cfeebd0c44c80c68afb458ea32a1c94cf5c7cc1d")
        #expect(GhcupRelease.digest(inSums: sums, asset: "x86_64-apple-darwin-ghcup-0.2.6.2") == nil)
    }

    // MARK: - The verdict

    @Test func offersGhcupUpgrade() async throws {
        let box = try Sandbox()
        let ghcup = try box.install(version: "0.2.6.1")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "0.2.6.1")
        #expect(status.oneClick == CLIToolCommand(executable: ghcup.path, arguments: ["upgrade"], pathPrefix: box.bin.path))
        #expect(try await box.status(latest: "0.2.6.1").state == .upToDate)
        // The SHA256SUMS is fetched once and remembered.
        _ = try await box.status()
        #expect(box.sumsCount == 1)
    }

    /// A file that claims a version but is not its published build is never run.
    /// Mutation: drop the hash gate.
    @Test func anUnpublishedFileIsWithheld() async throws {
        let box = try Sandbox()
        box.publish("0.2.6.1", "the real 0.2.6.1")
        try box.install(version: "0.2.6.1", publish: false)
        let status = try await box.status()
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)
    }

    /// Mutations: drop any one gate.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "0.2.6.1")
        #expect(try await box.status(busy: .upgrade(4)).withheld == .busy)
        #expect(await box.check(fails: true).status(of: try #require(box.scanner.scan().first), busy: nil)
            .withheld == .channelUnreadable)
        let quarantined = GhcupInstall(path: box.ghcup.path, version: "0.2.6.1", quarantined: true)
        #expect(await box.check().status(of: quarantined, busy: nil).withheld == .unverified)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        #expect(try await box.status().withheld == .unsupportedInstaller)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)
        try Data("#!/bin/sh\n".utf8).write(to: box.ghcup)
        #expect(try await box.status().withheld == .versionUnreadable)
    }

    // MARK: - The update

    /// The click runs `ghcup upgrade` with only `~/.ghcup/bin`, `curl` and
    /// `sw_vers` reachable, ghcup's own directory variables gone and its startup
    /// check skipped, and checks what it left. Mutation: keep the inherited
    /// `GHCUP_*` / `XDG_*` variables.
    @Test func upgradesAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(version: "0.2.6.1", upgrade: try box.upgradeBody(to: "0.2.6.2"))
        let outcome = await box.updater().update(try await box.status())
        #expect(outcome == .updated(version: "0.2.6.2"))
        #expect(box.read("ARGS") == "upgrade\n")
        let env = box.read("ENV") ?? ""
        #expect(!env.contains("GHCUP_INSTALL_BASE_PREFIX="))
        #expect(!env.contains("GHCUP_USE_XDG_DIRS="))
        #expect(!env.contains("XDG_BIN_HOME="))
        #expect(env.contains("GHCUP_SKIP_UPDATE_CHECK=1\n"))
        #expect(env.contains("KEEP=1"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        #expect(env.contains("PATH=\(box.bin.path):"))
        #expect(box.read("PATHLS") == "ghcup\ncurl\nsw_vers\n")
    }

    /// What the upgrade left must be the published build of a newer version.
    /// Mutation: report `.updated` without verifying the new file.
    @Test func anUnpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "0.2.6.1", upgrade: try box.upgradeBody(to: "0.2.6.2", publishNew: false))
        box.publish("0.2.6.2", "the real 0.2.6.2")
        let outcome = await box.updater().update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(message.contains("not the ghcup 0.2.6.2 the GHCup project published"))
    }

    /// "No GHCup update available" exits 0 having changed nothing: not "updated".
    @Test func anUnchangedFileIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "0.2.6.1", upgrade: "echo '[ Warn  ] No GHCup update available'")
        let outcome = await box.updater().update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(message.contains("is still ghcup 0.2.6.1"))
    }

    @Test func gatesAreAskedAgainAtTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "0.2.6.1", upgrade: try box.upgradeBody(to: "0.2.6.2"))
        let status = try await box.status()
        #expect(await box.updater(busy: { .upgrade(7) }).update(status) == .busy("ghcup upgrade is running (pid 7)"))
        guard case .failed(let moved, _) = await box.updater(latest: "0.2.6.1").update(status) else {
            Issue.record("ran on metadata that moved back"); return
        }
        #expect(moved.hasPrefix("not run:"))
        #expect(!box.ran)
    }

    /// ghcup's `[ Error ]` line with the exit status, as the row shows it.
    @Test func failureLineIsGhcupsError() {
        let outcome = ChildProcess.Outcome(
            terminationStatus: 11, uncaughtSignal: false, timedOut: false, standardOutput: Data(), standardError: Data())
        let lines = ["[ Info  ] Upgrading GHCup...", "[ Error ] Download failed: curl exited 22"]
        #expect(GhcupUpdater.failureMessage(lines, outcome, deadline: GhcupUpdater.defaultDeadline)
            == "Download failed: curl exited 22 (exit 11)")
    }

    // MARK: - Busy

    @Test func busyIsGhcupReplacingItself() {
        #expect(GhcupActivity.isUpgrade(["/Users/ann/.ghcup/bin/ghcup", "upgrade"]))
        #expect(!GhcupActivity.isUpgrade(["ghcup", "install", "ghc"]))
        let curl = ClaudeCodeActivity.Process(pid: 9, arguments: [
            "curl", "-Lf", "https://downloads.haskell.org/~ghcup/0.2.6.2/aarch64-apple-darwin-ghcup-0.2.6.2",
        ])
        #expect(GhcupActivity.busy(processes: [curl]) == .download(9))
        let toolchain = ClaudeCodeActivity.Process(pid: 8, arguments: [
            "curl", "https://downloads.haskell.org/~ghcup/unofficial-bindists/cabal/3.18.1.0/cabal.tar.xz",
        ])
        #expect(GhcupActivity.busy(processes: [toolchain]) == nil)
    }

    // MARK: - Release notes

    /// `CHANGELOG.md` through the production parser: entries with their dates,
    /// sub-bullets and `###` headings; a pre-ISO date dropped. Excerpt of
    /// master's (fetched 2026-10-09), byte for byte in the lines kept.
    @Test func releaseNotesFromTheChangelog() throws {
        let markdown = """
            # Version history for ghcup

            ## 0.2.6.2 -- 2026-06-16

            * Fix X.Y symlinks wrt [#1365](https://github.com/haskell/ghcup-hs/issues/1365)
              - you may want to run `ghcup fixup symlinks` if you are affected
            * Introduce `ghcup fixup` [#1369](https://github.com/haskell/ghcup-hs/issues/1369)

            ## 0.2.6.0 -- 2026-06-11

            ### Bugfixes affecting VSCode

            * Fix filtering in `ghcup list` wrt [#1354](https://github.com/haskell/ghcup-hs/issues/1354)

            ### Other bugfixes

            * Add missing `--disable-ld-override` to GHC bindist configure runs

            ## 0.1.19.4 -- 2023-7-02

            * Fix something
            """
        let log = try #require(GhcupChangelog.parse(markdown))
        #expect(log.entries.map(\.version) == ["0.2.6.2", "0.2.6.0", "0.1.19.4"])
        #expect(log.entries.map(\.date) == ["2026-06-16", "2026-06-11", nil])
        #expect(log.entries[1].content.contains(.heading("Bugfixes affecting VSCode")))
        #expect(log.entries[1].content.contains(.heading("Other bugfixes")))
        #expect(log.entries[0].items.first?.hasPrefix("Fix X.Y symlinks") == true)
    }
}
