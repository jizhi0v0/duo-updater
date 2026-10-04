import Testing
import Foundation
@testable import DuoUpdaterCore

/// A standalone Codex built out of plain files in a temporary directory, laid out
/// the way `install.sh` lays it out (`rust-v0.160.0`, 2026-10-04). Shared by the
/// Codex suites.
final class CodexSandbox {
    let root: URL
    var home: URL { root.appendingPathComponent("home") }
    var standalone: URL { home.appendingPathComponent(".codex/packages/standalone") }
    var launcher: URL { home.appendingPathComponent(".local/bin/codex") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    /// The binary's text is what the injected signature check reads.
    var scanner: CodexScanner {
        CodexScanner(
            home: home,
            checkSignature: { url in
                switch (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "openai": return .vendor
                case "adhoc": return .adHoc
                default: return .otherSigner
                }
            },
            isQuarantined: { url in
                FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("QUARANTINED").path)
            })
    }

    @discardableResult
    func write(_ url: URL, _ text: String, executable: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        return url
    }

    func link(_ link: URL, to destination: String) throws {
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: destination)
    }

    /// `releases/<version>-<target>` in the package layout.
    func release(
        _ version: String, target: String = "aarch64-apple-darwin", packageVersion: String? = nil,
        signer: String = "openai", legacy: Bool = false
    ) throws {
        let dir = standalone.appendingPathComponent("releases/\(version)-\(target)")
        if legacy {
            try write(dir.appendingPathComponent("codex"), signer, executable: true)
            return
        }
        try write(dir.appendingPathComponent("bin/codex"), signer, executable: true)
        try write(dir.appendingPathComponent("bin/codex-code-mode-host"), signer, executable: true)
        try write(dir.appendingPathComponent("codex-path/rg"), "rg", executable: true)
        try link(dir.appendingPathComponent("codex"), to: "bin/codex")
        try write(dir.appendingPathComponent("codex-package.json"), """
            {"layoutVersion":1,"version":"\(packageVersion ?? version)","target":"\(target)","variant":"codex",\
            "entrypoint":"bin/codex","resourcesDir":"codex-resources","pathDir":"codex-path"}
            """)
    }

    /// A release, `current` pointing at it, and the launcher — absolute links, as
    /// the installer writes them.
    func install(_ version: String, target: String = "aarch64-apple-darwin", signer: String = "openai") throws {
        try release(version, target: target, signer: signer)
        try link(standalone.appendingPathComponent("current"),
                 to: standalone.appendingPathComponent("releases/\(version)-\(target)").path)
        try link(launcher, to: standalone.appendingPathComponent("current/bin/codex").path)
        try write(standalone.appendingPathComponent("install.lock"), "")
    }
}

@Suite struct CodexTests {

    static func check(_ latest: String = "0.160.0") -> CodexCheck {
        CodexCheck(latest: { _ in latest })
    }

    static func status(
        _ box: CodexSandbox, latest: String = "0.160.0", settings: CodexSettings = CodexSettings(),
        busy: CodexActivity.Busy? = nil
    ) async throws -> CLIToolStatus {
        let install = try #require(box.scanner.scan().first.map(box.scanner.withSignature))
        return await check(latest).status(of: install, settings: settings, busy: busy)
    }

    // MARK: - Scanner

    @Test func readsTheReleaseCurrentNamesWithoutRunningIt() throws {
        let box = try CodexSandbox()
        try box.release("0.142.4")
        try box.install("0.143.0")
        let install = try #require(box.scanner.scan().first)
        #expect(install.path == box.launcher.path)
        #expect(install.root == box.standalone.path)
        #expect(install.version == "0.143.0")
        #expect(install.target == "aarch64-apple-darwin")
        #expect(install.binary == box.standalone.appendingPathComponent("releases/0.143.0-aarch64-apple-darwin/bin/codex").path)
        #expect(install.problem == nil)
        // Measured by the check, not the scan.
        #expect(install.signature == nil)
        #expect(box.scanner.withSignature(install).signature == .vendor)
    }

    @Test func nothingWithoutAStandaloneRoot() throws {
        let box = try CodexSandbox()
        // An npm or Homebrew codex on the launcher's place is not this install.
        try box.write(box.launcher, "#!/usr/bin/env node", executable: true)
        #expect(box.scanner.scan().isEmpty)
    }

