import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Obelus: finding `obg` and `ob` where its installer puts them, reading their
/// version out of the file, their verdict, the archive check the trust rule
/// rests on, their one-click (the vendor's installer) and their release notes.
///
/// "obg" here is a small file carrying `obelus/<version>`, as every real build
/// does (measured 2026-10-19 on 0.9.0 to 0.16.0). The "installer" is a
/// `#!/bin/sh` script that copies a staged file over the install, as the real
/// one's `install` does. `SHA256SUMS`, the downloads and their unpacking are
/// injected: nothing here reads the host's process table, runs an Obelus build
/// or reaches the network.
@Suite struct ObelusTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        func file(_ name: ObelusInstall.Binary = .obg) -> URL { bin.appendingPathComponent(name.rawValue) }
        let digests: ObelusPublishedDigests
        private let lock = NSLock()
        /// "<version> <binary>" → the binary its release archive holds.
        private var published: [String: Data] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-obelus-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = ObelusPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        /// A build's bytes the way the real ones lay them out: a source path, a
        /// crate's version, then the User-Agent and what the linker put after it.
        static func build(_ version: String, salt: String = "") -> Data {
            Data("obelus/src/main.rs\0gix-hashtable-0.16.0\0d: edge.height == self.height - 1obelus/\(version)not cached\(salt)".utf8)
        }

        @discardableResult
        func install(_ version: String, _ name: ObelusInstall.Binary = .obg, at url: URL? = nil,
                     publish: Bool = true, salt: String = "") throws -> URL {
            let url = url ?? file(name)
            let bytes = Self.build(version, salt: salt)
            try bytes.write(to: url)
            if publish { self.publish(version, name, bytes) }
            return url
        }

        func publish(_ version: String, _ name: ObelusInstall.Binary, _ bytes: Data) {
            lock.withLock { published["\(version) \(name.rawValue)"] = bytes }
        }
        var downloadCount: Int { lock.withLock { downloads } }

        var scanner: ObelusScanner { ObelusScanner(home: home, isQuarantined: { _ in false }) }

        static func archive(_ version: String, _ name: ObelusInstall.Binary) -> Data { Data("txz-\(version) \(name.rawValue)".utf8) }
        static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

        /// `SHA256SUMS` as the release carries it: a line for each archive, Linux's
        /// among them; `names` the macOS archives it lists.
        static func sums(_ version: String, names: [ObelusInstall.Binary] = ObelusInstall.Binary.allCases) -> Data {
            var lines = ["\(String(repeating: "cd", count: 32))  ob-\(version)-aarch64-unknown-linux-gnu.tar.xz"]
            for name in names {
                lines.append("\(hex(archive(version, name)))  \(name.rawValue)-\(version)-universal2-apple-darwin.tar.xz")
            }
            lines.append("\(String(repeating: "ef", count: 32))  obelus.svg")
            return Data((lines.joined(separator: "\n") + "\n").utf8)
        }

        func release(latest: String = "0.16.0", names: [ObelusInstall.Binary] = ObelusInstall.Binary.allCases,
                     status: Int = 200) -> ObelusRelease {
            ObelusRelease(fetch: { url, _ in
                if status != 200 { return (Data(), status, nil) }
                if url == ObelusRelease.latestSums { return (Self.sums(latest, names: names), 200, nil) }
                let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                return (Self.sums(version), 200, nil)
            })
        }

        /// The release assets; `tamper` serves an archive `SHA256SUMS` does not name.
        func verifier(tamper: Bool = false) -> ObelusVerifier {
            let release = release()
            return ObelusVerifier(
                release: { try await release.release(version: $0) },
                download: { url in
                    let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                    let name = ObelusInstall.Binary(rawValue: String(url.lastPathComponent.prefix { $0 != "-" }))!
                    self.lock.withLock { self.downloads += 1 }
                    return tamper ? Data("other".utf8) : Self.archive(version, name)
                },
                extract: { archive, directory in
                    let parts = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
                        .replacingOccurrences(of: "txz-", with: "").split(separator: " ").map(String.init)
                    let name = ObelusInstall.Binary(rawValue: parts[1])!
                    let bytes = self.lock.withLock { self.published["\(parts[0]) \(parts[1])"] } ?? Data()
                    let inside = directory.appendingPathComponent(ObelusRelease.archiveDirectory(name, version: parts[0]))
                    try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
                    try bytes.write(to: inside.appendingPathComponent(name.rawValue))
                },
                digests: digests)
        }

        func check(latest: String = "0.16.0", names: [ObelusInstall.Binary] = ObelusInstall.Binary.allCases,
                   status: Int = 200) -> ObelusCheck {
            let release = release(latest: latest, names: names, status: status)
            return ObelusCheck(latest: { try await release.latest() })
        }

        func status(_ name: ObelusInstall.Binary = .obg, latest: String = "0.16.0",
                    names: [ObelusInstall.Binary] = ObelusInstall.Binary.allCases,
                    busy: ObelusActivity.Busy? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first { $0.name == name })
            return await check(latest: latest, names: names).status(of: install, busy: busy)
        }

        /// The installer stand-in: records its arguments, environment and `PATH`,
        /// then copies the staged build over `--dir/<--bin>`, as the real one does.
        func installer(installs version: String?, _ name: ObelusInstall.Binary = .obg, publishNew: Bool = true,
                       body: String? = nil) throws -> Data {
            var copy = "echo nothing"
            if let version {
                let bytes = Self.build(version, salt: publishNew ? "" : "local")
                if publishNew { publish(version, name, bytes) }
                let staged = root.appendingPathComponent("staged-\(version)")
                try bytes.write(to: staged)
                copy = #"/bin/cp "\#(staged.path)" "$6/$2""#
            }
            return Data("""
                #!/bin/sh
                repository=obelus-editor/obelus
                #   --bin) --version) --dir) --no-omarchy) --no-desktop)
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$PATH" > "\(root.path)/PATHLS"
                \(body ?? copy)
                """.utf8)
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        func updater(script: Data, latest: String = "0.16.0", busy: @escaping ObelusUpdater.BusyCheck = { nil }) -> ObelusUpdater {
            ObelusUpdater(
                busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(),
                fetchScript: { url in
                    #expect(url == ObelusUpdater.installer)
                    return script
                },
                environment: { ["OBELUS_INSTALL_DIR": "/ZZFixture/elsewhere", "KEEP": "1"] })
        }
    }

    // MARK: - Finding it

    /// The version after `obelus/`, and never a path after it or a crate's
    /// version elsewhere. Mutations: accept disagreeing versions; read a path.
    @Test func readsTheUserAgentVersion() throws {
        let box = try Sandbox()
        func read(_ text: String) throws -> String? {
            let url = box.root.appendingPathComponent("probe")
            try Data(text.utf8).write(to: url)
            return ObelusScanner.version(of: url)
        }
        #expect(try read("obelus/src/lib.rs\0obelus/0.16.0not cached\0obelus/0.16.0https://") == "0.16.0")
        #expect(try read("x obelus/0.9.0\0") == "0.9.0")
        #expect(try read("obelus/src/lib.rs\0vte-0.15.0\0") == nil)
        #expect(try read("obelus/0.16.0 obelus/0.15.0") == nil)
        #expect(try read("obelus/0.16.0.1") == nil)
    }

    /// Both binaries, each its own row; the file is read, never run.
    @Test func findsBothBinaries() throws {
        let box = try Sandbox()
        let window = try box.install("0.15.0", .obg)
        let terminal = try box.install("0.14.0", .ob)
        #expect(box.scanner.scan() == [
            ObelusInstall(path: window.path, name: .obg, binary: window.path, version: "0.15.0"),
            ObelusInstall(path: terminal.path, name: .ob, binary: terminal.path, version: "0.14.0"),
        ])
    }

    /// Another tool's `~/.local/bin/ob` is not Obelus's at all. Mutation: keep a
    /// file without `obelus/` as a versionUnreadable row.
    @Test func anotherToolsObIsNotARow() throws {
        let box = try Sandbox()
        try Data("#!/bin/sh\necho some other ob\n".utf8).write(to: box.file(.ob))
        #expect(box.scanner.scan().isEmpty)
    }

    /// Homebrew's, mise's and an app's copy belong to them; a link to anywhere
    /// else is an install the click would replace; a dangling link is broken.
    /// Mutations: drop the Cellar, mise or `.app` test.
    @Test func ownersOtherThanTheInstallerAreSkipped() throws {
        let box = try Sandbox()
        for owner in ["ZZFixture-prefix/Cellar/obelus/0.16.0/bin",
                      "home/.local/share/mise/installs/github-obelus-editor-obelus/0.16.0",
                      "ZZFixture.app/Contents/MacOS"] {
            let dir = box.root.appendingPathComponent(owner)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let owned = try box.install("0.16.0", at: dir.appendingPathComponent("obg"))
            try? FileManager.default.removeItem(at: box.file())
            try FileManager.default.createSymbolicLink(atPath: box.file().path, withDestinationPath: owned.path)
            #expect(box.scanner.scan().isEmpty, "\(owner)")
        }

        try FileManager.default.removeItem(at: box.file())
        let elsewhere = box.root.appendingPathComponent("ZZFixture-dotfiles")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let loose = try box.install("0.15.0", at: elsewhere.appendingPathComponent("obg"))
        try FileManager.default.createSymbolicLink(atPath: box.file().path, withDestinationPath: loose.path)
        let linked = try #require(box.scanner.scan().first)
        #expect(linked.linked)
        #expect(linked.version == "0.15.0")

        try FileManager.default.removeItem(at: loose)
        #expect(box.scanner.scan().first?.problem == .executableMissing)
    }

    @Test func nothingInstalledIsNothing() throws {
        #expect(try Sandbox().scanner.scan().isEmpty)
    }

    /// Obelus's, but with no version after its `obelus/`.
    @Test func aFileWithoutTheVersionIsUnreadable() async throws {
        let box = try Sandbox()
        try Data("obelus/src/main.rs\0".utf8).write(to: box.file())
        let status = try await box.status()
        #expect(status.withheld == .versionUnreadable)
        #expect(status.oneClick == nil)
    }

    // MARK: - The verdict

    /// An update is the vendor's installer pointed at the row's binary and
    /// directory; nothing is downloaded and nothing is run to decide it.
    @Test func offersTheInstaller() async throws {
        let box = try Sandbox()
        try box.install("0.15.0", .obg)
        try box.install("0.15.0", .ob)
        for name in ObelusInstall.Binary.allCases {
            let status = try await box.status(name)
            #expect(status.state == .updateAvailable)
            #expect(status.name == name.rawValue)
            #expect(status.installedVersion == "0.15.0")
            #expect(status.latestVersion == "0.16.0")
            #expect(status.oneClick?.display
                == "curl -fsSL https://raw.githubusercontent.com/obelus-editor/obelus/master/contrib/install.sh | sh -s -- --bin \(name.rawValue) --dir \(box.bin.path)")
            #expect(status.manualCommand == nil)
        }
        #expect(box.downloadCount == 0)
    }

    /// One `SHA256SUMS` for both rows of a check. Mutation: ask it per row.
    @Test func oneCheckAsksOnce() async throws {
        let box = try Sandbox()
        try box.install("0.15.0", .obg)
        try box.install("0.15.0", .ob)
        let asked = Counter()
        let release = box.release()
        let check = ObelusCheck(latest: { asked.add(); return try await release.latest() })
        let report = await ObelusProvider.report(installs: box.scanner.scan(), busy: nil, check: check)
        #expect(report.statuses.map(\.state) == [.updateAvailable, .updateAvailable])
        #expect(asked.count == 1)
        #expect(await ObelusProvider.report(installs: [], busy: nil, check: check).statuses.isEmpty)
        #expect(asked.count == 1)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func add() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    @Test func comparesVersions() async throws {
        let box = try Sandbox()
        try box.install("0.16.0")
        #expect(try await box.status().state == .upToDate)
        try box.install("0.17.0")
        let ahead = try await box.status()
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    /// Each gate withholds the click; those where the user can still update by
    /// hand hand out the command. Mutations: drop any one gate, or its command.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install("0.15.0")
        let command = try #require(try await box.status().oneClick)

        #expect(try await box.status(busy: .installer(42)).withheld == .busy)

        // SHA256SUMS lists ob's archive but not obg's.
        let unlisted = try await box.status(names: [.ob])
        #expect(unlisted.withheld == .unverified)
        #expect(unlisted.oneClick == nil)
        #expect(unlisted.manualCommand == command)

        let down = await box.check(status: 404).status(of: try #require(box.scanner.scan().first), busy: nil)
        #expect(down.withheld == .channelUnreadable)
        #expect(down.state == .unknown)

        // A directory this user cannot write to.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = try await box.status()
        #expect(readOnly.withheld == .unsupportedInstaller)
        #expect(readOnly.oneClick == nil)
        #expect(readOnly.manualCommand == command)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        // A link the installer's install would replace with a file.
        let linked = ObelusInstall(path: box.file().path, binary: "/ZZFixture/elsewhere/obg", version: "0.15.0", linked: true)
        let status = await box.check().status(of: linked, busy: nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand == command)
    }

    // MARK: - The release

    /// The version every macOS archive's name carries, and each one's sha256;
    /// nothing from another asset. Mutations: take Linux's line; accept two
    /// versions; accept a short hash.
    @Test func parsesSHA256SUMS() throws {
        let a = String(repeating: "ab", count: 32)
        let b = String(repeating: "cd", count: 32)
        let sums = """
            \(String(repeating: "11", count: 32))  obg-0.16.0-x86_64-unknown-linux-gnu.tar.xz
            \(a)  obg-0.16.0-universal2-apple-darwin.tar.xz
            \(b) *ob-0.16.0-universal2-apple-darwin.tar.xz
            \(String(repeating: "22", count: 32))  Obelus-0.16.0-universal2-apple-darwin.app.zip
            """
        #expect(ObelusRelease.parseSums(Data(sums.utf8))
            == ObelusRelease.Published(version: "0.16.0", archiveDigests: [.obg: a, .ob: b]))
        #expect(ObelusRelease.parseSums(Data("\(a)  obg-0.16.0-universal2-apple-darwin.tar.xz\n\(b)  ob-0.15.0-universal2-apple-darwin.tar.xz".utf8)) == nil)
        #expect(ObelusRelease.parseSums(Data("abcd  obg-0.16.0-universal2-apple-darwin.tar.xz".utf8)) == nil)
        #expect(ObelusRelease.parseSums(Data("<html>Not Found</html>".utf8)) == nil)
    }

    /// The real v0.16.0 `SHA256SUMS`'s macOS lines, as fetched 2026-10-19.
    @Test func parsesTheRealSums() throws {
        let sums = """
            c7817b7727c0dbfb6ce925d40429ff3dbb5409de206249020cead9eaab7838e9  ob-0.16.0-universal2-apple-darwin.tar.xz
            51644d90759d11e518ed2bf47e9e872b3786f249c84dc719baf7fadd4afc5962  ob-0.16.0-x86_64-unknown-linux-gnu.tar.xz
            3a7d4a702b7191a426ed7096aba73aa7a5d99c404e4912ee9d4bfbdef64d6fd2  obg-0.16.0-universal2-apple-darwin.tar.xz
            7136f4554a866bf4b64df63a6fdd1c2f12e38da0d4754a5bbfc9cf22da064577  Obelus-0.16.0-universal2-apple-darwin.app.zip
            fac3a944aece09a6c7bf9525b7dd001c585a25551637b5185bca2591cb0e3fc0  obelus.svg
            """
        let published = try #require(ObelusRelease.parseSums(Data(sums.utf8)))
        #expect(published.version == "0.16.0")
        #expect(published.archiveDigests[.obg] == "3a7d4a702b7191a426ed7096aba73aa7a5d99c404e4912ee9d4bfbdef64d6fd2")
        #expect(published.archiveDigests[.ob] == "c7817b7727c0dbfb6ce925d40429ff3dbb5409de206249020cead9eaab7838e9")
    }

    // MARK: - The archive check

    /// The archive must match `SHA256SUMS`; the binary inside it is compared
    /// with the file, and remembered so the archive is downloaded once per
    /// version and binary. Mutations: skip the archive's check; compare
    /// nothing; never remember; remember obg's hash for ob.
    @Test func verifiesAgainstTheReleaseArchive() async throws {
        let box = try Sandbox()
        let file = try box.install("0.15.0").path
        #expect(await box.verifier().verify(binary: file, name: .obg, version: "0.15.0") == .matches)
        #expect(await box.verifier().verify(binary: file, name: .obg, version: "0.15.0") == .matches)
        #expect(box.downloadCount == 1)
        #expect(box.digests.digest(.obg, version: "0.15.0") == CLIToolTrust.sha256(of: URL(fileURLWithPath: file)))
        #expect(box.digests.digest(.ob, version: "0.15.0") == nil)

        box.publish("0.14.0", .obg, Sandbox.build("0.14.0"))
        let tampered = await box.verifier(tamper: true).verify(binary: file, name: .obg, version: "0.14.0")
        guard case .couldNotVerify = tampered else { Issue.record("expected couldNotVerify, got \(tampered)"); return }
        #expect(box.digests.digest(.obg, version: "0.14.0") == nil)

        // Not the published build of its version.
        try box.install("0.14.0", publish: false, salt: "local")
        let differs = await box.verifier().verify(binary: file, name: .obg, version: "0.14.0")
        guard case .differs = differs else { Issue.record("expected differs, got \(differs)"); return }
    }

    // MARK: - The update

    /// The installer runs pinned to the release checked, for the row's binary
    /// and directory, with `HOME` the scan's, a `PATH` of the script's tools
    /// only and `OBELUS_INSTALL_DIR` gone; then the file it left is checked
    /// against its release. Mutations: drop `--version`; keep the variable;
    /// skip the check after.
    @Test func updatesThroughTheInstallerAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install("0.15.0", .ob)
        let status = try await box.status(.ob)
        let outcome = await box.updater(script: try box.installer(installs: "0.16.0", .ob)).update(status)
        #expect(outcome == .updated(version: "0.16.0"))
        #expect(box.read("ARGS")?.trimmingCharacters(in: .whitespacesAndNewlines)
            == "--bin ob --version v0.16.0 --dir \(box.bin.path) --no-omarchy --no-desktop")
        let env = try #require(box.read("ENV"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        #expect(env.contains("KEEP=1"))
        #expect(!env.contains("OBELUS_INSTALL_DIR"))
        let tools = Set(try #require(box.read("PATHLS")).split(separator: "\n").map(String.init))
        #expect(tools == Set(ObelusUpdater.defaultTools.keys))
        #expect(!tools.contains("sudo"))
        #expect(box.scanner.scan().first { $0.name == .ob }?.version == "0.16.0")
    }

    /// What the installer leaves must be its version's published build, and
    /// newer. Mutations: drop either check after the run.
    @Test func whatTheInstallerLeftMustPassTheTrustRule() async throws {
        let box = try Sandbox()
        try box.install("0.15.0")
        let status = try await box.status()

        box.publish("0.16.0", .obg, Sandbox.build("0.16.0"))
        let unpublished = await box.updater(script: try box.installer(installs: "0.16.0", publishNew: false)).update(status)
        guard case .failed(let message, _) = unpublished else { Issue.record("expected failed, got \(unpublished)"); return }
        #expect(message.contains("is not the obg 0.16.0 obelus-editor published"))

        try box.install("0.15.0")
        let unchanged = await box.updater(script: try box.installer(installs: nil)).update(status)
        guard case .failed(let still, _) = unchanged else { Issue.record("expected failed, got \(unchanged)"); return }
        #expect(still.contains("is still obg 0.15.0"))
    }

    /// The installer's own `obelus: …` line and its exit status are the row's
    /// reason; the whole output is the detail pane's.
    @Test func aFailingInstallerSaysWhy() async throws {
        let box = try Sandbox()
        try box.install("0.15.0")
        let status = try await box.status()
        let script = try box.installer(installs: nil, body: """
            echo "obelus: v0.16.0 has no obg-0.16.0-universal2-apple-darwin.tar.xz" >&2
            exit 1
            """)
        let outcome = await box.updater(script: script).update(status)
        guard case .failed(let message, let output) = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(message == "v0.16.0 has no obg-0.16.0-universal2-apple-darwin.tar.xz (install.sh exited with status 1)")
        #expect(output.contains("obelus: v0.16.0 has no"))
    }

    /// Asked again at the click: a run under way, the file changed, a directory
    /// gone read-only, a release no longer newer, a script that is not the
    /// installer. Nothing is run in any of them. Mutations: drop any one.
    @Test func theClickAsksTheGatesAgain() async throws {
        let box = try Sandbox()
        try box.install("0.15.0")
        let status = try await box.status()
        let script = try box.installer(installs: "0.16.0")

        #expect(await box.updater(script: script, busy: { .installer(7) }).update(status) == .busy("Obelus's installer is running (pid 7)"))
        let notNewer = await box.updater(script: script, latest: "0.15.0").update(status)
        guard case .failed = notNewer else { Issue.record("expected failed, got \(notNewer)"); return }
        let notInstaller = await box.updater(script: Data("#!/bin/sh\necho \"$@\" > \"\(box.root.path)/ARGS\"\n".utf8))
            .update(status)
        guard case .failed = notInstaller else { Issue.record("expected failed, got \(notInstaller)"); return }

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = await box.updater(script: script).update(status)
        guard case .failed(let why, _) = readOnly else { Issue.record("expected failed, got \(readOnly)"); return }
        #expect(why.contains("cannot write"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        try box.install("0.14.0")
        let moved = await box.updater(script: script).update(status)
        guard case .failed = moved else { Issue.record("expected failed, got \(moved)"); return }
        #expect(!box.ran)
    }

    @Test func aStatusWithoutTheClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.install("0.15.0")
        let status = try await box.status(names: [.ob])
        #expect(await box.updater(script: try box.installer(installs: "0.16.0")).update(status) == .notOffered)
        #expect(!box.ran)
    }

    /// The real installer passes `isInstaller`, as fetched 2026-10-19: its
    /// first line, its repository and each option the run passes.
    @Test func recognisesTheRealInstallersShape() {
        let excerpt = """
            #!/bin/sh
            # Fetches a released Obelus and puts it somewhere on your PATH.
            repository=obelus-editor/obelus
            while [ $# -gt 0 ]; do
                case $1 in
                    --bin) asked=${2:-}; binaries=$asked; shift 2 ;;
                    --version) tag=${2:-}; shift 2 ;;
                    --dir) directory=${2:-}; shift 2 ;;
                    --no-omarchy) omarchy=no; shift ;;
                    --no-desktop) desktop=no; shift ;;
            """
        #expect(ObelusUpdater.isInstaller(Data(excerpt.utf8)))
        #expect(!ObelusUpdater.isInstaller(Data(excerpt.replacingOccurrences(of: "--version)", with: "--tag)").utf8)))
        #expect(!ObelusUpdater.isInstaller(Data("<!DOCTYPE html>".utf8)))
    }

    // MARK: - Activity

    /// Mutation: match any `sh`, or any curl.
    @Test func busyIsTheInstallerOrItsDownload() {
        typealias P = ClaudeCodeActivity.Process
        #expect(ObelusActivity.busy(processes: [P(pid: 3, arguments: ["/bin/sh", "/var/folders/x/duo-obelus-1/obelus-install-AB.sh", "--bin", "obg"])])
            == .installer(3))
        #expect(ObelusActivity.busy(processes: [P(pid: 4, arguments: ["curl", "-fL", "--progress-bar", "https://github.com/obelus-editor/obelus/releases/download/v0.16.0/obg-0.16.0-universal2-apple-darwin.tar.xz", "-o", "/tmp/x"])])
            == .download(4))
        #expect(ObelusActivity.busy(processes: [P(pid: 5, arguments: ["/bin/sh", "install.sh"]), P(pid: 6, arguments: ["curl", "https://example.com"])]) == nil)
    }

    // MARK: - Release notes

    /// GitHub's generated "What's Changed", as Obelus's releases carry it: one
    /// item per pull request, the newest first.
    @Test func releaseNotesListTheirChanges() throws {
        let json = """
            [{"tag_name": "v0.16.0", "published_at": "2026-10-16T10:13:48Z", "draft": false, "prerelease": false,
              "body": "## What's Changed\\n* Swift is read through tree-sitter: highlighted, and outlined by a query of Obelus's own by @sunli829 in https://github.com/obelus-editor/obelus/pull/212\\n* 0.16.0 by @sunli829 in https://github.com/obelus-editor/obelus/pull/222\\n\\n\\n**Full Changelog**: https://github.com/obelus-editor/obelus/compare/v0.15.0...v0.16.0"},
             {"tag_name": "v0.15.0", "published_at": "2026-10-15T09:40:25Z", "draft": false, "prerelease": false,
              "body": "## What's Changed\\n* A window without the keys draws no caret by @sunli829 in https://github.com/obelus-editor/obelus/pull/198"}]
            """
        let changelog = try #require(ObelusRelease.parseNotes(json))
        #expect(changelog.entries.map(\.version) == ["0.16.0", "0.15.0"])
        #expect(changelog.entries.first?.items.count == 2)
    }
}
