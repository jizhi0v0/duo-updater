import DuoUpdaterCore
import Foundation
import Testing

/// The app's side of the staged-version read (`HelperStagedVersionReader`,
/// #588), over real XPC in one process: an anonymous listener exporting a fake
/// helper, and the reader connecting to its endpoint. What this cannot cover is
/// the production connection — the Mach service, the privileged flag and the
/// code-signing pin (`HelperStagedVersionReader.live`) — which needs the
/// installed daemon; that is the real-machine step.
///
/// Each case names the mutation it was seen to fail under.
@Suite(.timeLimit(.minutes(1)))
struct HelperStagedVersionReaderTests {

    static let bundleID = "com.zzfixture.staged"

    /// A current helper: the reply crosses XPC intact.
    @Test func aCurrentHelperIsAsked() async {
        let fake = ZZFakeHelper(versionReply: HelperProtocolRevision.versionReply(bundleVersion: "121"),
                                fields: (Self.bundleID, "1.102.4", "101.102.4"))
        let read = await Self.reader(serving: fake).read(bundleID: Self.bundleID)
        #expect(read == .init(identifier: Self.bundleID, shortVersion: "1.102.4", buildVersion: "101.102.4"))
        #expect(fake.askedFor == [Self.bundleID])
    }

    /// The helper's "nothing" is three nils, and NSXPC carries nil strings in a
    /// reply rather than failing the call.
    @Test func aCurrentHelperWithNothingStagedAnswersNils() async {
        let fake = ZZFakeHelper(versionReply: HelperProtocolRevision.versionReply(bundleVersion: "121"),
                                fields: (nil, nil, nil))
        let read = await Self.reader(serving: fake).read(bundleID: Self.bundleID)
        #expect(read == .init(identifier: nil, shortVersion: nil, buildVersion: nil))
    }

    /// Constraint 6: a helper from before the selector (its `helperVersion`
    /// reply is the bare bundle version) is treated as not enabled — the read is
    /// never sent, and the answer is nil.
    ///
    /// Mutation: drop the `supportsStagedSparkleBundleVersions` guard in `read`
    /// — the fake is then asked and answers.
    @Test func anOlderHelperIsNeverAskedTheNewQuestion() async {
        let fake = ZZFakeHelper(versionReply: "121", fields: (Self.bundleID, "1.102.4", "101.102.4"))
        let read = await Self.reader(serving: fake).read(bundleID: Self.bundleID)
        #expect(read == nil)
        #expect(fake.askedFor.isEmpty)
    }

    /// Mutation: make `revision(ofVersionReply:)` return `current` when there is
    /// no marker — a revision-1 helper then reads as able.
    @Test func revisionsAreReadFromTheVersionReply() {
        #expect(HelperProtocolRevision.revision(ofVersionReply: "121") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "0") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "121 protocol/") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "121 protocol/x") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "121 protocol/0") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "121 protocol/99999") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "121 protocol/２") == 1)
        #expect(HelperProtocolRevision.revision(ofVersionReply: "121 protocol/3") == 3)
        let current = HelperProtocolRevision.versionReply(bundleVersion: "121")
        #expect(current.hasPrefix("121"))
        #expect(HelperProtocolRevision.revision(ofVersionReply: current) == HelperProtocolRevision.current)
        #expect(HelperProtocolRevision.supportsStagedSparkleBundleVersions(versionReply: current))
        #expect(!HelperProtocolRevision.supportsStagedSparkleBundleVersions(versionReply: "121"))
    }

    /// A helper that accepts the connection and never answers — the state
    /// `HelperShellRunner.ensureReachable` documents after an in-place update.
    ///
    /// Mutation: delete the deadline `Task` in `call` — the read never returns
    /// and the suite's time limit fails it.
    @Test func aSilentHelperTimesOut() async {
        let fake = ZZFakeHelper(versionReply: nil, fields: (nil, nil, nil))
        var reader = Self.reader(serving: fake)
        reader.timeout = .milliseconds(300)
        #expect(await reader.read(bundleID: Self.bundleID) == nil)
    }

    /// No connection (helper not enabled, or no requirement to pin it to): nil,
    /// without touching anything.
    @Test func noConnectionIsNoRead() async {
        #expect(await HelperStagedVersionReader(connect: { nil }).read(bundleID: Self.bundleID) == nil)
    }

    /// A connection the other side refuses — what a peer failing the helper's
    /// code-signing gate gets (4097, see `HelperPeerGate`): the error handler
    /// answers nil at once instead of the call waiting out the deadline.
    ///
    /// (A listener that was simply invalidated is not this case: measured here,
    /// a call to its endpoint got neither a reply nor an error, and only the
    /// deadline ended it — which is what `aSilentHelperTimesOut` covers.)
    ///
    /// Mutation: make the error handler a no-op — the read then waits the full
    /// 30 s deadline.
    @Test func aRefusedConnectionIsNoRead() async {
        let listener = NSXPCListener.anonymous()
        let delegate = ZZRefusingDelegate()
        listener.delegate = delegate
        listener.resume()
        let endpoint = EndpointBox(listener.endpoint, retaining: [listener, delegate])
        var reader = HelperStagedVersionReader(connect: { NSXPCConnection(listenerEndpoint: endpoint.value) })
        reader.timeout = .seconds(30)
        let start = ContinuousClock.now
        #expect(await reader.read(bundleID: Self.bundleID) == nil)
        #expect(ContinuousClock.now - start < .seconds(20))
    }

    // MARK: fixtures

    /// Keeps the listener and its delegate alive for the reader's lifetime.
    static func reader(serving fake: ZZFakeHelper) -> HelperStagedVersionReader {
        let listener = NSXPCListener.anonymous()
        let delegate = ZZExportingDelegate(exported: fake)
        listener.delegate = delegate
        listener.resume()
        let box = EndpointBox(listener.endpoint, retaining: [listener, delegate])
        return HelperStagedVersionReader(connect: { NSXPCConnection(listenerEndpoint: box.value) })
    }
}

final class EndpointBox: @unchecked Sendable {
    let value: NSXPCListenerEndpoint
    private let retained: [AnyObject]
    init(_ value: NSXPCListenerEndpoint, retaining: [AnyObject] = []) {
        self.value = value
        self.retained = retaining
    }
}

final class ZZExportingDelegate: NSObject, NSXPCListenerDelegate {
    let exported: ZZFakeHelper
    init(exported: ZZFakeHelper) { self.exported = exported }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MASHelperProtocol.self)
        connection.exportedObject = exported
        connection.resume()
        return true
    }
}

final class ZZRefusingDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        false
    }
}

/// A helper that answers whatever it is told to. `versionReply == nil` never
/// replies at all.
final class ZZFakeHelper: NSObject, MASHelperProtocol, @unchecked Sendable {
    private let versionReply: String?
    private let fields: (String?, String?, String?)
    private let lock = NSLock()
    private var _askedFor: [String] = []
    var askedFor: [String] { lock.lock(); defer { lock.unlock() }; return _askedFor }

    init(versionReply: String?, fields: (String?, String?, String?)) {
        self.versionReply = versionReply
        self.fields = fields
    }

    func installMASApp(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String,
                       withReply reply: @escaping (Int32, String?) -> Void) {
        reply(-1, "ZZFixture")
    }

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        if let versionReply { reply(versionReply) }
    }

    func stagedSparkleBundleVersions(bundleID: String,
                                     withReply reply: @escaping (String?, String?, String?) -> Void) {
        lock.lock(); _askedFor.append(bundleID); lock.unlock()
        reply(fields.0, fields.1, fields.2)
    }
}
