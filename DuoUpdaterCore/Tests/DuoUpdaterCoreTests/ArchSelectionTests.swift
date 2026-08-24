import Testing
import Foundation
@testable import DuoUpdaterCore

/// Architecture-aware GitHub asset selection. When a release ships both an Intel
/// and an Apple-silicon artifact that match the rule's pattern, the right one for
/// the host must win — and an arch-pinned pattern (the current registry) must keep
/// behaving exactly as before.
struct ArchSelectionTests {

    private func assets(_ names: [String]) -> [(name: String, url: URL, size: Int64?)] {
        names.enumerated().map { index, name in
            (name, URL(string: "https://example.com/\(name)")!, Int64(index))
        }
    }

    @Test func prefersArm64WhenHostIsArm64() {
        let a = assets(["app-1.0-x86_64.dmg", "app-1.0-arm64.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-[0-9.]+-(x86_64|arm64)\.dmg$"#, preferring: .arm64)
        #expect(url?.url.lastPathComponent == "app-1.0-arm64.dmg")
    }

    @Test func prefersX86WhenHostIsIntel() {
        let a = assets(["app-1.0-x86_64.dmg", "app-1.0-arm64.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-[0-9.]+-(x86_64|arm64)\.dmg$"#, preferring: .x86_64)
        #expect(url?.url.lastPathComponent == "app-1.0-x86_64.dmg")
    }

    @Test func neutralAssetPreferredOverForeignArch() {
        // A universal/arch-neutral build is safe for either Mac; never pick the
        // explicitly-Intel one for an arm64 host when a neutral one matches.
        let a = assets(["app-1.0-x86_64.dmg", "app-1.0-universal.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-1\.0-.*\.dmg$"#, preferring: .arm64)
        #expect(url?.url.lastPathComponent == "app-1.0-universal.dmg")
    }

    @Test func architectureMarkersRequireFilenameBoundaries() {
        let a = assets(["IntelliJ-1.0-arm64.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"\.dmg$"#, preferring: .arm64,
            allowingIntelTranslation: false)
        #expect(url?.url.lastPathComponent == "IntelliJ-1.0-arm64.dmg")
    }

    @Test func filenameNamingBothArchitecturesIsUniversal() {
        let a = assets(["app-1.0-arm64-x86_64.dmg"])
        for arch: HostArch in [.arm64, .x86_64] {
            let url = GitHubReleaseRule.installableAsset(
                from: a, matching: #"\.dmg$"#, preferring: arch,
                allowingIntelTranslation: false)
            #expect(url?.url.lastPathComponent == "app-1.0-arm64-x86_64.dmg")
        }
    }

    @Test func fallsBackToForeignArchWhileRosettaCanRunIt() {
        // Only an Intel build exists for this release — better to offer it than
        // nothing, but ONLY while the machine can still run it.
        let a = assets(["app-1.0-x86_64.dmg"])
        let url = GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-1\.0-x86_64\.dmg$"#, preferring: .arm64,
            allowingIntelTranslation: true)
        #expect(url?.url.lastPathComponent == "app-1.0-x86_64.dmg")
    }

    @Test func refusesForeignArchOnceTranslationIsGone() {
        // Same release, same machine, after Rosetta stops covering apps (macOS 28)
        // or where it was never installed: an Intel build would not launch, so the
        // row must stay detection-only rather than swap in a broken bundle.
        let a = assets(["app-1.0-x86_64.dmg"])
        #expect(GitHubReleaseRule.installableAsset(
            from: a, matching: #"app-1\.0-x86_64\.dmg$"#, preferring: .arm64,
            allowingIntelTranslation: false) == nil)
        // A native or universal build in the same release is unaffected by the gate
        // — this is also the architecture-upgrade path for a Mac still running the
        // Intel copy: the arm64 asset wins at step 1, translation never consulted.
        let both = assets(["app-1.0-x86_64.dmg", "app-1.0-arm64.dmg"])
        #expect(GitHubReleaseRule.installableAsset(
            from: both, matching: #"app-1\.0-(x86_64|arm64)\.dmg$"#, preferring: .arm64,
            allowingIntelTranslation: false)?.url.lastPathComponent == "app-1.0-arm64.dmg")
        let universal = assets(["app-1.0-x86_64.dmg", "app-1.0-universal.dmg"])
        #expect(GitHubReleaseRule.installableAsset(
            from: universal, matching: #"app-1\.0-.*\.dmg$"#, preferring: .arm64,
            allowingIntelTranslation: false)?.url.lastPathComponent == "app-1.0-universal.dmg")
    }

    @Test func archPinnedPatternServesItsOwnArchitectureOnly() {
        // The real RustDesk-style anchored pattern matches exactly one asset.
        let a = assets([
            "rustdesk-1.4.6-aarch64.dmg",
            "rustdesk-1.4.6-x86_64.dmg",
        ])
        let pattern = #"^rustdesk-[0-9.]+-aarch64\.dmg$"#
        #expect(GitHubReleaseRule.installableAsset(from: a, matching: pattern, preferring: .arm64)?
            .url.lastPathComponent == "rustdesk-1.4.6-aarch64.dmg")
        // On an Intel Mac that same rule now resolves NOTHING rather than handing
        // over an arm64 bundle. There is no reverse translation — an arm64 build
        // has never run on Intel — so this was an install that could only fail.
        // (Unreachable in the shipped app, which is itself arm64-only, but the
        // registry is public and the semantics should not depend on that.)
        #expect(GitHubReleaseRule.installableAsset(
            from: a, matching: pattern, preferring: .x86_64) == nil)
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
