import Foundation

/// Runs a vendor's documented install command as root, behind the system's
/// administrator panel — for an install in a directory only root may write
/// (`/usr/local/bin` as `sudo` left it), and only from a click on that row's
/// own Update (`CLIToolsModel.update`; `updateAll` skips these rows).
///
/// **Whose name is on the panel.** The command goes through `do shell script …
/// with administrator privileges` run by `NSAppleScript` inside DuoUpdater, not
/// by an `osascript` child: TN2065 says `do shell script` "always runs as a
/// child of the process running the script", and Apple DTS answered a developer
/// whose panel read "osascript" since Monterey that `osascript` "was intended
/// for folks writing shell scripts, not as an API for use by apps … use the
/// `NSAppleScript` API" (developer.apple.com/forums/thread/695616).
/// `NSAppleScript` is on the Threading Programming Guide's "Main Thread Only
/// Classes" list, so the panel is raised from the main actor and the main
/// thread waits for the user's answer — and no longer: the command itself is
/// started in the background (TN2065's `command > file 2>&1 &`), so
/// `do shell script` returns as soon as it is authorized and the run is
/// followed by polling its log and status files from here.
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
/// **Where the output goes.** A directory of the user's own in their temporary
/// directory (never `HOME`), into which the root shell creates `log` and
/// `status` with noclobber (`set -C`: `O_EXCL`, so a link planted at either
/// name is refused rather than written through). The directory is the user's,
/// so both files are removed with it afterwards.
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
        case authorized
        /// AppleScript's error number and message.
        case error(number: Int, message: String)
    }

    typealias Authorize = @MainActor @Sendable (_ shell: String) -> Authorization

    /// The row's line while the panel is up, said before it is raised.
    static let waitingLine = "Waiting for an administrator password…"

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

    /// The live runner: the panel in this process, output under the user's
    /// temporary directory, the system proxy passed on.
    static func live(deadline: ChildProcess.Deadline) -> Runner {
        let shell = Shell(
            authorize: { inProcess($0) },
            workRoot: FileManager.default.temporaryDirectory,
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy },
            poll: .milliseconds(500), beforePanel: .milliseconds(150), deadline: deadline)
        return { command, progress in await shell.run(command, progress: progress) }
    }

    struct Shell: Sendable {
        let authorize: Authorize
        let workRoot: URL
        let environment: @Sendable () -> [String: String]
        let poll: Duration
        /// How long the main thread is left free between saying the panel is
        /// coming and raising it, so the row can draw that line first: once
        /// `NSAppleScript` holds the main thread nothing redraws until the
        /// user answers, and the row went on reading "Checking …" behind the
        /// panel (seen 2026-10-10).
        let beforePanel: Duration
        let deadline: ChildProcess.Deadline

        func run(_ command: String, progress: @escaping @Sendable (String) -> Void) async -> Result {
            let directory = workRoot.appendingPathComponent("duoupdater-admin-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            } catch {
                return .refused("could not prepare \(directory.path): \(error.localizedDescription)")
            }
            defer { try? FileManager.default.removeItem(at: directory) }
            let text = CLIToolAdministratorRun.shell(
                command: command, directory: directory.path, proxies: CLIToolAdministratorRun.proxies(environment()))
            progress(CLIToolAdministratorRun.waitingLine)
            try? await Task.sleep(for: beforePanel)
            let authorize = self.authorize
            switch await MainActor.run(body: { authorize(text) }) {
            case .error(let number, _) where number == CLIToolAdministratorRun.userCanceled:
                return .declined
            case .error(let number, let message):
                return .refused(message.isEmpty ? "authorization failed (\(number))" : message)
            case .authorized:
                break
            }
            return await follow(directory, progress: progress)
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

    /// The shell line `do shell script` runs as root. It returns at once: the
    /// command runs in a background subshell whose output goes to
    /// `<directory>/log` and whose exit status goes to `<directory>/status`.
    static func shell(command: String, directory: String, proxies: [String: String]) -> String {
        let environment = [
            "HOME=/var/root", "USER=root", "LOGNAME=root", "SHELL=/bin/sh",
            "PATH=\(CLIToolCommandRunner.systemPath):/usr/local/bin",
        ] + proxies.keys.sorted().map { "\($0)=\(quote(proxies[$0] ?? ""))" }
        let log = quote(directory + "/log")
        let status = quote(directory + "/status")
        return "( set -C; cd / && umask 022 && /usr/bin/env -i \(environment.joined(separator: " ")) "
            + "/bin/sh -c \(quote(command)) < /dev/null > \(log) 2>&1; echo $? > \(status) ) "
            + "< /dev/null > /dev/null 2>&1 &"
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

    /// The panel, raised by this process.
    @MainActor static func inProcess(_ shell: String) -> Authorization {
        guard let script = NSAppleScript(source: appleScript(for: shell)) else {
            return .error(number: 0, message: "could not build the AppleScript")
        }
        var info: NSDictionary?
        if script.executeAndReturnError(&info) != nil { return .authorized }
        let number = (info?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = info?[NSAppleScript.errorMessage] as? String ?? ""
        return .error(number: number, message: message)
    }
}
