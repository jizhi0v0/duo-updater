import Testing
import Foundation
@testable import DuoUpdaterCore

// MARK: - Version extraction (the fragile, format-specific core)

@Test func extractsVersionFromDmgFilename() {
    let v = VendorProbeRecipe.extractVersion(
        from: "ToDesk_4.7.6.0.dmg",
        pattern: #"_(\d+(?:\.\d+){1,3})\.dmg$"#
    )
    #expect(v == "4.7.6.0")
}

@Test func extractsClaudeVersionFromRedirectLocationPath() {
    // Claude's `dmg/latest/redirect` 307s here; the version is a path segment,
    // not the filename (the filename is a content hash). The pattern must read
    // the directory between `/darwin/universal/` and the next slash.
    let location =
        "https://downloads.claude.ai/releases/darwin/universal/1.9659.4/Claude-8cc65547f75f6ddd5b8ff0e04d3a2c450a970ccc.dmg"
    let v = VendorProbeRecipe.extractVersion(
        from: location,
        pattern: #"/darwin/universal/([0-9]+\.[0-9]+\.[0-9]+)/"#
    )
    #expect(v == "1.9659.4")
}

@Test func extractsVersionWithGenericPattern() {
    // No capture group → whole match is used.
    let v = VendorProbeRecipe.extractVersion(
        from: "App-2.10.3.pkg",
        pattern: #"\d+\.\d+\.\d+"#
    )
    #expect(v == "2.10.3")
}

@Test func extractsVersionFromJSONBody() {
    let body = #"{"platform":"mac","latest":"3.2.1","url":"https://x/y.dmg"}"#
    let v = VendorProbeRecipe.extractVersion(
        from: body,
        pattern: #""latest"\s*:\s*"([\d.]+)""#
    )
    #expect(v == "3.2.1")
}

@Test func returnsNilWhenPatternDoesNotMatch() {
    let v = VendorProbeRecipe.extractVersion(
        from: "no-version-here.dmg",
        pattern: #"_(\d+\.\d+)\.dmg$"#
    )
    #expect(v == nil)
}

@Test func returnsNilForInvalidPattern() {
    let v = VendorProbeRecipe.extractVersion(from: "1.2.3", pattern: "([")
    #expect(v == nil)
}

// Regression: a structured body whose app version is listed first, followed by
// unrelated higher version-shaped numbers (plugin versions). First-match must
// win; highest-match would wrongly grab the plugin number — the HBuilderX trap.
@Test func firstMatchBeatsLaterHigherPluginVersions() {
    let body = #"{"version":"5.07.2026041006","plugins":[{"version":"8.0.0"},{"version":"1.2.3"}]}"#
    let pat = #""version"\s*:\s*"([0-9][0-9.]*)""#
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pat) == "5.07.2026041006")
    // Highest would pick the unrelated plugin version — which is why selectHighest
    // must stay opt-in, not the default.
    #expect(VendorProbeRecipe.highestVersion(from: body, pattern: pat) == "8.0.0")
}

// Ascending Sparkle appcast: highestVersion picks the newest, first-match would
// grab the oldest. This is the case selectHighest exists for (VLC).
@Test func highestVersionPicksNewestFromAscendingFeed() {
    let xml = #"<item sparkle:version="3.0.14"/><item sparkle:version="3.0.20"/><item sparkle:version="3.0.23"/>"#
    let pat = #"sparkle:version="([0-9.]+)""#
    #expect(VendorProbeRecipe.extractVersion(from: xml, pattern: pat) == "3.0.14")
    #expect(VendorProbeRecipe.highestVersion(from: xml, pattern: pat) == "3.0.23")
}

@Test func extractsSurgeVersionFromSparkleShortVersionString() {
    let xml = """
    <item>
      <title>Surge Mac</title>
      <sparkle:shortVersionString>6.6.0</sparkle:shortVersionString>
      <sparkle:version>11270</sparkle:version>
      <description>Fixes and improvements.</description>
    </item>
    """
    let pat = #"<sparkle:shortVersionString>([0-9]+(?:\.[0-9]+){1,2})</sparkle:shortVersionString>"#
    #expect(VendorProbeRecipe.extractVersion(from: xml, pattern: pat) == "6.6.0")
}

@Test func takesFirstVersionWhenSeveralPresent() {
    // First match wins — keep recipe patterns specific to avoid grabbing the
    // wrong number (e.g. a macOS minimum) on a busy filename/body.
    let v = VendorProbeRecipe.extractVersion(
        from: "Foo_5.1.2_macos11.dmg",
        pattern: #"_(\d+(?:\.\d+){1,3})_"#
    )
    #expect(v == "5.1.2")
}

// MARK: - OrbStack multi-channel appcast (cross-channel containment)

/// One appcast carries every channel as separate `<item>`s. Each OrbStack recipe
/// is anchored to its own `<sparkle:channel>` tag and tempered so it can't reach
/// past `</item>` into a neighbouring item — so a user is only ever offered their
/// channel's build, even if the feed reorders or a channel's item lacks a version.
private func orbStackVersionPattern(_ channel: ReleaseChannel) -> String {
    VendorProbeRegistry.recipes.first {
        $0.bundleID == "dev.kdrag0n.MacVirt" && $0.channel == channel
    }!.versionPattern
}

