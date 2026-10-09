import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// zoxide: finding it where its installer puts it, reading its version out of
/// the file, its verdict, the archive check the trust rule rests on, its
/// one-click (the vendor's installer) and its release notes.
///
/// "zoxide" here is a small file carrying one of the literals every real build
/// puts before its version (measured 2026-10-09 on 0.8.3 to 0.10.0). The
/// "installer" is a `#!/bin/sh` script that copies a staged file over the
/// install, as the real one's `cp` does. The release API, the downloads and
/// their unpacking are injected: nothing here reads the host's process table,
/// runs a zoxide build or reaches the network.
@Suite struct ZoxideTests {

    static let target = "aarch64-apple-darwin"

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var file: URL { bin.appendingPathComponent("zoxide") }
        let digests: ZoxidePublishedDigests
        private let lock = NSLock()
        /// version → the `zoxide` its release archive holds.
        private var published: [String: Data] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-zoxide-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = ZoxidePublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        /// A build's bytes the way 0.10.0's arm64 build lays them out: dependency
        /// versions around it, the about text right before its own.
        static func build(_ version: String, salt: String = "") -> Data {
            Data("\u{7}clap 4.6.0\0regex0.18.0\0addimportqueryremoveA smarter cd command for your terminal\(version)\0\u{1}\u{2}prompt\(salt)".utf8)
        }

        @discardableResult
        func install(_ version: String, at url: URL? = nil, publish: Bool = true, salt: String = "") throws -> URL {
            let url = url ?? file
            let bytes = Self.build(version, salt: salt)
            try bytes.write(to: url)
            if publish { self.publish(version, bytes) }
            return url
        }

        func publish(_ version: String, _ bytes: Data) { lock.withLock { published[version] = bytes } }
        var downloadCount: Int { lock.withLock { downloads } }

        var scanner: ZoxideScanner {
            ZoxideScanner(home: home, isQuarantined: { _ in false }, readTarget: { _ in ZoxideTests.target })
        }

        static func archive(_ version: String) -> Data { Data("tgz-\(version)".utf8) }
        static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

