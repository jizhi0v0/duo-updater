import Foundation
import Darwin

/// Which processes are running an install's binary right now, and whether each
/// one runs the file on disk or a copy from before an update.
///
/// A tool that updates itself — Claude Code's background updater, a vendor's
/// `self-update` — leaves every process started before the update on the old
/// code: Claude Code's own docs say its updates "take effect the next time you
/// start Claude Code" (code.claude.com/docs/en/setup, read 2026-10-16). The
/// check then reads "up to date" while those processes are not. This is what
/// tells the two apart.
///
/// Matched on the executable path, exactly as the kernel spells it
/// (`proc_pidpath`, symlinks resolved), never on a name: another copy of the
/// same tool elsewhere — Claude's desktop app runs its own under
/// `~/Library/Application Support/Claude/claude-code/` — is another install,
/// not this one. A script's process is its interpreter, so a tool that is a
/// script (an npm package's `.js`, `nvm.sh`) never matches; that is the rule,
/// not a gap to paper over by reading argv.
///
/// Two ways a running copy is stale, both measured 2026-10-16:
/// - **the file was replaced under it.** After a `mv` over the binary,
///   `proc_pidpath` still names the same path, but the region the executable
///   is mapped from keeps the old inode (`PROC_PIDREGIONPATHINFO`), while
///   `stat` on the path reads the new one. Which version that copy was is not
///   on disk any more, so it is reported without one.
/// - **the install keeps a file per version** (Claude Code's native
///   `~/.local/share/claude/versions/<version>`, its launcher a symlink to
///   one): a process on a sibling file runs that version, by name.
///
/// Cost, measured 2026-10-16 on 1049 processes: one `proc_pidpath` each is
/// 1.2–1.4 ms for the whole table; the region read is only for processes whose
/// directory is one of the installs'.
public enum CLIToolProcesses {

    /// What `stat` and the kernel's region info agree a file is.
    public struct FileID: Sendable, Hashable {
        public let device: Int64
        public let inode: UInt64

        public init(device: Int64, inode: UInt64) {
            self.device = device
            self.inode = inode
        }
    }

    /// One install's binary, as the process table will spell it.
    public struct Target: Sendable, Hashable {
        /// The binary, symlinks resolved.
        public let executable: String
        /// Other files beside it are this install's other versions, each named
        /// by its version (Claude Code's native layout).
        public let versionedSiblings: Bool

        public init(executable: String, versionedSiblings: Bool) {
            self.executable = executable
            self.versionedSiblings = versionedSiblings
        }

        var directory: String { (executable as NSString).deletingLastPathComponent }
    }

    /// A process whose executable sits in one of the installs' directories.
    public struct Running: Sendable, Equatable {
        public let pid: pid_t
        /// As `proc_pidpath` spells it.
        public let path: String
        /// The file the executable is mapped from; nil when the kernel would
        /// not say (another user's process), and then it is not called stale.
        public let file: FileID?
        /// `argv`, read only where a target asks to (`ignores`); empty otherwise.
        public let arguments: [String]

        public init(pid: pid_t, path: String, file: FileID?, arguments: [String] = []) {
            self.pid = pid
            self.path = path
            self.file = file
            self.arguments = arguments
        }
    }

    /// The binary `status`'s processes run, or nil when it is not one this can
    /// match: a directory (a toolchain, a package), or nothing on disk.
    public static func target(of status: CLIToolStatus) -> Target? {
        var executable: String? = status.path
        if case .claudeCode(let claude) = status.detail { executable = claude.install.executable ?? status.path }
        return executable.flatMap { target(kind: status.kind, path: $0) }
    }

    /// The same for a sighting, which knows only the install's path — `duo list`.
    public static func target(of sighting: CLIToolSighting) -> Target? {
        target(kind: sighting.kind, path: sighting.path)
    }

