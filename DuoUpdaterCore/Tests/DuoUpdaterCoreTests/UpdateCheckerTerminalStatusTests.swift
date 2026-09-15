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
            /// The vendor refused its newest release for this macOS (#634).
            case refusing(OSWindowRefusal)
        }

        let name: String
        /// Must be stated for a store row. `UpdateChecker` skips every source
        /// that says no when `isMASApp` — inheriting the protocol default here
        /// silently turned two cases below into tests of the SKIP, one of them
        /// red and the other passing without measuring anything (caught in
        /// adversarial review, not by the suite).
        let answersAppStoreCopies: Bool
        private let behaviour: Behaviour
        private let lock = NSLock()
        private var consultedCount = 0

        init(_ behaviour: Behaviour, name: String = "Scripted",
             answersAppStoreCopies: Bool = false) {
            self.behaviour = behaviour
            self.name = name
            self.answersAppStoreCopies = answersAppStoreCopies
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
            case .refusing(let refusal):
                // The refused release as a source would report it: the refusal's
                // own version as the marketing string, no build.
                throw OSWindowRefused(refusal, release: RemoteVersion(
                    shortVersion: refusal.version, version: nil, downloadURL: nil,
                    sourceName: name))
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
    /// carried `guard !app.isMASApp`, and it was wrong three times — twice about
    /// the sources, and once about Keka, which two successive comments called a
    /// store copy and then not one. Both were measured, on different Macs, and
    /// both were wrong to be written as facts about the app (see
    /// `SourceStorePolicyTests`). Do not reintroduce an inventory here, and do not
    /// settle a policy question with what is installed on the machine you happen
    /// to be on; the gate and its table are the answer.
    ///
    /// If a later change makes this `.appStoreManaged`, that is a decision to
    /// argue for here, not a tidy-up of an inconsistency.
    @Test func anAppStoreAppReportsAFailedStoreLookup() async {
        let source = ScriptedSource(.throwing, name: "App Store",
                                    answersAppStoreCopies: true)
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
    ///
    /// `answersAppStoreCopies: true` is what makes this measure the MISS. Without
    /// it the source is skipped by the gate and `.appStoreManaged` arrives from
    /// the skip path — an answer a wrong implementation (one that turned a store
    /// miss into `.unknown`) would produce too.
    @Test func anAppStoreAppWithNoAnswerIsManaged() async {
        let source = ScriptedSource(.missing, name: "App Store",
                                    answersAppStoreCopies: true)
        let result = await UpdateChecker(sources: [source]).check(Self.app(isMASApp: true))
        #expect(source.consulted)
        #expect(result.status == .appStoreManaged)
    }

    /// The combination the gate creates and neither case above covers: a store
    /// row whose non-store source is silenced AND whose store lookup throws.
    /// The silenced one must not contribute to the verdict in either direction —
    /// it neither supplies an answer nor suppresses the `.error` the store's own
    /// failure earns.
    ///
    /// Ordered with the silenced source FIRST, so a gate that ran it would let it
    /// answer before the store ever threw.
    @Test func aSilencedSourceNeitherAnswersNorHidesTheStoresFailure() async {
        let silenced = ScriptedSource(.answering("9.9"), name: "Elsewhere")
        let store = ScriptedSource(.throwing, name: "App Store",
                                   answersAppStoreCopies: true)
        let result = await UpdateChecker(sources: [silenced, store])
            .check(Self.app(isMASApp: true))

        #expect(!silenced.consulted)
        #expect(store.consulted)
        guard case .error = result.status else {
            Issue.record("expected .error, got \(result.status)")
            return
        }
    }

    // MARK: - .outsideOSWindow — the vendor refused this macOS (#634)

    private static let ceiling = OSWindowRefusal(
        bound: .ceiling(maximum: "26.99"), version: "6.5", hostOS: "27.0.0")
    private static let floor = OSWindowRefusal(
        bound: .floor(minimum: "28.0"), version: "7.0", hostOS: "27.0.0")

    /// A source that READ its answer and was told "not for this macOS" is neither
    /// the dash (a source covered the app) nor a failed check (nothing to retry).
    ///
    /// Mutation: delete the `catch let refused as OSWindowRefused` clause, so the
    /// refusal falls into the generic `catch` → `.error` → red.
    @Test func aRefusedReleaseIsNotForThisMacOSRatherThanAFailure() async {
        let source = ScriptedSource(.refusing(Self.ceiling))
        let result = await UpdateChecker(sources: [source]).check(Self.app())
        #expect(source.consulted)
        #expect(result.status == .outsideOSWindow(Self.ceiling))
        #expect(result.remote == nil)
    }

    /// A refusal is only news about a release that would have been an update. A
    /// copy already on the refused build — the Mac moved to a macOS the vendor has
    /// not caught up with — or past it (a lagging or abandoned feed) must not be
    /// told the vendor "won't offer" it: that row stays what it was before, the
    /// dash of a source with nothing to say.
    ///
    /// Mutation: drop the `evaluate` guard in the `OSWindowRefused` catch → both
    /// copies come back `.outsideOSWindow` → red.
    @Test func aRefusedReleaseTheCopyAlreadyHasOrPassedIsNotNews() async {
        for installed in ["6.5", "6.6"] {
            let app = InstalledApp(
                name: "Subject", bundleID: "com.example.subject",
                shortVersion: installed, buildVersion: nil,
                path: URL(fileURLWithPath: "/Applications/Subject.app"),
                isMASApp: false, sparkleFeedURL: nil)
            let result = await UpdateChecker(sources: [ScriptedSource(.refusing(Self.ceiling))]).check(app)
            #expect(result.status == .unknown, "installed \(installed)")
        }
    }

    /// A refusal is a miss for THAT source only: a later source with a release this
    /// Mac can run is the better answer, and it must still be asked.
    ///
    /// Mutation: `return` the `.outsideOSWindow` row from inside the catch instead
    /// of `continue` → the second source is never consulted → red.
    @Test func aLaterSourceThatAnswersBeatsTheRefusal() async {
        let refusing = ScriptedSource(.refusing(Self.ceiling), name: "Vendor")
        let answering = ScriptedSource(.answering("6.4.9"), name: "Elsewhere")
        let result = await UpdateChecker(sources: [refusing, answering]).check(Self.app())
        #expect(refusing.consulted)
        #expect(answering.consulted)
        #expect(result.status == .updateAvailable(latest: "6.4.9"))
    }

    /// The refusal outranks another source's failure, in either order: it is a
    /// fact the row can state, and `.error` would swap it for a Retry that changes
    /// nothing about the vendor's bound.
    ///
    /// Mutation: move the refusal's `return` below the `if let lastError` block →
    /// both orders come back `.error` → red.
    @Test func aRefusalOutranksAnotherSourcesFailure() async {
        for order in [["refusing", "throwing"], ["throwing", "refusing"]] {
            let sources = order.map { kind in
                kind == "refusing"
                    ? ScriptedSource(.refusing(Self.ceiling), name: kind)
                    : ScriptedSource(.throwing, name: kind)
            }
            let result = await UpdateChecker(sources: sources).check(Self.app())
            #expect(result.status == .outsideOSWindow(Self.ceiling), "order \(order)")
        }
    }

    /// Sources are in priority order; the row names the refusal of the first one,
    /// the source it would otherwise have trusted.
    ///
    /// Mutation: assign `refusal = refused.refusal` unconditionally → the second
    /// source's floor is named → red.
    @Test func theFirstSourcesRefusalIsTheOneNamed() async {
        let result = await UpdateChecker(sources: [
            ScriptedSource(.refusing(Self.ceiling), name: "first"),
            ScriptedSource(.refusing(Self.floor), name: "second"),
        ]).check(Self.app())
        #expect(result.status == .outsideOSWindow(Self.ceiling))
    }

    /// Below Toolbox, like a failure is: the borrowed vendor read being refused
    /// changes nothing about "open Toolbox".
    ///
    /// Mutation: drop `!app.isToolboxManaged` from the refusal's condition → red.
    @Test func aToolboxOwnedAppKeepsItsChannelWhenTheVendorRefuses() async {
        let app = Self.androidStudioPreview(.canary)
        // Newer than the fixture's 2025.2: a refusal of an OLDER release is a miss
        // before precedence is ever asked, and this would pass without measuring it.
        let refusal = OSWindowRefusal(bound: .ceiling(maximum: "26.99"), version: "2026.1", hostOS: "27.0.0")
        let source = ScriptedSource(.refusing(refusal))
        let result = await UpdateChecker(sources: [source]).check(app)
        #expect(source.consulted)
        #expect(result.status == .toolboxManaged)
    }

    // MARK: - the gap this file is meant to close

    /// The list above is only a guard while it is COMPLETE. `UpdateStatus` carries
    /// two more cases (`upToDate`, `updateAvailable`), which `check` reaches from
    /// a source that answered and never from the "no source answered" tail — so
    /// the tail's five are all of them, and each has a row above.
    ///
    /// Written as an exhaustive `switch` on purpose: adding a case to
    /// `UpdateStatus` stops compiling here, which is the only mechanism that makes
    /// someone come back and decide what a thrown source does to it.
    @Test func everyStatusIsAccountedFor() {
        for status: UpdateStatus in [
            .upToDate, .updateAvailable(latest: "1"), .unknown,
            .appStoreManaged, .toolboxManaged, .testFlightManaged, .error("x"),
            .outsideOSWindow(Self.ceiling),
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
            case .outsideOSWindow:
                break  // aRefusedReleaseIsNotForThisMacOSRatherThanAFailure and the rows after it
            }
        }
    }
}
