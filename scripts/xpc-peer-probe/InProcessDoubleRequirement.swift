import Foundation
import Security

// In-process check of the root helper's two requirement layers, for OS versions
// the launchd probe (run.sh) hasn't been run on. NOT shipped.
//
// HelperPeerGate puts the client requirement on the listener
// (setConnectionCodeSigningRequirement) AND on every accepted connection
// (setCodeSigningRequirement). <xpc/connection.h> calls setting a peer
// requirement more than once per connection a programming error; if some libxpc
// copied the listener's requirement onto accepted connections, the second call
// would trap and every helper connection would die. This probe runs that exact
// sequence on an anonymous listener with a self-connection:
//
//   a  listener never-matching                     → ping fails, delegate NOT called
//   b  listener matching + connection matching      → ping replied (must not trap)
//   c  listener matching + connection never-matching → delegate called, no method run
//
// "matching" is this process's own designated requirement, read at run time;
// "never matching" names an invented identifier and team. Each scenario runs in a
// child process of this same executable, so a trap in one is reported as
// "CRASHED signal N" (SIGTRAP is 5) instead of hiding the others. Exit status is 0
// only if all three match their expectations.
//
// Build: swiftc -O scripts/xpc-peer-probe/InProcessDoubleRequirement.swift -o probe
// (Foundation + Security only, Swift 5.9+). Run: ./probe

@objc protocol ZZDoubleRequirementProbe {
    func ping(withReply reply: @escaping (String) -> Void)
}

let neverMatching = "anchor apple generic and identifier \"com.duoupdater.zzfixture.app\" "
    + "and certificate leaf[subject.OU] = \"ZZFIXTURE0\""

final class Counts {
    private let lock = NSLock()
    private var _delegate = 0
    private var _invoked = 0
    func delegateCalled() { lock.lock(); _delegate += 1; lock.unlock() }
    func invoked() { lock.lock(); _invoked += 1; lock.unlock() }
    var snapshot: (delegate: Int, invoked: Int) { lock.lock(); defer { lock.unlock() }; return (_delegate, _invoked) }
}

final class Exported: NSObject, ZZDoubleRequirementProbe {
    let counts: Counts
    init(counts: Counts) { self.counts = counts }
    func ping(withReply reply: @escaping (String) -> Void) {
        counts.invoked()
        reply("pong")
    }
}

final class Delegate: NSObject, NSXPCListenerDelegate {
    let connectionRequirement: String
    let counts: Counts
    init(connectionRequirement: String, counts: Counts) {
        self.connectionRequirement = connectionRequirement
        self.counts = counts
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        counts.delegateCalled()
        // The call under test: a second requirement, this time on the connection.
        conn.setCodeSigningRequirement(connectionRequirement)
        conn.exportedInterface = NSXPCInterface(with: ZZDoubleRequirementProbe.self)
        conn.exportedObject = Exported(counts: counts)
        conn.resume()
        return true
    }
}

final class Once {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock(); let go = !done; done = true; lock.unlock()
        if go { body() }
    }
}

func ownDesignatedRequirement() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
          let requirement else { return nil }
    var text: CFString?
    guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
    return text as String
}

func runScenario(_ name: String) -> Int32 {
    setvbuf(stdout, nil, _IOLBF, 0)
    guard let own = ownDesignatedRequirement() else {
        print("SUMMARY \(name): ERROR could not read this process's designated requirement")
        return 2
    }
    let table: [String: (listener: String, connection: String, expectation: String)] = [
        "a": (neverMatching, neverMatching, "failed delegate=0 invoked=0"),
        "b": (own, own, "replied delegate=1 invoked=1"),
        "c": (own, neverMatching, "failed delegate=1 invoked=0"),
    ]
    guard let row = table[name] else {
        print("SUMMARY \(name): ERROR unknown scenario")
        return 2
    }
    let listenerRequirement = row.listener
    let connectionRequirement = row.connection
    let expectation = row.expectation
    print("SCENARIO \(name) START pid=\(getpid()) own-requirement=\(own)")

    let counts = Counts()
    let listener = NSXPCListener.anonymous()
    listener.setConnectionCodeSigningRequirement(listenerRequirement)
    let delegate = Delegate(connectionRequirement: connectionRequirement, counts: counts)
    listener.delegate = delegate
    listener.resume()

    let conn = NSXPCConnection(listenerEndpoint: listener.endpoint)
    conn.remoteObjectInterface = NSXPCInterface(with: ZZDoubleRequirementProbe.self)
    conn.resume()

    let done = DispatchSemaphore(value: 0)
    let once = Once()
    let outcomeLock = NSLock()
    var outcome = "timeout"
    func finish(_ value: String) {
        once.run {
            outcomeLock.lock(); outcome = value; outcomeLock.unlock()
            done.signal()
        }
    }
    let proxy = conn.remoteObjectProxyWithErrorHandler { error in
        let e = error as NSError
        finish("failed(\(e.domain) \(e.code))")
    } as? ZZDoubleRequirementProbe
    if let proxy {
        proxy.ping { _ in finish("replied") }
    } else {
        finish("failed(no proxy)")
    }
    _ = done.wait(timeout: .now() + 15)
    // Let anything still in flight on the listener side land before counting.
    Thread.sleep(forTimeInterval: 0.5)
    conn.invalidate()
    listener.invalidate()
    withExtendedLifetime(delegate) {}

    outcomeLock.lock(); let result = outcome; outcomeLock.unlock()
    let (d, i) = counts.snapshot
    let shortOutcome = result.hasPrefix("failed") ? "failed" : result
    let observed = "\(shortOutcome) delegate=\(d) invoked=\(i)"
    let pass = observed == expectation
    print("SUMMARY \(name): \(pass ? "PASS" : "FAIL") observed=[\(result) delegate=\(d) invoked=\(i)] expected=[\(expectation)]")
    return pass ? 0 : 1
}

let args = CommandLine.arguments
if args.count > 1 {
    exit(runScenario(args[1]))
}

setvbuf(stdout, nil, _IOLBF, 0)
let info = ProcessInfo.processInfo
print("PROBE host: \(info.operatingSystemVersionString)")
guard let me = Bundle.main.executableURL else {
    print("PROBE ERROR: no executable URL")
    exit(2)
}
var allPassed = true
for scenario in ["a", "b", "c"] {
    let child = Process()
    child.executableURL = me
    child.arguments = [scenario]
    do {
        try child.run()
    } catch {
        print("SUMMARY \(scenario): ERROR could not start child: \(error)")
        allPassed = false
        continue
    }
    child.waitUntilExit()
    switch child.terminationReason {
    case .uncaughtSignal:
        print("SUMMARY \(scenario): CRASHED signal \(child.terminationStatus) (SIGTRAP=5 is what an XPC API-misuse trap raises)")
        allPassed = false
    case .exit:
        print("CHILD \(scenario) exit status \(child.terminationStatus)")
        if child.terminationStatus != 0 { allPassed = false }
    @unknown default:
        print("CHILD \(scenario) ended for an unknown reason, status \(child.terminationStatus)")
        allPassed = false
    }
}
print("OVERALL: \(allPassed ? "PASS" : "FAIL")")
exit(allPassed ? 0 : 1)
