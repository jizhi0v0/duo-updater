import Foundation

enum dev_warp_Warp_Stable {
    static let set = AppRecipeSet(
        family: "dev-warp-Warp-Stable",
        probes: [
        // History: docs/app-audits/dev-warp-Warp-Stable.md#历史与实测
        // Warp — Preview / Dev. One JSON lists every channel's version, each tagged
        // with the channel name in its suffix (`…preview_01`), so a per-channel
        // pattern is unambiguous. Channels ship as separate bundle ids
        // (`dev.warp.Warp-Preview`, …) — the Stable build is the existing
        // `dev.warp.Warp-Stable` recipe below. Both capture groups matter: the app
        // reports the feed's `v<stamp>.<channel>_NN` as `<stamp>.NN`, so the
        // counter is joined back on (see `VendorProbeRecipe.version(of:in:)`).
        // Confirmed against real bundles on all three tracks — including dev's
        // `_00`, which the app does spell out as a trailing `.00`. (The record of
        // that check was never tracked in git; the audit's channel-verify section,
        // `docs/app-audits/dev-warp-Warp-Stable.md`, covers the three tracks.)
        //
        // PREVIEW installs one-click; DEV deliberately does not. `app.warp.dev/
        // download?package=dmg&channel=preview` really does serve WarpPreview.app
        // (dev.warp.Warp-Preview, Team 2BBY89MBSN, notarized, version matching the
        // JSON; checked 2026-08-09). The same URL with `channel=dev` ignores the
        // parameter and hands back **Warp.app / dev.warp.Warp-Stable** — wiring that
        // would install Stable over a Dev install, the cross-channel swap the whole
        // channel gate exists to prevent. Note the Content-Type on both is
        // `text/html` despite the body being a disk image of a few hundred MB;
        // don'"'"'t trust it.
        //
        // The JSON still lists `beta` and `canary`, but Warp abandoned both tracks
        // (beta froze at 2024-12, canary at 2022-09 — see 2026-06-04 audit), so we
        // carry NO recipe for them: probing would only ever surface a years-stale
        // "latest", worse than the clean "unknown" an installed Warp-Beta/Canary
        // now gets. Bundle-id-suffix detection still tags such an install for the
        // UI; it just has no version source.
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Preview",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.preview_([0-9]+)""#,
            changelogURL: URL(string: "https://docs.warp.dev/changelog"),
            install: VendorInstallSpec(
                urlSource: .fixed(
                    URL(string: "https://app.warp.dev/download?package=dmg&channel=preview")!),
                kind: .dmg),
            channel: .preview),
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Dev",
            url: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"v([0-9.]+)\.dev_([0-9]+)""#,
            downloadURL: URL(string: "https://www.warp.dev/download"),
            changelogURL: URL(string: "https://docs.warp.dev/changelog"),
            channel: .dev),

        // Warp — GitHub releases carry NO binary asset; the real dmg lives on
        // Warp's CDN. `app.warp.dev/download?package=dmg` returns a tiny HTML page
        // linking the current `releases.warp.dev/stable/v<ver>/Warp.dmg` (always
        // latest). Version + download both come from that one page. Team 2BBY89MBSN.
        // (Note: its URL build can lead the GitHub tag by a few hours — the CDN is
        // the more accurate source, so Warp lives here, not in GitHubReleaseRegistry.)
        VendorProbeRecipe(
            bundleID: "dev.warp.Warp-Stable",
            url: URL(string: "https://app.warp.dev/download?package=dmg")!,
            mode: .responseBody,
            versionPattern: #"releases\.warp\.dev/stable/v([0-9.]+)\.stable_([0-9]+)"#,
            changelogURL: URL(string: "https://docs.warp.dev/changelog/2026/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://releases\.warp\.dev/stable/[^"]+\.dmg)"#),
                kind: .dmg),
            // GET 302s straight to the full dmg — DON'T follow; read the small
            // redirect body, whose href carries both the version and the dmg URL.
            followRedirects: false),
        ],
        changelogs: [
        // Warp — read the machine-readable feed, not the docs site. When this
        // recipe moved (mid-2026), docs.warp.dev sat behind a Vercel "Security
        // Checkpoint" JS bot wall that returned HTTP 429 + a challenge page to any
        // non-browser fetch, so the old Starlight-HTML scrape (year-pinned
        // `/changelog/2026/`) went dark; a 2026-09-14 recheck got plain 200s
        // (History has it). `releases.warp.dev/channel_versions.json` is the same
        // ungated endpoint the vendor probe already uses and carries a full
        // per-channel, per-version `changelogs` map (date + markdown sections) —
        // richer and far more stable than scraping rendered HTML. One recipe per
        // channel; both point at the same JSON but the `channel` selects the
        // sub-feed (and gives each its own cache slot — see `ChangelogService`).
        // The entries are NOT in
        // newest-first document order in the JSON, so the structured decoder sorts
        // by the (lexically-chronological) version key — hence not a regex recipe.
        //
        // Stable and Preview only. There is deliberately **no Dev recipe**: Warp
        // ships a real `dev.warp.Warp-Dev` build and the probe tracks its version
        // fine, but the vendor publishes no notes for that track. `changelogs.dev`
        // holds exactly one entry — and it is fixture data, unchanged for years
        // (when checked, 2026-08-09 and 2026-09-14):
        //   "v0.2026.08.07.08.31.dev_00": { "date": "2021-11-23T10:07:01-06:00",
        //     "sections": [ { "title": "dev", "items": ["dev 1", "dev 2"] } ],
        //     "oz_updates": ["[TEST] Testing Oz recent updates!", …] }
        // The version key tracks the live dev build, but the body is placeholder
        // text under a 2021 date, and it uses the pre-2022 `sections` shape rather
        // than the `markdown_sections` every real entry has had since. Surfacing
        // "dev 1 / dev 2" under the installed dev version would be worse than
        // nothing, so Warp-Dev carries no recipe and falls back to embedding
        // docs.warp.dev/changelog — same call, and the same reasoning, as the
        // VendorProbe declining to probe the abandoned beta/canary tracks.
        ChangelogRecipe(
            bundleID: "dev.warp.Warp-Stable",
            source: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .warpChannelVersions),
        ChangelogRecipe(
            bundleID: "dev.warp.Warp-Preview",
            source: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            maxEntries: 20,
            channel: .preview,
            structuredFormat: .warpChannelVersions),
        ],
        channelProofs: [
        ChannelProofKey("dev.warp.Warp-Preview", .preview): .artifact(#"channel=preview"#),
        ])
}
