import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Helm: finding it where its script puts it, its verdict on its own major line,
/// the archive check, the one-click through the official script, and its notes.
///
/// "helm" here is a `#!/bin/sh` script in a fixture directory carrying the Go
/// build information every build from 3.20.0 on carries (`mod\thelm.sh/helm/v3\t
/// v3.21.4\t`, measured 2026-10-09). The "official script" is a stand-in bash
/// script that passes `isInstaller` and does to the disk what `get-helm-3` does:
/// `cp` over the file. Pointers, downloads and unpacking are injected.
@Suite struct HelmTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { root.appendingPathComponent("ZZFixture-usr-local-bin") }
        var binary: URL { bin.appendingPathComponent("helm") }
        let digests: HelmPublishedDigests
        private let lock = NSLock()
        private var published: [String: String] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-helm-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = HelmPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func helm(version: String) -> String {
            let major = version.split(separator: ".")[0]
            return "#!/bin/sh\n# path\thelm.sh/helm/v\(major)/cmd/helm\nmod\thelm.sh/helm/v\(major)\tv\(version)\t\nexit 0\n"
        }

        @discardableResult
        func install(version: String, publish: Bool = true) throws -> URL {
            let text = Self.helm(version: version)
            try Data(text.utf8).write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
            if publish { self.publish(version, text) }
            return binary
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        var downloadCount: Int { lock.withLock { downloads } }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        /// A stand-in for `get-helm-<major>`: records how it was run, then `cp`s
        /// `to` over `$HELM_INSTALL_DIR/helm`, as the script's `installFile` does.
        func script(major: Int = 3, to version: String, publishNew: Bool = true, fail: String? = nil) throws -> Data {
            let next = Self.helm(version: version)
            if publishNew { publish(version, next) }
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            let body = fail.map { "echo '\($0)'\necho 'Failed to install helm'\necho '\tFor support, go to https://github.com/helm/helm.'\nexit 1" }
                ?? """
                cp "\(staged.path)" "$HELM_INSTALL_DIR/helm"
                command -v helm > "\(root.path)/WHICH"
                """
            return Data("""
                #!/usr/bin/env bash
                : ${HELM_INSTALL_DIR:="/usr/local/bin"}
                # latest_release_url="https://get.helm.sh/helm\(major)-latest-version?ts=$(date +%s)"
                case x in '--no-sudo') ;; esac
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$TMPDIR" >/dev/null || exit 9
                /bin/ls $(echo "$PATH" | /usr/bin/tr ':' ' ') > "\(root.path)/PATHLS"
                \(body)
                """.utf8)
        }

        var scanner: HelmScanner {
            HelmScanner(home: home, systemDirectory: bin, isQuarantined: { _ in false }, readTarget: { _ in "arm64" })
        }

        static func archive(_ version: String) -> Data { Data("tgz-\(version)".utf8) }

        func verifier(tamper: Bool = false) -> HelmVerifier {
            HelmVerifier(
                download: { url in
                    let name = url.lastPathComponent
                    let version = String(name.dropFirst("helm-v".count)).components(separatedBy: "-darwin").first ?? ""
                    guard self.lock.withLock({ self.published[version] }) != nil else { throw HelmRelease.Failure.http(404) }
                    if url.pathExtension == "sha256" {
                        return Data(SHA256.hash(data: Self.archive(version)).map { String(format: "%02x", $0) }.joined().utf8)
                    }
                    self.lock.withLock { self.downloads += 1 }
                    return tamper ? Data("other".utf8) : Self.archive(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self).replacingOccurrences(of: "tgz-", with: "")
                    let text = self.lock.withLock { self.published[version] } ?? ""
                    let inside = directory.appendingPathComponent("darwin-arm64")
                    try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
                    try Data(text.utf8).write(to: inside.appendingPathComponent("helm"))
                },
                digests: digests)
        }

        func check(latest: [Int: String] = [3: "3.22.0", 4: "4.3.0"], fails: Bool = false) -> HelmCheck {
            let verifier = verifier()
            return HelmCheck(latest: { major in
                if fails { throw HelmRelease.Failure.http(503) }
                guard let version = latest[major] else { throw HelmRelease.Failure.noLine(major) }
                return version
            }, knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
        }

        func updater(latest: [Int: String] = [3: "3.22.0", 4: "4.3.0"], script: Data,
                     busy: @escaping HelmUpdater.BusyCheck = { nil }) -> HelmUpdater {
            HelmUpdater(busy: busy, scanner: scanner, check: check(latest: latest), verifier: verifier(),
                        environment: { ["USE_SUDO": "true", "HELM_INSTALL_DIR": "/elsewhere", "DESIRED_VERSION": "v9.9.9",
                                        "KEEP": "1"] },
                        fetchScript: { url in
                            #expect(url.absoluteString == "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3")
                            return script
                        })
        }

        func status(busy: HelmActivity.Busy? = nil) async throws -> CLIToolStatus {
            await check().status(of: try #require(scanner.scan().first), busy: busy)
        }
    }

    // MARK: - Finding it

    /// The main module's version on its own major line; `(devel)` (builds before
    /// 3.20.0) and a version on the other line are unreadable. Mutations: accept
    /// `(devel)`; drop the major check.
    @Test func readsTheModuleVersion() throws {
        func windows(_ text: String) -> [Data] {
            text.components(separatedBy: "mod\thelm.sh/helm/v").dropFirst().map { Data(("mod\thelm.sh/helm/v" + $0).utf8) }
        }
        #expect(HelmScanner.moduleVersion(in: windows("x\nmod\thelm.sh/helm/v3\tv3.21.4\t\ndep\t…")) == "3.21.4")
        #expect(HelmScanner.moduleVersion(in: windows("mod\thelm.sh/helm/v4\tv4.3.0\t\nmod\thelm.sh/helm/v4\tv4.3.0\t")) == "4.3.0")
        #expect(HelmScanner.moduleVersion(in: windows("mod\thelm.sh/helm/v3\t(devel)\t\n")) == nil)
        #expect(HelmScanner.moduleVersion(in: windows("mod\thelm.sh/helm/v3\tv4.3.0\t\n")) == nil)
        #expect(HelmScanner.moduleVersion(in: windows("mod\thelm.sh/helm/v3\tv3.21.4\t mod\thelm.sh/helm/v3\tv3.21.3\t")) == nil)

        let box = try Sandbox()
        try box.install(version: "3.21.4")
        let install = try #require(box.scanner.scan().first)
        #expect(install.version == "3.21.4")
        #expect(install.major == 3)
        #expect(install.writable)
        #expect(install.problem == nil)
    }

    /// Homebrew's is not looked at; any other link is reported; an old build is
    /// `.versionUnreadable`. Mutation: treat a link as the file.
    @Test func linksAndOldBuilds() async throws {
        let box = try Sandbox()
        let cellar = box.root.appendingPathComponent("opt/homebrew/Cellar/helm/3.22.0/bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try Data(Sandbox.helm(version: "3.22.0").utf8).write(to: cellar.appendingPathComponent("helm"))
        try FileManager.default.createSymbolicLink(atPath: box.binary.path, withDestinationPath: cellar.appendingPathComponent("helm").path)
        #expect(box.scanner.scan().isEmpty)

        try FileManager.default.removeItem(at: box.binary)
        let loose = box.root.appendingPathComponent("helm-elsewhere")
        try Data(Sandbox.helm(version: "3.21.4").utf8).write(to: loose)
        box.publish("3.21.4", Sandbox.helm(version: "3.21.4"))
        try FileManager.default.createSymbolicLink(atPath: box.binary.path, withDestinationPath: loose.path)
        let linked = try await box.status()
        #expect(linked.withheld == .unsupportedInstaller)
        #expect(linked.oneClick == nil)
        #expect(linked.manualCommand == nil)

        try FileManager.default.removeItem(at: box.binary)
        try Data("#!/bin/sh\nmod\thelm.sh/helm/v3\t(devel)\t\n".utf8).write(to: box.binary)
        let old = try await box.status()
        #expect(old.withheld == .versionUnreadable)
        #expect(old.state == .unknown)
    }

    // MARK: - The verdict

    /// Compared on its own line: a v3 install is offered v3's latest, never v4.
    /// Mutation: ask the v4 pointer.
    @Test func comparesOnItsOwnMajorLine() async throws {
        let box = try Sandbox()
        try box.install(version: "3.21.4")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "3.22.0")
        #expect(status.channel == "v3")
        #expect(status.releaseNotesKey == "helm-v3")
        #expect(status.oneClick?.arguments.contains("v3.22.0") == true)
        #expect(status.oneClick?.arguments.contains("USE_SUDO=false") == true)
        try box.install(version: "3.22.0")
        #expect(try await box.status().state == .upToDate)
        try box.install(version: "4.2.4")
        #expect(try await box.status().latestVersion == "4.3.0")
    }

    /// A file only `sudo` could replace is reported with Helm's documented
    /// command and never offered. Mutations: drop the gate; drop the command.
    @Test func aReadOnlyInstallGetsTheDocumentedCommand() async throws {
        let box = try Sandbox()
        try box.install(version: "3.21.4")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let status = try await box.status()
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.oneClick == nil)
        #expect(status.manualCommand?.display == "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash")
        // And the updater, asked anyway, runs nothing.
        let ran = await box.updater(script: try box.script(to: "3.22.0")).update(status)
        #expect(ran == .notOffered)
        #expect(box.read("ARGS") == nil)
    }

    /// Mutations: drop any one gate.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "3.21.4")
        #expect(try await box.status(busy: .download(3)).withheld == .busy)
        #expect(await box.check(fails: true).status(of: try #require(box.scanner.scan().first), busy: nil)
            .withheld == .channelUnreadable)
        let path = box.binary.path
        #expect(await box.check().status(of: HelmInstall(path: path, binary: path, version: "3.21.4", quarantined: true),
                                         busy: nil).withheld == .unverified)
        box.publish("3.21.4", "not this file")
        _ = await box.verifier().verify(binary: path, version: "3.21.4", target: "arm64")
        #expect(try await box.status().withheld == .unverified)
    }

    @Test func readsThePointer() async throws {
        let ok = HelmRelease(fetch: { url in
            #expect(url.absoluteString == "https://get.helm.sh/helm3-latest-version")
            return (Data("v3.22.0\n".utf8), 200)
        })
        #expect(try await ok.latest(major: 3) == "3.22.0")
        let crossed = HelmRelease(fetch: { _ in (Data("v4.3.0".utf8), 200) })
        await #expect(throws: HelmRelease.Failure.unreadable) { try await crossed.latest(major: 3) }
        await #expect(throws: HelmRelease.Failure.noLine(2)) { try await ok.latest(major: 2) }
        #expect(HelmRelease.digestURL(version: "3.22.0", target: "arm64").absoluteString
            == "https://get.helm.sh/helm-v3.22.0-darwin-arm64.tar.gz.sha256")
    }

    /// Mutations: skip the archive check; never remember.
    @Test func verifiesAgainstTheReleaseArchive() async throws {
        let box = try Sandbox()
        let path = try box.install(version: "3.21.4").path
        #expect(await box.verifier().verify(binary: path, version: "3.21.4", target: "arm64") == .matches)
        #expect(await box.verifier().verify(binary: path, version: "3.21.4", target: "arm64") == .matches)
        #expect(box.downloadCount == 1)
        box.publish("3.21.3", "x")
        let tampered = await box.verifier(tamper: true).verify(binary: path, version: "3.21.3", target: "arm64")
        guard case .couldNotVerify = tampered else { Issue.record("expected couldNotVerify, got \(tampered)"); return }
    }

    // MARK: - The update

    /// The line's script, pinned to the checked version, without sudo, into the
    /// install's own directory, with a PATH of its programs and a `helm` link
    /// only. Mutations: keep the inherited `USE_SUDO`/`HELM_INSTALL_DIR`/
    /// `DESIRED_VERSION`; drop `--no-sudo`; put the install's directory on PATH.
    @Test func updatesThroughTheScript() async throws {
        let box = try Sandbox()
        try box.install(version: "3.21.4")
        let outcome = await box.updater(script: try box.script(to: "3.22.0")).update(try await box.status())
        #expect(outcome == .updated(version: "3.22.0"))
        #expect(box.read("ARGS") == "--version v3.22.0 --no-sudo\n")
        let env = box.read("ENV") ?? ""
        #expect(env.contains("USE_SUDO=false\n"))
        #expect(env.contains("VERIFY_CHECKSUM=true\n"))
        #expect(env.contains("HELM_INSTALL_DIR=\(box.bin.path)\n"))
        #expect(!env.contains("DESIRED_VERSION="))
        #expect(env.contains("KEEP=1"))
        let path = (box.read("PATHLS") ?? "").split(separator: "\n")
        #expect(path.contains("curl") && path.contains("openssl") && path.contains("helm"))
        #expect(!path.contains("sudo") && !path.contains("git"))
        #expect(box.read("WHICH")?.hasSuffix("/helm\n") == true)
        #expect(box.scanner.scan().first?.version == "3.22.0")
    }

    /// Another line's script, or an error page, is not run. Mutation: skip `isInstaller`.
    @Test func onlyTheLinesScriptRuns() async throws {
        let box = try Sandbox()
        try box.install(version: "3.21.4")
        let status = try await box.status()
        guard case .failed(let message, _) = await box.updater(script: try box.script(major: 4, to: "3.22.0")).update(status) else {
            Issue.record("ran the v4 script for a v3 install"); return
        }
        #expect(message.contains("v3 script"))
        #expect(box.read("ARGS") == nil)
        #expect(!HelmUpdater.isInstaller(Data("<html>404</html>".utf8), major: 3))
    }

    /// What the script left must be a newer published build of the same line.
    /// Mutation: report `.updated` without verifying.
    @Test func anUnpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "3.21.4")
        let script = try box.script(to: "3.22.0", publishNew: false)
        box.publish("3.22.0", "the real 3.22.0")
        guard case .failed(let message, _) = await box.updater(script: script).update(try await box.status()) else {
            Issue.record("an unpublished result read as updated"); return
        }
        #expect(message.contains("is not the helm 3.22.0"))
    }

    /// The script's own reason, not its support link, with the exit status.
    /// Mutation: use the shared last-line rule.
    @Test func aFailedScriptSaysWhy() async throws {
        let box = try Sandbox()
        try box.install(version: "3.21.4")
        let script = try box.script(to: "3.22.0", fail: "SHA sum of /tmp/x.tar.gz does not match. Aborting.")
        guard case .failed(let message, let output) = await box.updater(script: script).update(try await box.status()) else {
            Issue.record("a failed script read as updated"); return
        }
        #expect(message == "SHA sum of /tmp/x.tar.gz does not match. Aborting. (exit 1)")
        #expect(output.contains("For support"))
    }

    @Test func busyIsTheScriptOrItsDownload() {
        #expect(HelmActivity.busy(processes: [.init(pid: 5, arguments: ["bash", "/tmp/get_helm.sh"])]) == .script(5))
        #expect(HelmActivity.busy(processes: [.init(pid: 6, arguments: [
            "curl", "-SsL", "https://get.helm.sh/helm-v3.22.0-darwin-arm64.tar.gz", "-o", "/tmp/x"])]) == .download(6))
        #expect(HelmActivity.busy(processes: [.init(pid: 7, arguments: ["helm", "upgrade", "my-release"])]) == nil)
    }

    // MARK: - Release notes

    static func json(_ releases: [(String, Bool, String)]) throws -> String {
        let objects: [[String: Any]] = releases.map {
            ["tag_name": $0.0, "prerelease": $0.1, "draft": false, "published_at": "2026-09-10T00:08:41Z", "body": $0.2]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: objects), as: UTF8.self)
    }

    /// The line's releases only; the community links, download section and
    /// commit list left out when the release has notable changes; a release with
    /// only a commit list keeps it, without hashes and authors. Bodies are
    /// excerpts of 3.22.0, 4.3.0 and 3.21.3 (fetched 2026-10-09), `\r\n` and all.
    /// Mutations: drop the preamble cut; keep `## Changelog` beside notable
    /// changes; drop the hash strip; drop the tag pattern.
    @Test func releaseNotesAreTheLinesNotableChanges() throws {
        let notable = """
            Helm v3.22.0 is a feature release. Users are encouraged to upgrade for the best experience.\r
            \r
            - Join the discussion in [Kubernetes Slack](https://kubernetes.slack.com):\r
              -  for questions and just to hang out\r
            - Test, debug, and contribute charts: [ArtifactHub/packages](https://artifacthub.io/packages/search?kind=0)\r
            \r
            ## Notable Changes\r
            \r
            * primarily dependency updates and k8s-io group to 0.37.0\r
            \r
            ## Installation and Upgrading\r
            \r
            - [MacOS arm64](https://get.helm.sh/helm-v3.22.0-darwin-arm64.tar.gz) ([checksum](https://get.helm.sh/helm-v3.22.0-darwin-arm64.tar.gz.sha256sum) / 4c9982a6cdeb458b60258df66b55398ca5b19293f6877faffe2909ad6f23dfe0)\r
            \r
            ## What's Next\r
            \r
            - 3.22.1 is the next patch release\r
            \r
            ## Changelog\r
            \r
            - chore(deps): bump the k8s-io group 813176c51bb5c181dbbd7901298ddcc104cd3417 (dependabot[bot])\r
            """
        let commitsOnly = """
            Helm v3.21.3 is a patch release.\r
            \r
            - Join the discussion in [Kubernetes Slack](https://kubernetes.slack.com):\r
            \r
            ## Installation and Upgrading\r
            \r
            - [MacOS arm64](https://get.helm.sh/helm-v3.21.3-darwin-arm64.tar.gz)\r
            \r
            ## Changelog\r
            \r
            - fix: drop containerd v1 dep to resolve govulncheck CVEs 037733e7d51b08e30a0233bd546c345ab3ea3bba (Benoit Tigeot)\r
            """
        let v4 = "## Notable Changes\r\n\r\n* feat: Add duration functions by @aeroyorch in https://github.com/helm/helm/pull/31695\r\n"
        let json = try Self.json([("v4.3.0", false, v4), ("v3.22.0", false, notable), ("v3.22.0-rc.1", true, notable),
                                  ("v3.21.3", false, commitsOnly)])
        let log = try #require(HelmChangelog.parse(json, major: 3))
        #expect(log.entries.map(\.version) == ["3.22.0", "3.21.3"])
        #expect(log.entries[0].items == ["primarily dependency updates and k8s-io group to 0.37.0"])
        #expect(log.entries[1].items == ["fix: drop containerd v1 dep to resolve govulncheck CVEs"])
        let all = log.entries.flatMap(\.items).joined(separator: "\n")
        #expect(!all.contains("Slack") && !all.contains("get.helm.sh") && !all.contains("patch release"))
        #expect(try #require(HelmChangelog.parse(json, major: 4)).entries.map(\.version) == ["4.3.0"])
    }
}