    static func target(kind: CLIToolKind, path: String) -> Target? {
        guard let resolved = realpath(path) else { return nil }
        var info = stat()
        guard stat(resolved, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let siblings = kind == .claudeCode
            && (resolved as NSString).deletingLastPathComponent.hasSuffix("/claude/versions")
        return Target(executable: resolved, versionedSiblings: siblings)
    }

    /// Who runs `target`, from one read of the process table (`running`) and
    /// the file now on disk (`current`).
    public static func usage(of target: Target, current: FileID?, processes: [Running]) -> CLIToolUsage {
        var live: [pid_t] = []
        var stale: [CLIToolUsage.Copy] = []
        for process in processes {
            if process.path == target.executable {
                if let file = process.file, let current, file != current {
                    stale.append(.init(pid: process.pid, version: nil))
                } else {
                    live.append(process.pid)
                }
            } else if target.versionedSiblings,
                      (process.path as NSString).deletingLastPathComponent == target.directory {
                // `claude update` from an old session's launcher is the updater
                // itself, on its way out — not a session left on the old code.
                guard !ClaudeCodeActivity.isClaudeUpdateCommand(process.arguments) else { continue }
                let name = (process.path as NSString).lastPathComponent
                guard name.first?.isNumber == true else { continue }
                stale.append(.init(pid: process.pid, version: name))
            }
        }
        return CLIToolUsage(current: live.sorted(), stale: stale.sorted { $0.pid < $1.pid })
    }

    /// Every target's usage, from one read of the process table.
    public static func usage(of targets: some Collection<Target>) -> [Target: CLIToolUsage] {
        guard !targets.isEmpty else { return [:] }
        let processes = running(in: Set(targets.map(\.directory)),
                                readingArgumentsIn: Set(targets.filter(\.versionedSiblings).map(\.directory)))
        var answer: [Target: CLIToolUsage] = [:]
        for target in Set(targets) {
            answer[target] = usage(of: target, current: fileID(target.executable), processes: processes)
        }
        return answer
    }

    // MARK: - Reading the kernel

    /// The processes whose executable sits in one of `directories`. `argv` is
    /// read only for those in `readingArgumentsIn`.
    public static func running(in directories: Set<String>, readingArgumentsIn: Set<String> = []) -> [Running] {
        guard !directories.isEmpty else { return [] }
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) })
        guard count > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var found: [Running] = []
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            let directory = (path as NSString).deletingLastPathComponent
            guard directories.contains(directory) else { continue }
            let arguments = readingArgumentsIn.contains(directory)
                ? ClaudeCodeActivity.arguments(of: pid) ?? [] : []
            found.append(Running(pid: pid, path: path, file: mappedFile(of: pid, path: path), arguments: arguments))
        }
        return found
    }

    /// The file `pid`'s executable is mapped from: the first of its regions
    /// backed by `path`. The main binary's `__TEXT` is the lowest such region;
    /// the walk is bounded, and gives up (nil) rather than guess.
    static func mappedFile(of pid: pid_t, path: String) -> FileID? {
        var info = proc_regionwithpathinfo()
        let size = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        var address: UInt64 = 0
        for _ in 0..<16 {
            guard proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, size) == size else { return nil }
            let regionPath = withUnsafeBytes(of: &info.prp_vip.vip_path) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if regionPath == path {
                let stat = info.prp_vip.vip_vi.vi_stat
                return FileID(device: Int64(stat.vst_dev), inode: stat.vst_ino)
            }
            let next = info.prp_prinfo.pri_address + info.prp_prinfo.pri_size
            guard next > address else { return nil }
            address = next
        }
        return nil
    }

    static func fileID(_ path: String) -> FileID? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileID(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }

    static func realpath(_ path: String) -> String? {
        guard let resolved = Darwin.realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

/// Who is running one install right now (`CLIToolProcesses`).
public struct CLIToolUsage: Sendable, Equatable {
    /// A process on a copy from before the update.
    public struct Copy: Sendable, Equatable, Hashable {
        public let pid: pid_t
        /// The version it runs, when the install's layout names it.
        public let version: String?

        public init(pid: pid_t, version: String?) {
            self.pid = pid
            self.version = version
        }
    }

    /// Processes running the file on disk now.
    public let current: [pid_t]
    /// Processes still on an older copy.
    public let stale: [Copy]

    public init(current: [pid_t], stale: [Copy]) {
        self.current = current
        self.stale = stale
    }

    public static let none = CLIToolUsage(current: [], stale: [])

    public var isRunning: Bool { !current.isEmpty || !stale.isEmpty }

    /// The older versions still running, oldest first; a copy whose version is
    /// not known is left out (`hasUnknownStale`).
    public var staleVersions: [String] {
        Set(stale.compactMap(\.version)).sorted { VersionComparator.compare($0, $1) == .orderedAscending }
    }

    public var hasUnknownStale: Bool { stale.contains { $0.version == nil } }
}
