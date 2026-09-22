import Foundation

/// A newer Homebrew release than the one installed — what the workbench's Brew tree
/// offers a one-click `brew update` for.
public struct HomebrewSelfUpdate: Sendable, Equatable {
    /// `HOMEBREW_VERSION` as brew reports it: `7.0.0`, or `6.0.22-310-ga45b0a0` for
    /// a checkout that follows `main` (developer mode).
    public let installed: String
    /// The latest stable release tag, e.g. `7.0.0`.
    public let latest: String

    public init(installed: String, latest: String) {
        self.installed = installed
        self.latest = latest
    }
}

/// What `brew config` says about this Homebrew: its version, and whether the user
/// has turned auto-update off.
///
/// Read from brew itself rather than by parsing `brew.env` here: `bin/brew` loads
/// three env files with a precedence of its own (user over prefix over system,
/// unless `HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY`), and a file value overrides the
/// same variable from the process environment — reimplementing that would drift
/// the moment brew changes it. `brew config` prints the result.
public struct HomebrewConfig: Sendable, Equatable {
    public let version: String
    /// The user set `HOMEBREW_NO_AUTO_UPDATE` — in a shell rc file, a `brew.env`,
    /// or `launchctl setenv`. They don't want Homebrew updating itself behind their
    /// back, so we don't offer to do it either.
    public let autoUpdateDisabled: Bool

    public init(version: String, autoUpdateDisabled: Bool) {
        self.version = version
        self.autoUpdateDisabled = autoUpdateDisabled
    }

    /// Parse `brew config` output. nil when there is no `HOMEBREW_VERSION:` line.
    ///
    /// Boolean variables print as `set` or `false` (`SystemConfig.homebrew_env_config`),
    /// so a listed key alone is not enough: `HOMEBREW_NO_AUTO_UPDATE: false` means
    /// auto-update is on.
    public static func parse(_ output: String) -> HomebrewConfig? {
        var version: String?
        var autoUpdateDisabled = false
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let value = Self.value(of: "HOMEBREW_VERSION", in: line) {
                version = value
            } else if let value = Self.value(of: "HOMEBREW_NO_AUTO_UPDATE", in: line) {
                autoUpdateDisabled = (value == "set")
            }
        }
        guard let version, !version.isEmpty else { return nil }
        return HomebrewConfig(version: version, autoUpdateDisabled: autoUpdateDisabled)
    }

    private static func value(of key: String, in line: String) -> String? {
        let prefix = key + ":"
        guard line.hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}

public enum HomebrewSelfUpdatePolicy {
    /// Whether to offer `brew update`, and for which versions. nil = show nothing.
    ///
    /// Hidden when the user disabled auto-update, when either version is missing,
    /// or when either doesn't parse — every one of those is "we can't say an update
    /// is wanted", and a button that runs `brew update` is not a guess to make.
    ///
    /// Only the release part of the installed version is compared. A developer-mode
    /// checkout (`homebrew.devcmdrun`, or `HOMEBREW_DEVELOPER`) follows `main`, so it
    /// is nearly always some commits past a tag: `6.0.22-310-g…` is behind `7.0.0`,
    /// `7.0.0-3-g…` is not. Comparing against `main` itself instead would light the
    /// row up permanently.
    public static func update(config: HomebrewConfig?, latestTag: String?) -> HomebrewSelfUpdate? {
        guard let config, !config.autoUpdateDisabled,
              let latestTag,
              let latest = releaseComponents(latestTag, allowingDescribeSuffix: false),
              let installed = releaseComponents(config.version, allowingDescribeSuffix: true),
              installed.lexicographicallyPrecedes(latest)
        else { return nil }
        return HomebrewSelfUpdate(installed: config.version, latest: latestTag)
    }

    /// `[major, minor, patch]` of a Homebrew version. With `allowingDescribeSuffix`,
    /// also accepts what `git describe` appends to a non-tag checkout
    /// (`-<commits>-g<sha>`, then `-dirty`), as `set-homebrew-version-from-git` does.
    static func releaseComponents(_ version: String, allowingDescribeSuffix: Bool) -> [Int]? {
        let pattern = allowingDescribeSuffix
            ? #"^(\d+)\.(\d+)\.(\d+)(?:-\d+-g[0-9a-f]+)?(?:-dirty)?$"#
            : #"^(\d+)\.(\d+)\.(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: version, range: NSRange(version.startIndex..., in: version)),
              match.numberOfRanges == 4
        else { return nil }
        let parts = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: version) else { return nil }
            return Int(version[range])
        }
        return parts.count == 3 ? parts : nil
    }
}

