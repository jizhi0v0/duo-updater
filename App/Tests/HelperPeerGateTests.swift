import Foundation
import Security
import Testing

/// The root helper's XPC peer gate (`App/Helper/HelperPeerGate.swift`).
///
/// ## What these run against, and what they can't
///
/// Real XPC, in one process: an `NSXPCListener.anonymous()` with the gate installed,
/// and a client connection to its endpoint from the same test process. The
/// requirement check is libxpc's, on the listener connection, evaluated against
/// the connection request's sender — here the test process itself. So "a peer
/// that doesn't match" means a requirement this process doesn't satisfy, and "a
/// peer that does" means this process's own designated requirement, read at run
/// time. Neither depends on how the host signed `xctest` (it is ad-hoc on both
/// Xcode 26.6 and 27, which is exactly why `anchor apple` can't serve as the
/// "matching" requirement here).
///
/// Cross-process behaviour — a separately signed peer, a launchd Mach service,
/// the exec race — needs launchd agents and is NOT in `make test`; run
/// `scripts/xpc-peer-probe/run.sh`. One consequence, named rather than hidden: a
/// mutation that swaps the requirement for a *weaker* one this process still fails
/// (e.g. `anchor apple`) is not caught by the real-XPC cases; it is caught by
/// `installPassesTheRequirementVerbatimBeforeDelegateAndResume`, which records
/// what reaches the listener.
///
/// Every case names the mutation it was seen to fail under.
@Suite(.timeLimit(.minutes(1)))
struct HelperPeerGateTests {

    /// Matches nothing that can run this test: invented bundle id and team.
    static let neverMatching =
        "anchor apple generic and identifier \"com.duoupdater.zzfixture.app\" "
        + "and certificate leaf[subject.OU] = \"ZZFIXTURE0\""

    // MARK: real XPC

    /// Mutation: delete `listener.setConnectionCodeSigningRequirement(requirement)`
    /// in `install` — the delegate then accepts, `exportedObjectsMade` and
    /// `invocations` become 1, and the call replies.
    @Test func aPeerFailingTheRequirementNeverReachesTheExportedObject() async throws {
        let rec = Recorder()
        let listener = NSXPCListener.anonymous()
        let gate = HelperPeerGate.install(on: listener, requirement: Self.neverMatching,
                                          interface: Self.interface,
                                          exportedObject: rec.makeExported,
                                          connectionOpened: rec.opened,
                                          connectionClosed: rec.closed)
        let outcome = await Self.call(listener.endpoint)
        withExtendedLifetime(gate) {}
        listener.invalidate()

        #expect(outcome == .failed)
        #expect(rec.snapshot.exportedObjectsMade == 0)
        #expect(rec.snapshot.invocations == 0)
        #expect(rec.snapshot.opened == 0)
    }

    /// The harness's positive control, and the identity binding.
    ///
    /// Mutations: `HelperClientIdentity(uid: 0, …)` in `identity(uid:gid:)` → the
    /// uid assertion fails; drop `conn.invalidationHandler = connectionClosed` →
    /// the closed count stays 0 and the suite time limit fails the case; replace the
    /// requirement installed by `install` with `neverMatching` → no reply.
    @Test func aPeerMeetingTheRequirementIsServedAsItsOwnUser() async throws {
        let rec = Recorder()
        let listener = NSXPCListener.anonymous()
        let gate = HelperPeerGate.install(on: listener, requirement: try Self.ownDesignatedRequirement(),
                                          interface: Self.interface,
                                          exportedObject: rec.makeExported,
                                          connectionOpened: rec.opened,
                                          connectionClosed: rec.closed)
        let (outcome, client) = await Self.callKeepingConnection(listener.endpoint)
        #expect(outcome == .replied)

        let identity = try #require(rec.snapshot.identities.first)
        #expect(identity.uid == geteuid())
        #expect(identity.gid == getegid())
        #expect(identity.userName == NSUserName())

        // Q2: an accepted connection is counted once and released once.
        await rec.waitForClose { client.invalidate() }
        withExtendedLifetime(gate) {}
        listener.invalidate()
        #expect(rec.snapshot.opened == 1)
        #expect(rec.snapshot.closed == 1)
    }

