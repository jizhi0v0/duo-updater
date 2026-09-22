import Foundation
import Testing
@testable import DuoUpdaterCore

/// `UpdatePolicy.clearsStagedBuild` and `SparkleStagingClearance.clear`.
///
/// The clearance fails closed, so most of what is worth pinning here is the
/// branches that must NOT delete anything: each fake system below breaks one
/// step and the staged bundle has to survive it.
struct SparkleStagingClearanceTests {

    // MARK: - clearsStagedBuild

    private func result(installed: String, latest: String?) -> UpdateResult {
        UpdateResult(
            app: InstalledApp(
                name: "TinyWeb", bundleID: "com.example.tinyweb",
                shortVersion: installed, buildVersion: nil,
                path: URL(fileURLWithPath: "/Applications/TinyWeb.app"),
                isMASApp: false, sparkleFeedURL: nil,
                hasSelfUpdater: false, hasSparkleUpdater: true),
            remote: RemoteVersion(
                shortVersion: latest, version: nil,
                downloadURL: URL(string: "https://example.com/t.dmg"), sourceName: "Sparkle"),
            status: .updateAvailable(latest: latest ?? "?"))
    }

    private func staged(_ version: String, updater: StagedUpdater? = .sparkle) -> StagedSelfUpdate {
        StagedSelfUpdate(version: version, buildVersion: nil,
                         stagedBundlePath: URL(fileURLWithPath: "/tmp/staged.app"), updater: updater)
    }

