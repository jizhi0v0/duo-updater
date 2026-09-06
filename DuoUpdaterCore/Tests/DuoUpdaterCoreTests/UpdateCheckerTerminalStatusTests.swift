import Testing
import Foundation
@testable import DuoUpdaterCore

/// What `UpdateChecker.check(_:)` settles on when a source **throws**, for every
/// terminal status it can reach — one row per outcome, no gaps.
///
/// This file exists because of a miss. Making `VendorProbeSource` throw (it used
/// to swallow every failure into nil) silently jumped the queue in front of the
/// whole tail of `check(_:)`: `if let lastError` sits ABOVE the block that maps
/// "no source answered" onto `.toolboxManaged` / `.testFlightManaged` /
/// `.appStoreManaged` / `.unknown`. Only `.unknown` was the one under discussion,
/// so only `.unknown` got checked; `.toolboxManaged` turned out to be reachable
/// too, and an Android Studio Canary row lost its "open Toolbox" button — the one
/// action it had — to a Retry button for a version number. Caught at review, not
/// by a test.
///
/// Nothing owned that intersection, and the three tests that came close all
/// couldn't see it: `ToolboxInventoryTests.toolboxManagedAppLabelledManaged`
/// builds its app on the default `.stable` channel, so `check` returns at the
/// early Toolbox branch and never enters the source loop at all;
/// `VendorInstallTests.toolboxManagedCopiesResolveDetectionOnly` does use
/// canary/beta but asserts on `VendorProbeSource` directly, never on the status
/// the checker derives; and `UnknownAppsTests` runs the whole real stack and only
/// `log()`s, with no assertion that can fail.
///
/// So the rule this file encodes is not "test the vendor probe" but: **every exit
/// from `check(_:)` states, here, what a thrown source does to it.** A new status,
/// or a new source that can throw where none could before, has to come add its
/// row — which is the part that was missing.
///
/// The asymmetry between the rows is deliberate and is the whole reason they are
/// written out one by one rather than folded into a loop. Read the comments.
@Suite struct UpdateCheckerTerminalStatusTests {

    /// A source under test control: it answers, misses, or throws on command, and
    /// remembers whether it was consulted at all.
    ///
    /// The "was it consulted" half is load-bearing for the early-return rows
    /// below. Asserting only on the final status would let a regression that
    /// moves a guard *below* the loop pass unnoticed whenever the source happens
    /// to miss — this way the test fails on the guard moving, not on the weather.
    private final class ScriptedSource: UpdateSource, @unchecked Sendable {
        enum Behaviour {
            case throwing
            case missing
            case answering(String)
        }

        let name: String
        private let behaviour: Behaviour
        private let lock = NSLock()
        private var consultedCount = 0

        init(_ behaviour: Behaviour, name: String = "Scripted") {
            self.behaviour = behaviour
            self.name = name
        }

        /// The error a real source raises for the failure this stands in for — a
        /// dropped connection. Its message is what the row would show.
        static let error = URLError(.networkConnectionLost)

