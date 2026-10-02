import Testing
import Foundation
import CryptoKit
@testable import DuoUpdaterCore

/// Running uv's one-click update: the trust rule at the click (signature, or the
/// published release's hash), what is run with which environment, and the check
/// of what the update left.
///
/// "uv" here is a `#!/bin/sh` script in a temporary HOME whose second line
/// names its signer for the injected check (`# vendor`, `# adhoc`). Its `self
/// update` does what the real one does to the disk — new `uv` and `uvx` by
/// rename, the receipt rewritten — and prints the lines uv prints (measured
/// 2026-10-02). The busy check, the base environment, the release download and
/// the unpacking are injected: nothing here reads the host's process table,
/// runs the real uv or reaches the network.
@Suite struct UvUpdaterTests {

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var uv: URL { bin.appendingPathComponent("uv") }
        var uvx: URL { bin.appendingPathComponent("uvx") }
        let verified: UvVerifiedFiles

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("uv-updater-tests-\(UUID().uuidString)")
            verified = UvVerifiedFiles(fileURL: root.appendingPathComponent("verified.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// The fake uv and uvx at `version`, signed as `signer`. `selfUpdate` is
        /// the shell body run for `uv self update`.
        func install(version: String, signer: String, selfUpdate: String) throws {
            let script = """
                #!/bin/sh
                # \(signer)
                if [ "$1" = self ] && [ "$2" = update ]; then
                \(selfUpdate)
                fi
                """
            try Data(script.utf8).write(to: uv)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uv.path)
            try Data("#!/bin/sh\n# \(signer)\n# uvx \(version)\n".utf8).write(to: uvx)
            try Data(version.utf8).write(to: bin.appendingPathComponent("VERSION"))
            try receipt(version)
        }

        func receipt(_ version: String, prefix: String? = nil) throws {
            let json = """
                {"binaries":["uv","uvx"],"install_layout":"flat","install_prefix":"\(prefix ?? bin.path)",\
                "modify_path":true,"provider":{"source":"cargo-dist","version":"0.30.2"},\
                "source":{"app_name":"uv","name":"uv","owner":"astral-sh","release_type":"github"},"version":"\(version)"}
                """
            let url = UvReceipt.location(home: home)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(json.utf8).write(to: url)
        }

        /// What the installer does: new files moved into place, the receipt
        /// rewritten. `signer` is what the new files are signed as.
        func installerBody(to version: String, signer: String = "vendor", receipt: String? = nil) -> String {
            let receiptPath = UvReceipt.location(home: home).path
            return """
                echo "$@" > "\(root.path)/ARGS"
                env > "\(root.path)/ENV"
                echo 'info: Checking for updates...' >&2
                printf '#!/bin/sh\\n# \(signer)\\n' > "\(bin.path)/uv.new" && chmod 755 "\(bin.path)/uv.new"
                printf '#!/bin/sh\\n# \(signer)\\n# uvx \(version)\\n' > "\(bin.path)/uvx.new"
                mv "\(bin.path)/uv.new" "\(bin.path)/uv"
                mv "\(bin.path)/uvx.new" "\(bin.path)/uvx"
                echo \(version) > "\(bin.path)/VERSION"
                sed -i '' 's/"version":"[0-9.]*"}$/"version":"\(receipt ?? version)"}/' "\(receiptPath)"
                echo 'success: Upgraded uv from v0.9.18 to v\(version)! https://github.com/astral-sh/uv/releases/tag/\(version)' >&2
                """
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ARGS").path) }

        func read(_ name: String) -> String? {
            try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        }

        var scanner: UvScanner {
            UvScanner(
                home: home,
                // The signer is the second line: the script's body names the
                // signer of the files its `self update` writes.
                checkSignature: { url in
                    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    let signer = text.split(separator: "\n").dropFirst().first ?? ""
                    if signer == "# vendor" { return .vendor }
                    if signer == "# adhoc" { return .adHoc }
                    return .otherSigner
                },
                readVersion: { url in
                    try? String(contentsOf: url.deletingLastPathComponent().appendingPathComponent("VERSION"),
                                encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                },
                isQuarantined: { _ in false },
                verified: verified)
        }

        /// The release as "published": `archive` is its bytes, unpacking it
        /// yields `uv`/`uvx` with `contents` (the installed files' own, unless
        /// told otherwise).
        func verifier(
            published: [String: String]? = nil, fetched: Lines? = nil, fetchFails: Bool = false,
            digest: String? = nil
        ) -> UvVerifier {
            let archive = Data("ARCHIVE-BYTES".utf8)
            let sha = digest ?? SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
            let contents = published ?? [
                "uv": (try? String(contentsOf: uv, encoding: .utf8)) ?? "",
                "uvx": (try? String(contentsOf: uvx, encoding: .utf8)) ?? "",
            ]
            return UvVerifier(
                fetch: { url in
                    fetched?.add(url.absoluteString)
                    if fetchFails { throw UvRelease.Failure.http(503) }
                    return url.pathExtension == "sha256" ? Data("\(sha)  uv-aarch64-apple-darwin.tar.gz\n".utf8) : archive
                },
                extract: { file, directory in
                    #expect(try Data(contentsOf: file) == archive)
                    let dir = directory.appendingPathComponent("uv-aarch64-apple-darwin")
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    for (name, text) in contents { try Data(text.utf8).write(to: dir.appendingPathComponent(name)) }
                },
                architecture: { _ in "aarch64" },
                verified: verified)
        }

        func status() async throws -> CLIToolStatus {
            let install = try #require(await scanner.scan().first)
            return await UvCheck(latest: { _ in "0.12.21" }).statuses(of: [install], busy: nil)[0]
        }
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    func updater(
        _ box: Sandbox, verifier: UvVerifier? = nil, busy: @escaping UvUpdater.BusyCheck = { nil },
        environment: [String: String] = [:]
    ) -> UvUpdater {
        UvUpdater(busy: busy, scanner: box.scanner, verifier: verifier ?? box.verifier(), environment: { environment })
    }

    /// The child reads the receipt the check read: `HOME` is the scanner's, the
    /// variables that would point uv at another receipt are gone, the install
    /// directory leads `PATH`, the proxy is passed through. Kills: keeping
    /// `XDG_CONFIG_HOME` / `AXOUPDATER_CONFIG_*`.
    @Test func runsSelfUpdateAndChecksWhatItLeft() async throws {
        let box = try Sandbox()
        try box.install(version: "0.12.20", signer: "vendor", selfUpdate: box.installerBody(to: "0.12.21"))
        let status = try await box.status()
        #expect(status.oneClick?.arguments == ["self", "update"])
        let lines = Lines()
        let outcome = await updater(box, environment: [
            "HOME": "/ZZFixture-elsewhere", "PATH": "/somewhere/else", "XDG_CONFIG_HOME": "/ZZFixture-xdg",
            "AXOUPDATER_CONFIG_PATH": "/ZZFixture-axo", "HTTPS_PROXY": "http://127.0.0.1:6152",
        ]).update(status) { lines.add($0) }
        #expect(outcome == .updated(version: "0.12.21"))
        #expect(box.read("ARGS") == "self update\n")
        let env = try #require(box.read("ENV"))
        #expect(env.contains("\nHOME=\(box.home.path)\n") || env.hasPrefix("HOME=\(box.home.path)\n"))
        #expect(env.contains("PATH=\(box.bin.path):\(CLIToolCommandRunner.systemPath)\n"))
        #expect(env.contains("HTTPS_PROXY=http://127.0.0.1:6152"))
        #expect(!env.contains("XDG_CONFIG_HOME"))
        #expect(!env.contains("AXOUPDATER_CONFIG_PATH"))
        #expect(lines.all.contains { $0.hasPrefix("success: Upgraded uv from v0.9.18 to v0.12.21!") })
    }

    /// An unsigned copy is compared with the published release before it runs,
    /// and the answer is remembered for the files as they were.
    @Test func unsignedCopyIsVerifiedAgainstTheReleaseFirst() async throws {
        let box = try Sandbox()
        try box.install(version: "0.9.18", signer: "adhoc", selfUpdate: box.installerBody(to: "0.12.21"))
        let status = try await box.status()
        #expect(status.oneClick != nil)
        let fetched = Lines()
        let identity = try #require(UvVerifiedFiles.identity(of: box.uv.path, uvx: box.uvx.path))
        let outcome = await updater(box, verifier: box.verifier(fetched: fetched)).update(status)
        #expect(outcome == .updated(version: "0.12.21"))
        #expect(fetched.all == [
            "https://github.com/astral-sh/uv/releases/download/0.9.18/uv-aarch64-apple-darwin.tar.gz.sha256",
            "https://github.com/astral-sh/uv/releases/download/0.9.18/uv-aarch64-apple-darwin.tar.gz",
        ])
        #expect(box.ran)
        // Remembered under the identity the click saw (the files are new now).
        let stored = try JSONDecoder().decode(
            [String: UvVerifiedFiles.Entry].self, from: Data(contentsOf: box.verified.fileURL))
        #expect(stored[box.uv.path]?.verdict == .matches)
        #expect(stored[box.uv.path]?.identity == identity)
    }

    /// An update started elsewhere while the first click checks the archive is
    /// not raced: busy is asked again after the check.
    ///
    /// Mutation: drop the busy check after the trust block.
    @Test func busyAfterTheHashCheckRunsNothing() async throws {
        let box = try Sandbox()
        try box.install(version: "0.9.18", signer: "adhoc", selfUpdate: box.installerBody(to: "0.12.21"))
        let status = try await box.status()
        let asked = Lines()
        let outcome = await updater(box, busy: {
            asked.add("asked")
            return asked.all.count > 1 ? .installer(77) : nil
        }).update(status)
        #expect(outcome == .busy("the uv installer is running (pid 77)"))
        #expect(!box.ran)
    }

    /// Kills: running the update without the verifier's verdict (treating
    /// `.differs` as a pass), and not remembering it.
    @Test func unsignedCopyThatIsNotTheReleaseIsNeverRun() async throws {
        let box = try Sandbox()
        try box.install(version: "0.9.18", signer: "adhoc", selfUpdate: box.installerBody(to: "0.12.21"))
        let status = try await box.status()
        let verifier = box.verifier(published: ["uv": "#!/bin/sh\n# adhoc\n# the real one\n", "uvx": ""])
        let outcome = await updater(box, verifier: verifier).update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "not run: \(box.uv.path) is not the uv Astral published for uv 0.9.18")
        #expect(!box.ran)
        // The next check says so without a download.
        let again = try await box.status()
        #expect(again.withheld == .unverified)
        #expect(again.oneClick == nil)
        // And a click on the old status refuses without fetching anything.
        let fetched = Lines()
        let refused = await updater(box, verifier: box.verifier(fetched: fetched)).update(status)
        guard case .failed = refused else { Issue.record("\(refused)"); return }
        #expect(fetched.all.isEmpty)
        #expect(!box.ran)
    }

