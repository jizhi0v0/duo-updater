import Foundation

enum com_google_Chrome {
    static let set = AppRecipeSet(
        family: "com-google-Chrome",
        probes: [
        // History: docs/app-audits/com-google-Chrome.md#历史与实测
        // Google Chrome — official VersionHistory API (page_size=1, desc).
        //
        // All four channels install from Google's own permanent per-channel dmg
        // (`dl.google.com/chrome/mac/universal/<channel>/…`): each holds the matching
        // bundle id, Team EQHXZ8M8AV, notarized Developer ID, and a version in the
        // same 4-part form the API reports.
        //
        // Chrome self-updates through Keystone, which is NOT a reason to withhold
        // one-click — that is what `vendorInstallPolicy` is for, and its own settings
        // copy names Chrome. Keystone keeps managing whatever bundle is on disk; a
        // swap to a newer build does not confuse it. Under the default we install
        // over a running Chrome and restart it; picking "defer while running"
        // instead brings it forward to update itself.
        VendorProbeRecipe(
            bundleID: "com.google.Chrome",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            // Rollout-aware. The bare `versions` endpoint returns the newest build
            // that merely EXISTS — even at 0.5% rollout — so we'd lead Keystone and
            // show a phantom update (Chrome itself still says "up to date"). The
            // `releases` endpoint carries a `fraction` (0–1 rollout). Take the
            // highest version at fraction=1 (fully rolled out = what Keystone offers
            // everyone). `fraction` precedes `version` in each release object.
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg")!),
                kind: .dmg)),

        // Google Chrome — Beta / Dev / Canary channels. Each ships its OWN bundle
        // id (`com.google.Chrome.beta` / `.dev` / `.canary`) and is detected as
        // its own `ReleaseChannel`, so the channel gate routes each install to its
        // matching feed — a Beta install never gets the Stable version and vice
        // versa. Same rollout-aware `fraction:1` pattern as Stable (the
        // VersionHistory API is identical per channel; Canary publishes every
        // build at fraction 1). Each installs from its own permanent dmg — see the
        // Stable note above for why Keystone is not a reason to withhold that.
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.beta",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/beta/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/beta/googlechromebeta.dmg")!),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.dev",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/dev/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/dev/googlechromedev.dmg")!),
                kind: .dmg),
            channel: .dev),
        VendorProbeRecipe(
            bundleID: "com.google.Chrome.canary",
            url: URL(string: "https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/canary/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc")!,
            mode: .responseBody,
            versionPattern: #""fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            changelogURL: URL(string: "https://developer.chrome.com/release-notes"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://dl.google.com/chrome/mac/universal/canary/googlechromecanary.dmg")!),
                kind: .dmg),
            channel: .canary),
        ],
        changelogs: [
        // Google Chrome — Chrome has no single consumer changelog page; the
        // canonical "what changed" surface is the Chrome Releases blog (Blogger).
        // We fetch the *Stable updates* label page, which is server-rendered and
        // carries each post's full body inline inside a
        // `<script type='text/template'>` block (Blogger hydrates it client-side,
        // but the raw markup is complete). The label page mixes platforms
        // (Android / iOS / ChromeOS / Desktop), so the entryPattern requires the
        // exact post title `Stable Channel Update for Desktop` — that one literal
        // both selects the desktop posts AND excludes the Beta/Dev/Early/Extended
        // channels (whose titles differ: "Chrome Beta for Desktop Update",
        // "Early Stable Update for Desktop", etc.). Structure per post, e.g.:
        //   <a ... title='Stable Channel Update for Desktop'>…</a>
        //   <span class='publishdate' itemprop='datePublished'>Wednesday, May 27, 2026</span>
        //   <script type='text/template'>…post HTML…</script>
        // No version lives in the title or URL, so `version` is the first 4-part
        // build number in the body prose (e.g. 148.0.7778.216) — display-only and
        // low-stakes, so grabbing the first listed build is fine even though a post
        // lists Windows/Mac/Linux variants.
        //
        // Two item shapes, tried in order:
        //   1. CVE — security updates list each fix as inline spans (NOT <li>), e.g.:
        //      "[$reward][issue] Severity CVE-2026-9872: Out of bounds write in GPU."
        //      The CVE id + description sit together in one span's text, so anchor on
        //      the `CVE-YYYY-N:` literal and capture to the next tag.
        //   2. lead — promotion posts (no CVEs yet, "Security update coming shortly")
        //      have only prose; capture the announcement sentence ("…promotion of
        //      Chrome N to the stable channel" / "…has been updated to …"), using a
        //      tempered dot so it can't span past its own </p> into the boilerplate
        //      ("Interested in switching release channels?…") or the signature.
        // Security posts match CVE first (≥1 item) so the lead pattern never fires on
        // them; promotion posts fall through to lead. A parse miss just embeds the page.
        ChangelogRecipe(
            bundleID: "com.google.Chrome",
            source: URL(string: "https://chromereleases.googleblog.com/search/label/Stable%20updates")!,
            // Every gap here is written so that a FAILING match costs one pass, not
            // a combinatorial search. This pattern used to be four unbounded lazy
            // gaps (`.*?`) in a row, which is fine while the page still matches and
            // ruinous the day it stops — and a vendor restyle is exactly "it stops".
            // Every gap below is now either
            //
            //   • an atomic group `(?>…)` around a gap AND the literal that ends it,
            //     so once the first publishdate (then the first template opener)
            //     after the title is found, a later failure cannot send the engine
            //     back to look for another one; or
            //   • a lookahead, which is atomic in ICU: the version is located once,
            //     and a failure downstream cannot retry against the next
            //     version-shaped number in the body.
            //
            // `ChromeChangelogPatternTests` pins that fail-fast bound with a generated
            // page (the real one is too big to commit).
            //
            // What NOT to reach for here: `(?:…)*+` and `(?>(?:…)*)` over the BODY.
            // A possessive/atomic run silently stops matching past ~250 000
            // characters — measured: 100 000 matches, 250 000 does not, and the
            // failure is a quiet "no match", not an error. Chrome's post bodies run to
            // hundreds of KB, so that form can drop one and the pane loses an entry
            // with nothing anywhere saying so. The gaps below are atomic only across
            // spans of a few hundred characters, well under that limit.
            entryPattern:
                #"title='Stable Channel Update for Desktop'>"#
                + #"(?>(?:(?!<span class='publishdate').)*?"#
                + #"<span class='publishdate'[^>]*>\s*(?<date>[^<]+?)\s*</span>)"#
                + #"(?>(?:(?!<script type='text/template'>).)*?"#
                + #"<script type='text/template'>\s*)"#
                + #"(?=(?:(?!</script>).)*?(?<version>\d+\.\d+\.\d+\.\d+))"#
                + #"(?<body>(?:(?!</script>).)*?)</script>"#,
            itemPatterns: [
                #"(?<item>CVE-\d{4}-\d+:[^<]*)"#,
                #"<p[^>]*>(?<item>(?:(?!</p>).)*?(?:promotion of Chrome|been updated to)(?:(?!</p>).)*?)</p>"#,
            ],
            minItemLength: 8),
        ],
        channelProofs: [
        ChannelProofKey("com.google.Chrome.beta", .beta): .artifact(#"/beta/googlechromebeta\.dmg"#),
        ChannelProofKey("com.google.Chrome.dev", .dev): .artifact(#"/dev/googlechromedev\.dmg"#),
        ChannelProofKey("com.google.Chrome.canary", .canary): .artifact(#"/canary/googlechromecanary\.dmg"#),
        ])
}
