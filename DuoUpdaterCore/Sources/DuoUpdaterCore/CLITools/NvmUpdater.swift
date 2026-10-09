import Foundation

/// Runs the one-click update an nvm status offers — the newer tag's official
/// installer, pointed at the install's own directory — and checks what it left.
///
/// **The update.** nvm's README ("Installing and Updating",
/// https://github.com/nvm-sh/nvm#installing-and-updating, read 2026-10-09):
/// "To install or update nvm, you should run the install script". So the
/// installer of the tag `releases/latest` named at the check,
/// `https://raw.githubusercontent.com/nvm-sh/nvm/v<latest>/install.sh`, is
/// fetched whole into a private temporary directory and run as `bash <file>` —
/// the README's `curl -o- … | bash` without the pipe.
///
/// **No trust check.** nvm is exempt from the trust rule (`CLIToolTrust`) by the
/// user's decision of 2026-10-09: it is shell scripts, with nothing to check a
/// signature or a hash of, and the user takes the tag's `install.sh` as stable.
/// No commit, tag or digest is checked. What is refused is a download that is
/// not nvm's installer at all (`isInstaller`: an error page, say).
///
/// **The child's environment.** The README's customisation variables are
/// `NVM_SOURCE`, `NVM_DIR`, `PROFILE` and `NODE_VERSION`; reading `install.sh`
/// (v0.40.8, the same file on `master` on 2026-10-09) finds a few more.
/// - `NVM_DIR` is the install's directory. The installer uses `$NVM_DIR`, else
///   `$XDG_CONFIG_HOME/nvm`, else `~/.nvm`; an app has neither variable, so
///   without it a `~/.config/nvm` install would get a second copy in `~/.nvm`.
/// - `PROFILE=/dev/null`: "the user has specifically requested NOT to have nvm
///   touch their profile" (`nvm_detect_profile`, and again where the source
///   lines would be appended). No rc file is read or written.
/// - `HOME` is the scan's.
/// - Gone (`overrides`): `NVM_SOURCE` (where `nvm.sh` or the clone comes from),
///   `NVM_INSTALL_VERSION` (another version than the tag's),
///   `NVM_INSTALL_GITHUB_REPO` (another repository), `METHOD` (git or script
///   regardless of the layout), `NODE_VERSION` (`nvm_install_node` would also
///   `nvm install` that node), `NVM_ENV` (`testing` skips the install),
///   `XDG_CONFIG_HOME` (another directory, were `NVM_DIR` empty); and bash's
///   own `BASH_ENV`, `SHELLOPTS` and exported functions (`BASH_FUNC_*`), which
///   would run or redefine something before the script's first line — a `git`
///   or `command` function, say. A terminal-run `duo` may carry any of them.
///
/// **The child's `PATH`** is a private directory holding only the programs the
/// script and the `nvm.sh` it sources run (`tools`) — no `sudo`, no
/// `xcode-select`, no `which`. `install.sh` uses `curl` (downloads), `grep`,
/// `sed`, `mkdir`, `ls`, `sort` and `chmod`; the `nvm.sh` it sources at the end
/// runs `nvm use --silent default` when a default node is set, which needs
/// `awk`, `tail`, `tr` and `uname` (measured 2026-10-09: the real installer run
/// against an install with a default node until nothing was "command not
/// found"). That puts nvm's own node directory first on the `PATH`;
/// `nvm_check_global_modules` then finds that `npm` inside `NVM_DIR` and stops,
/// so no `npm` runs (a recording stand-in `npm` was never called). With no
/// default node, no `node` or `npm` is on the `PATH` at all.
///
/// **git, and the Command Line Tools dialog.** On a Mac without the Command
/// Line Tools, `/usr/bin/git` is a shim that puts the "install the command line
/// developer tools" dialog on screen. `install.sh` (v0.40.8, `nvm_do_install`)
/// guards against it only when `xcode-select` is on the `PATH`, `xcode-select -p`
/// exits 2, *and* `which git` prints literally `/usr/bin/git` — a link to the
/// shim from any other directory would pass that guard and run the shim (the
/// README's troubleshooting, nvm issue #1782, says the installer "can't
/// properly detect if Git is installed" there). So the shim is never on the
/// `PATH`, under any name:
/// - A **script** layout (the bare files) is updated with no `git` on the
///   `PATH` at all: the installer's `nvm_has git` fails and it downloads the
///   three files with `curl`, as it did the first time. The layout is kept, and
///   no git runs.
/// - A **git** layout (a checkout) gets a `git` that `exec`s a real git binary
///   (`git()`): the Command Line Tools' own, Homebrew's, or the selected
///   developer directory's — each a binary, not the shim, and never anything
///   that resolves into `/usr/bin`. Without one there is no click (`NvmCheck`).
///   A wrapper, not a link: git finds its helpers (`git-remote-https`) next to
///   the path it was started by, and through a link it looked in the private
///   directory and failed — "git: 'remote-https' is not a git command", seen in
///   the real run of 2026-10-09.
/// With `xcode-select` off the `PATH`, the installer's own guard is skipped;
/// it has nothing left to guard.
///
/// **After the run.** A non-zero exit is a failure, with the script's own last
/// line and the status. Exit 0 is read back from `nvm.sh`: the target version
/// is `updated`; anything else a failure. Nothing else is gated: nvm is sourced
/// into shells, not a running binary, and the installer takes no lock.
public struct NvmUpdater: Sendable {

