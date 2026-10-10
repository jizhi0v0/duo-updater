import Foundation

enum org_mozilla_firefox {
    static let set = AppRecipeSet(
        family: "org-mozilla-firefox",
        probes: [
        // History: docs/app-audits/org-mozilla-firefox.md#历史与实测
        // Firefox — `product-details` carries Release and ESR. Beta, Developer
        // Edition and Nightly are NOT readable there and go to Mozilla's own
        // update service instead; see the block above those three recipes.
        // Release, Beta and ESR all ship as
        // `org.mozilla.firefox`; the channel is told apart by `application.ini`
        // RemotingName (`firefox`/`firefox-beta`/`firefox-esr` — see
        // `ReleaseChannel`), NOT the version suffix, because the installed
        // `CFBundleShortVersionString` DROPS the `b`/`esr` (checked on real Beta and
        // ESR bundles 2026-06-04; History has the versions). So three
        // recipes share that bundle id and are picked by the install's detected
        // channel. Developer Edition (`org.mozilla.firefoxdeveloperedition`,
        // RemotingName `firefox-dev`) and Nightly (`org.mozilla.nightly`) have
        // their own ids. Where `product-details` IS the source (Release, ESR) the
        // captured version keeps the feed's `esr` form: it sorts as a pre-release
        // (never phantoms against the suffix-less install) while a real bump still
        // compares newer. One-click: identical mechanism to
        // Thunderbird — `download.mozilla.org/?product=…-latest&os=osx` 302→ the
        // per-channel `.dmg` (checked for all five product codes 2026-06-17; History
        // has the versions). All Mozilla-signed (Team `43AQ936H96`),
        // so VendorInstaller's same-Team gate is satisfied / fails closed. Note Dev
        // Edition's product code is `firefox-devedition-latest` (its dmg lives under
        // /pub/devedition/, not /pub/firefox/).
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""LATEST_FIREFOX_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-latest&os=osx&lang=en-US")!),
                kind: .dmg)),
        // ── Mozilla pre-release channels: `aus5.mozilla.org` / `aus.thunderbird.net`
        //
        // Beta, Developer Edition and Nightly cannot be tracked from
        // `product-details` at all, and the reason is on the DISK side, not the
        // feed's. An installed Firefox beta reports `CFBundleShortVersionString`
        // = "155.0" for the whole cycle — the `b5` is stripped — so a feed that
        // says "155.0b5" is measured against "155.0" and the tokenizer ranks the
        // pre-release BELOW the release: `isNewer` is false for every build of
        // the cycle. Nightly is worse: Mozilla ships one EVERY DAY and they are
        // all called `157.0a1`, so a ~4-week cycle gives exactly zero update
        // notices (checked 2026-08-30 against real bundles; History has how both
        // halves went unnoticed before that).
        //
        // The bundle does carry a per-build number — `CFBundleVersion` is
        // `<major><yy>.<month>.<day>`, `15526.8.26` for 155.0b5 — but no Mozilla
        // endpoint publishes it, so it cannot be the comparison key. What both
        // sides DO share is `application.ini`'s `BuildID`: the app's own updater
        // asks `aus5.mozilla.org` (the URL is in `application.ini` itself, under
        // `[AppUpdate]`) and that service answers with the same `BuildID`, byte
        // for byte (checked 2026-08-30 on all five channels by unpacking the
        // official dmg and diffing against the live response; History has the
        // build ids).
        //
        // So these five recipes (Firefox beta, Developer Edition and Nightly in this
        // file; Thunderbird beta and Daily in `Recipes/org-mozilla-thunderbird.swift`)
        // are `versionIsBuild` in the `.vendor` namespace —
        // compared against `InstalledApp.vendorBuildVersion`, never against
        // `CFBundleVersion` — with `displayVersion` carrying Mozilla's own human
        // string ("155.0 Beta 5") for the row.
        //
        // **The URL is a fixed anchor, and that is deliberate.** AUS is a
        // *conditional* endpoint: it answers "what is newer than the version and
        // build you name", so passing this machine's own build would make an empty
        // `<updates></updates>` mean "you are current" — and the same empty
        // response in a sweep, which has no installed app, would mean "broken".
        // One response shape, two meanings, is how a check goes quietly dead.
        // With a frozen anchor every user and the nightly sweep send the SAME
        // request, an answer is always expected, and empty is unambiguously a
        // failure. The anchor has to meet these constraints (measured 2026-08-30;
        // History has the requests and answers):
        //
        //   • The version must be at or above Mozilla's newest *watershed*: below
        //     it, AUS answers with the watershed build rather than the current
        //     one. Nightly has no watershed.
        //   • The build id must be newer than a floor, which sat well below this
        //     anchor's 2025-01-01 when measured — below the floor AUS answers
        //     nothing, on every channel, regardless of version.
        //   • The OS version does not affect the answer, and there is no
        //     throttling: identical requests get identical answers.
        //
        // Both anchors decay eventually — a new watershed above 155.0, or the
        // build-id floor rising past 2025. **Both decay modes are caught**, and
        // that is why a frozen anchor is safe: a watershed answers with an OLD
        // build id and a risen floor answers with nothing, so either way the value
        // `duo verify` records goes DOWN and the baseline flags a regression. That
        // is not true of the marketing anchor this replaced, which is what made
        // the same idea unusable before.
        //
        //
        // The row keeps saying "155.0b5", not Mozilla's own `displayVersion`
        // ("155.0 Beta 5"), and that is load-bearing rather than taste: the beta
        // changelog recipes template their URL off this string
        // (`ChangelogRecipe.urlVersionToken` turns `155.0b5` into `155.0beta`), so
        // the prose form 404s the release notes. Beta and Developer Edition take
        // it out of the `<patch>` download URL, which spells it the way the rest
        // of the app already does; Nightly's `displayVersion` is `157.0a1`
        // already, so it uses that attribute directly.
        //
        // The five recipes' anchors are set so the answer can never be a copy of the
        // question: `RecipeSanity` warns when an extracted version appears
        // verbatim in the request URL, which is exactly the shape a pattern
        // matching the URL instead of the body would take. Nightly is anchored at
        // 120.0a1 rather than the current nightly version for that reason (nightly
        // has no watershed at all, so an older version still gets today's build;
        // History has the measurement).
        // Thunderbird's `application.ini` names `aus.thunderbird.net`, which 302s
        // to the same path on `aus5.mozilla.org`. We follow Thunderbird's own host
        // rather than short-cutting to the redirect target: if the two ever
        // diverge, the app's URL is the one that stays right.
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://aus5.mozilla.org/update/6/Firefox/155.0/20250101000000/Darwin_aarch64-gcc3/en-US/beta/Darwin%2025.0.0/default/default/default/update.xml")!,
            mode: .responseBody,
            versionPattern: #"buildID="([0-9]{14})""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/channel/desktop/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/beta/notes/"),
            versionIsBuild: true,
            buildNamespace: .vendor,
            displayVersionPattern:
                #"product=firefox-([0-9][0-9.]*b[0-9]+)-complete"#,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-beta-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .beta),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefox",
            url: URL(string: "https://product-details.mozilla.org/1.0/firefox_versions.json")!,
            mode: .responseBody,
            versionPattern: #""FIREFOX_ESR"\s*:\s*"([0-9]+(?:\.[0-9]+)+esr)""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/enterprise/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/organizations/notes/"),
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-esr-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .esr),
        VendorProbeRecipe(
            bundleID: "org.mozilla.firefoxdeveloperedition",
            url: URL(string: "https://aus5.mozilla.org/update/6/Firefox/155.0/20250101000000/Darwin_aarch64-gcc3/en-US/aurora/Darwin%2025.0.0/default/default/default/update.xml")!,
            mode: .responseBody,
            versionPattern: #"buildID="([0-9]{14})""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/developer/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/beta/notes/"),
            versionIsBuild: true,
            buildNamespace: .vendor,
            displayVersionPattern:
                #"product=devedition-([0-9][0-9.]*b[0-9]+)-complete"#,
            // Developer Edition tracks the Beta train (version is a `bN`) but has
            // its own bundle id and RemotingName `firefox-dev`, so the detector
            // classifies it `.dev` — the channel its recipe must target.
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-devedition-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .dev),
        VendorProbeRecipe(
            bundleID: "org.mozilla.nightly",
            url: URL(string: "https://aus5.mozilla.org/update/6/Firefox/120.0a1/20250101000000/Darwin_aarch64-gcc3/en-US/nightly/Darwin%2025.0.0/default/default/default/update.xml")!,
            mode: .responseBody,
            versionPattern: #"buildID="([0-9]{14})""#,
            downloadURL: URL(string: "https://www.mozilla.org/firefox/channel/desktop/"),
            changelogURL: URL(string: "https://www.mozilla.org/firefox/nightly/notes/"),
            versionIsBuild: true,
            buildNamespace: .vendor,
            displayVersionPattern: #"displayVersion="([^"]+)""#,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://download.mozilla.org/?product=firefox-nightly-latest&os=osx&lang=en-US")!),
                kind: .dmg),
            channel: .nightly),
        ],
        changelogs: [
        // History: docs/app-audits/org-mozilla-firefox.md#历史与实测
        // ── Firefox (Mozilla) — five channels, three bundle ids, one page per
        // version on firefox.com (www.mozilla.org/…/releasenotes/ 301s there), the
        // same model as Thunderbird's recipes: `sourceTemplate` takes the offered
        // (else installed) version, so the notes always match the row, with no pin.
        // Release, Beta and ESR share `org.mozilla.firefox` and are told apart by
        // `channel` (RemotingName, see the probes above).
        //
        // Every channel's page has the same shape:
        //   <h2 class="c-release-summary …">
        //     <span class="c-release-version …">157.0.1</span>
        //     <span class="c-release-product …">Firefox Release</span></h2>
        //   <p class="c-release-date …">October 6, 2026</p>
        //   … <li class="release-note" id="note-792283">
        //       <div class="release-note-content"><p>change text…</p></div></li>
        // The date is optional (a not-yet-released version's page has none). One
        // page is one version, so maxEntries:1 and the body runs to the end of the
        // document. Items are anchored on a NUMERIC note id: the page also lists
        // `id="note-mdn"`, a bare "Developer Information" link, which is not a change.
        //
        // The `source` of each is the channel's "latest notes" alias, which
        // redirects to the current version's page; it is only the fallback when no
        // version is supplied.

        // Release: the page is the plain version, `/157.0.1/`.
        ChangelogRecipe(
            bundleID: "org.mozilla.firefox",
            source: URL(string: "https://www.firefox.com/en-US/firefox/notes/")!,
            entryPattern: firefoxEntryPattern,
            itemPatterns: firefoxItemPatterns,
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://www.firefox.com/en-US/firefox/{version}/releasenotes/"),

        // Beta: one cumulative page per cycle, `/158.0beta/`, exactly Thunderbird
        // Beta's form, so `{version}` with `channel: .beta` already maps both the
        // offered `158.0b5` and the installed `158.0` there (`urlVersionToken`).
        // `/158.0b5/` is a 404. The entry's version is the page's own `158.0beta`.
        ChangelogRecipe(
            bundleID: "org.mozilla.firefox",
            source: URL(string: "https://www.firefox.com/en-US/firefox/beta/notes/")!,
            entryPattern: firefoxEntryPattern,
            itemPatterns: firefoxItemPatterns,
            maxEntries: 1,
            channel: .beta,
            sourceTemplate: "https://www.firefox.com/en-US/firefox/{version}/releasenotes/"),

        // ESR: firefox.com drops the `esr` suffix once the ESR's minor is past 0
        // (`/140.17.0/`, and `/140.17.0esr/` is a 404) but keeps it on `140.0esr`,
        // whose number Release also has. Thunderbird keeps the suffix throughout,
        // so this uses the `{firefoxVersion}` placeholder rather than `{version}`
        // (see `ChangelogRecipe.firefoxVersionToken`).
        ChangelogRecipe(
            bundleID: "org.mozilla.firefox",
            source: URL(string: "https://www.firefox.com/en-US/firefox/organizations/notes/")!,
            entryPattern: firefoxEntryPattern,
            itemPatterns: firefoxItemPatterns,
            maxEntries: 1,
            channel: .esr,
            sourceTemplate: "https://www.firefox.com/en-US/firefox/{firefoxVersion}/releasenotes/"),

        // Developer Edition is built from the Beta cycle and has no notes of its
        // own: firefox.com's `/firefox/developer/notes/` redirects to the Beta
        // page. Its channel is `.dev`, which `urlVersionToken` passes through
        // unchanged (`158.0b5`), so the template builds the Beta form itself from
        // the first two components: `{majorMinor}beta` → `158.0beta`.
        ChangelogRecipe(
            bundleID: "org.mozilla.firefoxdeveloperedition",
            source: URL(string: "https://www.firefox.com/en-US/firefox/developer/notes/")!,
            entryPattern: firefoxEntryPattern,
            itemPatterns: firefoxItemPatterns,
            maxEntries: 1,
            channel: .dev,
            sourceTemplate: "https://www.firefox.com/en-US/firefox/{majorMinor}beta/releasenotes/"),

        // Nightly: one page per nightly version, `/160.0a1/`, which is both the
        // probe's display version and the bundle's short version, so `{version}`
        // as is. Every nightly build of a cycle shares the page; Mozilla updates it
        // as features land.
        ChangelogRecipe(
            bundleID: "org.mozilla.nightly",
            source: URL(string: "https://www.firefox.com/en-US/firefox/nightly/notes/")!,
            entryPattern: firefoxEntryPattern,
            itemPatterns: firefoxItemPatterns,
            maxEntries: 1,
            channel: .nightly,
            sourceTemplate: "https://www.firefox.com/en-US/firefox/{version}/releasenotes/"),
        ],
        channelProofs: [
        // MARK: Mozilla
        // The installed bundles hide their channel (`CFBundleShortVersionString`
        // drops the `b`/`esr` suffix — see `ReleaseChannel.detect`), but the
        // download paths do not: Beta sits under a `<major>.0b<N>` release dir, ESR
        // under an `esr` one, Developer Edition under `/devedition/`, Nightly under
        // `/nightly/`. Firefox Beta and Developer Edition resolve the SAME upstream
        // version (e.g. 154.0b8), so only the `/devedition/` vs `/firefox/` path tells
        // them apart — which is exactly why the marker is a path, not a version.
        ChannelProofKey("org.mozilla.firefox", .beta): .artifact(#"/firefox/releases/[0-9.]+b[0-9]+/"#),
        ChannelProofKey("org.mozilla.firefox", .esr): .artifact(#"/firefox/releases/[0-9.]+esr/"#),
        ChannelProofKey("org.mozilla.firefoxdeveloperedition", .dev): .artifact(#"/devedition/releases/"#),
        ChannelProofKey("org.mozilla.nightly", .nightly): .artifact(#"/firefox/nightly/"#),
        ])

    /// Shared by all five Firefox changelog recipes: every channel's notes page
    /// is the same template (see the comment over `changelogs`).
    private static let firefoxEntryPattern =
        #"<span class="c-release-version[^"]*"[^>]*>\s*(?<version>[^<]+?)\s*</span>\s*"#
        + #"<span class="c-release-product[^"]*"[^>]*>[^<]*</span>\s*</h2>\s*"#
        + #"(?:<p class="c-release-date[^"]*"[^>]*>\s*(?<date>[^<]+?)\s*</p>)?"#
        + #"(?<body>.*)"#
    private static let firefoxItemPatterns = [
        #"<li class="release-note" id="note-\d+">\s*<div class="release-note-content">\s*(?<item>.*?)\s*</div>\s*</li>"#,
    ]
}
