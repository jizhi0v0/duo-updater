import Foundation

enum com_jetbrains_intellij {
    static let set = AppRecipeSet(
        family: "com-jetbrains-intellij",
        probes: [
        // History: docs/app-audits/com-jetbrains-intellij.md#历史与实测
        // IntelliJ IDEA — JetBrains data services. The `YYYY.` prefix is what keeps
        // this off the 2-component `majorVersion` field; the segment count must NOT
        // be pinned: JetBrains ships four-component versions too (e.g.
        // `"version": "2026.2.0.1"`). Accept one to three segments after the
        // year. Only consulted when Toolbox isn't managing it (a website install);
        // the same JSON carries the aarch64 DMG direct link, so we install in place.
        // No inline sha256 (the API gives only a checksum *link*), so we lean on the
        // mandatory Team ID signature gate — same posture as VLC's DMG. Apple
        // Silicon (macM1) only.
        VendorProbeRecipe(
            bundleID: "com.jetbrains.intellij",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]{4}(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://www.jetbrains.com/idea/whatsnew/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""macM1"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg)),

        // IntelliJ IDEA EAP — same data services API on the `eap` channel. The EAP
        // marketing "version" stays the same (e.g. "2026.2") across many builds, so
        // comparing it would never detect a build bump; we compare on the `build`
        // (e.g. 262.x) via `versionIsBuild`. The installed bundle's CFBundleVersion
        // is prefixed (e.g. "IU-262.6653.22") while the API build is bare (e.g.
        // "262.7132.23") — `UpdateChecker` strips the product-code prefix so they
        // compare in one namespace. `channel: .preview` matches the `-EAP` bundle id (see
        // ReleaseChannel). Like stable, only consulted when Toolbox isn't managing
        // this copy.
        VendorProbeRecipe(
            bundleID: "com.jetbrains.intellij-EAP",
            url: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=eap")!,
            mode: .responseBody,
            versionPattern: #""build"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://www.jetbrains.com/idea/whatsnew/"),
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""macM1"\s*:\s*\{[^}]*?"link"\s*:\s*"([^"]+\.dmg)""#),
                kind: .dmg),
            channel: .preview),
        ],
        changelogs: [
        // IntelliJ IDEA — same JetBrains data-services API as Toolbox (`IIU`
        // product code, stable releases only via `type=release`). Structured decode
        // (`StructuredChangelogDecoder.decodeJetBrainsProductReleases`): the old
        // regex path read `whatsnew` as raw JSON-escaped text, where an embedded
        // `\n` is a two-character escape a hand-written item pattern can silently
        // mis-anchor on (the ChatWise-class bug this decoder family exists to avoid).
        // `Decodable` unescapes the JSON string for us, so the decoder walks real
        // HTML instead: `whatsnew` is a lead `<p>` summary then `<ul><li>` bullets,
        // and only the `<li>` bullets count as discrete changes — the lead `<p>`
        // is boilerplate ("IntelliJ IDEA X is out with…"). A hotfix release with no
        // `<li>` at all (its content is plain `<p>` prose, or just a pointer to the
        // release notes) yields zero items and is skipped, same as the regex did.
        ChangelogRecipe(
            bundleID: "com.jetbrains.intellij",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&type=release")!,
            maxEntries: 20,
            structuredFormat: .jetBrainsProductReleases),
        ],
        channelProofs: [
        // EAP dmgs are named `idea-<build>-aarch64.dmg` — the same shape stable
        // uses, so the filename proves nothing. The endpoint does: `type=eap` vs
        // stable's `type=release`, and the install pattern reads the dmg out of
        // that response body.
        //
        // `url` alone, and that is the honest scope rather than a weaker one: the
        // response to `type=eap` contains ONLY EAP builds, so `versionPattern`
        // (`"build": "…"`) and the install pattern (`"macM1" … "link"`) carry no
        // channel token at all. Naming either would assert something this recipe
        // cannot satisfy. (The install pattern is byte-identical to the stable
        // recipe's; the version pattern is NOT — stable reads `"version"` and this
        // reads `"build"`, because `versionIsBuild` compares the build. That
        // difference is deliberate and says nothing about the channel.)
        // What naming `url` buys is that swapping the endpoint back to
        // `type=release` fails the proof instead of passing on patterns that never
        // mentioned a channel.
        ChannelProofKey("com.jetbrains.intellij-EAP", .preview):
            .recipeAnchor(#"type=eap"#, in: ["url"]),
        ])
}
