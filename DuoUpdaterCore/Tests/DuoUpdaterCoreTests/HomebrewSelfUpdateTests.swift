import Testing
import Foundation
@testable import DuoUpdaterCore

/// Whether the workbench offers `brew update`, and what it reads to decide.
///
/// `brew config` output is a captured fixture (Homebrew 7.0.0, 2026-09-13) rather
/// than a live read, per CLAUDE.md "测试不能问宿主": whether this machine's brew is
/// current, or its user disabled auto-update, must not change a test's answer.
@Suite struct HomebrewSelfUpdateTests {

    /// Head of a real `brew config`, with the user-set variables section appended
    /// by each test.
    private static let configHead = """
        HOMEBREW_VERSION: 6.0.22-310-ga45b0a0
        ORIGIN: https://github.com/Homebrew/brew
        HEAD: a45b0a0143000000000000000000000000000000
        Last commit: 2 hours ago
        Branch: main
        Core tap: N/A
        Core cask tap: N/A
        HOMEBREW_PREFIX: /opt/homebrew
        """

    // MARK: - brew config

    /// Mutation: parse the version from the wrong key, or not at all → nil/other.
    @Test func readsTheVersionAndDefaultsToAutoUpdateOn() {
        let config = HomebrewConfig.parse(Self.configHead)
        #expect(config == HomebrewConfig(version: "6.0.22-310-ga45b0a0", autoUpdateDisabled: false))
    }

    /// Mutation: drop the `HOMEBREW_NO_AUTO_UPDATE` branch → reads as enabled.
    @Test func noAutoUpdateSetDisablesIt() {
        let config = HomebrewConfig.parse(Self.configHead + "\nHOMEBREW_NO_AUTO_UPDATE: set\nHOMEBREW_NO_ENV_HINTS: set")
        #expect(config?.autoUpdateDisabled == true)
    }

    /// brew prints boolean variables as `set` or `false`. Mutation: treat the key's
    /// mere presence as "disabled" → this user, who explicitly has auto-update on,
    /// would never be offered the update.
    @Test func noAutoUpdateFalseLeavesItOn() {
        let config = HomebrewConfig.parse(Self.configHead + "\nHOMEBREW_NO_AUTO_UPDATE: false")
        #expect(config?.autoUpdateDisabled == false)
    }

    /// Mutation: return a config with an empty version → the policy would get a
    /// value it can't parse instead of a clear "no config".
    @Test func noVersionLineIsNoConfig() {
        #expect(HomebrewConfig.parse("ORIGIN: https://github.com/Homebrew/brew\nBranch: stable") == nil)
    }

    // MARK: - Policy

    private func offer(_ installed: String, _ latest: String?, disabled: Bool = false) -> HomebrewSelfUpdate? {
        HomebrewSelfUpdatePolicy.update(
            config: HomebrewConfig(version: installed, autoUpdateDisabled: disabled),
            latestTag: latest)
    }

    /// Mutation: invert or drop the comparison → no offer when behind.
    @Test func behindTheLatestReleaseIsOffered() {
        #expect(offer("6.0.22", "7.0.0") == HomebrewSelfUpdate(installed: "6.0.22", latest: "7.0.0"))
    }

    /// Mutation: `<=` instead of strictly-less → the row never goes away after updating.
    @Test func onTheLatestReleaseIsNotOffered() {
        #expect(offer("7.0.0", "7.0.0") == nil)
    }

    /// Mutation: drop the `autoUpdateDisabled` guard → offered to a user who opted out.
    @Test func disabledAutoUpdateHidesEvenWhenBehind() {
        #expect(offer("6.0.22", "7.0.0", disabled: true) == nil)
    }

    /// A developer-mode checkout follows `main`, so its version carries a
    /// `git describe` suffix. Mutation: stop accepting the suffix → a developer
    /// who is a whole release behind is never told.
    @Test func developerCheckoutBehindAReleaseIsOffered() {
        #expect(offer("6.0.22-310-ga45b0a0", "7.0.0")?.installed == "6.0.22-310-ga45b0a0")
        #expect(offer("6.0.22-dirty", "7.0.0") != nil)
        #expect(offer("6.0.22-4-g1a2b3c4-dirty", "7.0.0") != nil)
    }

    /// Mutation: compare against the commit count, or treat any suffix as "behind"
    /// → a developer already past the release sees the row permanently.
    @Test func developerCheckoutPastTheReleaseIsNotOffered() {
        #expect(offer("7.0.0-3-gd79ef82", "7.0.0") == nil)
    }

