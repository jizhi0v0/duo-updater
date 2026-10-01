import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running a Rust row's one-click update: what is run, with which environment,
/// and what the row is told.
///
/// "rustup" here is a `#!/bin/sh` script in a temporary `CARGO_HOME`. Its
/// sha256 is "published" by the fake server (`RustTests.Server`) as the version
/// the test says it is, so the trust rule is the real one. `self update` copies
/// `NEXT` beside it over itself, as rustup's `--self-replace` copies
/// `rustup-init`; `update <toolchain>` writes the toolchain's manifest under
/// `$RUSTUP_HOME`, so a child that did not get the row's homes fails the test.
/// The busy check and the base environment are injected; nothing reads the
/// host's process table or settings, runs the real rustup or reaches the
/// network.
@Suite struct RustUpdaterTests {

    typealias Sandbox = RustTests.Sandbox
    typealias Server = RustTests.Server

    static let script = """
        #!/bin/sh
        here="$(dirname "$0")"
        echo "$@" > "$here/ARGS"
        echo "$CARGO_HOME|$RUSTUP_HOME|$PATH|$https_proxy" > "$here/ENV"
        if [ "$1" = self ]; then
          echo 'info: checking for self-update (current version: 1.29.0)'
          [ -f "$here/FAIL" ] && { echo 'error: could not download file from x'; echo 'info: caused by y'; exit 1; }
          [ -f "$here/NEXT" ] && cp "$here/NEXT" "$here/rustup.tmp" && mv "$here/rustup.tmp" "$0"
          echo 'info: rustup updated - 1.29.1 (from 1.29.0)'
          exit 0
        fi
        if [ "$1" = update ]; then
          [ -f "$here/STAY" ] && exit 0
          printf '[pkg.rust]\\nversion = "1.99.0 (b940084d7 2026-09-28)"\\n' > "$RUSTUP_HOME/toolchains/$2/lib/rustlib/multirust-channel-manifest.toml"
          echo "  $2 updated - rustc 1.99.0 (b940084d7 2026-09-28) (from rustc 1.98.1 (48a229cea 2026-09-01))"
          exit 0
        fi
        exit 3
        """

    /// The installed rustup (claims 1.29.0, published as 1.29.0) and the build
    /// a self-update brings (`NEXT`, claims and is published as 1.29.1).
    static func install(_ box: Sandbox, _ server: Server, nextPublished: Bool = true) throws {
        let sha = try box.rustup(script + "\n# rustup/1.29.0 (\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.rustup.path)
        server.publishRustup("1.29.0", sha: sha)
        let next = script + "\n# rustup/1.29.1 (\n"
        try Data(next.utf8).write(to: box.cargo.appendingPathComponent("bin/NEXT"))
        server.publishRustup(
            "1.29.1", sha: nextPublished ? RustTests.sha256(next) : String(repeating: "e", count: 64), latest: true)
        server.publishChannel("stable", label: "1.99.0 (b940084d7 2026-09-28)")
        try box.toolchain("stable-aarch64-apple-darwin", label: "1.98.1 (48a229cea 2026-09-01)",
                          updateHash: "a7c8774a5fd8441c997d")
    }

    static func statuses(_ box: Sandbox, _ server: Server, settings: RustupSettings = RustupSettings()) async throws
        -> (rustup: CLIToolStatus, stable: CLIToolStatus)
    {
        let report = await RustProvider.report(
            rustup: box.scanner().rustup(), toolchains: box.scanner().toolchains(), settings: settings, busy: nil,
            check: RustCheck(release: server.release))
        let rustup = try #require(report.statuses.first { $0.name == "rustup" })
        let stable = try #require(report.statuses.first { $0.name == "stable-aarch64-apple-darwin" })
        _ = try #require(rustup.oneClick)
        _ = try #require(stable.oneClick)
        return (rustup, stable)
    }

    func updater(
        _ box: Sandbox, _ server: Server, busy: @escaping RustUpdater.BusyCheck = { nil },
        settings: RustupSettings = RustupSettings(), lock: RustActivity.RunLock = RustActivity.RunLock()
    ) -> RustUpdater {
        RustUpdater(
            scanner: box.scanner(), release: server.release, busy: busy,
            environment: { ["CARGO_HOME": "/ZZFixture-rust/wrong-cargo", "RUSTUP_HOME": "/ZZFixture-rust/wrong-rustup",
                            "PATH": "/ZZFixture-rust/bin", "https_proxy": "http://proxy.invalid:1"] },
            settings: { settings }, lock: lock)
    }

    func read(_ box: Sandbox, _ name: String) -> String? {
        try? String(contentsOf: box.cargo.appendingPathComponent("bin/\(name)"), encoding: .utf8)
    }

    /// Kills the mutation that leaves the child's `CARGO_HOME`/`RUSTUP_HOME` as
    /// inherited: the script would write the manifest under the wrong home and
    /// the toolchain would read as unchanged.
    @Test func toolchainUpdateRunsRustupWithTheRowsHomes() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let (_, stable) = try await Self.statuses(box, server)
        let outcome = await updater(box, server).update(stable)
        #expect(outcome == .updated(version: "1.99.0"))
        #expect(read(box, "ARGS") == "update stable-aarch64-apple-darwin --no-self-update\n")
        #expect(read(box, "ENV") == "\(box.cargo.path)|\(box.rustupHome.path)|\(CLIToolCommandRunner.systemPath)|http://proxy.invalid:1\n")
    }

