import Foundation
import Darwin
import SQLite3

/// Is something already changing a global npm package right now?
///
/// npm documents no lock for a global install, and replaces a package directory
/// whole (a new inode each time), so two installs into one prefix race each
/// other. What an install in flight looks like, read with `KERN_PROCARGS2` (the
/// same reader as `ClaudeCodeActivity`) every 50 ms while `npm install -g` ran in
/// a scratch prefix (npm 11.6.2 under node 24.13.0, 2026-10-02):
///
///     argv ["<prefix>/bin/node", "<prefix>/bin/npm", "install", "-g", "--prefix", "<prefix>", "cowsay@1.6.0"]
///     argv ["npm", "", "", "", "", "", ""]                          (npm setting its title)
///     argv ["npm install cowsay@1.6.0", "", "", "", "", "", ""]     (for the rest of the run)
///
/// npm overwrites its argv with `process.title` — `npm` plus the positional
/// arguments, flags left out "to keep secrets from being leaked" (`lib/npm.js`) —
/// so for nearly the whole run nothing in argv names the prefix, nor even `-g`.
/// What still does is the executable: `proc_pidpath` stayed `<prefix>/bin/node`
/// throughout. So an npm is attributed to a prefix by the node running it.
///
/// That attribution is coarse in one direction: a project-local `npm install`
/// run by the same node also counts, and holds back every package of that
/// prefix until it ends — a false "busy" for a while, never a race.
///
/// A package with its own updater is also busy while that runs (`openclaw
/// update`, `agent-browser upgrade`), whatever node runs it — for openclaw
/// from 2026.9 by its own record of the run (`openclawUpdateRun`).
public enum NpmActivity {

    /// A process as the kernel reports it: argv, the file it executes, and when
    /// it started (`pbi_start_tvsec`, seconds since 1970).
    public struct Process: Sendable, Equatable {
        public let pid: pid_t
        public let arguments: [String]
        public let executable: String?
        public let started: UInt64?

        public init(pid: pid_t, arguments: [String], executable: String?, started: UInt64? = nil) {
            self.pid = pid
            self.arguments = arguments
            self.executable = executable
            self.started = started
        }
    }

    public enum Busy: Sendable, Equatable, CustomStringConvertible {
        /// An npm that changes packages, run by this prefix's node.
        case npm(String, pid: pid_t)
        /// The package's own updater.
        case ownUpdater(String, pid: pid_t)

        public var description: String {
            switch self {
            case .npm(let command, let pid): return "\(command) is running in this node prefix (pid \(pid))"
            case .ownUpdater(let command, let pid): return "\(command) is running (pid \(pid))"
            }
        }
    }

    /// npm's commands that write to `node_modules`, with their aliases (npm 11's
    /// `lib/utils/cmd-list.js`).
    static let changingCommands: Set<String> = [
        "install", "i", "in", "ins", "inst", "insta", "instal", "isnt", "isnta", "isntal", "isntall", "add",
        "install-test", "it", "install-ci-test", "cit",
        "ci", "clean-install", "ic", "install-clean", "isntall-clean",
        "update", "up", "upgrade", "udpate",
        "uninstall", "un", "unlink", "remove", "rm", "r",
        "link", "ln", "dedupe", "ddp", "prune", "rebuild", "rb",
    ]

    public static func busy(_ install: NpmInstall, processes: [Process]) -> Busy? {
        let node = install.runtime.node.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        for process in processes {
            if let node, let executable = process.executable,
               URL(fileURLWithPath: executable).resolvingSymlinksInPath().path == node,
               let command = npmCommand(process.arguments) ?? ownUpdaterTitle(process.arguments, install: install) {
                return command.hasPrefix("npm") ? .npm(command, pid: process.pid) : .ownUpdater(command, pid: process.pid)
            }
            if let command = ownUpdater(process.arguments, install: install) {
                return .ownUpdater(command, pid: process.pid)
            }
        }
        return openclawUpdateRun(install, processes: processes)
    }

    /// `npm <command>` when argv is an npm changing packages, in either shape: the
    /// title npm writes over argv[0] (`npm install cowsay@1.6.0`), or the argv it
    /// was started with (`node …/bin/npm install …`, `…/npm-cli.js install …`).
    /// A bare `npm` title is the moment before npm has parsed its arguments, when
    /// it could be anything — counted, since it may be an install.
    static func npmCommand(_ arguments: [String]) -> String? {
        guard let first = arguments.first else { return nil }
        let title = first.split(separator: " ").map(String.init)
        if title.first == "npm", arguments.dropFirst().allSatisfy(\.isEmpty) {
            guard title.count > 1 else { return "npm" }
            return changingCommands.contains(title[1]) ? "npm \(title[1])" : nil
        }
        let names = arguments.prefix(2).map { ($0 as NSString).lastPathComponent }
        guard let index = names.firstIndex(where: { $0 == "npm" || $0 == "npm-cli.js" }) else { return nil }
        // The command is the first argument after npm that is not a flag.
        guard let command = arguments.dropFirst(index + 1).first(where: { !$0.hasPrefix("-") }),
              changingCommands.contains(command) else { return nil }
        return "npm \(command)"
    }

