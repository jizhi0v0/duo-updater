import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running mise's one-click update. The mise is a shell script whose
/// `self-update` does what 2026.10.3's did to a scratch HOME on 2026-10-09 —
/// prints its lines and replaces its own file by rename — and records its
/// arguments and environment. Nothing here reaches the network or runs a real
/// mise.
@Suite struct MiseUpdaterTests {

    static func updating(to version: String = "2026.10.4", signer: String = "jdx", extra: String = "") -> String {
        MiseSandbox.script(body: """
        env > "$HOME/ENV"
        echo "$@" > "$HOME/ARGS"
        \(extra)
        if [ "$1" = self-update ]; then
          echo "Selected mise \(version) (minimum release age: 24h)"
          new="$TMPDIR/mise-new"
          printf '#!/bin/sh\\n# %s:%s\\n# %s:%s\\n' VERSION '\(version)' SIGNER '\(signer)' > "$new"
          chmod +x "$new"
          mv -f "$new" "$0"
          echo "Updated mise to \(version)"
          exit 0
        fi
        """)
    }

    static func environment(_ home: URL) -> [String: String] {
        let text = (try? String(contentsOf: home.appendingPathComponent("ENV"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    static func updater(
        _ box: MiseSandbox, latest: String = "2026.10.4", busy: @escaping MiseUpdater.BusyCheck = { _ in nil },
        environment: [String: String] = [:], token: String? = nil
    ) -> MiseUpdater {
        MiseUpdater(busy: busy, scanner: box.scanner, check: MiseTests.check(latest), environment: { environment },
                    token: { token })
    }

    /// The app's GitHub token is handed to mise only after mise said it found
    /// none of its own and GitHub's API refused it — the two lines 2026.10.5
    /// printed with the anonymous budget spent (2026-10-11) — and then for one
    /// more run, as `MISE_GITHUB_TOKEN`. Up front it would outrank the user's
    /// own `credential_command`, `gh` login or tokens file.
    /// Kills: handing it on the first run; no retry; retrying a 403 mise met
    /// with a token of its own; retrying with no token to give.
    @Test func theAppsGitHubTokenIsHandedOnOnlyWhenMiseHadNone() async throws {
        let noToken = """
        echo "mise WARN  GitHub API returned a 403 Forbidden error. This is most commonly caused by exceeding the rate limit, though other causes (e.g. insufficient token permissions) are possible." >&2
        echo "mise WARN  No GitHub token was found, so mise is making unauthenticated requests to GitHub which have a much lower rate limit." >&2
        echo "mise ERROR HTTP status client error (403 Forbidden) for url (https://api.github.com/repos/jdx/mise/releases/tags/v2026.10.4)" >&2
        exit 1
        """
        let ownToken = """
        echo "mise WARN  GitHub API returned a 403 Forbidden error. This is most commonly caused by exceeding the rate limit, though other causes (e.g. insufficient token permissions) are possible." >&2
        echo "mise ERROR HTTP status client error (403 Forbidden) for url (https://api.github.com/repos/jdx/mise/releases/tags/v2026.10.4)" >&2
        exit 1
        """
        for (token, failure, runs, updated) in [
            ("ZZFixture-token", nil, ["run:"], true),
            ("ZZFixture-token", noToken, ["run:", "run:ZZFixture-token"], true),
            ("ZZFixture-token", ownToken, ["run:"], false),
            (nil, noToken, ["run:"], false),
        ] as [(String?, String?, [String], Bool)] {
            let box = try MiseSandbox()
            var extra = "echo \"run:$MISE_GITHUB_TOKEN\" >> \"$HOME/RUNS\""
            if let failure { extra += "\nif [ -z \"$MISE_GITHUB_TOKEN\" ]; then\n\(failure)\nfi" }
            try box.install(Self.updating(extra: extra))
            let outcome = await Self.updater(box, token: token).update(try await MiseTests.status(box))
            let ran = try String(contentsOf: box.home.appendingPathComponent("RUNS"), encoding: .utf8)
            #expect(ran.split(separator: "\n").map(String.init) == runs)
            if updated {
                #expect(outcome == .updated(version: "2026.10.4"))
            } else {
                #expect(outcome != .updated(version: "2026.10.4"))
            }
        }
    }

    /// The row's Cancel lands while the app's token is being looked up for the
    /// retry: the lookup comes back empty in the cancelled task, the retry
    /// never runs — and that is what the click stopped, so the row reads it as
    /// a cancel, not as the first run's 403.
    /// Mutation: drop the `noteRefusedCommit` in `update` → false, red.
    @Test func aCancelThatCutsTheTokenLookupStoppedTheRetry() async throws {
        let box = try MiseSandbox()
        try box.install(Self.updating(extra: """
        echo "run:$MISE_GITHUB_TOKEN" >> "$HOME/RUNS"
        echo "mise WARN  No GitHub token was found, so mise is making unauthenticated requests to GitHub which have a much lower rate limit." >&2
        echo "mise ERROR HTTP status client error (403 Forbidden) for url (https://api.github.com/repos/jdx/mise/releases/tags/v2026.10.4)" >&2
        exit 1
        """))
        let id = "zz-mise-\(UUID().uuidString)"
        let updater = MiseUpdater(
            busy: { _ in nil }, scanner: box.scanner, check: MiseTests.check("2026.10.4"), environment: { [:] },
            token: { InstallJobs.cancel(id); return nil })
        let status = try await MiseTests.status(box)
        let stopped = await InstallJobs.run(id) {
            _ = await updater.update(status)
            return InstallJobs.cancelStoppedSomething(id)
        }
        #expect(stopped)
        let ran = try String(contentsOf: box.home.appendingPathComponent("RUNS"), encoding: .utf8)
        #expect(ran == "run:\n")
    }

    @Test func updatesAndChecksWhatItLeft() async throws {
        let box = try MiseSandbox()
        try box.install(Self.updating())
        let status = try await MiseTests.status(box)
        let outcome = await Self.updater(
            box, environment: ["HOME": "/elsewhere", "MISE_SELF_UPDATE_REPOSITORY": "acme/mise",
                               "MISE_SELF_UPDATE_API_URL": "https://ghe.example/api/v3", "GITHUB_TOKEN": "t"]
        ).update(status)
        #expect(outcome == .updated(version: "2026.10.4"))
        let env = Self.environment(box.home)
        #expect(env["HOME"] == box.home.path)
        #expect(env["PATH"] == CLIToolCommandRunner.systemPath)
        #expect(env["MISE_SELF_UPDATE_REPOSITORY"] == nil && env["MISE_SELF_UPDATE_API_URL"] == nil)
        #expect(env["GITHUB_TOKEN"] == "t")
        let args = try String(contentsOf: box.home.appendingPathComponent("ARGS"), encoding: .utf8)
        #expect(args == "self-update -y --no-plugins\n")
    }

    /// mise exits 0 having changed nothing when its own minimum release age is
    /// longer than the default the row applied. Mutation: drop the
    /// newer-version guard in `verdict`.
    @Test func exitZeroWithNothingNewSaysWhatMisePicked() async throws {
        let box = try MiseSandbox()
        try box.install(MiseSandbox.script(body: """
        echo "Selected mise 2026.10.2 (minimum release age: 7d)"
        echo "mise is already up to date"
        exit 0
        """))
        let outcome = await Self.updater(box).update(try await MiseTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "mise self-update finished, but mise is still 2026.10.3 (Selected mise 2026.10.2 (minimum release age: 7d))")
    }

    /// Mutation: drop the signature guard in `verdict`.
    @Test func aResultNotSignedByItsTeamIsAFailure() async throws {
        let box = try MiseSandbox()
        try box.install(Self.updating(signer: "someone"))
        let outcome = await Self.updater(box).update(try await MiseTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.contains("not signed by Jeffrey Dickey"))
    }

    /// mise's own first `mise ERROR` line and the exit status, as 2026.10.4
    /// printed them for a packager's marker (scratch HOME, 2026-10-09).
    /// Mutation: take the last `mise ERROR` line instead of the first.
    @Test func aFailedUpdateSaysWhyAndHowItExited() async throws {
        let box = try MiseSandbox()
        try box.install(MiseSandbox.script(body: """
        echo "mise ERROR mise is installed via a package manager, cannot update" >&2
        echo "mise ERROR Version: 2026.10.3 macos-arm64 (2026-10-05)" >&2
        echo "mise ERROR Run with --verbose or MISE_VERBOSE=1 for more information" >&2
        exit 1
        """))
        let outcome = await Self.updater(box).update(try await MiseTests.status(box))
        guard case .failed(let message, let output) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "mise self-update: mise is installed via a package manager, cannot update (exit 1)")
        #expect(output.contains("Run with --verbose"))
    }

    /// Mutation: drop the re-read of the release index in `update`.
    @Test func neverRunsTowardAnOlderPick() async throws {
        let box = try MiseSandbox()
        try box.install(Self.updating())
        let status = try await MiseTests.status(box)
        let outcome = await Self.updater(box, latest: "2026.10.3").update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.hasPrefix("not run:"))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ARGS").path))
    }

    @Test func busyIsNotRun() async throws {
        let box = try MiseSandbox()
        try box.install(Self.updating())
        let outcome = await Self.updater(box, busy: { _ in .selfUpdate(pid: 4) }).update(try await MiseTests.status(box))
        #expect(outcome == .busy("mise self-update is running (pid 4)"))
    }
}