    @Test func selfUpdateIsVerifiedAfterwards() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let (rustup, _) = try await Self.statuses(box, server)
        #expect(rustup.installedVersion == "1.29.0")
        let outcome = await updater(box, server).update(rustup)
        #expect(outcome == .updated(version: "1.29.1"))
        #expect(read(box, "ARGS") == "self update\n")
    }

    /// The trust rule after the update. Kills the mutation that reports exit 0
    /// as updated without hashing the new file: here the new file is not the
    /// build rust-lang publishes for 1.29.1.
    @Test func selfUpdateLeavingAnUnpublishedFileFails() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server, nextPublished: false)
        let (rustup, _) = try await Self.statuses(box, server)
        guard case .failed(let message, let output) = await updater(box, server).update(rustup) else {
            Issue.record("expected a failure"); return
        }
        #expect(message.contains("not rust-lang's for 1.29.1"))
        #expect(output.contains("rustup updated - 1.29.1"))
    }

    @Test func selfUpdateThatChangedNothingFails() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        try FileManager.default.removeItem(at: box.cargo.appendingPathComponent("bin/NEXT"))
        let (rustup, _) = try await Self.statuses(box, server)
        let outcome = await updater(box, server).update(rustup)
        #expect(outcome == .failed(
            message: "rustup self update finished, but rustup is still 1.29.0",
            output: "info: checking for self-update (current version: 1.29.0)\ninfo: rustup updated - 1.29.1 (from 1.29.0)"))
    }

    @Test func toolchainThatDidNotMoveFails() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        try Data().write(to: box.cargo.appendingPathComponent("bin/STAY"))
        let (_, stable) = try await Self.statuses(box, server)
        guard case .failed(let message, _) = await updater(box, server).update(stable) else {
            Issue.record("expected a failure"); return
        }
        #expect(message == "rustup update finished, but stable-aarch64-apple-darwin is still 1.98.1")
    }

    /// rustup's own reason, without `error: `, even with `info:` after it.
    @Test func failureIsRustupsErrorLine() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        try Data().write(to: box.cargo.appendingPathComponent("bin/FAIL"))
        let (rustup, _) = try await Self.statuses(box, server)
        guard case .failed(let message, _) = await updater(box, server).update(rustup) else {
            Issue.record("expected a failure"); return
        }
        #expect(message == "could not download file from x")
    }

    /// The trust rule at the click. Kills the mutation that runs the command
    /// without re-hashing rustup: the file was swapped for one rust-lang never
    /// published, and it must not run (no `ARGS` written).
    @Test func rustupSwappedSinceTheCheckIsNotRun() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let (_, stable) = try await Self.statuses(box, server)
        try Data((Self.script + "\n# tampered rustup/1.29.0 (\n").utf8).write(to: box.rustup)
        guard case .failed(let message, _) = await updater(box, server).update(stable) else {
            Issue.record("expected a failure"); return
        }
        #expect(message.hasPrefix("not run:"))
        #expect(read(box, "ARGS") == nil)
    }

    /// A rustup replaced since the check by another build rust-lang publishes
    /// (it updated itself meanwhile) is proved again and run.
    @Test func rustupReplacedByAnotherPublishedBuildStillRuns() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let (_, stable) = try await Self.statuses(box, server)
        try FileManager.default.removeItem(at: box.rustup)
        try FileManager.default.copyItem(at: box.cargo.appendingPathComponent("bin/NEXT"), to: box.rustup)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box.rustup.path)
        #expect(await updater(box, server).update(stable) == .updated(version: "1.99.0"))
    }

    /// Kills the mutation that drops the click-time busy check.
    @Test func busyAtTheClickRunsNothing() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let (_, stable) = try await Self.statuses(box, server)
        let outcome = await updater(box, server, busy: { .rustup("rustup toolchain install", pid: 77) }).update(stable)
        #expect(outcome == .busy("rustup toolchain install is running (pid 77)"))
        #expect(read(box, "ARGS") == nil)
    }

    /// Kills the mutation that drops the in-process lock: with another of
    /// DuoUpdater's own rustup commands under way, a second is not started.
    @Test func secondRustupCommandFromDuoUpdaterWaitsItsTurn() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let (_, stable) = try await Self.statuses(box, server)
        let lock = RustActivity.RunLock()
        #expect(lock.tryAcquire())
        #expect(await updater(box, server, lock: lock).update(stable) == .busy(RustActivity.Busy.ours.description))
        #expect(read(box, "ARGS") == nil)
        lock.release()
        #expect(await updater(box, server, lock: lock).update(stable) == .updated(version: "1.99.0"))
        // Released afterwards, whatever the outcome.
        #expect(lock.tryAcquire())
    }

    /// Kills the mutation that skips re-reading `auto_self_update` at the click.
    @Test func selfUpdateTurnedOffBeforeTheClickIsNotRun() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let (rustup, stable) = try await Self.statuses(box, server)
        let off = RustupSettings(autoSelfUpdate: "disable")
        #expect(await updater(box, server, settings: off).update(rustup) == .notOffered)
        #expect(read(box, "ARGS") == nil)
        // A toolchain's update is not rustup's self-update.
        #expect(await updater(box, server, settings: off).update(stable) == .updated(version: "1.99.0"))
    }

    @Test func noOfferRunsNothing() async throws {
        let box = try Sandbox()
        let server = Server()
        try Self.install(box, server)
        let status = CLIToolStatus(
            kind: .rust, path: box.rustup.path, installedVersion: "1.29.0", latestVersion: "1.29.1", channel: nil,
            state: .updateAvailable, oneClick: nil, withheld: .autoUpdateOff, note: nil,
            detail: .rust(RustItem(path: box.rustup.path, version: "1.29.0")))
        #expect(await updater(box, server).update(status) == .notOffered)
        #expect(read(box, "ARGS") == nil)
    }
}