/// The `HOMEBREW_*` variables the user exports from their login shell.
///
/// A GUI app is launched by launchd, not by a shell, so its environment never saw
/// `~/.zshrc`. The most common way to configure Homebrew is exactly that — an
/// `export` in a shell rc file — so without this, a user who set
/// `HOMEBREW_NO_AUTO_UPDATE` there would still be offered an update, and a brew
/// we spawn would run with none of their settings.
public enum LoginShellEnvironment {
    static let beginMarker = "__DUO_HOMEBREW_ENV_BEGIN__"
    static let endMarker = "__DUO_HOMEBREW_ENV_END__"

    /// Run the user's login shell as an interactive login shell and collect its
    /// `HOMEBREW_*` variables. nil when the shell can't be run, times out, or
    /// doesn't print the markers — the caller must treat that as "unknown", not as
    /// "the user set nothing".
    ///
    /// Awaited through `ChildProcess`. rc files routinely start background helpers
    /// that inherit stdout; `ChildProcess` stops reading at the shell's exit rather
    /// than waiting for those to close the pipe, which is what the output file this
    /// used to write to was for.
    public static func resolveHomebrewVariables(timeout: TimeInterval = 10) async -> [String: String]? {
        guard let shell = loginShellPath() else { return nil }
        return await resolveHomebrewVariables(shell: shell, environment: nil, timeout: timeout)
    }

