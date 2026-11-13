import Foundation
import Testing
@testable import DuoUpdaterCore
struct LocalPR1987LiveTests {
 @Test func installedProcesses() throws {
  let processes = NestedAppGuard.liveProcesses(includeUninspectable: true)
  let app = URL(fileURLWithPath: "/Applications/Pearcleaner.app")
  let nested = processes.filter { ($0.executablePath ?? "").hasPrefix(app.path + "/") }
  #expect(!nested.isEmpty)
  #expect(nested.contains { ($0.executablePath ?? "").contains(".appex/") })
  let main = AutomaticInstall.runningMainProcesses(at: app, processes: processes)
  #expect(main.isEmpty)
  try AutomaticInstall.checkProcesses(at: app, processes: processes, allowRunningApp: false)
  let running = URL(fileURLWithPath: "/Applications/DuoUpdater.app")
  #expect(!AutomaticInstall.runningMainProcesses(at: running, processes: processes).isEmpty)
  #expect(throws: AutomaticInstall.Deferred.self) {
   try AutomaticInstall.checkProcesses(at: running, processes: processes, allowRunningApp: false)
  }
  print("LIVE helper-only Pearcleaner PIDs=\(nested.map(\.pid)) main=[]: allowed; DuoUpdater main-running: deferred")
 }
}
