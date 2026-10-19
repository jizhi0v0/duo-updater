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
        //
        // The download is checked against the hex `sha256` the manifest gives
        // that same asset, on top of the Team-ID gate. The checksum pattern takes
        // the object holding the first stable aarch64 dmg filename — the asset the
        // URL pattern reads — whatever the key order inside it; if that object
        // carries no `sha256` it matches nothing (Team-ID only,
        // `checksumPatternNoMatch` in `duo verify`) rather than the x86_64 or
        // linux asset's digest.
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
                kind: .dmg,
                checksumPattern:
                    #"\A(?:(?!longbridge-v[0-9.]+-macos-aarch64\.dmg)[\s\S])*?\{(?=[^{}]*"url"\s*:\s*"https://assets\.lbkrs\.com/github/release/longbridge-desktop/stable/longbridge-v[0-9.]+-macos-aarch64\.dmg")[^{}]*?"sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex)),

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
        // place even when the website offers no way to discover it. `changelogURL`
        // still names the preview index although that URL now redirects to the
        // Longbridge Pro product listing (see the preview changelog below).
        //
        // Two structural differences from the stable manifest, both deliberate
        // here: the version carries a `-preview.N` suffix (so the pattern requires
        // it — the stable pattern's trailing quote cannot match this shape, and
        // this one cannot match stable's, verified both directions against the
        // live bodies), and preview assets have shipped WITHOUT the `sha256` field
        // stable includes (History). The checksum pattern is stable's, re-anchored
        // on the preview aarch64 asset: when that asset carries a `sha256` the
        // download is checked against it, and when it doesn't (as on 0.19.0-preview.1)
        // the pattern matches nothing and the install is Team-ID gated only — it
        // never borrows another asset's digest.
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
                kind: .dmg,
                checksumPattern:
                    #"\A(?:(?!longbridge-v[0-9.]+-preview\.[0-9]+-macos-aarch64\.dmg)[\s\S])*?\{(?=[^{}]*"url"\s*:\s*"https://assets\.lbkrs\.com/github/release/longbridge-desktop/preview/longbridge-v[0-9.]+-preview\.[0-9]+-macos-aarch64\.dmg")[^{}]*?"sha256"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex),
            channel: .preview),
        ],
        changelogs: [
        // History: docs/app-audits/com-longbridge-app-desktop.md#历史与实测
        // Longbridge Desktop — the English release page for the installed minor
        // line, not the compact latest.json notes: the page carries the richer
        // release body and some releases interleave screenshots with their change
        // lines. The vendor serves one page per MINOR line (`…/longbridge-pro/v0.19`;
        // the unprefixed `…/0.19` is a 200 meta-refresh stub with no sections)
        // holding every patch release in it, each in a `release-section` carrying its
        // own `data-rail-version` and `data-rail-date`; the entry pattern takes the
        // first section, which is the newest on that page. A section ends at its
        // own `</section>`, so no entry can run into the next one.
        //
        // The entry body starts at `div.prose`: the `<p>` summary above it repeats
        // the first change line and would otherwise be read as one.
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
        // The `/en/` pages serve English for every user, so the `data-rail-*`
        // attributes the entry pattern reads are the same in every locale.
        //
        // `source` is the releases INDEX, used only when no version is supplied.
        // It must not be a per-version page: that page parses perfectly, so the
        // no-version fallback would render one pinned release's notes as if they
        // described whatever build the user actually has. The index carries no
        // `release-section`, so it correctly yields nothing and the UI falls
        // back to the embedded web page — which is the same assumption
        // `Verify.sweepChangelog` relies on when it skips version-templated
        // recipes that have no version to resolve.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop",
            source: URL(string: "https://longbridge.com/desktop/release-notes/")!,
            entryPattern:
                #"<section id="v[^"]*" class="release-section"[^>]*\bdata-rail-version="(?<version>[0-9]+(?:\.[0-9]+)+)"[^>]*\bdata-rail-date="(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})"[^>]*>(?:(?!</section>).)*?<div class="prose[^"]*">(?<body>(?:(?!</section>).)*?)</section>"#,
            itemPatterns: [
                #"<(?:li|p)\b[^>]*>(?<item>.*?)(?=<video\b|</(?:li|p)>)"#,
            ],
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://longbridge.com/en/changelog/longbridge-pro/v{majorMinor}",
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#),

        // Longbridge Desktop Preview — no HTML page to read any more. The vendor's
        // preview release-notes URLs (`/desktop/release-notes/preview/` and
        // `…/preview/v<version>`) now redirect to the Longbridge Pro product listing,
        // which carries no preview build; the preview manifest is the only place the
        // preview notes are still published. So this reads the manifest's
        // `release_notes.en` through `StructuredChangelogDecoder`. The decoder
        // returns the manifest's own version (the newest preview build), so it has
        // no per-version URL to resolve and no `sourceTemplate`.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop.preview",
            source: URL(string: "https://assets.lbkrs.com/github/release/longbridge-desktop/preview/latest.json")!,
            mode: .json,
            channel: .preview,
            structuredFormat: .longbridgeDesktopManifest),
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
