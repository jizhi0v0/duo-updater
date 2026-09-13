import Foundation

enum com_sublimetext_4 {
    static let set = AppRecipeSet(
        family: "com-sublimetext-4",
        probes: [
        // Sublime Text 4 — self-updates, so it reaches us here. NOTE: HTML scrape
        // (no usable API: the /updates/.../updatecheck endpoint 404s and the cask
        // has no livecheck). The /download page is server-rendered: its latest
        // marker `<p class="latest"><i>Version:</i> Build 4200</p>` precedes the
        // descending history, so the FIRST "Build NNNN" is newest. CRITICAL:
        // capture the FULL "Build NNNN" string, not the bare 4-digit build — the
        // installed CFBundleShortVersionString is literally "Build 4200" (with the
        // space), and VersionComparator ranks a number above adjacent text, so a
        // bare "4200" vs "Build 4200" reads as a perpetual phantom update. Keeping
        // the "Build " prefix makes it compare like-for-like. Detection only.
        VendorProbeRecipe(
            bundleID: "com.sublimetext.4",
            url: URL(string: "https://www.sublimetext.com/download")!,
            mode: .responseBody,
            versionPattern: #"class="latest"><i>Version:</i>\s*(Build\s+4[0-9]{3})"#,
            changelogURL: URL(string: "https://www.sublimetext.com/download"),
            // One-click verified 2026-08-09 on build 4200: `Sublime Text.app` in the
            // archive, bundle id and Team (Z6D26JE4Y4) matching the installed copy,
            // its CFBundleShortVersionString literally "Build 4200" like the probe's
            // value, spctl "Notarized Developer ID".
            //
            // The page ships the download link as a TEMPLATE — the literal string
            // `sublime_text_build_${version}_mac.zip`, with JS filling it in — so
            // there is no href to lift. Rebuild it from the same "latest" marker the
            // version comes from, taking the BARE build number (the version pattern
            // keeps the "Build " prefix on purpose; a URL can't).
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.sublimetext.com/sublime_text_build_{0}_mac.zip",
                    fields: [#"class="latest"><i>Version:</i>\s*Build\s+(4[0-9]{3})"#]),
                kind: .zip)),
        ],
        changelogs: [
        // Sublime Text 4 — the /download page is fully server-rendered and carries
        // the <h2>Changelog</h2> inline (no hydration). Each release is an <article>
        // (the newest is <article class="current">) shaped as:
        //   <h3>Build 4200</h3><div class="release-date">21 May 2025</div>
        //   <h3>New Features and Improvements</h3>     ← section sub-headings, ignored
        //   <ul class="topic"><li>…</li>…</ul>          ← one or more lists per build
        // Versions are 4-digit BUILD numbers. The version h3 is usually "Build 4200",
        // but the original v4 release reads "4 (Build 4107)", so the h3 capture
        // tolerates a leading "<digit> (Build " and trailing ")" and grabs only the
        // 4xxx digits. `body` runs to the next </article>, spanning every section's
        // <li> in a build; the sub-heading <h3>s between are harmless because
        // itemPatterns only consume <li>. The page mixes stable + dev builds
        // newest-first; we take whatever it presents.
        ChangelogRecipe(
            bundleID: "com.sublimetext.4",
            source: URL(string: "https://www.sublimetext.com/download")!,
            entryPattern:
                #"<article[^>]*>\s*"#
                + #"<h3>(?:[^<]*?\(Build\s+)?(?:Build\s+)?(?<version>4\d{3})\)?</h3>\s*"#
                + #"<div class="release-date">(?<date>[^<]*)</div>"#
                + #"(?<body>.*?)</article>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
        ])
}