    /// TinyWeb, 2026-09-22: 27.0.2 installed, 27.0.3 staged, 27.1.3 offered.
    ///
    /// Mutations: drop the `updater == .sparkle` guard (the Squirrel case goes
    /// red); compare against the installed version instead of the latest (the
    /// staged-is-latest case goes red).
    @Test func clearsOnlyASparkleStagingThatIsNotTheLatest() {
        let tinyWeb = result(installed: "27.0.2", latest: "27.1.3")
        #expect(UpdatePolicy.clearsStagedBuild(tinyWeb, staged: staged("27.0.3")),
                "trailing the latest — cleared, and our Update installs 27.1.3")
        #expect(!UpdatePolicy.clearsStagedBuild(tinyWeb, staged: staged("27.1.3")),
                "the latest is staged — a Relaunch away, yielded to")
        #expect(UpdatePolicy.clearsStagedBuild(
            result(installed: "27.1.3", latest: "27.1.4"), staged: staged("27.0.3")),
            "older than installed is only a downgrade waiting for the quit")
        #expect(!UpdatePolicy.clearsStagedBuild(tinyWeb, staged: staged("27.0.3", updater: nil)),
                "Squirrel / Spotify stage differently — keep yielding")
        #expect(!UpdatePolicy.clearsStagedBuild(
            result(installed: "27.0.2", latest: nil), staged: staged("27.0.3")),
            "no latest to compare against — nothing proves it trails")
    }

    // MARK: - clear

    private let bundleID = "com.example.tinyweb"

    /// A real app bundle path and a real Sparkle cache with one staged build, in
    /// a scratch directory.
    private struct Fixture {
        let root: URL
        let caches: URL
        let app: InstalledApp
        let staged: StagedSelfUpdate
        let stagingRun: URL
        var launcherUpdater: String { caches.path + "/com.example.tinyweb/org.sparkle-project.Sparkle/Launcher/qA6he5gxK/Updater.app/Contents/MacOS/Updater" }
        var autoupdate: String { app.path.path + "/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" }
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("SparkleStagingClearanceTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let stagingRun = caches.appendingPathComponent(
            "\(bundleID)/org.sparkle-project.Sparkle/Installation/UyW7q0KAC", isDirectory: true)
        let stagedApp = stagingRun.appendingPathComponent("PZ96JBkAi/TinyWeb.app", isDirectory: true)
        try fm.createDirectory(at: stagedApp.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data().write(to: stagingRun.appendingPathComponent("update.dmg"))
        let appPath = root.appendingPathComponent("Applications/TinyWeb.app", isDirectory: true)
        try fm.createDirectory(at: appPath, withIntermediateDirectories: true)
        let app = InstalledApp(
            name: "TinyWeb", bundleID: bundleID, shortVersion: "27.0.2", buildVersion: "102",
            path: appPath, isMASApp: false, sparkleFeedURL: nil,
            hasSelfUpdater: false, hasSparkleUpdater: true)
        try await body(Fixture(
            root: root, caches: caches, app: app,
            staged: StagedSelfUpdate(version: "27.0.3", buildVersion: "103",
                                     stagedBundlePath: stagedApp, updater: .sparkle),
            stagingRun: stagingRun))
    }

    /// Records what the clearance asked of the system.
    private final class Calls: @unchecked Sendable {
        var removed: [String] = []
    }

    private func system(
        _ f: Fixture, calls: Calls,
        jobs: [SparkleStagingClearance.Job]? = nil,
        paths: [pid_t: String]? = nil,
        refuses: Set<String> = [],
        alive: Set<pid_t> = []
    ) -> SparkleStagingClearance.System {
        let jobs = jobs ?? [
            .init(pid: 802, label: "com.example.tinyweb-sparkle-updater"),
            .init(pid: 804, label: "com.example.tinyweb-sparkle-progress"),
            .init(pid: 712, label: "application.com.example.tinyweb.1.2"),
            .init(pid: 900, label: "com.example.tinyweb.helper"),
        ]
        let paths = paths ?? [
            802: f.autoupdate,
            804: f.launcherUpdater,
            712: f.app.path.path + "/Contents/MacOS/TinyWeb",
            900: f.app.path.path + "/Contents/Frameworks/Helper.framework/Helper",
        ]
        return SparkleStagingClearance.System(
            listJobs: { jobs },
            executablePath: { paths[$0] },
            removeJob: { label in calls.removed.append(label); return !refuses.contains(label) },
            isAlive: { alive.contains($0) },
            bundleIdentifier: { $0 == 804 ? "org.sparkle-project.Sparkle.Updater" : nil },
            sleep: { _ in })
    }

    /// Mutations: widen the framework home to all of `Contents/Frameworks` (the
    /// helper gets removed); drop the cache home (the progress agent survives).
    @Test func clearsBothInstallerJobsAndTheStagingRun() async throws {
        try await withFixture { f in
            let calls = Calls()
            let outcome = await SparkleStagingClearance.clear(
                for: f.app, staged: f.staged, cachesDirectory: f.caches,
                system: system(f, calls: calls))
            #expect(outcome == .cleared)
            #expect(Set(calls.removed) == [
                "com.example.tinyweb-sparkle-updater", "com.example.tinyweb-sparkle-progress",
            ], "only the installer's jobs — not the app itself, not its own helper")
            #expect(!FileManager.default.fileExists(atPath: f.stagingRun.path),
                    "the whole staging run goes, archive included")
        }
    }

    /// Each broken step must leave the staged bundle in place and say so.
    ///
    /// Mutations: turn any of the guards in `clear` into a fall-through (the
    /// matching case goes red on `fileExists`).
    @Test func anyUnconfirmedStepLeavesTheStagingAlone() async throws {
        typealias Setup = (Fixture, Calls) -> SparkleStagingClearance.System
        let cases: [(String, Setup)] = [
            ("launchctl list failed", { f, c in self.system(f, calls: c, jobs: nil, paths: nil).with { $0.listJobs = { nil } } }),
            ("no installer job", { f, c in self.system(f, calls: c, jobs: [.init(pid: 712, label: "application.x")]) }),
            ("removal refused, installer still up", { f, c in
                self.system(f, calls: c,
                            refuses: ["com.example.tinyweb-sparkle-updater", "com.example.tinyweb-sparkle-progress"],
                            alive: [802, 804]) }),
            ("installer survives", { f, c in self.system(f, calls: c, alive: [802]) }),
        ]
        for (name, setup) in cases {
            try await withFixture { f in
                let outcome = await SparkleStagingClearance.clear(
                    for: f.app, staged: f.staged, cachesDirectory: f.caches,
                    system: setup(f, Calls()))
                guard case .notCleared = outcome else {
                    Issue.record("\(name): expected notCleared, got \(outcome)")
                    return
                }
                #expect(FileManager.default.fileExists(atPath: f.staged.stagedBundlePath.path),
                        "\(name): the staged bundle must survive")
            }
        }
    }

    /// Round 3's case: `Autoupdate`'s job refused and its process armed. The
    /// progress agent must be left alone — it is the only thing the staged-install
    /// gates see, and without it the next Update would install under a live
    /// installer that applies the stale build on quit. The gates then still say
    /// "will apply it when you quit it", which is true, so `touchedInstaller` is
    /// false.
    ///
    /// Mutations: remove agents in the same pass as the installer (the `removed`
    /// expectation goes red); report `touchedInstaller: true` here (the second).
    @Test func aSurvivingInstallerKeepsItsProgressAgent() async throws {
        try await withFixture { f in
            let calls = Calls()
            let outcome = await SparkleStagingClearance.clear(
                for: f.app, staged: f.staged, cachesDirectory: f.caches,
                system: system(f, calls: calls,
                               refuses: ["com.example.tinyweb-sparkle-updater"], alive: [802]))
            #expect(calls.removed == ["com.example.tinyweb-sparkle-updater"],
                    "the agent is not touched while the installer survives")
            #expect(outcome == .notCleared(
                reason: "still running after removal: [\"com.example.tinyweb-sparkle-updater\"], launchd refused [\"com.example.tinyweb-sparkle-updater\"]",
                touchedInstaller: false))
            #expect(FileManager.default.fileExists(atPath: f.staged.stagedBundlePath.path))
        }
    }

    /// The one state past undoing: the installer gone, the agent refusing to go.
    /// Nothing applies on quit any more, and the outcome must say part of the
    /// installer was removed. The installer goes first.
    ///
    /// Mutations: hard-code `touchedInstaller: false` (goes red); swap the phases
    /// (the order expectation goes red).
    @Test func anInstallerGoneButAnAgentLeftSaysSo() async throws {
        try await withFixture { f in
            let calls = Calls()
            let outcome = await SparkleStagingClearance.clear(
                for: f.app, staged: f.staged, cachesDirectory: f.caches,
                system: system(f, calls: calls, alive: [804]))
            #expect(calls.removed == [
                "com.example.tinyweb-sparkle-updater", "com.example.tinyweb-sparkle-progress",
            ], "installer first, agent second")
            guard case .notCleared(_, let touched) = outcome else {
                Issue.record("expected notCleared, got \(outcome)"); return
            }
            #expect(touched)
            #expect(FileManager.default.fileExists(atPath: f.staged.stagedBundlePath.path))
        }
        try await withFixture { f in
            let outcome = await SparkleStagingClearance.clear(
                for: f.app, staged: f.staged, cachesDirectory: f.caches,
                system: system(f, calls: Calls(), jobs: [.init(pid: 712, label: "application.x")]))
            #expect(outcome == .notCleared(
                reason: "no installer job found for com.example.tinyweb", touchedInstaller: false))
        }
    }

    /// A job that exits on its own between the list and the removal fails
    /// `remove` and is exactly as gone: the processes decide, not the status.
    ///
    /// Mutation: fail on any refused removal (goes red).
    @Test func aRefusedRemovalOfAJobThatIsGoneStillClears() async throws {
        try await withFixture { f in
            let outcome = await SparkleStagingClearance.clear(
                for: f.app, staged: f.staged, cachesDirectory: f.caches,
                system: system(f, calls: Calls(), refuses: ["com.example.tinyweb-sparkle-progress"]))
            #expect(outcome == .cleared)
        }
    }

    /// A staged path that is not inside this app's own Sparkle cache is refused
    /// before anything is asked of launchd — nothing outside it is ever deleted.
    @Test func refusesAStagedPathOutsideTheCache() async throws {
        try await withFixture { f in
            let calls = Calls()
            let elsewhere = StagedSelfUpdate(
                version: "27.0.3", buildVersion: "103",
                stagedBundlePath: f.app.path, updater: .sparkle)
            let outcome = await SparkleStagingClearance.clear(
                for: f.app, staged: elsewhere, cachesDirectory: f.caches,
                system: system(f, calls: calls))
            #expect(outcome != .cleared)
            #expect(calls.removed.isEmpty)
            #expect(FileManager.default.fileExists(atPath: f.app.path.path))
        }
    }

    /// Real `launchctl list` output, TinyWeb armed, 2026-09-22 10:58.
    @Test func parsesLaunchctlList() {
        let output = """
            PID\tStatus\tLabel
            802\t0\tcom.tableplus.TinyWeb-sparkle-updater
            -\t0\tcom.apple.something
            804\t0\tcom.tableplus.TinyWeb-sparkle-progress
            """
        #expect(SparkleStagingClearance.parseJobList(output) == [
            .init(pid: 802, label: "com.tableplus.TinyWeb-sparkle-updater"),
            .init(pid: 804, label: "com.tableplus.TinyWeb-sparkle-progress"),
        ])
    }
}

private extension SparkleStagingClearance.System {
    func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
    }
}
