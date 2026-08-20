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

// HBuilderX Alpha — alpha.json carries a short "displayVersion" before the real
// "version" pre-release string. The recipe pattern must skip displayVersion and
// capture the full "-alpha" build (which matches the installed CFBundleShortVersionString).
@Test func extractsHBuilderXAlphaVersionFromConfigJSON() {
    let recipe = try! #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "io.dcloud.HBuilderXAlpha" })
    #expect(recipe.channel == .alpha)  // linchpin: must match the app's detected channel
    let body = #"{"displayVersion":"5.11","version":"5.11.2026052520-alpha","release":"https://x"}"#
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern)
        == "5.11.2026052520-alpha")
}

// ToDesk — the download page server-renders the macOS pkg URL into an inline data
// blob. As of 2026-07-13 every macOS version field is variable-ized (`mac_version:l`),
// so the one durable literal is the consumer `macos/ToDesk_<ver>.pkg` filename. The
// page also carries DaaS (enterprise) pkg links `ToDesk_DaaS_v1.1.0.1.pkg` /
// `…-v1.1.0.1_392.pkg` that appear FIRST; anchoring on `ToDesk_<digit>` skips them
// (they read `ToDesk_D…`) and lands the consumer GA build. Regression guard below:
// the retired `mac_version:"…"` anchor must no longer match this body.
@Test func todeskAnchorsOnGAPkgFilenameNotDaaSChannel() {
    let recipe = try! #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.youqu.todesk.mac" })
    // Trimmed real blob: DaaS GA + gray pkg links (own digits) precede the GA
    // positional-arg block; every mac_version field is now a bare variable.
    let body = #"mac_link:"https://dl.todesk.com/daas/mac/ToDesk_DaaS_v1.1.0.1.pkg",mac_link_gray:"https://dl.todesk.com/daas/mac/ToDesk_DaaS-v1.1.0.1_392.pkg",mac_version:l,mac_version_gray:l,"#
        + #"("",false,"-1","2026.7.10","https://dl.todesk.com/macos/ToDesk_4.9.7.4.pkg",true)"#
    // Version anchors on the consumer GA pkg filename, NOT the DaaS 1.1.0.1 links.
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == "4.9.7.4")
    // Regression: the retired mac_version literal anchor finds nothing in the new body.
    #expect(VendorProbeRecipe.extractVersion(
        from: body, pattern: #"mac_version:"([0-9]+(?:\.[0-9]+)+)""#) == nil)
    // The install spec rebuilds the GA pkg URL from the captured filename version.
    guard case let .bodyTemplate(template, fields) = recipe.install?.urlSource else {
        Issue.record("expected bodyTemplate install source"); return
    }
    let captured = try! #require(VendorProbeRecipe.extractVersion(from: body, pattern: fields[0]))
    #expect(captured == "4.9.7.4")
    #expect(template.replacingOccurrences(of: "{0}", with: captured)
        == "https://dl.todesk.com/macos/ToDesk_4.9.7.4.pkg")
}

// Spotify — has no cheap version API; the version is read from the bundled
// Info.plist inside the 1.8MB stub-installer zip via the .zipEntryPlist mode.
// Can't exercise the network+unzip offline, so assert the recipe wiring and that
// the validator accepts a real dotted version while rejecting the binary-plist
// header / non-version noise the extractor would otherwise see on a bad parse.
@Test func spotifyZipPlistRecipeIsWiredAndValidatesVersion() {
    let recipe = try! #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.spotify.client" })
    guard case let .zipEntryPlist(entry, key) = recipe.mode else {
        Issue.record("expected .zipEntryPlist mode"); return
    }
    #expect(entry == "Install Spotify.app/Contents/Info.plist")
    #expect(key == "CFBundleShortVersionString")
    // versionPattern is the final validator over the plist value.
    #expect(VendorProbeRecipe.extractVersion(from: "1.2.92.148", pattern: recipe.versionPattern) == "1.2.92.148")
    #expect(VendorProbeRecipe.extractVersion(from: "bplist00", pattern: recipe.versionPattern) == nil)
    #expect(VendorProbeRecipe.extractVersion(from: "Spotify", pattern: recipe.versionPattern) == nil)
    // One-click install pulls the always-latest universal dmg (fixed URL).
    guard case let .fixed(url) = recipe.install?.urlSource else {
        Issue.record("expected fixed dmg install source"); return
    }
    #expect(url.absoluteString == "https://download.scdn.co/SpotifyARM64.dmg")
    #expect(recipe.install?.kind == .dmg)
}

// Alcove — the vendor retired `update.tryalcove.com` (NXDOMAIN, 2026-08-09), so
// the public fallback reads the `/latest` metadata document instead, the first
// public surface that keeps pace with the licensed channel.
@Test func alcoveProbesTheLiveMetadataEndpointAndStaysDetectionOnly() {
    let recipe = try! #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.henrikruscon.Alcove" })
    // The dead host must not survive anywhere in the recipe.
    #expect(!recipe.url.absoluteString.contains("update.tryalcove.com"))
    #expect(recipe.url.absoluteString == "https://download.tryalcove.com/latest")

    // A real response, verbatim. `minimum_system_version` is the trap: it also
    // ends in `version`, so an unanchored pattern reads "15 Sequoia" — or worse,
    // silently matches it the day the key order changes.
    let body = #"{"version":"1.7.9","build":203,"published_at":"2026-06-30T20:57:57.000Z""#
        + #","assets":[{"name":"Alcove.zip","size_bytes":15269999}]"#
        + #","minimum_system_version":"15 Sequoia"}"#
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == "1.7.9")
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"minimum_system_version":"15 Sequoia"}"#,
        pattern: recipe.versionPattern) == nil)
    // Segment count isn't pinned, so a future 1.8 or 1.8.0.1 still reads.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"version":"1.8","build":210}"#, pattern: recipe.versionPattern) == "1.8")
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"version":"1.8.0.1"}"#, pattern: recipe.versionPattern) == "1.8.0.1")

    // DETECTION ONLY, deliberately. The dmg on this same host is the trial build
    // and trails this metadata (1.7.9 here vs 1.7.7 in the bundle on 2026-08-09),
    // so an install spec would install 1.7.7, keep reporting 1.7.9, and re-offer
    // the update forever.
    #expect(recipe.install == nil,
            "the public dmg lags this metadata — installing it would be a phantom update")

    // Notes come from the vendor's page in a WebView: the retired host took the
    // parseable feed with it and this endpoint carries no release notes.
    #expect(recipe.changelogURL?.absoluteString == "https://www.tryalcove.com/changelog")
    #expect(ChangelogRecipeRegistry.recipe(forBundleID: "com.henrikruscon.Alcove") == nil,
            "the changelog recipe pointed at the dead host and was removed")
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
            isMASApp: false, sparkleFeedURL: nil,
            releaseChannel: recipe.channel
        )
        let remote = (try? await source.latestVersion(for: app)) ?? nil
        log("[probe] \(recipe.bundleID) (\(recipe.url.absoluteString))")
        log("        -> version: \(remote?.shortVersion ?? "nil")  download: \(remote?.downloadURL?.absoluteString ?? "nil")")
    }
}

// MARK: - Wave-1 self-updater detection probes (fixtures from real responses)

@Test func slackProbeExtractsVersionFromRedirectFilename() {
    // The 302 from slack.com/ssb/download-osx-universal resolves to this filename.
    let filename = "Slack-4.50.128-macOS.dmg"
    #expect(VendorProbeRecipe.extractVersion(
        from: filename, pattern: #"^Slack-([0-9]+\.[0-9]+\.[0-9]+)-macOS\.dmg$"#) == "4.50.128")
}