        var consulted: Bool {
            lock.withLock { consultedCount > 0 }
        }

        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            // `withLock`, not `lock()`/`unlock()`: the bare pair is unavailable in an
            // async context (nothing stops a suspension between them).
            lock.withLock { consultedCount += 1 }
            switch behaviour {
            case .throwing:
                throw Self.error
            case .missing:
                return nil
            case .answering(let version):
                return RemoteVersion(
                    shortVersion: version, version: nil, downloadURL: nil,
                    sourceName: name, requiresManualInstaller: true)
            }
        }
    }

    private static func app(
        bundleID: String = "com.example.subject",
        isMASApp: Bool = false,
        isToolboxManaged: Bool = false,
        isTestFlightApp: Bool = false,
        channel: ReleaseChannel = .stable
    ) -> InstalledApp {
        InstalledApp(
            name: "Subject", bundleID: bundleID,
            shortVersion: "1.0.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/Subject.app"),
            isMASApp: isMASApp, isToolboxManaged: isToolboxManaged,
            isTestFlightApp: isTestFlightApp, sparkleFeedURL: nil,
            releaseChannel: channel)
    }

    /// The Toolbox-managed app that still reaches the source loop. Android Studio
    /// Canary/Beta are the only ones (`prefersVendorProbeOverToolbox`), which is
    /// why the bug lived exactly here and nowhere else.
    private static func androidStudioPreview(_ channel: ReleaseChannel) -> InstalledApp {
        InstalledApp(
            name: "Android Studio", bundleID: "com.google.android.studio",
            shortVersion: "2025.2", buildVersion: "AI-252.0.0",
            path: URL(fileURLWithPath: "/Applications/Android Studio Preview.app"),
            isMASApp: false, isToolboxManaged: true, sparkleFeedURL: nil,
            releaseChannel: channel)
    }

    // MARK: - .unknown — nothing owns this app

    /// The baseline both other rows are measured against: with no channel to fall
    /// back on, a thrown source is all we know, so it is what the row says.
    @Test func anUnownedAppReportsAThrownFailure() async {
        let source = ScriptedSource(.throwing)
        let result = await UpdateChecker(sources: [source]).check(Self.app())

        #expect(source.consulted)
        guard case .error(let message) = result.status else {
            Issue.record("expected .error, got \(result.status)")
            return
        }
        #expect(message == ScriptedSource.error.localizedDescription)
    }

    /// And a source that simply doesn't apply still means "nothing covers this" —
    /// the dead "—". This is the pair that gives the dash its meaning: it is the
    /// *absence* of a source, never the failure of one.
    @Test func anUnownedAppWithNoApplicableSourceIsUnknown() async {
        let result = await UpdateChecker(sources: [ScriptedSource(.missing)])
            .check(Self.app())
        #expect(result.status == .unknown)
    }

    // MARK: - .toolboxManaged — Toolbox owns the install

    /// Toolbox is the installer; a source only ran at all because we BORROW a
    /// version read for the preview channels. "Open Toolbox" is valid whether or
    /// not that read came back, so a throw must not replace it with Retry.
    @Test func aToolboxOwnedAppKeepsItsChannelWhenASourceThrows() async {
        for channel in [ReleaseChannel.canary, .beta] {
            let app = Self.androidStudioPreview(channel)
            #expect(app.prefersVendorProbeOverToolbox, "\(channel.rawValue) must reach the loop")

            let source = ScriptedSource(.throwing)
            let result = await UpdateChecker(sources: [source]).check(app)

            #expect(source.consulted, "\(channel.rawValue) never reached the source")
            #expect(result.status == .toolboxManaged, "\(channel.rawValue) lost its Toolbox row")
        }
    }

    /// A borrowed read that SUCCEEDS still wins — the guard above must not have
    /// pinned these rows to `.toolboxManaged` unconditionally, which would throw
    /// away the very version we borrowed the probe to get.
    @Test func aToolboxOwnedAppStillTakesAVersionWhenTheBorrowedReadWorks() async {
        let result = await UpdateChecker(sources: [ScriptedSource(.answering("2026.1"))])
            .check(Self.androidStudioPreview(.canary))
        #expect(result.status == .updateAvailable(latest: "2026.1"))
    }

    /// Every other Toolbox app returns before the loop, so no source can throw for
    /// it in the first place. Pinned on "was it consulted", not on the status: if
    /// that early branch is ever moved below the loop, this fails immediately
    /// instead of waiting for a source that happens to throw.
    @Test func anOrdinaryToolboxAppNeverReachesASourceAtAll() async {
        let source = ScriptedSource(.throwing)
        let result = await UpdateChecker(sources: [source])
            .check(Self.app(bundleID: "com.jetbrains.intellij", isToolboxManaged: true))

        #expect(!source.consulted, "a Toolbox-managed app must not be handed to a source")
        #expect(result.status == .toolboxManaged)
    }

    // MARK: - .testFlightManaged — TestFlight owns the beta

    /// Same shape, and unreachable for the same reason: `check` returns above the
    /// loop. This is what KEEPS `.testFlightManaged` out of the `lastError` race,
    /// so it is the guard worth pinning, not the status.
    @Test func aTestFlightAppNeverReachesASourceAtAll() async {
        let source = ScriptedSource(.throwing)
        let result = await UpdateChecker(sources: [source])
            .check(Self.app(isTestFlightApp: true))

        #expect(!source.consulted, "a TestFlight app must not be handed to a source")
        #expect(result.status == .testFlightManaged)
    }

    // MARK: - .appStoreManaged — the store owns it, and is the one that failed

    /// **The deliberate asymmetry.** A store app looks like it deserves the same
    /// treatment as a Toolbox one, and it does not.
    ///
    /// The only source that runs for a store copy is `MacAppStoreSource` — not by
    /// inspection, but because `UpdateChecker` skips every source whose
    /// `answersAppStoreCopies` is false, which is all of them bar the store's.
    /// See `SourceStorePolicyTests`.
    ///
    /// So the thing that threw here is the lookup for the app the store DOES own.
    /// That is not a *borrowed* read the way Toolbox's is — Toolbox's probe
    /// answers a question Toolbox could have answered itself, while this IS the
    /// row's update check. A failure therefore has to read as a failed check;
    /// painting it "Managed by the App Store" would show the user the same row
    /// they get when the store is quietly keeping the app current.
    ///
    /// ⚠️ This paragraph used to be a hand-kept inventory of which sources
    /// carried `guard !app.isMASApp`, and it was wrong twice — the second time
    /// citing Keka as a store copy carrying a `SUFeedURL`, which was false on the
    /// day it was written (Developer ID, no `_MASReceipt`). Do not reintroduce an
    /// inventory here; the gate and its table are the answer.
    ///
    /// If a later change makes this `.appStoreManaged`, that is a decision to
    /// argue for here, not a tidy-up of an inconsistency.
    @Test func anAppStoreAppReportsAFailedStoreLookup() async {
        let source = ScriptedSource(.throwing, name: "App Store")
        let result = await UpdateChecker(sources: [source])
            .check(Self.app(isMASApp: true))

        #expect(source.consulted)
        guard case .error = result.status else {
            Issue.record("expected .error, got \(result.status)")
            return
        }
    }

    /// A store lookup that merely misses is a different thing from one that
    /// failed, and keeps the managed label.
    @Test func anAppStoreAppWithNoAnswerIsManaged() async {
        let result = await UpdateChecker(sources: [ScriptedSource(.missing)])
            .check(Self.app(isMASApp: true))
        #expect(result.status == .appStoreManaged)
    }

    // MARK: - the gap this file is meant to close

    /// The list above is only a guard while it is COMPLETE. `UpdateStatus` carries
    /// two more cases (`upToDate`, `updateAvailable`), which `check` reaches from
    /// a source that answered and never from the "no source answered" tail — so
    /// the tail's four are all of them, and each has a row above.
    ///
    /// Written as an exhaustive `switch` on purpose: adding a case to
    /// `UpdateStatus` stops compiling here, which is the only mechanism that makes
    /// someone come back and decide what a thrown source does to it.
    @Test func everyStatusIsAccountedFor() {
        for status: UpdateStatus in [
            .upToDate, .updateAvailable(latest: "1"), .unknown,
            .appStoreManaged, .toolboxManaged, .testFlightManaged, .error("x"),
        ] {
            switch status {
            case .upToDate, .updateAvailable:
                break  // a source answered; the tail is never reached
            case .unknown:
                break  // anUnownedAppReportsAThrownFailure / …WithNoApplicableSource
            case .toolboxManaged:
                break  // aToolboxOwnedAppKeepsItsChannelWhenASourceThrows
            case .testFlightManaged:
                break  // aTestFlightAppNeverReachesASourceAtAll
            case .appStoreManaged:
                break  // anAppStoreAppReportsAFailedStoreLookup
            case .error:
                break  // the outcome under test throughout
            }
        }
    }
}
