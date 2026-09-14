import Foundation

enum com_longbridge_app_desktop {
    static let set = AppRecipeSet(
        family: "com-longbridge-app-desktop",
        probes: [
        // MARK: - 2026-08-25 Longbridge Desktop

        // History: docs/app-audits/com-longbridge-app-desktop.md#历史与实测
        // Longbridge Desktop — the vendor's compact stable JSON is the same
        // manifest used by its release-notes site. `version` matches the mounted
        // app's CFBundleShortVersionString exactly (e.g. 0.19.1); CFBundleVersion is
        // a timestamp-like build (e.g. 20260820.080114) and must not be compared.
        //
        // The response carries both macOS architectures. DuoUpdater currently
        // runs this official-website install path on Apple Silicon, so the URL
        // pattern is deliberately pinned to `macos-aarch64.dmg` instead of taking
        // the first arbitrary dmg asset. Verified against the mounted 0.19.1
        // artifact: com.longbridge.app.desktop, Team 45NG8MW7WK, accepted by
        // Gatekeeper as Notarized Developer ID. The DMG is self-contained.
        VendorProbeRecipe(
            bundleID: "com.longbridge.app.desktop",
            url: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/stable/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,4})""#,
            downloadURL: URL(string: "https://longbridge.com/desktop/")!,
            changelogURL: URL(string: "https://longbridge.com/desktop/release-notes/")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://assets\.lbkrs\.com/github/release/longbridge-desktop/stable/longbridge-v[0-9.]+-macos-aarch64\.dmg)""#),
                kind: .dmg)),

        // Longbridge Desktop Preview — a SEPARATE bundle id
        // (`com.longbridge.app.desktop.preview`, "Longbridge Preview.app"), so
        // `ReleaseChannel.detect` resolves it via the `.preview` bundle-id suffix
        // and the two trains cannot be confused by bundle id alone.
        //
        // The channel's website presence has come and gone: `/desktop/preview/` has
        // been 404 when checked — no download landing page — and the preview
        // release-notes index has at times rendered an EMPTY version list while the per-version
        // notes pages, this manifest, and the artifacts stayed published (History
        // has both states). So a user who already runs Preview can be updated in
        // place even when the website offers no way to discover it. That is why
        // `changelogURL` points at the preview index rather than a version-specific
        // page: it is the right place conceptually, listed or not.
        //
        // Two structural differences from the stable manifest, both deliberate
        // here: the version carries a `-preview.N` suffix (so the pattern requires
        // it — the stable pattern's trailing quote cannot match this shape, and
        // this one cannot match stable's, verified both directions against the
        // live bodies), and preview assets have shipped WITHOUT the `sha256` field
        // stable includes (History). No checksum is asserted either way
        // (`checksumPattern` wants a base64 SHA-512), so that difference costs
        // nothing.
        //
        // The preview artifact is com.longbridge.app.desktop.preview, arm64,
        // Team 45NG8MW7WK — the SAME team as stable, which is what
        // `VendorInstaller`'s signature gate requires — notarized Developer ID.
        VendorProbeRecipe(
            bundleID: "com.longbridge.app.desktop.preview",
            url: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/latest.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,4}-preview\.[0-9]+)""#,
            changelogURL: URL(string: "https://longbridge.com/desktop/release-notes/preview/")!,
            publishedAtPattern: #""published_at"\s*:\s*"([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""url"\s*:\s*"(https://assets\.lbkrs\.com/github/release/longbridge-desktop/preview/longbridge-v[0-9.]+-preview\.[0-9]+-macos-aarch64\.dmg)""#),
                kind: .dmg),
            channel: .preview),
        ],
        changelogs: [
        // Longbridge Desktop — use the English per-version page rather than the
        // compact latest.json notes: the page carries the richer release body and
        // some releases interleave screenshots with their change lines. Stop at
        // Downloads so installer links never become changelog items.
        //
        // `<video>` terminates an item because it is the one element whose INNER
        // text would otherwise survive `stripTags` and land in the notes as
        // "Your browser does not support the video tag."; the native changelog
        // model has no video block, so the element itself is dropped.
        // `<img>` deliberately does NOT terminate an item. It is a void tag with
        // no text, `stripTags` removes it regardless, and `imagePattern` collects
        // images from the whole body independently of item boundaries — so the
        // boundary added nothing and could only truncate. With it, a bullet whose
        // illustration came FIRST captured an empty item, lost it to
        // `minItemLength`, and resumed scanning past its own text: the entire line
        // disappeared. Longbridge puts media last on every page today, so this was
        // latent, not live — the regression test pins the other ordering.
        // The path serves English with no locale prefix and does NOT content-
        // negotiate (verified under `Accept-Language: zh-CN` and `zh-HK`), so the
        // literal `Release Date:` anchor is stable for every user.
        //
        // `source` is the releases INDEX, used only when no version is supplied.
        // It must not be a per-version page: that page parses perfectly, so the
        // no-version fallback would render one pinned release's notes as if they
        // described whatever build the user actually has. The index carries no
        // `Release Date:` block, so it correctly yields nothing and the UI falls
        // back to the embedded web page — which is the same assumption
        // `Verify.sweepChangelog` relies on when it skips version-templated
        // recipes that have no version to resolve.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop",
            source: URL(string: "https://longbridge.com/desktop/release-notes/")!,
            entryPattern:
                #"<div[^>]*class="vp-doc[^"]*"[^>]*>\s*<div>\s*<h1[^>]*>\s*v?(?<version>[0-9]+(?:\.[0-9]+)+).*?</h1>\s*<p>\s*<em>\s*Release Date:\s*(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\s*</em>\s*</p>(?<body>.*?)(?=<h2[^>]*id="downloads")"#,
            itemPatterns: [
                #"<(?:li|p)\b[^>]*>(?<item>.*?)(?=<video\b|</(?:li|p)>)"#,
            ],
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://longbridge.com/desktop/release-notes/v{version}",
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#),

        // Longbridge Desktop Preview — separate bundle id, separate URL subtree
        // (`/release-notes/preview/v<version>`), same page structure as stable.
        //
        // The version group REQUIRES the `-preview.N` suffix. Reusing stable's
        // group here would be a silent mis-read rather than a miss: on this page
        // it matches and stops at the numeric part (e.g. `0.19.0`), dropping the suffix, so the pane would
        // label a preview build with the stable version number it is not. Anchored
        // this way the two patterns are mutually exclusive — verified in both
        // directions against the live pages.
        //
        // `source` is the preview index. Like stable's, it has carried no
        // `Release Date:` block whether or not it listed any versions (History),
        // which makes it
        // a correct no-version fallback for the same reason: it yields nothing and
        // the UI embeds the page instead of inventing an entry.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop.preview",
            source: URL(string: "https://longbridge.com/desktop/release-notes/preview/")!,
            entryPattern:
                #"<div[^>]*class="vp-doc[^"]*"[^>]*>\s*<div>\s*<h1[^>]*>\s*v?(?<version>[0-9]+(?:\.[0-9]+)+-preview\.[0-9]+).*?</h1>\s*<p>\s*<em>\s*Release Date:\s*(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\s*</em>\s*</p>(?<body>.*?)(?=<h2[^>]*id="downloads")"#,
            itemPatterns: [
                #"<(?:li|p)\b[^>]*>(?<item>.*?)(?=<video\b|</(?:li|p)>)"#,
            ],
            maxEntries: 1,
            channel: .preview,
            sourceTemplate: "https://longbridge.com/desktop/release-notes/preview/v{version}",
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#),
        ],
        channelProofs: [
        // Longbridge splits the two trains by CDN path — `/longbridge-desktop/
        // preview/` vs `/stable/` — and the artifact filename carries the
        // `-preview.N` suffix on top of that, so the URL names the channel twice.
        // Unusually for a copied-from-stable recipe, the two manifests cannot even
        // match each other's version pattern (stable's requires a closing quote
        // straight after the numeric version; preview's requires the suffix), so a
        // cross-train resolve fails closed rather than silently succeeding.
        ChannelProofKey("com.longbridge.app.desktop.preview", .preview):
            .artifact(#"/longbridge-desktop/preview/"#),
        ],
        changelogPages: [
        // Longbridge Desktop — the structured recipe follows the exact version
        // page. Keep the English release-notes index as a web fallback while an
        // update result or a freshly added recipe has not populated yet.
        "com.longbridge.app.desktop": URL(string: "https://longbridge.com/desktop/release-notes/")!,
        ])
}
