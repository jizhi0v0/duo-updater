import Testing
import Foundation
@testable import DuoUpdaterCore

@Test func intelliJVersionPatternSurvivesAFourthSegment() {
    // JetBrains shipped "2026.2.0.1" against a pattern pinned to exactly three
    // segments, so it matched nothing and the row fell to "unknown" — a silent
    // failure, since a probe that resolves no version isn't an error anywhere.
    let recipe = VendorProbeRegistry.recipes.first { $0.bundleID == "com.jetbrains.intellij" }
    let pattern = try! #require(recipe?.versionPattern)
    func version(in body: String) -> String? {
        guard let m = body.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(body[m])
        return match.range(of: #"[0-9]{4}(\.[0-9]+)+"#, options: .regularExpression)
            .map { String(match[$0]) }
    }
    #expect(version(in: #"{"version":"2026.2.0.1","build":"262.8665.337"}"#) == "2026.2.0.1")
    #expect(version(in: #"{"version":"2026.1.4"}"#) == "2026.1.4")
    // `majorVersion` is 2-component and must never be what we pick up.
    #expect(version(in: #"{"majorVersion":"2026.2"}"#) == nil)
}