        /// The release as the API answers it: a digest for the arm64 archive of
        /// every published version, unless `digest` is false.
        func releaseJSON(_ version: String, digest: Bool = true) -> Data {
            let name = "zoxide-\(version)-aarch64-apple-darwin.tar.gz"
            let asset: String = digest
                ? #"{"name": "\#(name)", "digest": "sha256:\#(Self.hex(Self.archive(version)))"}"#
                : #"{"name": "\#(name)", "digest": null}"#
            return Data(#"{"tag_name": "v\#(version)", "assets": [\#(asset)]}"#.utf8)
        }

        func release(latest: String = "0.10.0", digest: Bool = true, status: Int = 200) -> ZoxideRelease {
            ZoxideRelease(fetch: { url, _ in
                if status != 200 { return (Data(), status, "0") }
                if url == ZoxideRelease.latestURL { return (self.releaseJSON(latest, digest: digest), 200, nil) }
                let version = String(url.lastPathComponent.dropFirst())
                guard self.lock.withLock({ self.published[version] }) != nil else { return (Data(), 404, nil) }
                return (self.releaseJSON(version), 200, nil)
            })
        }

        /// The release assets; `tamper` serves an archive its digest does not name.
        func verifier(tamper: Bool = false) -> ZoxideVerifier {
            let release = release()
            return ZoxideVerifier(
                release: { try await release.release(version: $0) },
                download: { url in
                    let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                    self.lock.withLock { self.downloads += 1 }
                    return tamper ? Data("other".utf8) : Self.archive(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
                        .replacingOccurrences(of: "tgz-", with: "")
                    let bytes = self.lock.withLock { self.published[version] } ?? Data()
                    try bytes.write(to: directory.appendingPathComponent("zoxide"))
                },
                digests: digests)
        }

        func check(latest: String = "0.10.0", digest: Bool = true, status: Int = 200) -> ZoxideCheck {
            let release = release(latest: latest, digest: digest, status: status)
            return ZoxideCheck(latest: { try await release.latest() })
        }

        func status(latest: String = "0.10.0", digest: Bool = true, busy: ZoxideActivity.Busy? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(latest: latest, digest: digest).status(of: install, busy: busy)
        }

        /// The installer stand-in: records its arguments, environment and `PATH`,
        /// then `cp`s the staged build over `--bin-dir/zoxide`, as the real one does.
        func installer(installs version: String?, publishNew: Bool = true, body: String? = nil) throws -> Data {
            var copy = "echo nothing"
            if let version {
                let bytes = Self.build(version, salt: publishNew ? "" : "local")
                if publishNew { publish(version, bytes) }
                let staged = root.appendingPathComponent("staged-\(version)")
                try bytes.write(to: staged)
                copy = #"/bin/cp "\#(staged.path)" "$2/zoxide""#
            }
            return Data("""
                #!/bin/sh
                # The official zoxide installer.
                #   --bin-dir) _ZOXIDE_BIN_DIR="$2" && shift 2 ;;
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$PATH" > "\(root.path)/PATHLS"
                \(body ?? copy)
                """.utf8)
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        func updater(script: Data, latest: String = "0.10.0", busy: @escaping ZoxideUpdater.BusyCheck = { nil }) -> ZoxideUpdater {
            ZoxideUpdater(
                busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(),
                fetchScript: { url in
                    #expect(url == ZoxideUpdater.installer)
                    return script
                },
                environment: { ["_ZOXIDE_ARCH": "x86_64-apple-darwin", "KEEP": "1"] })
        }
    }

    // MARK: - Finding it

    /// Each shape the real builds put the version in, measured 2026-10-09: the
    /// version after the anchor, with or without NUL padding or a `v`, and
    /// never a dependency's version elsewhere in the file. Mutations: drop an
    /// anchor; skip the NULs; accept disagreeing versions; let a longer version
    /// with a fourth part (`0.10.0.1`) read as its first three.
    @Test func readsTheCompiledVersionAfterEachAnchor() {
        func read(_ text: String) -> String? {
            let data = Data(text.utf8)
            var windows: [Data] = []
            for anchor in ZoxideScanner.anchors {
                var start = data.startIndex
                while let range = data.range(of: anchor, in: start..<data.endIndex) {
                    windows.append(Data(data[range.upperBound..<min(data.endIndex, range.upperBound + 32)]))
                    start = range.upperBound
                }
            }
            return ZoxideScanner.compiledVersion(after: windows)
        }
        // 0.10.0 / 0.9.9 arm64.
        #expect(read("clap4.6.0addimportqueryremoveA smarter cd command for your terminal0.10.0\0\u{1}") == "0.10.0")
        #expect(read("A smarter cd command for your terminal0.9.9A subcommand is required") == "0.9.9")
        // 0.9.9 / 0.10.0 x86_64.
        #expect(read("addimportqueryremove\0\0\0\0\0\u{0}0.10.0\0\u{1}\u{2}none") == "0.10.0")
        // 0.9.8.
        #expect(read("A smarter cd command for your terminalAjeet D'Souza <98ajeet@gmail.com>0.9.8pathsscore") == "0.9.8")
        // 0.9.4 to 0.9.7, and 0.8.3 / 0.9.0 with their `v`.
        #expect(read("{tab}Resolve symlinks when storing paths0.9.7pathsAddPATHS") == "0.9.7")
        #expect(read("_ZO_RESOLVE_SYMLINKS  Resolve symlinks when storing pathsv0.9.0pathsAdd") == "0.9.0")
        // No anchor: dependency versions are never read.
        #expect(read("clap 4.6.0\0regex 0.18.0\0zoxide") == nil)
        #expect(read("A smarter cd command for your terminal0.10.0 Resolve symlinks when storing paths0.9.9") == nil)
        #expect(read("A smarter cd command for your terminal0.10.0.1") == nil)
        #expect(read("A smarter cd command for your terminal{before-help}") == nil)
    }

    /// The file is read, never run: a fixture's bytes give its version.
    @Test func findsTheInstallerLocation() throws {
        let box = try Sandbox()
        let file = try box.install("0.9.9")
        #expect(box.scanner.scan() == [ZoxideInstall(path: file.path, binary: file.path, version: "0.9.9")])
    }

    /// Homebrew's, cargo's and an app's copy belong to them; a link to anywhere
    /// else is an install the click would write through; a dangling link is
    /// broken. Mutations: drop the Cellar, cargo or `.app` test.
    @Test func ownersOtherThanTheInstallerAreSkipped() throws {
        let box = try Sandbox()
        for owner in ["ZZFixture-prefix/Cellar/zoxide/0.10.0/bin", "home/.cargo/bin", "ZZFixture.app/Contents/MacOS"] {
            let dir = box.root.appendingPathComponent(owner)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let owned = try box.install("0.10.0", at: dir.appendingPathComponent("zoxide"))
            try? FileManager.default.removeItem(at: box.file)
            try FileManager.default.createSymbolicLink(atPath: box.file.path, withDestinationPath: owned.path)
            #expect(box.scanner.scan().isEmpty, "\(owner)")
        }

        try FileManager.default.removeItem(at: box.file)
        let elsewhere = box.root.appendingPathComponent("ZZFixture-dotfiles")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let loose = try box.install("0.9.9", at: elsewhere.appendingPathComponent("zoxide"))
        try FileManager.default.createSymbolicLink(atPath: box.file.path, withDestinationPath: loose.path)
        let linked = try #require(box.scanner.scan().first)
        #expect(linked.linked)
        #expect(linked.version == "0.9.9")

        try FileManager.default.removeItem(at: loose)
        #expect(box.scanner.scan().first?.problem == .executableMissing)
    }

    @Test func nothingInstalledIsNothing() throws {
        #expect(try Sandbox().scanner.scan().isEmpty)
    }

    @Test func aFileWithoutTheVersionIsUnreadable() async throws {
        let box = try Sandbox()
        try Data("#!/bin/sh\necho not zoxide\n".utf8).write(to: box.file)
        let status = try await box.status()
        #expect(status.withheld == .versionUnreadable)
        #expect(status.oneClick == nil)
    }

    // MARK: - The verdict

    /// An update is the vendor's installer pointed at the install's directory;
    /// nothing is downloaded and nothing is run to decide it.
    @Test func offersTheInstaller() async throws {
        let box = try Sandbox()
        try box.install("0.9.9")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "0.9.9")
        #expect(status.latestVersion == "0.10.0")
        #expect(status.oneClick?.display
            == "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir \(box.bin.path)")
        #expect(status.manualCommand == nil)
        #expect(box.downloadCount == 0)
    }

