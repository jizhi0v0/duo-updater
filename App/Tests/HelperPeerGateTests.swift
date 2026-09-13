import Foundation
import Security
import Testing

/// The root helper's XPC peer gate (`App/Helper/HelperPeerGate.swift`) and its
/// request-identity check (`HelperService.installMASApp`).
///
/// ## What these run against, and what they can't
///
/// Real XPC, in one process: an `NSXPCListener.anonymous()` with the gate installed,
/// and a client connection to its endpoint from the same test process. The
/// requirement checks are libxpc's, evaluated against the sender of the connection
/// request / each message — here the test process itself. So "a peer that doesn't
/// match" means a requirement this process doesn't satisfy, and "a peer that does"
/// means this process's own designated requirement, read at run time. Neither
/// depends on how the host signed `xctest` (ad-hoc on both Xcode 26.6 and 27, which
/// is exactly why `anchor apple` can't serve as the "matching" requirement here).
///
/// Cross-process behaviour — a separately signed peer, a launchd Mach service, the
/// exec race — needs launchd agents and is NOT in `make test`; run
/// `scripts/xpc-peer-probe/run.sh`.
///
/// ## Known mutations no case here catches
///
/// Named so nobody mistakes the green run for coverage of them. Each is covered
/// only by a manual step (listed in PR #591):
///
/// - **`effectiveUserIdentifier` → `geteuid()`** (and the gid twin) in the delegate.
///   Peer and listener are one process, so both give the same number. Manual: a
///   client running as a different user than the helper (the helper is root, so
///   any real install) must get its own uid in `SUDO_UID`, not 0.
/// - **`install(on:team:…)`'s default `team:` changed** (to nil, or to a literal).
///   The ad-hoc test host has no team, so `OwnTeamIdentifier.current` is nil either
///   way. Manual: a real signed install must still serve the app (nil ⇒ every App
///   Store install fails) and refuse a forged client.
/// - **`main.swift` dropping the gate** (`_ = HelperPeerGate.install(…)`): the
///   listener holds its delegate weakly, so the gate is deallocated and the listener
///   is left with no delegate (what it then does with connections was not measured).
///   main.swift's top-level code is not compiled here. Manual: a real install must
///   serve the app, and a forged client must still be refused.
/// - **Weaker requirement the test process also fails** (e.g. `anchor apple`) in the
///   real-XPC cases — caught instead by the recorder in
///   `installPassesTheRequirementVerbatimBeforeDelegateAndResume`.
///
/// Every other case names the mutation it was seen to fail under.
@Suite(.timeLimit(.minutes(1)))
struct HelperPeerGateTests {

    /// Matches nothing that can run this test: invented bundle id and team.
    static let neverMatching =
        "anchor apple generic and identifier \"com.duoupdater.zzfixture.app\" "
        + "and certificate leaf[subject.OU] = \"ZZFIXTURE0\""

    // MARK: real XPC

    /// The listener layer: the delegate is never even consulted.
    ///
    /// Mutation: delete `listener.setConnectionCodeSigningRequirement(requirement)`
    /// in `install` — the per-connection layer still keeps the call from running,
    /// but the delegate is consulted, so `exportedObjectsMade` and `opened` become 1.
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

    /// The per-connection layer on its own: the real listener carries a requirement
    /// this process MEETS (put there by `RequirementSwappingListener`), while the
    /// gate's own requirement — the one it sets on each accepted connection — is
    /// `neverMatching`. Not vacuous against the listener layer: it asserts the
    /// delegate DID accept (`exportedObjectsMade == 1`, `opened == 1`), so the only
    /// thing left to stop the call is the per-connection requirement. And the
    /// accepted-then-rejected connection must still be released (`closed == 1`),
    /// or it would hold `IdleExit` open.
    ///
    /// Mutation: delete `conn.setCodeSigningRequirement(installation.requirement)`
    /// → the call replies and `invocations` becomes 1.
    @Test func aConnectionRequirementStopsWhatTheListenerLetThrough() async throws {
        let rec = Recorder()
        let real = NSXPCListener.anonymous()
        let swapping = RequirementSwappingListener(wrapping: real,
                                                   listenerRequirement: try Self.ownDesignatedRequirement())
        let gate = HelperPeerGate.install(on: swapping, requirement: Self.neverMatching,
                                          interface: Self.interface,
                                          exportedObject: rec.makeExported,
                                          connectionOpened: rec.opened,
                                          connectionClosed: rec.closed)
        let (outcome, client) = await Self.callKeepingConnection(real.endpoint)
        #expect(outcome == .failed)
        await rec.waitForClose { client.invalidate() }
        withExtendedLifetime(gate) {}
        real.invalidate()

        #expect(rec.snapshot.exportedObjectsMade == 1)
        #expect(rec.snapshot.opened == 1)
        #expect(rec.snapshot.invocations == 0)
        #expect(rec.snapshot.closed == 1)
    }

