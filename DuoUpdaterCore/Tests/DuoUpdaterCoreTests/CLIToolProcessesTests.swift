import Testing
import Foundation
@testable import DuoUpdaterCore

struct CLIToolProcessesTests {

    let disk = CLIToolProcesses.FileID(device: 1, inode: 200)
    let replaced = CLIToolProcesses.FileID(device: 1, inode: 100)

    @Test func aProcessOnTheFileOnDiskIsCurrent() {
        let target = CLIToolProcesses.Target(executable: "/Users/u/.local/bin/codex")
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 10, path: "/Users/u/.local/bin/codex", file: disk),
        ])
        #expect(usage == CLIToolUsage(current: [10], stale: []))
        #expect(usage.isRunning)
    }

    @Test func aProcessOnAReplacedFileIsStaleWithoutAVersion() {
        let target = CLIToolProcesses.Target(executable: "/Users/u/.local/bin/codex")
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 10, path: "/Users/u/.local/bin/codex", file: replaced),
            .init(pid: 11, path: "/Users/u/.local/bin/codex", file: disk),
        ])
        #expect(usage.current == [11])
        #expect(usage.stale == [.init(pid: 10, version: nil)])
        #expect(usage.hasUnknownStale)
    }

    /// Updated, then put back on the build a process runs (rolled back, or
    /// downgraded by hand): the file is a new inode, the build is the same, and
    /// the process is on what is installed.
    @Test func aReplacedFileOfTheSameBuildIsCurrent() {
        let target = CLIToolProcesses.Target(executable: "/x/tool")
        let processes: [CLIToolProcesses.Running] = [.init(pid: 10, path: "/x/tool", file: replaced)]
        #expect(CLIToolProcesses.usage(of: target, current: disk, processes: processes, sameBuild: { _, _ in true })
                == CLIToolUsage(current: [10], stale: []))
        #expect(CLIToolProcesses.usage(of: target, current: disk, processes: processes, sameBuild: { _, _ in false }).stale.count == 1)
        // Unreadable counts as different: the inode says it was replaced.
        #expect(CLIToolProcesses.usage(of: target, current: disk, processes: processes, sameBuild: { _, _ in nil }).stale.count == 1)
    }

    /// The kernel half: this test process runs the build its own file holds.
    @Test func theTestProcessIsTheBuildOnDisk() throws {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        #expect(proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0)
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        #expect(CLIToolProcesses.runningCDHash(getpid())?.count == 20)
        #expect(CLIToolProcesses.sameBuild(pid: getpid(), asFileAt: path) == true)
    }

    /// Without the kernel's word on the mapped file there is nothing to call
    /// stale: a row must not say "restart" on a guess.
    @Test func anUnreadableMappingIsNotStale() {
        let target = CLIToolProcesses.Target(executable: "/x/tool")
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 10, path: "/x/tool", file: nil),
        ])
        #expect(usage == CLIToolUsage(current: [10], stale: []))
    }

    /// The path must be the binary's, exactly: another file in the same
    /// directory is another tool, unless the install keeps a file per version.
    @Test func aNeighbourIsNotThisToolUnlessItsLayoutIsVersioned() {
        let plain = CLIToolProcesses.Target(executable: "/Users/u/.local/bin/agent")
        let processes: [CLIToolProcesses.Running] = [.init(pid: 10, path: "/Users/u/.local/bin/zoxide", file: disk)]
        #expect(CLIToolProcesses.usage(of: plain, current: disk, processes: processes) == .none)
    }

    @Test func claudeSessionsOnOlderVersionsAreStaleByName() {
        let versions = "/Users/u/.local/share/claude/versions"
        let target = CLIToolProcesses.Target(executable: "\(versions)/2.1.301", versions: .init(root: versions, skipsClaudeUpdate: true))
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 30, path: "\(versions)/2.1.301", file: disk),
            .init(pid: 21, path: "\(versions)/2.1.300", file: replaced),
            .init(pid: 12, path: "\(versions)/2.1.299", file: replaced),
            .init(pid: 22, path: "\(versions)/2.1.300", file: replaced),
            // The updater itself, started from an old session's launcher.
            .init(pid: 40, path: "\(versions)/2.1.300", file: replaced, arguments: ["claude", "update"]),
            // Not a version: the installer's own scratch file, say.
            .init(pid: 50, path: "\(versions)/.tmp-download", file: replaced),
        ])
        #expect(usage.current == [30])
        #expect(usage.stale.map(\.pid) == [12, 21, 22])
        #expect(usage.staleVersions == ["2.1.299", "2.1.300"])
        #expect(!usage.hasUnknownStale)
        #expect(CLIToolWording.stillRunning(usage, of: .claudeCode) == "3 open sessions still run 2.1.299, 2.1.300")
    }

    /// A session on a version newer than the launcher's is not left behind.
    @Test func aNewerSiblingIsNotStale() {
        let versions = "/Users/u/.local/share/claude/versions"
        let target = CLIToolProcesses.Target(executable: "\(versions)/2.1.300", versions: .init(root: versions, skipsClaudeUpdate: true))
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 21, path: "\(versions)/2.1.301", file: replaced),
        ])
        #expect(usage == .none)
    }

    /// The app holds a check's verdict for hours; Claude Code's own updater
    /// repoints the launcher in between. The target follows the launcher as it
    /// is now, not the file the check resolved.
    @Test func aNativeClaudeTargetFollowsTheLauncherNotTheCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-processes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let versions = root.appendingPathComponent(".local/share/claude/versions")
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let old = versions.appendingPathComponent("2.1.300"), new = versions.appendingPathComponent("2.1.301")
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: new)
        let launcher = root.appendingPathComponent("claude")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: old)
        let install = ClaudeCodeInstall(
            path: launcher.path, method: .native, origin: .conventional, executable: old.path, version: "2.1.300",
            signature: .anthropic, problem: nil)
        let status = CLIToolStatus(
            kind: .claudeCode, path: launcher.path, installedVersion: "2.1.300", latestVersion: "2.1.301",
            channel: "latest", state: .updateAvailable, oneClick: nil, withheld: nil, note: nil,
            detail: .claudeCode(ClaudeCodeStatus(
                install: install, channel: .latest, latestVersion: "2.1.301", versionConfirmed: nil,
                state: .updateAvailable, oneClick: nil, note: nil)))
        #expect(CLIToolProcesses.target(of: status)?.executable == CLIToolProcesses.realpath(old.path))

        // `claude update` repoints the launcher; the verdict above is unchanged.
        try FileManager.default.removeItem(at: launcher)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: new)
        #expect(CLIToolProcesses.target(of: status)?.executable == CLIToolProcesses.realpath(new.path))
    }

    /// Claude's desktop app runs its own copy of the CLI; it is not the native
    /// install, whatever its file is called.
    @Test func theDesktopAppsBundledCopyIsAnotherInstall() {
        let target = CLIToolProcesses.Target(
            executable: "/Users/u/.local/share/claude/versions/2.1.301",
            versions: .init(root: "/Users/u/.local/share/claude/versions", skipsClaudeUpdate: true))
        let bundled = "/Users/u/Library/Application Support/Claude/claude-code/2.1.299/abc/claude.app/Contents/MacOS/claude"
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [.init(pid: 9, path: bundled, file: replaced)])
        #expect(usage == .none)
    }

    @Test func keepingStaleDropsOnlyTheUnconfirmed() {
        let usage = CLIToolUsage(current: [1], stale: [.init(pid: 2, version: "2.1.300"), .init(pid: 3, version: nil)])
        let kept = usage.keepingStale { $0.pid == 3 }
        #expect(kept == CLIToolUsage(current: [1], stale: [.init(pid: 3, version: nil)]))
        #expect(usage.keepingStale { _ in false }.isRunning)
        #expect(!CLIToolUsage(current: [], stale: [.init(pid: 2, version: nil)]).keepingStale { _ in false }.isRunning)
    }

    /// Ten sessions on three versions: one line per older version, oldest
    /// first, each with its own pids; a copy of unknown version last.
    @Test func staleCopiesAreListedByVersion() {
        let usage = CLIToolUsage(current: [1, 2], stale: [
            .init(pid: 30, version: "2.1.300"), .init(pid: 10, version: "2.1.299"), .init(pid: 31, version: "2.1.300"),
            .init(pid: 11, version: "2.1.299"), .init(pid: 99, version: nil),
        ])
        let groups = usage.staleByVersion
        #expect(groups.map(\.version) == ["2.1.299", "2.1.300", nil])
        #expect(groups.map(\.pids) == [[10, 11], [30, 31], [99]])
        #expect(CLIToolWording.stillRunning(2, on: "2.1.299", of: .claudeCode) == "2 sessions on 2.1.299")
        #expect(CLIToolWording.stillRunning(1, on: "2.1.300", of: .claudeCode) == "1 session on 2.1.300")
        #expect(CLIToolWording.stillRunning(1, on: nil, of: .codex) == "1 running process still runs a copy that has since been replaced")
    }

    @Test func noStaleCopyMeansNothingToSay() {
        #expect(CLIToolWording.stillRunning(CLIToolUsage(current: [1], stale: []), of: .claudeCode) == nil)
    }

    @Test func claudesNativeVersionsDirectoryIsVersionedForClaudeOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-processes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let versions = root.appendingPathComponent(".local/share/claude/versions")
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let binary = versions.appendingPathComponent("2.1.301")
        try Data("x".utf8).write(to: binary)
        let launcher = root.appendingPathComponent("claude")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: binary)

        let claude = try #require(CLIToolProcesses.target(kind: .claudeCode, path: launcher.path))
        #expect(claude.executable == CLIToolProcesses.realpath(binary.path))
        #expect(claude.versions == .init(root: CLIToolProcesses.realpath(versions.path)!, skipsClaudeUpdate: true))
        #expect(CLIToolProcesses.target(kind: .codex, path: launcher.path)?.versions == nil)
        // A directory (a toolchain, a package) is not a binary to match.
        #expect(CLIToolProcesses.target(kind: .rust, path: versions.path) == nil)
        #expect(CLIToolProcesses.target(kind: .codex, path: root.appendingPathComponent("gone").path) == nil)
    }

    /// A box with a launcher that symlinks into a versioned layout, as each
    /// vendor's installer left it on the development Mac (2026-10-17).
    struct Box {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("cli-processes-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        @discardableResult func file(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
            return url
        }
        @discardableResult func link(_ path: String, to destination: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: root.appendingPathComponent(destination).path)
            return url
        }
        func real(_ path: String) -> String { CLIToolProcesses.realpath(root.appendingPathComponent(path).path)! }
    }

    /// Codex standalone: `~/.local/bin/codex` → `current/bin/codex`, `current` →
    /// `releases/<version>-<target>`. A TUI and its managed daemon started on
    /// 0.162.1 stay on that release's file after `codex update`.
    @Test func codexProcessesOnAnOlderReleaseAreStaleByVersion() throws {
        let box = try Box()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let releases = ".codex/packages/standalone/releases"
        try box.file("\(releases)/0.162.1-aarch64-apple-darwin/bin/codex")
        try box.file("\(releases)/0.163.0-aarch64-apple-darwin/bin/codex")
        try box.file("\(releases)/0.163.0-aarch64-apple-darwin/codex-path/rg")
        try box.file("\(releases)/0.131.0-aarch64-apple-darwin/codex")
        try box.link(".codex/packages/standalone/current", to: "\(releases)/0.163.0-aarch64-apple-darwin")
        let launcher = try box.link(".local/bin/codex", to: ".codex/packages/standalone/current/bin/codex")

        let target = try #require(CLIToolProcesses.target(kind: .codex, path: launcher.path))
        #expect(target.executable == box.real("\(releases)/0.163.0-aarch64-apple-darwin/bin/codex"))
        let root = box.real(releases)
        #expect(target.versions?.root == root)
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 30, path: target.executable, file: disk),
            .init(pid: 21, path: "\(root)/0.162.1-aarch64-apple-darwin/bin/codex", file: replaced),
            .init(pid: 22, path: "\(root)/0.162.1-aarch64-apple-darwin/bin/codex", file: replaced),
            // A release from before the package layout keeps its binary at the top.
            .init(pid: 12, path: "\(root)/0.131.0-aarch64-apple-darwin/codex", file: replaced),
            // The ripgrep a release bundles is not Codex.
            .init(pid: 40, path: "\(root)/0.162.1-aarch64-apple-darwin/codex-path/rg", file: replaced),
            // Nor is a helper beside the binary.
            .init(pid: 41, path: "\(root)/0.162.1-aarch64-apple-darwin/bin/codex-code-mode-host", file: replaced),
        ])
        #expect(usage.current == [30])
        #expect(usage.stale == [.init(pid: 12, version: "0.131.0"), .init(pid: 21, version: "0.162.1"),
                                .init(pid: 22, version: "0.162.1")])
        #expect(CLIToolWording.stillRunning(usage, of: .codex) == "3 running processes still run 0.131.0, 0.162.1")
        #expect(CLIToolWording.stillRunning(CLIToolUsage(current: [], stale: [.init(pid: 1, version: "0.162.1")]), of: .codex)
                == "1 running process still runs 0.162.1")
    }

    /// Cursor Agent's launcher is a bash script that execs the `node` beside it:
    /// the process to match is that `node`, by release.
    @Test func cursorAgentIsMatchedOnItsReleasesNode() throws {
        let box = try Box()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let versions = ".local/share/cursor-agent/versions"
        for version in ["2026.10.01-e373342", "2026.10.16-e3cb207"] {
            try box.file("\(versions)/\(version)/cursor-agent")
            try box.file("\(versions)/\(version)/node")
        }
        let launcher = try box.link(".local/bin/agent", to: "\(versions)/2026.10.16-e3cb207/cursor-agent")

        let target = try #require(CLIToolProcesses.target(kind: .cursorAgent, path: launcher.path))
        #expect(target.executable == box.real("\(versions)/2026.10.16-e3cb207/node"))
        let root = box.real(versions)
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 30, path: target.executable, file: disk),
            .init(pid: 21, path: "\(root)/2026.10.01-e373342/node", file: replaced),
            .init(pid: 40, path: "\(root)/2026.10.01-e373342/rg", file: replaced),
        ])
        #expect(usage == CLIToolUsage(current: [30], stale: [.init(pid: 21, version: "2026.10.01-e373342")]))
    }

    /// Two Cursor releases of one date: the commits do not order, so another
    /// release of the launcher's date counts as older, the CLI's own rule
    /// (`CursorAgentRelease.compare`), whichever way the hashes sort.
    @Test func anotherCursorReleaseOfTheSameDateIsStale() {
        let versions = CLIToolProcesses.Versions(root: "/v", binaries: ["node"], ordering: .cursorAgentRelease)
        for (old, new) in [("2026.10.16-0338208", "2026.10.16-e3cb207"), ("2026.10.16-e3cb207", "2026.10.16-0338208")] {
            let target = CLIToolProcesses.Target(executable: "/v/\(new)/node", versions: versions)
            let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
                .init(pid: 21, path: "/v/\(old)/node", file: replaced),
                // A later date is not one to leave for the launcher's.
                .init(pid: 22, path: "/v/2026.10.30-abcdef0/node", file: replaced),
            ])
            #expect(usage == CLIToolUsage(current: [], stale: [.init(pid: 21, version: old)]))
        }
    }

    /// Junie: the row is the shim, a bash script; the process is the build's
    /// native launcher inside its jpackage bundle, `current` naming the build.
    @Test func junieIsMatchedOnItsBuildsLauncher() throws {
        let box = try Box()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let launcher = "Applications/junie.app/Contents/MacOS/junie"
        let versions = ".local/share/junie/versions"
        for build in ["3579.5", "3659.4"] {
            try box.file("\(versions)/\(build)/\(launcher)")
            try box.file("\(versions)/\(build)/junie")
        }
        try box.link(".local/share/junie/current", to: "\(versions)/3659.4")
        let shim = try box.file(".local/bin/junie")

        let target = try #require(CLIToolProcesses.target(kind: .junie, path: shim.path))
        #expect(target.executable == box.real("\(versions)/3659.4/\(launcher)"))
        let root = box.real(versions)
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 30, path: target.executable, file: disk),
            .init(pid: 21, path: "\(root)/3579.5/\(launcher)", file: replaced),
            // The JRE the bundle carries is not Junie.
            .init(pid: 40, path: "\(root)/3579.5/Applications/junie.app/Contents/runtime/Contents/Home/bin/java", file: replaced),
        ])
        #expect(usage == CLIToolUsage(current: [30], stale: [.init(pid: 21, version: "3579.5")]))
        // No `current`: nothing to match, rather than the shim.
        try FileManager.default.removeItem(at: box.root.appendingPathComponent(".local/share/junie/current"))
        #expect(CLIToolProcesses.target(kind: .junie, path: shim.path)?.versions == nil)
    }

    /// Vite+'s row is its data root; `current/bin/vp` resolves into
    /// `<version>/bin/vp`, and the runtime it manages is not `vp`.
    @Test func vitePlusProcessesOnAnOlderVersionAreStale() throws {
        let box = try Box()
        defer { try? FileManager.default.removeItem(at: box.root) }
        let data = ".local/share/vite-plus"
        try box.file("\(data)/1.2.0/bin/vp")
        try box.file("\(data)/1.3.0/bin/vp")
        try box.file("\(data)/js_runtime/node/24.22.0/bin/node")
        try box.link("\(data)/current", to: "\(data)/1.3.0")

        let target = try #require(CLIToolProcesses.target(kind: .vitePlus, path: box.root.appendingPathComponent(data).path))
        #expect(target.executable == box.real("\(data)/1.3.0/bin/vp"))
        let root = box.real(data)
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 21, path: "\(root)/1.2.0/bin/vp", file: replaced),
            .init(pid: 40, path: "\(root)/js_runtime/node/24.22.0/bin/node", file: replaced),
        ])
        #expect(usage == CLIToolUsage(current: [], stale: [.init(pid: 21, version: "1.2.0")]))
    }

    /// A layout's entries are matched on the declared binary only, and the
    /// launcher's own entry is never stale.
    @Test func versionsMatchOnlyTheDeclaredBinary() {
        let versions = CLIToolProcesses.Versions(root: "/r", binaries: ["bin/codex", "codex"], nameSuffixes: ["-aarch64-apple-darwin"])
        #expect(versions.entry(of: "/r/0.1.0-aarch64-apple-darwin/bin/codex") == "0.1.0-aarch64-apple-darwin")
        #expect(versions.entry(of: "/r/0.1.0-aarch64-apple-darwin/codex") == "0.1.0-aarch64-apple-darwin")
        #expect(versions.entry(of: "/r/0.1.0/bin/codex-code-mode-host") == nil)
        // `bin` is an entry by shape, but its name is not a version.
        #expect(versions.entry(of: "/r/bin/codex") == "bin")
        #expect(versions.version(ofEntry: "bin") == nil)
        #expect(versions.entry(of: "/rx/0.1.0/bin/codex") == nil)
        #expect(versions.entry(of: "/r") == nil)
        #expect(versions.version(ofEntry: "0.1.0-aarch64-apple-darwin") == "0.1.0")
        #expect(versions.version(ofEntry: ".tmp-0.1.0") == nil)
        let claude = CLIToolProcesses.Versions(root: "/v")
        #expect(claude.entry(of: "/v/2.1.300") == "2.1.300")
        #expect(claude.entry(of: "/v/2.1.300/x") == nil)
    }

    /// The kernel half for a nested layout: this test process, read as if its
    /// directory's parent were a versions root.
    @Test func theTestProcessIsFoundUnderAVersionsRoot() throws {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        #expect(proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0)
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let root = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let found = CLIToolProcesses.running(in: [], under: [root])
        #expect(found.contains { $0.pid == getpid() && $0.path == path })
        #expect(!CLIToolProcesses.running(in: [], under: [root + "-not"]).contains { $0.pid == getpid() })
    }

    /// The kernel half, on this test process itself: its path as `proc_pidpath`
    /// spells it, and the mapped file is the one on disk.
    @Test func theTestProcessIsFoundRunningItsOwnBinary() throws {
        let pid = getpid()
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        #expect(proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0)
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        let directory = (path as NSString).deletingLastPathComponent

        let found = CLIToolProcesses.running(in: [directory])
        let me = try #require(found.first { $0.pid == pid })
        #expect(me.path == path)
        #expect(me.file != nil)
        #expect(me.file == CLIToolProcesses.fileID(path))

        let target = CLIToolProcesses.Target(executable: path)
        let usage = try #require(CLIToolProcesses.usage(of: [target])[target])
        #expect(usage.current.contains(pid))
        #expect(usage.stale.isEmpty)
    }
}
