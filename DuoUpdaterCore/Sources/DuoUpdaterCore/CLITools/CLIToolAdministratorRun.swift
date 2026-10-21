import Foundation

/// Runs a vendor's documented install command as root, behind the system's
/// administrator panel — for an install in a directory only root may write
/// (`/usr/local/bin` as `sudo` left it), and only from a click: that row's
/// own Update (`CLIToolsModel.update`), or the app's Update All, which asks
/// for each such copy at the click, one panel after another
/// (`CLIToolsModel.updateAll`). Neither waits in the CLI tab's queue
/// (`CLIRunQueue`): the root shell runs under `env -i` with the system `PATH`
/// and writes only its tool's file and its own output directory, so it cannot
/// clash with a Homebrew run.
///
/// **Whose name is on the panel.** The command goes through `do shell script …
/// with administrator privileges` run by `NSAppleScript` inside DuoUpdater, not
/// by an `osascript` child: TN2065 says `do shell script` "always runs as a
/// child of the process running the script", and Apple DTS answered a developer
/// whose panel read "osascript" since Monterey that `osascript` "was intended
/// for folks writing shell scripts, not as an API for use by apps … use the
/// `NSAppleScript` API" (developer.apple.com/forums/thread/695616).
///
/// **Which thread waits for the answer.** Not the main one: `NSAppleScript`'s
/// `executeAndReturnError` returns only once the user answers the panel, and
/// run on the main actor it froze the whole app for that long — 877 of 877
/// samples in `OSAExecute` with the panel up, no redraw, no ✕ (real Mac,
/// 2026-10-21). The Threading Programming Guide still lists `NSAppleScript` as
/// main-thread-only, but the AppleScript 10.6 release notes lifted that: "OSA
/// and AppleScript are now thread-safe … This also applies to
/// `NSAppleScript`", with "trying to manipulate the same script from multiple
/// threads at once" not recommended. A scripting-addition command is run on
/// the main thread anyway unless its Info.plist marks it `ThreadSafe` (TN1164);
/// StandardAdditions marks `do shell script` (`sysoexec`) so. The panel itself
/// is SecurityAgent's, not this process's. So the script is built and
/// compiled on the main thread, and run on one serial queue of its own
/// (`panelQueue`), one panel at a time as the main thread used to give; only
/// the answer comes back to the main actor. (Compiled on the main thread
/// because a process whose first AppleScript ran on another thread stopped
/// draining its main queue under a bare `CFRunLoopRun`, the test runner's
/// loop: measured 2026-10-21, macOS 27.2; under `NSApplication.run` it did
/// not, and compiling on the main thread first cured both.)
/// The command itself is started in the background (TN2065's
/// `command > file 2>&1 &`), so `do shell script` returns as soon as it is
/// authorized and the run is followed by polling its log and status files
/// from here.
///
/// **What root gets.** TN2065: `do shell script` "inherits the environment of
/// its parent process" — DuoUpdater's, `HOME` included — so a vendor script
/// run as is would leave root-owned caches, temp files or man pages in the
/// user's home. The command runs under `env -i` with root's own `HOME`
/// (`/var/root`, as `sudo -H` would), `USER`/`LOGNAME` root, the system
/// `PATH` with `/usr/local/bin` last (the directory being updated, which is
/// root's; Helm's script ends by looking itself up there), the system proxy
/// only, `/` as the working directory, umask 022 and no stdin. Nothing else of
/// the app's environment reaches it.
///
/// **Where the output goes.** Into a directory root makes for itself once the
/// panel has authorized: `mktemp -d` under `/private/tmp` (root's, sticky), made
/// readable (755) so this process can follow `log` and `status` (644, umask
/// 022), its path the `do shell script` result. Root deletes it itself a minute
/// after writing `status` (`linger`), long past the half-second poll; a run
/// whose status lands while the app is not polling just reads as timed out.
///
/// Never a path the user can change. It used to be a directory of the user's,
/// made before the panel, with the files created under noclobber (`set -C`) —
/// which is not `O_EXCL`: `/bin/sh` is bash 3.2, whose noclobber opens an
/// existing non-regular file as usual. Measured 2026-10-20: `set -C; echo hi >
/// a` with `a` a link to `/dev/null`, or to a FIFO, exits 0 and the FIFO's
/// reader gets "hi"; only a link to a regular file is refused. So any process
/// of the user's could, while the panel was up, point `log` at a root-only
/// device or swap the empty directory for a link to a root-only one, and root
/// wrote there. Root's own directory leaves nothing to point: `mktemp`'s
/// `mkdir` refuses an existing name and follows no link, the sticky bit keeps
/// anyone else from renaming or removing it, and only root writes inside it.
/// Weighed and not taken: piping the output to a writer dropped to the user
/// (`sudo -u`), which the user's processes could kill mid-install, and
/// checking the files from the shell, which has no `O_NOFOLLOW`. The output is
/// a vendor installer's progress and is readable by other accounts on the Mac
/// while it lingers, as it would be on a shared terminal.
///
/// The command is a constant of the tool's check (`HelmCheck.rootCommand`,
/// `StarshipCheck.rootCommand`) — never a string from a status, a file or the
/// network — so nothing outside this code chooses what runs as root.
enum CLIToolAdministratorRun {

