import Testing
import Foundation
@testable import DuoUpdaterCore

struct CLIToolProcessesTests {

    let disk = CLIToolProcesses.FileID(device: 1, inode: 200)
    let replaced = CLIToolProcesses.FileID(device: 1, inode: 100)

    @Test func aProcessOnTheFileOnDiskIsCurrent() {
        let target = CLIToolProcesses.Target(executable: "/Users/u/.local/bin/codex", versionedSiblings: false)
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 10, path: "/Users/u/.local/bin/codex", file: disk),
        ])
        #expect(usage == CLIToolUsage(current: [10], stale: []))
        #expect(usage.isRunning)
    }

    @Test func aProcessOnAReplacedFileIsStaleWithoutAVersion() {
        let target = CLIToolProcesses.Target(executable: "/Users/u/.local/bin/codex", versionedSiblings: false)
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 10, path: "/Users/u/.local/bin/codex", file: replaced),
            .init(pid: 11, path: "/Users/u/.local/bin/codex", file: disk),
        ])
        #expect(usage.current == [11])
        #expect(usage.stale == [.init(pid: 10, version: nil)])
        #expect(usage.hasUnknownStale)
    }

    /// Without the kernel's word on the mapped file there is nothing to call
    /// stale: a row must not say "restart" on a guess.
    @Test func anUnreadableMappingIsNotStale() {
        let target = CLIToolProcesses.Target(executable: "/x/tool", versionedSiblings: false)
        let usage = CLIToolProcesses.usage(of: target, current: disk, processes: [
            .init(pid: 10, path: "/x/tool", file: nil),
        ])
        #expect(usage == CLIToolUsage(current: [10], stale: []))
    }

    /// The path must be the binary's, exactly: another file in the same
    /// directory is another tool, unless the install keeps a file per version.
    @Test func aNeighbourIsNotThisToolUnlessItsLayoutIsVersioned() {
        let plain = CLIToolProcesses.Target(executable: "/Users/u/.local/bin/agent", versionedSiblings: false)
        let processes: [CLIToolProcesses.Running] = [.init(pid: 10, path: "/Users/u/.local/bin/zoxide", file: disk)]
        #expect(CLIToolProcesses.usage(of: plain, current: disk, processes: processes) == .none)
    }

    @Test func claudeSessionsOnOlderVersionsAreStaleByName() {
        let versions = "/Users/u/.local/share/claude/versions"
        let target = CLIToolProcesses.Target(executable: "\(versions)/2.1.301", versionedSiblings: true)
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
        let target = CLIToolProcesses.Target(executable: "\(versions)/2.1.300", versionedSiblings: true)
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
            executable: "/Users/u/.local/share/claude/versions/2.1.301", versionedSiblings: true)
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
        #expect(CLIToolWording.stillRunning(1, on: nil, of: .codex) == "1 running process still runs the copy from before the update")
    }

    @Test func noStaleCopyMeansNothingToSay() {
        #expect(CLIToolWording.stillRunning(CLIToolUsage(current: [1], stale: []), of: .claudeCode) == nil)
    }

    @Test func onlyClaudesNativeVersionsDirectoryIsVersioned() throws {
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
        #expect(claude.versionedSiblings)
        #expect(CLIToolProcesses.target(kind: .codex, path: launcher.path)?.versionedSiblings == false)
        // A directory (a toolchain, a package) is not a binary to match.
        #expect(CLIToolProcesses.target(kind: .rust, path: versions.path) == nil)
        #expect(CLIToolProcesses.target(kind: .codex, path: root.appendingPathComponent("gone").path) == nil)
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

        let target = CLIToolProcesses.Target(executable: path, versionedSiblings: false)
        let usage = try #require(CLIToolProcesses.usage(of: [target])[target])
        #expect(usage.current.contains(pid))
        #expect(usage.stale.isEmpty)
    }
}
