import Foundation
import Synchronization
import Testing
@testable import DuoUpdaterCore

@Suite(.timeLimit(.minutes(1)))
struct SparkleInstallationReadinessTests {
    /// Exercises the actual XPC selector/data bridge, not a mocked Bool. Sparkle
    /// returns nil while preparing and publishes an archive after stage 1.
    @Test(arguments: [nil, Data(), Data([1, 2, 3])] as [Data?])
    func onlyPublishedNonemptyInfoIsReady(_ info: Data?) async {
        let fixture = Fixture(info: info)
        let ready = await fixture.reader.read()
        #expect(fixture.server.calls.withLock { $0 } == 1)
        #expect(ready == (info.map { !$0.isEmpty } ?? false))
    }

    @Test func aStatusServiceThatDoesNotReplyCannotAuthorizeQuit() async {
        let fixture = Fixture(info: Data([1]), silent: true)
        #expect(await fixture.reader.read() == false)
        #expect(fixture.server.calls.withLock { $0 } == 1)
    }

    @Test func aMissingServiceCannotAuthorizeQuit() async {
        let reader = SparkleInstallationReadiness(connect: {
            NSXPCConnection(machServiceName: "io.duoupdater.zzfixture.missing-status")
        })
        #expect(await reader.read() == false)
    }

    private final class Fixture: @unchecked Sendable {
        let listener = NSXPCListener.anonymous()
        let server: Server
        let delegate: Listener
        let deadline = AsyncStream<Void>.makeStream()
        init(info: Data?, silent: Bool = false) {
            let deadline = deadline.continuation
            server = Server(info: info, silent: silent, received: {
                if silent { deadline.yield(()) }
            })
            delegate = Listener(server: server)
            listener.delegate = delegate
            listener.resume()
        }
        deinit { listener.invalidate() }
        var reader: SparkleInstallationReadiness {
            var reader = SparkleInstallationReadiness(connect: { [self] in
                NSXPCConnection(listenerEndpoint: listener.endpoint)
            })
            let stream = deadline.stream
            reader.waitForTimeout = { for await _ in stream { return } }
            return reader
        }
    }

    private final class Listener: NSObject, NSXPCListenerDelegate {
        let server: Server
        init(server: Server) { self.server = server }
        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            connection.exportedInterface = NSXPCInterface(with: SparkleStatusInfoProtocol.self)
            connection.exportedObject = server
            connection.resume()
            return true
        }
    }

    private final class Server: NSObject, SparkleStatusInfoProtocol {
        let info: Data?
        let silent: Bool
        let received: () -> Void
        let calls = Mutex(0)
        init(info: Data?, silent: Bool, received: @escaping () -> Void) {
            self.info = info; self.silent = silent; self.received = received
        }
        func probeStatusInfo(_ reply: @escaping (Data?) -> Void) {
            calls.withLock { $0 += 1 }
            received()
            if !silent { reply(info) }
        }
    }
}