@Test func discordProbeExtractsVersionFromDistroURL() {
    // Trimmed slice of the real stable manifest JSON. host_version is an array
    // (unusable — single capture group), so the version comes from the distro url
    // path; the 0.0.392 delta SOURCE must not be captured.
    let fixture = #"""
    {"full":{"host_version":[0,0,393],"url":"https://stable.dl2.discordapp.net/distro/app/stable/osx/universal/0.0.393/full.distro"},"deltas":[{"host_version":[0,0,392],"url":"https://stable.dl2.discordapp.net/distro/app/stable/osx/universal/0.0.393/from/0.0.392"}],"required_update":true}
    """#
    let stable = registryRecipe("com.hnc.Discord")
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: stable.versionPattern)
        == "0.0.393")

    // 2026-08-16: the vendor moved stable's CDN host from `stable.dl2.discordapp.net`
    // to plain `dl.discordapp.net` — captured verbatim from the live manifest, which
    // is what took this probe red in `duo verify`. The channel segment in the PATH is
    // the anchor that must carry the recipe, not the hostname.
    let movedHost = #"""
    {"full":{"host_version":[0,0,408],"url":"https://dl.discordapp.net/distro/app/stable/osx/universal/0.0.408/full.distro"},"deltas":[{"host_version":[0,0,407],"url":"https://dl.discordapp.net/distro/app/stable/osx/universal/0.0.408/from/0.0.407"}]}
    """#
    #expect(VendorProbeRecipe.extractVersion(from: movedHost, pattern: stable.versionPattern)
        == "0.0.408")
}

@Test func discordPTBAndCanaryProbesExtractTheirOwnChannelVersion() {
    // PTB / Canary mirror Stable: same manifest shape, the version lives in the
    // per-channel distro url path. Each recipe's pattern is anchored to its OWN
    // channel literal so it can't grab a neighbour's number, and its `channel`
    // is the linchpin the source's gate matches against the installed app.
    let ptbBody = #"{"full":{"host_version":[0,0,237],"url":"https://ptb.dl2.discordapp.net/distro/app/ptb/osx/universal/0.0.237/full.distro"},"deltas":[{"url":"https://ptb.dl2.discordapp.net/distro/app/ptb/osx/universal/0.0.237/from/0.0.236"}]}"#
    let ptb = registryRecipe("com.hnc.DiscordPTB")
    #expect(ptb.channel == .ptb)
    #expect(VendorProbeRecipe.extractVersion(from: ptbBody, pattern: ptb.versionPattern) == "0.0.237")

    let canaryBody = #"{"full":{"host_version":[0,0,1136],"url":"https://canary.dl2.discordapp.net/distro/app/canary/osx/universal/0.0.1136/full.distro"},"deltas":[{"url":"https://canary.dl2.discordapp.net/distro/app/canary/osx/universal/0.0.1136/from/0.0.1135"}]}"#
    let canary = registryRecipe("com.hnc.DiscordCanary")
    #expect(canary.channel == .canary)
    #expect(VendorProbeRecipe.extractVersion(from: canaryBody, pattern: canary.versionPattern) == "0.0.1136")

    // Cross-channel containment: the PTB pattern must NOT match a canary body.
    #expect(VendorProbeRecipe.extractVersion(from: canaryBody, pattern: ptb.versionPattern) == nil)
}

@Test func notionProbeExtractsVersionFromRedirectLocation() {
    // Real 307 Location from https://www.notion.so/desktop/mac/download
    let location = "https://desktop-release.notion-static.com/Notion-7.20.0-universal.dmg"
    #expect(VendorProbeRecipe.extractVersion(
        from: location, pattern: #"Notion-([0-9]+\.[0-9]+\.[0-9]+)-"#) == "7.20.0")
}

@Test func obsidianProbeReadsStableNotBeta() {
    // Real desktop-releases.json shape: stable latestVersion first, then a HIGHER
    // beta.latestVersion. First match (extractVersion) must return the stable one.
    let fixture = #"""
    {
        "minimumVersion": "0.14.5",
        "latestVersion": "1.12.7",
        "downloadUrl": "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.12.7/obsidian-1.12.7.asar.gz",
        "beta": {
            "minimumVersion": "0.14.5",
            "latestVersion": "1.13.0",
            "downloadUrl": "https://releases.obsidian.md/release/obsidian-1.13.0.asar.gz"
        }
    }
    """#
    #expect(VendorProbeRecipe.extractVersion(
        from: fixture, pattern: #""latestVersion"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#) == "1.12.7")
}

@Test func figmaProbeExtractsVersion() {
    // Trimmed real body from https://desktop.figma.com/mac-arm/RELEASE.json
    let fixture = #"{"version":"126.4.11","name":"126.4.11","rollback":true,"url":"https://desktop.figma.com/mac-arm/Figma-126.4.11.zip"}"#
    #expect(VendorProbeRecipe.extractVersion(
        from: fixture, pattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#) == "126.4.11")
}

@Test func onePasswordProbeTakesNewestTitleSkippingBareHeading() {
    // Trimmed slice of releases.1password.com/mac/stable/: the <h1> has no version
    // (must be skipped); the first versioned title is the newest stable build.
    let fixture = #"""
    <h1 class="c-heading c-heading--1">1Password for Mac</h1>
    <h6 class="c-heading c-updates__title">1Password for Mac 8.12.22</h6>
    <h6 class="c-heading c-updates__title">1Password for Mac 8.12.21</h6>
    """#
    #expect(VendorProbeRecipe.extractVersion(
        from: fixture, pattern: #"1Password for Mac\s+([0-9]+\.[0-9]+\.[0-9]+)"#) == "8.12.22")
}

@Test func sublimeTextProbeKeepsBuildPrefixForComparison() {
    // Trimmed real slice of sublimetext.com/download. The captured form MUST keep
    // the "Build " prefix so it compares like-for-like against the installed
    // CFBundleShortVersionString "Build 4200" (a bare "4200" would read as newer).
    let fixture = """
    <p class="latest"><i>Version:</i> Build 4200</p>
        <h3>Build 4192</h3>
        <h3>Build 4189</h3>
    """
    let pattern = #"class="latest"><i>Version:</i>\s*(Build\s+4[0-9]{3})"#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "Build 4200")
    #expect(VersionComparator.isNewer("Build 4200", than: "Build 4200") == false)
}

@Test func sublimeMergeProbeKeepsBuildPrefix() {
    // sublimemerge.com/download — same shape as Sublime Text; builds are 2xxx.
    let fixture = """
    <p class="latest"><i>Version:</i> Build 2125</p>
        <h3>Build 2123</h3>
    """
    let pattern = #"class="latest"><i>Version:</i>\s*(Build\s+[0-9]{4})"#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "Build 2125")
    #expect(VersionComparator.isNewer("Build 2125", than: "Build 2125") == false)
}

@Test func plexProbeScopesToMacOSAndDropsBuildSuffix() {
    // plex.tv/api/downloads/6.json — Windows block FIRST (proves MacOS scoping);
    // the 3-component capture drops the feed's .359 build (avoids phantom update).
    let fixture = #"""
    {"computer":{"Windows":{"version":"1.112.0.359-0d79a49f","releases":[{"url":"https://downloads.plex.tv/plex-desktop/1.112.0.359-0d79a49f/windows/Plex.exe"}]},"MacOS":{"version":"1.112.0.359-0d79a49f","releases":[{"url":"https://downloads.plex.tv/plex-desktop/1.112.0.359-0d79a49f/macos/Plex-universal.zip"}]}}}
    """#
    let pattern = #""MacOS"\s*:\s*\{[^}]*?"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "1.112.0")
}

@Test func alfredProbeReadsVersionKeyFromPlistAppcast() {
    // alfredapp.com/app/update5/general.xml — plist; the version <key> is the
    // latest, distinct from the descending "## Alfred X.Y.Z" changelog markdown.
    let fixture = """
    <key>build</key>
    <integer>2320</integer>
    <key>changelogdata</key>
    <string># Change Log

    ## Alfred 5.7.3
    ## Alfred 5.7.2
    </string>
    <key>version</key>
    <string>5.7.3</string>
    """
    let pattern = #"<key>version</key>\s*<string>([0-9][0-9.]*)</string>"#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "5.7.3")
}

@Test func shottrProbeReadsStableNotBeta() {
    // shottr.cc/api/version.json — the "latestVersion" anchor must skip the
    // sibling "betaLatestVersion" listed just above it.
    let fixture = #"""
    {"betaBuild":"120","betaLatestVersion":"1.9.0","build":"128","latestVersion":"1.9.1","link":"https://shottr.cc/newversion.html","releaseDate":"2025-12-17"}
    """#
    let pattern = #""latestVersion"\s*:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)?)""#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "1.9.1")
}

@Test func theUnarchiverProbeReadsShortVersionAttribute() {
    // DevMate appcast — version is the sparkle:shortVersionString ATTRIBUTE on the
    // enclosure (descending feed → first match newest).
    let fixture = """
    <item><title>147</title>\
    <enclosure url="https://dl.devmate.com/com.macpaw.site.theunarchiver/147/TheUnarchiver-147.zip" sparkle:version="147" sparkle:shortVersionString="4.3.9"/></item>\
    <item><title>146</title>\
    <enclosure url="https://dl.devmate.com/com.macpaw.site.theunarchiver/146/TheUnarchiver-146.zip" sparkle:version="146" sparkle:shortVersionString="4.3.8"/></item>
    """
    let pattern = #"sparkle:shortVersionString="([0-9.]+)""#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "4.3.9")
}

@Test func orionProbeTakesHighestMarketingVersionNotBuild() {
    // cdn.kagi.com/updates/26_0/appcast.xml — ASCENDING; must take HIGHEST
    // shortVersionString (marketing 1.0.8), never the build (147.1).
    let fixture = """
    <item><sparkle:version>146</sparkle:version><sparkle:shortVersionString>1.0.7</sparkle:shortVersionString></item>
    <item><sparkle:version>147</sparkle:version><sparkle:shortVersionString>1.0.8</sparkle:shortVersionString></item>
    <item><sparkle:version>147.1</sparkle:version><sparkle:shortVersionString>1.0.8</sparkle:shortVersionString></item>
    """
    let pattern = #"<sparkle:shortVersionString>([0-9]+(?:\.[0-9]+)+)</sparkle:shortVersionString>"#
    #expect(VendorProbeRecipe.highestVersion(from: fixture, pattern: pattern) == "1.0.8")
}

@Test func dropboxProbeExtractsThreeComponentVersionFromLocation() {
    // 302 Location with %20-encoded filename; version is 3-component (254/4/2518).
    let location = "https://edge.dropboxstatic.com/dbx-releng/client/Dropbox%20254.4.2518.dmg"
    let pattern = #"Dropbox(?:%20| )([0-9]+\.[0-9]+\.[0-9]+)\.dmg"#
    #expect(VendorProbeRecipe.extractVersion(from: location, pattern: pattern) == "254.4.2518")
}

@Test func microsoftTeamsProbeAnchorsToWebView2CanaryNotWebView2() {
    // The config/v1/MicrosoftTeams JSON carries two macOS tracks: WebView2
    // (lower version) and WebView2Canary (production/Public R4, higher version).
    // The pattern MUST anchor to "WebView2Canary"; a loose "macOS":{"latestVersion"
    // would grab the lower WebView2 track first.
    let fixture = #"""
    {"BuildSettings":{"WebView2":{"macOS":{"latestVersion":"25290.302.4044.3989","buildLink":"https://installer.teams.static.microsoft/production-osx/25290.302.4044.3989/MicrosoftTeams.pkg"}},"WebView2Canary":{"macOS":{"latestVersion":"26120.3106.4725.800","buildLink":"https://teamsinstaller.public.onecdn.static.microsoft/production-osx/26120.3106.4725.800/MicrosoftTeams.pkg"}}}}
    """#
    let pattern = #""WebView2Canary":\{"macOS":\{"latestVersion":"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "26120.3106.4725.800")
}

@Test func oneDriveProbeExtractsMarketingVersionFromLocationPath() {
    // The 302 from go.microsoft.com/fwlink/?linkid=823060 lands on a versioned
    // .pkg URL whose filename is just "OneDrive.pkg" — the version lives in the
    // path. Capture only the first THREE components: that equals the installed
    // CFBundleShortVersionString (26.078.0426); the trailing .0002 is a build
    // revision the marketing version omits, and reading it would phantom-update.
    let location = "https://oneclient.sfx.ms/Mac/Installers/26.078.0426.0002/universal/OneDrive.pkg"
    let pattern = #"/Installers/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/"#
    #expect(VendorProbeRecipe.extractVersion(from: location, pattern: pattern) == "26.078.0426")
}

// MARK: - Office suite probes (unified version via fwlink / XML)

@Test func microsoftOfficeFwlinkExtractsVersionFromLocation() {
    // All Office fwlinks 301 to versioned .pkg URLs on the Office CDN. The version
    // is a 3-component segment (16.109.26053122) embedded in the filename.
    // followRedirects:false reads the Location header.
    let location = "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Microsoft_PowerPoint_16.109.26053122_Installer.pkg"
    let pattern = #"_(\d+\.\d+\.\d+)_Installer\.pkg"#
    #expect(VendorProbeRecipe.extractVersion(from: location, pattern: pattern) == "16.109.26053122")
}

/// A trimmed slice of the REAL Office AutoUpdate manifest (0409OPIM2019.xml,
/// fetched 2026-08-09): one delta entry (the first dict, keys alphabetical as
/// plist serialization emits them) plus the no-baseline full-updater entry that
/// follows the 24 delta entries. The previous fixture here was invented rather
/// than trimmed from the wire, which is exactly how the retired
/// `Update Version Location` key went unnoticed after Microsoft dropped it.
private let outlookManifestFixture = #"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
<dict>
    <key>Application ID</key>
    <string>OPIM2019</string>
    <key>Baseline Version</key>
    <string>16.107.26030937</string>
    <key>BinaryUpdaterLocation</key>
    <string>https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Outlook_16.107.26030937_to_16.109.26053122_BinaryDelta.pkg</string>
    <key>BinaryUpdaterSize</key>
    <integer>216560</integer>
    <key>FullUpdaterLocation</key>
    <string>https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Microsoft_Outlook_16.109.26053122_Updater.pkg</string>
    <key>FullUpdaterSize</key>
    <integer>1318143</integer>
    <key>Location</key>
    <string>https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Outlook_16.107.26030937_to_16.109.26053122_Delta.pkg</string>
    <key>Payload</key>
    <string>Outlook_16.107.26030937_to_16.109.26053122_Delta.pkg</string>
    <key>Title</key>
    <string>Microsoft Outlook Update 16.109.3 (26053122)</string>
    <key>Update Version</key>
    <string>16.109.26053122</string>
</dict>
<dict>
    <key>Application ID</key>
    <string>OPIM2019</string>
    <key>Location</key>
    <string>https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Microsoft_Outlook_16.109.26053122_Updater.pkg</string>
    <key>Payload</key>
    <string>Microsoft_Outlook_16.109.26053122_Updater.pkg</string>
    <key>Update Version</key>
    <string>16.109.26053122</string>
</dict>
</array>
</plist>
"""#

@Test func microsoftOutlookProbeExtractsVersionFromXML() {
    // Outlook uses the Office AutoUpdate XML manifest which carries the version
    // in <key>Update Version</key><string>...</string> — the BUILD, not the
    // marketing string (the pkg declares CFBundleShortVersionString 16.109.3),
    // which is what `versionIsBuild` on the recipe is for.
    let recipe = try! #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.microsoft.Outlook" })
    #expect(recipe.versionIsBuild)
    #expect(VendorProbeRecipe.extractVersion(
        from: outlookManifestFixture, pattern: recipe.versionPattern) == "16.109.26053122")
}