    /// The installer's file name starts with this, so `NvmActivity` can tell a
    /// run of it in the process table.
    static let scriptPrefix = "nvm-install-"

    typealias BusyCheck = @Sendable () -> NvmActivity.Busy?
    typealias FetchScript = @Sendable (URL) async throws -> Data

    let busy: BusyCheck
    let scanner: NvmScanner
    let git: NvmCheck.Git
    let fetchScript: FetchScript
    /// The child's environment before the variables above are set.
    let environment: @Sendable () -> [String: String]
    /// The programs linked onto the child's `PATH`, by name. A checkout's `git`
    /// is a wrapper beside them (`prepare`).
    let tools: [String: String]
    let deadline: ChildProcess.Deadline

    /// A shallow fetch of one tag, or three small files. The deadline is for a
    /// child that hangs.
    static let defaultDeadline = ChildProcess.Deadline(terminateAfter: .seconds(5 * 60), killAfter: .seconds(5 * 60 + 30))

    /// Removed from the child's environment; see the type's comment.
    static let overrides = [
        "NVM_SOURCE", "NVM_INSTALL_VERSION", "NVM_INSTALL_GITHUB_REPO", "METHOD", "NODE_VERSION", "NVM_ENV",
        "XDG_CONFIG_HOME", "BASH_ENV", "SHELLOPTS",
    ]
    /// bash's exported functions, `BASH_FUNC_<name>%%`.
    static let exportedFunctionPrefix = "BASH_FUNC_"

    static let defaultTools = [
        "curl": "/usr/bin/curl", "grep": "/usr/bin/grep", "sed": "/usr/bin/sed", "mkdir": "/bin/mkdir",
        "ls": "/bin/ls", "sort": "/usr/bin/sort", "chmod": "/bin/chmod", "awk": "/usr/bin/awk",
        "tail": "/usr/bin/tail", "uname": "/usr/bin/uname", "tr": "/usr/bin/tr",
    ]

    public init() {
        self.init(
            busy: { NvmActivity.busy(processes: ClaudeCodeActivity.runningProcesses()) },
            scanner: NvmScanner(),
            git: { NvmUpdater.git() },
            fetchScript: { try await JunieUpdater.download($0) },
            // The installer's curl and git read the proxy variables, which a GUI
            // app launched by launchd does not have. See `SystemProxyEnvironment`.
            environment: { ProcessInfo.processInfo.environmentWithSystemProxy })
    }

    init(
        busy: @escaping BusyCheck,
        scanner: NvmScanner,
        git: @escaping NvmCheck.Git,
        fetchScript: @escaping FetchScript,
        environment: @escaping @Sendable () -> [String: String],
        tools: [String: String] = NvmUpdater.defaultTools,
        deadline: ChildProcess.Deadline = NvmUpdater.defaultDeadline
    ) {
        self.busy = busy
        self.scanner = scanner
        self.git = git
        self.fetchScript = fetchScript
        self.environment = environment
        self.tools = tools
        self.deadline = deadline
    }

    // MARK: - git

    /// Where a real git may be, in order: the Command Line Tools' own, Homebrew's
    /// (Apple silicon, Intel), and the developer directory `xcode-select -s`
    /// chose (`/var/db/xcode_select_link`, read as a link, never by running
    /// `xcode-select`).
    static let gitCandidates = [
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/var/db/xcode_select_link/usr/bin/git",
    ]

    /// The first candidate that resolves to an executable file outside
    /// `/usr/bin`, the shims' directory; nil when there is none. Nothing is run.
    /// `resolve` is the seam tests use: the path a candidate resolves to when it
    /// is an executable file, else nil.
    static func git(
        candidates: [String] = gitCandidates,
        resolve: (String) -> String? = { path in
            guard let real = LuvusScanner.canonicalPath(path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: real),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  access(real, X_OK) == 0
            else { return nil }
            return real
        }
    ) -> String? {
        for candidate in candidates {
            guard let real = resolve(candidate), !real.hasPrefix("/usr/bin/") else { continue }
            return real
        }
        return nil
    }

