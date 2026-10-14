import Testing
import Foundation
@testable import DuoUpdaterCore

/// Future-input probe. For each run's (versionPattern, installAssetPattern), ask
/// the PRODUCTION matchers what they do with tags and asset names that don't
/// exist yet: an rc/beta that the vendor forgot to flag as a prerelease, a
/// four-part version, a tag without `v`. Opt-in: needs BENCH_PROBE_IN/OUT.
struct ZZPatternProbe {
    struct Item: Decodable {
        let run: String
        let versionPattern: String
        let installAssetPattern: String?
        let tags: [String]
        let assets: [String]
    }

    @Test func probe() throws {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["BENCH_PROBE_IN"], let outPath = env["BENCH_PROBE_OUT"] else { return }
        let items = try JSONDecoder().decode([Item].self, from: Data(contentsOf: URL(fileURLWithPath: inPath)))
        var out: [[String: Any]] = []
        for item in items {
            var tags: [String: String] = [:]
            for t in item.tags {
                tags[t] = VendorProbeRecipe.extractVersion(from: t, pattern: item.versionPattern) ?? "<no match>"
            }
            var assets: [String: String] = [:]
            if let pattern = item.installAssetPattern {
                for a in item.assets {
                    let one = [(name: a, url: URL(string: "https://example.invalid/\(a)")!, size: Int64?.none)]
                    let picked = GitHubReleaseRule.installableAsset(
                        from: one, matching: pattern, preferring: .arm64, allowingIntelTranslation: true)
                    assets[a] = picked == nil ? "rejected" : "accepted"
                }
            }
            out.append(["run": item.run, "tags": tags, "assets": assets])
        }
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath))
    }
}
