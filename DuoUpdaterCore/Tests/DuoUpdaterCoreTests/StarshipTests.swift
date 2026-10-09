import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Starship: finding it where its script puts it, its verdict, the archive
/// check, the one-click through the official script, and its notes.
///
/// "starship" here is a `#!/bin/sh` script in a fixture directory carrying the
/// `pkg_version:<v>` literal every build carries (1.16.0 to 1.26.0, measured
/// 2026-10-09). The "official script" is a stand-in `sh` script that passes
/// `isInstaller` and unpacks a new file into `-b`. The latest-release redirect,
/// downloads and unpacking are injected.
@Suite struct StarshipTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { root.appendingPathComponent("ZZFixture-usr-local-bin") }
        var binary: URL { bin.appendingPathComponent("starship") }
        let digests: StarshipPublishedDigests
        private let lock = NSLock()
        private var published: [String: String] = [:]
        private var downloads = 0

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-starship-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            digests = StarshipPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.removeItem(at: root)
        }

        static func starship(version: String) -> String {
            "#!/bin/sh\n# branch:main pkg_version:\(version)\0build_time:2026-06\nexit 0\n"
        }

        @discardableResult
        func install(version: String, publish: Bool = true) throws -> URL {
            let text = Self.starship(version: version)
            try Data(text.utf8).write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
            if publish { self.publish(version, text) }
            return binary
        }

        func publish(_ version: String, _ text: String) { lock.withLock { published[version] = text } }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        /// A stand-in for `install.sh`: records how it was run, then writes `to`
        /// into `-b` as a new file, as its `tar -xzof … -C` does; `fail` exits as
        /// its `error` does.
        func script(to version: String, publishNew: Bool = true, fail: String? = nil) throws -> Data {
            let next = Self.starship(version: version)
            if publishNew { publish(version, next) }
            let staged = root.appendingPathComponent("next-\(version)")
            try Data(next.utf8).write(to: staged)
            let body = fail.map { "printf '%s\\n' \"\u{1B}[31mx \($0)\u{1B}(B\u{1B}[m\" >&2\nexit 1" } ?? """
                while [ "$#" -gt 0 ]; do case "$1" in -b) BIN_DIR="$2"; shift 2;; *) shift;; esac; done
                rm -f "$BIN_DIR/starship"; /bin/cp "\(staged.path)" "$BIN_DIR/starship"
                """
            return Data("""
                #!/usr/bin/env sh
                # BASE_URL="https://github.com/starship/starship/releases"
                # -b | --bin-dir)
                # -v | --version)
                echo "$@" > "\(root.path)/ARGS"
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$PATH" > "\(root.path)/PATHLS"
                \(body)
                """.utf8)
        }

        var scanner: StarshipScanner {
            StarshipScanner(home: home, systemDirectory: bin, isQuarantined: { _ in false },
                            readTarget: { _ in "aarch64-apple-darwin" })
        }

        static func archive(_ version: String) -> Data { Data("tgz-\(version)".utf8) }

        func verifier() -> StarshipVerifier {
            StarshipVerifier(
                download: { url in
                    let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                    guard self.lock.withLock({ self.published[version] }) != nil else { throw StarshipRelease.Failure.http(404) }
                    if url.pathExtension == "sha256" {
                        return Data(SHA256.hash(data: Self.archive(version)).map { String(format: "%02x", $0) }.joined().utf8)
                    }
                    self.lock.withLock { self.downloads += 1 }
                    return Self.archive(version)
                },
                extract: { archive, directory in
                    let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self).replacingOccurrences(of: "tgz-", with: "")
                    try Data((self.lock.withLock { self.published[version] } ?? "").utf8)
                        .write(to: directory.appendingPathComponent("starship"))
                },
                digests: digests)
        }

        func check(latest: String = "1.26.0") -> StarshipCheck {
            let verifier = verifier()
            return StarshipCheck(latest: { latest },
                                 knownVerdict: { verifier.knownVerdict(binary: $0, version: $1, target: $2) })
        }

        func updater(latest: String = "1.26.0", script: Data) -> StarshipUpdater {
            StarshipUpdater(busy: { nil }, scanner: scanner, check: check(latest: latest), verifier: verifier(),
                            environment: { ["BIN_DIR": "/elsewhere", "VERSION": "latest", "KEEP": "1"] },
                            fetchScript: { url in
                                #expect(url == StarshipCheck.installer)
                                return script
                            })
        }

        func status(busy: StarshipActivity.Busy? = nil) async throws -> CLIToolStatus {
            await check().status(of: try #require(scanner.scan().first), busy: busy)
        }
    }

    /// Mutation: accept disagreeing `pkg_version:` literals.
    @Test func readsTheCompiledVersion() throws {
        func windows(_ text: String) -> [Data] {
            text.components(separatedBy: "pkg_version:").dropFirst().map { Data(("pkg_version:" + $0).utf8) }
        }
        #expect(StarshipScanner.compiledVersion(in: windows("branch:main\0pkg_version:1.26.0\0build")) == "1.26.0")
        #expect(StarshipScanner.compiledVersion(in: windows("pkg_version:1.26.0 pkg_version:1.25.1")) == nil)
        #expect(StarshipScanner.compiledVersion(in: windows("pkg_version:{}")) == nil)
        let box = try Sandbox()
        try box.install(version: "1.25.1")
        #expect(box.scanner.scan().first?.version == "1.25.1")
    }

    /// The tag GitHub's latest redirect lands on; any other landing is
    /// unreadable. Mutation: accept any final URL.
    @Test func readsTheLatestRedirect() async throws {
        let ok = StarshipRelease(resolve: { url in
            #expect(url == StarshipRelease.latestPage)
            return (URL(string: "https://github.com/starship/starship/releases/tag/v1.26.0"), 200)
        })
        #expect(try await ok.latest() == "1.26.0")
        let unredirected = StarshipRelease(resolve: { _ in (URL(string: "https://github.com/starship/starship/releases"), 200) })
        await #expect(throws: StarshipRelease.Failure.unreadable) { try await unredirected.latest() }
        let elsewhere = StarshipRelease(resolve: { _ in (URL(string: "https://evil.example/starship/starship/releases/tag/v9.0.0"), 200) })
        await #expect(throws: StarshipRelease.Failure.unreadable) { try await elsewhere.latest() }
    }

    @Test func offersThePinnedScript() async throws {
        let box = try Sandbox()
        try box.install(version: "1.25.1")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick?.display
            == "curl -sS https://starship.rs/install.sh | sh -s -- -y -b \(box.bin.path) -v v1.26.0")
        try box.install(version: "1.26.0")
        #expect(try await box.status().state == .upToDate)
    }

    /// Mutations: drop the writable gate; drop the documented command; treat a link as the file.
    @Test func gatesWithholdTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "1.25.1")
        #expect(try await box.status(busy: .download(2)).withheld == .busy)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.bin.path)
        let readOnly = try await box.status()
        #expect(readOnly.withheld == .unsupportedInstaller)
        #expect(readOnly.oneClick == nil)
        #expect(readOnly.manualCommand?.display == "curl -sS https://starship.rs/install.sh | sh")
        #expect(await box.updater(script: try box.script(to: "1.26.0")).update(readOnly) == .notOffered)
        #expect(box.read("ARGS") == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.bin.path)

        try FileManager.default.removeItem(at: box.binary)
        let loose = box.root.appendingPathComponent("starship-elsewhere")
        try Data(Sandbox.starship(version: "1.25.1").utf8).write(to: loose)
        try FileManager.default.createSymbolicLink(atPath: box.binary.path, withDestinationPath: loose.path)
        let linked = try await box.status()
        #expect(linked.withheld == .unsupportedInstaller)
        #expect(linked.manualCommand == nil)

        let path = box.binary.path
        #expect(await box.check().status(of: StarshipInstall(path: path, binary: path, version: "1.25.1", quarantined: true),
                                         busy: nil).withheld == .unverified)
    }

    /// `-y -b <dir> -v v<target>`, the script's own variables removed, a PATH
    /// without sudo or the bin directory. Mutations: drop `-v`; keep the
    /// inherited `BIN_DIR`; put the bin directory on PATH.
    @Test func updatesThroughTheScript() async throws {
        let box = try Sandbox()
        try box.install(version: "1.25.1")
        let outcome = await box.updater(script: try box.script(to: "1.26.0")).update(try await box.status())
        #expect(outcome == .updated(version: "1.26.0"))
        #expect(box.read("ARGS") == "-y -b \(box.bin.path) -v v1.26.0\n")
        let env = box.read("ENV") ?? ""
        #expect(!env.contains("BIN_DIR=") && !env.contains("VERSION="))
        #expect(env.contains("KEEP=1"))
        let path = (box.read("PATHLS") ?? "").split(separator: "\n")
        #expect(path.contains("curl") && path.contains("tar"))
        #expect(!path.contains("sudo") && !path.contains("starship"))
    }

    /// Mutation: report `.updated` without verifying the result.
    @Test func anUnpublishedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "1.25.1")
        let script = try box.script(to: "1.26.0", publishNew: false)
        box.publish("1.26.0", "the real 1.26.0")
        guard case .failed(let message, _) = await box.updater(script: script).update(try await box.status()) else {
            Issue.record("an unpublished result read as updated"); return
        }
        #expect(message.contains("is not the starship 1.26.0"))
    }

    /// The script's `x <reason>`, colours off, with the exit status.
    @Test func aFailedScriptSaysWhy() async throws {
        let box = try Sandbox()
        try box.install(version: "1.25.1")
        let script = try box.script(to: "1.26.0", fail: "Superuser not granted, aborting installation")
        guard case .failed(let message, _) = await box.updater(script: script).update(try await box.status()) else {
            Issue.record("a failed script read as updated"); return
        }
        #expect(message == "Superuser not granted, aborting installation (exit 1)")
        #expect(!StarshipUpdater.isInstaller(Data("<html>".utf8)))
    }

    @Test func busyIsTheDownloadOrOurScript() {
        #expect(StarshipActivity.busy(processes: [.init(pid: 3, arguments: [
            "curl", "--fail", "--silent", "--location", "--output", "/tmp/x.tar.gz",
            "https://github.com/starship/starship/releases/latest/download/starship-aarch64-apple-darwin.tar.gz"])]) == .download(3))
        #expect(StarshipActivity.busy(processes: [.init(pid: 4, arguments: ["/bin/sh", "/tmp/d/starship-install.sh", "-y"])])
            == .script(4))
        #expect(StarshipActivity.busy(processes: [.init(pid: 5, arguments: ["starship", "prompt"])]) == nil)
    }

    /// release-please's `###` headings survive; the version heading does not
    /// become a change. Excerpt of 1.26.0's body (fetched 2026-10-09).
    @Test func releaseNotesKeepTheirHeadings() throws {
        let body = """
            ## [1.26.0](https://github.com/starship/starship/compare/v1.25.1...v1.26.0) (2026-06-28)


            ### Features

            * **git:** enable sha256 support ([#7531](https://github.com/starship/starship/issues/7531)) ([e1418b2](https://github.com/starship/starship/commit/e1418b212974b1ebc7274c2813b0a1b74d7c428d))


            ### Bug Fixes

            * **nodejs:** avoid deno project files ([#7478](https://github.com/starship/starship/issues/7478)) ([96c1f90](https://github.com/starship/starship/commit/96c1f90eeb9acd255ec28c2a00918dba2a474997))
            """
        let releases: [[String: Any]] = [
            ["tag_name": "v1.26.0", "prerelease": false, "draft": false, "published_at": "2026-06-28T17:02:47Z", "body": body],
        ]
        let log = try #require(StarshipChangelog.parse(String(decoding: try JSONSerialization.data(withJSONObject: releases), as: UTF8.self)))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "1.26.0")
        #expect(entry.content.contains(.heading("Features")))
        #expect(entry.content.contains(.heading("Bug Fixes")))
        #expect(entry.items.count == 2)
        #expect(entry.items.first?.hasPrefix("**git:** enable sha256 support") == true)
    }
}
