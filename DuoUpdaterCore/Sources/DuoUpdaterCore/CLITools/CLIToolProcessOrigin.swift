import Foundation
import Darwin
import AppKit

/// Who started one process that runs a CLI tool's binary (`CLIToolProcesses`),
/// read from the kernel and launchd alone — nothing about any one tool.
///
/// Two answers, because one is not enough:
/// - **used by**: the ancestor chain (`ppid`). The outermost ancestor that is
///   an app LaunchServices runs, else the top of the chain — the one launchd is
///   the parent of — leaving out the tool itself. A Claude Code session's
///   chain is claude ← disclaimer ← Claude: the app is the outermost, not the
///   nearest. Without an app, the top (screen, tmux, sshd-session) says more
///   than the nearest, which is nearly always a shell or `login` (screen runs
///   each window through `login`). A path inside a `.app` is not an app: the
///   toolchain's git and `/usr/bin/python3` run from inside Xcode.app with
///   Xcode not running, and a folder can be named `my-site.app`.
/// - **started in**: the process's launchd coalition. It stays the one the
///   process was started in after its parent is gone: a daemon a remote SSH
///   session started, whose parent is launchd now, still reads
///   `com.openssh.sshd.<UUID>` (state terminated); a tmux server started in
///   Terminal still reads Terminal's after it was attached from iTerm — it is
///   where, not who uses it now. Measured 2026-10-21 on macOS 27.2 with
///   Terminal, iTerm, tmux, `nohup … & disown`, a LaunchAgent and an SSH
///   session.
///
/// The coalition's name is read from `launchctl print pid/<pid>`, whose man
/// page says that output "is NOT API in any sense at all": a name this cannot
/// parse is nil, and the surface says less rather than something wrong.
public struct CLIToolProcessOrigin: Sendable, Equatable {

    public struct Ancestor: Sendable, Equatable {
        public let pid: pid_t
        /// As `proc_pidpath` spells it; nil when the kernel would not say.
        public let path: String?
        /// What `ps` would show: `argv[0]` as the process set it (sshd's
        /// "sshd-session: bobby@notty"), else the path's last component, else
        /// the kernel's short name.
        public let name: String
        /// The bundle, when this process is an app LaunchServices runs
        /// (`NSRunningApplication`); nil for a helper inside one (Claude's
        /// `disclaimer`) and for a tool that only sits in one.
        public let app: String?
        public let appBundleID: String?

        public init(pid: pid_t, path: String?, name: String, app: String? = nil, appBundleID: String? = nil) {
            self.pid = pid
            self.path = path
            self.name = name
            self.app = app
            self.appBundleID = appBundleID
        }
    }

    /// The launchd coalition the process was started in.
    public struct Coalition: Sendable, Equatable {
        /// As launchd names it: `application.com.apple.Terminal.<n>.<n>`,
        /// `com.openssh.sshd.<UUID>`, a LaunchAgent's label,
        /// `application.ClaudeWakeHost.app.<UUID>` for an applet.
        public let name: String
        /// Whatever started it is gone (launchd's `state = terminated`). Its
        /// name stays while any member lives — 13 h on, measured.
        public let ended: Bool
        /// launchd's `bundle ID` line, for an `application.` coalition; empty
        /// for an AppleScript applet, which has none.
        let bundleLine: String?

        public init(name: String, ended: Bool, bundleLine: String? = nil) {
            self.name = name
            self.ended = ended
            self.bundleLine = bundleLine
        }

        /// The app's bundle identifier, for an `application.` coalition: the
        /// `bundle ID` line, else what the name carries before its instance.
        public var bundleID: String? {
            guard name.hasPrefix("application.") else { return nil }
            if let bundleLine { return bundleLine.isEmpty ? nil : bundleLine }
            guard !name.contains(".app.") else { return nil }
            let id = Self.trimmingInstance(String(name.dropFirst("application.".count)))
            return id.isEmpty ? nil : id
        }

        /// What to call it: the bundle identifier, an applet's name, or the
        /// name without its per-instance tail (`com.openssh.sshd`).
        public var label: String {
            if let bundleID { return bundleID }
            if name.hasPrefix("application."), let range = name.range(of: ".app.") {
                return String(name[name.index(name.startIndex, offsetBy: "application.".count)..<range.lowerBound])
            }
            return Self.trimmingInstance(name)
        }

        /// Drops trailing components that are all digits or a UUID.
        static func trimmingInstance(_ name: String) -> String {
            var parts = name.split(separator: ".", omittingEmptySubsequences: false)
            while parts.count > 1, let last = parts.last,
                  last.allSatisfy(\.isNumber) || UUID(uuidString: String(last)) != nil {
                parts.removeLast()
            }
            return parts.joined(separator: ".")
        }
    }

    public let pid: pid_t
    /// `argv`; empty when the kernel would not say.
    public let arguments: [String]
    public let started: Date?
    /// The process's own executable, as `proc_pidpath` spells it.
    public let executable: String?
    /// Parent first, up to and including launchd.
    public let ancestors: [Ancestor]
    public let coalition: Coalition?

    public init(
        pid: pid_t, arguments: [String], started: Date?, executable: String?, ancestors: [Ancestor],
        coalition: Coalition?
    ) {
        self.pid = pid
        self.arguments = arguments
        self.started = started
        self.executable = executable
        self.ancestors = ancestors
        self.coalition = coalition
    }

    /// The ancestor that uses the process: the outermost running app, else
    /// the top of the chain; never launchd nor the same binary (a tool that
    /// runs itself — a daemon its own CLI started); nil when nothing is left.
    public var usedBy: Ancestor? {
        let others = ancestors.filter { $0.pid > 1 && ($0.path == nil || $0.path != executable) }
        return others.last { $0.app != nil } ?? others.last
    }

