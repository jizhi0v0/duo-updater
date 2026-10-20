import Foundation
import Testing

@testable import DuoUpdaterCore

/// TaskExplorer: one stable GitHub rule, plus the 2.x copies still signed as
/// `com.objective-see.TaskExplorer` (the 3.0 builds changed only the case).
@Suite struct TaskExplorerGitHubRuleTests {

    /// A 2.1.0 copy, read off the real 2.1.0 zip, is filed under the 3.x id; a
    /// copy under the old id at 3.0.0 or later is not that rename. Mutation: drop
    /// the TaskExplorer entry from `BundleIDMigration.all` → the first
    /// expectation fails.
    @Test func a2xCopyUnderTheOldCaseIsFiledUnderTheCurrentId() {
        #expect(BundleIDMigration.recipeBundleID(
            for: "com.objective-see.TaskExplorer", installedVersion: "2.1.0")
            == "com.objective-see.taskexplorer")
        #expect(BundleIDMigration.recipeBundleID(
            for: "com.objective-see.TaskExplorer", installedVersion: "3.0.0")
            == "com.objective-see.TaskExplorer")
    }

    /// Every tag published so far reads, and a suffixed tag does not.
    @Test func theVersionPatternReadsEveryTagAndNoSuffixedOne() throws {
        let rule = try #require(GitHubReleaseRegistry.rules.first {
            $0.bundleID == "com.objective-see.taskexplorer"
        })
        for (tag, version) in [("v2.1.0", "2.1.0"), ("v3.0.0", "3.0.0"),
                               ("v3.1.0", "3.1.0"), ("v4.0", "4.0")] {
            #expect(VendorProbeRecipe.extractVersion(
                from: tag, pattern: rule.versionPattern) == version)
        }
        #expect(VendorProbeRecipe.extractVersion(
            from: "v3.2.0-beta.1", pattern: rule.versionPattern) == nil)
    }
}