@Test func orbStackChannelsResolveToTheirOwnItem() {
    let feed = """
    <item>
      <sparkle:channel>stable</sparkle:channel>
      <enclosure url="https://cdn-updates.orbstack.dev/arm64/OrbStack_v2.1.3_20115_arm64.dmg" />
    </item>
    <item>
      <sparkle:channel>beta</sparkle:channel>
      <enclosure url="https://cdn-updates.orbstack.dev/arm64/OrbStack_v2.2.0_20200_arm64.dmg" />
    </item>
    """
    #expect(VendorProbeRecipe.extractVersion(from: feed, pattern: orbStackVersionPattern(.stable)) == "2.1.3")
    #expect(VendorProbeRecipe.extractVersion(from: feed, pattern: orbStackVersionPattern(.beta)) == "2.2.0")
}

/// The whole point of the tempering: a channel whose own item carries no version
/// must resolve to nil — NOT bleed into the next item's (different-channel) build.
@Test func orbStackDoesNotLeakAcrossItems() {
    let feed = """
    <item>
      <sparkle:channel>stable</sparkle:channel>
    </item>
    <item>
      <sparkle:channel>beta</sparkle:channel>
      <enclosure url="https://cdn-updates.orbstack.dev/arm64/OrbStack_v9.9.9_99999_arm64.dmg" />
    </item>
    """
    // Stable has no OrbStack_v before </item> → must be nil, not the beta 9.9.9.
    #expect(VendorProbeRecipe.extractVersion(from: feed, pattern: orbStackVersionPattern(.stable)) == nil)
    #expect(VendorProbeRecipe.extractVersion(from: feed, pattern: orbStackVersionPattern(.beta)) == "9.9.9")
}

// MARK: - Source behaviour

@Test func sourceReturnsNilWhenNoRecipeForApp() async throws {
    let source = VendorProbeSource(recipes: [])  // empty table
    let app = InstalledApp(
        name: "ToDesk", bundleID: "com.youqu.todesk.mac",
        shortVersion: "4.7.0.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/ToDesk.app"),
        isMASApp: false, sparkleFeedURL: nil
    )
    let remote = try await source.latestVersion(for: app)
    #expect(remote == nil)  // not applicable → engine falls through to .unknown
}

@Test func sourceReturnsNilForAppWithoutBundleID() async throws {
    let source = VendorProbeSource()
    let app = InstalledApp(
        name: "Mystery", bundleID: nil,
        shortVersion: "1.0", buildVersion: nil,
        path: URL(fileURLWithPath: "/Applications/Mystery.app"),
        isMASApp: false, sparkleFeedURL: nil
    )
    let remote = try await source.latestVersion(for: app)
    #expect(remote == nil)
}

// MARK: - Probe debugging harness (live; for hunting new recipes)

/// Ad-hoc harness for confirming a candidate recipe before adding it to
/// `VendorProbeRegistry`. Fill in `candidates` with a recipe to debug, run this
/// test, and read stderr to see what the probe resolves. Skipped (no-op) when
/// empty, so it stays green in CI. This is the "大量调试" workbench the project
/// memory `duo-updater-vendor-probe-plan` calls for.
// Regression: Postman's notes array is sorted newest-first; the pattern must
// anchor to "notes":[{ so it grabs the first entry's version, not a later one.
@Test func extractsPostmanVersionFromNotesArray() {
    let body = #"{"notes":[{"version":"12.13.2","content":"...","createdAt":"2026-06-02T00:00:00.000Z"},{"version":"12.12.7","content":"...","createdAt":"2026-05-30T00:00:00.000Z"}]}"#
    let pat = #""notes"\s*:\s*\[\s*\{[^}]*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pat) == "12.13.2")
}

@Test func probeCandidateRecipes() async {
    let err = FileHandle.standardError
    func log(_ s: String) { err.write((s + "\n").data(using: .utf8)!) }

    // ⬇️ Drop a recipe here to debug it, e.g.:
    // VendorProbeRecipe(
    //     bundleID: "com.youqu.todesk.mac",
    //     url: URL(string: "https://dl.todesk.com/.../latest")!,
    //     mode: .redirectFilename,
    //     versionPattern: #"_(\d+(?:\.\d+){1,3})\.dmg$"#)
    let candidates: [VendorProbeRecipe] = []

    guard !candidates.isEmpty else {
        log("[probe] no candidate recipes — skipping live harness")
        return
    }

    let source = VendorProbeSource(recipes: candidates)
    for recipe in candidates {
        let app = InstalledApp(
            name: recipe.bundleID, bundleID: recipe.bundleID,
            shortVersion: "0", buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/\(recipe.bundleID).app"),
            isMASApp: false, sparkleFeedURL: nil
        )
        let remote = (try? await source.latestVersion(for: app)) ?? nil
        log("[probe] \(recipe.bundleID) (\(recipe.url.absoluteString))")
        log("        -> version: \(remote?.shortVersion ?? "nil")  download: \(remote?.downloadURL?.absoluteString ?? "nil")")
    }
}