    /// Mutations: accept a `current` that is not a link; read the version from
    /// `codex-package.json` instead of the directory; drop the launcher check.
    @Test func brokenLayoutsAreProblems() throws {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        // The package file disagrees with the directory.
        try box.release("0.143.0", packageVersion: "0.150.0")
        #expect(box.scanner.scan().first?.problem == .packageMismatch)
        try box.release("0.143.0", target: "x86_64-apple-darwin")
        try box.link(box.standalone.appendingPathComponent("current"),
                     to: box.standalone.appendingPathComponent("releases/0.143.0-x86_64-apple-darwin").path)
        // The launcher names `current`, not a release: a swap keeps it valid.
        #expect(box.scanner.scan().first?.target == "x86_64-apple-darwin")
        #expect(box.scanner.scan().first?.problem == nil)

        let other = try CodexSandbox()
        try other.install("0.143.0")
        try other.link(other.standalone.appendingPathComponent("current"), to: "/nowhere/garbage")
        #expect(other.scanner.scan().first?.problem == .versionUnreadable)
        try FileManager.default.removeItem(at: other.standalone.appendingPathComponent("current"))
        try other.write(other.standalone.appendingPathComponent("current"), "not a link")
        #expect(other.scanner.scan().first?.problem == .noCurrent)

        let empty = try CodexSandbox()
        try empty.install("0.143.0")
        try FileManager.default.removeItem(
            at: empty.standalone.appendingPathComponent("releases/0.143.0-aarch64-apple-darwin/bin/codex"))
        #expect(empty.scanner.scan().first?.problem == .binaryMissing)

        let moved = try CodexSandbox()
        try moved.install("0.143.0")
        try moved.link(moved.launcher, to: "/opt/homebrew/bin/codex")
        #expect(moved.scanner.scan().first?.problem == .launcherElsewhere)
    }

    @Test func readsTheLegacyLayout() throws {
        let box = try CodexSandbox()
        try box.release("0.120.0", legacy: true)
        try box.link(box.standalone.appendingPathComponent("current"),
                     to: box.standalone.appendingPathComponent("releases/0.120.0-aarch64-apple-darwin").path)
        try box.link(box.launcher, to: box.standalone.appendingPathComponent("current/codex").path)
        let install = try #require(box.scanner.scan().first)
        #expect(install.version == "0.120.0")
        #expect(install.problem == nil)
        #expect(install.binary?.hasSuffix("0.120.0-aarch64-apple-darwin/codex") == true)
    }

    @Test func releaseNames() {
        #expect(CodexScanner.release("0.143.0-aarch64-apple-darwin")! == ("0.143.0", "aarch64-apple-darwin"))
        #expect(CodexScanner.release("0.162.0-alpha.12-x86_64-apple-darwin")! == ("0.162.0-alpha.12", "x86_64-apple-darwin"))
        #expect(CodexScanner.release("0.143.0-aarch64-unknown-linux-musl") == nil)
        #expect(CodexScanner.release("garbage-aarch64-apple-darwin") == nil)
        #expect(CodexScanner.release("0.143.0") == nil)
    }

    // MARK: - Settings

