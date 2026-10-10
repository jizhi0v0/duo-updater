import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// The Lorca CLI: finding it where its install script puts it, the signed
/// manifest its check reads, its verdict, the archive check the trust rule rests
/// on, its one-click update both ways `lorca update` works, and what counts as
/// busy.
///
/// "lorca" here is a `#!/bin/sh` script in a temporary directory, carrying the
/// `lorca/<version>` User-Agent every real build carries, run on into the next
/// literal as it is in the real file (measured 2026-10-09 on 0.1.1 to 0.1.11).
/// Its `update` does what the real one does to the disk — stages a copy beside
/// the file and renames it over it — at once, or a moment later the way a
/// running `lorca serve` does. The manifest, the release downloads and their
/// unpacking are injected; the manifests are signed with a key made here.
@Suite struct LorcaTests {

    static let signingKey = Curve25519.Signing.PrivateKey()
    static let publicKey = signingKey.publicKey.rawRepresentation.base64EncodedString()

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var userBin: URL { home.appendingPathComponent(".local/bin") }
        let digests: LorcaPublishedDigests
        private let lock = NSLock()
        /// version → the `lorca` its release archive holds.
        private var published: [String: String] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("lorca-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = LorcaPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: userBin, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: userBin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func script(version: String, update: String = "exit 0") -> String {
            """
            #!/bin/sh
            # lorca/\(version)x-opencode-session and lorca/\(version)--version, lorca-agent/9.9.9
            case " $* " in *" update "*)
            \(update)
            ;; esac
            """
        }

        @discardableResult
        func install(version: String, update: String = "exit 0", publish: Bool = true) throws -> URL {
            let text = Self.script(version: version, update: update)
            let file = userBin.appendingPathComponent("lorca")
            try Data(text.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            if publish { self.publish(version, text) }
            return file
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        var downloadCount: Int { lock.withLock { downloads } }

        func settings(_ json: String) throws {
            let folder = home.appendingPathComponent(".lorca")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: folder.appendingPathComponent("settings.json"))
        }

        /// What `lorca update` does to the disk: stage the new build beside the
        /// old one and rename it into place, after `delay` seconds in the
        /// background when it is handed to `lorca serve` — or, given `held`,
        /// once that file is gone (~300 s at most).
        func updateBody(to version: String, served: Bool = false, delay: Double = 0, held: URL? = nil) throws -> String {
            let next = Self.script(version: version)
            publish(version, next)
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            let dir = userBin.path
            let swap = """
                /bin/cp "\(staged.path)" "\(dir)/.lorca-\(version)-$$" && /bin/chmod 755 "\(dir)/.lorca-\(version)-$$" && /bin/mv -f "\(dir)/.lorca-\(version)-$$" "\(dir)/lorca"
                """
            let record = """
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                """
            if served {
                let wait = held.map {
                    "n=0; while [ -e \"\($0.path)\" ] && [ $n -lt 3000 ]; do /bin/sleep 0.1; n=$((n+1)); done"
                } ?? "/bin/sleep \(delay)"
                return record + """

                    ( \(wait); \(swap) ) >/dev/null 2>&1 &
                    echo "Installing lorca \(version); lorca serve restarts into it once no bot is at work."
                    """
            }
            return record + "\n" + swap + "\necho \"Installed lorca \(version).\""
        }

        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        var scanner: LorcaScanner {
            LorcaScanner(home: home, isQuarantined: { _ in false }, readTarget: { _ in "macos-aarch64" })
        }

        static func archive(_ version: String) -> Data { Data("tgz-\(version)".utf8) }

        func verifier(tamper: Bool = false) -> LorcaVerifier {
            LorcaVerifier(
                download: { url in
                    let tag = url.deletingLastPathComponent().lastPathComponent
                    let version = String(tag.dropFirst("cli-v".count))
                    guard tag.hasPrefix("cli-v"), self.lock.withLock({ self.published[version] }) != nil else {
                        throw LorcaRelease.Failure.http(404)
                    }
                    if url.pathExtension == "sha256" {
                        let hex = SHA256.hash(data: Self.archive(version)).map { String(format: "%02x", $0) }.joined()
                        return Data("\(hex)  lorca-cli-macos-aarch64.tar.gz\n".utf8)
                    }
                    self.lock.withLock { self.downloads += 1 }
                    return tamper ? Data("other".utf8) : Self.archive(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
                        .replacingOccurrences(of: "tgz-", with: "")
                    let text = self.lock.withLock { self.published[version] } ?? ""
                    try Data(text.utf8).write(to: directory.appendingPathComponent("lorca"))
                },
                digests: digests)
        }

        func check(latest: String = "0.1.12", fails: Bool = false) -> LorcaCheck {
            let release = LorcaTests.release(latest: latest, fails: fails)
            let verifier = verifier()
            return LorcaCheck(latest: { try await release.latest() },
                              knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) },
                              freePort: { 50123 })
        }