    /// No team ⇒ no requirement ⇒ reject everyone, including a peer that would
    /// have matched anything.
    ///
    /// Mutation: move `gate.installedOn = listener` out of the `if let requirement`
    /// branch (so the nil-team path accepts) → this process is served.
    /// Mutation: move `connectionOpened()` above the `installedOn` guard → `opened`
    /// becomes 1 for a rejected peer.
    @Test func withoutATeamEveryPeerIsRejected() async throws {
        let rec = Recorder()
        let listener = NSXPCListener.anonymous()
        let gate = HelperPeerGate.install(on: listener, requirement: nil,
                                          interface: Self.interface,
                                          exportedObject: rec.makeExported,
                                          connectionOpened: rec.opened,
                                          connectionClosed: rec.closed)
        let outcome = await Self.call(listener.endpoint)
        withExtendedLifetime(gate) {}
        listener.invalidate()

        #expect(outcome == .failed)
        #expect(rec.snapshot.exportedObjectsMade == 0)
        #expect(rec.snapshot.invocations == 0)
        #expect(rec.snapshot.opened == 0)
    }

    /// The delegate can't see whether a listener carries a requirement, so a gate
    /// attached to any listener other than the one it installed on must refuse.
    ///
    /// Mutation: delete the `installedOn === listener` comparison (keep only
    /// `guard let installedOn`) → the unguarded listener serves this process.
    @Test func aGateAttachedToAnotherListenerRejects() async throws {
        let rec = Recorder()
        let guarded = NSXPCListener.anonymous()
        let gate = HelperPeerGate.install(on: guarded, requirement: try Self.ownDesignatedRequirement(),
                                          interface: Self.interface,
                                          exportedObject: rec.makeExported,
                                          connectionOpened: rec.opened,
                                          connectionClosed: rec.closed)
        let unguarded = NSXPCListener.anonymous()
        unguarded.delegate = gate
        unguarded.resume()

        let outcome = await Self.call(unguarded.endpoint)
        withExtendedLifetime(gate) {}
        guarded.invalidate()
        unguarded.invalidate()

        #expect(outcome == .failed)
        #expect(rec.snapshot.exportedObjectsMade == 0)
        #expect(rec.snapshot.opened == 0)
    }

    // MARK: what reaches the listener

    /// Mutations: pass `"anchor apple"` to `setConnectionCodeSigningRequirement`;
    /// delete that call; move `listener.resume()` above it — each changes `events`.
    @Test func installPassesTheRequirementVerbatimBeforeDelegateAndResume() {
        let spy = SpyListener()
        let gate = HelperPeerGate.install(on: spy, requirement: Self.neverMatching,
                                          interface: Self.interface,
                                          exportedObject: { _ in NSObject() },
                                          connectionOpened: {}, connectionClosed: {})
        #expect(spy.events == ["requirement:" + Self.neverMatching, "delegate", "resume"])
        #expect(spy.delegate === gate)
    }

    /// The production call site passes no requirement, so the default decides.
    /// Written so it holds whether or not this test process has a team.
    ///
    /// Mutation: change the default to `requirement: String? = "anchor apple"` →
    /// the recorded requirement differs from `clientRequirement`.
    @Test func installDefaultsToTheClientRequirement() {
        let spy = SpyListener()
        let gate = HelperPeerGate.install(on: spy, interface: Self.interface,
                                          exportedObject: { _ in NSObject() },
                                          connectionOpened: {}, connectionClosed: {})
        withExtendedLifetime(gate) {}
        let expected = HelperPeerGate.clientRequirement.map { ["requirement:" + $0] } ?? []
        #expect(spy.events == expected + ["delegate", "resume"])
    }

