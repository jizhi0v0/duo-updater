import Foundation

enum cc_ffitch_shottr {
    static let set = AppRecipeSet(
        family: "cc-ffitch-shottr",
        probes: [
        // History: docs/app-audits/cc-ffitch-shottr.md#历史与实测
        // Shottr — its own JSON version check (the same endpoint baked into the app
        // binary: shottr.cc/api/version.json). NOT a Sparkle appcast — Shottr ships
        // none (no Info.plist SUFeedURL, /appcast.xml 404s), so it reaches us here.
        // `latestVersion` is the STABLE marketing version, equal to the
        // app's CFBundleShortVersionString. A `betaLatestVersion` also lives in the
        // body — the `"latestVersion"` anchor can't match the `"betaLatestVersion"`
        // key (different literal prefix), so a stable install is never offered the
        // beta build.
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
        ],
        changelogs: [
        // History: docs/app-audits/cc-ffitch-shottr.md#历史与实测
        // Shottr — `newversion.html`, the page the probe links. Static HTML, newest
        // first, one `<div class="segment">` per release, with NO dates anywhere:
        //   <div class="leftcol"><h3>Shottr v1.9.2</h3></div>
        //   <div class="rightcol"><b>Improvements</b><ul><li>…</li></ul> …</div>
        // The newest release is the page's headline instead, `<h1>Shottr v1.9.3 is
        // out!</h1>`, so both heading levels and the trailing words are accepted.
        // Older segments keep a commented-out copy of that headline
        // (`<!--<h1>Shottr v1.7.2 is out!</h1>`), which the `leftcol` anchor keeps
        // from reading as a second entry. The version is the number after "v", the
        // same marketing version the probe's `latestVersion` reports.
        //
        // The gap from the heading to `rightcol` may not cross into the next
        // segment, so a release without notes cannot take the next one's. Items
        // are `<li>`; a release written as paragraphs (1.7.1) falls back to `<p>`,
        // skipping the bold one that is its section name. `<b>` section names
        // directly before a list or closing a paragraph render as headings.
        ChangelogRecipe(
            bundleID: "cc.ffitch.shottr",
            source: URL(string: "https://shottr.cc/newversion.html")!,
            entryPattern:
                #"<div class="leftcol">\s*<h[13]>\s*Shottr v(?<version>[0-9]+(?:\.[0-9]+){1,3})(?:\s+is out!)?\s*</h[13]>"#
                + #"(?:(?!<div class="segment").)*?<div class="rightcol">"#
                + #"(?<body>.*?)(?=<div class="segment"|<style|</body>)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<p>(?!\s*<b>)(?<item>.*?)</p>"#,
            ],
            headingPattern: #"<b>(?<heading>[^<]+)</b>\s*(?=<ul|<li|</p>)"#),
        ])
}