    @Test func comparesVersions() async throws {
        let box = try Sandbox()
        try box.install("0.10.0")
        #expect(try await box.status().state == .upToDate)
        try box.install("0.11.0")
        let ahead = try await box.status()
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    /// Each gate withholds the click; those where the user can still update by
    /// hand hand out the command. Mutations: drop any one gate, or its command.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install("0.9.9")
        let command = try #require(try await box.status().oneClick)

        #expect(try await box.status(busy: .installer(42)).withheld == .busy)

        // No digest on the latest release: what the installer leaves could not be checked.
        let undigested = try await box.status(digest: false)
        #expect(undigested.withheld == .unverified)
        #expect(undigested.oneClick == nil)
        #expect(undigested.manualCommand == command)

        // Rate-limited: no verdict, said as GitHub's limit.
        let limited = await box.check(status: 403).status(of: try #require(box.scanner.scan().first), busy: nil)
        #expect(limited.withheld == .rateLimited)
        #expect(limited.state == .unknown)
        let down = await box.check(status: 503).status(of: try #require(box.scanner.scan().first), busy: nil)
        #expect(down.withheld == .channelUnreadable)

        // A directory only sudo could write to.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = try await box.status()
        #expect(readOnly.withheld == .unsupportedInstaller)
        #expect(readOnly.oneClick == nil)
        #expect(readOnly.manualCommand == command)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        // A link the installer's cp would write through.
        let linked = ZoxideInstall(path: box.file.path, binary: "/ZZFixture/elsewhere/zoxide", version: "0.9.9", linked: true)
        let status = await box.check().status(of: linked, busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand == command)
    }

    // MARK: - The release

    /// The digest of each macOS archive, by target, and nothing from another
    /// asset. Mutations: take another asset's digest; accept a tag without `v`.
    @Test func parsesTheReleaseDigests() throws {
        let hex = String(repeating: "ab", count: 32)
        let json = """
            {"tag_name": "v0.10.0", "assets": [
              {"name": "zoxide-0.10.0-aarch64-apple-darwin.tar.gz", "digest": "sha256:\(hex)"},
              {"name": "zoxide-0.10.0-x86_64-apple-darwin.tar.gz", "digest": null},
              {"name": "zoxide-0.10.0-aarch64-unknown-linux-musl.tar.gz", "digest": "sha256:\(String(repeating: "cd", count: 32))"}
            ]}
            """
        let published = try #require(ZoxideRelease.parseRelease(Data(json.utf8)))
        #expect(published == ZoxideRelease.Published(version: "0.10.0", archiveDigests: ["aarch64-apple-darwin": hex]))
        #expect(ZoxideRelease.parseRelease(Data(#"{"tag_name": "0.10.0", "assets": []}"#.utf8)) == nil)
    }

    // MARK: - The archive check

    /// The archive must match its release's `digest`; its `zoxide` is compared
    /// with the file, and remembered so the archive is downloaded once per
    /// version. Mutations: skip the archive's digest; compare nothing; never
    /// remember.
    @Test func verifiesAgainstTheReleaseArchive() async throws {
        let box = try Sandbox()
        let file = try box.install("0.9.9").path
        #expect(await box.verifier().verify(binary: file, version: "0.9.9", target: Self.target) == .matches)
        #expect(await box.verifier().verify(binary: file, version: "0.9.9", target: Self.target) == .matches)
        #expect(box.downloadCount == 1)
        #expect(box.digests.digest(version: "0.9.9", target: Self.target) == CLIToolTrust.sha256(of: URL(fileURLWithPath: file)))

        box.publish("0.9.8", Sandbox.build("0.9.8"))
        let tampered = await box.verifier(tamper: true).verify(binary: file, version: "0.9.8", target: Self.target)
        guard case .couldNotVerify = tampered else { Issue.record("expected couldNotVerify, got \(tampered)"); return }
        #expect(box.digests.digest(version: "0.9.8", target: Self.target) == nil)

        // Not the published build of its version.
        try box.install("0.9.8", publish: false, salt: "local")
        let differs = await box.verifier().verify(binary: file, version: "0.9.8", target: Self.target)
        guard case .differs = differs else { Issue.record("expected differs, got \(differs)"); return }
    }

    // MARK: - The update

    /// The installer runs as `/bin/sh <file> --bin-dir <dir>`, with `HOME` the
    /// scan's, a `PATH` of the script's tools only (no `sudo`), `_ZOXIDE_ARCH`
    /// gone; then the file it left is checked against its release. Mutations:
    /// keep `_ZOXIDE_ARCH`; put `sudo` on the `PATH`; skip the check after.
    @Test func updatesThroughTheInstallerAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install("0.9.9")
        let status = try await box.status()
        let outcome = await box.updater(script: try box.installer(installs: "0.10.0")).update(status)
        #expect(outcome == .updated(version: "0.10.0"))
        #expect(box.read("ARGS")?.trimmingCharacters(in: .whitespacesAndNewlines) == "--bin-dir \(box.bin.path)")
        let env = try #require(box.read("ENV"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        #expect(env.contains("KEEP=1"))
        #expect(!env.contains("_ZOXIDE_ARCH"))
        let tools = Set(try #require(box.read("PATHLS")).split(separator: "\n").map(String.init))
        #expect(tools == Set(ZoxideUpdater.defaultTools.keys))
        #expect(!tools.contains("sudo"))
        #expect(box.scanner.scan().first?.version == "0.10.0")
    }

    /// What the installer leaves must be its version's published build, and
    /// newer. Mutations: drop either check after the run.
    @Test func whatTheInstallerLeftMustPassTheTrustRule() async throws {
        let box = try Sandbox()
        try box.install("0.9.9")
        let status = try await box.status()

        box.publish("0.10.0", Sandbox.build("0.10.0"))
        let unpublished = await box.updater(script: try box.installer(installs: "0.10.0", publishNew: false)).update(status)
        guard case .failed(let message, _) = unpublished else { Issue.record("expected failed, got \(unpublished)"); return }
        #expect(message.contains("is not the zoxide 0.10.0 ajeetdsouza published"))

        try box.install("0.9.9")
        let unchanged = await box.updater(script: try box.installer(installs: nil)).update(status)
        guard case .failed(let still, _) = unchanged else { Issue.record("expected failed, got \(unchanged)"); return }
        #expect(still.contains("is still zoxide 0.9.9"))
    }

    /// The installer's own `Error: …` line and its exit status are the row's
    /// reason; the whole output is the detail pane's.
    @Test func aFailingInstallerSaysWhy() async throws {
        let box = try Sandbox()
        try box.install("0.9.9")
        let status = try await box.status()
        let script = try box.installer(installs: nil, body: """
            echo "Error: you have exceeded GitHub's API rate limit." >&2
            exit 1
            """)
        let outcome = await box.updater(script: script).update(status)
        guard case .failed(let message, let output) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(message == "you have exceeded GitHub's API rate limit. (install.sh exited with status 1)")
        #expect(output.contains("Error: you have exceeded GitHub's API rate limit."))
    }

    /// Asked again at the click: a run under way, the file changed, a directory
    /// gone read-only, a release no longer newer, a script that is not the
    /// installer. Nothing is run in any of them. Mutations: drop any one.
    @Test func theClickAsksTheGatesAgain() async throws {
        let box = try Sandbox()
        try box.install("0.9.9")
        let status = try await box.status()
        let script = try box.installer(installs: "0.10.0")

        #expect(await box.updater(script: script, busy: { .installer(7) }).update(status) == .busy("zoxide's installer is running (pid 7)"))
        let notNewer = await box.updater(script: script, latest: "0.9.9").update(status)
        guard case .failed = notNewer else { Issue.record("expected failed, got \(notNewer)"); return }
        let notInstaller = await box.updater(script: Data("<html>rate limited</html>".utf8)).update(status)
        guard case .failed = notInstaller else { Issue.record("expected failed, got \(notInstaller)"); return }

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = await box.updater(script: script).update(status)
        guard case .failed(let why, _) = readOnly else { Issue.record("expected failed, got \(readOnly)"); return }
        #expect(why.contains("sudo"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        try box.install("0.9.8")
        let moved = await box.updater(script: script).update(status)
        guard case .failed = moved else { Issue.record("expected failed, got \(moved)"); return }
        #expect(!box.ran)
    }

    @Test func aStatusWithoutTheClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.install("0.9.9")
        let status = try await box.status(digest: false)
        #expect(await box.updater(script: try box.installer(installs: "0.10.0")).update(status) == .notOffered)
        #expect(!box.ran)
    }

    // MARK: - Activity

    /// Mutation: match any `sh`, or any curl.
    @Test func busyIsTheInstallerOrItsDownload() {
        typealias P = ClaudeCodeActivity.Process
        #expect(ZoxideActivity.busy(processes: [P(pid: 3, arguments: ["/bin/sh", "/var/folders/x/duo-zoxide-1/zoxide-install-AB.sh", "--bin-dir", "/Users/ann/.local/bin"])])
            == .installer(3))
        #expect(ZoxideActivity.busy(processes: [P(pid: 4, arguments: ["curl", "-sLo", "zoxide.tar.gz", "https://github.com/ajeetdsouza/zoxide/releases/download/v0.10.0/zoxide-0.10.0-aarch64-apple-darwin.tar.gz"])])
            == .download(4))
        #expect(ZoxideActivity.busy(processes: [P(pid: 5, arguments: ["/bin/sh", "install.sh"]), P(pid: 6, arguments: ["curl", "https://example.com"])]) == nil)
    }

    // MARK: - Release notes

    /// Keep a Changelog bodies, as zoxide's releases carry them: each heading a
    /// section, each `-` line an item, the newest first. Mutation: parse with
    /// another format.
    @Test func releaseNotesKeepTheirSections() throws {
        let json = """
            [{"tag_name": "v0.10.0", "published_at": "2026-07-04T12:41:16Z", "draft": false, "prerelease": false,
              "body": "### Added\\n\\n- `import` now supports fetching entries from `atuin`.\\n\\n### Changed\\n\\n- `import` now takes a subcommand instead of the `--from` flag.\\n\\n### Fixed\\n\\n- Zsh: skip doctor diagnostics in non-interactive shells."},
             {"tag_name": "v0.9.9", "published_at": "2026-01-31T07:48:49Z", "draft": false, "prerelease": false,
              "body": "### Added\\n\\n- Support for Android ARMv7.\\n\\n### Fixed\\n\\n- Bash: avoid overwriting `$PIPESTATUS`."}]
            """
        let changelog = try #require(ZoxideRelease.parseNotes(json))
        #expect(changelog.entries.map(\.version) == ["0.10.0", "0.9.9"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.content.compactMap { if case .heading(let h) = $0 { h } else { nil } } == ["Added", "Changed", "Fixed"])
        #expect(newest.items == [
            "`import` now supports fetching entries from `atuin`.",
            "`import` now takes a subcommand instead of the `--from` flag.",
            "Zsh: skip doctor diagnostics in non-interactive shells.",
        ])
    }
}
