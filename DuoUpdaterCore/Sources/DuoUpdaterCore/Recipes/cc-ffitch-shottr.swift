import Foundation

enum cc_ffitch_shottr {
    static let set = AppRecipeSet(
        family: "cc-ffitch-shottr",
        probes: [
        // Shottr — its own JSON version check (the same endpoint baked into the app
        // binary: shottr.cc/api/version.json). NOT a Sparkle appcast — Shottr ships
        // none (no Info.plist SUFeedURL, /appcast.xml 404s), so it reaches us here.
        // `latestVersion` is the STABLE marketing version (1.9.1), equal to the
        // app's CFBundleShortVersionString. A `betaLatestVersion` also lives in the
        // body — the `"latestVersion"` anchor can't match the `"betaLatestVersion"`
        // key (different literal prefix), so a stable install is never offered the
        // One-click: the same JSON's `"package"` is the stable `Shottr-<ver>.pkg`.
        // Anchor to `"package"` (leading quote) so it never matches `"betaPackage"`
        // — a stable install is never handed the EAP pkg. (Shottr self-updates via
        // its own .pkg updater; this is the fallback behind the same-Team gate.)
        //
        // No `publishedAtPattern`: the same body also carries `"releaseDate":
        // "2025-12-17"` (fetched 2026-08-31) — a bare day, no time. #300 wired
        // `VendorProbeSource` to `ReleaseDate.publishedFields`, so a pattern
        // here would now land honestly in `RemoteVersion.vendorDay` instead of
        // being silently inert — the mechanism is ready. Adding the pattern
        // itself is left for a follow-up: per this repo's fragile-recipe rule,
        // a recipe change needs the real broken response reproduced and
        // `duo verify` run against it, not just a mechanism change.
        VendorProbeRecipe(
            bundleID: "cc.ffitch.shottr",
            url: URL(string: "https://shottr.cc/api/version.json")!,
            mode: .responseBody,
            versionPattern: #""latestVersion"\s*:\s*"([0-9]+\.[0-9]+(?:\.[0-9]+)?)""#,
            downloadURL: URL(string: "https://shottr.cc/"),
            changelogURL: URL(string: "https://shottr.cc/newversion.html"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""package"\s*:\s*"(https://shottr\.cc/[^"]+\.pkg)""#),
                kind: .pkg)),
        ])
}
