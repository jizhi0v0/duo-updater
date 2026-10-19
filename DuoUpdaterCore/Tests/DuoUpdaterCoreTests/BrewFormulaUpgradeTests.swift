import Testing
import Foundation
@testable import DuoUpdaterCore

/// `BrewFormulaService.upgrade(formula:)`: brew's dry run and `brew fetch` of
/// what it lists, which a cancel stops, then the upgrade itself as the commit.
///
/// The runs go to an invented `brew` script (`init(executor:…brewPath:)`), never
/// the host's (CLAUDE.md "测试不能问宿主"). The script appends each call's
/// arguments and its `HOMEBREW_NO_AUTO_UPDATE` to `calls`, and does what the
/// test's mode files say. Fixture names are `zzfixture-*`.
@Suite struct BrewFormulaUpgradeTests {

    // MARK: - The sequence

    /// Dry run with brew's auto-update left alone, `brew fetch` of every
    /// package it lists, then the upgrade with auto-update off (it ran already).
    ///
    /// Mutations: (a) skip `prefetch` → the calls are the upgrade alone;
    /// (b) drop `HOMEBREW_NO_AUTO_UPDATE` from the commit's environment → its
    /// line ends `|` + the host's value.
    @Test func anUpgradeDownloadsWhatTheDryRunListsThenUpgrades() async throws {
        let brew = try FakeBrew()
        defer { brew.remove() }
        try await brew.service.upgrade(formula: "zzfixture-node") { _ in }
        #expect(brew.calls == [
            "upgrade --formula zzfixture-node --dry-run|\(Self.hostNoAutoUpdate)",
            "fetch --formula -- zzfixture-simdjson zzfixture-node|1",
            "upgrade --formula zzfixture-node|1",
        ])
    }

    /// A dry run that fails downloads nothing ahead; the upgrade still runs and
    /// downloads for itself, as it always did.
    ///
    /// Mutation: throw on a failed dry run → the upgrade never runs.
    @Test func aFailedDryRunStillUpgrades() async throws {
        let brew = try FakeBrew(dryRunStatus: 1)
        defer { brew.remove() }
        try await brew.service.upgrade(formula: "zzfixture-node") { _ in }
        #expect(brew.calls == [
            "upgrade --formula zzfixture-node --dry-run|\(Self.hostNoAutoUpdate)",
            "upgrade --formula zzfixture-node|1",
        ])
    }

    /// A fetch that fails is no failure of the upgrade, which runs next.
    ///
    /// Mutation: throw on a failed fetch → the upgrade never runs.
    @Test func aFailedFetchStillUpgrades() async throws {
        let brew = try FakeBrew(fetch: .fail)
        defer { brew.remove() }
        try await brew.service.upgrade(formula: "zzfixture-node") { _ in }
        #expect(brew.calls.count == 3)
        #expect(brew.calls.last == "upgrade --formula zzfixture-node|1")
    }

    /// Upgrade All: the formulae's dry run and fetch, the named casks' fetch,
    /// then the two upgrades with auto-update off. Casks are always named.
    ///
    /// Mutation: drop the cask fetch → no `fetch --cask` line.
    @Test func upgradeAllDownloadsFormulaeAndCasksThenUpgradesBoth() async throws {
        let brew = try FakeBrew()
        defer { brew.remove() }
        try await brew.service.upgradeAll(casks: ["zzfixture-cask"]) { _ in }
        #expect(brew.calls == [
            "upgrade --formula --dry-run|\(Self.hostNoAutoUpdate)",
            "fetch --formula -- zzfixture-simdjson zzfixture-node|1",
            "fetch --cask -- zzfixture-cask|1",
            "upgrade --formula|1",
            "upgrade --cask zzfixture-cask|1",
        ])
    }

    /// No casks: no cask fetch and no `brew upgrade --cask` at all, which with
    /// no tokens would sweep every cask.
    ///
    /// Mutation: drop the commit's `guard !tokens.isEmpty` → a bare
    /// `upgrade --cask` line.
    @Test func upgradeAllWithoutCasksNeverRunsACaskCommand() async throws {
        let brew = try FakeBrew()
        defer { brew.remove() }
        try await brew.service.upgradeAll(casks: []) { _ in }
        #expect(!brew.calls.contains { $0.contains("--cask") })
        #expect(brew.calls.last == "upgrade --formula|1")
    }

    // MARK: - Cancel

    /// A cancel while brew fetches interrupts the fetch — it runs its own
    /// SIGINT handler — and the upgrade never starts.
    ///
    /// Mutations: (a) run the fetch `.runToCompletion` → the fetch is never
    /// interrupted and loops until the watchdog; (b) run it `.terminateChild`
    /// → killed without its handler, so no `fetch.interrupted`.
    @Test func aCancelWhileFetchingStopsBeforeTheUpgrade() async throws {
        let brew = try FakeBrew(fetch: .holdUntilInterrupted)
        defer { brew.remove() }
        let id = "test-brew-formula:\(UUID().uuidString)"
        let answer = Answer()
        let watchdog = brew.watchdog()
        let (result, stopped) = await InstallJobs.run(id) { () -> (Result<Void, any Error>, Bool) in
            let result = await Result.of {
                try await brew.service.upgrade(formula: "zzfixture-node") { line in
                    if line == "fetching" { answer.set(InstallJobs.cancel(id)) }
                }
            }
            return (result, InstallJobs.cancelStoppedSomething(id))
        }
        watchdog.cancel()
        #expect(answer.value == .cancelled)
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(stopped)
        #expect(brew.exists("fetch.interrupted"), "the fetch ran its own SIGINT handler")
        #expect(!brew.calls.contains { $0.hasPrefix("upgrade --formula zzfixture-node|") })
    }

    /// Upgrade All cancelled while brew fetches: the fetch runs its own SIGINT
    /// handler, and neither the casks' fetch nor either upgrade starts.
    ///
    /// Mutation: run `prefetch`'s fetch `.terminateChild` → killed without its
    /// handler, so no `fetch.interrupted`.
    @Test func upgradeAllCancelledWhileFetchingUpgradesNothing() async throws {
        let brew = try FakeBrew(fetch: .holdUntilInterrupted)
        defer { brew.remove() }
        let id = "test-brew-upgrade-all:\(UUID().uuidString)"
        let answer = Answer()
        let watchdog = brew.watchdog()
        let (result, stopped) = await InstallJobs.run(id) { () -> (Result<Void, any Error>, Bool) in
            let result = await Result.of {
                try await brew.service.upgradeAll(casks: ["zzfixture-cask"]) { line in
                    if line == "fetching" { answer.set(InstallJobs.cancel(id)) }
                }
            }
            // What `upgradeBrewFormulae` reads to show no error and skip the re-read.
            return (result, InstallJobs.cancelStoppedSomething(id))
        }
        watchdog.cancel()
        #expect(answer.value == .cancelled)
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(stopped)
        #expect(!brew.calls.contains { $0.hasPrefix("upgrade --formula|") || $0.hasPrefix("upgrade --cask") })
        #expect(!brew.calls.contains { $0.hasPrefix("fetch --cask") }, "the casks' fetch never started either")
        #expect(brew.exists("fetch.interrupted"), "the fetch ran its own SIGINT handler")
    }

    /// Once the upgrade itself runs, a cancel is refused and the upgrade
    /// finishes: brew replacing a keg is never cut short.
    ///
    /// Mutation: skip the commit's `InstallCommit.run` → the cancel is
    /// answered `.cancelled` and nothing stops the upgrade anyway.
    @Test func aCancelOnceTheUpgradeStartedIsRefused() async throws {
        let brew = try FakeBrew(upgrade: .holdUntilReleased)
        defer { brew.remove() }
        let id = "test-brew-formula:\(UUID().uuidString)"
        let answer = Answer()
        let watchdog = brew.watchdog()
        let result = await InstallJobs.run(id) { () -> Result<Void, any Error> in
            await Result.of {
                try await brew.service.upgrade(formula: "zzfixture-node") { line in
                    if line == "pouring" {
                        answer.set(InstallJobs.cancel(id))
                        brew.touch("release")
                    }
                }
            }
        }
        watchdog.cancel()
        #expect(answer.value == .tooLate(committing: "brew upgrade"))
        #expect(throws: Never.self) { try result.get() }
        #expect(brew.calls.last == "upgrade --formula zzfixture-node|1")
    }

    /// An upgrade that ran and failed may still have poured some of what it was
    /// asked for, so the job stays committing — a cancel after it is "too
    /// late", not a stop of something that changed nothing.
    ///
    /// Mutation: drop `InstallCommit.handedOver()` from `run` → the job is back
    /// to `.preparing`.
    @Test func aFailedUpgradeStaysHandedOver() async throws {
        let brew = try FakeBrew(upgrade: .fail)
        defer { brew.remove() }
        let id = "test-brew-formula:\(UUID().uuidString)"
        let (result, phase) = await InstallJobs.run(id) { () -> (Result<Void, any Error>, InstallJobs.Phase?) in
            let result = await Result.of {
                try await brew.service.upgrade(formula: "zzfixture-node") { _ in }
            }
            return (result, InstallJobs.phase(of: id))
        }
        #expect(throws: BrewFormulaService.BrewError.self) { try result.get() }
        #expect(phase == .committing)
    }

    // MARK: - Reading the dry run

    /// Captured from `brew upgrade --formula --dry-run node` (Homebrew 7.0.9,
    /// 2026-10-19), tap-trust warning cut, names changed: the dependency's
    /// section, then the requested package's, which has no colon.
    @Test func aSingleFormulasDryRunListsItsDependencyAndItself() {
        let output = """
            ==> Downloading bottle manifests
            ✔︎ Bottle Manifest zzfixture-node (26.12.0)
            ==> Would upgrade 1 dependency:
            zzfixture-simdjson 5.0.4 -> 5.0.5
            ==> Would upgrade 1 requested outdated package
            zzfixture-node 26.11.1_1 -> 26.12.0 (21.3MB)
            """
        #expect(BrewFormulaService.packagesToFetch(dryRun: output) == ["zzfixture-simdjson", "zzfixture-node"])
    }

    /// The bulk run's table, padded into columns (captured the same day).
    @Test func theBulkDryRunsPaddedTableIsRead() {
        let output = """
            ==> Would upgrade 3 outdated packages
            zzfixture-sqlite          3.54.0    -> 3.54.1   (2.5MB)
            zzfixture-llama.cpp       0.6.0_1   -> 0.7.0    (8MB)
            zzfixture-hdrhistogram_c  0.12.0    -> 0.12.1   (59.2KB)
            """
        #expect(BrewFormulaService.packagesToFetch(dryRun: output)
                == ["zzfixture-sqlite", "zzfixture-llama.cpp", "zzfixture-hdrhistogram_c"])
    }

    /// Dependencies to install are listed by new version alone; a tap formula
    /// by its full name; ANSI colour from a user's `HOMEBREW_COLOR` is no part
    /// of a name; a package listed twice is fetched once.
    @Test func installedDependenciesTapNamesColourAndRepeats() {
        let output = """
            \u{1B}[34m==>\u{1B}[0m \u{1B}[1mWould install 2 dependencies for zzfixture-tool:\u{1B}[0m
            zzfixture-lib@3 1.2
            zzfixture-user/zzfixture-tap/zzfixture-dep 0.1.0
            ==> Would upgrade 1 requested outdated package
            zzfixture-tool 1.0 -> 1.1
            ==> Would upgrade 1 outdated package
            zzfixture-tool 1.0 -> 1.1
            """
        #expect(BrewFormulaService.packagesToFetch(dryRun: output)
                == ["zzfixture-lib@3", "zzfixture-user/zzfixture-tap/zzfixture-dep", "zzfixture-tool"])
    }

    /// What is not a package to download: lines under other headings — pinned,
    /// deprecated, would build from source — and prose brew prints after a
    /// section without a heading of its own.
    ///
    /// Mutation: drop `isVersionChangeLine` → "Disable" and "Some" are taken.
    @Test func otherSectionsAndProseAreNotRead() {
        let output = """
            ==> Would upgrade 1 outdated package
            zzfixture-a 1 -> 2
            Homebrew will now attempt to upgrade casks with `auto_updates true`.
            Disable this behaviour with `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1`.
            Some casks may still require `--greedy`.
            ==> 1 Pinned formula
            zzfixture-pinned 3.0
            ==> 1 Deprecated or disabled package
            zzfixture-old (deprecated)
            ==> 1 homebrew/core formula that would build from source
            zzfixture-a
            Warning: zzfixture-b 1.0 is already installed
            """
        #expect(BrewFormulaService.packagesToFetch(dryRun: output) == ["zzfixture-a"])
    }

    // MARK: - Fixture

    /// The host's own `HOMEBREW_NO_AUTO_UPDATE`, which the dry run inherits:
    /// it is the user's to set, and the dry run does not add it.
    static var hostNoAutoUpdate: String {
        ProcessInfo.processInfo.environment["HOMEBREW_NO_AUTO_UPDATE"] ?? ""
    }

    /// A first cancel answer, kept for the test to read.
    final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: InstallJobs.CancelResult?
        func set(_ value: InstallJobs.CancelResult) { lock.withLock { if answer == nil { answer = value } } }
        var value: InstallJobs.CancelResult? { lock.withLock { answer } }
    }

    struct FakeBrew {
        enum Fetch { case succeed, fail, holdUntilInterrupted }
        enum Upgrade { case succeed, fail, holdUntilReleased }

        let dir: URL
        let service: BrewFormulaService

        init(dryRunStatus: Int32 = 0, fetch: Fetch = .succeed, upgrade: Upgrade = .succeed) throws {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZZFixture-brew-upgrade-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let d = dir.path
            let fetchBody: String
            switch fetch {
            case .succeed: fetchBody = "echo fetched; exit 0"
            case .fail: fetchBody = "echo 'Error: fetch failed'; exit 1"
            case .holdUntilInterrupted:
                fetchBody = "trap \"touch '\(d)/fetch.interrupted'; exit 130\" INT; echo fetching; while [ ! -e '\(d)/release' ]; do sleep 0.1; done; exit 0"
            }
            let upgradeBody: String
            switch upgrade {
            case .succeed: upgradeBody = "echo upgraded; exit 0"
            case .fail: upgradeBody = "echo 'Error: post-install failed'; exit 1"
            case .holdUntilReleased:
                upgradeBody = "echo pouring; while [ ! -e '\(d)/release' ]; do sleep 0.05; done; echo upgraded; exit 0"
            }
            let script = """
                #!/bin/sh
                printf '%s|%s\\n' "$*" "${HOMEBREW_NO_AUTO_UPDATE:-}" >> '\(d)/calls'
                case "$*" in
                *--dry-run*)
                    echo '==> Would upgrade 1 dependency:'
                    echo 'zzfixture-simdjson 5.0.4 -> 5.0.5'
                    echo '==> Would upgrade 1 requested outdated package'
                    echo 'zzfixture-node 26.11.1_1 -> 26.12.0 (21.3MB)'
                    exit \(dryRunStatus) ;;
                fetch*) \(fetchBody) ;;
                upgrade*) \(upgradeBody) ;;
                esac
                exit 2
                """
            let path = dir.appendingPathComponent("brew")
            try Data(script.utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
            service = BrewFormulaService(executor: { _ in nil }, brewPath: { path.path })
        }

        var calls: [String] {
            let text = (try? String(contentsOf: dir.appendingPathComponent("calls"), encoding: .utf8)) ?? ""
            return text.split(separator: "\n").map(String.init)
        }

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
        }

        func touch(_ name: String) {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: nil)
        }

        /// Ends a hold that a broken build never ends, 300 s on: the upgrade and
        /// the fetch both stop at `release`, so the test fails on what it
        /// expects rather than hanging.
        func watchdog() -> DispatchWorkItem {
            let dir = dir
            let item = DispatchWorkItem {
                FileManager.default.createFile(atPath: dir.appendingPathComponent("release").path, contents: nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: item)
            return item
        }

        func remove() { try? FileManager.default.removeItem(at: dir) }
    }
}

private extension Result where Failure == any Error {
    static func of(_ body: () async throws -> Success) async -> Self {
        do { return .success(try await body()) } catch { return .failure(error) }
    }
}
