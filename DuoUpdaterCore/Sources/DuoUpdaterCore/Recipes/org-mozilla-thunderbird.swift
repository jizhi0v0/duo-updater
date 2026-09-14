import Foundation

enum org_mozilla_thunderbird {
    static let set = AppRecipeSet(
        family: "org-mozilla-thunderbird",
        probes: [
        // History: docs/app-audits/org-mozilla-thunderbird.md#历史与实测
        // Shared rationale for Mozilla pre-release channels: Recipes/org-mozilla-firefox.swift.

        // Thunderbird — same Mozilla `product-details` mechanism for Release and
        // ESR; Beta and Daily go to `aus.thunderbird.net` for the same reason the
        // Firefox pre-release channels do (see that block). Channel routing
        // is by `application.ini` RemotingName (see `ReleaseChannel`), NOT the
        // version suffix: the installed `CFBundleShortVersionString` DROPS the
        // `b`/`esr` suffix (verified on real bundles 2026-06-04). Bundle ids differ
        // per channel — Release & ESR share `org.mozilla.thunderbird`, Beta is
        // `org.mozilla.thunderbirdbeta`, Daily is `org.mozilla.thunderbird-daily`.
        // The `product-details` probes still capture the feed's full `esr` form: it
        // sorts as a pre-release (< the suffix-less installed version) so it never
        // phantoms; a real bump (140.11.1→140.12.0esr) still compares newer.
        // One-click: Mozilla's `download.mozilla.org/?product=…-latest&os=osx`
        // 302-redirects to the per-channel `.dmg` on its CDN (checked for all four
        // product codes 2026-06-17; History has the versions). Every channel is
        // signed by Mozilla Corporation (Team `43AQ936H96`), so the VendorInstaller
        // same-Team gate is satisfied and fails closed if Mozilla ever rotates.
        // Best-effort in-place dmg swap on top of Thunderbird's own self-updater.
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_THUNDERBIRD_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-latest&os=osx&lang=en-US")!),
                kind: .dmg)),
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbirdbeta",
            url: URL(string: "https://aus.thunderbird.net/update/6/Thunderbird/155.0/20250101000000/Darwin_aarch64-gcc3/en-US/beta/Darwin%2025.0.0/default/default/default/update.xml")!,
            mode: .responseBody,
            versionPattern: #"buildID="([0-9]{14})""#,
            downloadURL: URL(string: "https://www.thunderbird.net/channel/desktop/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            versionIsBuild: true,
            buildNamespace: .vendor,
            displayVersionPattern:
                #"product=thunderbird-([0-9][0-9.]*b[0-9]+)-complete"#,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-beta-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird",
            url: URL(string: "https://product-details.mozilla.org/1.0/thunderbird_versions.json")!,
            mode: .responseBody,
            versionPattern: #""THUNDERBIRD_ESR"\s*:\s*"([0-9]+(?:\.[0-9]+)+esr)""#,
            downloadURL: URL(string: "https://www.thunderbird.net/enterprise/"),
            changelogURL: URL(string: "https://www.thunderbird.net/thunderbird/releases/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-esr-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .esr),
        // Daily/Nightly has NO changelogURL on purpose: thunderbird.net publishes
        // no nightly release notes (every /<ver>/releasenotes/ 404s) and no
        // ChangelogRecipe can target it, so pointing changelogURL at the *stable*
        // releases index would embed an unrelated stable page for a nightly user.
        // Leaving it nil makes the detail pane show the honest "No release notes"
        // empty state (with a download link) instead — better than a wrong page.
        VendorProbeRecipe(
            bundleID: "org.mozilla.thunderbird-daily",
            url: URL(string: "https://aus.thunderbird.net/update/6/Thunderbird/120.0a1/20250101000000/Darwin_aarch64-gcc3/en-US/nightly/Darwin%2025.0.0/default/default/default/update.xml")!,
            mode: .responseBody,
            versionPattern: #"buildID="([0-9]{14})""#,
            downloadURL: URL(string: "https://www.thunderbird.net/channel/desktop/"),
            versionIsBuild: true,
            buildNamespace: .vendor,
            displayVersionPattern: #"displayVersion="([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=thunderbird-nightly-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .nightly),
        ],
        changelogs: [
        // ── Thunderbird (Mozilla) — one product, four channels, but only THREE
        // bundle ids: Stable and ESR BOTH ship as `org.mozilla.thunderbird`
        // (the install short-version drops the `esr` suffix, and the channel is
        // only knowable from `application.ini` RemotingName — see ReleaseChannel /
        // AppScanner). So Stable and ESR are distinguished here by the recipe
        // `channel` field; `recipe(forBundleID:channel:)` is given the install's
        // detected channel and picks the matching train. Nightly/Daily
        // (`org.mozilla.thunderbird-daily`) publishes NO structured release-notes
        // page (every /<ver>/releasenotes/ 404s — auto-builds have no curated
        // notes), so it has no recipe and keeps the web-view fallback.
        //
        // Every channel's per-version notes page shares one structure:
        //   <h4>Version 151.0 | Released May 19, 2026</h4>
        //   <h3 class="header-section">What’s New</h3>          ← section labels (ignored)
        //   <div id="note-0" class="note-container"><div class="note-flex">
        //     <h4 class="note-category">…new/changed/fixed…</h4>
        //     <div class="note-text"><p>change text…</p></div></div></div>
        // Each page is ONE version, so maxEntries:1; body runs to end of doc and
        // the item patterns only ever match `note-text`, so the footer is ignored.

        // Thunderbird Stable — version-templated. Each release has its own page
        // (`/<version>/releasenotes/`) and there is no inline multi-version page or
        // "latest" alias, so we substitute the app's target version into
        // `sourceTemplate` and fetch exactly that build's page — the rendered
        // version then always matches what the user has/​is offered (151.0.1, not
        // the 151.0 major), with no pin to bump. `source` is the releases index,
        // used only as a fallback if no version is ever supplied. Each page is one
        // version → maxEntries:1.
        ChangelogRecipe(
            bundleID: "org.mozilla.thunderbird",
            source: URL(string: "https://www.thunderbird.net/en-US/thunderbird/releases/")!,
            entryPattern:
                #"<h[1-6][^>]*>\s*Version\s+(?<version>[^<|]+?)\s*\|\s*Released\s+(?<date>[^<]+?)\s*</h[1-6]>"#
                + #"(?<body>.*)"#,
            itemPatterns: [
                #"<div class="note-text">\s*<p>(?<item>.*?)</p>"#,
                #"<div class="note-text">\s*(?<item>.*?)\s*</div>"#,
            ],
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://www.thunderbird.net/en-US/thunderbird/{version}/releasenotes/"),

        // Thunderbird ESR — SAME bundle id as Stable, matched by `channel: .esr`,
        // same per-version template. The install's short version is stripped of the
        // `esr` suffix (140.11.1), but the notes page is `/140.11.1esr/…`, so
        // `resolvedSource` re-appends `esr` for this channel (see
        // `urlVersionToken`). This keeps ESR's shown version consistent with the
        // install on both the steady state (installed == latest) and when an ESR
        // security update is offered.
        ChangelogRecipe(
            bundleID: "org.mozilla.thunderbird",
            source: URL(string: "https://www.thunderbird.net/en-US/thunderbird/140.0/releasenotes/")!,
            entryPattern:
                #"<h[1-6][^>]*>\s*Version\s+(?<version>[^<|]+?)\s*\|\s*Released\s+(?<date>[^<]+?)\s*</h[1-6]>"#
                + #"(?<body>.*)"#,
            itemPatterns: [
                #"<div class="note-text">\s*<p>(?<item>.*?)</p>"#,
                #"<div class="note-text">\s*(?<item>.*?)\s*</div>"#,
            ],
            maxEntries: 1,
            channel: .esr,
            sourceTemplate: "https://www.thunderbird.net/en-US/thunderbird/{version}/releasenotes/"),

        // Thunderbird Beta — its own bundle id (`org.mozilla.thunderbirdbeta`),
        // version-templated like the others. The notes URL is keyed by MAJOR, not
        // build: `/152.0beta/releasenotes/` is one cumulative page for the whole
        // 152 beta cycle (b1→b2→…, several "What’s Fixed" sections under one
        // "152.0beta" heading). `urlVersionToken` drops the bN build suffix and
        // appends "beta" (152.0 / 152.0b3 → 152.0beta), so the template
        // auto-tracks the current cycle with no pin to bump. `source` is one
        // fixed cycle's page (152.0beta), used as a fallback only.
        ChangelogRecipe(
            bundleID: "org.mozilla.thunderbirdbeta",
            source: URL(string: "https://www.thunderbird.net/en-US/thunderbird/152.0beta/releasenotes/")!,
            entryPattern:
                #"<h[1-6][^>]*>\s*Version\s+(?<version>[^<|]+?)\s*\|\s*Released\s+(?<date>[^<]+?)\s*</h[1-6]>"#
                + #"(?<body>.*)"#,
            itemPatterns: [
                #"<div class="note-text">\s*<p>(?<item>.*?)</p>"#,
                #"<div class="note-text">\s*(?<item>.*?)\s*</div>"#,
            ],
            maxEntries: 1,
            channel: .beta,
            sourceTemplate: "https://www.thunderbird.net/en-US/thunderbird/{version}/releasenotes/"),
        ],
        channelProofs: [
        // Shared rationale for Mozilla (channel proofs): Recipes/org-mozilla-firefox.swift.
        ChannelProofKey("org.mozilla.thunderbirdbeta", .beta): .artifact(#"/thunderbird/releases/[0-9.]+b[0-9]+/"#),
        ChannelProofKey("org.mozilla.thunderbird", .esr): .artifact(#"/thunderbird/releases/[0-9.]+esr/"#),
        ChannelProofKey("org.mozilla.thunderbird-daily", .nightly): .artifact(#"/thunderbird/nightly/"#),
        ])
}
