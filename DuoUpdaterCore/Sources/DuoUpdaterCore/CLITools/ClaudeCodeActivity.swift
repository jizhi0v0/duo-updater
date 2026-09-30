import Foundation
import Darwin

/// Is something already updating Claude Code right now?
///
/// The same question the Relaunch flow asks before it swaps an app: if the user
/// ran `claude update` in a terminal, or a running session's background updater
/// is mid-download, a second update started from DuoUpdater would race it. So
/// before offering — and again before running — an update, look for one in flight.
public enum ClaudeCodeActivity {

    /// A process as the kernel reports it.
    public struct Process: Sendable, Equatable {
        public let pid: pid_t
        public let arguments: [String]

        public init(pid: pid_t, arguments: [String]) {
            self.pid = pid
            self.arguments = arguments
        }
    }

    /// Why an install is considered busy, for the row to say so.
    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// `claude update` / `claude install` is running (pid).
        case updateCommand(pid_t)
        /// The native installer has a staging directory owned by a live process —
        /// a background update in progress inside some running session.
        case staging(version: String, pid: pid_t)
        /// npm / pnpm / bun is installing or removing the package (pid).
        case packageManager(pid_t)

        public var description: String {
            switch self {
            case .updateCommand(let pid): return "claude update is running (pid \(pid))"
            case .staging(let version, let pid): return "downloading \(version) (pid \(pid))"
            case .packageManager(let pid): return "a package manager is changing it (pid \(pid))"
            }
        }
    }

    /// The first sign of an update in flight for `install`, or nil.
    ///
    /// `~/.local/state/claude/locks/<version>.lock` is deliberately not a sign:
    /// every running native session holds one on the version it runs (JSON with
    /// `pid`, `version`, `execPath`, `acquiredAt`; measured 2026-09-30), so it
    /// means "in use", not "updating".
    public static func busy(
        _ install: ClaudeCodeInstall,
        processes: [Process],
        stagingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/claude/staging"),
        isAlive: (pid_t) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    ) -> Busy? {
        switch install.method {
        case .native, .unknown:
            for process in processes where isClaudeUpdateCommand(process.arguments) {
                return .updateCommand(process.pid)
            }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: stagingDirectory.path)) ?? []
            for entry in entries.sorted() {
                guard let (version, pid) = stagingOwner(entry), isAlive(pid) else { continue }
                return .staging(version: version, pid: pid)
            }
            return nil
        case .npm, .pnpm, .bun:
            for process in processes where isPackageManagerTouchingClaude(process.arguments) {
                return .packageManager(process.pid)
            }
            return nil
        }
    }

    /// The version and pid a native staging directory's name carries, or nil.
    ///
    /// Two shapes, both measured 2026-09-30 in a scratch HOME while downloading,
    /// and matching the template string in each binary:
    /// - up to 2.1.274: `<version>.<pid>.<epoch ms>`;
    /// - 2.1.280 and later: `<version>.<pid>.<epoch ms>.<8 hex digits>`.
    ///
    /// Behind a flag the directory is the bare `<version>`, with no pid to check;
    /// that is not read as busy. The epoch is what tells the shapes apart: read
    /// loosely, `2.1.285` is "version 2, pid 1" — and pid 1, launchd, is always alive.
    static func stagingOwner(_ name: String) -> (version: String, pid: pid_t)? {
        var parts = name.split(separator: ".")
        // An epoch in ms has 13 digits, so an 8-character suffix is never it.
        if parts.count >= 4, let last = parts.last, last.count == 8, last.allSatisfy(\.isHexDigit) {
            parts.removeLast()
        }
        guard parts.count >= 3, let epoch = parts.last, epoch.count >= 12, epoch.allSatisfy(\.isASCII),
              epoch.allSatisfy(\.isNumber), let pid = pid_t(parts[parts.count - 2]) else { return nil }
        return (parts.dropLast(2).joined(separator: "."), pid)
    }

    /// `claude update`, `claude install [target]` — however the binary was named.
    static func isClaudeUpdateCommand(_ arguments: [String]) -> Bool {
        guard arguments.count >= 2 else { return false }
        let executable = (arguments[0] as NSString).lastPathComponent
        let isClaude = executable == "claude" || executable == "claude.exe"
            || arguments[0].contains("/.local/share/claude/versions/")
        return isClaude && ["update", "install"].contains(arguments[1])
    }

    /// npm, pnpm or bun with the package on its command line — including the
    /// `node …/npm-cli.js install -g @anthropic-ai/claude-code` shape.
    static func isPackageManagerTouchingClaude(_ arguments: [String]) -> Bool {
        guard arguments.contains(where: { $0.contains("@anthropic-ai/claude-code") }) else { return false }
        return arguments.prefix(2).contains {
            let name = ($0 as NSString).lastPathComponent
            return ["npm", "npm-cli.js", "pnpm", "pnpm.js", "pnpm.cjs", "bun", "node"].contains(name)
        }
    }

    // MARK: - Reading the process table

    /// Every process of this user with its argv, read with `KERN_PROCARGS2`.
    /// Processes whose arguments cannot be read (another user's, or gone) are
    /// skipped.
    public static func runningProcesses() -> [Process] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        })
        guard count > 0 else { return [] }
        return pids.prefix(min(count, capacity)).compactMap { pid in
            guard pid > 0, let arguments = arguments(of: pid) else { return nil }
            return Process(pid: pid, arguments: arguments)
        }
    }

    /// The layout is `argc` (Int32), the executable path, NUL padding, then
    /// `argc` NUL-terminated arguments, then the environment.
    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }  // executable path
        while index < size, buffer[index] == 0 { index += 1 }  // padding
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