// Regression for the 2026-08-09 silent one-click death: Microsoft removed the
// `Update Version Location` key the install spec read, so the version still
// resolved while the installer URL didn't — the row degraded to detection-only
// with no signal. The replacement templates the pkg off the same `Update Version`
// capture detection uses, so install can't break while detection survives.
@Test func microsoftOutlookOneClickTemplatesFullUpdaterNotADelta() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.microsoft.Outlook" })
    // The retired key is really gone from the wire format — the old pattern is dead.
    #expect(VendorProbeRecipe.extractVersion(
        from: outlookManifestFixture,
        pattern: #"<key>Update Version Location</key>\s*<string>([^<]+\.pkg)</string>"#) == nil)

    let install = try #require(recipe.install)
    #expect(install.kind == .pkg)
    guard case let .bodyPattern(pattern) = install.urlSource else {
        Issue.record("expected bodyPattern install source"); return
    }
    let resolved = try #require(
        VendorProbeRecipe.extractVersion(from: outlookManifestFixture, pattern: pattern))
    // The 1.29GB standalone package, signed by Team UBF8T346G9 (same as the
    // installed app) — NOT either patch form.
    #expect(resolved == "https://res.public.onecdn.static.microsoft/mro1cdnstorage/"
        + "C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/"
        + "Microsoft_Outlook_16.109.26053122_Updater.pkg")
    // The guard that matters. Both deltas sit in the same dict and the same CDN
    // directory, and alphabetical key order puts BinaryUpdaterLocation ahead of
    // FullUpdaterLocation — so a pattern that leaned on ordering alone would be
    // one manifest reshuffle away from installing a partial payload.
    #expect(!resolved.contains("Delta"))
    // …and the pkg carries the very build the probe reports (no scheme drift).
    #expect(resolved.contains(try #require(VendorProbeRecipe.extractVersion(
        from: outlookManifestFixture, pattern: recipe.versionPattern))))
}

