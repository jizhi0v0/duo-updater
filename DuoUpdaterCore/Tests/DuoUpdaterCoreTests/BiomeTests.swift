import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Biome: finding it where its installer puts it, naming its version by its
/// sha256 among the published builds, its verdict, its one-click (the vendor's
/// installer, pinned to the version checked) and its release notes.
///
/// "Biome" here is a small file; the Mach-O check is injected. The release
/// endpoints (`latest.txt`, the GitHub API's tag and list) are injected too, and
/// serve the sha256 of each fixture build as its asset's `digest`. The
/// "installer" is a bash script that copies a staged file to
/// `$BIOME_INSTALL_DIR/biome`, as the real one's `mv` does. Nothing here reads
/// the host's process table, runs a Biome build or reaches the network.
@Suite struct BiomeTests {

    static let target = "darwin-arm64"

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var file: URL { bin.appendingPathComponent("biome") }
        let digests: BiomePublishedDigests
        private let lock = NSLock()
        /// version → its published `biome-darwin-arm64`.
        private var published: [String: Data] = [:]
        private var calls: [URL] = []
        private var hashes = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-biome-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = BiomePublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func build(_ version: String, salt: String = "") -> Data { Data("biome-build-\(version)\(salt)".utf8) }
        static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

        @discardableResult
        func install(_ version: String, at url: URL? = nil, publish: Bool = true, salt: String = "") throws -> URL {
            let url = url ?? file
            let bytes = Self.build(version, salt: salt)
            try? FileManager.default.removeItem(at: url)
            try bytes.write(to: url)
            if publish { self.publish(version, bytes) }
            return url
        }

        func publish(_ version: String, _ bytes: Data) { lock.withLock { published[version] = bytes } }
        func apiCalls(_ url: URL) -> Int { lock.withLock { calls.filter { $0 == url }.count } }
        var hashCount: Int { lock.withLock { hashes } }

        var scanner: BiomeScanner {
            BiomeScanner(home: home, digests: digests, readTarget: { _ in BiomeTests.target }, hash: { url in
                self.lock.withLock { self.hashes += 1 }
                return CLIToolTrust.sha256(of: url)
            })
        }

        /// One release as the API answers it: a digest for the arm64 binary
        /// unless `digest` is false, and one for a Linux build that must not be read.
        func releaseObject(_ version: String, digest: Bool = true) -> String {
            let bytes = lock.withLock { published[version] } ?? Data()
            let arm = digest ? "\"sha256:\(Self.hex(bytes))\"" : "null"
            return """
                {"tag_name": "@biomejs/biome@\(version)", "prerelease": false, "draft": false,
                 "published_at": "2026-10-21T11:05:24Z", "body": "## \(version)\\n\\n### Patch Changes\\n\\n- Fixed it.",
                 "assets": [{"name": "biome-darwin-arm64", "digest": \(arm)},
                            {"name": "biome-linux-arm64", "digest": "sha256:\(String(repeating: "cd", count: 32))"}]}
                """
        }

        /// The list: every published version, newest first, behind another
        /// package's release and a CLI prerelease.
        func listJSON() -> String {
            let versions = lock.withLock { Array(published.keys) }
                .sorted { VersionComparator.compare($0, $1) == .orderedDescending }
            let others = [
                #"{"tag_name": "@biomejs/js-api@6.1.0", "prerelease": false, "draft": false, "assets": [{"name": "biome-darwin-arm64", "digest": "sha256:\#(String(repeating: "ef", count: 32))"}]}"#,
                #"{"tag_name": "@biomejs/biome@9.0.0-beta.1", "prerelease": true, "draft": false, "assets": [{"name": "biome-darwin-arm64", "digest": "sha256:\#(String(repeating: "aa", count: 32))"}]}"#,
            ]
            return "[" + (others + versions.map { releaseObject($0) }).joined(separator: ",") + "]"
        }

