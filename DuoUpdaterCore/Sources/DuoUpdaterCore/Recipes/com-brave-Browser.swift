import Foundation

enum com_brave_Browser {
    static let set = AppRecipeSet(
        family: "com-brave-Browser",
        probes: [
        // History: docs/app-audits/com-brave-Browser.md#历史与实测
        // Brave Browser — Beta / Nightly. Sparkle appcast per channel and per ARCH.
        // Distinct bundle ids (`com.brave.Browser.beta` / `.nightly`) so the channel
        // gate routes each install to its own feed.
        //
        // COMPARE ON THE BUILD, not the marketing string. The feed's
        // `sparkle:shortVersionString` is Brave's own 4-part version (e.g. "1.94.104.0")
        // while the installed bundle reports a CHROMIUM-prefixed one
        // (e.g. "151.1.94.104"). Comparing those puts 1 against 151 and concludes the
        // installed copy is newer — so the row read "up to date" forever and Brave
        // Beta/Nightly could never surface an update. `sparkle:version` (e.g. "194.104")
        // is exactly the bundle's `CFBundleVersion`, so that's the pair that lines
        // up; `displayVersionPattern` keeps the human-readable string on screen.
        //
        // The `-arm64` feed is deliberate: the plain path serves x64 dmgs only
        // (`Brave-Browser-Beta-x64.dmg`). The two feeds are published separately and
        // are not always on the same build, so reading the arm64 feed keeps the
        // version and the artifact in one document. Team KL8N8XSYF4, notarized.
        VendorProbeRecipe(
            bundleID: "com.brave.Browser.beta",
            url: URL(string: "https://updates.bravesoftware.com/sparkle/Brave-Browser/beta-arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:version="([0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://brave.com/latest/")!,
            versionIsBuild: true,
            displayVersionPattern: #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://[^"]+Brave-Browser-Beta-arm64\.dmg)""#),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.brave.Browser.nightly",
            url: URL(string: "https://updates.bravesoftware.com/sparkle/Brave-Browser/nightly-arm64/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:version="([0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://brave.com/latest/")!,
            versionIsBuild: true,
            displayVersionPattern: #"sparkle:shortVersionString="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://[^"]+Brave-Browser-Nightly-arm64\.dmg)""#),
                kind: .dmg),
            channel: .nightly),
        ],
        channelProofs: [
        ChannelProofKey("com.brave.Browser.beta", .beta): .artifact(#"beta-arm64/.*Brave-Browser-Beta"#),
        ChannelProofKey("com.brave.Browser.nightly", .nightly): .artifact(#"nightly-arm64/.*Brave-Browser-Nightly"#),
        ])
}