    /// One line for the pid: "used by Claude", "used by tmux · started in
    /// Terminal", "started in com.openssh.sshd (no longer running)"; the
    /// parent's name when neither is known. `appName` names an app by its
    /// bundle identifier (`installedAppName`).
    public func summary(appName: (String) -> String? = Self.installedAppName) -> String {
        let user = usedBy
        let userName = user.map { $0.app.map(Self.name(ofApp:)) ?? $0.name }
        var started: String?
        if let coalition {
            if let id = coalition.bundleID {
                // The app the chain already names says it once.
                if id != user?.appBundleID { started = appName(id) ?? id }
            } else {
                started = coalition.label
            }
            if let place = started, coalition.ended {
                started = String(localized: "\(place) (no longer running)")
            }
        }
        switch (userName, started) {
        case let (user?, place?): return String(localized: "used by \(user) · started in \(place)")
        case let (user?, nil): return String(localized: "used by \(user)")
        case let (nil, place?): return String(localized: "started in \(place)")
        case (nil, nil): return String(localized: "parent: \(ancestors.first?.name ?? "launchd")")
        }
    }

    /// "Claude" for `/Applications/Claude.app`.
    public static func name(ofApp path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The installed app with `bundleID`, by name, or nil.
    @Sendable public static func installedAppName(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { name(ofApp: $0.path) }
    }

    // MARK: - Reading

    /// What the kernel says of `pid` now, with `coalition` — the caller's,
    /// from `readCoalition` — as it is; nil once the process has exited.
    /// Synchronous and cheap (`proc_pidinfo`, `KERN_PROCARGS2`), but it asks
    /// LaunchServices which ancestors are apps: run it off the cooperative pool.
    public static func read(pid: pid_t, coalition: Coalition?) -> CLIToolProcessOrigin? {
        guard let parent = parentPID(of: pid) else { return nil }
        var ancestors: [Ancestor] = []
        var next = parent
        var seen: Set<pid_t> = [pid]
        // Bounded: a chain is a handful deep, and a pid reused mid-walk must
        // not loop.
        while next > 0, ancestors.count < 32, seen.insert(next).inserted {
            ancestors.append(ancestor(next))
            guard next > 1, let up = parentPID(of: next) else { break }
            next = up
        }
        return CLIToolProcessOrigin(
            pid: pid, arguments: ClaudeCodeActivity.argumentsAndEnvironment(of: pid)?.arguments ?? [],
            started: CLIToolProcesses.startTime(of: pid), executable: path(of: pid), ancestors: ancestors,
            coalition: coalition)
    }

    /// `arguments` as a POSIX shell reads them back: an argument with anything
    /// but plain characters single-quoted, a `'` inside it as `'\''`.
    public var commandLine: String {
        arguments.map { argument in
            let plain = !argument.isEmpty && argument.unicodeScalars.allSatisfy {
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "@%+=:,./_-".unicodeScalars.contains($0))
            }
            return plain ? argument : "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        }.joined(separator: " ")
    }

    /// This origin with launchd's coalition.
    public func with(coalition: Coalition?) -> CLIToolProcessOrigin {
        CLIToolProcessOrigin(pid: pid, arguments: arguments, started: started, executable: executable,
                             ancestors: ancestors, coalition: coalition)
    }

    static func ancestor(_ pid: pid_t) -> Ancestor {
        let path = path(of: pid)
        let argv0 = ClaudeCodeActivity.argumentsAndEnvironment(of: pid)?.arguments.first
        let name = argv0.flatMap { $0.isEmpty ? nil : ($0 as NSString).lastPathComponent }
            ?? path.map { ($0 as NSString).lastPathComponent }
            ?? shortName(of: pid) ?? "pid \(pid)"
        let app = pid > 1 ? NSRunningApplication(processIdentifier: pid) : nil
        return Ancestor(pid: pid, path: path, name: name, app: app?.bundleURL?.path, appBundleID: app?.bundleIdentifier)
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    static func shortName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return name.isEmpty ? nil : name
    }

    /// `launchctl print pid/<pid>`'s resource coalition, or nil.
    public static func readCoalition(of pid: pid_t) async -> Coalition? {
        // Measured at under 10 ms; a launchd that does not answer must not
        // hold the read.
        guard let outcome = try? await ChildProcess.run(
            "/bin/launchctl", ["print", "pid/\(pid)"], standardError: .discard,
            deadline: .init(terminateAfter: .seconds(2), killAfter: .seconds(3)), onCancel: .terminateChild)
        else { return nil }
        // Not the exit status: a pid gone by now prints a stub and exits 0,
        // one launchd will not show (root's) exits 1 — only the block counts.
        return parseCoalition(String(decoding: outcome.standardOutput, as: UTF8.self))
    }

    /// The `resource coalition = { … }` block's name and state.
    static func parseCoalition(_ output: String) -> Coalition? {
        var inBlock = false
        var name: String?
        var ended = false
        var bundleLine: String?
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("resource coalition = {") { inBlock = true; continue }
            guard inBlock else { continue }
            if trimmed == "}" { break }
            if trimmed.hasPrefix("name = ") { name = String(trimmed.dropFirst("name = ".count)) }
            if trimmed.hasPrefix("state = ") { ended = trimmed == "state = terminated" }
            if trimmed.hasPrefix("bundle ID =") {
                bundleLine = trimmed.dropFirst("bundle ID =".count).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let name, !name.isEmpty else { return nil }
        return Coalition(name: name, ended: ended, bundleLine: bundleLine)
    }
}
