import Foundation

/// Who is on the other end of an accepted helper connection. Every privileged
/// operation runs in this user's session; the client's own uid/gid/userName
/// arguments are only checked against it, never trusted.
struct HelperClientIdentity: Equatable, Sendable {
    let uid: uid_t
    let gid: gid_t
    let userName: String
}

/// The listener-side seam `HelperPeerGate.install` drives. `NSXPCListener` is the
/// only production conformer; tests add a recorder so the exact requirement string
/// and the order of the three calls are asserted, not assumed.
protocol HelperPeerListener: AnyObject {
    func setConnectionCodeSigningRequirement(_ requirement: String)
    var delegate: NSXPCListenerDelegate? { get set }
    func resume()
}

extension NSXPCListener: HelperPeerListener {}

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
/// ## Fail-closed invariants (each has a test in `HelperPeerGateTests`)
///
/// - No requirement (our own team unreadable: unsigned / ad-hoc) ⇒ nothing is
///   installed on the listener and **every** connection is rejected here.
/// - The gate only answers for the listener it installed the requirement on. The
///   delegate can't ask a listener whether it carries a requirement, so being
///   attached to any other listener rejects everything instead of silently
///   accepting unchecked peers.
/// - Rejected connections never reach `connectionOpened`, so they can't keep the
///   daemon alive (`IdleExit`).
final class HelperPeerGate: NSObject, NSXPCListenerDelegate {
    static let clientBundleIdentifier = "com.duoupdater.app"

    /// `anchor apple generic and identifier "com.duoupdater.app" and certificate
    /// leaf[subject.OU] = "<this helper's own team>"`, or nil when that team can't
    /// be read. See `OwnTeamIdentifier`.
    static let clientRequirement: String? =
        OwnTeamIdentifier.requirement(bundleIdentifier: clientBundleIdentifier)

    /// Set only when a requirement was actually installed on that listener, so
    /// "no team" and "some other listener" collapse into the same single check.
    private weak var installedOn: HelperPeerListener?
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

    /// Install the requirement, attach the gate, and start the listener — in that
    /// order, and the only way to obtain a gate, so no listener can be resumed
    /// with this delegate before the requirement is on it.
    ///
    /// The listener holds its delegate weakly: the caller must keep the returned
    /// gate alive for as long as the listener runs.
    static func install(on listener: HelperPeerListener,
                        requirement: String? = clientRequirement,
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
            gate.installedOn = listener
        } else {
            NSLog("duo-helper: own team identifier unavailable — every connection will be rejected")
        }
        listener.delegate = gate
        listener.resume()
        return gate
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        // A peer that fails the code-signing requirement never gets here (see the
        // type comment), so the rejections logged below are the only ones this
        // process sees; libxpc drops the others without calling us.
        guard let installedOn, installedOn === (listener as AnyObject) else {
            NSLog("duo-helper: rejected connection — no client requirement is installed on this listener (own team unreadable, or not the listener this gate installed)")
            return false
        }
        guard let identity = Self.identity(uid: conn.effectiveUserIdentifier,
                                           gid: conn.effectiveGroupIdentifier) else {
            NSLog("duo-helper: rejected connection — no account for euid \(conn.effectiveUserIdentifier)")
            return false
        }
        conn.exportedInterface = interface
        conn.exportedObject = exportedObject(identity)
        // Hold the process open for as long as this client is talking to us, and
        // let it exit once nobody is — see `IdleExit`, which is what keeps a
        // replaced app bundle from stranding a helper launchd will never restart.
        // Rejected connections deliberately never get here: they must not keep a
        // daemon alive.
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
