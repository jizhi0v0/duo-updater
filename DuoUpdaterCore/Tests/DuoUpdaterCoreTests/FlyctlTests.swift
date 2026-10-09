import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// flyctl: finding it where its installer puts it, its verdict, the archive check
/// the trust rule rests on, its one-click update and its release notes.
///
/// "flyctl" here is a `#!/bin/sh` script under a fixture home, carrying the Go
/// build setting every real build carries (`-X …/buildinfo.buildVersion=<v>`,
/// measured 2026-10-09 on 0.4.0 to 0.4.115). Its `version upgrade` does what the
/// installer does to the disk — writes a new file and `mv`s it over. The
/// endpoint, the release downloads and their unpacking are injected: nothing here
/// reads the host's process table, runs a flyctl build or reaches the network.
@Suite struct FlyctlTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var fly: URL { home.appendingPathComponent(".fly") }
        var bin: URL { fly.appendingPathComponent("bin") }
        var binary: URL { bin.appendingPathComponent("flyctl") }
        let digests: FlyctlPublishedDigests
        private let lock = NSLock()
        private var published: [String: String] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-flyctl-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = FlyctlPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func script(version: String, upgrade: String = "exit 0") -> String {
            """
            #!/bin/sh
            # build -ldflags="-X github.com/superfly/flyctl/internal/buildinfo.buildDate=2026-10-07T08:46:21Z -X github.com/superfly/flyctl/internal/buildinfo.buildVersion=\(version) -X x.commit=abc"
            if [ "$1" = version ] && [ "$2" = upgrade ]; then
            \(upgrade)
            fi
            """
        }

        @discardableResult
        func install(version: String, upgrade: String = "exit 0", publish: Bool = true) throws -> URL {
            let text = Self.script(version: version, upgrade: upgrade)
            try Data(text.utf8).write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
            if publish { self.publish(version, text) }
            return binary
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        var downloadCount: Int { lock.withLock { downloads } }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }
        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }

        /// What the installer does: a new file in `tmp`, `mv`d over the old one.
        func upgradeBody(to version: String, publishNew: Bool = true) throws -> String {
            let next = Self.script(version: version)
            if publishNew { publish(version, next) }
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            return """
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$PATH" > "\(root.path)/PATHLS"
                /bin/mkdir -p "$FLYCTL_INSTALL/tmp"
                /bin/cp "\(staged.path)" "$FLYCTL_INSTALL/tmp/flyctl" && /bin/chmod 755 "$FLYCTL_INSTALL/tmp/flyctl"
                /bin/mv "$FLYCTL_INSTALL/tmp/flyctl" "$FLYCTL_INSTALL/bin/flyctl"
                echo "Upgraded flyctl"
                """
        }

        var scanner: FlyctlScanner { FlyctlScanner(home: home, isQuarantined: { _ in false }, readTarget: { _ in "arm64" }) }

        static func archive(_ version: String) -> Data { Data("tgz-\(version)".utf8) }

        func verifier(tamper: Bool = false) -> FlyctlVerifier {
            FlyctlVerifier(
                download: { url in
                    let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                    guard self.lock.withLock({ self.published[version] }) != nil else { throw FlyctlRelease.Failure.http(404) }
                    if url.pathExtension == "txt" {
                        let hex = SHA256.hash(data: Self.archive(version)).map { String(format: "%02x", $0) }.joined()
                        let other = String(repeating: "0", count: 64)
                        return Data("\(other)  flyctl_\(version)_Linux_arm64.tar.gz\n\(hex)  flyctl_\(version)_macOS_arm64.tar.gz\n".utf8)
                    }
                    self.lock.withLock { self.downloads += 1 }
                    return tamper ? Data("other".utf8) : Self.archive(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self).replacingOccurrences(of: "tgz-", with: "")
                    let text = self.lock.withLock { self.published[version] } ?? ""
                    try Data(text.utf8).write(to: directory.appendingPathComponent("flyctl"))
                },
                digests: digests)
        }

        func check(latest: String = "0.4.115", fails: Bool = false) -> FlyctlCheck {
            let verifier = verifier()
            return FlyctlCheck(latest: { target in
                if fails { throw FlyctlRelease.Failure.http(503) }
                #expect(target == "arm64")
                return latest
            }, knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
        }

        func updater(latest: String = "0.4.115", busy: @escaping FlyctlUpdater.BusyCheck = { nil }) -> FlyctlUpdater {
            FlyctlUpdater(busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(),
                          environment: { ["FLYCTL_INSTALL": "/elsewhere", "SHELL": "/bin/zsh", "KEEP": "1"] })
        }

        func status(latest: String = "0.4.115", busy: FlyctlActivity.Busy? = nil) async throws -> CLIToolStatus {
            await check(latest: latest).status(of: try #require(scanner.scan().first), busy: busy)
        }
    }

    // MARK: - Finding it

    /// The build version, read from the bytes; disagreeing builds are unreadable.
    /// Mutation: accept the first `buildVersion=` only.
    @Test func readsTheBuildVersion() throws {
        let box = try Sandbox()
        try box.install(version: "0.4.114")
        let install = try #require(box.scanner.scan().first)
        #expect(install.version == "0.4.114")
        #expect(install.problem == nil)
        #expect(install.channel == nil)
        #expect(install.autoUpdate)

        func windows(_ text: String) -> [Data] {
            text.components(separatedBy: "internal/buildinfo.buildVersion=").dropFirst()
                .map { Data(("internal/buildinfo.buildVersion=" + $0).utf8) }
        }
        #expect(FlyctlScanner.buildVersion(in: windows("x internal/buildinfo.buildVersion=0.4.115 -X y")) == "0.4.115")
        #expect(FlyctlScanner.buildVersion(in: windows(
            "internal/buildinfo.buildVersion=0.4.115 internal/buildinfo.buildVersion=0.4.114")) == nil)
        #expect(FlyctlScanner.buildVersion(in: windows("internal/buildinfo.buildVersion=../x")) == nil)
    }

    /// `~/.fly/state.yml`'s channel and `~/.fly/config.yml`'s `auto_update`.
    @Test func readsChannelAndAutoUpdate() throws {
        let box = try Sandbox()
        try box.install(version: "0.4.114")
        try Data("channel: shell\ninvalidver: null\n".utf8).write(to: box.fly.appendingPathComponent("state.yml"))
        try Data("access_token: x\nauto_update: false\n".utf8).write(to: box.fly.appendingPathComponent("config.yml"))
        let install = try #require(box.scanner.scan().first)
        #expect(install.channel == "shell")
        #expect(!install.followsPrerelease)
        #expect(!install.autoUpdate)
        #expect(FlyctlInstall(path: "p", version: "1.0.0", channel: "pre").followsPrerelease)
        #expect(!FlyctlInstall(path: "p", version: "1.0.0", channel: "shell-prerel").followsPrerelease)
    }

    /// A link out of `~/.fly` is reported; Homebrew's is not ours; dangling is broken.
    /// Mutation: drop the under-`~/.fly` test.
    @Test func linksAreClassified() throws {
        let box = try Sandbox()
        let elsewhere = box.root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let loose = elsewhere.appendingPathComponent("flyctl")
        try Data(Sandbox.script(version: "0.4.114").utf8).write(to: loose)
        try FileManager.default.createSymbolicLink(atPath: box.binary.path, withDestinationPath: loose.path)
        #expect(box.scanner.scan().first?.problem == .unknownLocation)

        try FileManager.default.removeItem(at: box.binary)
        let cellar = box.root.appendingPathComponent("opt/homebrew/Cellar/flyctl/0.4.115/bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try Data(Sandbox.script(version: "0.4.115").utf8).write(to: cellar.appendingPathComponent("flyctl"))
        try FileManager.default.createSymbolicLink(atPath: box.binary.path, withDestinationPath: cellar.appendingPathComponent("flyctl").path)
        #expect(box.scanner.scan().isEmpty)

        try FileManager.default.removeItem(at: cellar.appendingPathComponent("flyctl"))
        #expect(box.scanner.scan().first?.problem == .executableMissing)
    }

    // MARK: - The verdict

    @Test func offersVersionUpgrade() async throws {
        let box = try Sandbox()
        let binary = try box.install(version: "0.4.114")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "0.4.115")
        #expect(status.oneClick == CLIToolCommand(executable: binary.path, arguments: ["version", "upgrade"], pathPrefix: nil))
        #expect(box.downloadCount == 0)
        try box.install(version: "0.4.115")
        #expect(try await box.status().state == .upToDate)
    }

    /// Mutations: drop any one gate.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "0.4.114")
        #expect(try await box.status(busy: .upgrade(4)).withheld == .busy)
        #expect(await box.check(fails: true).status(of: try #require(box.scanner.scan().first), busy: nil)
            .withheld == .channelUnreadable)

        let path = box.binary.path
        let pre = await box.check().status(of: FlyctlInstall(path: path, binary: path, version: "0.4.114", channel: "pre"), busy: nil)
        #expect(pre.withheld == .unsupportedInstaller)
        #expect(pre.manualCommand?.arguments == ["version", "upgrade"])
        let off = await box.check().status(of: FlyctlInstall(path: path, binary: path, version: "0.4.114", autoUpdate: false), busy: nil)
        #expect(off.withheld == .autoUpdateOff)
        #expect(off.oneClick == nil)
        #expect(off.manualCommand?.arguments == ["version", "upgrade"])
        let quarantined = FlyctlInstall(path: path, binary: path, version: "0.4.114", quarantined: true)
        #expect(await box.check().status(of: quarantined, busy: nil).withheld == .unverified)
        let readOnly = FlyctlInstall(path: path, binary: path, version: "0.4.114", writable: false)
        #expect(await box.check().status(of: readOnly, busy: nil).withheld == .unsupportedInstaller)
        let linked = FlyctlInstall(path: path, binary: "/elsewhere/flyctl", version: "0.4.114", problem: .unknownLocation)
        let link = await box.check().status(of: linked, busy: nil)
        #expect(link.withheld == .unsupportedInstaller)
        #expect(link.manualCommand == nil)
    }

    /// Mutation: ignore the known digest.
    @Test func aKnownDigestThatDiffersIsWithheld() async throws {
        let box = try Sandbox()
        box.publish("0.4.114", Sandbox.script(version: "0.4.114"))
        try box.install(version: "0.4.114", upgrade: "echo altered", publish: false)
        _ = await box.verifier().verify(binary: box.binary.path, version: "0.4.114", target: "arm64")
        let status = try await box.status()
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)
    }

    // MARK: - The archive check

    /// The archive must match its line in `checksums.txt`; the digest is
    /// remembered. Mutations: skip the archive check; take the first line of the
    /// checksums file; never remember.
    @Test func verifiesAgainstTheReleaseArchive() async throws {
        let box = try Sandbox()
        let binary = try box.install(version: "0.4.114").path
        #expect(await box.verifier().verify(binary: binary, version: "0.4.114", target: "arm64") == .matches)
        #expect(await box.verifier().verify(binary: binary, version: "0.4.114", target: "arm64") == .matches)
        #expect(box.downloadCount == 1)
        box.publish("0.4.113", "x")
        let tampered = await box.verifier(tamper: true).verify(binary: binary, version: "0.4.113", target: "arm64")
        guard case .couldNotVerify = tampered else { Issue.record("expected couldNotVerify, got \(tampered)"); return }
        #expect(box.digests.digest(version: "0.4.113", target: "arm64") == nil)
        #expect(FlyctlRelease.archiveURL(version: "0.4.115", target: "arm64").absoluteString
            == "https://github.com/superfly/flyctl/releases/download/v0.4.115/flyctl_0.4.115_macOS_arm64.tar.gz")
    }

    /// The `latest` track's JSON; the arch as Go spells it.
    @Test func readsTheTrack() async throws {
        let ok = FlyctlRelease(fetch: { url in
            #expect(url.absoluteString == "https://api.fly.io/app/flyctl_releases/darwin/amd64/latest")
            return (Data(#"{"version":"v0.4.115","prerelease":false,"download_url":"x"}"#.utf8), 200)
        })
        #expect(try await ok.latest(target: "x86_64") == "0.4.115")
        let pre = FlyctlRelease(fetch: { _ in (Data(#"{"version":"v0.5.0-pre-1","prerelease":true}"#.utf8), 200) })
        await #expect(throws: FlyctlRelease.Failure.self) { try await pre.latest(target: "arm64") }
        let down = FlyctlRelease(fetch: { _ in (Data(), 404) })
        await #expect(throws: FlyctlRelease.Failure.http(404)) { try await down.latest(target: "arm64") }
    }

    // MARK: - The update

    /// `flyctl version upgrade` with `FLYCTL_INSTALL`, `SHELL`, `HOME` set and a
    /// PATH of the installer's programs and the install itself — no sudo, no
    /// brew. Mutations: leave the inherited `FLYCTL_INSTALL`; put sudo on PATH.
    @Test func updatesAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(version: "0.4.114", upgrade: try box.upgradeBody(to: "0.4.115"))
        let outcome = await box.updater().update(try await box.status())
        #expect(outcome == .updated(version: "0.4.115"))
        #expect(box.read("ARGS") == "version upgrade\n")
        let env = box.read("ENV") ?? ""
        #expect(env.contains("FLYCTL_INSTALL=\(box.fly.path)\n"))
        #expect(env.contains("SHELL=/bin/sh\n"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        #expect(env.contains("KEEP=1"))
        let path = (box.read("PATHLS") ?? "").split(separator: "\n")
        #expect(path.contains("flyctl") && path.contains("curl") && path.contains("sh"))
        #expect(!path.contains("sudo") && !path.contains("brew"))
        #expect(box.downloadCount == 2)
    }

    /// Mutation: report `.updated` without verifying the new file.
    @Test func anUnpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "0.4.114", upgrade: try box.upgradeBody(to: "0.4.115", publishNew: false))
        box.publish("0.4.115", "the real 0.4.115")
        guard case .failed(let message, _) = await box.updater().update(try await box.status()) else {
            Issue.record("an unpublished result read as updated"); return
        }
        #expect(message.contains("is not the flyctl 0.4.115 Fly.io published"))
    }

    /// Mutations: drop the busy re-check, the latest re-check, the trust check.
    @Test func gatesAreAskedAgainAtTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "0.4.114", upgrade: try box.upgradeBody(to: "0.4.115"))
        let status = try await box.status()
        #expect(await box.updater(busy: { .upgrade(7) }).update(status) == .busy("flyctl version upgrade is running (pid 7)"))
        guard case .failed(let moved, _) = await box.updater(latest: "0.4.114").update(status) else {
            Issue.record("ran on a track that moved back"); return
        }
        #expect(moved.hasPrefix("not run:"))
        box.publish("0.4.114", "not this file")
        guard case .failed(let message, _) = await box.updater().update(status) else { Issue.record("ran unverified"); return }
        #expect(message.hasPrefix("not run:"))
        #expect(!box.ran)
    }

    /// A failed upgrade's row line is flyctl's `Error:` with the exit status.
    @Test func failureLineCarriesTheReasonAndStatus() {
        let outcome = ChildProcess.Outcome(
            terminationStatus: 1, uncaughtSignal: false, timedOut: false, standardOutput: Data(), standardError: Data())
        #expect(FlyctlUpdater.failureMessage(
            ["Running automatic upgrade", "Error: cannot update this installation.", "the environment variable…"],
            outcome, deadline: FlyctlUpdater.defaultDeadline) == "cannot update this installation. (exit 1)")
        #expect(FlyctlUpdater.failureMessage(["curl: (6) Could not resolve host: fly.io"], outcome,
                                             deadline: FlyctlUpdater.defaultDeadline)
            == "curl: (6) Could not resolve host: fly.io (exit 1)")
    }

    // MARK: - Busy

    @Test func busyIsAnUpgradeOrADownload() {
        #expect(FlyctlActivity.isUpgrade(["/Users/ann/.fly/bin/flyctl", "version", "upgrade"]))
        #expect(FlyctlActivity.isUpgrade(["fly", "version", "update"]))
        #expect(!FlyctlActivity.isUpgrade(["flyctl", "version"]))
        #expect(!FlyctlActivity.isUpgrade(["flyctl", "deploy", "version", "upgrade"]))
        let curl = ClaudeCodeActivity.Process(pid: 9, arguments: [
            "curl", "-q", "--fail", "--output", "/Users/ann/.fly/tmp/flyctl.tar.gz",
            "https://github.com/superfly/flyctl/releases/download/v0.4.115/flyctl_0.4.115_macOS_arm64.tar.gz",
        ])
        #expect(FlyctlActivity.busy(processes: [curl]) == .download(9))
        #expect(FlyctlActivity.busy(processes: [.init(pid: 2, arguments: ["curl", "https://api.fly.io/x"])]) == nil)
    }

    // MARK: - Release notes

    /// goreleaser's bullets lose their 40-hex commit. Excerpt of 0.4.115's body
    /// (fetched 2026-10-09). Mutation: drop the hash strip.
    @Test func releaseNotesDropTheCommitHash() throws {
        let body = """
            ## Changelog
            * a1cf49a52b36fba66a2bf0907617bd5aadb8a727 Restore --delete to the docs sync (#5293)
            * e58a4d55bf8c4bc85fc48e625642e2ae7d757adf Add FLY_NO_PROMPT to make flyctl never prompt (#5295)
            """
        let releases: [[String: Any]] = [
            ["tag_name": "v0.4.115", "prerelease": false, "draft": false, "published_at": "2026-10-08T19:14:42Z", "body": body],
        ]
        let log = try #require(FlyctlChangelog.parse(String(decoding: try JSONSerialization.data(withJSONObject: releases), as: UTF8.self)))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "0.4.115")
        #expect(entry.items.count == 2)
        #expect(entry.items.first?.hasPrefix("Restore --delete to the docs sync") == true)
        #expect(!entry.items.contains { $0.range(of: "[0-9a-f]{40}", options: .regularExpression) != nil })
    }
}