    /// Test seam: an explicit shell and environment (nil = inherit ours), so a test
    /// can point `HOME`/`ZDOTDIR` at fixture rc files instead of the host's.
    ///
    /// Runs to completion if the caller is cancelled, as the Dispatch hop it
    /// replaced did; `timeout` is what bounds it. A cancellation teardown would
    /// SIGKILL the shell alone and leave its rc's children running, which is the
    /// leak the timeout branch below exists to avoid.
    ///
    /// `timeout` counts from the shell's launch, as it did when the wait started
    /// after `Process.run()` returned: every spawn in this process goes through
    /// swift-subprocess's one worker thread, so a clock started at the call could
    /// expire before the shell existed, return nil without a pid to kill, and leave
    /// the shell to start afterwards with nobody watching it. `beforeSpawn` is a
    /// test seam for that wait, `timerExited` one for the timer's own end, and
    /// `sleep` one for the timer's clock, so a test can tell whether the timer
    /// started before or after the launch without racing it against real time.
    static func resolveHomebrewVariables(
        shell: String, environment: [String: String]?, timeout: TimeInterval,
        beforeSpawn: (@Sendable () async -> Void)? = nil,
        timerExited: (@Sendable () -> Void)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> [String: String]? {
        let launched = LaunchedPID()
        let runner = Task {
            try? await ChildProcess.run(
                // `-l -i`: login + interactive, so both ~/.zprofile and ~/.zshrc (or
                // the bash/fish equivalents) are read. The script is plain enough for
                // sh, zsh, bash and fish alike.
                shell,
                ["-l", "-i", "-c",
                 "printf '\\n\(beginMarker)\\n'; /usr/bin/env -0; printf '\\n\(endMarker)\\n'"],
                environment: environment,
                // Empty and closed, where it was /dev/null: either way the shell reads
                // EOF and nothing waits on a terminal.
                standardInput: Data(),
                standardError: .discard,
                onCancel: .runToCompletion,
                onLaunch: { launched.set($0) },
                beforeSpawn: beforeSpawn)
        }
        guard case .finished(let outcome) = await race(
            runner, launched: launched, within: timeout, timerExited: timerExited,
            sleep: sleep) else {
            // SIGKILL, not SIGTERM: an interactive zsh ignores SIGTERM, so the
            // shell — and whatever in the rc file it is stuck waiting on — would keep
            // running, one more for every check. The shell's descendants are collected
            // first, while they are still its children, since killing the shell
            // reparents them and leaves nothing to find them by. SIGSTOP first, so a
            // shell looping in its rc can't start a new child between the listing
            // and the kill. The pid cannot have been reused: `ChildProcess` has not
            // reaped the shell yet.
            // The race only times out after a launch, so the pid is there.
            if let pid = launched.value {
                kill(pid, SIGSTOP)
                for victim in descendants(of: pid) + [pid] { kill(victim, SIGKILL) }
                _ = await runner.value
            }
            return nil
        }
        guard let outcome else { return nil }
        return parse(outcome.standardOutput)
    }

    private enum Race: Sendable {
        case finished(ChildProcess.Outcome?)
        case timedOut
    }

    /// `runner`'s value if it lands within `seconds` of the shell's launch, else
    /// `.timedOut` — without waiting for `runner`, which a task group would do. A
    /// runner that finishes without ever launching (the spawn failed) wins the race.
    ///
    /// The runner finishing cancels the timer. Without that, a spawn that fails
    /// (a `pw_shell` naming a shell that is not installed) left the timer parked
    /// in `waitForLaunch` for good: one leaked task per workbench refresh.
    private static func race(
        _ runner: Task<ChildProcess.Outcome?, Never>, launched: LaunchedPID,
        within seconds: TimeInterval, timerExited: (@Sendable () -> Void)?,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async -> Race {
        let once = OnceRace()
        return await withCheckedContinuation { continuation in
            once.arm(continuation)
            let timer = Task {
                defer { timerExited?() }
                do {
                    try await launched.waitForLaunch()
                    try await sleep(.seconds(seconds))
                    once.resume(.timedOut)
                } catch {}
            }
            Task {
                let value = await runner.value
                timer.cancel()
                once.resume(.finished(value))
            }
        }
    }

    private final class OnceRace: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Race, Never>?
        func arm(_ c: CheckedContinuation<Race, Never>) { lock.withLock { continuation = c } }
        func resume(_ value: Race) {
            let c: CheckedContinuation<Race, Never>? = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            c?.resume(returning: value)
        }
    }

    /// The shell's pid once it has launched. Same shape as `ChildProcess`'s
    /// `LaunchSignal`: one waiter, released by the launch or by cancellation.
    private final class LaunchedPID: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t?
        private var waiter: CheckedContinuation<Void, Never>?

        func set(_ value: pid_t) {
            let resume: CheckedContinuation<Void, Never>? = lock.withLock {
                pid = value
                defer { waiter = nil }
                return waiter
            }
            resume?.resume()
        }

        var value: pid_t? { lock.withLock { pid } }

        /// Returns once `set` has been called; throws `CancellationError` if the
        /// waiting task is cancelled first, which is how `race` releases it when
        /// the launch never happens.
        func waitForLaunch() async throws {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let now: Bool = lock.withLock {
                        if pid != nil || Task.isCancelled { return true }
                        waiter = continuation
                        return false
                    }
                    if now { continuation.resume() }
                }
            } onCancel: {
                let resume: CheckedContinuation<Void, Never>? = lock.withLock {
                    defer { waiter = nil }
                    return waiter
                }
                resume?.resume()
            }
            try Task.checkCancellation()
        }
    }

    /// Every live descendant of `pid`, deepest first. Children that already detached
    /// (double-forked daemons) have been reparented and aren't found — those were
    /// never going to hold the shell up.
    private static func descendants(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        // The size argument is in bytes, but the return value is a pid COUNT
        // (measured: three children → 3, not 12).
        let count = buffer.withUnsafeMutableBytes { raw in
            proc_listchildpids(pid, raw.baseAddress, Int32(raw.count))
        }
        guard count > 0 else { return [] }
        let children = buffer.prefix(min(Int(count), buffer.count)).filter { $0 > 0 }
        return children.flatMap { descendants(of: $0) + [$0] }
    }

    /// The `HOMEBREW_*` entries between the markers of `env -0` output. nil when
    /// either marker is missing. Anything the rc files print before or after
    /// (banners, `fortune`, warnings) is outside the markers and ignored.
    static func parse(_ data: Data) -> [String: String]? {
        let begin = Data("\n\(beginMarker)\n".utf8)
        let end = Data("\n\(endMarker)\n".utf8)
        guard let beginRange = data.range(of: begin),
              let endRange = data.range(of: end, in: beginRange.upperBound..<data.endIndex)
        else { return nil }
        let body = data[beginRange.upperBound..<endRange.lowerBound]
        var variables: [String: String] = [:]
        for entry in body.split(separator: 0) {
            guard let text = String(data: Data(entry), encoding: .utf8),
                  text.hasPrefix("HOMEBREW_"),
                  let equals = text.firstIndex(of: "=")
            else { continue }
            variables[String(text[..<equals])] = String(text[text.index(after: equals)...])
        }
        return variables
    }

    /// The account's login shell from the user database — not `$SHELL`, which a GUI
    /// app inherits from launchd rather than from the user's choice.
    private static func loginShellPath() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return nil }
        let path = String(cString: shell)
        return path.isEmpty ? nil : path
    }
}

