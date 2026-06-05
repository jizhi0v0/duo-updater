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
    #expect(VendorProbeRecipe.extractVersion(
        from: fixture,
        pattern: #"stable\.dl2\.discordapp\.net/distro/app/stable/osx/universal/([0-9]+\.[0-9]+\.[0-9]+)/"#) == "0.0.393")
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

@Test func microsoftOutlookProbeExtractsVersionFromXML() {
    // Outlook uses the Office AutoUpdate XML manifest which carries the version
    // in <key>Update Version</key><string>...</string>.
    let fixture = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Payload</key>
      <dict>
        <key>Update Version</key>
        <string>16.109.26053122</string>
        <key>Update Version Location</key>
        <string>https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Microsoft_Outlook_16.109.26053122_Installer.pkg</string>
      </dict>
    </dict>
    </plist>
    """#
    let pattern = #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#
    #expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "16.109.26053122")
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