    /// Mutation: compare version strings instead of numbers → "6.10.0" < "6.9.9".
    @Test func componentsCompareNumerically() {
        #expect(offer("6.9.9", "6.10.0") != nil)
        #expect(offer("6.10.0", "6.9.9") == nil)
    }

    /// Anything we can't read is "can't say an update is wanted". Mutation: fall
    /// back to offering when a side doesn't parse.
    @Test func unreadableVersionsAreNotOffered() {
        #expect(offer(">=4.3.0 (shallow or no git repository)", "7.0.0") == nil)
        #expect(offer("6.0.22", nil) == nil)
        #expect(offer("6.0.22", "7.0.0-rc1") == nil)
        // The latest tag is a release, never a describe string.
        #expect(offer("6.0.22", "7.0.0-3-gd79ef82") == nil)
        #expect(HomebrewSelfUpdatePolicy.update(config: nil, latestTag: "7.0.0") == nil)
    }

    // MARK: - GitHub response

    @Test func readsTheTagName() {
        #expect(HomebrewLatestRelease.tagName(from: Data(#"{"tag_name":"7.0.0","name":"7.0.0"}"#.utf8)) == "7.0.0")
        #expect(HomebrewLatestRelease.tagName(from: Data(#"{"message":"API rate limit exceeded"}"#.utf8)) == nil)
    }

    // MARK: - Login shell environment

    private func envOutput(_ entries: [String], before: String = "", after: String = "") -> Data {
        var data = Data(before.utf8)
        data.append(Data("\n\(LoginShellEnvironment.beginMarker)\n".utf8))
        for entry in entries { data.append(Data(entry.utf8)); data.append(0) }
        data.append(Data("\n\(LoginShellEnvironment.endMarker)\n".utf8))
        data.append(Data(after.utf8))
        return data
    }