        func updater(
            latest: String = "0.1.12", busy: @escaping LorcaUpdater.BusyCheck = { nil }, tamper: Bool = false,
            settle: Duration = .seconds(10), listening: Set<Int> = []
        ) -> LorcaUpdater {
            LorcaUpdater(
                busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(tamper: tamper),
                environment: {
                    ["LORCA_DOWNLOAD_URL": "https://elsewhere.example", "LORCA_HOME": "/elsewhere", "KEEP": "1"]
                },
                settle: settle, pollInterval: .milliseconds(50), isListening: { listening.contains($0) })
        }

        func status(latest: String = "0.1.12", appServe: pid_t? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(latest: latest).status(of: install, busy: nil, appServe: appServe)
        }
    }

    static func manifest(_ version: String, kind: String = "lorca-cli") -> Data {
        Data("""
            {"kind": "\(kind)", "version": "\(version)", "builds": {"macos-aarch64": \
            {"file": "lorca-cli-macos-aarch64.tar.gz", "sha256": "\(String(repeating: "ab", count: 32))", "size": 17788021}}}
            """.utf8)
    }

    static func sign(_ data: Data) -> Data {
        Data(((try? signingKey.signature(for: data)) ?? Data()).base64EncodedString().utf8)
    }

    static func release(
        latest: String = "0.1.12", fails: Bool = false, manifest: Data? = nil, signature: Data? = nil
    ) -> LorcaRelease {
        let body = manifest ?? Self.manifest(latest)
        let sig = signature ?? sign(body)
        return LorcaRelease(fetch: { url in
            if fails { throw LorcaRelease.Failure.http(503) }
            if url == LorcaRelease.manifest { return (body, 200) }
            #expect(url == LorcaRelease.signature)
            return (sig, 200)
        }, keys: [publicKey])
    }

    // MARK: - Scanner

    @Test func readsTheVersionFromTheFileWithoutRunningIt() throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", update: "touch \"\(box.root.path)/RAN\"")
        let install = try #require(box.scanner.scan().first)
        #expect(install.path == box.userBin.appendingPathComponent("lorca").path)
        #expect(install.version == "0.1.11")
        #expect(install.problem == nil)
        #expect(install.autoUpdate)
        #expect(install.hasUpdateCommand)
        #expect(box.read("RAN") == nil)
    }

    /// The real bytes run on into `x-opencode` and `--version`, which the
    /// parser stops at by itself; a literal led by `-` and a word (not seen in
    /// 0.1.1 to 0.1.11) would read as a semver suffix, which the cut drops.
    ///
    /// Mutation: drop the `-` cut in `compiledVersion` (the last case then reads
    /// two versions and nil).
    @Test func theVersionStopsWhereTheNextLiteralStarts() {
        func windows(_ text: String) -> [Data] {
            text.components(separatedBy: "lorca/").dropFirst().map { Data(("lorca/" + $0).utf8) }
        }
        #expect(LorcaScanner.compiledVersion(in: windows("lorca/0.1.11x-opencode lorca/0.1.11--versionP")) == "0.1.11")
        #expect(LorcaScanner.compiledVersion(in: windows("lorca/0.1.10\0\0 lorca/0.1.10x-opencode")) == "0.1.10")
        #expect(LorcaScanner.compiledVersion(in: windows("lorca/0.1.10 lorca/0.1.11")) == nil)
        #expect(LorcaScanner.compiledVersion(in: windows("lorca/serve")) == nil)
        #expect(LorcaScanner.compiledVersion(in: windows("lorca/0.1.11-agent lorca/0.1.11x")) == "0.1.11")
    }

    @Test func versionsBeforeTheUpdateCommandAreKnown() {
        #expect(!LorcaInstall(path: "/x", version: "0.1.10").hasUpdateCommand)
        #expect(LorcaInstall(path: "/x", version: "0.1.11").hasUpdateCommand)
        #expect(LorcaInstall(path: "/x", version: "1.0.0").hasUpdateCommand)
    }

    @Test func aBrokenLinkIsABrokenInstall() throws {
        let box = try Sandbox()
        try FileManager.default.createSymbolicLink(
            atPath: box.userBin.appendingPathComponent("lorca").path, withDestinationPath: box.root.appendingPathComponent("gone").path)
        let install = try #require(box.scanner.scan().first)
        #expect(install.problem == .executableMissing)
    }

    /// The Mac app's own copy is the app's, not this group's.
    @Test func aLinkIntoTheMacAppIsNotThisGroups() throws {
        let box = try Sandbox()
        let inside = box.root.appendingPathComponent("Lorca.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try Data(Sandbox.script(version: "1.0.11").utf8).write(to: inside.appendingPathComponent("lorca"))
        try FileManager.default.createSymbolicLink(
            atPath: box.userBin.appendingPathComponent("lorca").path, withDestinationPath: inside.appendingPathComponent("lorca").path)
        #expect(box.scanner.scan().isEmpty)
    }

    @Test func readsAutoUpdateAsLorcaDoes() throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11")
        try box.settings(#"{"auto_update": false}"#)
        #expect(box.scanner.scan().first?.autoUpdate == false)
        try box.settings(#"{"auto_update": true}"#)
        #expect(box.scanner.scan().first?.autoUpdate == true)
        try box.settings(#"{}"#)
        #expect(box.scanner.scan().first?.autoUpdate == true)
        try box.settings("not json")
        #expect(box.scanner.scan().first?.autoUpdate == true)
    }

    // MARK: - Manifest

    /// The manifest of cli-v0.1.11 and its `.sig` as published (fetched
    /// 2026-10-09), against the key `update.rs` trusts.
    @Test func thePublishedManifestVerifiesAgainstLorcasKey() throws {
        let manifest = try #require(Data(base64Encoded: Self.published0111))
        let signature = Data("ZQp3XD9YohHtuZBvJcJKrxnMm44PZ7UyyrfYyPN22p/t0GNwwSOHTCuN7CEMul5iOhdf5kdYbpaCWFrCBfnICw==\n".utf8)
        #expect(LorcaRelease.isSigned(manifest, signature: signature, keys: LorcaRelease.keys))
        var altered = manifest
        altered[altered.startIndex] = UInt8(ascii: " ")
        #expect(!LorcaRelease.isSigned(altered, signature: signature, keys: LorcaRelease.keys))
        let parsed = try #require(LorcaRelease.parse(manifest))
        #expect(parsed.version == "0.1.11")
        #expect(parsed.build == LorcaRelease.Manifest.Build(
            file: "lorca-cli-macos-aarch64.tar.gz",
            sha256: "b8e2ee7f9087194c8c742eae7f8e2b6049edc94054ec6837999496f95922fe45", size: 17_788_021))
    }

    @Test func aManifestNotSignedByATrustedKeyIsRefused() async throws {
        let other = Curve25519.Signing.PrivateKey()
        let body = Self.manifest("9.0.0")
        let forged = Data(try other.signature(for: body).base64EncodedString().utf8)
        await #expect(throws: LorcaRelease.Failure.unsigned) {
            try await Self.release(manifest: body, signature: forged).latest()
        }
        await #expect(throws: LorcaRelease.Failure.unsigned) {
            try await Self.release(manifest: body, signature: Data("not base64".utf8)).latest()
        }
        let manifest = try await Self.release(latest: "0.1.12").latest()
        #expect(manifest.version == "0.1.12")
    }

    @Test func anotherKindOrVersionShapeIsUnreadable() async {
        await #expect(throws: LorcaRelease.Failure.unreadable) {
            try await Self.release(manifest: Self.manifest("0.1.12", kind: "lorca-desktop")).latest()
        }
        await #expect(throws: LorcaRelease.Failure.unreadable) {
            try await Self.release(manifest: Self.manifest("0.1.12-beta")).latest()
        }
    }

    // MARK: - Check

    @Test func upToDateAndNewer() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.12")
        #expect(try await box.status().state == .upToDate)
        try box.install(version: "0.1.11")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "0.1.12")
        let binary = box.userBin.appendingPathComponent("lorca").path
        #expect(status.oneClick == CLIToolCommand(executable: binary, arguments: ["update"], pathPrefix: nil))
        #expect(box.downloadCount == 0, "a check never downloads an archive")
    }

    @Test func aReleaseBeforeLorcaUpdateIsOnlyReported() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.10")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
    }

    @Test func autoUpdateOffIsReportedWithTheCommand() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11")
        try box.settings(#"{"auto_update": false}"#)
        let status = try await box.status()
        #expect(status.withheld == .autoUpdateOff)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand?.arguments == ["update"])
    }

    @Test func aKnownDifferentFileIsUnverified() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", publish: false)
        box.publish("0.1.11", "the real build")
        _ = await box.verifier().publishedDigest(version: "0.1.11", target: "macos-aarch64")
        let status = try await box.status()
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)
    }

    @Test func anUnreadableManifestSaysSo() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11")
        let install = try #require(box.scanner.scan().first)
        let status = await box.check(fails: true).status(of: install, busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .channelUnreadable)
    }

    // MARK: - Update

    @Test func updatesInPlaceAndChecksTheResult() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", update: try box.updateBody(to: "0.1.12"))
        let status = try await box.status()
        let outcome = await box.updater().update(status)
        #expect(outcome == .updated(version: "0.1.12"))
        #expect(box.read("ARGS")?.trimmingCharacters(in: .whitespacesAndNewlines) == "update")
        let environment = box.read("ENV") ?? ""
        #expect(!environment.contains("LORCA_DOWNLOAD_URL"))
        #expect(!environment.contains("LORCA_HOME"))
        #expect(environment.contains("KEEP=1"))
        #expect(environment.contains("HOME=\(box.home.path)\n"))
    }

    /// `lorca update` handed to a running `lorca serve` exits at once; the file
    /// changes a moment later.
    ///
    /// Mutation: skip the wait (the outcome then reads "is still lorca 0.1.11").
    @Test func waitsForLorcaServeToPutTheFileInPlace() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", update: try box.updateBody(to: "0.1.12", served: true, delay: 0.4))
        let status = try await box.status()
        let outcome = await box.updater().update(status)
        #expect(outcome == .updated(version: "0.1.12"))
    }

    /// The swap waits for the test, not for a set time: with a 30 s delay it
    /// read as `.updated` on a hosted-runner push run (38024970744, the test
    /// taking 74 s), and holding every `.medium` pool thread past a scaled-down
    /// delay reproduces that locally — the settle loop wakes after the swap.
    /// (That CI starves the pool the same way is inferred, not instrumented.)
    /// Held, nothing but `settle` running out can end the wait.
    /// Mutation: drop `clock.now < end` from the settle loop (the swap then
    /// comes after ~300 s and the outcome reads `.updated`).
    @Test func aServeThatNeverSwapsIsAFailure() async throws {
        let box = try Sandbox()
        let hold = box.root.appendingPathComponent("hold")
        FileManager.default.createFile(atPath: hold.path, contents: nil)
        try box.install(version: "0.1.11", update: try box.updateBody(to: "0.1.12", served: true, held: hold))
        let status = try await box.status()
        let outcome = await box.updater(settle: .milliseconds(300)).update(status)
        try FileManager.default.removeItem(at: hold)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.contains("is still lorca 0.1.11"))
    }

    @Test func notRunWhenTheFileIsNotThePublishedBuild() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", update: try box.updateBody(to: "0.1.12"))
        let status = try await box.status()
        let outcome = await box.updater(tamper: true).update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.hasPrefix("not run:"))
        #expect(box.read("ARGS") == nil)
    }

    @Test func notRunTowardANotNewerVersionOrWhileBusy() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", update: try box.updateBody(to: "0.1.12"))
        let status = try await box.status()
        guard case .failed = await box.updater(latest: "0.1.11").update(status) else {
            Issue.record("ran toward 0.1.11"); return
        }
        #expect(await box.updater(busy: { .update(42) }).update(status) == .busy("lorca update is running (pid 42)"))
        #expect(box.read("ARGS") == nil)
    }

    @Test func aResultThatIsNotPublishedIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", update: try box.updateBody(to: "0.1.12"))
        let status = try await box.status()
        box.publish("0.1.12", "another build")
        guard case .failed(let message, _) = await box.updater().update(status) else {
            Issue.record("accepted an unpublished result"); return
        }
        #expect(message.hasPrefix("lorca update finished"))
    }

    // MARK: - The Mac app's lorca serve

    /// With the Mac app's `lorca serve` on the default port, the click names a
    /// free port, where nothing answers, so `lorca update` installs here.
    ///
    /// Mutation: ignore `appServe` in the check (the arguments are then plain
    /// `update`); drop the listening re-check in the updater.
    @Test func updatesPastTheMacAppsServe() async throws {
        let box = try Sandbox()
        try box.install(version: "0.1.11", update: try box.updateBody(to: "0.1.12"))
        let status = try await box.status(appServe: 99)
        #expect(status.oneClick?.arguments == ["--port", "50123", "update"])
        guard case .failed(let message, _) = await box.updater(listening: [50123]).update(status) else {
            Issue.record("ran with something on the port"); return
        }
        #expect(message == "not run: something now listens on port 50123")
        #expect(box.read("ARGS") == nil)
        #expect(await box.updater().update(status) == .updated(version: "0.1.12"))
        #expect(box.read("ARGS")?.trimmingCharacters(in: .whitespacesAndNewlines) == "--port 50123 update")
    }

    @Test func findsTheMacAppsServeOnTheDefaultPort() {
        func process(_ arguments: [String]) -> ClaudeCodeActivity.Process {
            ClaudeCodeActivity.Process(pid: 9, arguments: arguments)
        }
        let app = "/Applications/Lorca.app/Contents/Resources/bin/lorca"
        #expect(LorcaActivity.appServe(processes: [process(
            [app, "serve", "--port", "4862", "--parent-pid", "1", "--ready-stdout"])]) == 9)
        #expect(LorcaActivity.appServe(processes: [process([app, "--port", "4862", "serve"])]) == 9)
        #expect(LorcaActivity.appServe(processes: [process([app, "serve"])]) == 9)
        #expect(LorcaActivity.appServe(processes: [process([app, "serve", "--port", "5000"])]) == nil)
        #expect(LorcaActivity.appServe(processes: [process(["/Users/ann/.local/bin/lorca", "serve"])]) == nil)
        #expect(LorcaActivity.appServe(processes: [process([app, "status"])]) == nil)
    }

    /// The free port the kernel hands out has nothing on it.
    @Test func aFreeLoopbackPortIsNotListenedOn() throws {
        let port = try #require(LorcaCheck.freeLoopbackPort())
        #expect(port > 0)
        #expect(!LorcaCheck.isListening(port))
    }

    // MARK: - Activity

    @Test func busyIsAnInstallingUpdateOrAnInstallerDownload() {
        func process(_ arguments: [String]) -> ClaudeCodeActivity.Process {
            ClaudeCodeActivity.Process(pid: 7, arguments: arguments)
        }
        #expect(LorcaActivity.busy(processes: [process(["/Users/ann/.local/bin/lorca", "update"])]) == .update(7))
        #expect(LorcaActivity.busy(processes: [process(["lorca", "update", "--check"])]) == nil)
        #expect(LorcaActivity.busy(processes: [process(["lorca", "update", "--auto", "off"])]) == nil)
        #expect(LorcaActivity.busy(processes: [process(["lorca", "serve"])]) == nil)
        #expect(LorcaActivity.busy(processes: [process(["lorca", "--port", "50123", "update"])]) == .update(7))
        #expect(LorcaActivity.busy(processes: [process(["lorca", "--home", "/x", "update", "--check"])]) == nil)
        #expect(LorcaActivity.busy(processes: [process(
            ["curl", "-fL", "-o", "/tmp/x", "https://github.com/egoist/lorca/releases/latest/download/lorca-cli-macos-aarch64.tar.gz"])])
            == .download(7))
        #expect(LorcaActivity.busy(processes: [process(
            ["curl", "https://github.com/egoist/lorca/releases/download/desktop-v0.1.5/Lorca.AppImage"])]) == nil)
    }

    /// `lorca-cli.json` of cli-v0.1.11, byte for byte, base64.
    static let published0111 = "ewogICJraW5kIjogImxvcmNhLWNsaSIsCiAgInZlcnNpb24iOiAiMC4xLjExIiwKICAiYnVpbGRzIjogewogICAgImxpbnV4LWFhcmNoNjQiOiB7CiAgICAgICJmaWxlIjogImxvcmNhLWNsaS1saW51eC1hYXJjaDY0LnRhci5neiIsCiAgICAgICJzaGEyNTYiOiAiMjk4Yjc1ZjA0MGViNDE0YmNhZTkxYmE0YmQ0MTNjMjYxYmEyODE2NTYxMDZiM2Y0MGM3ZTQzYmU5MThiY2Y1NSIsCiAgICAgICJzaXplIjogMTY1MjM5MDYKICAgIH0sCiAgICAibGludXgteDg2XzY0IjogewogICAgICAiZmlsZSI6ICJsb3JjYS1jbGktbGludXgteDg2XzY0LnRhci5neiIsCiAgICAgICJzaGEyNTYiOiAiNTUzOWYwMzVlYzUyODUzNjNiNzg1NDFmNTFiOWU4NDVmOGRmMWJhMjUyYTk1NmE3MjA3OGMyZGZlZGViODUzMCIsCiAgICAgICJzaXplIjogMTc2NTQ3OTgKICAgIH0sCiAgICAibWFjb3MtYWFyY2g2NCI6IHsKICAgICAgImZpbGUiOiAibG9yY2EtY2xpLW1hY29zLWFhcmNoNjQudGFyLmd6IiwKICAgICAgInNoYTI1NiI6ICJiOGUyZWU3ZjkwODcxOTRjOGM3NDJlYWU3ZjhlMmI2MDQ5ZWRjOTQwNTRlYzY4Mzc5OTk0OTZmOTU5MjJmZTQ1IiwKICAgICAgInNpemUiOiAxNzc4ODAyMQogICAgfSwKICAgICJ3aW5kb3dzLXg4Nl82NCI6IHsKICAgICAgImZpbGUiOiAibG9yY2EtY2xpLXdpbmRvd3MteDg2XzY0LnppcCIsCiAgICAgICJzaGEyNTYiOiAiYjIxM2RlOWU4YmY4ZjJlNTE1YTQ5MjgzNGExNjkxOTdlNmM1ZDVmZjdmMDY2NTE3OTk0NDAwNmI2M2VjZGFhNCIsCiAgICAgICJzaXplIjogMjE2MzgxMjkKICAgIH0KICB9Cn0K"
}