extension HomebrewConfig {
    /// Run `brew config` with the user's shell-exported variables added. nil when
    /// brew is missing, fails, or prints no version.
    ///
    /// Deliberately NOT `HOMEBREW_NO_AUTO_UPDATE=1` like the read paths in
    /// `BrewFormulaService`: this read is how we learn whether the *user* set it,
    /// and injecting our own would make every answer "disabled". `brew config`
    /// doesn't auto-update (it isn't in `setup-auto-update`'s command list).
    ///
    /// Awaited through `ChildProcess`; stderr discarded, as before, and drained.
    /// Runs to completion if the caller is cancelled, like the hop it replaced: a
    /// `nil` here reads as "config unreadable" and hides the row.
    public static func read(environment extra: [String: String]) async -> HomebrewConfig? {
        guard let brew = HomebrewInstaller.brewPath() else { return nil }
        var env = ProcessInfo.processInfo.environmentWithSystemProxy
        env.merge(extra) { _, user in user }
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        guard let outcome = try? await ChildProcess.run(
            brew, ["config"], environment: env,
            standardError: .discard, onCancel: .runToCompletion),
              outcome.succeeded
        else { return nil }
        return parse(String(decoding: outcome.standardOutput, as: UTF8.self))
    }
}

/// The latest Homebrew release tag from GitHub, remembered for six hours so opening
/// the workbench repeatedly doesn't spend the unauthenticated API budget (60/h,
/// shared with every other GitHub check).
public actor HomebrewLatestRelease {
    public static let shared = HomebrewLatestRelease()

    private let session: URLSession
    private let ttl: TimeInterval
    private var cached: (tag: String, fetchedAt: Date)?

    public init(session: URLSession = .updates, ttl: TimeInterval = 6 * 60 * 60) {
        self.session = session
        self.ttl = ttl
    }

    /// nil on any failure (offline, rate-limited, unexpected body). Only successes
    /// are cached, so a failure is retried on the next check.
    public func latestTag(token: String?) async -> String? {
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < ttl { return cached.tag }
        guard let url = URL(string: "https://api.github.com/repos/Homebrew/brew/releases/latest")
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await session.countedData(for: request, purpose: .versionCheck),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let tag = Self.tagName(from: data)
        else { return nil }
        cached = (tag, Date())
        return tag
    }

    static func tagName(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String, !tag.isEmpty
        else { return nil }
        return tag
    }
}

/// Decides whether to offer a Homebrew update, honouring the user's own config.
public enum HomebrewSelfUpdateCheck {
    public struct Outcome: Sendable, Equatable {
        /// nil = show nothing.
        public let update: HomebrewSelfUpdate?
        /// The user's shell-exported `HOMEBREW_*` variables, to pass to the
        /// `brew update` this offers — so e.g. a `HOMEBREW_DEVELOPER` set only in
        /// `~/.zshrc` keeps following `main` instead of being moved to a tag.
        public let environment: [String: String]

        public static let hidden = Outcome(update: nil, environment: [:])
    }

    /// Fails closed at every step: if we can't read the user's shell environment or
    /// brew's config, we can't know they didn't disable auto-update, so nothing is
    /// offered. The token is asked for only once the config says an update may be
    /// offered — resolving one can spawn `gh auth token`.
    public static func run(token: @Sendable () async -> String?) async -> Outcome {
        guard HomebrewInstaller.brewPath() != nil else { return .hidden }
        // Each hidden outcome is logged with its reason: a row that silently never
        // appears is otherwise indistinguishable from "Homebrew is up to date".
        guard let shell = await LoginShellEnvironment.resolveHomebrewVariables() else {
            Log.app.notice("brew self-update: hidden — login shell environment unreadable")
            return .hidden
        }
        guard let config = await HomebrewConfig.read(environment: shell) else {
            Log.app.notice("brew self-update: hidden — `brew config` unreadable")
            return .hidden
        }
        guard !config.autoUpdateDisabled else {
            Log.app.info("brew self-update: hidden — HOMEBREW_NO_AUTO_UPDATE is set")
            return .hidden
        }
        let latest = await HomebrewLatestRelease.shared.latestTag(token: await token())
        let update = HomebrewSelfUpdatePolicy.update(config: config, latestTag: latest)
        Log.app.info("brew self-update: installed=\(config.version, privacy: .public) latest=\(latest ?? "unknown", privacy: .public) offer=\(update != nil, privacy: .public)")
        return Outcome(update: update, environment: shell)
    }
}
