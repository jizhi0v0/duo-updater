import Foundation

/// Who is on the other end of an accepted helper connection. Every privileged
/// operation runs in this user's session; the client's own uid/gid/userName
/// arguments are only checked against it, never trusted.
struct HelperClientIdentity: Equatable, Sendable {
    let uid: uid_t
    let gid: gid_t
    let userName: String

    /// Whether the identity a client *claims* in a request is the one its
    /// connection was accepted with. `HelperService.installMASApp` refuses any
    /// request for which this is false — the helper's second security check, which
    /// keeps an accepted client from choosing another user's session.
    func matchesClaim(uid: Int, gid: Int, userName: String) -> Bool {
        uid == Int(self.uid) && gid == Int(self.gid) && userName == self.userName
    }
}

/// The listener-side seam `HelperPeerGate.install` drives. `NSXPCListener` is the
/// only production conformer (its `xpcListener` is itself). Tests add a recorder,
/// so the exact requirement string and the order of the three calls are asserted
/// rather than assumed, and a wrapper that puts a *different* requirement on a real
/// listener, so the per-connection layer can be tested on its own.
protocol HelperPeerListener: AnyObject {
    func setConnectionCodeSigningRequirement(_ requirement: String)
    var delegate: NSXPCListenerDelegate? { get set }
    func resume()
    /// The listener whose delegate callbacks the gate will answer.
    var xpcListener: NSXPCListener? { get }
}

extension NSXPCListener: HelperPeerListener {
    var xpcListener: NSXPCListener? { self }
}

/// THE security gate of the root helper: only the DuoUpdater app built alongside
/// it may drive `mas` as root.
///
/// ## How the check works (public API only)
///
/// The code-signing requirement is installed on the **listener**
/// (`setConnectionCodeSigningRequirement`, macOS 13). Measured 2026-09-13 on
/// macOS 27 (26A428) with `scripts/xpc-peer-probe/run.sh` — separately built,
/// separately signed peer processes reaching a launchd Mach service through the
/// same `NSXPCListener(machServiceName:)` initializer the helper uses:
///
/// - a non-matching peer's connection request is dropped **before this delegate is
///   consulted**: no delegate call, no exported object, no method invoked — also
///   for a burst of 200 queued messages, and for the production-shaped requirement
///   against an ad-hoc binary forging the right identifier;
/// - the check is bound to the request's audit token, not its PID: with the
///   listener SIGSTOPped, a non-matching process queued a request plus a burst and
///   then exec()ed a *matching* binary under the same PID; after SIGCONT the queued
///   request was still rejected, and libxpc logged `xpc_support_check_token …
///   status: -67065` (errSecCSNoSuchCode: that PID version is gone) instead of the
///   plain mismatch's -67050. The same sequence with no requirement delivered the
///   queued messages, so the race was really exercised;
/// - what a rejected client sees did not change: interruption plus
///   NSCocoaErrorDomain 4097, exactly as when a delegate returns false.
///
/// Foundation's header says the same ("the incoming connection is automatically
/// rejected before consulting the delegate"). On this macOS the method is a direct
/// call to `xpc_connection_set_peer_code_signing_requirement` on the listener
/// connection (disassembled), whose header says requests that fail it "are dropped".
///
/// The uid/gid come from `effectiveUserIdentifier` / `effectiveGroupIdentifier`,
/// read here in the delegate. On macOS 27 (disassembled) they are
/// `xpc_connection_get_euid` / `_egid`, which read `val[1]` / `val[2]` of the very
/// audit token `xpc_connection_get_audit_token` returns — and that is what the
/// private `-[NSXPCConnection auditToken]` the old code used calls. So the numbers
/// are the ones `audit_token_to_euid/egid` produced before, from the same field, in
/// the same callback (the one place Computest's CVE-2023-32405 write-up calls the
/// connection token safe: nothing else has arrived on the connection yet).
/// NOT observed on macOS 14–26; the requirement check itself runs in
/// `DuoUpdaterAppTests` on whatever macOS CI uses.
///
/// ## Second layer: the same requirement on every accepted connection
///
/// The listener-level behaviour above was observed on macOS 27 only; CI (macOS
/// 26.6) runs only the in-process cases in `HelperPeerGateTests`, and macOS 14/15
/// are unobserved. So the delegate ALSO sets the requirement on each connection it
/// accepts (`NSXPCConnection.setCodeSigningRequirement`, macOS 13) before resuming
/// it. That layer is checked per message: in the probe's `conn-bad` /
/// `conn-bad-burst` scenarios (per-connection requirement only, none on the
/// listener) a non-matching peer got no method invoked, even with 200 queued
/// messages. It keeps `IdleExit` balanced: there the rejected connection was
/// counted by the delegate and then invalidated, `opened=1 closed=1`, and
/// `aConnectionRequirementStopsWhatTheListenerLetThrough` waits for that close.
/// Setting both was clean in the probe's `both-good` scenario (a matching peer
/// served, no XPC API-misuse trap): on macOS 27 the listener requirement lives on
/// the listener connection and this one on the peer connection. Not observed below
/// macOS 27 — if an older libxpc treated it as a second set on one connection, it
/// would trap: the helper fails closed by crashing, not by accepting.
///
/// ## Fail-closed invariants (each has a test in `HelperPeerGateTests`)
///
/// - No requirement (our own team unreadable, or not a well-formed team id) ⇒
///   nothing is installed on the listener and **every** connection is rejected here.
/// - The gate only answers for the listener it installed the requirement on. The
///   delegate can't ask a listener whether it carries a requirement, so being
///   attached to any other listener rejects everything instead of silently
///   accepting unchecked peers.
/// - Connections rejected before the delegate never reach `connectionOpened`, so
///   they can't keep the daemon alive (`IdleExit`).
final class HelperPeerGate: NSObject, NSXPCListenerDelegate {
    static let clientBundleIdentifier = "com.duoupdater.app"