    /// The harness's positive control, and the identity binding.
    ///
    /// Mutations: `HelperClientIdentity(uid: 0, …)` in `identity(uid:gid:)` → the
    /// uid assertion fails; drop `conn.invalidationHandler = connectionClosed` →
    /// the closed count stays 0 and the suite time limit fails the case; replace the
    /// requirement installed by `install` with `"anchor apple"` → no reply.
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
    /// Mutation: in the delegate, enforce the guard only `if let installation`
    /// (accept when nothing was installed) → this process is served.
    /// Mutation: move `connectionOpened()` above the `installation` guard →
    /// `opened` becomes 1 for a rejected peer.
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
    /// Mutation: drop `installedOn === listener` from the guard → the unguarded
    /// listener serves this process (its own requirement matches us).
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

    /// The production entry point, with a team: what reaches the listener is the
    /// client requirement for THAT team, character for character.
    ///
    /// Mutation: in `install(on:team:…)`, pass
    /// `OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.cli", team: team)`
    /// instead of `requirement(team: team)` → the recorded requirement differs.
    @Test func installForATeamInstallsTheAppRequirementForThatTeam() {
        let spy = SpyListener()
        let gate = HelperPeerGate.install(on: spy, team: "ZZFIXTURE0", interface: Self.interface,
                                          exportedObject: { _ in NSObject() },
                                          connectionOpened: {}, connectionClosed: {})
        withExtendedLifetime(gate) {}
        #expect(spy.events == ["requirement:" + Self.appRequirementForFixtureTeam, "delegate", "resume"])
    }

    // MARK: the requirement string

    static let appRequirementForFixtureTeam =
        "anchor apple generic and identifier \"com.duoupdater.app\" and certificate leaf[subject.OU] = \"ZZFIXTURE0\""

    /// The exact string, pinned for an invented team. The bundle id and the team
    /// clause are the load-bearing parts: a different id would admit another binary
    /// of the same team (the `duo` CLI, the helper itself) as a root client.
    ///
    /// Mutations: in `HelperPeerGate.requirement(team:)`, use bundle id
    /// `"com.duoupdater.cli"`; in `OwnTeamIdentifier`, return `"anchor apple"` or drop
    /// the `certificate leaf[subject.OU]` clause → the first expectation fails.
    @Test func theClientRequirementIsPinnedForATeam() {
        #expect(HelperPeerGate.requirement(team: "ZZFIXTURE0") == Self.appRequirementForFixtureTeam)
        #expect(HelperPeerGate.requirement(team: nil) == nil)
    }

    /// A team is spliced between quotes, and a malformed requirement crashes the
    /// helper at launch, so anything but ten `A-Z0-9` characters yields nil.
    ///
    /// Mutations: drop `team.utf8.count == 10` → the short and long cases fail;
    /// drop the character-set check → the quote, lowercase and space cases fail.
    @Test(arguments: [
        "",                      // empty
        "ZZFIXTURE",             // 9
        "ZZFIXTURE00",           // 11
        "ZZFIXTURE\"",           // 10, with a quote that would close the string
        "zzfixture0",            // 10, lowercase
        "ZZFIX TURE",            // 10, with a space
        "ZZFIXTUR\" or \"",      // injection-shaped
    ])
    func aMalformedTeamYieldsNoRequirement(_ team: String) {
        #expect(OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.app", team: team) == nil)
    }

    /// The fixture team used throughout is itself well-formed, so the cases above
    /// aren't passing on a fixture the validation would have rejected anyway.
    @Test func theFixtureTeamIsWellFormed() {
        #expect("ZZFIXTURE0".utf8.count == 10)
        #expect(OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.app", team: "ZZFIXTURE0") != nil)
        #expect(HelperPeerGate.clientBundleIdentifier == "com.duoupdater.app")
    }

