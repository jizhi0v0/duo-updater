import Foundation

enum app_shift {
    static let set = AppRecipeSet(
        family: "app-shift",
        changelogs: [
        // History: docs/app-audits/app-shift.md#历史与实测
        // Shift (shift.graphics, github.com/shift-editor/shift) — the repo's
        // CHANGELOG.md, which Release Please writes.
        //
        // Detection needs no recipe: the bundle's `app-update.yml` names a generic
        // electron-builder feed and `ElectronManifestSource` reads it. That
        // manifest carries no notes, so without this the pane has nothing.
        //
        // Not GitHub releases, though the release body holds the same text. The
        // vendor marks EVERY versioned release `prerelease: true` (its
        // `docs/releases.md`: Alpha / Developer Preview are release metadata, not
        // part of the version), and `.gitHubReleases` reads a stable install's
        // notes from non-prereleases only — it would find none. The rolling
        // `nightly` release is in that list too. CHANGELOG.md has neither problem.
        //
        // Release Please's shape:
        //
        //   ## [0.1.1](https://github.com/shift-editor/shift/compare/v0.1.0...v0.1.1) (2026-10-01)
        //   ### Features
        //   * **desktop:** add Nightly branding ([#293](…/issues/293)) ([450f0f3](…/commit/450f0f3…))
        //
        //  * The version must be numeric, which skips the file's own trailing
        //    `## Changelog` preamble. The bracket and link are optional because
        //    Release Please writes a repo's first release without a compare link.
        //  * The item pattern drops the trailing commit-hash link: every bullet
        //    ends with one and it says nothing to a reader. The issue link stays.
        //  * Nightly (`app.shift.nightly`) is a separate bundle id, versioned
        //    `0.<run>.<attempt>`, with no per-build notes; this recipe is keyed to
        //    the Release bundle only and does not apply to it.
        ChangelogRecipe(
            bundleID: "app.shift",
            source: URL(string: "https://raw.githubusercontent.com/shift-editor/shift/main/CHANGELOG.md")!,
            entryPattern:
                #"(?:^|\n)##\s+\[?(?<version>[0-9]+(?:\.[0-9]+){1,3})\]?(?:\([^)\n]*\))?\s+\((?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\)\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [
                #"\n\*\s+(?<item>[^\n]+?)(?:\s+\(\[[0-9a-f]{7,40}\]\(https://github\.com/[^)\s]*\)\))?(?=\n|\z)"#,
            ],
            markdownSource: true,
            headingPattern: #"\n###\s+(?<heading>[^\n]+)"#),
        ])
}
