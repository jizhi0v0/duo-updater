import Foundation

// Probe peer for scripts/xpc-peer-probe/run.sh. The same binary is signed twice
// with different identities; which copy runs decides whether it satisfies the
// listener's requirement.
//
// Arguments: <service> <tag> <count> [exec <path> <args...>]
//   Sends <count> one-way `fire` and <count> `ping` messages WITHOUT waiting, so a
//   burst is already queued when the listener first looks at us. With `exec`, it
//   replaces its own image immediately after queueing (same PID — the classic
//   "send then exec something trusted" race); otherwise it waits for the replies
//   or a connection error and prints what it saw.

@objc protocol ProbeProtocol {
    func fire(_ tag: String)
    func ping(_ tag: String, withReply reply: @escaping (String) -> Void)
}

let args = CommandLine.arguments
guard args.count >= 4, let count = Int(args[3]) else {
    FileHandle.standardError.write("usage: peer <service> <tag> <count> [exec path args...]\n".data(using: .utf8)!)
    exit(64)
}
let service = args[1], tag = args[2]
setvbuf(stdout, nil, _IOLBF, 0)
print("PEER start pid=\(getpid()) tag=\(tag)")

let conn = NSXPCConnection(machServiceName: service, options: [])
conn.remoteObjectInterface = NSXPCInterface(with: ProbeProtocol.self)
let done = DispatchSemaphore(value: 0)
conn.invalidationHandler = { print("PEER invalidated tag=\(tag)"); done.signal() }
conn.interruptionHandler = { print("PEER interrupted tag=\(tag)"); done.signal() }
conn.resume()

let replies = DispatchGroup()
let proxy = conn.remoteObjectProxyWithErrorHandler { error in
    print("PEER error tag=\(tag): \((error as NSError).domain) \((error as NSError).code) \(error.localizedDescription)")
    done.signal()
} as! ProbeProtocol
for i in 0..<count {
    proxy.fire("\(tag)-fire-\(i)")
    replies.enter()
    proxy.ping("\(tag)-ping-\(i)") { r in print("PEER reply \(r)"); replies.leave() }
}

if args.count >= 6, args[4] == "exec" {
    // Give the queued messages a moment to be enqueued on the Mach port, then
    // replace the image. execv keeps the PID.
    usleep(20_000)
    print("PEER exec -> \(args[5])")
    let cargs = Array(args[5...]).map { strdup($0) } + [nil]
    execv(args[5], cargs)
    print("PEER execv failed errno=\(errno)")
    exit(1)
}

DispatchQueue.global().async {
    replies.wait()
    print("PEER all replies tag=\(tag)")
    done.signal()
}
if done.wait(timeout: .now() + 8) == .timedOut { print("PEER timeout tag=\(tag)") }
// Let the reply error handler report too: it and the connection handler race.
usleep(300_000)
exit(0)
