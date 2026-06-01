import Testing
import Foundation
@testable import DuoUpdaterCore

/// Lists the apps no current source can resolve, so we can decide how a GitHub
/// Releases source should map them. Read the stderr output.
@Test func listUnknownApps() async {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    let apps = AppScanner().scan()
    let checker = UpdateChecker(sources: [
        MacAppStoreSource(), SparkleAppcastSource(), HomebrewCaskSource()
    ])
    let results = await checker.check(apps)
    let unknown = results.filter { if case .unknown = $0.status { return true } else { return false } }

    log("\n=== \(unknown.count) unknown apps ===")
    for r in unknown {
        log("• \(r.app.name)  | bundle: \(r.app.bundleID ?? "?")  | v\(r.app.shortVersion ?? "?")  | sparkleFeed: \(r.app.sparkleFeedURL?.host ?? "no")")
    }
}
