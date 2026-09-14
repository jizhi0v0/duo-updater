import Foundation

enum org_gimp_gimp {
    static let set = AppRecipeSet(
        family: "org-gimp-gimp",
        probes: [
        // History: docs/app-audits/org-gimp-gimp.md#历史与实测
        // GIMP — the project's own `gimp_versions.json`, served from gimp.org.
        // `STABLE` is an array of release objects, newest first (checked
        // 2026-09-14), so anchoring on the "STABLE" key and taking the first
        // object's own `"version"` field is enough — no risk of reading
        // `DEVELOPMENT`'s or `NIGHTLY`'s number instead. That value matched BOTH
        // `CFBundleShortVersionString` and `CFBundleVersion` of the mounted arm64
        // dmg (checked 2026-08-16; History has the version) — the same scheme the
        // app reports, so no `versionIsBuild`.
        //
        // One-click: the JSON carries no download URL, only a `macos` array of
        // per-arch filenames (e.g. `gimp-3.2.4-arm64.dmg`). The real download host
        // (`download.gimp.org/gimp/v{major.minor}/macos/{filename}`) was confirmed
        // by HEAD (200, resolves through their mirror network via `Location`), so
        // the install URL is rebuilt from two captures off the same `macos` block:
        // the filename's major.minor and the filename itself. The published
        // `sha512`/`sha256` fields are HEX, not the base64 SHA-512 `checksumPattern`
        // verifies, so no checksum is wired — the Team-ID signature gate is the
        // only defense, same tradeoff as Gemini (`Recipes/com-google-GeminiMacOS.swift`).
        // Bundle identity: `org.gimp.gimp`, notarized Developer ID, Team T25BQ8HSJF
        // (GNOME Foundation) — `spctl` accepted it as "Notarized Developer ID"
        // (checked 2026-08-16).
        VendorProbeRecipe(
            bundleID: "org.gimp.gimp",
            url: URL(string: "https://www.gimp.org/gimp_versions.json")!,
            mode: .responseBody,
            versionPattern: #""STABLE"\s*:\s*\[\s*\{\s*"version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            downloadURL: URL(string: "https://www.gimp.org/downloads/"),
            changelogURL: URL(string: "https://www.gimp.org/news/"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.gimp.org/gimp/v{0}/macos/{1}",
                    fields: [
                        #""filename"\s*:\s*"gimp-([0-9]+\.[0-9]+)\.[0-9]+-arm64\.dmg""#,
                        #""filename"\s*:\s*"(gimp-[0-9.]+-arm64\.dmg)""#,
                    ]),
                kind: .dmg)),
        ])
}
