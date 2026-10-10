import Foundation
import Testing
@testable import DuoUpdaterCore

/// What the app's CLI surfaces and `duo` share (`CLITools`, `CLIToolStatus`'s
/// `joinsUpdateAll` and `commandToCopy`, `CLIToolExit`): one copy of each rule,
/// so these pin the rule itself.
struct CLIToolsTests {

    static let path = "/ZZFixture-cli-tools/bin/tool"

    static func status(
        _ kind: CLIToolKind = .fx, state: CLIToolState = .updateAvailable, oneClick: Bool = true,
        withheld: CLIToolWithheld? = nil, manual: Bool = false, administrator: Bool = false
    ) -> CLIToolStatus {
        CLIToolStatus(
            kind: kind, path: path, installedVersion: "1.0.0", latestVersion: "1.1.0", channel: nil, state: state,
            oneClick: oneClick ? CLIToolCommand(executable: path, arguments: ["update"], pathPrefix: nil) : nil,
            withheld: withheld, note: nil,
            manualCommand: manual ? CLIToolCommand(executable: "curl", arguments: ["-sS", "x", "|", "sh"], pathPrefix: nil) : nil,
            detail: .fx(FxInstall(path: path, version: "1.0.0")), needsAdministrator: administrator)
    }

    /// Every tool has its provider, once, in `CLIToolKind`'s order — the order
    /// the app's CLI tab and `duo` list them in.
    @Test func everyKindHasOneProviderInKindOrder() {
        #expect(CLITools.providers().map(\.kind) == CLIToolKind.allCases)
    }

    @Test func updateAllRunsAnOfferedUpdateThatNeedsNoPassword() {
        #expect(Self.status().joinsUpdateAll)
        #expect(!Self.status(oneClick: false, withheld: .unverified).joinsUpdateAll)
        #expect(!Self.status(manual: true, administrator: true).joinsUpdateAll)
    }

    /// The command handed out to copy: beside an update the tool's own
    /// auto-update setting holds back, one DuoUpdater will not run (an
    /// unsupported installer, an unverified file), and one that needs an
    /// administrator password — never beside any other gate.
    @Test func theCommandToCopyFollowsTheGate() {
        for withheld: CLIToolWithheld in [.autoUpdateOff, .unsupportedInstaller, .unverified] {
            #expect(Self.status(oneClick: false, withheld: withheld, manual: true).commandToCopy != nil)
        }
        for withheld: CLIToolWithheld in [.busy, .broken, .wrongSigner, .channelUnreadable] {
            #expect(Self.status(oneClick: false, withheld: withheld, manual: true).commandToCopy == nil)
        }
        #expect(Self.status(manual: true, administrator: true).commandToCopy?.display == "curl -sS x | sh")
        // Not once there is nothing to update.
        #expect(Self.status(state: .upToDate, manual: true, administrator: true).commandToCopy == nil)
    }

    /// Exit 0 is an update only when the version moved.
    @Test func anUpdateCountsOnlyWhenTheVersionMoved() {
        #expect(CLITools.settle(before: "1.0.0", after: "1.1.0") == .updated("1.1.0"))
        #expect(CLITools.settle(before: "1.0.0", after: "1.0.0") == .unchanged("1.0.0"))
        #expect(CLITools.settle(before: "1.0.0", after: nil) == .unreadable)
        #expect(CLITools.settle(before: nil, after: "1.1.0") == .updated("1.1.0"))
    }

    @Test func requestsAreFiledUnderThePackageOrTheTool() {
        #expect(CLITools.attributionID(Self.status()) == "fx")
    }

    /// `duo` learns how the vendor's command ended through `CLIToolExit`; the
    /// app, which sets no observer, is told nothing.
    @Test func theRunnerReportsTheExitStatusToAnObserver() async {
        let seen = Seen()
        let command = CLIToolCommand(executable: "/bin/sh", arguments: ["-c", "echo nope >&2; exit 3"], pathPrefix: nil)
        let run = await CLIToolExit.$observer.withValue({ seen.add($0) }) {
            await CLIToolCommandRunner.run(
                command, environment: ["PATH": "/usr/bin:/bin"],
                deadline: ChildProcess.Deadline(terminateAfter: .seconds(30), killAfter: .seconds(35)),
                progress: { _ in })
        }
        #expect(run.lines == ["nope"])
        #expect(seen.all == [CLIToolExit.Status(executable: "/bin/sh", status: 3, signal: false, timedOut: false)])
    }

    /// Every provider asked answers, in `providers` order whichever finishes
    /// first. Run under `-c release` too: a task group's `for await` has been
    /// miscompiled there before (swift64-release-taskgroup-miscompile).
    @Test func providersAreAskedAtOnceAndAnsweredInOrder() async {
        let kinds: [CLIToolKind] = [.uv, .deno, .mise, .helm, .zoxide, .atuin]
        let providers: [any CLIToolProvider] = kinds.enumerated().map { index, kind in
            Delayed(kind: kind, delay: .milliseconds(10 * (kinds.count - index)))
        }
        for _ in 0..<5 {
            let answers = await CLITools.inProviderOrder(providers, [0, 2, 3, 5]) { await $0.scan() }
            #expect(answers.map(\.0) == [0, 2, 3, 5])
            #expect(answers.flatMap { $0.1.map(\.kind) } == [.uv, .mise, .helm, .atuin])
        }
    }

    struct Delayed: CLIToolProvider {
        let kind: CLIToolKind
        let delay: Duration
        func scan() async -> [CLIToolSighting] {
            try? await Task.sleep(for: delay)
            return [CLIToolSighting(kind: kind, path: CLIToolsTests.path, version: "1")]
        }
        func check() async -> CLIToolReport { CLIToolReport(kind: kind, statuses: [], context: .deno) }
        func update(_ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void) async -> CLIToolUpdateOutcome {
            .notOffered
        }
        func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog { Changelog(entries: []) }
    }

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [CLIToolExit.Status] = []
        func add(_ status: CLIToolExit.Status) { lock.withLock { statuses.append(status) } }
        var all: [CLIToolExit.Status] { lock.withLock { statuses } }
    }
}
