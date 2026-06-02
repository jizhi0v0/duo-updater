import Testing
import Foundation
@testable import DuoUpdaterCore

/// Live smoke test against ALL of the machine's real apps through every source
/// (App Store → Sparkle → Homebrew). Not a unit test — exercises the full
/// network + parse + compare path and prints a summary to stderr.
@Test func liveFullCheckSmoke() async {
    let apps = AppScanner().scan()
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    log("\n=== Full check: \(apps.count) apps ===")
    let checker = UpdateChecker(sources: [
        MacAppStoreSource(),
        SparkleAppcastSource(),
        HomebrewCaskSource(),
        GitHubReleasesSource(token: GitHubToken.resolve()),
        VendorProbeSource()
    ])
    let results = await checker.check(apps)

    var updates = 0, upToDate = 0, unknown = 0, errors = 0
    var bySource: [String: Int] = [:]
    for r in results {
        if let s = r.remote?.sourceName.split(separator: " ").first.map(String.init) {
            bySource[s, default: 0] += 1
        }
        switch r.status {
        case .updateAvailable(let latest):
            updates += 1
            log("⬆️  \(r.app.name): \(r.app.shortVersion ?? "?") → \(latest)  [\(r.remote?.sourceName ?? "?")]")
        case .upToDate: upToDate += 1
        case .unknown: unknown += 1
        case .appStoreManaged: unknown += 1
        case .toolboxManaged: unknown += 1
        case .testFlightManaged: unknown += 1
        case .error(let e): errors += 1; log("⚠️  \(r.app.name): \(e)")
        }
    }
    log("--- updates: \(updates), upToDate: \(upToDate), unknown: \(unknown), errors: \(errors) ---")
    log("--- resolved by source: \(bySource) ---")
}
