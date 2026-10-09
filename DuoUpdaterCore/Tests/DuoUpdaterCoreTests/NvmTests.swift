import Testing
import Foundation
@testable import DuoUpdaterCore

/// nvm: finding it where its installer puts it — and not where Homebrew does —
/// reading its version out of `nvm.sh`, its verdict, its one-click (the newer
/// tag's installer) and its release notes. The release API, the installer, the
/// git found and the process table are injected; nothing here runs nvm or git,
/// or reaches the network. The "installer" is a bash stand-in that records what
/// it was given and copies a staged `nvm.sh` into `$NVM_DIR`.
@Suite struct NvmTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-nvm-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// The lines around nvm's version as v0.40.8's `nvm.sh` has them,
        /// colour-code `nvm_echo` lines included.
        static func nvmSH(_ version: String) -> String {
            """
            nvm_print_color_code() {
              case "${1-}" in
                'r') nvm_echo '0;31m' ;;
                'g') nvm_echo '0;32m' ;;
              esac
            }
            nvm() {
              case $COMMAND in
                "--version" | "-v")
                  nvm_echo '\(version)'
                ;;
                "unload")
              esac
            }
            """
        }

        @discardableResult
        func install(_ version: String, in relative: String = ".nvm", git: Bool = true) throws -> URL {
            let dir = home.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if git { try FileManager.default.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true) }
            let file = dir.appendingPathComponent("nvm.sh")
            try Data(Self.nvmSH(version).utf8).write(to: file)
            return file
        }

        var scanner: NvmScanner { NvmScanner(home: home) }

        static let git = "/ZZFixture-git/bin/git"

        func check(latest: String = "0.40.8", status: Int = 200, git: String? = Sandbox.git) -> NvmCheck {
            let release = NvmRelease(fetch: { url, _ in
                #expect(url == NvmRelease.latestURL)
                return (Data(#"{"tag_name": "v\#(latest)", "assets": []}"#.utf8), status, status == 200 ? nil : "0")
            })
            return NvmCheck(latest: { try await release.latest() }, git: { git })
        }

        func status(
            latest: String = "0.40.8", git: String? = Sandbox.git, busy: NvmActivity.Busy? = nil
        ) async throws -> CLIToolStatus {
            let install = try #require(scanner.scan().first)
            return await check(latest: latest, git: git).status(of: install, busy: busy)
        }

        /// The installer stand-in: records its environment, its `PATH`'s
        /// programs and where its `git` points, then copies a staged `nvm.sh`
        /// of `version` into `$NVM_DIR`, as the real one rewrites it there.
        func installer(installs version: String?, body: String? = nil) throws -> Data {
            var copy = "echo nothing"
            if let version {
                let staged = root.appendingPathComponent("staged-\(version)")
                try Data(Self.nvmSH(version).utf8).write(to: staged)
                copy = #"/bin/cp "\#(staged.path)" "$NVM_DIR/nvm.sh""#
            }
            return Data("""
                #!/usr/bin/env bash
                nvm_do_install() {
                  if [ "${PROFILE-}" = '/dev/null' ] ; then echo; fi
                }
                /usr/bin/env > "\(root.path)/ENV"
                /bin/ls "$PATH" > "\(root.path)/PATHLS"
                /bin/cat "$PATH/git" > "\(root.path)/GIT"
                \(body ?? copy)
                """.utf8)
        }

        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ENV").path) }
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }

        func updater(
            script: Data, git: String? = Sandbox.git, busy: @escaping NvmUpdater.BusyCheck = { nil },
            environment: [String: String] = ["KEEP": "1"]
        ) -> NvmUpdater {
            NvmUpdater(
                busy: busy, scanner: scanner, git: { git },
                fetchScript: { url in
                    #expect(url.absoluteString == "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh")
                    return script
                },
                environment: { environment })
        }
    }

    // MARK: - The version

    /// The `--version` case, in both spellings nvm has used, and never one of
    /// the colour-code `nvm_echo` lines. Mutations: anchor on `nvm_echo '`
    /// alone; drop the `| "-v"` option; accept disagreeing versions.
    @Test func readsTheVersionCase() {
        #expect(NvmScanner.version(in: Sandbox.nvmSH("0.40.8")) == "0.40.8")
        #expect(NvmScanner.version(in: "    \"--version\")\n      nvm_echo '0.35.3'\n    ;;") == "0.35.3")
        #expect(NvmScanner.version(in: "'r') nvm_echo '0;31m' ;;\nnvm_echo '1.2.3'") == nil)
        #expect(NvmScanner.version(in: Sandbox.nvmSH("0.40.8") + Sandbox.nvmSH("0.40.7")) == nil)
    }

    // MARK: - Finding it

    /// The git clone and the bare-files install, in either default directory.
    @Test func findsBothLayoutsInBothPlaces() throws {
        let box = try Sandbox()
        let cloned = try box.install("0.40.7")
        let bare = try box.install("0.40.6", in: ".config/nvm", git: false)
        #expect(box.scanner.scan() == [
            NvmInstall(path: cloned.path, version: "0.40.7", layout: .git),
            NvmInstall(path: bare.path, version: "0.40.6", layout: .script),
        ])
    }

    /// Homebrew's stub, as on this Mac on 2026-10-09: `~/.nvm/nvm.sh` a link
    /// into the keg (`opt/nvm` → `Cellar/nvm/0.40.8`). It is brew's, and makes
    /// no row. Mutation: follow the link.
    @Test func homebrewsStubIsNotListed() throws {
        let box = try Sandbox()
        let keg = box.root.appendingPathComponent("ZZFixture-homebrew/Cellar/nvm/0.40.8/libexec")
        try FileManager.default.createDirectory(at: keg, withIntermediateDirectories: true)
        try Data(Sandbox.nvmSH("0.40.8").utf8).write(to: keg.appendingPathComponent("nvm.sh"))
        try Data("#!/usr/bin/env bash\n".utf8).write(to: keg.appendingPathComponent("nvm-exec"))
        let opt = box.root.appendingPathComponent("ZZFixture-homebrew/opt")
        try FileManager.default.createDirectory(at: opt, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: opt.appendingPathComponent("nvm").path,
                                                   withDestinationPath: "../Cellar/nvm/0.40.8")
        let dir = box.home.appendingPathComponent(".nvm")
        for name in ["alias", "versions", ".cache"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        for name in ["nvm.sh", "nvm-exec"] {
            try FileManager.default.createSymbolicLink(
                atPath: dir.appendingPathComponent(name).path,
                withDestinationPath: opt.appendingPathComponent("nvm/libexec/\(name)").path)
        }
        #expect(box.scanner.scan().isEmpty)
    }

    /// `~/.config/nvm` a link to `~/.nvm` is one install. Mutation: no dedupe.
    @Test func oneDirectoryUnderTwoNamesIsOneInstall() throws {
        let box = try Sandbox()
        let file = try box.install("0.40.7")
        try FileManager.default.createDirectory(at: box.home.appendingPathComponent(".config"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: box.home.appendingPathComponent(".config/nvm").path,
                                                   withDestinationPath: file.deletingLastPathComponent().path)
        #expect(box.scanner.scan().map(\.path) == [file.path])
    }

    @Test func aDirectoryWithoutNvmIsNothing() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.home.appendingPathComponent(".nvm/versions/node"), withIntermediateDirectories: true)
        #expect(box.scanner.scan().isEmpty)
    }

    // MARK: - The verdict

    /// A newer tag is a click: the README's update, the newer tag's installer,
    /// in either layout. Mutation: name the installed tag instead of the latest.
    @Test func anUpdateIsAClick() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let status = try await box.status()
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "0.40.7")
        #expect(status.latestVersion == "0.40.8")
        #expect(status.withheld == nil)
        #expect(status.manualCommand == nil)
        #expect(status.oneClick?.display
            == "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash")
    }

    /// A directory this user cannot write keeps today's command to copy.
    /// Mutation: drop the `writable` gate.
    @Test func aReadOnlyDirectoryIsTheCommandOnly() async throws {
        let box = try Sandbox()
        let file = try box.install("0.40.7", git: false)
        let dir = file.deletingLastPathComponent().path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir) }
        let status = try await box.status()
        #expect(status.oneClick == nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.manualCommand?.display
            == "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash")
        if case .nvm(let install) = status.detail { #expect(!install.writable) } else { Issue.record("no nvm detail") }
    }

    /// A checkout needs a git that is not `/usr/bin/git`'s shim; the bare files
    /// need none. Mutations: drop the git gate; ask it of the script layout too.
    @Test func aCheckoutWithoutARealGitIsNoClick() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let noGit = try await box.status(git: nil)
        #expect(noGit.oneClick == nil)
        #expect(noGit.withheld == .updaterMissing)
        #expect(noGit.manualCommand == nil)

        let bare = try Sandbox()
        try bare.install("0.40.7", in: ".config/nvm", git: false)
        let script = try await bare.status(git: nil)
        #expect(script.oneClick != nil)
        #expect(script.withheld == nil)
    }

    /// Mutation: drop the busy gate.
    @Test func aRunUnderWayIsBusy() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let status = try await box.status(busy: .installer(9))
        #expect(status.oneClick == nil)
        #expect(status.withheld == .busy)
        #expect(status.note == "nvm's installer is running (pid 9)")
    }

    @Test func otherVerdicts() async throws {
        let box = try Sandbox()
        try box.install("0.40.8")
        let install = try #require(box.scanner.scan().first)
        let current = await box.check().status(of: install, busy: nil)
        #expect(current.state == .upToDate)
        #expect(current.oneClick == nil)
        #expect(current.manualCommand == nil)
        #expect(await box.check(latest: "0.40.7").status(of: install, busy: nil).state == .ahead)
        #expect(await box.check(status: 403).status(of: install, busy: nil).withheld == .rateLimited)
        #expect(await box.check(status: 502).status(of: install, busy: nil).withheld == .channelUnreadable)

        let unreadable = NvmInstall(path: install.path, version: nil, problem: .versionUnreadable)
        #expect(await box.check().status(of: unreadable, busy: nil).withheld == .versionUnreadable)
    }

    // MARK: - git

    /// The first candidate that is a real file outside `/usr/bin`: a link to the
    /// shim is passed over, whatever its name. Mutations: drop the `/usr/bin`
    /// check; return the candidate rather than what it resolves to.
    @Test func gitIsNeverTheShim() {
        let facts = [
            "/ZZFixture-a/git": "/usr/bin/git",
            "/ZZFixture-b/git": "/ZZFixture-Cellar/git/2.51.0/bin/git",
        ]
        #expect(NvmUpdater.git(candidates: ["/ZZFixture-none/git", "/ZZFixture-a/git", "/ZZFixture-b/git"],
                               resolve: { facts[$0] })
            == "/ZZFixture-Cellar/git/2.51.0/bin/git")
        #expect(NvmUpdater.git(candidates: ["/usr/bin/git", "/ZZFixture-a/git"], resolve: { facts[$0] ?? $0 }) == nil)
        #expect(!NvmUpdater.gitCandidates.contains { $0.hasPrefix("/usr/bin/") })
    }

    // MARK: - The update

    /// The bare files: `bash <install.sh>` with `NVM_DIR` the install's own
    /// directory, `PROFILE=/dev/null`, `HOME` the scan's, a `PATH` of the
    /// script's programs only — no git, `sudo`, `xcode-select` or `which` — and
    /// the variables that would redirect it gone. Mutations: drop any `overrides`
    /// entry or the `BASH_FUNC_` filter; skip `NVM_DIR` or `PROFILE`; put git on
    /// the bare files' `PATH`.
    @Test func updatesTheBareFilesInPlace() async throws {
        let box = try Sandbox()
        try box.install("0.40.7", in: ".config/nvm", git: false)
        let status = try await box.status()
        let inherited = [
            "KEEP": "1", "NVM_SOURCE": "https://example.com/nvm.sh", "NVM_INSTALL_VERSION": "v0.1.0",
            "NVM_INSTALL_GITHUB_REPO": "someone/nvm", "METHOD": "git", "NODE_VERSION": "22", "NVM_ENV": "x",
            "XDG_CONFIG_HOME": "/ZZFixture-xdg", "BASH_ENV": "/ZZFixture-bashenv", "SHELLOPTS": "xtrace",
            "BASH_FUNC_git%%": "() {  /usr/bin/true\n}",
        ]
        let outcome = await box.updater(script: try box.installer(installs: "0.40.8"), environment: inherited).update(status)
        #expect(outcome == .updated(version: "0.40.8"))
        let env = try #require(box.read("ENV"))
        #expect(env.contains("NVM_DIR=\(box.home.path)/.config/nvm\n"))
        #expect(env.contains("PROFILE=/dev/null\n"))
        #expect(env.contains("HOME=\(box.home.path)\n"))
        #expect(env.contains("KEEP=1\n"))
        for key in inherited.keys where key != "KEEP" {
            #expect(!env.contains("\(key)"), "\(key) reached the installer")
        }
        let tools = Set(try #require(box.read("PATHLS")).split(separator: "\n").map(String.init))
        #expect(tools == Set(NvmUpdater.defaultTools.keys))
        #expect(tools.isDisjoint(with: ["git", "sudo", "xcode-select", "which"]))
        #expect(box.scanner.scan().map(\.version) == ["0.40.8"])
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent(".nvm").path))
    }

    /// A checkout: `git` on the `PATH` is a wrapper that `exec`s the real one
    /// found, beside the same programs. Mutation: leave it off; link it.
    @Test func updatesACheckoutWithTheGitFound() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let status = try await box.status()
        let outcome = await box.updater(script: try box.installer(installs: "0.40.8")).update(status)
        #expect(outcome == .updated(version: "0.40.8"))
        #expect(box.read("GIT") == "#!/bin/sh\nexec '\(Sandbox.git)' \"$@\"\n")
        let tools = Set(try #require(box.read("PATHLS")).split(separator: "\n").map(String.init))
        #expect(tools == Set(NvmUpdater.defaultTools.keys).union(["git"]))
        #expect(try #require(box.read("ENV")).contains("NVM_DIR=\(box.home.path)/.nvm\n"))
    }

    /// The installer's own last line and its exit status are the row's reason;
    /// the whole output is the detail pane's. Exit 0 with `nvm.sh` not at the
    /// target is a failure too. Mutations: drop the exit status; trust exit 0.
    @Test func whatTheInstallerLeftIsReadBack() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let status = try await box.status()
        let failing = try box.installer(installs: nil, body: """
            echo "=> nvm is already installed in $NVM_DIR, trying to update using git"
            echo "Failed to update nvm with v0.40.8, run 'git fetch' in $NVM_DIR yourself." >&2
            exit 1
            """)
        let failed = await box.updater(script: failing).update(status)
        guard case .failed(let message, let output) = failed else { Issue.record("expected failed, got \(failed)"); return }
        #expect(message == "Failed to update nvm with v0.40.8, run 'git fetch' in \(box.home.path)/.nvm yourself. (exit 1)")
        #expect(output.contains("trying to update using git"))

        let unchanged = await box.updater(script: try box.installer(installs: nil)).update(status)
        guard case .failed(let still, _) = unchanged else { Issue.record("expected failed, got \(unchanged)"); return }
        #expect(still == "install.sh finished, but nvm.sh is still 0.40.7")

        let other = await box.updater(script: try box.installer(installs: "0.40.6")).update(status)
        guard case .failed(let wrong, _) = other else { Issue.record("expected failed, got \(other)"); return }
        #expect(wrong == "install.sh finished, but nvm.sh is still 0.40.6")
    }

    /// Asked again at the click: a run under way, the install changed, a
    /// directory gone read-only, git gone from a checkout, a download that is
    /// not nvm's installer. Nothing is run in any of them. Mutations: drop any one.
    @Test func theClickAsksTheGatesAgain() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let status = try await box.status()
        let script = try box.installer(installs: "0.40.8")

        #expect(await box.updater(script: script, busy: { .installer(7) }).update(status)
            == .busy("nvm's installer is running (pid 7)"))
        let noGit = await box.updater(script: script, git: nil).update(status)
        guard case .failed(let gitWhy, _) = noGit else { Issue.record("expected failed, got \(noGit)"); return }
        #expect(gitWhy.contains("/usr/bin/git"))
        // Valid bash that would run — and leave ENV — were it not refused.
        let notInstaller = await box.updater(script: Data("#!/usr/bin/env bash\n/usr/bin/env > \"\(box.root.path)/ENV\"\n".utf8))
            .update(status)
        guard case .failed = notInstaller else { Issue.record("expected failed, got \(notInstaller)"); return }

        let dir = box.home.appendingPathComponent(".nvm").path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        let readOnly = await box.updater(script: script).update(status)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir)
        guard case .failed(let why, _) = readOnly else { Issue.record("expected failed, got \(readOnly)"); return }
        #expect(why.contains("sudo"))

        try box.install("0.40.6")
        let moved = await box.updater(script: script).update(status)
        guard case .failed = moved else { Issue.record("expected failed, got \(moved)"); return }
        #expect(!box.ran)
    }

    @Test func aStatusWithoutTheClickRunsNothing() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let status = try await box.status(git: nil)
        #expect(await box.updater(script: try box.installer(installs: "0.40.8")).update(status) == .notOffered)
        #expect(!box.ran)
    }

    // MARK: - Activity

    /// Only DuoUpdater's own run of the installer. Mutation: match any bash.
    @Test func busyIsOurInstaller() {
        typealias P = ClaudeCodeActivity.Process
        #expect(NvmActivity.busy(processes: [P(pid: 3, arguments: ["/bin/bash", "/var/folders/x/duo-nvm-1/nvm-install-AB.sh"])])
            == .installer(3))
        #expect(NvmActivity.busy(processes: [P(pid: 5, arguments: ["bash"]), P(pid: 6, arguments: ["/bin/bash", "install.sh"])]) == nil)
    }

    // MARK: - Release notes

    /// nvm's bodies: `## <Section>` over ` - ` bullets with one leading space,
    /// a heading with trailing spaces (v0.40.7's `## New Stuff   `). Mutation:
    /// parse with another format.
    @Test func releaseNotesKeepTheirSections() throws {
        let json = """
            [{"tag_name": "v0.40.8", "published_at": "2026-09-21T02:26:02Z", "draft": false, "prerelease": false,
              "body": "## Bug Fixes\\n - `nvm_alias`, `nvm_version_path`: reject `..` path components\\n - `nvm-exec`: improve the no-version failure message\\n\\n## Performance\\n - Optimize nvm_tree_contains_path with in-memory POSIX parent-walk (#3912)"},
             {"tag_name": "v0.40.7", "published_at": "2026-08-18T06:22:50Z", "draft": false, "prerelease": false,
              "body": "## New Stuff   \\n - `nvm install`: serialize concurrent installs of the same version\\n    \\n## Docs\\n - [readme] link every referenced person and project to its canonical page"}]
            """
        let changelog = try #require(NvmRelease.parseNotes(json))
        #expect(changelog.entries.map(\.version) == ["0.40.8", "0.40.7"])
        let newest = try #require(changelog.entries.first)
        #expect(newest.content.compactMap { if case .heading(let h) = $0 { h } else { nil } } == ["Bug Fixes", "Performance"])
        #expect(newest.items == [
            "`nvm_alias`, `nvm_version_path`: reject `..` path components",
            "`nvm-exec`: improve the no-version failure message",
            "Optimize nvm_tree_contains_path with in-memory POSIX parent-walk",
        ])
        let older = try #require(changelog.entries.last)
        #expect(older.content.compactMap { if case .heading(let h) = $0 { h } else { nil } } == ["New Stuff", "Docs"])
    }
}