    enum Result: Sendable {
        /// The user dismissed the panel: nothing ran.
        case declined
        /// The panel did not authorize — a wrong password given up on, or the
        /// authorization failing — with the system's own reason.
        case refused(String)
        /// The command ran as root; its output and exit status.
        case ran(CLIToolCommandRunner.Run)
    }

    /// What an update asks: run `command` as root, each output line to
    /// `progress`.
    typealias Runner = @Sendable (_ command: String, _ progress: @escaping @Sendable (String) -> Void) async -> Result

    /// The panel's answer to one `do shell script … with administrator privileges`.
    enum Authorization: Sendable, Equatable {
        /// What the shell printed: where root put the run's output.
        case authorized(String)
        /// AppleScript's error number and message.
        case error(number: Int, message: String)
    }

    /// Called on `panelQueue`, never on the main thread; it blocks until the
    /// panel is answered.
    typealias Authorize = @Sendable (_ shell: String) -> Authorization

    /// The row's line while the panel is up, said before it is raised.
    static let waitingLine = "Waiting for an administrator password…"

    /// The row's line once the panel authorized the run, said in the main-actor
    /// turn that tells `CLIToolAdministratorPanel.answered`, before it: until
    /// the command's first log line,
    /// the row went on reading `waitingLine`, and under Update All the next
    /// panel, raised a moment later, froze it there — two rows "waiting for a
    /// password" with one already given (real Mac, 2026-10-20).
    static let authorizedLine = "Running as root…"

    /// AppleScript's "User canceled." — what dismissing the panel answers.
    static let userCanceled = -128

