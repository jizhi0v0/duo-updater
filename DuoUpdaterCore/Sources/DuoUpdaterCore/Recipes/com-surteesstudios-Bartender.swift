import Foundation

enum com_surteesstudios_Bartender {
    static let set = AppRecipeSet(
        family: "com-surteesstudios-Bartender",
        probes: [
        // History: docs/app-audits/com-surteesstudios-Bartender.md#历史与实测
        // Bartender — Sparkle appcast (ascending, oldest-first). Version lives in
        // sparkle:shortVersionString on each <item>. selectHighest because the feed
        // lists items oldest-first.
        //
        // DEAD FOR DETECTION, kept as a sweep anchor. The app's bundle declares
        // `SUFeedURL = https://www.macbartender.com/B2/updates/AppcastB6.xml`, the
        // same address as below (read from a real bundle on 2026-08-31; History
        // has the hedge that settled), so `SparkleAppcastSource` answers first and
        // this recipe never runs in production. It stays because `duo verify`
        // sweeps the recipe registries and nothing sweeps Sparkle feeds — deleting
        // the row would leave the endpoint unwatched. Do not "fix" this by
        // re-pointing it.
        VendorProbeRecipe(
            bundleID: "com.surteesstudios.Bartender",
            url: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            mode: .responseBody,
            versionPattern: #"<sparkle:shortVersionString>([0-9]+\.[0-9]+\.[0-9]+)</sparkle:shortVersionString>"#,
            changelogURL: URL(string: "https://www.macbartender.com/B2/updates/AppcastB6.xml")!,
            selectHighest: true,
            // `bodyPatternLast`, not `bodyPattern`: this appcast is ASCENDING, so the
            // first enclosure is 6.0.0 and the newest is the final one — the same
            // reason `selectHighest` is set for the version. Taking the first match
            // would install a two-year-old build over a current one.
            //
            // (Note the older entries are served from macbartender.com and the
            // recent ones from downloads.macbartender.com — the pattern accepts
            // either host.)
            install: VendorInstallSpec(
                urlSource: .bodyPatternLast(
                    #"<enclosure[^>]*url="(https://[^"]*macbartender\.com/[^"]+\.zip)""#),
                kind: .zip)),
        ])
}
