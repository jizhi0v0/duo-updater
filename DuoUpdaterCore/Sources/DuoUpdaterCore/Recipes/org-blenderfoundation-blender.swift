import Foundation

enum org_blenderfoundation_blender {
    static let set = AppRecipeSet(
        family: "org-blenderfoundation-blender",
        changelogs: [
        // History: docs/app-audits/org-blenderfoundation-blender.md#历史与实测
        // Blender — developer.blender.org/docs/release_notes/<major.minor>/ is the
        // clean per-version notes page (the blender.org/download marketing pages are
        // sprawling splash pages with no parseable block). One page per MINOR, with
        // its patch releases folded in, so the URL is templated on `{majorMinor}`:
        // the page always matches the target build, and nothing needs bumping when
        // Blender ships. `source` is only the fallback for a load with no version.
        //
        // Each page is an <h1> "Blender X.Y Release Notes" — "Blender X.Y LTS
        // Release Notes" on an LTS minor — then a <p>"Blender X.Y [LTS] was released
        // on DATE."</p>, then module-section <ul>s and Compatibility/Bugfixes lists.
        // We surface a COARSE summary (changed-module list + compat/bugfix bullets).
        // The body ends at the "Corrective Releases" <h2> where there is one, else at
        // </article>: LTS pages have no such heading (their fixes live on a separate
        // LTS page), and a lookahead that insisted on it matched nothing there.
        //
        // Requiring the literal "was released on" is a GUARD: daily/alpha/beta builds
        // share the bundle id, and an in-development minor's page reads "is currently
        // in Alpha/Beta" instead, so it yields zero entries (safe embed fallback)
        // rather than a partial changelog.
        ChangelogRecipe(
            bundleID: "org.blenderfoundation.blender",
            source: URL(string: "https://developer.blender.org/docs/release_notes/5.2/")!,
            entryPattern:
                #"<h1[^>]*>Blender\s+(?<version>\d+\.\d+(?:\.\d+)?)(?:\s+LTS)?\s+Release Notes.*?</h1>\s*"#
                + #"<p>Blender\s+[\d.]+(?:\s+LTS)?\s+was released on\s+(?<date>[^.<]+)\.</p>"#
                + #"(?<body>.*?)"#
                + #"(?=<h2[^>]*id="corrective-releases"|</article>)"#,
            itemPatterns: [#"<li>\s*(?<item>.*?)\s*</li>"#],
            maxEntries: 1,
            sourceTemplate: "https://developer.blender.org/docs/release_notes/{majorMinor}/"),
        ])
}