    /// Keeps only `HOMEBREW_*`, splits entries on NUL and each on its first `=`.
    /// Mutations: split on newlines (the multi-line value breaks), split on the
    /// last `=` (the URL value breaks), or keep every variable.
    @Test func parsesOnlyHomebrewVariablesBetweenTheMarkers() {
        let data = envOutput(
            ["PATH=/usr/bin:/bin",
             "HOMEBREW_NO_AUTO_UPDATE=1",
             "HOMEBREW_BREW_GIT_REMOTE=https://example.invalid/brew.git?a=b",
             "HOMEBREW_ZZFIXTURE_MULTILINE=line one\nHOMEBREW_NOT_A_KEY=line two"],
            before: "Welcome back!\nHOMEBREW_BANNER=printed by an rc file\n",
            after: "HOMEBREW_TRAILER=also printed by an rc file\n")
        #expect(LoginShellEnvironment.parse(data) == [
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_BREW_GIT_REMOTE": "https://example.invalid/brew.git?a=b",
            "HOMEBREW_ZZFIXTURE_MULTILINE": "line one\nHOMEBREW_NOT_A_KEY=line two",
        ])
    }

    /// An empty map means "the user set nothing" and lets the row show; a shell that
    /// died half-way must not be read that way. Mutation: return what was parsed
    /// so far when the end marker is missing.
    @Test func missingEndMarkerIsUnknownNotEmpty() {
        var data = Data("\n\(LoginShellEnvironment.beginMarker)\n".utf8)
        data.append(Data("HOMEBREW_NO_AUTO_UPDATE=1".utf8)); data.append(0)
        #expect(LoginShellEnvironment.parse(data) == nil)
        #expect(LoginShellEnvironment.parse(Data()) == nil)
    }

    /// A real zsh reading fixture rc files (HOME and ZDOTDIR point at a temp dir,
    /// never the host's). Covers what the parser tests can't: the `-l -i -c` script
    /// actually produces parseable output, and an rc file that leaves a background
    /// child holding stdout doesn't stall the read.
    ///
    /// Not reading the background child's pipe to EOF is `ChildProcess`'s
    /// behaviour now (it stops at the shell's exit), so the mutation that used to
    /// be named here — read a pipe to EOF — has no place left to go. What is pinned
    /// is that the call still returns with the shell's answer and not with the
    /// `timeout`'s nil: mutation `timeout: 20` → an immediate timeout (race the
    /// runner against `.seconds(0)`) → nil.
    ///
    /// The 60 s watchdog is not a performance bound (the real call returns in well
    /// under a second); it only has to sit between "returns normally" and "waits
    /// for the child", which are two orders of magnitude apart. It resumes a
    /// continuation instead of cancelling anything, so it fires even if the call
    /// under test never yields.
    @Test func readsVariablesExportedByAFixtureZshrc() async throws {
        // A per-run duration, so the background `sleep` this rc leaves behind can be
        // found and killed afterwards instead of outliving the test for two minutes.
        let marker = "120.\(Int.random(in: 100_000...999_999))"
        let home = try Self.fixtureHome(zshrc: """
            echo "rc banner"
            export HOMEBREW_NO_AUTO_UPDATE=1
            sleep \(marker) &
            """)
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = Self.fixtureEnvironment(home: home)
        let box = ResultBox()
        let finished = await Self.within(seconds: 60) {
            box.value = await LoginShellEnvironment.resolveHomebrewVariables(
                shell: "/bin/zsh", environment: environment, timeout: 20)
        }
        #expect(finished)
        #expect(box.value?["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        for pid in await Self.processes(matching: "sleep \(marker)") { kill(pid, SIGKILL) }
    }

    /// True when `body` finished within `seconds`. Resumes on whichever comes
    /// first and abandons the other, so a `body` that never returns is a false,
    /// not a stuck suite.
    private static func within(seconds: Double, _ body: @escaping @Sendable () async -> Void) async -> Bool {
        final class Once: @unchecked Sendable {
            let lock = NSLock()
            var continuation: CheckedContinuation<Bool, Never>?
            func resume(_ value: Bool) {
                let c: CheckedContinuation<Bool, Never>? = lock.withLock {
                    defer { continuation = nil }
                    return continuation
                }
                c?.resume(returning: value)
            }
        }
        let once = Once()
        return await withCheckedContinuation { continuation in
            once.lock.withLock { once.continuation = continuation }
            Task { await body(); once.resume(true) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { once.resume(false) }
        }
    }

    /// The timeout counts from the shell's launch. A clock started at the call
    /// would give up before the shell existed — returning nil with no pid to kill,
    /// and leaving the shell to start unwatched.
    ///
    /// The timer's clock is injected, so nothing here races real time. A timer
    /// that starts sleeping while the spawn is still being held back finds its
    /// timeout already spent (the pre-launch wait outlasted it), and gives up; one
    /// that starts after the launch sleeps until the shell has answered and it is
    /// cancelled. The spawn is held for 2 s or until a timer starts, whichever is
    /// first, which only has to give a timer started at the call time to show
    /// itself. It replaced a real 8 s wait against a real 5 s timeout: on the
    /// 3-core runner, with the #763 backup tests in the same process, that 8 s
    /// sleep took up to 34 s and the shell's answer took up to 10 s to come back
    /// after launch (its rc files ran in ≤ 1.1 s; 20 instrumented runs,
    /// 2026-09-22), so the real timeout won 5 times in 77 CI runs from 09-19.
    ///
    /// Mutation: drop `try await launched.waitForLaunch()` from `race` → nil.
    @Test func theTimeoutCountsFromTheShellsLaunch() async throws {
        let home = try Self.fixtureHome(zshrc: "export HOMEBREW_NO_AUTO_UPDATE=1")
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = Self.fixtureEnvironment(home: home)
        let timerStarted = Flag()
        let spawnReleased = Flag()
        let variables = await LoginShellEnvironment.resolveHomebrewVariables(
            shell: "/bin/zsh", environment: environment, timeout: 5,
            beforeSpawn: {
                _ = await Self.within(seconds: 2) { await timerStarted.wait() }
                spawnReleased.set()
            },
            sleep: { _ in
                timerStarted.set()
                guard spawnReleased.value else { return }
                try await Task.sleep(for: .seconds(600))
            })
        #expect(variables?["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    }

    /// A shell that cannot start (a `pw_shell` naming one that is not installed)
    /// makes the runner win the race, and the timer that was waiting for a launch
    /// is released, not left parked for the life of the process. Not a timing
    /// test: the timeout is ten minutes, so the timer can only end by being
    /// released; the 60 s bound only turns a regression into a failure instead of
    /// a hang.
    ///
    /// Mutations: drop `timer.cancel()` in `race`, or drop the resume in
    /// `waitForLaunch`'s cancellation handler → the timer never exits.
    @Test func aShellThatCannotStartLeavesNoTimerBehind() async {
        let exited = Flag()
        let variables = await LoginShellEnvironment.resolveHomebrewVariables(
            shell: "/nonexistent/ZZFixture-shell", environment: [:], timeout: 600,
            timerExited: { exited.set() })
        #expect(variables == nil)
        let released = await Self.within(seconds: 60) { await exited.wait() }
        #expect(released, "the launch timer is still parked")
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var isSet = false
        private var waiter: CheckedContinuation<Void, Never>?
        var value: Bool { lock.withLock { isSet } }
        func set() {
            let c: CheckedContinuation<Void, Never>? = lock.withLock {
                isSet = true
                defer { waiter = nil }
                return waiter
            }
            c?.resume()
        }
        func wait() async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let now: Bool = lock.withLock {
                    if isSet { return true }
                    waiter = c
                    return false
                }
                if now { c.resume() }
            }
        }
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String: String]?
        var value: [String: String]? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    /// Mutation: return an empty map on timeout → reads as "nothing set". Ignoring
    /// the timeout altogether never returns (the rc below loops forever), so that
    /// one surfaces as a hung run, not a red test.
    ///
    /// Also: giving up must not leave the stuck shell behind. The rc's `sleep` has a
    /// per-run duration so this test can find exactly its own process.
    ///
    /// The rc hangs in a loop on purpose. Measured 2026-09-13 with Foundation's
    /// `Process`: `terminate()` DID end an rc that was a single `sleep 30` (also
    /// with `trap '' TERM` in front), so a fixture like that cannot catch a
    /// `terminate()` regression — but an rc looping `while :; do sleep 1; done` left
    /// the shell alive and spawning new children. Why the two differ was not
    /// established; the loop is simply the shape observed to leak.
    ///
    /// Mutations: SIGTERM instead of SIGSTOP + SIGKILL → the loop keeps starting
    /// new `sleep`s; kill only the shell → the current `sleep` is reparented and
    /// survives; miscount `proc_listchildpids` → same as killing only the shell;
    /// `ChildProcess` never reports the pid (`onLaunch` not called) → the timeout,
    /// which counts from launch, never starts: the call never returns and the 60 s
    /// watchdog fails the test (the leaked shell is killed by parent pid below).
    ///
    /// Not timing-sensitive: the rc loops forever, so the only way to finish is
    /// the timeout firing, and it starts only once the shell exists.
    @Test func aShellThatHangsIsUnknownAndKilled() async throws {
        let marker = "30.\(Int.random(in: 100_000...999_999))"
        let home = try Self.fixtureHome(zshrc: "while :; do sleep \(marker); done")
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = Self.fixtureEnvironment(home: home)
        let box = ResultBox()
        let returned = await Self.within(seconds: 60) {
            box.value = await LoginShellEnvironment.resolveHomebrewVariables(
                shell: "/bin/zsh", environment: environment, timeout: 1) ?? [:]
        }
        #expect(returned, "the call never returned")
        #expect(box.value == [:], "a hung shell must read as unknown (nil)")
        if !returned {
            for pid in await Self.processes(matching: "sleep \(marker)") {
                var info = proc_bsdinfo()
                if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 {
                    kill(pid_t(info.pbi_ppid), SIGKILL)
                }
                kill(pid, SIGKILL)
            }
        }
        // SIGKILL delivery is asynchronous; allow it a moment before calling it a leak.
        var survivors = await Self.processes(matching: "sleep \(marker)")
        for _ in 0..<20 where !survivors.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            survivors = await Self.processes(matching: "sleep \(marker)")
        }
        #expect(survivors.isEmpty, "leaked: \(survivors)")
        for pid in survivors { kill(pid, SIGKILL) }
    }

    private static func processes(matching pattern: String) async -> [pid_t] {
        guard let pgrep = try? await ChildProcess.run(
            "/usr/bin/pgrep", ["-f", pattern], onCancel: .terminateChild)
        else { return [] }
        return String(decoding: pgrep.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
    }

    private static func fixtureHome(zshrc: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-login-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try zshrc.write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        return home
    }

    private static func fixtureEnvironment(home: URL) -> [String: String] {
        ["HOME": home.path, "ZDOTDIR": home.path, "PATH": "/usr/bin:/bin", "USER": NSUserName()]
    }
}
