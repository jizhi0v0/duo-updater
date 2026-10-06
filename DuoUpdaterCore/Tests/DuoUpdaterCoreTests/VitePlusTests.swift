import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Vite+ (`vp`): finding it under its two roots, its verdict, the package check
/// the trust rule rests on, its one-click update and its release notes.
///
/// "vp" here is a `#!/bin/sh` script in a temporary HOME, laid out as the
/// installer and `vp upgrade` lay it out (measured 2026-10-06 with 0.2.9, 0.3.3
/// and 1.0.0): `<root>/<version>/bin/vp`, the wrapper `package.json`, and
/// `current` linking to the active version. Its `upgrade` does what the real one
/// does to the disk — a new version directory, then `current` swapped. The
/// registry, the package download and its unpacking are injected: nothing here
/// reads the host's process table, runs a Vite+ build or reaches the network.
@Suite struct VitePlusTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var single: URL { home.appendingPathComponent(".vite-plus") }
        var split: URL { home.appendingPathComponent(".local/share/vite-plus") }
        let verified: UvVerifiedFiles
        private let lock = NSLock()
        /// version → the `vp` its npm package holds.
        private var published: [String: String] = [:]
        private var downloads = 0

        init() throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("vite-plus-tests-\(UUID().uuidString)")
            self.root = root
            verified = UvVerifiedFiles(fileURL: root.appendingPathComponent("verified.json"))
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        static func script(version: String, upgrade: String = "exit 0") -> String {
            """
            #!/bin/sh
            # vp \(version)
            if [ "$1" = upgrade ]; then
            \(upgrade)
            fi
            """
        }

        static func packageJSON(_ version: String) -> String {
            #"{"name": "vp-global", "version": "\#(version)", "private": true, "dependencies": {"vite-plus": "\#(version)"}}"#
        }

        /// `<dir>/<version>` with its `vp` and `package.json`, made `current`; the
        /// file is what npm published for that version unless `publish` is false.
        @discardableResult
        func install(at dir: URL, version: String, upgrade: String = "exit 0", publish: Bool = true) throws -> URL {
            let text = Self.script(version: version, upgrade: upgrade)
            let bin = dir.appendingPathComponent("\(version)/bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: bin.appendingPathComponent("vp"))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appendingPathComponent("vp").path)
            try Data(Self.packageJSON(version).utf8).write(to: dir.appendingPathComponent("\(version)/package.json"))
            let current = dir.appendingPathComponent("current")
            try? FileManager.default.removeItem(at: current)
            try FileManager.default.createSymbolicLink(atPath: current.path, withDestinationPath: version)
            if publish { self.publish(version, text) }
            return bin.appendingPathComponent("vp")
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        var downloadCount: Int { lock.withLock { downloads } }

        /// What `vp upgrade <version>` does to `dir`: the new version beside the
        /// old, then `current` swapped. Published unless `publishNew` is false.
        func upgradeBody(in dir: URL, to version: String, publishNew: Bool = true) throws -> String {
            let next = Self.script(version: version)
            if publishNew { publish(version, next) }
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            try Data(Self.packageJSON(version).utf8).write(to: root.appendingPathComponent("next-\(version).json"))
            return """
                echo "$@" > "\(root.path)/ARGS"
                env > "\(root.path)/ENV"
                mkdir -p "\(dir.path)/\(version)/bin"
                cp "\(staged.path)" "\(dir.path)/\(version)/bin/vp" && chmod 755 "\(dir.path)/\(version)/bin/vp"
                cp "\(root.path)/next-\(version).json" "\(dir.path)/\(version)/package.json"
                ln -sfn \(version) "\(dir.path)/current"
                echo "✓ Updated vite-plus to \(version)"
                """
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        var scanner: VitePlusScanner {
            VitePlusScanner(home: home, verified: verified, readPlatform: { _ in "darwin-arm64" }, isQuarantined: { _ in false })
        }

        static func tarball(_ version: String) -> Data { Data("tgz-\(version)".utf8) }

        /// The registry: `vite-plus/latest`, and each published version's
        /// platform package document.
        func release(latest: String = "1.0.0", registryFails: Bool = false) -> VitePlusRelease {
            VitePlusRelease(fetch: { url in
                if registryFails { throw VitePlusRelease.Failure.http(503) }
                if url == VitePlusRelease.channel { return (Data(#"{"version": "\#(latest)"}"#.utf8), 200) }
                let version = url.lastPathComponent
                guard url.absoluteString.contains("vite-plus-cli-darwin-arm64"), self.lock.withLock({ self.published[version] }) != nil
                else { return (Data("{}".utf8), 404) }
                let integrity = "sha512-" + Data(SHA512.hash(data: Self.tarball(version))).base64EncodedString()
                let json = """
                    {"version": "\(version)", "dist": {
                      "tarball": "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-darwin-arm64/-/vite-plus-cli-darwin-arm64-\(version).tgz",
                      "integrity": "\(integrity)",
                      "attestations": {"provenance": {"predicateType": "https://slsa.dev/provenance/v1"}}}}
                    """
                return (Data(json.utf8), 200)
            })
        }

        func verifier(latest: String = "1.0.0", tamper: Bool = false) -> VitePlusVerifier {
            VitePlusVerifier(
                release: release(latest: latest),
                download: { url in
                    self.lock.withLock { self.downloads += 1 }
                    let version = url.lastPathComponent
                        .replacingOccurrences(of: "vite-plus-cli-darwin-arm64-", with: "")
                        .replacingOccurrences(of: ".tgz", with: "")
                    return tamper ? Data("other".utf8) : Self.tarball(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self).replacingOccurrences(of: "tgz-", with: "")
                    let package = directory.appendingPathComponent("package")
                    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
                    let text = self.lock.withLock { self.published[version] } ?? ""
                    try Data(text.utf8).write(to: package.appendingPathComponent("vp"))
                },
                verified: verified)
        }

        func check(latest: String = "1.0.0", registryFails: Bool = false) -> VitePlusCheck {
            let release = release(latest: latest, registryFails: registryFails)
            return VitePlusCheck(latest: { try await release.latest() })
        }

        func updater(latest: String = "1.0.0", busy: @escaping VitePlusUpdater.BusyCheck = { nil }) -> VitePlusUpdater {
            VitePlusUpdater(
                busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(latest: latest),
                environment: { ["VP_HOME": "/elsewhere", "XDG_DATA_HOME": "/elsewhere", "KEEP": "1"] })
        }

        func status(latest: String = "1.0.0", busy: VitePlusActivity.Busy? = nil) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(latest: latest).status(of: install, busy: busy)
        }
    }

    // MARK: - Finding it

    /// A fresh 0.3+ install: the split root, its version from the wrapper
    /// package, the binary `current` names. Mutation: read the version from the
    /// directory name (the `+suffix` case below would break).
    @Test func findsASplitInstall() throws {
        let box = try Sandbox()
        let vp = try box.install(at: box.split, version: "0.3.3")
        let installs = box.scanner.scan()
        #expect(installs == [VitePlusInstall(
            path: box.split.path, layout: .split, version: "0.3.3", binary: vp.resolvingSymlinksInPath().path,
            platform: "darwin-arm64")])
    }

    /// A forced reinstall's `<version>+<suffix>` directory still reads as the
    /// version its package names.
    @Test func versionIsThePackagesNotTheDirectorys() throws {
        let box = try Sandbox()
        try box.install(at: box.split, version: "1.0.0")
        try FileManager.default.moveItem(at: box.split.appendingPathComponent("1.0.0"), to: box.split.appendingPathComponent("1.0.0+r1"))
        try FileManager.default.removeItem(at: box.split.appendingPathComponent("current"))
        try FileManager.default.createSymbolicLink(atPath: box.split.appendingPathComponent("current").path, withDestinationPath: "1.0.0+r1")
        #expect(box.scanner.scan().first?.version == "1.0.0")
    }

    /// Both roots: `vp` resolves `~/.vite-plus` whenever its `current` exists, so
    /// the split one is shadowed. Mutation: never mark it.
    @Test func aSplitInstallBesideTheSingleRootIsShadowed() throws {
        let box = try Sandbox()
        try box.install(at: box.single, version: "0.2.9")
        try box.install(at: box.split, version: "0.3.3")
        let installs = box.scanner.scan()
        #expect(installs.map(\.layout) == [.singleRoot, .split])
        #expect(installs.map(\.problem) == [nil, .shadowed])
    }

    /// `vp` asks for `~/.vite-plus/current` without following it, so a dangling
    /// link still shadows the split install. Mutation: follow the link.
    @Test func aDanglingSingleRootLinkStillShadows() throws {
        let box = try Sandbox()
        try box.install(at: box.split, version: "0.3.3")
        try FileManager.default.createDirectory(at: box.single, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: box.single.appendingPathComponent("current").path, withDestinationPath: "0.0.0-missing")
        #expect(box.scanner.scan().last?.problem == .shadowed)
    }

    @Test func brokenInstallsSayHow() throws {
        let box = try Sandbox()
        try box.install(at: box.split, version: "0.3.3")
        try FileManager.default.removeItem(at: box.split.appendingPathComponent("0.3.3/bin/vp"))
        #expect(box.scanner.scan().first?.problem == .executableMissing)

        try box.install(at: box.single, version: "0.2.9")
        try Data(#"{"name": "something-else", "version": "0.2.9"}"#.utf8)
            .write(to: box.single.appendingPathComponent("0.2.9/package.json"))
        #expect(box.scanner.scan().first?.problem == .versionUnreadable)
    }

    @Test func nothingInstalledIsNothing() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.split, withIntermediateDirectories: true)
        #expect(box.scanner.scan().isEmpty)
    }

    // MARK: - The verdict

    /// An update is `vp upgrade <latest>` on the install's own binary, pinned.
    @Test func offersVpUpgradePinnedToLatest() async throws {
        let box = try Sandbox()
        let vp = try box.install(at: box.split, version: "0.3.3")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "1.0.0")
        #expect(status.oneClick == CLIToolCommand(
            executable: vp.resolvingSymlinksInPath().path, arguments: ["upgrade", "1.0.0"], pathPrefix: nil))
    }

    /// A release candidate is below its release, and a copy newer than `latest`
    /// is ahead, not an update.
    @Test func comparesBySemver() async throws {
        let box = try Sandbox()
        try box.install(at: box.split, version: "1.0.0-rc.1")
        #expect(try await box.status().state == .updateAvailable)
        try box.install(at: box.split, version: "1.0.0")
        #expect(try await box.status().state == .upToDate)
        try box.install(at: box.split, version: "1.1.0-rc.0")
        let ahead = try await box.status()
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
    }

    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install(at: box.single, version: "0.2.9")
        try box.install(at: box.split, version: "0.3.3")
        let install = try #require(box.scanner.scan().last)
        let shadowed = await box.check().status(of: install, busy: nil)
        #expect(shadowed.withheld == .unsupportedInstaller)
        #expect(shadowed.oneClick == nil)

        let single = try #require(box.scanner.scan().first)
        let busy = await box.check().status(of: single, busy: .command("upgrade", 42))
        #expect(busy.withheld == .busy)

        let failing = await box.check(registryFails: true).status(of: single, busy: nil)
        #expect(failing.withheld == .channelUnreadable)

        let quarantined = VitePlusInstall(path: single.path, layout: .singleRoot, version: "0.2.9",
                                          binary: single.binary, platform: "darwin-arm64", quarantined: true)
        #expect(await box.check().status(of: quarantined, busy: nil).withheld == .unverified)
    }

    /// A copy a click found not to be VoidZero's build stays withheld until the
    /// file changes. Mutation: ignore the remembered verdict.
    @Test func aCopyFoundNotToBeThePackageIsWithheld() async throws {
        let box = try Sandbox()
        let vp = try box.install(at: box.split, version: "0.3.3", publish: false)
        box.publish("0.3.3", "something else")
        let result = await box.verifier().verify(binary: vp.resolvingSymlinksInPath().path, version: "0.3.3", platform: "darwin-arm64")
        guard case .differs = result else { Issue.record("expected differs, got \(result)"); return }
        let status = try await box.status()
        #expect(status.withheld == .unverified)
        #expect(status.oneClick == nil)

        // Replaced by the published build: the verdict is gone with the old file.
        try box.install(at: box.split, version: "0.3.3")
        #expect(try await box.status().oneClick != nil)
    }

    // MARK: - The package check

    /// The package's SHA-512 is the registry's, and its `vp` is compared with the
    /// file; a definite answer is remembered. Mutations: skip the integrity
    /// check; compare nothing.
    @Test func verifiesAgainstTheNpmPackage() async throws {
        let box = try Sandbox()
        let vp = try box.install(at: box.split, version: "0.3.3").resolvingSymlinksInPath().path
        #expect(await box.verifier().verify(binary: vp, version: "0.3.3", platform: "darwin-arm64") == .matches)
        #expect(box.scanner.scan().first?.hashVerdict == .matches)

        let tampered = await box.verifier(tamper: true).verify(binary: vp, version: "0.3.3", platform: "darwin-arm64")
        guard case .couldNotVerify = tampered else { Issue.record("expected couldNotVerify, got \(tampered)"); return }

        let unknown = await box.verifier().verify(binary: vp, version: "0.3.4", platform: "darwin-arm64")
        guard case .couldNotVerify = unknown else { Issue.record("expected couldNotVerify, got \(unknown)"); return }
    }

    /// The registry's document must carry provenance, a sha512 integrity and a
    /// tarball on the registry itself, as the installer insists.
    @Test func packageDocumentsAreHeldToTheInstallersRules() throws {
        let integrity = "sha512-" + Data(repeating: 1, count: 64).base64EncodedString()
        func doc(provenance: String? = "https://slsa.dev/provenance/v1",
                 tarball: String = "https://registry.npmjs.org/x/-/x-1.0.0.tgz",
                 integrity: String = integrity) -> [String: Any] {
            var dist: [String: Any] = ["tarball": tarball, "integrity": integrity]
            if let provenance { dist["attestations"] = ["provenance": ["predicateType": provenance]] }
            return ["version": "1.0.0", "dist": dist]
        }
        #expect(throws: Never.self) { try VitePlusRelease.package(in: doc(), version: "1.0.0") }
        #expect(throws: VitePlusRelease.Failure.self) { try VitePlusRelease.package(in: doc(provenance: nil), version: "1.0.0") }
        #expect(throws: VitePlusRelease.Failure.self) {
            try VitePlusRelease.package(in: doc(tarball: "https://evil.example/x.tgz"), version: "1.0.0")
        }
        #expect(throws: VitePlusRelease.Failure.self) {
            try VitePlusRelease.package(in: doc(integrity: "sha1-abc"), version: "1.0.0")
        }
        #expect(throws: VitePlusRelease.Failure.self) { try VitePlusRelease.package(in: doc(), version: "1.0.1") }
    }

    // MARK: - The update

    /// The click checks the old file against its package, runs `vp upgrade
    /// <version>` without the root overrides, and checks what it left.
    @Test func updatesAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(at: box.split, version: "0.3.3", upgrade: try box.upgradeBody(in: box.split, to: "1.0.0"))
        let status = try await box.status()
        let outcome = await box.updater().update(status)
        #expect(outcome == .updated(version: "1.0.0"))
        #expect(box.read("ARGS") == "upgrade 1.0.0\n")
        let env = box.read("ENV") ?? ""
        #expect(!env.contains("VP_HOME="))
        #expect(!env.contains("XDG_DATA_HOME="))
        #expect(env.contains("KEEP=1"))
        #expect(env.contains("HOME=\(box.home.path)"))
        #expect(box.downloadCount == 2)
    }

    /// What the update left must be the published build of the pinned version.
    /// Mutation: report `.updated` without verifying the new file.
    @Test func anUnpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(at: box.split, version: "0.3.3",
                        upgrade: try box.upgradeBody(in: box.split, to: "1.0.0", publishNew: false))
        box.publish("1.0.0", "the real 1.0.0")
        let outcome = await box.updater().update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(message.contains("not the vp VoidZero published for 1.0.0"))
    }

    /// Nothing runs when the old file is not the package, when `latest` moved,
    /// or when an upgrade is already running.
    @Test func gatesAreAskedAgainAtTheClick() async throws {
        let box = try Sandbox()
        try box.install(at: box.split, version: "0.3.3", upgrade: try box.upgradeBody(in: box.split, to: "1.0.0"))
        let status = try await box.status()

        #expect(await box.updater(busy: { .command("upgrade", 7) }).update(status) == .busy("vp upgrade is running (pid 7)"))
        guard case .failed = await box.updater(latest: "1.0.1").update(status) else { Issue.record("ran on a moved latest"); return }

        box.publish("0.3.3", "not this file")
        guard case .failed(let message, _) = await box.updater().update(status) else { Issue.record("ran unverified"); return }
        #expect(message.hasPrefix("not run:"))
        #expect(!box.ran)
    }

    @Test func failureLineIsVpsOwnError() {
        let outcome = ChildProcess.Outcome(
            terminationStatus: 1, uncaughtSignal: false, timedOut: false, standardOutput: Data(), standardError: Data())
        let lines = ["info: checking for updates...", "error: Failed to download platform package: timed out"]
        #expect(VitePlusUpdater.failureMessage(lines, outcome, deadline: VitePlusUpdater.defaultDeadline)
            == "Failed to download platform package: timed out")
    }

    // MARK: - Busy

    /// `upgrade` or `implode` as `vp`'s subcommand; a task named `upgrade` and
    /// `upgrade --check` are not. Mutation: match any argument.
    @Test func busyIsVpChangingItself() {
        #expect(VitePlusActivity.changingCommand(["vp", "upgrade"]) == "upgrade")
        #expect(VitePlusActivity.changingCommand(["/Users/a/.vite-plus/bin/vp", "-C", "app", "upgrade", "1.0.0"]) == "upgrade")
        #expect(VitePlusActivity.changingCommand(["vp", "implode", "--yes"]) == "implode")
        #expect(VitePlusActivity.changingCommand(["vp", "upgrade", "--check"]) == nil)
        #expect(VitePlusActivity.changingCommand(["vp", "run", "upgrade"]) == nil)
        #expect(VitePlusActivity.changingCommand(["vpr", "upgrade"]) == nil)
        let curl = NpmActivity.Process(pid: 9, arguments: ["curl", "-sL", "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-darwin-arm64/-/x.tgz"], executable: nil)
        #expect(VitePlusActivity.busy(processes: [curl]) == .installer(9))
    }

    // MARK: - Release notes

    /// GitHub releases through the production decoder, without the "Published
    /// Packages" list every release ends with; prereleases dropped. Bodies are
    /// excerpts of 0.3.3's and 1.0.0-rc.1's (fetched 2026-10-06), cut down but
    /// byte for byte in the lines kept. Mutation: leave the section in.
    @Test func releaseNotesLeaveOutThePackageList() throws {
        let body = """
            This release fixes Homebrew setup, Windows installation, and workspace dependency commands.

            ### Fixes & Enhancements

            - Homebrew installations complete setup once, retain their bundled CLI, and direct upgrades to `brew upgrade vite-plus` ([#2729](https://github.com/voidzero-dev/vite-plus/pull/2729)), by @fengmk2.
            - `vp dedupe` warns about unsupported check options ([#2717](https://github.com/voidzero-dev/vite-plus/pull/2717)), by @jong-kyung.

            ### Bundled Versions

            | Tool | Version | Source |
            | --- | --- | --- |
            | `vite` | `8.3.0` | [`434e8e9`](https://github.com/vitejs/vite/commit/434e8e9495436a60789f2b588a04a6a24a3d1661) |

            ### Upgrade

            ```bash
            vp upgrade
            ```

            ### Published Packages

            - `@voidzero-dev/vite-plus-core@0.3.3`
            - `vite-plus@0.3.3`

            ### Installation

            **macOS/Linux:**

            ```bash
            curl -fsSL https://vite.plus | bash
            ```
            """
        let releases: [[String: Any]] = [
            ["tag_name": "v0.3.3", "prerelease": false, "draft": false, "published_at": "2026-09-18T03:11:45Z", "body": body],
            ["tag_name": "v0.1.21-alpha.7", "prerelease": true, "draft": false, "published_at": "2026-05-12T00:00:00Z",
             "body": "### Features\n\n- An alpha change"],
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: releases), as: UTF8.self)
        let log = try #require(VitePlusChangelog.parse(json))
        #expect(log.entries.map(\.version) == ["0.3.3"])
        let entry = try #require(log.entries.first)
        #expect(!entry.content.contains(.heading("Published Packages")))
        #expect(entry.content.contains(.heading("Fixes & Enhancements")))
        #expect(!entry.items.contains { $0.contains("vite-plus@0.3.3") })
        #expect(entry.items.contains { $0.hasPrefix("`vp dedupe` warns") })
    }
}