    /// `/usr/local/bin` itself — not a link to it — owned by root: the directory
    /// Helm's and Starship's scripts default to and escalate for. Blocking.
    static func isRootsDefault(_ directory: String) -> Bool {
        guard directory == "/usr/local/bin" else { return false }
        var info = stat()
        guard lstat(directory, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == 0
    }

    /// Where root makes the run's output directory: root's, sticky, and not a
    /// link (`/tmp` is one).
    static let liveWorkRoot = "/private/tmp"

    /// The live runner: the panel in this process, output under root's own
    /// directory in `liveWorkRoot`, the system proxy passed on.
    static func live(deadline: ChildProcess.Deadline) -> Runner {
        let shell = Shell(
            authorize: { inProcess($0) },
            workRoot: URL(fileURLWithPath: liveWorkRoot, isDirectory: true),
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            poll: .milliseconds(500), beforePanel: .milliseconds(150), linger: 60, deadline: deadline)
        return { command, progress in await shell.run(command, progress: progress) }
    }

    struct Shell: Sendable {
        let authorize: Authorize
        /// The directory root's `mktemp -d` makes the output directory in.
        let workRoot: URL
        let environment: @Sendable () -> [String: String]
        let poll: Duration
        /// How long the row is given between saying the panel is coming and
        /// raising it, so it can draw that line first: when `NSAppleScript`
        /// held the main thread nothing redrew until the user answered, and
        /// the row went on reading "Checking …" behind the panel (seen
        /// 2026-10-10).
        let beforePanel: Duration
        /// Seconds root keeps the output directory after writing `status`
        /// before deleting it — this process cannot delete what is root's.
        let linger: Int
        let deadline: ChildProcess.Deadline

        func run(_ command: String, progress: @escaping @Sendable (String) -> Void) async -> Result {
            let text = CLIToolAdministratorRun.shell(
                command: command, workRoot: workRoot.path, linger: linger,
                proxies: CLIToolAdministratorRun.proxies(environment()))
            progress(CLIToolAdministratorRun.waitingLine)
            // cancel-ok: one-shot pause before the commit; InstallCommit.run below refuses a cancelled caller
            try? await Task.sleep(for: beforePanel)
            // The tool's point of no return (`InstallCommit`), from raising the
            // panel through following the run: an authorized command is root's
            // and cannot be stopped from here, so neither is the following of
            // it — whose `try?` poll sleep would spin on a cancelled task. A
            // caller cancelled before it raises no panel and runs nothing.
            let shell = self
            // Landed only once the command ran: a dismissed or refused panel ran
            // nothing.
            let result = try? await InstallCommit.run("administrator run", landed: {
                if case .ran = $0 { return true } else { return false }
            }) {
                await shell.authorizeAndFollow(text, progress: progress)
            }
            return result ?? .refused("cancelled before the administrator panel was raised; nothing ran")
        }

        /// `run` from the panel on — its commit. See there.
        private func authorizeAndFollow(_ text: String, progress: @escaping @Sendable (String) -> Void) async -> Result {
            let authorize = self.authorize
            let answer = await withCheckedContinuation { continuation in
                CLIToolAdministratorRun.panelQueue.async { continuation.resume(returning: authorize(text)) }
            }
            await MainActor.run {
                if case .authorized = answer { progress(CLIToolAdministratorRun.authorizedLine) }
                CLIToolAdministratorPanel.answered?()
            }
            switch answer {
            case .error(let number, _) where number == CLIToolAdministratorRun.userCanceled:
                return .declined
            case .error(let number, let message):
                return .refused(message.isEmpty ? "authorization failed (\(number))" : message)
            case .authorized(let printed):
                guard let directory = outputDirectory(printed) else {
                    // The command was started; where it writes is unknown.
                    let outcome = ChildProcess.Outcome(
                        terminationStatus: -1, uncaughtSignal: false, timedOut: false,
                        standardOutput: Data(), standardError: Data())
                    return .ran(CLIToolCommandRunner.Run(
                        result: .finished(outcome), lines: ["the root shell named no output directory: \(printed)"]))
                }
                return await follow(directory, progress: progress)
            }
        }

        /// The directory the shell printed, when it is one `mktemp` made
        /// directly in `workRoot` from the line's template.
        func outputDirectory(_ printed: String) -> URL? {
            let path = printed.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = workRoot.path + "/" + CLIToolAdministratorRun.outputPrefix
            guard path.hasPrefix(prefix), path.count > prefix.count,
                  !path.dropFirst(prefix.count).contains("/")
            else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        /// The background command's log, line by line, until its status lands
        /// or the deadline passes. A run still going at the deadline cannot be
        /// stopped from here — it is root's — and is reported as timed out.
        private func follow(_ directory: URL, progress: @escaping @Sendable (String) -> Void) async -> Result {
            let log = CLIToolCommandRunner.OutputLog(onLine: progress)
            let logURL = directory.appendingPathComponent("log")
            let statusURL = directory.appendingPathComponent("status")
            var offset: UInt64 = 0
            func drain() {
                guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
                defer { try? handle.close() }
                try? handle.seek(toOffset: offset)
                if let data = try? handle.readToEnd(), !data.isEmpty {
                    offset += UInt64(data.count)
                    log.append(data)
                }
            }
            let clock = ContinuousClock()
            let limit = clock.now.advanced(by: deadline.terminateAfter)
            var status: Int32?
            while true {
                // The status is written after the log is complete, so a drain
                // after reading it misses nothing.
                if let code = Self.status(at: statusURL) {
                    status = code
                    break
                }
                drain()
                if clock.now >= limit { break }
                // cancel-ok: runs inside InstallCommit.run ("administrator run"), whose body no cancel reaches
                try? await Task.sleep(for: poll)
            }
            drain()
            log.finish()
            let outcome = ChildProcess.Outcome(
                terminationStatus: status ?? -1, uncaughtSignal: false, timedOut: status == nil,
                standardOutput: Data(), standardError: Data())
            return .ran(CLIToolCommandRunner.Run(result: .finished(outcome), lines: log.lines))
        }

        /// The exit status once the line `echo $?` writes is complete.
        static func status(at url: URL) -> Int32? {
            guard let data = try? Data(contentsOf: url), data.last == 0x0A else { return nil }
            return Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The start of the output directory's name; `mktemp` fills in the rest.
    static let outputPrefix = "duoupdater-admin."

    /// The shell line `do shell script` runs as root. It makes the output
    /// directory, prints its path and returns at once: the command runs in a
    /// background subshell whose output goes to `log` there and whose exit
    /// status goes to `status`, and which deletes the directory `linger`
    /// seconds later. A directory that cannot be made fails the line, and
    /// nothing runs.
    static func shell(command: String, workRoot: String, linger: Int, proxies: [String: String]) -> String {
        let environment = [
            "HOME=/var/root", "USER=root", "LOGNAME=root", "SHELL=/bin/sh",
            "PATH=\(CLIToolCommandRunner.systemPath):/usr/local/bin",
        ] + proxies.keys.sorted().map { "\($0)=\(quote(proxies[$0] ?? ""))" }
        let template = quote(workRoot + "/" + outputPrefix + "XXXXXXXX")
        return "cd / || exit 1; umask 022; d=$(/usr/bin/mktemp -d \(template)) || exit 1; "
            + "/bin/chmod 755 \"$d\" || exit 1; "
            + "( /usr/bin/env -i \(environment.joined(separator: " ")) "
            + "/bin/sh -c \(quote(command)) < /dev/null > \"$d/log\" 2>&1; echo $? > \"$d/status\"; "
            + "/bin/sleep \(linger); /bin/rm -rf \"$d\" ) < /dev/null > /dev/null 2>&1 & echo \"$d\""
    }

    /// The proxy variables of `environment` (`SystemProxyEnvironment`'s), and no
    /// other variable.
    static func proxies(_ environment: [String: String]) -> [String: String] {
        let names: Set = ["http_proxy", "https_proxy", "all_proxy", "no_proxy"]
        return environment.filter { names.contains($0.key.lowercased()) }
    }

    /// One shell word: single-quoted, each `'` closed, escaped and reopened.
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The AppleScript `NSAppleScript` runs: `shell` as a string literal.
    static func appleScript(for shell: String) -> String {
        let literal = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(literal)\" with administrator privileges"
    }

    /// Where every panel's script is built and run: off the main thread, and
    /// one at a time. Serial, so overcommit — it gets a thread however busy
    /// the cooperative pool is (`offCooperativePool`).
    static let panelQueue = DispatchQueue(label: "CLIToolAdministratorRun.panel", qos: .userInitiated)

    /// The panel, raised by this process. Blocks until it is answered; called
    /// on `panelQueue`.
    static func inProcess(_ shell: String) -> Authorization {
        execute(appleScript(for: shell))
    }

    /// `source` built and compiled by `NSAppleScript` on the main thread, then
    /// run on the calling thread — never the main one.
    static func execute(_ source: String) -> Authorization {
        dispatchPrecondition(condition: .notOnQueue(.main))
        final class Compiled: @unchecked Sendable {
            var script: NSAppleScript?
            var info: NSDictionary?
        }
        let compiled = DispatchQueue.main.sync { () -> Compiled in
            let made = Compiled()
            guard let script = NSAppleScript(source: source) else { return made }
            var info: NSDictionary?
            if script.compileAndReturnError(&info) { made.script = script } else { made.info = info }
            return made
        }
        var info = compiled.info
        guard let script = compiled.script else {
            if info == nil { return .error(number: 0, message: "could not build the AppleScript") }
            return error(info)
        }
        let result: NSAppleEventDescriptor? = script.executeAndReturnError(&info)
        if let result { return .authorized(result.stringValue ?? "") }
        return error(info)
    }

    private static func error(_ info: NSDictionary?) -> Authorization {
        let number = (info?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = info?[NSAppleScript.errorMessage] as? String ?? ""
        return .error(number: number, message: message)
    }
}

/// Who is told when an administrator panel has its answer.
public enum CLIToolAdministratorPanel {
    /// Called on the main actor as soon as the panel this task raised is
    /// answered — authorized, dismissed or refused — before the command it
    /// authorized runs. Bound by the app's Update All around each copy whose
    /// update asks for a password (`CLIToolsModel.updateAll`), so it raises
    /// the next copy's panel once this one's is answered rather than once its
    /// command is done. An update that ends before raising a panel never calls
    /// it; its caller waits for the update's end instead.
    @TaskLocal public static var answered: (@MainActor @Sendable () -> Void)?
}
