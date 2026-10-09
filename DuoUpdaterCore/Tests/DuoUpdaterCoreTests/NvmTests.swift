import Testing
import Foundation
@testable import DuoUpdaterCore

/// nvm: finding it where its installer puts it — and not where Homebrew does —
/// reading its version out of `nvm.sh`, its verdict (detection and the command
/// only) and its release notes. The release API is injected; nothing here runs
/// nvm, asks git or reaches the network.
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

        func check(latest: String = "0.40.8", status: Int = 200) -> NvmCheck {
            let release = NvmRelease(fetch: { url, _ in
                #expect(url == NvmRelease.latestURL)
                return (Data(#"{"tag_name": "v\#(latest)", "assets": []}"#.utf8), status, status == 200 ? nil : "0")
            })
            return NvmCheck(latest: { try await release.latest() })
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

    /// Never a click: the README's update, the newer tag's installer, to copy.
    /// Mutations: offer a click; name the installed tag instead of the latest.
    @Test func anUpdateIsTheCommandOnly() async throws {
        let box = try Sandbox()
        try box.install("0.40.7")
        let status = await box.check().status(of: try #require(box.scanner.scan().first))
        #expect(status.state == .updateAvailable)
        #expect(status.installedVersion == "0.40.7")
        #expect(status.latestVersion == "0.40.8")
        #expect(status.oneClick == nil)
        #expect(status.withheld == .unsupportedInstaller)
        #expect(status.manualCommand?.display
            == "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash")
        #expect(await NvmProvider().update(status, progress: { _ in }) == .notOffered)
    }

    @Test func otherVerdicts() async throws {
        let box = try Sandbox()
        try box.install("0.40.8")
        let install = try #require(box.scanner.scan().first)
        let current = await box.check().status(of: install)
        #expect(current.state == .upToDate)
        #expect(current.manualCommand == nil)
        #expect(await box.check(latest: "0.40.7").status(of: install).state == .ahead)
        #expect(await box.check(status: 403).status(of: install).withheld == .rateLimited)
        #expect(await box.check(status: 502).status(of: install).withheld == .channelUnreadable)

        let unreadable = NvmInstall(path: install.path, version: nil, problem: .versionUnreadable)
        #expect(await box.check().status(of: unreadable).withheld == .versionUnreadable)
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