    /// The two ways to have no requirement need different fixes, so the log must
    /// tell them apart.
    ///
    /// Mutation: make `missingRequirementReason` always return the "unavailable"
    /// text → the malformed-team expectation fails.
    @Test func noTeamAndAMalformedTeamAreLoggedDifferently() {
        #expect(OwnTeamIdentifier.missingRequirementReason(team: nil) == "own team identifier unavailable")
        #expect(OwnTeamIdentifier.missingRequirementReason(team: "zz\"fixture")
                == "own team identifier is not a well-formed Team ID (ten A-Z0-9 characters)")
    }

    // MARK: identity

    /// A uid no account can hold: `(uid_t)-1` is the "no change" sentinel of
    /// `setreuid`/`chown`, so no passwd entry exists for it on any host.
    ///
    /// Mutation: in `identity(uid:gid:)`, fall back to a name
    /// (`accountName(for: uid) ?? "unknown"`) → an identity is returned.
    @Test func aUidWithNoAccountHasNoIdentity() {
        #expect(HelperPeerGate.identity(uid: uid_t.max, gid: 0) == nil)
    }

    static let fixtureIdentity = HelperClientIdentity(uid: 4242, gid: 4343, userName: "zzfixture")

    /// Mutations: drop any one of the three clauses of `matchesClaim` → the case for
    /// that field fails.
    @Test func aClaimMustMatchTheConnectionOnEveryField() {
        let id = Self.fixtureIdentity
        #expect(id.matchesClaim(uid: 4242, gid: 4343, userName: "zzfixture"))
        #expect(!id.matchesClaim(uid: 0, gid: 4343, userName: "zzfixture"))
        #expect(!id.matchesClaim(uid: 4242, gid: 0, userName: "zzfixture"))
        #expect(!id.matchesClaim(uid: 4242, gid: 4343, userName: "root"))
    }

    /// The call site in `installMASApp`. Both requests stop before anything touches
    /// the disk or starts a process: the matching one at the lexical log-path check
    /// (an invented, non-temporary directory), which proves it got PAST the identity
    /// check; the mismatching one at the identity check.
    ///
    /// Mutation: delete the `matchesClaim` guard in `installMASApp` → the mismatching
    /// request also reaches "invalid log path".
    @Test func installMASAppRefusesAClaimThatDiffersFromItsConnection() async throws {
        // Tripwire: this case must never run where `HelperService` could find a real
        // `mas`. Today the bundle is hostless — `Bundle.main` is `xctest`, and there
        // is no `Contents/Resources/mas` beside it. Should a TEST_HOST ever make the
        // app the main bundle, fail here instead of calling into a service that one
        // guard reordering away would run `mas` as whoever runs the tests.
        try #require(Bundle.main.bundleIdentifier != "com.duoupdater.app")
        let masBesideMain = URL(fileURLWithPath: try #require(Bundle.main.executablePath))
            .resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/mas").path
        try #require(!FileManager.default.isExecutableFile(atPath: masBesideMain))

        let service = HelperService(clientIdentity: Self.fixtureIdentity)
        let logPath = "/ZZFixture-not-a-temp-dir/duo-mas-1.log"
        let matching = await Self.install(service, uid: 4242, logPath: logPath)
        let mismatching = await Self.install(service, uid: 0, logPath: logPath)
        #expect(matching.status == -1)
        #expect(matching.message == "invalid log path")
        #expect(mismatching.status == -1)
        #expect(mismatching.message == "client identity did not match its XPC connection")
    }

    static func install(_ service: HelperService, uid: Int, logPath: String) async -> (status: Int32, message: String?) {
        await withCheckedContinuation { cont in
            service.installMASApp(adamID: 1, uid: uid, gid: 4343, userName: "zzfixture", logPath: logPath) {
                cont.resume(returning: ($0, $1))
            }
        }
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

/// Records what `install` does to a listener; serves no connections.
private final class SpyListener: HelperPeerListener {
    var events: [String] = []
    weak var delegate: NSXPCListenerDelegate? {
        didSet { events.append("delegate") }
    }
    func setConnectionCodeSigningRequirement(_ requirement: String) {
        events.append("requirement:" + requirement)
    }
    func resume() { events.append("resume") }
    var xpcListener: NSXPCListener? { nil }
}

/// A real listener that receives `listenerRequirement` instead of whatever the
/// gate asks for, so the gate's own requirement only acts per connection.
/// (`NSXPCListener.anonymous()` can't be subclassed to do this: called on a
/// subclass it still returns a plain `NSXPCListener`.)
private final class RequirementSwappingListener: HelperPeerListener {
    let wrapped: NSXPCListener
    let listenerRequirement: String
    init(wrapping wrapped: NSXPCListener, listenerRequirement: String) {
        self.wrapped = wrapped
        self.listenerRequirement = listenerRequirement
    }
    func setConnectionCodeSigningRequirement(_ requirement: String) {
        wrapped.setConnectionCodeSigningRequirement(listenerRequirement)
    }
    var delegate: NSXPCListenerDelegate? {
        get { wrapped.delegate }
        set { wrapped.delegate = newValue }
    }
    func resume() { wrapped.resume() }
    var xpcListener: NSXPCListener? { wrapped }
}