    /// The exact string, pinned. The team clause is the load-bearing one.
    ///
    /// Mutations: in `OwnTeamIdentifier.requirement(bundleIdentifier:team:)`, return
    /// `"anchor apple"`, or drop the `certificate leaf[subject.OU]` clause, or drop
    /// `!team.isEmpty` → a case below fails. In `HelperPeerGate`, change
    /// `clientBundleIdentifier`, or define `clientRequirement` as `"anchor apple"`
    /// → the second or last expectation fails.
    @Test func theClientRequirementIsTheSameStringAsBefore() {
        #expect(OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.app", team: "ZZFIXTURE0")
                == "anchor apple generic and identifier \"com.duoupdater.app\" and certificate leaf[subject.OU] = \"ZZFIXTURE0\"")
        #expect(HelperPeerGate.clientBundleIdentifier == "com.duoupdater.app")
        #expect(OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.app", team: nil) == nil)
        #expect(OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.app", team: "") == nil)
        #expect(HelperPeerGate.clientRequirement
                == OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.app"))
    }

    // MARK: fixtures

    static var interface: NSXPCInterface { NSXPCInterface(with: ZZPeerGateProbe.self) }

    enum Outcome: Equatable { case replied, failed }

    /// This process's own designated requirement, as a string — the one
    /// requirement guaranteed to match the sender of a self-connection.
    static func ownDesignatedRequirement() throws -> String {
        var code: SecCode?
        try #require(SecCodeCopySelf([], &code) == errSecSuccess)
        var staticCode: SecStaticCode?
        try #require(SecCodeCopyStaticCode(try #require(code), [], &staticCode) == errSecSuccess)
        var requirement: SecRequirement?
        try #require(SecCodeCopyDesignatedRequirement(try #require(staticCode), [], &requirement) == errSecSuccess)
        var text: CFString?
        try #require(SecRequirementCopyString(try #require(requirement), [], &text) == errSecSuccess)
        return try #require(text) as String
    }

    static func call(_ endpoint: NSXPCListenerEndpoint) async -> Outcome {
        let (outcome, connection) = await callKeepingConnection(endpoint)
        connection.invalidate()
        return outcome
    }

    /// One `ping`, answered by the reply or by the connection failing — whichever
    /// comes first, exactly once.
    static func callKeepingConnection(_ endpoint: NSXPCListenerEndpoint) async -> (Outcome, NSXPCConnection) {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = interface
        connection.resume()
        let once = Once()
        let outcome: Outcome = await withCheckedContinuation { cont in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                once.run { cont.resume(returning: .failed) }
            } as? ZZPeerGateProbe
            guard let proxy else { once.run { cont.resume(returning: .failed) }; return }
            proxy.ping { _ in once.run { cont.resume(returning: .replied) } }
        }
        return (outcome, connection)
    }
}

@objc protocol ZZPeerGateProbe {
    func ping(withReply reply: @escaping (String) -> Void)
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        let go = !done
        done = true
        lock.unlock()
        if go { body() }
    }
}

private final class ProbeExported: NSObject, ZZPeerGateProbe {
    let onPing: @Sendable () -> Void
    init(onPing: @escaping @Sendable () -> Void) { self.onPing = onPing }
    func ping(withReply reply: @escaping (String) -> Void) {
        onPing()
        reply("pong")
    }
}

/// Everything the gate did, observed from its hooks and the exported object.
private final class Recorder: @unchecked Sendable {
    struct Snapshot {
        var exportedObjectsMade = 0
        var invocations = 0
        var opened = 0
        var closed = 0
        var identities: [HelperClientIdentity] = []
    }
    private let lock = NSLock()
    private var state = Snapshot()
    private var closeWaiter: CheckedContinuation<Void, Never>?

    var snapshot: Snapshot { lock.lock(); defer { lock.unlock() }; return state }

    var makeExported: @Sendable (HelperClientIdentity) -> AnyObject {
        { [self] identity in
            lock.lock(); state.exportedObjectsMade += 1; state.identities.append(identity); lock.unlock()
            return ProbeExported { [self] in lock.lock(); state.invocations += 1; lock.unlock() }
        }
    }
    var opened: @Sendable () -> Void { { [self] in lock.lock(); state.opened += 1; lock.unlock() } }
    var closed: @Sendable () -> Void {
        { [self] in
            lock.lock()
            state.closed += 1
            let waiter = closeWaiter
            closeWaiter = nil
            lock.unlock()
            waiter?.resume()
        }
    }

    /// Run `trigger`, then return once the gate's close hook has fired.
    func waitForClose(_ trigger: () -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if state.closed > 0 { lock.unlock(); cont.resume(); return }
            closeWaiter = cont
            lock.unlock()
            trigger()
        }
    }
}

private final class SpyListener: HelperPeerListener {
    var events: [String] = []
    weak var delegate: NSXPCListenerDelegate? {
        didSet { events.append("delegate") }
    }
    func setConnectionCodeSigningRequirement(_ requirement: String) {
        events.append("requirement:" + requirement)
    }
    func resume() { events.append("resume") }
}
