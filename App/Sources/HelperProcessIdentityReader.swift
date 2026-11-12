import Foundation

/// A fresh, bounded read for an executable ordinary process inspection could
/// not identify. No service is stopped or registered. Missing, old or silent
/// helpers leave the process unknown and automatic installation deferred.
struct HelperProcessIdentityReader: Sendable {
    let connect: @Sendable () -> NSXPCConnection?
    var timeout: DispatchTimeInterval = .seconds(2)
    var identity: @Sendable (Int32) -> ProcessExecutablePath.Identity? = ProcessExecutablePath.identity

    /// Synchronous for the final exchange guard. Call off the main actor and
    /// cooperative pool; the scheduler and AutomaticInstall.checkAsync do so.
    func read(pid: Int32) -> String? {
        guard let expected = identity(pid), let connection = connect() else { return nil }
        connection.remoteObjectInterface = NSXPCInterface(with: MASHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let version: String? = call(connection) { proxy, done in proxy.helperVersion(withReply: done) }
        guard let version, HelperProtocolRevision.supportsProcessExecutablePath(versionReply: version)
        else { return nil }
        let path: String? = call(connection) { proxy, done in
            proxy.processExecutablePath(pid: pid, startedSeconds: expected.seconds,
                startedMicroseconds: expected.microseconds, withReply: done)
        }
        guard identity(pid) == expected, let path, path.hasPrefix("/"), !path.contains("\0")
        else { return nil }
        return path
    }

    private func call(_ connection: NSXPCConnection,
                      _ send: (MASHelperProtocol, @escaping @Sendable (String?) -> Void) -> Void) -> String? {
        let reply = Reply()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in reply.finish(nil) })
                as? MASHelperProtocol else { return nil }
        send(proxy) { reply.finish($0) }
        guard reply.ready.wait(timeout: .now() + timeout) == .success else { return nil }
        return reply.result
    }

    private final class Reply: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var finished = false
        private var value: String?
        var result: String? { lock.withLock { value } }
        func finish(_ value: String?) {
            lock.withLock {
                guard !finished else { return }
                finished = true
                self.value = value
                ready.signal()
            }
        }
    }
}
