import Foundation

enum com_workbuddy_workbuddy_ai {
    static let set = AppRecipeSet(
        family: "com-workbuddy-workbuddy-ai",
        probes: [
        // History: docs/app-audits/com-workbuddy-workbuddy-ai.md#历史与实测
        // WorkBuddy ships as TWO separate apps, not two channels of one. Tencent
        // runs an international site and a China site, each with its own bundle
        // id, its own app name, its own update host and its own release train:
        //
        //   com.workbuddy.workbuddy-ai  "WorkBuddy AI.app"  www.workbuddy.ai
        //   com.workbuddy.workbuddy     "WorkBuddy.app"     www.workbuddy.cn
        //
        // Both are Electron, both signed by Team FN2V63AD2J (Tencent Technology
        // (Shanghai) Company Limited), and the two builds carry byte-identical
        // updater code — so the ONLY thing that routes an install to its own train
        // is the bundle id, which is exactly the key a recipe is looked up by.
        // Nothing here is a `channel`: both trains are stable, and neither app can
        // ever be handed the other's artifact.
        //
        // The endpoint is the one the app's own `AbstractUpdateService` calls:
        // `<base>/v2/update?platform=workbuddy-{os}-{arch}&version=<installed>`,
        // where `<base>` is the product's API endpoint and defaults to
        // `copilot.tencent.com` (which answers identically to www.workbuddy.cn).
        // No auth: the `x-user-id` / `x-tenant-id` parameters the app appends are
        // optional and we send neither.
        //
        // TRAP, and the reason `version=0.0.0` is pinned into the URL: this is a
        // "should I update?" service, not a "what is the latest?" one. Passing the
        // version you already run returns **204 No Content** (measured 2026-08-27
        // on both hosts; History has the versions sent), which would
        // make the probe go dark precisely when it should say "up to date". An
        // impossibly old version is what turns it into a latest-version query.
        //
        // TRAP, version scheme: the endpoint reports a FOUR-segment string
        // (e.g. "5.4.2.36857725") whose last segment is a build counter that appears
        // NOWHERE in the installed bundle — both `CFBundleShortVersionString` and
        // `CFBundleVersion` are the bare "5.4.2". Comparing the raw field would
        // read 36857725 > (nothing) forever, the permanent phantom update
        // `versionIsBuild` exists to prevent — but `versionIsBuild` is the wrong
        // fix here, since the build counter is not the app's CFBundleVersion
        // either. So capture group 1 takes only the first three segments and the
        // fourth is matched-and-discarded. Consequence to accept knowingly: a
        // vendor respin that bumps ONLY the build counter is invisible to us.
        // The optional fourth segment keeps the pattern matching if the vendor
        // ever drops back to a plain three-part version.
        //
        // Architecture: the endpoint serves both Macs and answered the same version
        // to each when checked (2026-08-27, 2026-09-14), but the `url` it hands
        // back is arch-specific (`/darwin-arm64/…` vs
        // `/darwin-x64/…`). Hence one recipe per architecture, split by
        // `hostRequirement` rather than by channel (the Raycast v1/v2 shape) so
        // exactly one is eligible on any given Mac — `VendorProbeSource` drops a
        // recipe whose architectures do not include `HostArch.current`, so on the
        // arm64 Macs DuoUpdater runs on (`App/project.yml`, `ARCHS: arm64`) the
        // x86_64 recipe is never consulted. The install pattern is additionally
        // pinned to its own `darwin-<arch>` path so a recipe cannot resolve the
        // other arch's artifact even if the endpoint were to start ignoring the
        // query.
        //
        // Sites: the two recipes are one helper apart, and BOTH CDN paths are
        // `/workbuddy/saas/darwin-<arch>/`, so the path alone does not say which
        // site an artifact came from. Each recipe therefore pins its own download
        // host as well. Without that, a later edit that swaps a host — or a vendor
        // that points one site's `/v2/update` at the other site's CDN — would have
        // one-click quietly replace a WorkBuddy AI install with the China build,
        // and nothing downstream could see it: same vendor, same Team, a real
        // notarized bundle, so the signature gate passes, and `ChannelProofRegistry`
        // does not apply because both recipes are `.stable`. Pinned, the same
        // situation degrades loudly instead (`installURLUnresolved`, which the
        // nightly `duo verify` sweep reports).
        //
        // One-click: the JSON's `url` is a plain, unsigned object on Tencent COS
        // (intl: `codebuddy-1328495429.cos.accelerate.myqcloud.com`; CN:
        // `download.codebuddy.cn`). The `sha256hash` field alongside it is a
        // SHA-256 hex digest, which `checksumPattern` (SHA-512, base64) cannot
        // consume, so it is left unused and Team FN2V63AD2J gates the swap
        // (History has the dated check of both vendor DMGs).
        //
        // Changelog: each site's page is the one the app itself links (the build
        // branches on `isOverseas()`); the intl page has run behind its own train
        // (History has the versions), which is what the intl ChangelogRecipe's
        // `acknowledgedStaleEntry` is for — see
        // `Recipes/com-workbuddy-workbuddy.swift`.
        VendorProbeRegistry.workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy-ai", host: "www.workbuddy.ai",
            assetHost: "codebuddy-1328495429.cos.accelerate.myqcloud.com", arch: .arm64,
            downloadURL: URL(string: "https://www.workbuddy.ai/")!,
            changelogURL: URL(string: "https://www.workbuddy.ai/docs/workbuddy/Changelog")!),
        VendorProbeRegistry.workBuddyRecipe(
            bundleID: "com.workbuddy.workbuddy-ai", host: "www.workbuddy.ai",
            assetHost: "codebuddy-1328495429.cos.accelerate.myqcloud.com", arch: .x86_64,
            downloadURL: URL(string: "https://www.workbuddy.ai/")!,
            changelogURL: URL(string: "https://www.workbuddy.ai/docs/workbuddy/Changelog")!),
        ],
        changelogs: [
        ChangelogRecipe(
            bundleID: "com.workbuddy.workbuddy-ai",
            source: URL(string: "https://www.workbuddy.ai/docs/workbuddy/Changelog")!,
            entryPattern: ChangelogRecipeRegistry.workBuddyEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            acknowledgedStaleEntry: "5.2.7"),
        ])
}