        func release(latest: String = "2.6.2", digest: Bool = true, latestStatus: Int = 200, apiStatus: Int = 200) -> BiomeRelease {
            BiomeRelease(digests: digests, fetch: { url, _ in
                if url == BiomeRelease.latestURL {
                    return (Data("\(latest)\n".utf8), latestStatus, nil)
                }
                self.lock.withLock { self.calls.append(url) }
                if apiStatus != 200 { return (Data(), apiStatus, "0") }
                if url == BiomeRelease.publishedURL { return (Data(self.listJSON().utf8), 200, nil) }
                for version in self.lock.withLock({ Array(self.published.keys) }) where url == BiomeRelease.tagURL(version: version) {
                    return (Data(self.releaseObject(version, digest: digest).utf8), 200, nil)
                }
                return (Data(#"{"message": "Not Found"}"#.utf8), 404, nil)
            })
        }

        func check(latest: String = "2.6.2", digest: Bool = true, latestStatus: Int = 200, apiStatus: Int = 200) -> BiomeCheck {
            BiomeCheck(release: release(latest: latest, digest: digest, latestStatus: latestStatus, apiStatus: apiStatus))
        }

        func status(latest: String = "2.6.2", digest: Bool = true, busy: BiomeActivity.Busy? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(latest: latest, digest: digest).status(of: install, busy: busy)
        }

        /// The installer stand-in: records its arguments, environment and `PATH`,
        /// then copies the staged build to `$BIOME_INSTALL_DIR/biome`.
        func installer(installs version: String?, publishNew: Bool = true, body: String? = nil) throws -> Data {
            var copy = "echo nothing"
            if let version {
                let bytes = Self.build(version, salt: publishNew ? "" : "local")
                if publishNew { publish(version, bytes) }
                let staged = root.appendingPathComponent("staged-\(version)")
                try bytes.write(to: staged)
                copy = #"/bin/cp "\#(staged.path)" "$BIOME_INSTALL_DIR/biome""#
            }
            return Data("""
                #!/usr/bin/env bash
                readonly APP="biome"
                # ${BIOME_INSTALL_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}
                #   -v | --version)
                #   --no-modify-path)
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$PATH" > "\(root.path)/PATHLS"
                \(body ?? copy)
                """.utf8)
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        func updater(script: Data, latest: String = "2.6.2", busy: @escaping BiomeUpdater.BusyCheck = { nil }) -> BiomeUpdater {
            BiomeUpdater(
                busy: busy, scanner: scanner, check: check(latest: latest),
                fetchScript: { url in
                    #expect(url == BiomeUpdater.installer)
                    return script
                },
                environment: { ["BIOME_VERSION": "1.0.0", "XDG_BIN_HOME": "/ZZFixture/elsewhere", "GITHUB_PATH": "/ZZFixture/gh", "KEEP": "1"] })
        }
    }

    // MARK: - Finding it

    /// The file is hashed, never run: a published build's sha256 names its
    /// version — at once once the store knows it, after one read of the
    /// releases' list when it does not. Mutations: skip `learnPublished`; read
    /// the version from anything but the digest.
    @Test func namesTheVersionByItsPublishedDigest() async throws {
        let box = try Sandbox()
        let file = try box.install("2.5.15")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        let unknown = try #require(box.scanner.scan().first)
        #expect(unknown.problem == .unrecognized)
        #expect(unknown.version == nil)
        #expect(unknown.sha256 == Sandbox.hex(Sandbox.build("2.5.15")))

        let status = await box.check().status(of: unknown, busy: nil)
        #expect(status.installedVersion == "2.5.15")
        #expect(status.state == .updateAvailable)
        #expect(box.apiCalls(BiomeRelease.publishedURL) == 1)
        #expect(box.scanner.scan() == [BiomeInstall(
            path: file.path, binary: file.path, version: "2.5.15", target: Self.target,
            sha256: Sandbox.hex(Sandbox.build("2.5.15")))])
    }

    /// A file that is no published build is reported, never offered, and the
    /// list is read once per `latest`, not on every check. Mutations: drop the
    /// `listedThrough` guard; offer the command.
    @Test func anUnpublishedFileIsNeitherRunNorReplaced() async throws {
        let box = try Sandbox()
        try box.install("2.5.15", publish: false, salt: "local")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        for _ in 0..<2 {
            let status = try await box.status()
            #expect(status.state == .unknown)
            #expect(status.withheld == .unverified)
            #expect(status.oneClick == nil)
            #expect(status.manualCommand == nil)
            #expect(CLIToolWording.reason(.unverified, of: status) == "Not the build its developer published")
        }
        #expect(box.apiCalls(BiomeRelease.publishedURL) == 1)
        // A new Biome release is worth one more look.
        _ = await box.check(latest: "2.6.3").status(of: try #require(box.scanner.scan().first), busy: nil)
        #expect(box.apiCalls(BiomeRelease.publishedURL) == 2)
    }

    /// The ~74 MB file is hashed again only once it changed. Mutation: never
    /// use the remembered hash, or keep it past a change.
    @Test func hashesAFileOncePerChange() throws {
        let box = try Sandbox()
        try box.install("2.5.15")
        _ = box.scanner.scan()
        _ = box.scanner.scan()
        #expect(box.hashCount == 1)
        try box.install("2.6.2")
        #expect(box.scanner.scan().first?.sha256 == Sandbox.hex(Sandbox.build("2.6.2")))
        #expect(box.hashCount == 2)
    }

    /// npm's, Homebrew's, cargo's, mise's and an app's copy belong to them, and
    /// a file that is not a macOS executable is some other tool's shim; a link to
    /// anywhere else is an install the click would replace; a dangling link is
    /// broken. Mutations: drop the `node_modules`, Cellar, cargo, mise or `.app`
    /// test, or the Mach-O one.
    @Test func ownersOtherThanTheInstallerAreSkipped() throws {
        let box = try Sandbox()
        for owner in ["home/.local/lib/node_modules/@biomejs/cli-darwin-arm64", "ZZFixture-prefix/Cellar/biome/2.6.2/bin",
                      "home/.cargo/bin", "home/.local/share/mise/installs/biome/2.6.2", "ZZFixture.app/Contents/MacOS"] {
            let dir = box.root.appendingPathComponent(owner)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let owned = try box.install("2.6.2", at: dir.appendingPathComponent("biome"))
            try? FileManager.default.removeItem(at: box.file)
            try FileManager.default.createSymbolicLink(atPath: box.file.path, withDestinationPath: owned.path)
            #expect(box.scanner.scan().isEmpty, "\(owner)")
        }

        try FileManager.default.removeItem(at: box.file)
        try Data("#!/bin/sh\nexec pnpm biome \"$@\"\n".utf8).write(to: box.file)
        let notMachO = BiomeScanner(home: box.home, digests: box.digests, readTarget: { _ in nil })
        #expect(notMachO.scan().isEmpty)

        try FileManager.default.removeItem(at: box.file)
        let elsewhere = box.root.appendingPathComponent("ZZFixture-dotfiles")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let loose = try box.install("2.5.15", at: elsewhere.appendingPathComponent("biome"))
        try FileManager.default.createSymbolicLink(atPath: box.file.path, withDestinationPath: loose.path)
        let linked = try #require(box.scanner.scan().first)
        #expect(linked.linked)

        try FileManager.default.removeItem(at: loose)
        #expect(box.scanner.scan().first?.problem == .executableMissing)
    }

    @Test func nothingInstalledIsNothing() throws {
        #expect(try Sandbox().scanner.scan().isEmpty)
    }

    // MARK: - The verdict

    /// An update is the vendor's installer, pinned to the version checked and
    /// pointed at the install's directory, never editing a shell rc file;
    /// nothing is run to decide it.
    @Test func offersTheInstaller() async throws {
        let box = try Sandbox()
        try box.install("2.5.15")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "2.5.15")
        #expect(status.latestVersion == "2.6.2")
        #expect(status.oneClick?.display
            == "curl -fsSL https://biomejs.dev/install | BIOME_INSTALL_DIR=\(box.bin.path) bash -s -- --version 2.6.2 --no-modify-path")
        #expect(status.manualCommand == nil)
        #expect(!box.ran)
    }

    @Test func comparesVersions() async throws {
        let box = try Sandbox()
        try box.install("2.6.2")
        #expect(try await box.status().state == .upToDate)
        // A build newer than latest.txt (GitHub's release out before the site's
        // pointer moved), named from a list read under an older latest.
        let newer = try Sandbox()
        try newer.install("2.7.0")
        let ahead = try await newer.status()
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    /// Each gate withholds the click; those where the user can still update by
    /// hand hand out the command. Mutations: drop any one gate, or its command.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install("2.5.15")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        let install = try #require(box.scanner.scan().first)
        let command = try #require(await box.check().status(of: install, busy: nil).oneClick)

        #expect(try await box.status(busy: .installer(42)).withheld == .busy)

        // No digest on the latest release: what the installer leaves could not be checked.
        let fresh = try Sandbox()
        try fresh.install("2.5.15")
        fresh.publish("2.6.2", Sandbox.build("2.6.2"))
        fresh.digests.remember([BiomeRelease.Published(version: "2.5.15", binaryDigests: [Self.target: Sandbox.hex(Sandbox.build("2.5.15"))])])
        let undigested = await fresh.check(digest: false).status(of: try #require(fresh.scanner.scan().first), busy: nil)
        #expect(undigested.withheld == .unverified)
        #expect(undigested.oneClick == nil)
        #expect(undigested.manualCommand == BiomeCheck.installCommand(version: "2.6.2", installDirectory: fresh.bin.path))
        #expect(CLIToolWording.reason(.unverified, of: undigested) == "The new release can’t be checked against a published digest")

        // latest.txt unreachable, or naming a prerelease: no verdict.
        let down = await box.check(latestStatus: 503).status(of: install, busy: nil)
        #expect(down.withheld == .channelUnreadable)
        let beta = await box.check(latest: "2.7.0-beta.1").status(of: install, busy: nil)
        #expect(beta.withheld == .channelUnreadable)
        #expect(beta.note?.contains("not a stable release") == true)

        // GitHub's rate limit while identifying a file: said as GitHub's limit.
        let limited = try Sandbox()
        try limited.install("2.5.15")
        let refused = await limited.check(apiStatus: 403).status(of: try #require(limited.scanner.scan().first), busy: nil)
        #expect(refused.withheld == .rateLimited)
        #expect(refused.state == .unknown)

        // A directory the installer could not write without sudo.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = try await box.status()
        #expect(readOnly.withheld == .unsupportedInstaller)
        #expect(readOnly.oneClick == nil)
        #expect(readOnly.manualCommand == command)
        #expect(CLIToolWording.reason(.unsupportedInstaller, of: readOnly) == "Updating it needs administrator rights")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        // A link the installer's mv would replace with a file.
        let linked = BiomeInstall(path: box.file.path, binary: "/ZZFixture/elsewhere/biome", version: "2.5.15", linked: true)
        let status = await box.check().status(of: linked, busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand == command)
    }

    // MARK: - The release

    /// Only `@biomejs/biome@X.Y.Z` releases not marked prerelease, and only
    /// their macOS binaries' digests. Mutations: take another asset's digest;
    /// accept js-api's tag or a prerelease.
    @Test func parsesTheReleaseDigests() throws {
        let hex = String(repeating: "ab", count: 32)
        let json = """
            [{"tag_name": "@biomejs/js-api@6.1.0", "prerelease": false, "assets": []},
             {"tag_name": "@biomejs/biome@2.6.2", "prerelease": false, "draft": false, "assets": [
               {"name": "biome-darwin-arm64", "digest": "sha256:\(hex)"},
               {"name": "biome-darwin-x64", "digest": null},
               {"name": "biome-linux-arm64", "digest": "sha256:\(String(repeating: "cd", count: 32))"}]},
             {"tag_name": "@biomejs/biome@2.0.0-beta.6", "prerelease": true, "assets": []},
             {"tag_name": "@biomejs/biome@2.7.0", "prerelease": true, "assets": [
               {"name": "biome-darwin-arm64", "digest": "sha256:\(String(repeating: "ee", count: 32))"}]},
             {"tag_name": "cli/v1.9.5-nightly.81fdedb", "prerelease": true, "assets": []}]
            """
        #expect(BiomeRelease.parseReleases(Data(json.utf8))
            == [BiomeRelease.Published(version: "2.6.2", binaryDigests: ["darwin-arm64": hex])])
        #expect(BiomeRelease.tagURL(version: "2.6.2").absoluteString
            == "https://api.github.com/repos/biomejs/biome/releases/tags/%40biomejs%2Fbiome%402.6.2")
    }

    // MARK: - The update

    /// The installer runs as `/bin/bash <file> --version <v> --no-modify-path`,
    /// with `HOME` the scan's, `BIOME_INSTALL_DIR` the install's directory, a
    /// `PATH` of the script's tools only (no `sudo`), and the variables that
    /// would redirect it gone; then the file it left is named by its hash.
    /// Mutations: keep `BIOME_VERSION` or `XDG_BIN_HOME`; drop
    /// `--no-modify-path`; put `sudo` on the `PATH`.
    @Test func updatesThroughTheInstallerAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install("2.5.15")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        let status = try await box.status()
        let outcome = await box.updater(script: try box.installer(installs: "2.6.2")).update(status)
        #expect(outcome == .updated(version: "2.6.2"))
        #expect(box.read("ARGS")?.trimmingCharacters(in: .whitespacesAndNewlines) == "--version 2.6.2 --no-modify-path")
        let env = try #require(box.read("ENV"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        #expect(env.contains("BIOME_INSTALL_DIR=\(box.bin.path)\n"))
        #expect(env.contains("KEEP=1"))
        #expect(!env.contains("BIOME_VERSION"))
        #expect(!env.contains("XDG_BIN_HOME"))
        #expect(!env.contains("GITHUB_PATH"))
        let tools = Set(try #require(box.read("PATHLS")).split(separator: "\n").map(String.init))
        #expect(tools == Set(BiomeUpdater.defaultTools.keys))
        #expect(!tools.contains("sudo"))
        #expect(box.scanner.scan().first?.version == "2.6.2")
    }

    /// What the installer leaves must be its version's published build, and
    /// newer. Mutations: drop either check after the run.
    @Test func whatTheInstallerLeftMustPassTheTrustRule() async throws {
        let box = try Sandbox()
        try box.install("2.5.15")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        let status = try await box.status()

        let unpublished = await box.updater(script: try box.installer(installs: "2.6.2", publishNew: false)).update(status)
        guard case .failed(let message, _) = unpublished else { Issue.record("expected failed, got \(unpublished)"); return }
        #expect(message.contains("is not the Biome 2.6.2 published on GitHub"))

        try box.install("2.5.15")
        let unchanged = await box.updater(script: try box.installer(installs: nil)).update(status)
        guard case .failed(let still, _) = unchanged else { Issue.record("expected failed, got \(unchanged)"); return }
        #expect(still.contains("is still Biome 2.5.15"))
    }

    /// The installer's own `Error: …` line (red, on stderr) and its exit status
    /// are the row's reason; the whole output is the detail pane's.
    @Test func aFailingInstallerSaysWhy() async throws {
        let box = try Sandbox()
        try box.install("2.5.15")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        let status = try await box.status()
        let script = try box.installer(installs: nil, body: #"""
            printf "\033[0;31mError: %s\033[0m\n" "failed to download Biome 2.6.2; see https://github.com/biomejs/biome/releases" >&2
            exit 1
            """#)
        let outcome = await box.updater(script: script).update(status)
        guard case .failed(let message, let output) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(message == "failed to download Biome 2.6.2; see https://github.com/biomejs/biome/releases (the installer exited with status 1)")
        #expect(output.contains("Error: failed to download Biome 2.6.2"))
    }

    /// Asked again at the click: a run under way, the file changed, a directory
    /// gone read-only, a release no longer newer, a script that is not the
    /// installer. Nothing is run in any of them. Mutations: drop any one.
    @Test func theClickAsksTheGatesAgain() async throws {
        let box = try Sandbox()
        try box.install("2.5.15")
        box.publish("2.6.2", Sandbox.build("2.6.2"))
        let status = try await box.status()
        let script = try box.installer(installs: "2.6.2")

        #expect(await box.updater(script: script, busy: { .installer(7) }).update(status) == .busy("Biome's installer is running (pid 7)"))
        let notNewer = await box.updater(script: script, latest: "2.5.15").update(status)
        guard case .failed = notNewer else { Issue.record("expected failed, got \(notNewer)"); return }
        // Valid bash that would run — and leave ARGS — were it not refused for
        // not being Biome's installer.
        let notInstaller = await box.updater(script: Data("#!/usr/bin/env bash\necho \"$@\" > \"\(box.root.path)/ARGS\"\n".utf8))
            .update(status)
        guard case .failed = notInstaller else { Issue.record("expected failed, got \(notInstaller)"); return }

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = await box.updater(script: script).update(status)
        guard case .failed(let why, _) = readOnly else { Issue.record("expected failed, got \(readOnly)"); return }
        #expect(why.contains("sudo"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        try box.install("2.5.14")
        let moved = await box.updater(script: script).update(status)
        guard case .failed = moved else { Issue.record("expected failed, got \(moved)"); return }
        #expect(!box.ran)
    }

    @Test func aStatusWithoutTheClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.install("2.5.15", publish: false, salt: "local")
        let status = try await box.status()
        #expect(await box.updater(script: try box.installer(installs: "2.6.2")).update(status) == .notOffered)
        #expect(!box.ran)
    }

    /// The installer's own source holds what `isInstaller` asks for. Mutation:
    /// ask for a marker the real script lacks.
    @Test func recognisesTheInstallersShape() {
        let real = """
            #!/usr/bin/env bash
            set -euo pipefail
            readonly APP="biome"
            readonly INSTALL_DIR="${BIOME_INSTALL_DIR:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
            \t\t-v | --version)
            \t\t--no-modify-path)
            """
        #expect(BiomeUpdater.isInstaller(Data(real.utf8)))
        #expect(!BiomeUpdater.isInstaller(Data("<!doctype html><title>404</title>".utf8)))
    }

    // MARK: - Activity

    /// Mutation: match any `bash`, or any curl.
    @Test func busyIsTheInstallerOrItsDownload() {
        typealias P = ClaudeCodeActivity.Process
        #expect(BiomeActivity.busy(processes: [P(pid: 3, arguments: ["/bin/bash", "/var/folders/x/duo-biome-1/biome-install-AB.sh", "--version", "2.6.2"])])
            == .installer(3))
        #expect(BiomeActivity.busy(processes: [P(pid: 4, arguments: ["curl", "--fail", "--location", "https://github.com/biomejs/biome/releases/download/@biomejs/biome@2.6.2/biome-darwin-arm64"])])
            == .download(4))
        #expect(BiomeActivity.busy(processes: [P(pid: 5, arguments: ["/bin/bash", "install"]), P(pid: 6, arguments: ["curl", "https://example.com"])]) == nil)
    }

    // MARK: - Release notes

    /// Changesets bodies, as Biome's CLI releases carry them: the version's own
    /// `##` heading, then `### Minor Changes` / `### Patch Changes`, each `-`
    /// line an item; GitHub's generated pull request list and the contributors
    /// after them are not, and js-api's releases and prereleases are not the
    /// CLI's. Mutations: drop `tagPattern` or `skipSections`; parse with
    /// another format.
    @Test func releaseNotesKeepTheirSections() throws {
        let json = """
            [{"tag_name": "@biomejs/js-api@6.1.0", "published_at": "2026-10-21T09:49:44Z", "draft": false, "prerelease": false,
              "body": "## 6.1.0\\n\\n### Minor Changes\\n\\n- A js-api change."},
             {"tag_name": "@biomejs/biome@2.6.2", "published_at": "2026-10-21T11:05:24Z", "draft": false, "prerelease": false,
              "body": "## 2.6.2\\n\\n### Minor Changes\\n\\n- [#11479](https://github.com/biomejs/biome/pull/11479) [`5c60ba8`](https://github.com/biomejs/biome/commit/5c60ba8) Thanks [@nhedger](https://github.com/nhedger)! - Added a `--git` flag to `biome init`.\\n\\n### Patch Changes\\n\\n- [#11800](https://github.com/biomejs/biome/pull/11800) [`1a2b3c4`](https://github.com/biomejs/biome/commit/1a2b3c4) Thanks [@ematipico](https://github.com/ematipico)! - Fixed a crash.\\n\\n## What's Changed\\n* chore: bump deps by @renovate in https://github.com/biomejs/biome/pull/11801\\n* refactor(codegen): deduplicate local types by @dyc3 in https://github.com/biomejs/biome/pull/11798\\n\\n## New Contributors\\n* @posido made their first contribution in https://github.com/biomejs/biome/pull/11907\\n\\n**Full Changelog**: https://github.com/biomejs/biome/compare/@biomejs/biome@2.5.15...@biomejs/biome@2.6.2"},
             {"tag_name": "@biomejs/biome@2.7.0-beta.1", "published_at": "2026-10-20T00:00:00Z", "draft": false, "prerelease": true,
              "body": "## 2.7.0-beta.1\\n\\n### Minor Changes\\n\\n- A beta change."},
             {"tag_name": "@biomejs/biome@2.5.15", "published_at": "2026-09-30T15:23:21Z", "draft": false, "prerelease": false,
              "body": "## 2.5.15\\n\\n### Patch Changes\\n\\n- Fixed another thing."}]
            """
        let changelog = try #require(BiomeRelease.parseNotes(json))
        #expect(changelog.entries.map(\.version) == ["2.6.2", "2.5.15"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.content.compactMap { if case .heading(let h) = $0 { h } else { nil } } == ["Minor Changes", "Patch Changes"])
        #expect(newest.items.count == 2)
        #expect(newest.items.first?.contains("Added a `--git` flag to `biome init`.") == true)
    }
}
