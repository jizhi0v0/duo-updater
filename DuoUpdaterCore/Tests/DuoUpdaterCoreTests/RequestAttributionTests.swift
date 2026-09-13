import Dispatch
import Foundation
import Testing
@testable import DuoUpdaterCore

/// `RequestAttribution.withApp` makes two promises in its doc comment, and the
/// request-log tests (`EventStoreTests`, `DownloaderTrafficTests`) only reach the
/// first one, through a loopback server. This suite states both directly:
///
///  1. inside `body`, `RequestAttribution.appID` reads the value passed in, and
///     the scope ends with `body` — nesting replaces, then restores;
///  2. `body` runs on the caller's actor. The closures below read nothing
///     isolated, so nothing about how they are written forces them onto it: only
///     `withApp`'s signature does, by letting a non-`Sendable` closure inherit the
///     caller's isolation. If that signature stops doing so (making `body`
///     `sending` is one way — measured) they still compile, and run on the global
///     pool, which is what the queue check sees.
///
/// What "inherits" means is narrower than it sounds, and the actor probe is
/// written around it: a closure in an actor *instance* method is isolated to that
/// actor only if it captures `self`. Without the `_ = self` below, the body runs
/// off the actor on Swift 6.3.3 and 6.4 alike, with the current `withApp`. The
/// main-actor probe has no such condition — a global actor needs no capture.
@Suite struct RequestAttributionTests {

    @Test func theValueIsVisibleInsideTheScopeAndGoneAfterIt() async {
        #expect(RequestAttribution.appID == nil)
        let inside = await RequestAttribution.withApp("ZZFixture-Outer.app") {
            RequestAttribution.appID
        }
        #expect(inside == "ZZFixture-Outer.app")
        #expect(RequestAttribution.appID == nil)
    }

    /// "Nesting is honest": an inner scope — including an explicit `nil`, which is
    /// how the Homebrew catalog and the App Store lookup opt out — replaces the
    /// outer one for its duration and hands it back afterwards.
    @Test func anInnerScopeReplacesTheOuterOneAndRestoresIt() async {
        let seen = await RequestAttribution.withApp("ZZFixture-Outer.app") {
            let inner = await RequestAttribution.withApp("ZZFixture-Inner.app") {
                RequestAttribution.appID
            }
            let opted = await RequestAttribution.withApp(nil) {
                RequestAttribution.appID
            }
            return [inner, opted, RequestAttribution.appID]
        }
        #expect(seen == ["ZZFixture-Inner.app", nil, "ZZFixture-Outer.app"])
    }

    @Test func bodyRunsOnTheCallingActor() async {
        let actor = ZZFixtureQueueActor()
        let observed = await actor.attributedProbe()
        #expect(observed.fixtureHolds, "fixture broken: the actor is not on its own queue")
        #expect(observed.onCallerQueue, "withApp's body left the calling actor")
        #expect(observed.appID == "ZZFixture-Actor.app")
    }

    @MainActor
    @Test func bodyRunsOnTheMainActorWhenCalledFromIt() async {
        let onMain = await RequestAttribution.withApp("ZZFixture-Main.app") {
            pthread_main_np() != 0
        }
        #expect(onMain, "withApp's body left the main actor")
    }
}

/// A serial executor backed by a Dispatch queue that carries a marker, so "is this
/// code running on the actor" is a question the queue can answer at runtime —
/// no `assertIsolated`, which would crash the process instead of failing a test.
private final class ZZFixtureQueueExecutor: SerialExecutor {
    static let key = DispatchSpecificKey<UInt8>()
    let queue: DispatchQueue

    init() {
        queue = DispatchQueue(label: "ZZFixture-RequestAttribution")
        queue.setSpecific(key: Self.key, value: 1)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { unowned.runSynchronously(on: executor) }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    static var isCurrent: Bool { DispatchQueue.getSpecific(key: key) != nil }
}

private actor ZZFixtureQueueActor {
    private let executor = ZZFixtureQueueExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func attributedProbe() async -> (fixtureHolds: Bool, onCallerQueue: Bool, appID: String?) {
        // `fixtureHolds` is what the other answer leans on: this method itself is
        // on the marked queue. Without it a red result could be a broken fixture.
        let fixtureHolds = ZZFixtureQueueExecutor.isCurrent
        let (onQueue, appID) = await RequestAttribution.withApp("ZZFixture-Actor.app") {
            _ = self  // what makes this closure actor-isolated; see the suite comment
            return (ZZFixtureQueueExecutor.isCurrent, RequestAttribution.appID)
        }
        return (fixtureHolds, onQueue, appID)
    }
}
