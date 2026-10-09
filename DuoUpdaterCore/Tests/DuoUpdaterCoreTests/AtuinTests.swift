import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Atuin: finding it where its installer puts it, its receipt and config, its
/// verdict, the archive check the trust rule rests on, its one-click update and
/// its release notes.
///
/// "atuin" here is a `#!/bin/sh` script in a temporary home, with the receipt
/// its installer writes. Its `update` does what the real one's installer does
/// to the disk — moves a new file into place and rewrites the receipt. The
/// channels, the release downloads and their unpacking are injected: nothing
/// here reads the host's process table, runs an Atuin build or reaches the
/// network.
@Suite struct AtuinTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".atuin/bin") }
        var atuin: URL { bin.appendingPathComponent("atuin") }
        let digests: AtuinPublishedDigests
        private let lock = NSLock()
        /// version → the `atuin` its release archive holds.
        private var published: [String: String] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-atuin-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = AtuinPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/atuin"),
                                                    withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func script(version: String, update: String = "exit 0") -> String {
            """
            #!/bin/sh
            # atuin \(version)
            if [ "$1" = update ]; then
            \(update)
            fi
            """
        }

        func receipt(version: String, prefix: String? = nil, owner: String = "atuinsh") throws {
            let json = """
                {"binaries":["atuin"],"binary_aliases":{},"cdylibs":[],"cstaticlibs":[],"install_layout":"flat",\
                "install_prefix":"\(prefix ?? bin.path)","modify_path":true,\
                "provider":{"source":"cargo-dist","version":"0.31.0"},\
                "source":{"app_name":"atuin","name":"atuin","owner":"\(owner)","release_type":"github"},\
                "version":"\(version)"}
                """
            try Data(json.utf8).write(to: home.appendingPathComponent(".config/atuin/atuin-receipt.json"))
        }

        func config(_ text: String) throws {
            try Data(text.utf8).write(to: home.appendingPathComponent(".config/atuin/config.toml"))
        }

        /// atuin at `~/.atuin/bin/atuin` with its receipt, published for its
        /// version unless `publish` is false.
        @discardableResult
        func install(version: String, update: String = "exit 0", publish: Bool = true) throws -> URL {
            let text = Self.script(version: version, update: update)
            try Data(text.utf8).write(to: atuin)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: atuin.path)
            try receipt(version: version)
            if publish { self.publish(version, text) }
            return atuin
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        var downloadCount: Int { lock.withLock { downloads } }

        /// What `atuin update` does: the installer moves the new build into place
        /// and rewrites the receipt.
        func updateBody(to version: String, publishNew: Bool = true) throws -> String {
            let next = Self.script(version: version)
            if publishNew { publish(version, next) }
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            let receiptFile = home.appendingPathComponent(".config/atuin/atuin-receipt.json").path
            return """
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/cp "\(staged.path)" "\(bin.path)/atuin.new" || exit 1
                /bin/chmod 755 "\(bin.path)/atuin.new"
                /bin/mv -f "\(bin.path)/atuin.new" "\(bin.path)/atuin"
                /usr/bin/sed -i '' 's/"version":"[^"]*"}$/"version":"\(version)"}/' "\(receiptFile)"
                echo "Updated atuin"
                """
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        var scanner: AtuinScanner {
            AtuinScanner(home: home, isQuarantined: { _ in false }, readTarget: { _ in "aarch64-apple-darwin" })
        }

        static func archive(_ version: String) -> Data { Data("tgz-\(version)".utf8) }

        /// The release assets: `<stem>.tar.gz.sha256` and `<stem>.tar.gz` of every
        /// published version, `tamper` serving an archive its digest does not name.
        func verifier(tamper: Bool = false) -> AtuinVerifier {
            AtuinVerifier(
                download: { url in
                    let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                    guard self.lock.withLock({ self.published[version] }) != nil else {
                        throw AtuinRelease.Failure.http(404)
                    }
                    if url.pathExtension == "sha256" {
                        let hex = SHA256.hash(data: Self.archive(version)).map { String(format: "%02x", $0) }.joined()
                        return Data("\(hex) *atuin-aarch64-apple-darwin.tar.gz\n".utf8)
                    }
                    self.lock.withLock { self.downloads += 1 }
                    return tamper ? Data("other".utf8) : Self.archive(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
                        .replacingOccurrences(of: "tgz-", with: "")
                    let text = self.lock.withLock { self.published[version] } ?? ""
                    let inside = directory.appendingPathComponent("atuin-aarch64-apple-darwin")
                    try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
                    try Data(text.utf8).write(to: inside.appendingPathComponent("atuin"))
                },
                digests: digests)
        }

        /// `stable` and `nightly` answers; `asked` records the channels asked.
        func check(stable: String = "18.23.0", nightly: String = "18.24.0-beta.1", fails: Bool = false) -> AtuinCheck {
            let verifier = verifier()
            return AtuinCheck(
                latest: { channel in
                    if fails { throw AtuinRelease.Failure.http(503) }
                    return channel == "nightly" ? nightly : stable
                },
                knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
        }

        func updater(stable: String = "18.23.0", busy: @escaping AtuinUpdater.BusyCheck = { nil }) -> AtuinUpdater {
            AtuinUpdater(
                busy: busy, scanner: scanner, check: check(stable: stable), verifier: verifier(),
                environment: {
                    ["ATUIN_UPDATE_CHANNEL": "nightly", "ATUIN_CONFIG_DIR": "/elsewhere", "XDG_CONFIG_HOME": "/elsewhere",
                     "AXOUPDATER_CONFIG_PATH": "/elsewhere", "INSTALLER_DOWNLOAD_URL": "https://elsewhere.example",
                     "CARGO_DIST_FORCE_INSTALL_DIR": "/elsewhere", "KEEP": "1"]
                })
        }

        func status(stable: String = "18.23.0", busy: AtuinActivity.Busy? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(stable: stable).status(of: install, busy: busy)
        }
    }

    // MARK: - Finding it

    /// The installer's place, the receipt's version and directory.
    @Test func findsTheInstallerCopy() throws {
        let box = try Sandbox()
        let atuin = try box.install(version: "18.22.0")
        #expect(box.scanner.scan() == [
            AtuinInstall(path: atuin.path, binary: atuin.path, version: "18.22.0", installDirectory: box.bin.path),
        ])
    }

    /// `atuin update` refuses a copy without the official receipt or one the
    /// receipt does not name; neither has a version to show. Mutations: drop the
    /// owner check; drop `isFor`.
    @Test func theReceiptDecidesTheCopy() throws {
        let box = try Sandbox()
        try box.install(version: "18.22.0")
        try box.receipt(version: "18.22.0", owner: "someone")
        #expect(box.scanner.scan().first?.problem == .noReceipt)
        #expect(box.scanner.scan().first?.version == nil)

        try FileManager.default.removeItem(at: box.home.appendingPathComponent(".config/atuin/atuin-receipt.json"))
        #expect(box.scanner.scan().first?.problem == .noReceipt)

        let other = box.root.appendingPathComponent("elsewhere/bin")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try box.receipt(version: "18.22.0", prefix: other.path)
        // The receipt's own copy is missing; the default one is not its.
        let installs = box.scanner.scan()
        #expect(installs.map(\.problem) == [.receiptElsewhere])
    }

    /// A receipt naming another directory is where the installer put atuin: that
    /// copy is found, and the default place, absent, is not reported.
    @Test func findsTheReceiptsDirectory() throws {
        let box = try Sandbox()
        let other = box.root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let file = other.appendingPathComponent("atuin")
        try Data(Sandbox.script(version: "18.22.0").utf8).write(to: file)
        try box.receipt(version: "18.22.0", prefix: other.path)
        #expect(box.scanner.scan().map(\.path) == [file.path])
        #expect(box.scanner.scan().first?.installDirectory == other.path)
    }

    /// Homebrew's copy is the brew group's. Mutation: drop `belongsElsewhere`.
    @Test func aBrewLinkIsNotOurs() throws {
        let box = try Sandbox()
        let cellar = box.root.appendingPathComponent("opt/homebrew/Cellar/atuin/18.23.0/bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        let brewed = cellar.appendingPathComponent("atuin")
        try Data(Sandbox.script(version: "18.23.0").utf8).write(to: brewed)
        try FileManager.default.createSymbolicLink(atPath: box.atuin.path, withDestinationPath: brewed.path)
        #expect(box.scanner.scan().isEmpty)
    }

    /// The two settings, at the top level only. Mutation: read past the first
    /// table header.
    @Test func readsTheConfig() {
        #expect(AtuinSettings.parse("") == AtuinSettings())
        #expect(AtuinSettings.parse("update_channel = \"nightly\" # beta\nupdate_check = false\n")
            == AtuinSettings(channel: "nightly", updateCheck: false))
        #expect(AtuinSettings.parse("[sync]\nupdate_channel = \"nightly\"\nupdate_check = false\n") == AtuinSettings())
        #expect(AtuinSettings.parse("update_channel = 'weekly'").channelIsKnown == false)
    }

    // MARK: - The verdict

    /// An update is `atuin update` on the file itself, with the receipt's
    /// directory first on PATH; nothing is downloaded to decide it.
    @Test func offersAtuinUpdate() async throws {
        let box = try Sandbox()
        let atuin = try box.install(version: "18.22.0")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "18.23.0")
        #expect(status.channel == "stable")
        #expect(status.oneClick == CLIToolCommand(executable: atuin.path, arguments: ["update"], pathPrefix: box.bin.path))
        #expect(box.downloadCount == 0)
    }

    /// `nightly` is compared on prereleases too, in semver order. Mutation:
    /// ignore the channel.
    @Test func followsTheConfigsChannel() async throws {
        let box = try Sandbox()
        try box.install(version: "18.23.0")
        #expect(try await box.status().state == .upToDate)
        try box.config("update_channel = \"nightly\"\n")
        let nightly = try await box.status()
        #expect(nightly.channel == "nightly")
        #expect(nightly.latestVersion == "18.24.0-beta.1")
        #expect(nightly.state == .updateAvailable)
        #expect(AtuinRelease.compare("18.20.0-beta.3", "18.20.0") == .orderedAscending)
    }

    /// `update_check = false` hands over the command instead. Mutation: drop it.
    @Test func updateCheckOffIsReported() async throws {
        let box = try Sandbox()
        try box.install(version: "18.22.0")
        try box.config("update_check = false\n")
        let status = try await box.status()
        #expect(status.withheld == .autoUpdateOff)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand?.arguments == ["update"])
    }

    /// Mutations: drop any one gate.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "18.22.0")
        #expect(try await box.status(busy: .update(42)).withheld == .busy)
        #expect(await box.check(fails: true).status(of: try #require(box.scanner.scan().first), busy: nil)
            .withheld == .channelUnreadable)
        try box.config("update_channel = \"weekly\"\n")
        #expect(try await box.status().withheld == .channelUnreadable)
        try box.config("")

        let path = box.atuin.path
        let quarantined = AtuinInstall(path: path, binary: path, version: "18.22.0", installDirectory: box.bin.path,
                                       quarantined: true)
        #expect(await box.check().status(of: quarantined, busy: nil).withheld == .unverified)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = try await box.status()
        #expect(readOnly.withheld == .unsupportedInstaller)
        #expect(readOnly.oneClick == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        try box.receipt(version: "18.22.0", owner: "someone")
        #expect(try await box.status().withheld == .unsupportedInstaller)
    }

    /// Once the release's digest is known, a copy that is not the published
    /// build is withheld by the check itself. Mutation: ignore the known digest.
    @Test func aKnownDigestThatDiffersIsWithheld() async throws {
        let box = try Sandbox()
        box.publish("18.22.0", Sandbox.script(version: "18.22.0"))
        let atuin = try box.install(version: "18.22.0", update: "echo altered", publish: false)
        let result = await box.verifier().verify(binary: atuin.path, version: "18.22.0", target: "aarch64-apple-darwin")
        guard case .differs = result else { Issue.record("expected differs, got \(result)"); return }
        let status = try await box.status()
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)
    }

    // MARK: - The archive check

    /// The archive must match the digest published beside it; its
    /// `atuin-<target>/atuin` is compared with the file, and that digest is
    /// remembered. Mutations: skip the archive's digest; never remember.
    @Test func verifiesAgainstTheReleaseArchive() async throws {
        let box = try Sandbox()
        let atuin = try box.install(version: "18.22.0").path
        #expect(await box.verifier().verify(binary: atuin, version: "18.22.0", target: "aarch64-apple-darwin") == .matches)
        #expect(await box.verifier().verify(binary: atuin, version: "18.22.0", target: "aarch64-apple-darwin") == .matches)
        #expect(box.downloadCount == 1)

        box.publish("18.21.0", "x")
        let tampered = await box.verifier(tamper: true).verify(binary: atuin, version: "18.21.0", target: "aarch64-apple-darwin")
        guard case .couldNotVerify = tampered else { Issue.record("expected couldNotVerify, got \(tampered)"); return }
        #expect(box.digests.digest(version: "18.21.0", target: "aarch64-apple-darwin") == nil)
        #expect(AtuinRelease.archiveURL(version: "18.23.0", target: "aarch64-apple-darwin").absoluteString
            == "https://github.com/atuinsh/atuin/releases/download/v18.23.0/atuin-aarch64-apple-darwin.tar.gz")
    }

    /// The stable manifest's release, not a prerelease and with the installer;
    /// the feed's highest semver. Mutations: accept a prerelease manifest; take
    /// the feed's first entry.
    @Test func readsTheChannels() async throws {
        let manifest = #"{"announcement_tag":"v18.23.0","announcement_is_prerelease":false,"artifacts":{"atuin-installer.sh":{}}}"#
        #expect(AtuinRelease.stableVersion(inManifest: Data(manifest.utf8)) == "18.23.0")
        let pre = #"{"announcement_tag":"v18.24.0-beta.1","announcement_is_prerelease":true,"artifacts":{"atuin-installer.sh":{}}}"#
        #expect(AtuinRelease.stableVersion(inManifest: Data(pre.utf8)) == nil)
        let feed = """
            <id>tag:github.com,2008:https://github.com/atuinsh/atuin/releases</id>
            <id>tag:github.com,2008:Repository/301244405/v18.20.0-beta.3</id>
            <id>tag:github.com,2008:Repository/301244405/v18.20.1</id>
            <id>tag:github.com,2008:Repository/301244405/v18.21.0-beta.1</id>
            <id>tag:github.com,2008:Repository/301244405/v18.20.0</id>
            """
        #expect(AtuinRelease.newest(inFeed: Data(feed.utf8)) == "18.21.0-beta.1")
        let release = AtuinRelease(fetch: { url in
            url == AtuinRelease.feed ? (Data(feed.utf8), 200) : (Data(manifest.utf8), 200)
        })
        #expect(try await release.latest(channel: "stable") == "18.23.0")
        #expect(try await release.latest(channel: "nightly") == "18.21.0-beta.1")
        await #expect(throws: AtuinRelease.Failure.http(502)) {
            try await AtuinRelease(fetch: { _ in (Data(), 502) }).latest(channel: "stable")
        }
    }

    // MARK: - The update

    /// The click checks the old file against its release, runs `atuin update`
    /// without the variables that would point it elsewhere, and checks what it
    /// left.
    @Test func updatesAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(version: "18.22.0", update: try box.updateBody(to: "18.23.0"))
        let outcome = await box.updater().update(try await box.status())
        #expect(outcome == .updated(version: "18.23.0"))
        #expect(box.read("ARGS") == "update\n")
        let env = box.read("ENV") ?? ""
        for gone in ["ATUIN_UPDATE_CHANNEL=", "ATUIN_CONFIG_DIR=", "XDG_CONFIG_HOME=", "AXOUPDATER_CONFIG_PATH=",
                     "INSTALLER_DOWNLOAD_URL=", "CARGO_DIST_FORCE_INSTALL_DIR="] {
            #expect(!env.contains(gone))
        }
        #expect(env.contains("KEEP=1"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        #expect(env.contains("PATH=\(box.bin.path):/usr/bin:/bin:/usr/sbin:/sbin\n"))
        #expect(box.downloadCount == 2)
        #expect(box.scanner.scan().first?.version == "18.23.0")
    }

    /// What the update left must be the published build of a newer version.
    /// Mutation: report `.updated` without verifying the new file.
    @Test func anUnpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "18.22.0", update: try box.updateBody(to: "18.23.0", publishNew: false))
        box.publish("18.23.0", "the real 18.23.0")
        let outcome = await box.updater().update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(message.contains("is not the atuin 18.23.0 atuinsh published"))
    }

    /// An update that exits 0 having changed nothing is not "updated".
    @Test func anUnchangedFileIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "18.22.0", update: "echo 'atuin v18.22.0 is up to date'")
        let outcome = await box.updater().update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(message.contains("is still atuin 18.22.0"))
    }

    /// Nothing runs when the old file is not the published build, when the
    /// channel moved back, or when an update is already running.
    @Test func gatesAreAskedAgainAtTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "18.22.0", update: try box.updateBody(to: "18.23.0"))
        let status = try await box.status()
        #expect(await box.updater(busy: { .update(7) }).update(status) == .busy("atuin update is running (pid 7)"))
        guard case .failed(let moved, _) = await box.updater(stable: "18.22.0").update(status) else {
            Issue.record("ran on a channel that moved back"); return
        }
        #expect(moved.hasPrefix("not run:"))
        box.publish("18.22.0", "not this file")
        guard case .failed(let message, _) = await box.updater().update(status) else { Issue.record("ran unverified"); return }
        #expect(message.hasPrefix("not run:"))
        #expect(!box.ran)
    }

    @Test func failureLineIsEyresError() {
        let outcome = ChildProcess.Outcome(
            terminationStatus: 1, uncaughtSignal: false, timedOut: false, standardOutput: Data(), standardError: Data())
        let lines = ["Checking for updates on the stable channel...", "Error: ", "   0: Failed to fetch releases",
                     "Error: could not reach GitHub", "", "Caused by:", "   0: error sending request"]
        #expect(AtuinUpdater.failureMessage(lines, outcome, deadline: AtuinUpdater.defaultDeadline)
            == "could not reach GitHub: error sending request (exit 1)")
    }

    // MARK: - Busy

    /// `update` as the word atuin dispatches on, without `--check`.
    @Test func busyIsAtuinReplacingItself() {
        #expect(AtuinActivity.isUpdate(["/Users/ann/.atuin/bin/atuin", "update"]))
        #expect(!AtuinActivity.isUpdate(["atuin", "update", "--check"]))
        #expect(!AtuinActivity.isUpdate(["atuin", "search", "update"]))
        let curl = ClaudeCodeActivity.Process(pid: 9, arguments: [
            "curl", "-sSfL", "https://github.com/atuinsh/atuin/releases/download/v18.23.0/atuin-aarch64-apple-darwin.tar.gz",
            "-o", "/tmp/x/input.tar.gz",
        ])
        #expect(AtuinActivity.busy(processes: [curl]) == .download(9))
        #expect(AtuinActivity.busy(processes: [.init(pid: 3, arguments: ["atuin", "update"])]) == .update(3))
    }

    // MARK: - Release notes

    /// `CHANGELOG.md` through the production parser: one entry per version
    /// section, the git-cliff categories kept as headings. The text is an
    /// excerpt of main's (fetched 2026-10-09), byte for byte in the lines kept.
    @Test func releaseNotesKeepTheCategories() throws {
        let markdown = """
            # Changelog

            All notable changes to this project will be documented in this file.

            ## 18.23.0

            ### Bug Fixes

            - *(common)* Sleep before each backoff attempt ([#4129](https://github.com/atuinsh/atuin/issues/4129))


            ### Features

            - Add easy config shortcuts ([#4213](https://github.com/atuinsh/atuin/issues/4213))

            ## 18.22.0

            ### Bug Fixes

            - Fix transaction lock ([#4152](https://github.com/atuinsh/atuin/issues/4152))
            """
        let log = try #require(AtuinChangelog.parse(markdown))
        #expect(log.entries.map(\.version) == ["18.23.0", "18.22.0"])
        let entry = try #require(log.entries.first)
        #expect(entry.content.contains(.heading("Bug Fixes")))
        #expect(entry.content.contains(.heading("Features")))
        #expect(entry.items.count == 2)
        #expect(!entry.items.contains { $0.contains("All notable changes") })
    }

    /// The changelog has no dates; each entry takes the UTC day of its
    /// release's `<updated>` in `releases.atom`, by id `…/v<version>`. A bare
    /// tag (no `v`) dates nothing, and a version the ten entries do not reach
    /// keeps none. The feed is the shape of the real one (2026-10-09), cut to
    /// the elements read around them. Mutations: no `dated` (entries stay
    /// undated); the date from the wrong capture group; the `v` made optional.
    @Test func releaseNotesTakeTheirDatesFromTheReleases() throws {
        let markdown = """
            # Changelog

            ## 18.23.0

            - Add easy config shortcuts ([#4213](https://github.com/atuinsh/atuin/issues/4213))

            ## 18.22.0

            - Fix transaction lock ([#4152](https://github.com/atuinsh/atuin/issues/4152))

            ## 18.0.0

            - An old one
            """
        let feed = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" xml:lang="en-US">
              <id>tag:github.com,2008:https://github.com/atuinsh/atuin/releases</id>
              <updated>2026-09-21T23:48:32Z</updated>
              <entry>
                <id>tag:github.com,2008:Repository/301244405/v18.23.0</id>
                <updated>2026-09-22T02:17:22Z</updated>
                <link rel="alternate" type="text/html" href="https://github.com/atuinsh/atuin/releases/tag/v18.23.0"/>
                <title>v18.23.0</title>
              </entry>
              <entry>
                <id>tag:github.com,2008:Repository/301244405/v18.22.0</id>
                <updated>2026-09-09T22:23:18Z</updated>
                <title>v18.22.0</title>
              </entry>
              <entry>
                <id>tag:github.com,2008:Repository/301244405/18.0.0</id>
                <updated>2024-01-01T00:00:00Z</updated>
                <title>18.0.0</title>
              </entry>
            </feed>
            """.utf8)
        let log = AtuinChangelog.dated(try #require(AtuinChangelog.parse(markdown)), feed: feed)
        #expect(log.entries.map(\.version) == ["18.23.0", "18.22.0", "18.0.0"])
        #expect(log.entries.map(\.date) == ["2026-09-22", "2026-09-09", nil])
        #expect(log.itemSyntax == .markdown)
        #expect(log.entries[0].items == ["Add easy config shortcuts ([#4213](https://github.com/atuinsh/atuin/issues/4213))"])

        // An answer that is not the feed (an error page) dates nothing and keeps the notes.
        let undated = AtuinChangelog.dated(try #require(AtuinChangelog.parse(markdown)),
                                           feed: Data("<html>Too many requests</html>".utf8))
        #expect(undated.entries.map(\.date) == [nil, nil, nil])
        #expect(undated.entries.count == 3)
    }
}
