import Foundation
import DuoUpdaterCore
import os

/// Asks the privileged helper which build a Sparkle installer running as root
/// has staged for one app (`MASHelperProtocol.stagedSparkleBundleVersions`), so
/// a row armed with staging this user cannot read can name its version (#588).
///
/// Every way this can go wrong answers nil, and nil is what the row showed
/// before the helper could be asked: Relaunch with "→ ?". Nothing here is
/// consulted by an install or restart decision (see
/// `SelfUpdaterStaging.rootStagedUpdate`), so a wrong or missing answer can
/// only cost the version label.
///
/// A connection per read, invalidated after it. `HelperShellRunner` caches its
/// connection for the length of an App Store batch; a cached one here would be
/// held open by a background sweep that runs every few minutes, and a held
/// connection keeps the daemon from ever reaching `IdleExit` — the mechanism
/// that lets a helper left behind by an in-place update heal itself.
///
/// Foundation and Core only, with the connection injected, so the test bundle
/// can run it against in-process listeners (`HelperStagedVersionReaderTests`);
/// the production connection is `HelperStagedVersionReader.live`.
struct HelperStagedVersionReader: Sendable {
    private static let log = Logger(subsystem: "com.duoupdater.app", category: "helper")

    /// A new, not yet resumed connection to the helper, or nil when it must not
    /// be asked (not enabled, or no requirement to pin it to). The reader sets
    /// the interface, resumes it and invalidates it.
    let connect: @Sendable () -> NSXPCConnection?
    /// For each of the two calls. The read is a few `openat`s and one small
    /// plist; most of this allows for launchd cold-starting the daemon.
    var timeout: Duration = .seconds(5)

    func read(bundleID: String) async -> SelfUpdaterStaging.RootStagedVersions? {
        guard let conn = connect() else { return nil }
        conn.remoteObjectInterface = NSXPCInterface(with: MASHelperProtocol.self)
        conn.resume()
        defer { conn.invalidate() }

        // Revision first. A helper that predates the selector would drop the
        // message on its side, so it is never sent one.
        guard let versionReply: String = await call(conn, "helperVersion", { proxy, done in
            proxy.helperVersion { done($0) }
        }) else { return nil }
        guard HelperProtocolRevision.supportsStagedSparkleBundleVersions(versionReply: versionReply)
        else {
            Self.log.notice("helper \(versionReply, privacy: .public) predates staged-version reads — showing the version as unknown")
            return nil
        }
        return await call(conn, "stagedSparkleBundleVersions") { proxy, done in
            proxy.stagedSparkleBundleVersions(bundleID: bundleID) { identifier, short, build in
                done(.init(identifier: identifier, shortVersion: short, buildVersion: build))
            }
        }
    }

    /// One call on `conn`, raced against `timeout`. Nil on the deadline, on a
    /// connection error and on a proxy that cannot be made — each logged, so no
    /// failure passes without a trace.
    private func call<T: Sendable>(
        _ conn: NSXPCConnection, _ name: String,
        _ send: @escaping @Sendable (MASHelperProtocol, @escaping @Sendable (T) -> Void) -> Void
    ) async -> T? {
        let timeout = self.timeout
        return await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
            let once = ReplyOnce()
            Task {
                try? await Task.sleep(for: timeout)
                once.fire {
                    Self.log.error("helper \(name, privacy: .public): no reply within \(timeout, privacy: .public)")
                    cont.resume(returning: nil)
                }
            }
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                once.fire {
                    Self.log.error("helper \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    cont.resume(returning: nil)
                }
            }) as? MASHelperProtocol else {
                once.fire {
                    Self.log.error("helper \(name, privacy: .public): no proxy")
                    cont.resume(returning: nil)
                }
                return
            }
            send(proxy) { value in once.fire { cont.resume(returning: value) } }
        }
    }
}

/// Lets exactly one of reply, error and deadline resume a continuation.
private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire(_ body: () -> Void) {
        lock.lock()
        let go = !fired
        fired = true
        lock.unlock()
        if go { body() }
    }
}