    /// `openclaw update` or `agent-browser upgrade` from this package: its script
    /// or binary (or the prefix's link to it) as argv[0] or argv[1], the update
    /// subcommand right after.
    static func ownUpdater(_ arguments: [String], install: NpmInstall) -> String? {
        let subcommand: String
        switch install.ownUpdate {
        case .openclaw: subcommand = "update"
        case .agentBrowser: subcommand = "upgrade"
        case nil: return nil
        }
        let package = URL(fileURLWithPath: install.path).resolvingSymlinksInPath().path
        for index in 0..<min(2, arguments.count) where index + 1 < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("/"), arguments[index + 1] == subcommand else { continue }
            let resolved = URL(fileURLWithPath: argument).resolvingSymlinksInPath().path
            if resolved.hasPrefix(package + "/") {
                return "\((install.manifestName ?? install.name)) \(subcommand)"
            }
        }
        return nil
    }

    /// openclaw's update under the title it gives itself. openclaw names each
    /// process after its command (`setProcessTitleForCommand`: `openclaw-<name>`),
    /// so once running, `openclaw update` is argv `["openclaw-update", "", …]`,
    /// and the doctor it runs next `openclaw-doctor` — seen with `ps` during a real
    /// one-click from DuoUpdater, 2026-10-02, where the argv form below matched
    /// for none of it. Like npm's title, attributed to the prefix by its node
    /// (`busy`). A doctor the user runs by hand also counts: busy for a while,
    /// never a race.
    static func ownUpdaterTitle(_ arguments: [String], install: NpmInstall) -> String? {
        guard case .openclaw = install.ownUpdate, let first = arguments.first,
              arguments.dropFirst().allSatisfy(\.isEmpty),
              first == "openclaw-update" || first == "openclaw-doctor"
        else { return nil }
        return "openclaw " + first.dropFirst("openclaw-".count)
    }

    /// openclaw's update by its own record of it. From 2026.9 the title says
    /// nothing: `setProcessTitleForCommand` sets plain `openclaw` for every
    /// command (2026.9.8's `dist/program-*.mjs`, read 2026-10-06; only the gateway
    /// renames itself, `openclaw-gateway`), so the update is argv
    /// `["openclaw", "", …]` like any other openclaw — and on macOS the title
    /// overwrites the environment block too (`ps -E` shows nothing), so neither
    /// can tell it apart. What still can is the ledger openclaw keeps of its own
    /// runs, the `update_runs` table of `<state>/state/openclaw.sqlite`: a row
    /// whose `status` is `running`, with the driver in `origin_json` —
    /// `{"driver":{"host":…,"pid":…,"startIdentity":"<start, seconds>"}}`.
    /// openclaw counts a run as live while any recorded driver (`driver`,
    /// `previousDrivers`) is alive and started when recorded (`update-run-activity`,
    /// `update-run-driver`), the start read with `proc_pidinfo` as here; a row a
    /// crashed update left `running` is not live, and neither is it here.
    ///
    /// Measured 2026-10-06: a real `openclaw update --tag 2026.9.8` of 2026.9.7
    /// (`bun add -g` in a scratch HOME, Homebrew's node 26.10.0), the process table
    /// and the ledger read every 100 ms. The row appeared 6 s after the command
    /// started and stayed `running` through `requested`, `validating` and
    /// `activating` (127 s) with the driver's pid and start matching the process
    /// table, until `finished` 7 s before the command exited (it went on to
    /// triage). The first 6 s — before the row, nothing yet staged — only the
    /// launcher's argv shows, and only when openclaw re-spawns itself, which it
    /// skips under `OPENCLAW_NODE_OPTIONS_READY=1` (`entry.respawn`), as an update
    /// started by a gateway inherits it.
    ///
    /// The ledger is per state directory, not per install: an update from another
    /// prefix's openclaw on the same `~/.openclaw` holds this one back too — busy
    /// for a while, never a race. Read-only, it cannot be opened while no openclaw
    /// has it open and its `-wal`/`-shm` are gone (prepare fails, `SQLITE_CANTOPEN`,
    /// measured on a copy of a closed one) — and then no update is running.
    static func openclawUpdateRun(_ install: NpmInstall, processes: [Process]) -> Busy? {
        guard case .openclaw(let settings) = install.ownUpdate, let state = settings.stateDirectory else { return nil }
        let drivers = runningUpdateDrivers(database: state + "/state/openclaw.sqlite")
        for process in processes where drivers.contains(where: {
            $0.pid == process.pid && process.started.map(String.init) == $0.startIdentity
        }) {
            return .ownUpdater("openclaw update", pid: process.pid)
        }
        return nil
    }

    struct UpdateDriver: Decodable, Equatable {
        let pid: pid_t
        let startIdentity: String
    }

    /// The drivers of every run openclaw's ledger has as `running`; none when it
    /// cannot be read (no file, no table — openclaw before 2026.9 —, or closed).
    static func runningUpdateDrivers(database: String) -> [UpdateDriver] {
        struct Origin: Decodable {
            let driver: UpdateDriver?
            let previousDrivers: [UpdateDriver]?
        }
        guard FileManager.default.fileExists(atPath: database) else { return [] }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT origin_json FROM update_runs WHERE status = 'running'",
                                 -1, &statement, nil) == SQLITE_OK else { return [] }
        var drivers: [UpdateDriver] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0),
                  let origin = try? JSONDecoder().decode(Origin.self, from: Data(String(cString: text).utf8))
            else { continue }
            drivers += (origin.driver.map { [$0] } ?? []) + (origin.previousDrivers ?? [])
        }
        return drivers
    }

    // MARK: - Reading the process table

    /// Every process of this user, with argv (`ClaudeCodeActivity.arguments`)
    /// and its executable (`proc_pidpath`). Processes whose arguments cannot be
    /// read (another user's, or gone) are skipped.
    public static func runningProcesses() -> [Process] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        })
        guard count > 0 else { return [] }
        return pids.prefix(min(count, capacity)).compactMap { pid in
            guard pid > 0, let arguments = ClaudeCodeActivity.arguments(of: pid) else { return nil }
            return Process(pid: pid, arguments: arguments, executable: executable(of: pid), started: started(pid))
        }
    }

    static func started(_ pid: pid_t) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec
    }

    static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
