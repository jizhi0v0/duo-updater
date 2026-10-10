import Foundation

enum com_exafunction_windsurf {
    static let set = AppRecipeSet(
        family: "com-exafunction-windsurf",
        probes: [
        // History: docs/app-audits/com-exafunction-windsurf.md#历史与实测
        // Devin Desktop (formerly Windsurf) — official stable update JSON. The
        // `windsurfVersion` field is the app's own marketing/build version;
        // `productVersion` is the upstream VS Code base and must never be parsed.
        // com.exafunction.windsurf, Team 83Z2LHX6XW, notarized.
        //
        // ONE-CLICK via `.bodyPattern`: the same response carries the finished
        // installer link (`"url": "…/Devin-darwin-arm64-<version>.dmg"`), so the
        // url and the version come out of one document — nothing to template and
        // nothing to order. The pattern requires the `.dmg` suffix so it cannot
        // drift onto some other absolute URL if the vendor adds a field.
        //
        // Detection is not architecture-neutral: the probe URL is
        // `/api/update/darwin-arm64-dmg/…` and the response's own `displayName` is
        // "macOS for Apple Silicon (.dmg)". The endpoint already picks the
        // architecture; there is no second choice for an install spec to make, and
        // this app is arm64-only anyway (`App/project.yml`).
        //
        // The download is checked against the response's `sha256hash` (hex), the
        // digest of the dmg the same response names, on top of the Team gate.
        VendorProbeRecipe(
            bundleID: "com.exafunction.windsurf",
            url: URL(string: "https://windsurf-stable.codeium.com/api/update/darwin-arm64-dmg/stable/latest")!,
            mode: .responseBody,
            versionPattern: #"\"windsurfVersion\"\s*:\s*\"([0-9]+(?:\.[0-9]+)+)\""#,
            downloadURL: URL(string: "https://devin.ai/desktop"),
            // The old `windsurf.com/editor/releases/` 308s to `/editor/releases`,
            // which 308s here; point at the destination, as the recipe below does.
            changelogURL: URL(string: "https://docs.devin.ai/desktop/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"\"url\"\s*:\s*\"(https://[^\"]+\.dmg)\""#),
                kind: .dmg,
                checksumPattern: #""sha256hash"\s*:\s*"([0-9a-f]{64})""#,
                checksumFormat: .sha256Hex)),
        ],
        changelogs: [
        // History: docs/app-audits/com-exafunction-windsurf.md#历史与实测
        // Devin Desktop's changelog at docs.devin.ai/desktop/changelog, a Mintlify
        // page of `<Update>` blocks, newest first. Each block is a
        // `data-component-part="update-label"` button ("v3.10.48"), an
        // `update-description` div holding the date, and an `update-content` div
        // with the notes, which ends at a "Download 3.10.48" `<details>`.
        //
        //   * The label is the bare version the update JSON's `windsurfVersion`
        //     reports, behind a `v`.
        //   * The gaps between label, date and content are tempered so they can't
        //     cross into the next block's label: a block missing its date or
        //     content does not match rather than borrowing the next one's.
        //   * Notes are `<li>` lines and `<span data-as="p">` paragraphs (the
        //     Markdown paragraphs), read by ONE pattern so they keep their order.
        //     A paragraph that is nothing but `<strong>` ("Devin Desktop",
        //     "Devin Cloud") is a section label, not a note: the item pattern
        //     skips it and `headingPattern` keeps it as a heading, together with
        //     the real `<h1>`–`<h3>` headings older blocks use. A heading's text is
        //     the last text run before its close, after Mintlify's anchor icon and
        //     its zero-width space.
        //   * Image paragraphs (`<span data-as="p">` around a zoomable `<img>`)
        //     strip to nothing and are dropped.
        ChangelogRecipe(
            bundleID: "com.exafunction.windsurf",
            source: URL(string: "https://docs.devin.ai/desktop/changelog")!,
            entryPattern:
                #"data-component-part="update-label"[^>]*>\s*v?(?<version>\d+(?:\.\d+)+)\s*</button>"#
                + #"(?:(?!update-label).)*?data-component-part="update-description"[^>]*>(?<date>[^<]*)</div>"#
                + #"(?:(?!update-label).)*?data-component-part="update-content"[^>]*>"#
                + #"(?<body>.*?)(?=<details|data-component-part="update-label"|</main>)"#,
            itemPatterns: [
                #"<(?:li|span data-as="p")(?![^>]*>\s*<strong>[^<]*</strong>\s*</span>)[^>]*>(?<item>.*?)</(?:li|span)>"#,
            ],
            headingPattern:
                #"(?:<h[1-3][^>]*>(?:(?!</h[1-3]>).)*?|<span data-as="p"[^>]*>\s*<strong>)"#
                + #"(?<heading>[^<>\x{200B}]+)(?:</span>\s*</h[1-3]>|</h[1-3]>|</strong>\s*</span>)"#),
        ])
}