    /// Mutations: read the key under a table; treat anything but `false` as off.
    @Test func settingsReadTheTopLevelKeyOnly() {
        #expect(CodexSettings.parse("").checkForUpdates)
        #expect(!CodexSettings.parse("model = \"o3\"\ncheck_for_update_on_startup = false # managed\n").checkForUpdates)
        #expect(!CodexSettings.parse("  check_for_update_on_startup=false").checkForUpdates)
        #expect(CodexSettings.parse("check_for_update_on_startup = true").checkForUpdates)
        #expect(CodexSettings.parse("[tui]\ncheck_for_update_on_startup = false").checkForUpdates)
        #expect(CodexSettings.parse("[projects.\"/x\"]\ntrust_level = \"trusted\"\ncheck_for_update_on_startup = false")
            .checkForUpdates)
        #expect(CodexSettings.parse("check_for_update_on_startup = \"false\"").checkForUpdates)
    }

    @Test func settingsFileUnderHome() throws {
        let box = try CodexSandbox()
        #expect(CodexSettings.read(home: box.home).checkForUpdates)
        try box.write(box.home.appendingPathComponent(".codex/config.toml"), "check_for_update_on_startup = false\n")
        #expect(!CodexSettings.read(home: box.home).checkForUpdates)
    }

    // MARK: - Release

    /// The channel answer as releases.openai.com gives it (2026-10-04), cut to the
    /// assets that matter.
    static func channel(tag: String = "rust-v0.160.0", targets: [String] = ["aarch64-apple-darwin", "x86_64-apple-darwin"]) -> Data {
        var assets: [[String: String]] = [
            ["name": "codex-package_SHA256SUMS", "digest": "sha256:" + String(repeating: "a", count: 64)],
            ["name": "bwrap", "digest": "sha256:" + String(repeating: "b", count: 64)],
        ]
        for target in targets {
            assets.append(["name": "codex-package-\(target).tar.gz", "digest": "sha256:" + String(repeating: "c", count: 64)])
        }
        return try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "assets": assets])
    }

    @Test func latestIsTheChannelsTag() async throws {
        let release = CodexRelease(fetch: { url in
            #expect(url == CodexRelease.channel)
            return (Self.channel(), 200)
        })
        #expect(try await release.latest(target: "aarch64-apple-darwin") == "0.160.0")
        await #expect(throws: CodexRelease.Failure.noPackage("aarch64-apple-darwin")) {
            try await CodexRelease(fetch: { _ in (Self.channel(targets: ["x86_64-apple-darwin"]), 200) })
                .latest(target: "aarch64-apple-darwin")
        }
        await #expect(throws: CodexRelease.Failure.http(503)) {
            try await CodexRelease(fetch: { _ in (Data(), 503) }).latest(target: "aarch64-apple-darwin")
        }
        await #expect(throws: CodexRelease.Failure.unreadable) {
            try await CodexRelease(fetch: { _ in (Self.channel(tag: "v0.160.0"), 200) }).latest(target: "aarch64-apple-darwin")
        }
        await #expect(throws: CodexRelease.Failure.unreadable) {
            try await CodexRelease(fetch: { _ in (Self.channel(tag: "rust-v0.160.0;rm"), 200) })
                .latest(target: "aarch64-apple-darwin")
        }
    }

    /// Mutations: compare strings; order alpha after the release; accept
    /// `-rc.1`, which the installer rejects.
    @Test func versionsOrderLikeTheInstallerNamesThem() {
        let ordered = [
            "0.99.0", "0.143.0", "0.160.0-alpha", "0.160.0-alpha.6", "0.160.0-alpha.6.1", "0.160.0-alpha.6.2",
            "0.160.0-alpha.10", "0.160.0-beta", "0.160.0-beta.2", "0.160.0", "0.160.1", "0.161.0-alpha.1", "1.0.0",
        ]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            #expect(CodexRelease.compare(a, b) == .orderedAscending, "\(a) < \(b)")
            #expect(CodexRelease.compare(b, a) == .orderedDescending, "\(b) > \(a)")
        }
        #expect(CodexRelease.compare("0.160.0", "0.160.0") == .orderedSame)
        #expect(CodexRelease.compare("garbage", "0.1.0") == .orderedAscending)
        #expect(!CodexRelease.isVersion("0.160.0-rc.1"))
        #expect(!CodexRelease.isVersion("0.160"))
        #expect(!CodexRelease.isVersion("0.160.0-alpha.1.2.3"))
        #expect(!CodexRelease.isVersion("0.160.0-beta.1.2"))
        #expect(CodexRelease.isVersion("0.159.0-alpha.12.1"))
    }

    // MARK: - Check

    @Test func outdatedSignedInstallIsOfferedTheInstaller() async throws {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        let status = try await Self.status(box)
        #expect(status.kind == .codex)
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "0.143.0")
        #expect(status.latestVersion == "0.160.0")
        #expect(status.channel == "latest")
        #expect(status.withheld == nil)
        let command = try #require(status.oneClick)
        #expect(command.display == "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh")
        #expect(command.pathPrefix == box.home.path + "/.local/bin")
    }

    /// Mutations: offer a click to `.ahead`; compare with the shared comparator,
    /// which puts `-alpha` above the release.
    @Test func neverOfferedTowardAnOlderOrSameVersion() async throws {
        let box = try CodexSandbox()
        try box.install("0.160.0")
        #expect(try await Self.status(box).state == .upToDate)
        let alpha = try CodexSandbox()
        try alpha.install("0.162.0-alpha.12")
        let ahead = try await Self.status(alpha)
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
        let beforeRelease = try CodexSandbox()
        try beforeRelease.install("0.160.0-alpha.6")
        #expect(try await Self.status(beforeRelease).state == .updateAvailable)
    }

    /// Mutations: drop any one gate.
    @Test func gatesWithholdTheClick() async throws {
        let unsigned = try CodexSandbox()
        try unsigned.install("0.143.0", signer: "adhoc")
        let wrong = try await Self.status(unsigned)
        #expect(wrong.withheld == .wrongSigner)
        #expect(wrong.oneClick == nil)
        #expect(wrong.note?.contains("2DC432GLL2") == true)

        let quarantined = try CodexSandbox()
        try quarantined.install("0.143.0")
        try quarantined.write(quarantined.standalone.appendingPathComponent("releases/0.143.0-aarch64-apple-darwin/bin/QUARANTINED"), "")
        #expect(try await Self.status(quarantined).withheld == .unverified)

        let box = try CodexSandbox()
        try box.install("0.143.0")
        let off = try await Self.status(box, settings: CodexSettings(checkForUpdates: false))
        #expect(off.withheld == .autoUpdateOff)
        #expect(off.oneClick == nil)
        #expect(off.manualCommand?.display == "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh")

        let busy = try await Self.status(box, busy: .installer(nil))
        #expect(busy.withheld == .busy)
        #expect(busy.oneClick == nil)

        let moved = try CodexSandbox()
        try moved.install("0.143.0")
        try moved.link(moved.launcher, to: "/opt/homebrew/bin/codex")
        let elsewhere = try await Self.status(moved)
        #expect(elsewhere.state == .updateAvailable)
        #expect(elsewhere.withheld == .unsupportedInstaller)
        // Up to date is still up to date, whatever the launcher.
        #expect(try await Self.status(moved, latest: "0.143.0").state == .upToDate)
    }

    @Test func brokenAndUnreadable() async throws {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        try box.release("0.143.0", packageVersion: "0.150.0")
        #expect(try await Self.status(box).withheld == .versionMismatch)

        let ok = try CodexSandbox()
        try ok.install("0.143.0")
        let install = try #require(ok.scanner.scan().first.map(ok.scanner.withSignature))
        let status = await CodexCheck(latest: { _ in throw CodexRelease.Failure.http(502) })
            .status(of: install, settings: CodexSettings(), busy: nil)
        #expect(status.state == .unknown)
        #expect(status.withheld == .channelUnreadable)
    }

    // MARK: - Activity

    /// An `flock(2)` lock — what `lockf <fd>` takes — on another descriptor of the
    /// file, so the probe meets it as it would meet the installer's. Mutations:
    /// drop the `flock` probe; report a lock on a missing file; leave the probe's
    /// own lock held.
    @Test func anFlockOnTheInstallLockIsBusy() throws {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        let lock = box.standalone.appendingPathComponent("install.lock")
        #expect(CodexActivity.busy(root: box.standalone) == nil)
        // Free again: the probe released what it took.
        #expect(CodexActivity.busy(root: box.standalone) == nil)
        let fd = open(lock.path, O_RDWR)
        #expect(fd >= 0)
        defer { close(fd) }
        #expect(lockFile(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(CodexActivity.busy(root: box.standalone) == .installer(nil))
        // The probe itself, apart from `F_GETLK` (which on some systems sees it too).
        let probe = open(lock.path, O_RDONLY)
        defer { close(probe) }
        #expect(CodexActivity.isFlocked(probe))
        #expect(lockFile(fd, LOCK_UN) == 0)
        #expect(!CodexActivity.isFlocked(probe))
        #expect(CodexActivity.busy(root: box.standalone) == nil)
        try FileManager.default.removeItem(at: lock)
        #expect(CodexActivity.busy(root: box.standalone) == nil)
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }

    /// The installer's own lock, taken the installer's way (`exec 9<>…; lockf 9`).
    /// The holder `exec`s into `sleep`, so one process has the descriptor and the
    /// lock goes with it; `ready` carries `lockf`'s exit status.
    @Test func theInstallersLockfIsBusy() async throws {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        let lock = box.standalone.appendingPathComponent("install.lock").path
        let ready = box.root.appendingPathComponent("ready")
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/bin/sh")
        holder.arguments = ["-c", "exec 9<>\"$1\"; lockf 9; echo $? > \"$2\"; exec sleep 60", "sh", lock, ready.path]
        try holder.run()
        defer { if holder.isRunning { holder.terminate() } }
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(50))
        let status = (try? String(contentsOf: ready, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        try #require(status == "0", "lockf 9 exited \(status ?? "never")")
        #expect(CodexActivity.busy(root: box.standalone) == .installer(nil))
        holder.terminate()
        holder.waitUntilExit()
        #expect(CodexActivity.busy(root: box.standalone) == nil)
    }

    @Test func theMkdirLockNamesItsPid() throws {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        let dir = box.standalone.appendingPathComponent("install.lock.d")
        try box.write(dir.appendingPathComponent("pid"), "4242\n")
        #expect(CodexActivity.busy(root: box.standalone, isAlive: { $0 == 4242 }) == .installer(4242))
        #expect(CodexActivity.busy(root: box.standalone, isAlive: { _ in false }) == nil)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("pid"))
        #expect(CodexActivity.busy(root: box.standalone, isAlive: { _ in false }) == .installer(nil))
    }

    // MARK: - Provider

    @Test func reportCarriesSettingsAndSightings() async throws {
        let box = try CodexSandbox()
        try box.install("0.143.0")
        let installs = box.scanner.scan().map(box.scanner.withSignature)
        let report = await CodexProvider.report(
            installs: installs, settings: CodexSettings(checkForUpdates: false), busy: nil, check: Self.check())
        #expect(report.kind == .codex)
        #expect(report.context == .codex(CodexSettings(checkForUpdates: false)))
        #expect(report.sightings == [CLIToolSighting(
            kind: .codex, path: box.launcher.path, version: "0.143.0", state: "aarch64-apple-darwin|-|-")])
        #expect(report.statuses.first?.withheld == .autoUpdateOff)
    }
}
