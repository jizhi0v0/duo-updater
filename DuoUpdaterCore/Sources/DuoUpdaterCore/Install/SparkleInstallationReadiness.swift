import Foundation

/// Sparkle's read-only status service. A live progress agent and a readable new
/// Info.plist can appear while extraction/validation is still running.
///
/// In Sparkle 2.9.1, SPUInstallerDriver sends SPUSentUpdateAppcastItemData only
/// after SPUInstallationFinishedStage1; StatusInfo then publishes this archive.
/// Before that, quitting the host aborts AppInstaller if _willCompleteInstallation
/// is still false. We need the publication, not the archive's contents, so no
/// vendor classes are decoded or linked into Core/CLI.
struct SparkleInstallationReadiness: Sendable {
    let connect: @Sendable () -> NSXPCConnection
    // Sparkle's own SPUProbeInstallStatus deadline. Injected so tests can fire
    // the deadline after the request arrives, rather than time the shared pool.
    var waitForTimeout: @Sendable () async -> Void = {
        try? await Task.sleep(for: .seconds(7)) // cancel-ok: one-shot deadline, no loop
    }

    static func isReady(bundleID: String) async -> Bool {
        // SPUMessageTypes: append -spks, then keep the last 127 characters.
        let service = String((bundleID + "-spks").suffix(127))
        return await Self(connect: { NSXPCConnection(machServiceName: service) }).read()
    }

    func read() async -> Bool {
        let connection = Connection(connect())
        connection.value.remoteObjectInterface = NSXPCInterface(with: SparkleStatusInfoProtocol.self)
        defer { connection.value.invalidate() }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await Self.query(connection) }
            group.addTask { await waitForTimeout(); return false }
            let ready = await group.next() ?? false
            connection.value.invalidate()
            group.cancelAll()
            return ready
        }
    }

    private static func query(_ shared: Connection) async -> Bool {
        let connection = shared.value
        return await withCheckedContinuation { continuation in
            let once = SparkleReadinessReply()
            let finish: @Sendable (Bool) -> Void = { ready in
                once.fire { continuation.resume(returning: ready) }
            }
            connection.invalidationHandler = { finish(false) }
            connection.interruptionHandler = { finish(false) }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in finish(false) })
                as? SparkleStatusInfoProtocol else { finish(false); return }
            proxy.probeStatusInfo { data in finish(data.map { !$0.isEmpty } ?? false) }
        }
    }

    /// NSXPCConnection supports invalidation from the deadline's task while its
    /// reply/error handlers run on Foundation's queue. Configure before resume.
    private final class Connection: @unchecked Sendable {
        let value: NSXPCConnection
        init(_ value: NSXPCConnection) { self.value = value }
    }
}

@objc protocol SparkleStatusInfoProtocol {
    @objc(probeStatusInfoWithReply:)
    func probeStatusInfo(_ reply: @escaping (Data?) -> Void)
}

private final class SparkleReadinessReply: @unchecked Sendable {
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
