import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running Deno's one-click update. The deno is a shell script whose `upgrade`
/// does what 2.9.6's did to a scratch HOME on 2026-10-09 — prints its lines and
/// renames a new file over its own path (a new inode) — and records the
/// environment it saw. Nothing here reaches the network or runs a real deno.
@Suite struct DenoUpdaterTests {

    /// A deno whose `upgrade` leaves `to`, signed as `signer`.
    static func upgrading(to version: String = "2.9.7", signer: String = "deno", channel: String = "stable") -> String {
        DenoSandbox.script(body: """
        env > "$HOME/ENV"
        if [ "$1" = upgrade ]; then
          echo "Current Deno version: v2.9.6"
          new="$TMPDIR/deno-new"
          # Spelled with %s, so this file holds one version literal, not two.
          printf '#!/bin/sh\\n# %s/%s+0c07124\\n# %s:%s\\n# %s:%s:%s\\n' Deno '\(version)' SIGNER '\(signer)' REPORT '\(version)' '\(channel)' > "$new"
          chmod +x "$new"
          mv -f "$new" "$0"
          echo "Upgraded successfully to Deno v\(version) (stable)"
          exit 0
        fi
        """)
    }

    static func environment(_ box: DenoSandbox) -> [String: String] {
        let text = (try? String(contentsOf: box.home.appendingPathComponent("ENV"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    static func updater(
        _ box: DenoSandbox, latest: String = "2.9.7", busy: @escaping DenoUpdater.BusyCheck = { _ in nil },
        environment: [String: String] = [:]
    ) -> DenoUpdater {
        DenoUpdater(busy: busy, scanner: box.scanner, check: DenoTests.check(latest), environment: { environment })
    }

    @Test func upgradesAndChecksWhatItLeft() async throws {
        let box = try DenoSandbox()
        try box.install(Self.upgrading())
        let status = try await DenoTests.status(box)
        let outcome = await Self.updater(
            box, environment: ["HOME": "/elsewhere", "PATH": "/x", "DENO_TESTING_UPGRADE": "1",
                               "DENO_DONT_USE_INTERNAL_BASE_UPGRADE_URL": "http://127.0.0.1:1", "https_proxy": "http://127.0.0.1:9"]
        ).update(status)
        #expect(outcome == .updated(version: "2.9.7"))
        let env = Self.environment(box)
        #expect(env["HOME"] == box.home.path)
        #expect(env["PATH"] == CLIToolCommandRunner.systemPath)
        #expect(env["DENO_TESTING_UPGRADE"] == nil)
        #expect(env["DENO_DONT_USE_INTERNAL_BASE_UPGRADE_URL"] == nil)
        #expect(env["https_proxy"] == "http://127.0.0.1:9")
        let tmp = try #require(env["TMPDIR"])
        #expect(tmp.contains("duo-deno-"))
        #expect(!FileManager.default.fileExists(atPath: tmp))
    }

    /// Mutation: dropping the signature guard in `verdict` reports `.updated`.
    @Test func aResultNotSignedByDenoLandIsAFailure() async throws {
        let box = try DenoSandbox()
        try box.install(Self.upgrading(signer: "adhoc"))
        let outcome = await Self.updater(box).update(try await DenoTests.status(box))
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.contains("not signed by Deno Land"))
    }

    /// Mutation: dropping the newer-version guard in `verdict`.
    @Test func exitZeroWithNothingNewIsAFailure() async throws {
        let box = try DenoSandbox()
        try box.install(DenoSandbox.script(body: "echo 'Local deno version 2.9.6 is the most recent release'; exit 0"))
        let outcome = await Self.updater(box).update(try await DenoTests.status(box))
        #expect(outcome == .failed(message: "deno upgrade finished, but Deno is still 2.9.6",
                                   output: "Local deno version 2.9.6 is the most recent release"))
    }

    /// The release channel moved back between the check and the click.
    /// Mutation: drop the re-read of the channel in `update`.
    @Test func neverRunsTowardAnOlderChannel() async throws {
        let box = try DenoSandbox()
        try box.install(Self.upgrading())
        let status = try await DenoTests.status(box)
        let outcome = await Self.updater(box, latest: "2.9.6").update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.hasPrefix("not run:"))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }

    /// The file became an LTS build between the check and the click.
    /// Mutation: drop the `reported == stable` re-check in `update`.
    @Test func notRunWhenTheFileIsNoLongerStable() async throws {
        let box = try DenoSandbox()
        try box.install(Self.upgrading())
        let status = try await DenoTests.status(box)
        try box.install(DenoSandbox.script(channel: "lts", body: "env > \"$HOME/ENV\""))
        let outcome = await Self.updater(box).update(status)
        guard case .failed(let message, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message.contains("not a stable Deno 2.9.6 build"))
        #expect(!FileManager.default.fileExists(atPath: box.home.appendingPathComponent("ENV").path))
    }

    @Test func busyIsNotRun() async throws {
        let box = try DenoSandbox()
        try box.install(Self.upgrading())
        let outcome = await Self.updater(box, busy: { _ in .upgrade(pid: 9) }).update(try await DenoTests.status(box))
        #expect(outcome == .busy("deno upgrade is running (pid 9)"))
    }

    /// Deno's own words and the exit status, as 2.9.7 printed them for a
    /// release that does not exist (scratch HOME, 2026-10-09).
    /// Mutation: drop the exit status from `failureMessage`.
    @Test func aFailedUpgradeSaysWhyAndHowItExited() async throws {
        let box = try DenoSandbox()
        try box.install(DenoSandbox.script(body: """
        echo "Current Deno version: v2.9.6"
        echo "Downloading https://github.com/denoland/deno/releases/download/v2.9.7/deno-aarch64-apple-darwin.zip"
        echo "Download could not be found, aborting" >&2
        exit 1
        """))
        let outcome = await Self.updater(box).update(try await DenoTests.status(box))
        guard case .failed(let message, let output) = outcome else { Issue.record("\(outcome)"); return }
        #expect(message == "deno upgrade: Download could not be found, aborting (exit 1)")
        #expect(output.contains("Current Deno version: v2.9.6"))

        let lines = ["Current Deno version: v2.9.6", "error: You do not have write permission to /x/deno"]
        let outcome2 = ChildProcess.Outcome(terminationStatus: 1, uncaughtSignal: false, timedOut: false,
                                            standardOutput: Data(), standardError: Data())
        #expect(DenoUpdater.failureMessage(lines, outcome2, deadline: DenoUpdater.defaultDeadline)
            == "deno upgrade: You do not have write permission to /x/deno (exit 1)")
    }
}