    // MARK: - The update

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> CLIToolUpdateOutcome {
        guard status.oneClick != nil, case .nvm(let install) = status.detail, let before = install.version,
              let target = status.latestVersion, NvmRelease.isVersion(target)
        else { return .notOffered }
        let busy = self.busy
        if let running = await offCooperativePool({ busy() }) {
            return .busy(running.description)
        }
        let scanner = self.scanner
        guard let now = await offCooperativePool({ scanner.reread(install.path) }), now.problem == nil,
              now.version == before, now.layout == install.layout
        else {
            return .failed(message: "not run: \(install.path) is no longer the nvm that was checked", output: "")
        }
        guard now.writable else {
            return .failed(message: "not run: \(install.directory) cannot be written without sudo", output: "")
        }
        guard VersionComparator.compare(before, target) == .orderedAscending else {
            return .failed(message: "not run: nvm \(target) is not newer than \(before)", output: "")
        }
        var git: String?
        if now.layout == .git {
            guard let found = self.git() else {
                return .failed(message: "not run: no git but /usr/bin/git's Command Line Tools stub was found", output: "")
            }
            git = found
        }

        let installer = NvmRelease.installer(version: target)
        let script: Data
        do {
            script = try await fetchScript(installer)
        } catch {
            return .failed(message: "could not download \(installer.absoluteString): \(error)", output: "")
        }
        guard Self.isInstaller(script) else {
            return .failed(message: "\(installer.absoluteString) did not answer with nvm's installer", output: "")
        }
        let scratch: URL
        let file: URL
        do {
            (scratch, file) = try await offCooperativePool { [tools, git] in
                try Self.prepare(script: script, tools: tools, git: git)
            }
        } catch {
            return .failed(message: "not run: could not prepare the installer: \(error)", output: "")
        }
        defer { try? FileManager.default.removeItem(at: scratch) }

        let environment = Self.childEnvironment(
            self.environment(), home: scanner.home.path, directory: install.directory,
            path: scratch.appendingPathComponent("bin").path)
        let run = await CLIToolCommandRunner.run(
            CLIToolCommand(executable: "/bin/bash", arguments: [file.path], pathPrefix: nil),
            environment: environment, deadline: deadline, progress: progress)
        let outcome: ChildProcess.Outcome
        switch run.result {
        case .couldNotStart(let error):
            return .failed(message: "could not run /bin/bash: \(error)", output: run.text)
        case .finished(let finished):
            outcome = finished
        }
        guard outcome.succeeded else {
            return .failed(message: Self.failureMessage(run.lines, outcome, deadline: deadline), output: run.text)
        }

        let after = await offCooperativePool { scanner.reread(install.path) }
        guard let version = after?.version, version == target else {
            let what = after?.version ?? "unreadable"
            return .failed(message: "install.sh finished, but nvm.sh is still \(what)", output: run.text)
        }
        return .updated(version: version)
    }

    /// The child's environment: the inherited one without `overrides` and
    /// bash's exported functions, with `HOME`, `PATH`, `NVM_DIR` and
    /// `PROFILE=/dev/null` set.
    static func childEnvironment(
        _ inherited: [String: String], home: String, directory: String, path: String
    ) -> [String: String] {
        var environment = inherited.filter { key, _ in
            !overrides.contains(key) && !key.hasPrefix(exportedFunctionPrefix)
        }
        environment["HOME"] = home
        environment["PATH"] = path
        environment["NVM_DIR"] = directory
        environment["PROFILE"] = "/dev/null"
        return environment
    }

    /// The script is nvm's installer: a bash script with its `nvm_do_install`
    /// and the `PROFILE=/dev/null` opt-out this run relies on. An error page or
    /// anything else is not run.
    static func isInstaller(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        return text.hasPrefix("#!/usr/bin/env bash") && text.contains("nvm_do_install() {")
            && text.contains(#"[ "${PROFILE-}" = '/dev/null' ]"#)
    }

    /// A private directory holding the script and `bin/`, a link to each tool
    /// and, given `git`, a `git` that `exec`s it, for the child's `PATH`. Blocking.
    static func prepare(script: Data, tools: [String: String], git: String?) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-nvm-\(UUID().uuidString)", isDirectory: true)
        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        for (name, target) in tools {
            try FileManager.default.createSymbolicLink(
                atPath: bin.appendingPathComponent(name).path, withDestinationPath: target)
        }
        if let git {
            let quoted = "'" + git.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
            let wrapper = bin.appendingPathComponent("git")
            try Data("#!/bin/sh\nexec \(quoted) \"$@\"\n".utf8).write(to: wrapper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        }
        let file = directory.appendingPathComponent("\(scriptPrefix)\(UUID().uuidString).sh")
        try script.write(to: file, options: .atomic)
        return (directory, file)
    }

    /// The line the row shows when the installer failed: its own last line with
    /// a letter in it (`nvm_echo >&2 "Failed to …"`), and the exit status. A
    /// timeout, a signal or a run with nothing to say keeps the shared wording.
    static func failureMessage(
        _ lines: [String], _ outcome: ChildProcess.Outcome, deadline: ChildProcess.Deadline
    ) -> String {
        let line = CLIToolCommandRunner.failureMessage(lines, outcome, deadline: deadline)
        guard !outcome.timedOut, !outcome.uncaughtSignal, lines.contains(where: CLIToolCommandRunner.isMeaningful)
        else { return line }
        return "\(line) (exit \(outcome.terminationStatus))"
    }
}
