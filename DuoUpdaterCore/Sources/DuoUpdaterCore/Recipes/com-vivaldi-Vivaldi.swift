import Foundation

enum com_vivaldi_Vivaldi {
    static let set = AppRecipeSet(
        family: "com-vivaldi-Vivaldi",
        probes: [
        // Vivaldi — Snapshot (preview) track. Sparkle appcast on the `snapshot`
        // channel. Independent bundle id (`com.vivaldi.Vivaldi.snapshot`) so the
        // channel gate routes it automatically. `sparkle:shortVersionString` carries
        // the marketing version (e.g. "8.1.4063.3"), and here it equals the bundle's
        // CFBundleShortVersionString exactly — no scheme mismatch to work around,
        // unlike the Brave feeds above.
        //
        // One-click verified 2026-08-09 on 8.2.4126.4: the enclosure is a universal
        // `.tar.xz` holding `Vivaldi Snapshot.app`, bundle id
        // com.vivaldi.Vivaldi.snapshot, Team 4XF3XNRN6Y, spctl "Notarized Developer
        // ID". `.tarGz` covers xz — see the ImageOptim note.
        //
        // DEAD FOR DETECTION, kept as a sweep anchor — same as Bartender and
        // ImageOptim. Measured on the real 8.2.4133.31 bundle (2026-08-31): it
        // declares `SUFeedURL = https://update.vivaldi.com/update/1.0/snapshot/mac/
        // appcast.xml`, this exact address, so Sparkle answers first.
        VendorProbeRecipe(
            bundleID: "com.vivaldi.Vivaldi.snapshot",
            url: URL(string: "https://update.vivaldi.com/update/1.0/snapshot/mac/appcast.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)</sparkle:shortVersionString>"#,
            changelogURL: URL(string: "https://vivaldi.com/blog/desktop/")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<enclosure[^>]*url="(https://downloads\.vivaldi\.com/[^"]+\.tar\.xz)""#),
                kind: .tarGz),
            channel: .preview),
        ],
        channelProofs: [
        ChannelProofKey("com.vivaldi.Vivaldi.snapshot", .preview): .artifact(#"/snapshot-auto/"#),
        ])
}
