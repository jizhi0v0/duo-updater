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
        // No checksum: the response's `sha256hash` is SHA-256 hex, and
        // `checksumPattern` verifies base64 SHA-512. Wiring the wrong digest would
        // fail every install; the signature and Team gates carry the integrity.
        VendorProbeRecipe(
            bundleID: "com.exafunction.windsurf",
            url: URL(string: "https://windsurf-stable.codeium.com/api/update/darwin-arm64-dmg/stable/latest")!,
            mode: .responseBody,
            versionPattern: #"\"windsurfVersion\"\s*:\s*\"([0-9]+(?:\.[0-9]+)+)\""#,
            downloadURL: URL(string: "https://devin.ai/desktop"),
            changelogURL: URL(string: "https://windsurf.com/editor/releases/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"\"url\"\s*:\s*\"(https://[^\"]+\.dmg)\""#),
                kind: .dmg)),
        ])
}
