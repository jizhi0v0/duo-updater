import Foundation

enum org_mozilla_firefox {
    static let set = AppRecipeSet(
        family: "org-mozilla-firefox",
        probes: [
        // Firefox — `product-details` carries Release and ESR. Beta, Developer
        // Edition and Nightly are NOT readable there and go to Mozilla's own
        // update service instead; see the block above those three recipes.
        // Release, Beta and ESR all ship as
        // `org.mozilla.firefox`; the channel is told apart by `application.ini`
        // RemotingName (`firefox`/`firefox-beta`/`firefox-esr` — see
        // `ReleaseChannel`), NOT the version suffix, because the installed
        // `CFBundleShortVersionString` DROPS the `b`/`esr` (verified on real
        // bundles 2026-06-04: Beta reports `152.0`, ESR `140.11.0`). So three
        // recipes share that bundle id and are picked by the install's detected
        // channel. Developer Edition (`org.mozilla.firefoxdeveloperedition`,
        // RemotingName `firefox-dev`) and Nightly (`org.mozilla.nightly`) have
        // their own ids. Where `product-details` IS the source (Release, ESR) the
        // captured version keeps the feed's `esr` form: it sorts as a pre-release
        // (never phantoms against the suffix-less install) while a real bump still
        // compares newer. One-click: identical mechanism to
        // Thunderbird — `download.mozilla.org/?product=…-latest&os=osx` 302→ the
        // per-channel `.dmg` (verified 2026-06-17: firefox-latest 152.0,
        // -beta-latest 152.0b10, -esr-latest 140.12.0esr, -devedition-latest
        // 152.0b10, -nightly-latest 154.0a1). All Mozilla-signed (Team `43AQ936H96`),
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
        // all called `157.0a1`, so a ~4-week cycle produced exactly zero update
        // notices. (Measured 2026-08-30 against real bundles; the beta half was
        // recorded as an accepted limitation on 2026-06-04, the nightly half was
        // never noticed because "remote == installed" had been written down as a
        // *good* sign — no phantom updates — without taking the next step.)
        //
        // The bundle does carry a per-build number — `CFBundleVersion` is
        // `<major><yy>.<month>.<day>`, `15526.8.26` for 155.0b5 — but no Mozilla
        // endpoint publishes it, so it cannot be the comparison key. What both
        // sides DO share is `application.ini`'s `BuildID`: the app's own updater
        // asks `aus5.mozilla.org` (the URL is in `application.ini` itself, under
        // `[AppUpdate]`) and that service answers with the same `BuildID`, byte
        // for byte. Verified 2026-08-30 on all five channels by unpacking the
        // official dmg and diffing against the live response:
        //
        //     FF beta        20260826090609    FF dev  20260826090609
        //     FF nightly     20260829211045    TB beta 20260826184332
        //     TB daily       20260829100815
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
        // failure. Measured constraints on the anchor (2026-08-30):
        //
        //   • The version must be at or above Mozilla's newest *watershed*.
        //     `ver=124.0` is answered with the 125.0 Beta 9 watershed build;
        //     `125.0` and everything above gets the current one. Nightly has no
        //     watershed (`90.0a1` still gets today's build).
        //   • The build id must be newer than roughly 2023-01-15 — below that AUS
        //     answers nothing, on every channel, regardless of version.
        //   • The OS version does not affect the answer (`Darwin 20`…`27` all
        //     agree), and there is no throttling: 10 identical requests, 10
        //     identical answers.
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
        // 120.0a1 rather than the current 157.0a1 for that reason (nightly has no
        // watershed at all — 90.0a1 still gets today's build).
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
        channelProofs: [
        // MARK: Mozilla
        // The installed bundles hide their channel (`CFBundleShortVersionString`
        // drops the `b`/`esr` suffix — see `ReleaseChannel.detect`), but the
        // download paths do not: Beta sits under a `<major>.0b<N>` release dir, ESR
        // under an `esr` one, Developer Edition under `/devedition/`, Nightly under
        // `/nightly/`. Firefox Beta and Developer Edition resolve the SAME upstream
        // version (154.0b8), so only the `/devedition/` vs `/firefox/` path tells
        // them apart — which is exactly why the marker is a path, not a version.
        ChannelProofKey("org.mozilla.firefox", .beta): .artifact(#"/firefox/releases/[0-9.]+b[0-9]+/"#),
        ChannelProofKey("org.mozilla.firefox", .esr): .artifact(#"/firefox/releases/[0-9.]+esr/"#),
        ChannelProofKey("org.mozilla.firefoxdeveloperedition", .dev): .artifact(#"/devedition/releases/"#),
        ChannelProofKey("org.mozilla.nightly", .nightly): .artifact(#"/firefox/nightly/"#),
        ])
}