    /// `anchor apple generic and identifier "com.duoupdater.app" and certificate
    /// leaf[subject.OU] = "<team>"`, or nil for a missing or malformed team. A pure
    /// function of the team so a test can pin its exact output: the test host is
    /// ad-hoc signed, so anything derived from our *own* team is nil there.
    static func requirement(team: String?) -> String? {
        OwnTeamIdentifier.requirement(bundleIdentifier: clientBundleIdentifier, team: team)
    }

    /// Present only when a requirement was actually installed on that listener, so
    /// "no team" and "some other listener" are one check, and the per-connection
    /// requirement can only ever be the one the listener carries.
    private struct Installation {
        weak var listener: NSXPCListener?
        let requirement: String
    }
    private var installation: Installation?
    private let interface: NSXPCInterface
    private let exportedObject: @Sendable (HelperClientIdentity) -> AnyObject
    private let connectionOpened: @Sendable () -> Void
    private let connectionClosed: @Sendable () -> Void

    private init(interface: NSXPCInterface,
                 exportedObject: @escaping @Sendable (HelperClientIdentity) -> AnyObject,
                 connectionOpened: @escaping @Sendable () -> Void,
                 connectionClosed: @escaping @Sendable () -> Void) {
        self.interface = interface
        self.exportedObject = exportedObject
        self.connectionOpened = connectionOpened
        self.connectionClosed = connectionClosed
        super.init()
    }

    /// The production entry point: the requirement for `team`, which defaults to the
    /// team that signed this process (see `OwnTeamIdentifier`).
    static func install(on listener: HelperPeerListener,
                        team: String? = OwnTeamIdentifier.current,
                        interface: NSXPCInterface,
                        exportedObject: @escaping @Sendable (HelperClientIdentity) -> AnyObject,
                        connectionOpened: @escaping @Sendable () -> Void,
                        connectionClosed: @escaping @Sendable () -> Void) -> HelperPeerGate {
        install(on: listener, requirement: requirement(team: team), interface: interface,
                exportedObject: exportedObject,
                connectionOpened: connectionOpened, connectionClosed: connectionClosed)
    }

    /// Install the requirement, attach the gate, and start the listener — in that
    /// order, and the only way to obtain a gate, so no listener can be resumed
    /// with this delegate before the requirement is on it. Takes any requirement so
    /// tests can use ones the test process does or doesn't satisfy; production goes
    /// through `install(on:team:…)`.
    ///
    /// The listener holds its delegate weakly: the caller must keep the returned
    /// gate alive for as long as the listener runs.
    static func install(on listener: HelperPeerListener,
                        requirement: String?,
                        interface: NSXPCInterface,
                        exportedObject: @escaping @Sendable (HelperClientIdentity) -> AnyObject,
                        connectionOpened: @escaping @Sendable () -> Void,
                        connectionClosed: @escaping @Sendable () -> Void) -> HelperPeerGate {
        let gate = HelperPeerGate(interface: interface,
                                  exportedObject: exportedObject,
                                  connectionOpened: connectionOpened,
                                  connectionClosed: connectionClosed)
        if let requirement {
            listener.setConnectionCodeSigningRequirement(requirement)
            gate.installation = Installation(listener: listener.xpcListener, requirement: requirement)
        } else {
            NSLog("duo-helper: own team identifier unavailable — every connection will be rejected")
        }
        listener.delegate = gate
        listener.resume()
        return gate
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        // A peer that fails the listener's code-signing requirement never gets here
        // (see the type comment), so the rejections logged below are the only ones
        // this process sees; libxpc drops the others without calling us.
        guard let installation, let installedOn = installation.listener,
              installedOn === listener else {
            NSLog("duo-helper: rejected connection — no client requirement is installed on this listener (own team unreadable, or not the listener this gate installed)")
            return false
        }
        guard let identity = Self.identity(uid: conn.effectiveUserIdentifier,
                                           gid: conn.effectiveGroupIdentifier) else {
            NSLog("duo-helper: rejected connection — no account for euid \(conn.effectiveUserIdentifier)")
            return false
        }
        // Second layer, checked per message — see "Second layer" in the type comment.
        conn.setCodeSigningRequirement(installation.requirement)
        conn.exportedInterface = interface
        conn.exportedObject = exportedObject(identity)
        // Hold the process open for as long as this client is talking to us, and
        // let it exit once nobody is — see `IdleExit`, which is what keeps a
        // replaced app bundle from stranding a helper launchd will never restart.
        // Connections rejected before this point never get here: they must not keep
        // a daemon alive. One the per-connection requirement rejects later was
        // counted here and is released by the invalidation handler below.
        connectionOpened()
        conn.invalidationHandler = connectionClosed
        conn.resume()
        return true
    }

    static func identity(uid: uid_t, gid: gid_t) -> HelperClientIdentity? {
        guard let user = accountName(for: uid) else { return nil }
        return HelperClientIdentity(uid: uid, gid: gid, userName: user)
    }

    private static func accountName(for uid: uid_t) -> String? {
        // Listener callbacks may validate more than one connection concurrently;
        // `getpwuid` uses shared storage, so use its re-entrant counterpart.
        let suggested = sysconf(_SC_GETPW_R_SIZE_MAX)
        var buffer = [CChar](
            repeating: 0, count: max(suggested > 0 ? Int(suggested) : 16_384, 1_024))
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        let status = buffer.withUnsafeMutableBufferPointer {
            getpwuid_r(uid, &entry, $0.baseAddress, $0.count, &result)
        }
        guard status == 0, result != nil, let name = entry.pw_name else { return nil }
        return String(cString: name)
    }
}
