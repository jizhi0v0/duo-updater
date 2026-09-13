import Foundation

// Probe listener for scripts/xpc-peer-probe/run.sh. NOT shipped, not the helper.
//
// Runs as a throwaway launchd *user agent* hosting an `NSXPCListener(machServiceName:)`
// — the same initializer the real helper uses — so a separately built, separately
// signed peer process reaches it over a real Mach service lookup. Every observable
// event is appended to a log file the script reads back:
//
//   DELEGATE  the listener delegate was consulted for a new connection
//   INVOKED   a method on the exported object actually ran
//   OPENED / CLOSED   the IdleExit-shaped counter moved (accepted connections only)
//
// Arguments: <log path> <mode> [requirement]
//   listener-req   listener.setConnectionCodeSigningRequirement(req); delegate accepts
//   conn-req       no listener requirement; delegate sets conn.setCodeSigningRequirement(req)
//   both-req       listener requirement AND the same requirement again on the connection
//   none           no requirement at all (control: shows the peer can reach us)
//   delegate-reject  no requirement; the delegate returns false (what the old
//                  audit-token gate did) — for comparing what a rejected client sees

@objc protocol ProbeProtocol {
    func fire(_ tag: String)
    func ping(_ tag: String, withReply reply: @escaping (String) -> Void)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: listener <log> <mode> [requirement]\n".data(using: .utf8)!)
    exit(64)
}
let logPath = args[1]
let mode = args[2]
let requirement = args.count > 3 ? args[3] : ""
let serviceName = ProcessInfo.processInfo.environment["PROBE_SERVICE"] ?? "missing"

let logLock = NSLock()
func log(_ line: String) {
    logLock.lock(); defer { logLock.unlock() }
    let stamped = "\(Date().timeIntervalSince1970) \(line)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(stamped.data(using: .utf8)!); try? h.close()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: stamped.data(using: .utf8))
    }
}

final class Exported: NSObject, ProbeProtocol {
    let connPID: pid_t
    init(connPID: pid_t) { self.connPID = connPID }
    func fire(_ tag: String) {
        let c = NSXPCConnection.current()
        log("INVOKED fire tag=\(tag) acceptPID=\(connPID) currentPID=\(c?.processIdentifier ?? -1) euid=\(c?.effectiveUserIdentifier ?? 9999)")
    }
    func ping(_ tag: String, withReply reply: @escaping (String) -> Void) {
        let c = NSXPCConnection.current()
        log("INVOKED ping tag=\(tag) acceptPID=\(connPID) currentPID=\(c?.processIdentifier ?? -1) euid=\(c?.effectiveUserIdentifier ?? 9999)")
        reply("pong \(tag)")
    }
}

let counterLock = NSLock()
nonisolated(unsafe) var live = 0

final class Delegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        log("DELEGATE pid=\(conn.processIdentifier) euid=\(conn.effectiveUserIdentifier) egid=\(conn.effectiveGroupIdentifier)")
        if mode == "delegate-reject" { log("REJECTED by delegate"); return false }
        if mode == "conn-req" || mode == "both-req" {
            conn.setCodeSigningRequirement(requirement)
            log("CONNREQ set on pid=\(conn.processIdentifier)")
        }
        conn.exportedInterface = NSXPCInterface(with: ProbeProtocol.self)
        conn.exportedObject = Exported(connPID: conn.processIdentifier)
        let pid = conn.processIdentifier
        counterLock.lock(); live += 1; let n = live; counterLock.unlock()
        log("OPENED pid=\(pid) live=\(n)")
        conn.invalidationHandler = {
            counterLock.lock(); live -= 1; let n = live; counterLock.unlock()
            log("CLOSED pid=\(pid) live=\(n)")
        }
        conn.interruptionHandler = { log("INTERRUPTED pid=\(pid)") }
        conn.resume()
        return true
    }
}

let delegate = Delegate()
let listener = NSXPCListener(machServiceName: serviceName)
if mode == "listener-req" || mode == "both-req" {
    listener.setConnectionCodeSigningRequirement(requirement)
}
listener.delegate = delegate
listener.resume()
log("LISTENING service=\(serviceName) mode=\(mode) requirement=\(requirement) pid=\(getpid())")
RunLoop.main.run()