// MARK: - Self-updaters with public Sparkle appcasts (safety-net probes)

@Test func bartenderProbeTakesHighestFromAscendingAppcast() {
    // Bartender's Sparkle appcast is ascending (oldest first); selectHighest picks
    // the newest version (6.5.2), not the first item (6.0.0).
    let fixture = """
    <item><sparkle:shortVersionString>6.0.0</sparkle:shortVersionString></item>
    <item><sparkle:shortVersionString>6.0.1</sparkle:shortVersionString></item>
    <item><sparkle:shortVersionString>6.5.2</sparkle:shortVersionString></item>
    """
    let pattern = #"<sparkle:shortVersionString>([0-9]+\.[0-9]+\.[0-9]+)</sparkle:shortVersionString>"#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "6.0.0")
    #expect(VendorProbeRecipe.highestVersion(from: fixture, pattern: pattern) == "6.5.2")
}

@Test func imageOptimProbeReadsVersionFromSparkleAppcast() {
    // ImageOptim's Sparkle appcast carries only the latest release on the
    // enclosure's sparkle:shortVersionString ATTRIBUTE. First match is current.
    let fixture = #"""
    <enclosure url="https://imageoptim.com/ImageOptim1.9.3.tar.xz" sparkle:version="1.9.3" sparkle:shortVersionString="1.9.3" />
    """#
    let pattern = #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+)""#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "1.9.3")
}

// MARK: - Brave Beta / Nightly Sparkle appcast extraction

@Test func braveBetaProbeExtractsVersionFromAppcast() {
    // Real Brave Beta appcast: sparkle:shortVersionString is an ATTRIBUTE on the
    // <enclosure> (not an element). The feed is descending (newest first), so
    // first match is the latest version.
    let fixture = #"""
    <item>
      <title>Brave-Browser 192.114</title>
      <enclosure url="https://updates-cdn.bravesoftware.com/sparkle/Brave-Browser/beta/192.114/Brave-Browser-Beta-x64.dmg"
                 sparkle:version="192.114"
                 sparkle:shortVersionString="1.92.114.0"
                 length="162002408" type="application/octet-stream"/>
    </item>
    """#
    let recipe = registryRecipe("com.brave.Browser.beta")
    #expect(recipe.channel == .beta)
    // Compare on the BUILD. The feed's marketing string is Brave's own version
    // while the installed bundle reports a Chromium-prefixed one ("151.92.114.0"
    // for "1.92.114.0"), so comparing those puts 1 against 151, reads the installed copy
    // as newer, and hides every update. `sparkle:version` IS the bundle's
    // CFBundleVersion, so that's the pair that lines up.
    #expect(recipe.versionIsBuild)
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: recipe.versionPattern) == "192.114")
    // The marketing string is still what the user sees.
    let display = try! #require(recipe.displayVersionPattern)
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: display) == "1.92.114.0")
    // And the install pulls the arm64 artifact — the un-suffixed feed serves x64 only.
    #expect(recipe.url.absoluteString.contains("beta-arm64"))
}

@Test func braveNightlyProbeExtractsVersionFromAppcast() {
    // Same attribute shape as Beta, just a different channel endpoint.
    let fixture = #"""
    <item>
      <title>Brave-Browser 193.35</title>
      <enclosure url="https://updates-cdn.bravesoftware.com/sparkle/Brave-Browser/nightly/193.35/Brave-Browser-Nightly-x64.dmg"
                 sparkle:version="193.35"
                 sparkle:shortVersionString="1.93.35.0"
                 length="162002408" type="application/octet-stream"/>
    </item>
    """#
    let recipe = registryRecipe("com.brave.Browser.nightly")
    #expect(recipe.channel == .nightly)
    // Compare on the BUILD. The feed's marketing string is Brave's own version
    // while the installed bundle reports a Chromium-prefixed one ("151.93.35.0"
    // for "1.93.35.0"), so comparing those puts 1 against 151, reads the installed copy
    // as newer, and hides every update. `sparkle:version` IS the bundle's
    // CFBundleVersion, so that's the pair that lines up.
    #expect(recipe.versionIsBuild)
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: recipe.versionPattern) == "193.35")
    // The marketing string is still what the user sees.
    let display = try! #require(recipe.displayVersionPattern)
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: display) == "1.93.35.0")
    // And the install pulls the arm64 artifact — the un-suffixed feed serves x64 only.
    #expect(recipe.url.absoluteString.contains("nightly-arm64"))
}

// MARK: - Vivaldi Snapshot Sparkle appcast extraction

@Test func vivaldiSnapshotProbeExtractsVersionFromAppcast() {
    // Real Vivaldi Snapshot appcast: sparkle:shortVersionString is an ELEMENT
    // (not an attribute), and the feed carries only the latest release.
    let fixture = #"""
    <item>
      <title>8.1.4063.3</title>
      <sparkle:shortVersionString>8.1.4063.3</sparkle:shortVersionString>
      <sparkle:version>8.1.4063.3</sparkle:version>
      <enclosure url="https://downloads.vivaldi.com/snapshot-auto/Vivaldi.8.1.4063.3.universal.tar.xz" />
    </item>
    """#
    let recipe = registryRecipe("com.vivaldi.Vivaldi.snapshot")
    #expect(recipe.channel == .preview)
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: recipe.versionPattern) == "8.1.4063.3")
}

// MARK: - End-to-end version-routing (the verdict, not just extraction)
//
// The extraction tests above prove a recipe pulls *a string*; they don't prove
// that string is COMPARABLE to what the installed app reports. These run the
// real registry recipe through the source's RemoteVersion-assembly seam and the
// engine's `evaluate`, so a scheme mismatch (e.g. a build version compared
// against a marketing version) surfaces as a phantom update here.

private func registryRecipe(_ bundleID: String) -> VendorProbeRecipe {
    let match = VendorProbeRegistry.recipes.first { $0.bundleID == bundleID }
    #expect(match != nil, "no registry recipe for \(bundleID)")
    return match!
}

private func installedApp(
    bundleID: String, short: String, build: String?
) -> InstalledApp {
    InstalledApp(
        name: bundleID, bundleID: bundleID, shortVersion: short, buildVersion: build,
        path: URL(fileURLWithPath: "/Applications/\(bundleID).app"),
        isMASApp: false, sparkleFeedURL: nil)
}

/// Run a registry recipe's extracted version through the real source seam +
/// engine, exactly as a live probe would.
private func verdict(
    recipe: VendorProbeRecipe, extracted: String, installed: InstalledApp
) -> UpdateStatus {
    let plan: (url: URL, checksum: String?)? =
        recipe.install != nil ? (url: recipe.url, checksum: nil) : nil
    let remote = VendorProbeSource.makeRemoteVersion(
        recipe: recipe, version: extracted, install: recipe.install, plan: plan,
        resolvedDownload: recipe.downloadURL ?? recipe.url)
    return UpdateChecker.evaluate(installed: installed, remote: remote)
}

@Test func officeBuildVersionRecipesDoNotPhantomUpdateWhenCurrent() {
    // The Office fwlink/XML recipes extract the BUILD (16.109.26053122) — the
    // installed app's CFBundleVersion — while its CFBundleShortVersionString is
    // the shorter 16.109.3. Without versionIsBuild the engine compares the build
    // against the marketing version (26053122 > 3 → perpetual phantom). With it,
    // an installed copy at the same build reads as up to date.
    let build = "16.109.26053122"
    for bundleID in [
        "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint",
        "com.microsoft.onenote.mac", "com.microsoft.Outlook",
    ] {
        let recipe = registryRecipe(bundleID)
        #expect(recipe.versionIsBuild, "\(bundleID) must route its build version")
        let installed = installedApp(bundleID: bundleID, short: "16.109.3", build: build)
        #expect(
            verdict(recipe: recipe, extracted: build, installed: installed) == .upToDate,
            "\(bundleID) phantom-updated against its own installed build")
        // A genuinely newer build still surfaces as an update.
        #expect(
            verdict(recipe: recipe, extracted: "16.110.26060000", installed: installed)
                == .updateAvailable(latest: "16.110.26060000"),
            "\(bundleID) missed a real update")
    }
}

// The Release Log places a release exactly only when `publishedAt` survives the
// whole probe path — recipe pattern → ReleaseDate → RemoteVersion. Alcove's public
// endpoint states an ISO8601 time with fractional seconds, which is the shape most
// likely to fall through a parser, so assert the real value end to end.
@Test func alcoveProbeCarriesPublishedAtThroughToRemoteVersion() throws {
    let recipe = registryRecipe("com.henrikruscon.Alcove")
    let pattern = try #require(recipe.publishedAtPattern)
    let body = #"{"version":"1.7.9","build":203,"published_at":"2026-06-30T20:57:57.000Z",""#
        + #""assets":[],"minimum_system_version":"15 Sequoia"}"#

    let raw = try #require(VendorProbeRecipe.extractVersion(from: body, pattern: pattern))
    #expect(raw == "2026-06-30T20:57:57.000Z")
    let parsed = try #require(ReleaseDate.parse(raw), "fractional-seconds ISO8601 must parse")
    // 2026-06-30T20:57:57Z — asserted as an epoch so a formatter silently reading
    // the timestamp in local time (a 2h skew here) can't pass unnoticed.
    #expect(parsed == Date(timeIntervalSince1970: 1782853077))

    // …and reaches RemoteVersion, which is what ReleaseTimelineStore gates on.
    let remote = VendorProbeSource.makeRemoteVersion(
        recipe: recipe, version: "1.7.9", install: nil, plan: nil,
        resolvedDownload: recipe.downloadURL, publishedAt: parsed)
    #expect(remote.publishedAt == parsed)
}

// Recipes without a publishedAtPattern must stay absent rather than inventing a
// time — the timeline then shows its estimated "≈" window instead.
@Test func probeWithoutPublishedAtPatternLeavesReleaseTimeUnset() {
    let recipe = registryRecipe("com.spotify.client")
    #expect(recipe.publishedAtPattern == nil)
    let remote = VendorProbeSource.makeRemoteVersion(
        recipe: recipe, version: "1.2.92.148", install: nil, plan: nil,
        resolvedDownload: recipe.downloadURL)
    #expect(remote.publishedAt == nil)
}

@Test func alcovePublicProbeComparesMarketingToMarketing() {
    // download.tryalcove.com/latest exposes BOTH `version` (1.7.9, marketing) and
    // `build` (203). The installed bundle is 1.7.9 (203), so grabbing the build
    // would compare 203 against 1.7.9 → a phantom update that never clears. Verified
    // against the real 2026-07-29 response: installed 1.7.9 reads as up to date.
    let recipe = registryRecipe("com.henrikruscon.Alcove")
    let installed = installedApp(
        bundleID: "com.henrikruscon.Alcove", short: "1.7.9", build: "203")
    #expect(verdict(recipe: recipe, extracted: "1.7.9", installed: installed) == .upToDate)
    // An older install still sees the real update.
    let old = installedApp(bundleID: "com.henrikruscon.Alcove", short: "1.7.7", build: "199")
    #expect(verdict(recipe: recipe, extracted: "1.7.9", installed: old)
                == .updateAvailable(latest: "1.7.9"))
}

@Test func intelliJEAPBuildRecipeStripsPrefixAndDoesNotPhantomUpdate() {
    // The EAP recipe extracts the bare build "262.7132.23" (versionIsBuild) while the
    // installed bundle's CFBundleVersion carries the product-code prefix
    // "IU-262.6653.22". The engine strips that prefix before comparing — so an install
    // already AT the latest build reads up to date (no perpetual phantom), and an
    // older build still surfaces the update.
    let recipe = registryRecipe("com.jetbrains.intellij-EAP")
    #expect(recipe.versionIsBuild, "EAP recipe must route its build version")
    #expect(recipe.channel == .preview, "EAP recipe must target the preview channel")

    // Already on the latest build (prefixed) → up to date, NOT a phantom update.
    let current = installedApp(bundleID: "com.jetbrains.intellij-EAP",
                               short: "EAP IU-262.7132.23", build: "IU-262.7132.23")
    #expect(
        verdict(recipe: recipe, extracted: "262.7132.23", installed: current) == .upToDate,
        "EAP phantom-updated against its own installed build")

    // An older installed build still surfaces the newer one.
    let older = installedApp(bundleID: "com.jetbrains.intellij-EAP",
                             short: "EAP IU-262.6653.22", build: "IU-262.6653.22")
    #expect(
        verdict(recipe: recipe, extracted: "262.7132.23", installed: older)
            == .updateAvailable(latest: "262.7132.23"),
        "EAP missed a real build bump")
}

@Test func androidStudioPreviewObeysStabilityFloorAndShowsCleanVersion() {
    // Faithful newest-first slice spanning TWO feature versions: the next version's
    // Canary 1 (2026.1.3, newest overall) sits above the current version's RC 1
    // (2026.1.2) and Canary 7 (2026.1.2). The quality ladder is Canary < Beta < RC.
    let body = #"""
    {"content":{"item":[\#
    {"build":"AI-261.25134.95.2613.15674866","platformVersion":"2026.1.3","name":"Android Studio Quail 3 | 2026.1.3 Canary 1","channel":"Canary","version":"2026.1.3.1"},\#
    {"build":"AI-261.25134.95.2612.15653154","platformVersion":"2026.1.2","name":"Android Studio Quail 2 | 2026.1.2 RC 1","channel":"RC","version":"2026.1.2.8"},\#
    {"build":"AI-261.25134.95.2612.15616290","platformVersion":"2026.1.2","name":"Android Studio Quail 2 | 2026.1.2 Canary 7","channel":"Canary","version":"2026.1.2.7"}\#
    ]}}
    """#

    func recipe(_ channel: ReleaseChannel) -> VendorProbeRecipe {
        let r = VendorProbeRegistry.recipes.first {
            $0.bundleID == "com.google.android.studio" && $0.channel == channel
        }
        #expect(r != nil, "no AS preview recipe for \(channel.rawValue)")
        return r!
    }
    func resolved(_ r: VendorProbeRecipe) -> (build: String, display: String) {
        let build = VendorProbeRecipe.extractVersion(from: body, pattern: r.versionPattern)
        let display = r.displayVersionPattern.flatMap {
            VendorProbeRecipe.extractVersion(from: body, pattern: $0)
        }
        #expect(build != nil && display != nil)
        return (build!, display!)
    }

    // Canary accepts the whole ladder → newest overall is the next version's Canary 1.
    let canary = resolved(recipe(.canary))
    #expect(canary.build == "AI-261.25134.95.2613.15674866")
    #expect(canary.display == "2026.1.3 Canary 1")

    // Beta accepts ONLY Beta/RC → it skips 2026.1.3 Canary 1 and lands on RC 1.
    // (A Beta must never be offered a Canary — that's a stability downgrade.)
    let beta = resolved(recipe(.beta))
    #expect(beta.build == "AI-261.25134.95.2612.15653154")
    #expect(beta.display == "2026.1.2 RC 1")

    // A Beta already on RC 1 is up to date — NOT pushed onto the newer Canary 1.
    let betaRemote = VendorProbeSource.makeRemoteVersion(
        recipe: recipe(.beta), version: beta.build, install: nil, plan: nil,
        resolvedDownload: nil, display: beta.display)
    #expect(betaRemote.displayVersion == "2026.1.2 RC 1")
    let betaOnRC = installedApp(
        bundleID: "com.google.android.studio", short: "2026.1.2",
        build: "AI-261.25134.95.2612.15653154")
    #expect(
        UpdateChecker.evaluate(installed: betaOnRC, remote: betaRemote) == .upToDate,
        "Beta on RC 1 must not be offered the next version's Canary")

    // A Canary 7 install IS offered Canary 1 of the next version, shown cleanly.
    let canaryRemote = VendorProbeSource.makeRemoteVersion(
        recipe: recipe(.canary), version: canary.build, install: nil, plan: nil,
        resolvedDownload: nil, display: canary.display)
    let canaryOn7 = installedApp(
        bundleID: "com.google.android.studio", short: "2026.1.2",
        build: "AI-261.25134.95.2612.15616290")
    #expect(
        UpdateChecker.evaluate(installed: canaryOn7, remote: canaryRemote)
            == .updateAvailable(latest: "2026.1.3 Canary 1"),
        "Canary should advance onto the newest preview, shown as a clean version")
}

// WeChat's public appcast: the current release is emitted once per system-version
// band (all carrying the same `sparkle:version`), plus older items. A trimmed but
// faithful slice — item 1 has the enclosure dmg; item 3 is DOCTYPE-wrapped and has
// NO enclosure (it tells the user to download from the website).
private let weChatFeed = #"""
<?xml version="1.0" ?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
<item>
<title>4.1.10.53</title>
<sparkle:version>268853</sparkle:version>
<sparkle:shortVersionString>4.1.10.53</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
<enclosure url="https://dldir1v6.qq.com/weixin/Universal/Mac/xWeChatMac_universal_4.1.10.53_39917.dmg?t=1781161112" length="496955386" type="application/octet-stream" sparkle:edSignature="aZyHiWF0=="/>
</item>
<item>
<title>4.1.10.53</title>
<sparkle:version>268853</sparkle:version>
<sparkle:maximumSystemVersion>14.3</sparkle:maximumSystemVersion>
<sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
<enclosure url="https://dldir1v6.qq.com/weixin/Universal/Mac/xWeChatMac_universal_4.1.10.53_39917.dmg?t=1781161112" sparkle:shortVersionString="4.1.10.53" type="application/octet-stream"/>
</item>
<item>
<title>4.1.10.53</title>
<sparkle:version>268853</sparkle:version>
<sparkle:minimumSystemVersion>14.3</sparkle:minimumSystemVersion>
</item>
<item>
<title>3.8.10.17</title>
<sparkle:version>27317</sparkle:version>
<sparkle:shortVersionString>3.8.10.17</sparkle:shortVersionString>
<enclosure url="https://dldir1v6.qq.com/weixin/Universal/Mac/xWeChatMac_universal_3.8.10.17_31000.dmg?t=1" type="application/octet-stream"/>
</item>
</channel></rss>
"""#

@Test func weChatProbesMarketingVersionAndDmg() {
    let recipe = registryRecipe("com.tencent.xinWeChat")
    #expect(recipe.selectHighest, "WeChat lists several shortVersionString — needs highest-wins")
    #expect(!recipe.versionIsBuild, "WeChat compares the MARKETING version (4.1.10), not the build")

    // The feed's 4-segment "4.1.10.53" is truncated to the 3-segment marketing
    // "4.1.10" — what the installed bundle and the official site report. The older
    // item (3.8.10.17 → 3.8.10) loses to it under selectHighest.
    #expect(VendorProbeRecipe.highestVersion(from: weChatFeed, pattern: recipe.versionPattern) == "4.1.10")

    // One-click pulls the FIRST enclosure (newest item), token query intact.
    guard case let .bodyPattern(pat) = recipe.install?.urlSource else {
        Issue.record("expected bodyPattern install source"); return
    }
    #expect(recipe.install?.kind == .dmg)
    #expect(
        VendorProbeRecipe.extractVersion(from: weChatFeed, pattern: pat)
            == "https://dldir1v6.qq.com/weixin/Universal/Mac/xWeChatMac_universal_4.1.10.53_39917.dmg?t=1781161112")
}

@Test func weChatMarketingVersionDoesNotPhantomUpdate() {
    let recipe = registryRecipe("com.tencent.xinWeChat")

    // On the latest marketing version → up to date, even though a newer build (268853)
    // exists for the same 4.1.10. We deliberately don't surface sub-builds.
    let current = installedApp(bundleID: "com.tencent.xinWeChat", short: "4.1.10", build: "268851")
    #expect(
        verdict(recipe: recipe, extracted: "4.1.10", installed: current) == .upToDate,
        "WeChat phantom-updated against the same marketing version")

    // A genuinely newer marketing version still surfaces, shown as "4.1.10".
    let behind = installedApp(bundleID: "com.tencent.xinWeChat", short: "4.1.9", build: "268000")
    #expect(
        verdict(recipe: recipe, extracted: "4.1.10", installed: behind)
            == .updateAvailable(latest: "4.1.10"),
        "WeChat missed a real marketing-version bump")
}

@Test func nonBuildRecipesStillCompareAgainstMarketingVersion() {
    // Teams and OneDrive stay non-build. `extracted` is what each recipe's pattern
    // captures (OneDrive: first 3 path components, NOT the 4-component path); short
    // / build are the real installed Info.plist fields read from the vendor pkg.
    // An installed copy at the current version is up to date; a newer one surfaces.
    struct Case { let bundleID, short, build, current, newer: String }
    for c in [
        // Teams: short == build == the detected version.
        Case(bundleID: "com.microsoft.teams2", short: "26120.3106.4725.800",
             build: "26120.3106.4725.800", current: "26120.3106.4725.800",
             newer: "26121.0.0.0"),
        // OneDrive: short is 3-component, build merges the first two — neither equals
        // the 4-component path. The pattern captures the first 3 (== short).
        Case(bundleID: "com.microsoft.OneDrive", short: "26.078.0426",
             build: "26078.0426.0002", current: "26.078.0426", newer: "26.079.0501"),
    ] {
        let recipe = registryRecipe(c.bundleID)
        #expect(!recipe.versionIsBuild)
        let installed = installedApp(bundleID: c.bundleID, short: c.short, build: c.build)
        #expect(
            verdict(recipe: recipe, extracted: c.current, installed: installed) == .upToDate,
            "\(c.bundleID) phantom-updated against its own installed version")
        #expect(
            verdict(recipe: recipe, extracted: c.newer, installed: installed)
                == .updateAvailable(latest: c.newer),
            "\(c.bundleID) missed a real update")
    }
}

@Test func microsoftTeamsInstallBuildLinkAnchorsToCanaryTrack() {
    // The install pattern must pull the buildLink from the WebView2Canary block,
    // not the WebView2 block listed first — otherwise detection (Canary) and
    // install (WebView2) point at different version tracks.
    let fixture = #"""
    {"BuildSettings":{"WebView2":{"macOS":{"latestVersion":"25290.302.4044.3989","buildLink":"https://installer.teams.static.microsoft/production-osx/25290.302.4044.3989/MicrosoftTeams.pkg"}},"WebView2Canary":{"macOS":{"latestVersion":"26120.3106.4725.800","buildLink":"https://teamsinstaller.public.onecdn.static.microsoft/production-osx/26120.3106.4725.800/MicrosoftTeams.pkg"}}}}
    """#
    let recipe = registryRecipe("com.microsoft.teams2")
    guard case let .bodyPattern(pattern)? = recipe.install?.urlSource else {
        Issue.record("Teams recipe lost its bodyPattern install spec")
        return
    }
    let link = VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern)
    #expect(link == "https://teamsinstaller.public.onecdn.static.microsoft/production-osx/26120.3106.4725.800/MicrosoftTeams.pkg")
}

// Thunderbird Nightly/Daily must have NO changelogURL: thunderbird.net publishes
// no nightly release notes and no recipe targets it, so a changelogURL would only
// embed the unrelated stable releases page. nil → honest "No release notes" state.
@Test func thunderbirdDailyHasNoChangelogURL() throws {
    let daily = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.mozilla.thunderbird-daily" })
    #expect(daily.channel == .nightly)
    #expect(daily.changelogURL == nil)
}

// Thunderbird — every channel is one-click via Mozilla's `download.mozilla.org`
// per-channel `-latest` redirect (302 → CDN `.dmg`). Lock in that each recipe
// carries a `.redirect` dmg install pointing at its own product code, so a future
// edit can't silently drop a channel back to detection-only or cross-wire it.
@Test func thunderbirdAllChannelsOneClickDmg() throws {
    let expected: [(channel: ReleaseChannel, product: String)] = [
        (.stable, "thunderbird-latest"),
        (.beta, "thunderbird-beta-latest"),
        (.esr, "thunderbird-esr-latest"),
        (.nightly, "thunderbird-nightly-latest"),
    ]
    for (channel, product) in expected {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first {
                $0.bundleID.hasPrefix("org.mozilla.thunderbird") && $0.channel == channel
            },
            "missing Thunderbird recipe for channel \(channel)")
        let install = try #require(recipe.install, "\(channel) must be one-click")
        #expect(install.kind == .dmg)
        guard case let .redirect(url) = install.urlSource else {
            Issue.record("\(channel) install must use a .redirect URL source")
            continue
        }
        #expect(url.absoluteString.contains("product=\(product)"))
        #expect(url.absoluteString.contains("os=osx"))
    }
}

// Firefox — same Mozilla one-click mechanism as Thunderbird, across all five
// channels. Dev Edition's product code is `firefox-devedition-latest` (NOT a
// plain `-dev`), so lock that mapping in too.
@Test func firefoxAllChannelsOneClickDmg() throws {
    let expected: [(bundleID: String, channel: ReleaseChannel, product: String)] = [
        ("org.mozilla.firefox", .stable, "firefox-latest"),
        ("org.mozilla.firefox", .beta, "firefox-beta-latest"),
        ("org.mozilla.firefox", .esr, "firefox-esr-latest"),
        ("org.mozilla.firefoxdeveloperedition", .dev, "firefox-devedition-latest"),
        ("org.mozilla.nightly", .nightly, "firefox-nightly-latest"),
    ]
    for (bundleID, channel, product) in expected {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first {
                $0.bundleID == bundleID && $0.channel == channel
            },
            "missing Firefox recipe for \(bundleID)/\(channel)")
        let install = try #require(recipe.install, "\(channel) must be one-click")
        #expect(install.kind == .dmg)
        guard case let .redirect(url) = install.urlSource else {
            Issue.record("\(channel) install must use a .redirect URL source")
            continue
        }
        #expect(url.absoluteString.contains("product=\(product)"))
        #expect(url.absoluteString.contains("os=osx"))
    }
}

// Signal stable — one-click resolves the UNIVERSAL dmg from the same latest-mac.yml
// we probe (not the per-arch zips), against updates.signal.org/desktop/. There is
// deliberately no checksum to assert: Signal staples the dmg after electron-builder
// writes the yml, so the feed's sha512 never matches the served bytes (see
// `signalRecipesCarryNoChecksum`). Per-channel filenames: see
// `signalInstallPatternsAreChannelSpecific`.
@Test func signalOneClickResolvesUniversalDmg() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.whispersystems.signal-desktop" })
    let body = """
    version: 8.14.0
    files:
      - url: signal-desktop-mac-x64-8.14.0.zip
        sha512: ZIPx64sha==
        size: 145932354
      - url: signal-desktop-mac-arm64-8.14.0.zip
        sha512: ZIParm64sha==
        size: 137665143
      - url: signal-desktop-mac-universal-8.14.0.dmg
        sha512: DMGuniversalSha512Value==
        size: 256425367
    path: signal-desktop-mac-x64-8.14.0.zip
    """
    let install = try #require(recipe.install)
    #expect(install.kind == .dmg)
    guard case let .bodyPatternRelative(pat, base) = install.urlSource else {
        Issue.record("expected bodyPatternRelative"); return
    }
    let fn = try #require(VendorProbeRecipe.extractVersion(from: body, pattern: pat))
    // Must grab the universal dmg, never the x64/arm64 zips.
    #expect(URL(string: fn, relativeTo: base)?.absoluteString
        == "https://updates.signal.org/desktop/signal-desktop-mac-universal-8.14.0.dmg")
}

// Obsidian — the manifest's own downloadUrl is an asar.gz we can't apply, so the
// one-click templates the GitHub release dmg from the STABLE latestVersion. The
// trap: a nested `beta` object carries a HIGHER latestVersion — the field regex
// (first match) must pick stable, or we'd ship a beta dmg to a stable install.
@Test func obsidianOneClickTemplatesStableDmgNotBeta() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "md.obsidian" })
    let body = """
    {"minimumVersion":"0.14.5","latestVersion":"1.12.7",\
    "downloadUrl":"https://github.com/obsidianmd/obsidian-releases/releases/download/v1.12.7/obsidian-1.12.7.asar.gz",\
    "beta":{"latestVersion":"1.13.1","downloadUrl":"https://releases.obsidian.md/release/obsidian-1.13.1.asar.gz"}}
    """
    let install = try #require(recipe.install)
    #expect(install.kind == .dmg)
    guard case let .bodyTemplate(template, fields) = install.urlSource else {
        Issue.record("expected bodyTemplate"); return
    }
    var filled = template
    for (i, pat) in fields.enumerated() {
        let v = try #require(VendorProbeRecipe.extractVersion(from: body, pattern: pat))
        filled = filled.replacingOccurrences(of: "{\(i)}", with: v)
    }
    #expect(filled
        == "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.12.7/Obsidian-1.12.7.dmg")
}

// Notion — one-click reuses the same /desktop/mac/download 307 the probe reads,
// HEAD-following it to the versioned universal dmg. Detection still uses
// followRedirects:false (reads the 307 itself) — the two must not be conflated.
@Test func notionOneClickRedirectsToDmg() throws {
    let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "notion.id" })
    #expect(recipe.followRedirects == false) // detection still reads the 307, not the 203MB body
    let install = try #require(recipe.install)
    #expect(install.kind == .dmg)
    guard case let .redirect(url) = install.urlSource else {
        Issue.record("expected redirect install"); return
    }
    #expect(url.absoluteString == "https://www.notion.so/desktop/mac/download")
}

// Batch 3 one-click wiring — verify each recipe's install URLSource resolves the
// RIGHT installer from a realistic body (the traps: stable-vs-beta keys, the
// ascending Orion feed's newest-last enclosure, macOS-vs-Windows in the Plex feed).
@Test func batch3OneClickInstallSourcesResolveCorrectly() throws {
    func recipe(_ id: String, channel: ReleaseChannel = .stable) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == id && $0.channel == channel })
    }
    func bodyPattern(_ r: VendorProbeRecipe) throws -> String {
        guard case let .bodyPattern(p) = try #require(r.install).urlSource else {
            Issue.record("\(r.bundleID): expected bodyPattern"); return ""
        }
        return p
    }

    // Cursor — downloadUrl dmg.
    let cursorBody = #"{"downloadUrl":"https://downloads.cursor.com/production/abc/darwin/arm64/Cursor-darwin-arm64.dmg","version":"3.7.42"}"#
    #expect(VendorProbeRecipe.extractVersion(from: cursorBody, pattern: try bodyPattern(try recipe("com.todesktop.230313mzl4w4u92")))
        == "https://downloads.cursor.com/production/abc/darwin/arm64/Cursor-darwin-arm64.dmg")

    // Raycast — downloadURL (proxy-wrapped presigned url, no literal quote inside).
    let rayBody = #"{"version":"1.104.19","downloadURL":"https://worker.raycast-releases.com/?url=https%3A%2F%2Fx.dmg%26X-Amz-Algorithm%3DAWS4"}"#
    #expect(VendorProbeRecipe.extractVersion(from: rayBody, pattern: try bodyPattern(try recipe("com.raycast.macos")))
        == "https://worker.raycast-releases.com/?url=https%3A%2F%2Fx.dmg%26X-Amz-Algorithm%3DAWS4")

    // Shottr — must grab "package", NOT "betaPackage".
    let shottrBody = #"{"betaPackage":"https://shottr.cc/dl/eap/Shottr-1.9.pkg","package":"https://shottr.cc/dl/Shottr-1.9.1.pkg"}"#
    #expect(VendorProbeRecipe.extractVersion(from: shottrBody, pattern: try bodyPattern(try recipe("cc.ffitch.shottr")))
        == "https://shottr.cc/dl/Shottr-1.9.1.pkg")

    // Element stable + nightly — nested updateTo.url zip from each feed's body.
    let elBody = #"{"currentRelease":"1.12.21","releases":[{"updateTo":{"url":"https://packages.element.io/desktop/update/macos/Element-1.12.21-universal-mac.zip"}}]}"#
    #expect(VendorProbeRecipe.extractVersion(from: elBody, pattern: try bodyPattern(try recipe("im.riot.app")))
        == "https://packages.element.io/desktop/update/macos/Element-1.12.21-universal-mac.zip")

    // Plex — MacOS universal zip, not the Windows installer that appears earlier.
    let plexBody = #"{"Windows":{"releases":[{"url":"https://downloads.plex.tv/plex-desktop/1.1/windows/Plex-Setup.exe"}]},"#
        + #""MacOS":{"version":"1.112.0","releases":[{"url":"https://downloads.plex.tv/plex-desktop/1.112.0.359-0d79a49f/macos/Plex-1.112.0.359-0d79a49f-universal.zip"}]}}"#
    #expect(VendorProbeRecipe.extractVersion(from: plexBody, pattern: try bodyPattern(try recipe("tv.plex.desktop")))
        == "https://downloads.plex.tv/plex-desktop/1.112.0.359-0d79a49f/macos/Plex-1.112.0.359-0d79a49f-universal.zip")

    // Orion — ASCENDING feed: install must take the LAST enclosure (newest), not first.
    let orionRecipe = try recipe("com.kagi.kagimacOS")
    guard case let .bodyPatternLast(orionPat) = try #require(orionRecipe.install).urlSource else {
        Issue.record("Orion: expected bodyPatternLast"); return
    }
    let orionBody = """
    <item><enclosure url="https://browser.kagi.com/updates/14_0/126.zip"/></item>
    <item><enclosure url="https://cdn.kagi.com/updates/26_0/147.zip"/></item>
    <item><enclosure url="https://cdn.kagi.com/updates/26_0/147.1.zip"/></item>
    """
    #expect(VendorProbeRecipe.lastMatch(from: orionBody, pattern: orionPat)
        == "https://cdn.kagi.com/updates/26_0/147.1.zip")
    // First-match would wrongly grab the oldest.
    #expect(VendorProbeRecipe.extractVersion(from: orionBody, pattern: orionPat)
        == "https://browser.kagi.com/updates/14_0/126.zip")

    // Slack + Discord stable use .redirect; just assert kind + that they're wired.
    if case .redirect = try #require(try recipe("com.tinyspeck.slackmacgap").install).urlSource {} else {
        Issue.record("Slack: expected redirect")
    }
    if case .redirect = try #require(try recipe("com.hnc.Discord").install).urlSource {} else {
        Issue.record("Discord: expected redirect")
    }
    #expect(try recipe("im.riot.nightly", channel: .nightly).install != nil)
}

// WeType (微信输入法) — reads the manifest the vendor's own stub installer reads.
//
// The real 2026-08-20 response of
// `z.weixin.qq.com/web/mac/download?channel=InstallInfo`, which 302s to a
// per-build `install_info_<ver>_<build>.json`.
private let weTypeInstallInfoFixture = #"""
{
  "zip_download_url": "https://download.weread.qq.com/app/wxkb/mac/2.2.3/WeType_2.2.3_657.zip",
  "zip_download_md5": "001fb418c7974c112bfc7ebbf47d483e",
  "zip_version": "2.2.3.657",
  "package_type": ""
}
"""#

@Test func weTypeReadsTheAppBuildNotTheInstallerStubs() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.tencent.inputmethod.wetype" })
    #expect(recipe.versionIsBuild)  // compared against CFBundleVersion, not 2.2.3
    #expect(recipe.url.absoluteString.contains("channel=InstallInfo"))

    // `zip_version` is major.minor.patch.build — the build is the LAST component,
    // and the marketing string is the first three. Splitting it the other way is
    // the whole bug this recipe used to have, in miniature.
    #expect(VendorProbeRecipe.extractVersion(
        from: weTypeInstallInfoFixture, pattern: recipe.versionPattern) == "657")
    let display = try #require(recipe.displayVersionPattern)
    #expect(VendorProbeRecipe.extractVersion(
        from: weTypeInstallInfoFixture, pattern: display) == "2.2.3")
}

/// What the previous recipe read, and why it was wrong — kept as a test so the
/// registry can never drift back to it.
///
/// It scraped `WeTypeInstaller_<x.y.z>_<build>_<letter>.zip` filenames off the
/// change-log page and treated that pair as the app's version. Those numbers
/// belong to the **installer stub**, which ships no payload: the stub in hand is
/// 2.2.0 (643) and installs 2.2.3 (657). The two schemes ran close enough to look
/// right, so nothing ever failed — the recipe just answered from the wrong
/// namespace, and only `remote is BEHIND the installed copy` in the nightly sweep
/// ever objected.
@Test func theInstallerStubFilenameIsNotTheAppVersion() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.tencent.inputmethod.wetype" })
    let oldPageBody = #"{"appInfo":{"mac":{"macwx_work_install_guide":"https://download.z.weixin.qq.com/app/mac/2.2.2/WeTypeInstaller_2.2.2_647_h.zip"}}}"#
    // The old source must no longer resolve to anything under the new pattern.
    #expect(VendorProbeRecipe.extractVersion(
        from: oldPageBody, pattern: recipe.versionPattern) == nil)
    #expect(!recipe.url.absoluteString.contains("change-log"))

    // The other trap the old recipe had to dodge, and that this endpoint removes
    // structurally: the change-log page lists every platform in one flat list
    // (`"platform":1`=iOS … `3`=macOS), so an unanchored highest-version pattern
    // takes iOS's number and reports a phantom update. The InstallInfo manifest
    // is macOS-only, so there is nothing to disambiguate.
    let flatList = """
    [{"id":120,"title":"x for iOS","version":"3.5.3","platform":1},\
    {"id":152,"title":"x for Mac","version":"2.2.2","platform":3}]
    """
    #expect(VendorProbeRecipe.highestVersion(
        from: flatList, pattern: #""version":"([0-9][^"]*)""#) == "3.5.3")
    #expect(VendorProbeRecipe.extractVersion(
        from: flatList, pattern: recipe.versionPattern) == nil)
}

/// Detection-only, and not for want of a download URL — the InstallInfo manifest
/// hands over the payload URL and its md5. The one-click shipped in 0.3.25 and was
/// withdrawn the same day after a user's WeType settings went missing, re-confirmed
/// 2026-08-20 by the vendor installer being run by hand. A bundle swap skips the
/// input-source registration and per-version migration the stub performs.
@Test func weTypeStaysDetectionOnlyAfterTheSettingsLoss() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.tencent.inputmethod.wetype" })
    #expect(recipe.install == nil)
    #expect(recipe.versionIsBuild)
    #expect(recipe.displayVersionPattern != nil)
    // The manifest does carry a usable payload URL — the reason to refuse is the
    // registration step, not a missing artifact.
    #expect(weTypeInstallInfoFixture.contains("WeType_2.2.3_657.zip"))
}

// Alcove — the old public endpoint (update.tryalcove.com) went NXDOMAIN, so the
// no-credential probe now reads download.tryalcove.com/latest. Real 2026-07-29
// response below (verbatim, 210 bytes). Two things this locks down:
//   1. the key is `version`, and the sibling `minimum_system_version` must never be
//      mistaken for it — hence the `{`/`,` anchor before the key;
//   2. it stays DETECTION-ONLY: the public dmg beside this metadata was still the
//      1.7.7 (199) trial build while /latest said 1.7.9, so an install spec would
//      install a version older than the one detected and strand the row on a
//      phantom "update available".
@Test func alcovePublicProbeReadsVersionNotMinimumSystemVersion() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.henrikruscon.Alcove" })
    #expect(recipe.url.absoluteString == "https://download.tryalcove.com/latest")
    #expect(recipe.install == nil)      // see (2) above — do not re-attach
    #expect(!recipe.versionIsBuild)     // `version` is marketing (== CFBundleShortVersionString)

    let body = #"{"version":"1.7.9","build":203,"published_at":"2026-06-30T20:57:57.000Z",""#
        + #""assets":[{"name":"Alcove.zip","size_bytes":15269999},{"name":"Alcove.dmg","size_bytes":16086914}],"#
        + #""minimum_system_version":"15 Sequoia"}"#
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == "1.7.9")

    // The `build` number must not leak into the compared value (203 > 1.7.9 would
    // be a permanent phantom update).
    #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) != "203")

    // Field order isn't guaranteed: even with a version-shaped minimum_system_version
    // listed first, the anchor keeps us on the real `version` key.
    let reordered = #"{"build":203,"minimum_system_version":"15.2.1","version":"1.8.0","assets":[]}"#
    #expect(VendorProbeRecipe.extractVersion(from: reordered, pattern: recipe.versionPattern) == "1.8.0")

    // Regression: the retired update.tryalcove.com shape (`tag_name`) finds nothing
    // here, which is exactly how the old recipe went silently blank.
    #expect(VendorProbeRecipe.extractVersion(
        from: body, pattern: #""tag_name"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#) == nil)
}