    /// uvx is part of the comparison. Kills: comparing `uv` alone.
    @Test func uvxMustMatchToo() async throws {
        let box = try Sandbox()
        try box.install(version: "0.9.18", signer: "adhoc", selfUpdate: box.installerBody(to: "0.12.21"))
        let uvText = try String(contentsOf: box.uv, encoding: .utf8)
        let outcome = await updater(box, verifier: box.verifier(published: ["uv": uvText, "uvx": "other"]))
            .update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.hasSuffix("is not the uvx Astral published for uv 0.9.18"))
        #expect(!box.ran)
    }

    /// A check that could not be made remembers nothing and runs nothing.
    /// Kills: dropping the archive-digest comparison (`couldNotVerify`).
    @Test func failedVerificationRunsNothing() async throws {
        let box = try Sandbox()
        try box.install(version: "0.9.18", signer: "adhoc", selfUpdate: box.installerBody(to: "0.12.21"))
        let status = try await box.status()
        let offline = await updater(box, verifier: box.verifier(fetchFails: true)).update(status)
        guard case .failed(let message, _) = offline else { Issue.record("\(offline)"); return }
        #expect(message.hasPrefix("not run: could not download uv 0.9.18 to compare"))
        let wrongDigest = await updater(box, verifier: box.verifier(digest: String(repeating: "ab", count: 32))).update(status)
        guard case .failed(let digestMessage, _) = wrongDigest else { Issue.record("\(wrongDigest)"); return }
        #expect(digestMessage == "not run: the uv 0.9.18 archive did not match the sha256 Astral publishes for it")
        #expect(!box.ran)
        #expect(!FileManager.default.fileExists(atPath: box.verified.fileURL.path))
        #expect(try await box.status().withheld == nil)
    }

    @Test func aRememberedMatchSkipsTheDownload() async throws {
        let box = try Sandbox()
        try box.install(version: "0.9.18", signer: "adhoc", selfUpdate: box.installerBody(to: "0.12.21"))
        let identity = try #require(UvVerifiedFiles.identity(of: box.uv.path, uvx: box.uvx.path))
        box.verified.remember(.matches, for: box.uv.path, identity: identity)
        let fetched = Lines()
        let outcome = await updater(box, verifier: box.verifier(fetched: fetched)).update(try await box.status())
        #expect(outcome == .updated(version: "0.12.21"))
        #expect(fetched.all.isEmpty)
    }

    /// Kills: dropping the busy re-check at the click.
    @Test func busyAtTheClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.install(version: "0.12.20", signer: "vendor", selfUpdate: box.installerBody(to: "0.12.21"))
        let outcome = await updater(box, busy: { .installer(77) }).update(try await box.status())
        #expect(outcome == .busy("the uv installer is running (pid 77)"))
        #expect(!box.ran)
    }

    /// The receipt moved to another directory since the check: `uv self update`
    /// would refuse, and the copy is no longer the one checked. Kills: dropping
    /// the `layout == .standalone` re-check.
    @Test func aCopyNoLongerStandaloneAtTheClickIsNotRun() async throws {
        let box = try Sandbox()
        try box.install(version: "0.12.20", signer: "vendor", selfUpdate: box.installerBody(to: "0.12.21"))
        let status = try await box.status()
        try box.receipt("0.12.20", prefix: box.home.appendingPathComponent("elsewhere").path)
        let outcome = await updater(box).update(status)
        // Said as what it is: the trust checks after it would also refuse (a
        // copy no receipt names has no receipt version), but with the wrong
        // reason.
        #expect(outcome == .failed(
            message: "not run: \(box.uv.path) is no longer the standalone uv that was checked", output: ""))
        #expect(!box.ran)
    }

    /// A vendor-signed copy replaced by an unsigned one since the check is not
    /// run on the strength of the old signature. Kills: dropping the final
    /// "not signed by Astral" branch of the click-time trust check.
    @Test func signatureIsAskedAgainAtTheClick() async throws {
        let box = try Sandbox()
        try box.install(version: "0.12.20", signer: "vendor", selfUpdate: box.installerBody(to: "0.12.21"))
        let status = try await box.status()
        try box.install(version: "0.12.20", signer: "other", selfUpdate: box.installerBody(to: "0.12.21"))
        let outcome = await updater(box).update(status)
        #expect(outcome == .failed(message: "not run: \(box.uv.path) is not signed by Astral", output: ""))
        #expect(!box.ran)
    }

    /// What the update left must carry Astral's Team ID. Kills: dropping the
    /// post-update signature check.
    @Test func anUnsignedResultIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(version: "0.12.20", signer: "vendor", selfUpdate: box.installerBody(to: "0.12.21", signer: "adhoc"))
        let outcome = await updater(box).update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "uv self update finished, but the new uv is not signed by Astral (Team 2DC432GLL2)")
    }

    /// Kills: dropping the post-update receipt comparison.
    @Test func aResultThatDisagreesWithItsReceiptIsAFailure() async throws {
        let box = try Sandbox()
        try box.install(
            version: "0.12.20", signer: "vendor", selfUpdate: box.installerBody(to: "0.12.21", receipt: "0.12.20"))
        let outcome = await updater(box).update(try await box.status())
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "uv self update finished, but the new uv reads as 0.12.21 and its receipt as 0.12.20")
    }

    /// uv's own `error:` line, without its prefix — what 0.9.18 printed through
    /// a dead proxy (2026-10-02). Kills: falling to the shared last-line rule,
    /// which would show the context-free root cause.
    @Test func failureIsUvsErrorLine() async throws {
        let box = try Sandbox()
        try box.install(version: "0.12.20", signer: "vendor", selfUpdate: """
            echo 'info: Checking for updates...' >&2
            echo 'error: error sending request for url (https://api.github.com/repos/astral-sh/uv/releases)' >&2
            echo '  Caused by: client error (Connect)' >&2
            echo '  Caused by: Connection refused (os error 61)' >&2
            exit 2
            """)
        let outcome = await updater(box).update(try await box.status())
        #expect(outcome == .failed(
            message: "error sending request for url (https://api.github.com/repos/astral-sh/uv/releases)",
            output: """
                info: Checking for updates...
                error: error sending request for url (https://api.github.com/repos/astral-sh/uv/releases)
                  Caused by: client error (Connect)
                  Caused by: Connection refused (os error 61)
                """))
    }

    @Test func notOfferedRunsNothing() async throws {
        let box = try Sandbox()
        try box.install(version: "0.12.21", signer: "vendor", selfUpdate: box.installerBody(to: "0.12.21"))
        #expect(await updater(box).update(try await box.status()) == .notOffered)
        #expect(!box.ran)
    }
}
