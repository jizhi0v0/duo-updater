import Foundation
import DuoUpdaterCore
let mode = CommandLine.arguments[1]
let bundle = URL(fileURLWithPath: "/Applications/VMPal.app")
let processes = NestedAppGuard.liveProcesses()
let own = processes.filter { ($0.executablePath ?? "").hasPrefix(bundle.path + "/") }
let relays = own.filter { $0.arguments?.contains("--mcp") == true }
let machines = own.filter { $0.arguments?.contains("--machine") == true }
precondition(!relays.isEmpty, "Must exercise real per-machine MCP relay processes")
let blockers = NestedAppGuard.blockers(bundlePath: bundle.path, processes: processes)
precondition(!blockers.contains { b in relays.contains { $0.pid == b.pid } })
var refused = false
var message = ""
do { try NestedAppGuard.check(bundle, appName: "VMPal", processes: { processes }) }
catch { refused = true; message = error.localizedDescription }
if mode == "running" {
 precondition(!machines.isEmpty)
 precondition(machines.allSatisfy { p in blockers.contains { $0.pid == p.pid } })
 precondition(refused)
} else {
 precondition(machines.isEmpty)
 precondition(blockers.isEmpty && !refused)
}
let result: [String: Any] = ["mode":mode,"date":ISO8601DateFormatter().string(from:Date()),"relays":relays.map(\.pid),"machinePIDs":machines.map(\.pid),"blockers":blockers.map { ["pid":$0.pid,"name":$0.name,"vmName":$0.vmName ?? ""] as [String:Any] },"refused":refused,"message":message]
print(String(data:try JSONSerialization.data(withJSONObject: result,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
