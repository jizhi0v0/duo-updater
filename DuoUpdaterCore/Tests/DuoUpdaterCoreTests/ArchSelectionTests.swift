import Testing
import Foundation
@testable import DuoUpdaterCore

/// Architecture-aware GitHub asset selection. When a release ships both an Intel
/// and an Apple-silicon artifact that match the rule's pattern, the right one for
/// the host must win — and an arch-pinned pattern (the current registry) must keep
/// behaving exactly as before.
struct ArchSelectionTests {

    private func assets(_ names: [String]) -> [(name: String, url: URL)] {
        names.map { ($0, URL(string: "https://example.com/\($0)")!) }
    }

    @Test func prefersArm64WhenHostIsArm64() {
        let a = assets(["app-1.0-x86_64.dmg", "app-1.0-arm64.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-[0-9.]+-(x86_64|arm64)\.dmg$"#, preferring: .arm64)
        #expect(url?.lastPathComponent == "app-1.0-arm64.dmg")
    }

    @Test func prefersX86WhenHostIsIntel() {
        let a = assets(["app-1.0-x86_64.dmg", "app-1.0-arm64.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-[0-9.]+-(x86_64|arm64)\.dmg$"#, preferring: .x86_64)
        #expect(url?.lastPathComponent == "app-1.0-x86_64.dmg")
    }

    @Test func neutralAssetPreferredOverForeignArch() {
        // A universal/arch-neutral build is safe for either Mac; never pick the
        // explicitly-Intel one for an arm64 host when a neutral one matches.
        let a = assets(["app-1.0-x86_64.dmg", "app-1.0-universal.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-1\.0-.*\.dmg$"#, preferring: .arm64)
        #expect(url?.lastPathComponent == "app-1.0-universal.dmg")
    }

    @Test func fallsBackToForeignArchWhenNothingBetter() {
        // Only an Intel build exists for this release — better to offer it than
        // nothing (the host can run it under Rosetta).
        let a = assets(["app-1.0-x86_64.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-1\.0-x86_64\.dmg$"#, preferring: .arm64)
        #expect(url?.lastPathComponent == "app-1.0-x86_64.dmg")
    }

    @Test func archPinnedPatternIsUnaffected() {
        // The real RustDesk-style anchored pattern matches exactly one asset, so
        // arch preference can't change the outcome on either host.
        let a = assets([
            "rustdesk-1.4.6-aarch64.dmg",
            "rustdesk-1.4.6-x86_64.dmg",
        ])
        let pattern = #"^rustdesk-[0-9.]+-aarch64\.dmg$"#
        #expect(GitHubReleaseRule.installableAsset(from: a, matching: pattern, preferring: .arm64)?
            .lastPathComponent == "rustdesk-1.4.6-aarch64.dmg")
        #expect(GitHubReleaseRule.installableAsset(from: a, matching: pattern, preferring: .x86_64)?
            .lastPathComponent == "rustdesk-1.4.6-aarch64.dmg")
    }

    @Test func noMatchStillReturnsNil() {
        let a = assets(["app-1.0-linux.AppImage"])
        #expect(GitHubReleaseRule.installableAsset(
            from: a, matching: #"\.dmg$"#, preferring: .arm64) == nil)
    }

    @Test func hostArchResolvesToAKnownValue() {
        // Whatever this test machine is, detection must land on one of the two.
        #expect(HostArch.current == .arm64 || HostArch.current == .x86_64)
        #expect(HostArch.arm64.foreignTokens == HostArch.x86_64.assetTokens)
        #expect(HostArch.x86_64.foreignTokens == HostArch.arm64.assetTokens)
    }
}
