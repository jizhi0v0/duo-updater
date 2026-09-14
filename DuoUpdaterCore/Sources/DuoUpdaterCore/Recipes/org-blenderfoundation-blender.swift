import Foundation

enum org_blenderfoundation_blender {
    static let set = AppRecipeSet(
        family: "org-blenderfoundation-blender",
        changelogs: [
        // History: docs/app-audits/org-blenderfoundation-blender.md#历史与实测
        // Blender — developer.blender.org/docs/release_notes/<major.minor>/ is the
        // clean per-version notes page (the blender.org/download marketing pages are
        // sprawling splash pages with no parseable block). Each page is an <h1>
        // "Blender 5.1 Release Notes", a <p>"Blender 5.1 was released on DATE."</p>,
        // then module-section <ul>s and Compatibility/Bugfixes lists up to the
        // "Corrective Releases" heading. We surface a COARSE summary (changed-module
        // list + compat/bugfix bullets). Requiring the literal "was released on" is a
        // GUARD: the dev-docs nav lists in-development versions first, whose intros
        // read "is currently in Alpha/Beta" and so DON'T match — yielding zero
        // entries (safe embed fallback) rather than a partial changelog. URL is
        // version-pinned to a RELEASED minor, so it has to be bumped by hand when a
        // new Blender ships (same as the old Warp/Ghostty version-pins) — Blender
        // exposes no released-only index to follow.
        ChangelogRecipe(
            bundleID: "org.blenderfoundation.blender",
            source: URL(string: "https://developer.blender.org/docs/release_notes/5.1/")!,
            entryPattern:
                #"<h1[^>]*>Blender\s+(?<version>\d+\.\d+(?:\.\d+)?)\s+Release Notes.*?</h1>\s*"#
                + #"<p>Blender\s+[\d.]+\s+was released on\s+(?<date>[^.<]+)\.</p>"#
                + #"(?<body>.*?)"#
                + #"(?=<h2[^>]*id="corrective-releases")"#,
            itemPatterns: [#"<li>\s*(?<item>.*?)\s*</li>"#],
            maxEntries: 1),
        ])
}
