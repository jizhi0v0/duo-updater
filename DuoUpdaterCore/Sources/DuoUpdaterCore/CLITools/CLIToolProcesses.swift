import Foundation
import Darwin
import Security

/// The kernel's code-signing operations on a process. Not in the SDK's
/// headers (`<sys/codesign.h>` is in the kernel's), but exported by
/// libsystem_kernel; `codesign` and friends use it. `CS_OPS_CDHASH` (5)
/// copies the 20-byte cdhash the kernel validated the process's executable
/// against when it was loaded.
@_silgen_name("csops")
private func csops(_ pid: pid_t, _ ops: UInt32, _ useraddr: UnsafeMutableRawPointer?, _ usersize: Int) -> Int32

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
/// - **the install keeps an entry per version** and repoints a symlink at the
///   new one (`Versions`): a process on an older entry runs that version, by
///   name. Measured 2026-10-17 with each vendor's own installer and update
///   command, a process started before the update and read after it: Claude
///   Code native (`versions/<version>`), Codex standalone
///   (`releases/<version>-<target>/bin/codex`, `codex update`), Cursor Agent
///   (`versions/<version>/node`, `agent update`) and Vite+ (`<version>/bin/vp`,
///   `vp upgrade`). Every other tool here replaces its one file (`ls -la` /
///   `realpath` of each install on the development Mac, and each
///   `*Install.swift`'s layout notes).
///
/// Cost, measured 2026-10-16 on 1049 processes: one `proc_pidpath` each is
/// 1.2–1.4 ms for the whole table; the region read is only for processes whose
/// directory is one of the installs', or under one's `Versions.root`.
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

    /// An install that keeps one entry per version in a directory, its
    /// launcher a symlink into the active one, declared by its provider
    /// (`processTarget(resolved:)` on the install's type).
    public struct Versions: Sendable, Hashable {
        /// The directory of entries: Claude Code's `versions/`, Codex's `releases/`.
        public let root: String
        /// Where the binary sits inside an entry, as `proc_pidpath` spells it;
        /// "" when the entry is the binary (Claude Code). Codex has two: its
        /// package layout's `bin/codex`, and its older releases' `codex`.
        public let binaries: [String]
        /// Cut from an entry's name to read its version (Codex's `-<target>`).
        public let nameSuffixes: [String]
        /// `argv` is read and `claude update` left out: that process is the
        /// updater itself, on its way out (Claude Code only).
        public let skipsClaudeUpdate: Bool

        public init(root: String, binaries: [String] = [""], nameSuffixes: [String] = [], skipsClaudeUpdate: Bool = false) {
            self.root = root
            self.binaries = binaries
            self.nameSuffixes = nameSuffixes
            self.skipsClaudeUpdate = skipsClaudeUpdate
        }

        /// The entry `path` is one of this layout's binaries in, or nil.
        func entry(of path: String) -> String? {
            guard path.hasPrefix(root + "/") else { return nil }
            let rest = path.dropFirst(root.count + 1)
            let entry = rest.prefix { $0 != "/" }
            guard !entry.isEmpty else { return nil }
            let inside = rest.dropFirst(entry.count).drop { $0 == "/" }
            return binaries.contains(String(inside)) ? String(entry) : nil
        }

        /// The version an entry's name says, or nil when the name is not one
        /// (the installer's scratch entries, `bin`, `current`).
        func version(ofEntry entry: String) -> String? {
            var name = entry
            if let suffix = nameSuffixes.first(where: { name.hasSuffix($0) }) { name.removeLast(suffix.count) }
            return name.first?.isNumber == true ? name : nil
        }
    }

    /// One install's binary, as the process table will spell it.
    public struct Target: Sendable, Hashable {
        /// The binary, symlinks resolved.
        public let executable: String
        /// The install's other versions, when it keeps one entry per version.
        public let versions: Versions?

        public init(executable: String, versions: Versions? = nil) {
            self.executable = executable
            self.versions = versions
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
    ///
    /// Resolved now, not taken from the check: a native Claude Code install's
    /// launcher is repointed by its own updater between checks (to
    /// `versions/<new>`), and the check's `install.executable` still names the
    /// old file — every new session then read as left on an old version
    /// (review, #1374). The launcher itself is the native install's path; an
    /// npm copy's launcher can be a script, so its binary is the check's.
    public static func target(of status: CLIToolStatus) -> Target? {
        var executable: String? = status.path
        if case .claudeCode(let claude) = status.detail, claude.install.method != .native {
            executable = claude.install.executable ?? status.path
        }
        return executable.flatMap { target(kind: status.kind, path: $0) }
    }

    /// The same for a sighting, which knows only the install's path — `duo list`.
    public static func target(of sighting: CLIToolSighting) -> Target? {
        target(kind: sighting.kind, path: sighting.path)
    }

    static func target(kind: CLIToolKind, path: String) -> Target? {
        // Vite+'s row is its data root; the binary is the active version's.
        let path = kind == .vitePlus ? (path as NSString).appendingPathComponent("current/bin/vp") : path
        guard let resolved = realpath(path), isRegularFile(resolved) else { return nil }
        let versioned: Target? = switch kind {
        case .claudeCode: ClaudeCodeInstall.processTarget(resolved: resolved)
        case .codex: CodexInstall.processTarget(resolved: resolved)
        case .cursorAgent: CursorAgentInstall.processTarget(resolved: resolved)
        case .vitePlus: VitePlusInstall.processTarget(resolved: resolved)
        default: nil
        }
        return versioned ?? Target(executable: resolved)
    }

    static func isRegularFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    /// Who runs `target`, from one read of the process table (`running`) and
    /// the file now on disk (`current`).
    ///
    /// A process mapped from another file than the one on disk is stale only
    /// when its build differs too (`sameBuild`, by cdhash): a tool updated and
    /// then put back on the build a process runs — rolled back, or downgraded
    /// by hand — leaves that process on what is installed, in a file of a new
    /// inode. Unknown (nil) counts as different.
    public static func usage(
        of target: Target, current: FileID?, processes: [Running],
        sameBuild: (pid_t, String) -> Bool? = { sameBuild(pid: $0, asFileAt: $1) }
    ) -> CLIToolUsage {
        var live: [pid_t] = []
        var stale: [CLIToolUsage.Copy] = []
        for process in processes {
            if process.path == target.executable {
                if let file = process.file, let current, file != current,
                   sameBuild(process.pid, target.executable) != true {
                    stale.append(.init(pid: process.pid, version: nil))
                } else {
                    live.append(process.pid)
                }
            } else if let versions = target.versions, let entry = versions.entry(of: process.path),
                      let currentEntry = versions.entry(of: target.executable), entry != currentEntry {
                // `claude update` from an old session's launcher is the updater
                // itself, on its way out — not a session left on the old code.
                guard !(versions.skipsClaudeUpdate && ClaudeCodeActivity.isClaudeUpdateCommand(process.arguments))
                else { continue }
                // Only an older version is one the session should leave: a newer
                // one beside the launcher's (a custom launcher held back, a
                // `minimumVersion` floor) is not one to leave for the launcher's.
                guard let version = versions.version(ofEntry: entry),
                      let current = versions.version(ofEntry: currentEntry),
                      VersionComparator.compare(version, current) == .orderedAscending else { continue }
                stale.append(.init(pid: process.pid, version: version))
            }
        }
        return CLIToolUsage(current: live.sorted(), stale: stale.sorted { $0.pid < $1.pid })
    }

    /// Every target's usage, from one read of the process table.
    public static func usage(of targets: some Collection<Target>) -> [Target: CLIToolUsage] {
        guard !targets.isEmpty else { return [:] }
        let versions = targets.compactMap(\.versions)
        let processes = running(in: Set(targets.map(\.directory)), under: Set(versions.map(\.root)),
                                readingArgumentsUnder: Set(versions.filter(\.skipsClaudeUpdate).map(\.root)))
        var answer: [Target: CLIToolUsage] = [:]
        for target in Set(targets) {
            answer[target] = usage(of: target, current: fileID(target.executable), processes: processes)
        }
        return answer
    }

    // MARK: - Reading the kernel

    /// The processes whose executable sits in one of `directories`, or anywhere
    /// under one of `roots`. `argv` is read only for those under
    /// `readingArgumentsUnder`.
    public static func running(
        in directories: Set<String>, under roots: Set<String> = [], readingArgumentsUnder: Set<String> = []
    ) -> [Running] {
        guard !directories.isEmpty || !roots.isEmpty else { return [] }
        let under = { (path: String, roots: Set<String>) in roots.contains { path.hasPrefix($0 + "/") } }
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
            guard directories.contains(directory) || under(path, roots) else { continue }
            let arguments = under(path, readingArgumentsUnder)
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

    /// Whether `pid` runs the build now at `path`: the cdhash the kernel
    /// loaded it with against the file's own. Nil when either is unreadable.
    ///
    /// Measured 2026-10-17 on a binary replaced under a running process (mv),
    /// then put back: `csops` kept the process's own cdhash throughout
    /// (33a5…; the file read d6a9…, then 33a5… again). The Security
    /// framework's dynamic code for a pid (`SecCodeCopyGuestWithAttributes`)
    /// followed the file instead, so it cannot answer this.
    public static func sameBuild(pid: pid_t, asFileAt path: String) -> Bool? {
        guard let running = runningCDHash(pid), let installed = fileCDHash(path) else { return nil }
        return running == installed
    }

    static func runningCDHash(_ pid: pid_t) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 20)
        let result = buffer.withUnsafeMutableBytes { csops(pid, 5, $0.baseAddress, $0.count) }
        guard result == 0, buffer.contains(where: { $0 != 0 }) else { return nil }
        return Data(buffer)
    }

    static func fileCDHash(_ path: String) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoUnique as String] as? Data
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
    /// A process on a copy other than the one installed now.
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

    /// The stale copies by the version they run, oldest first, a copy whose
    /// version is not known last: what a surface lists one line each, so ten
    /// sessions on three versions say which pid is on which.
    public var staleByVersion: [(version: String?, pids: [pid_t])] {
        let versions = staleVersions.map { Optional($0) } + (hasUnknownStale ? [nil] : [])
        return versions.map { version in (version, stale.filter { $0.version == version }.map(\.pid)) }
    }

    /// This usage with only the stale copies `keep` admits — the app shows a
    /// stale copy only once two reads apart have both seen it, so the old
    /// binary's last short-lived command at the moment of an update does not
    /// flash a "still running" mark or post a notice.
    public func keepingStale(where keep: (Copy) -> Bool) -> CLIToolUsage {
        CLIToolUsage(current: current, stale: stale.filter(keep))
    }
}
