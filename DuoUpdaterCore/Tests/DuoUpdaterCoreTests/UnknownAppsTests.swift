import Testing
import Foundation
@testable import DuoUpdaterCore

/// Diagnostic: lists what the FULL source stack still can't resolve, split into
/// genuinely-unknown vs App Store-managed. Read the stderr output.
@Test func listUnknownApps() async {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    let apps = AppScanner().scan()
    let checker = UpdateChecker(sources: [
        MacAppStoreSource(), SparkleAppcastSource(), HomebrewCaskSource(),
        GitHubReleasesSource(token: GitHubToken.resolve()), VendorProbeSource()
    ], toolbox: ToolboxSource())
    let results = await checker.check(apps)

    log("\n=== Toolbox-managed (now version-checked) ===")
    for r in results where r.remote?.sourceName == "Toolbox" {
        let s: String
        switch r.status {
        case .updateAvailable(let v): s = "⬆️ \(r.app.shortVersion ?? "?") → \(v)"
        case .upToDate: s = "✓ up to date"
        default: s = "\(r.status)"
        }
        log("• \(r.app.name)  | \(s)  | \(r.app.path.lastPathComponent)")
    }
    let unknown = results.filter { if case .unknown = $0.status { return true } else { return false } }
    let managed = results.filter { if case .appStoreManaged = $0.status { return true } else { return false } }
    let toolbox = results.filter { if case .toolboxManaged = $0.status { return true } else { return false } }

    log("\n=== \(unknown.count) genuinely-unknown apps ===")
    for r in unknown {
        log("• \(r.app.name)  | bundle: \(r.app.bundleID ?? "?")  | v\(r.app.shortVersion ?? "?")")
    }
    log("\n=== \(managed.count) App Store-managed apps ===")
    for r in managed {
        log("• \(r.app.name)  | bundle: \(r.app.bundleID ?? "?")")
    }
    log("\n=== \(toolbox.count) Toolbox-managed apps ===")
    for r in toolbox {
        log("• \(r.app.name)  | bundle: \(r.app.bundleID ?? "?")  | v\(r.app.shortVersion ?? "?")  | \(r.app.path.lastPathComponent)")
    }
}
