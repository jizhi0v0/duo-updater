import Foundation

enum org_libreoffice_script {
    static let set = AppRecipeSet(
        family: "org-libreoffice-script",
        probes: [
        // History: docs/app-audits/org-libreoffice-script.md#历史与实测
        // Shared rationale for 2026-08-16 group D (directory indexes): Recipes/com-operasoftware-Opera.swift.

        // LibreOffice — `download.documentfoundation.org/libreoffice/stable/` is a
        // MirrorBrain index of version folders (`26.2.5/`). `href="X.Y.Z/"` matches
        // only version folders; the page carries no other dotted-numeric hrefs.
        //
        // ONE-CLICK, via `.versionTemplate`. The mac artifact sits two levels below
        // the index, at a path that is fully determined by the version:
        // `<ver>/mac/aarch64/LibreOffice_<ver>_MacOS_aarch64.dmg`. That URL answers
        // with a 302 to a MirrorBrain mirror (e.g. `mirror.usi.edu` /
        // `mirror.fcix.net`; checked by HEAD 2026-08-16 and 2026-09-14) — the
        // mirror changes per request, which is why the URL is built from the
        // canonical host and never cached. The deeper path is not a blocker;
        // `.bodyTemplate` would be, because its regexes take the FIRST match while
        // this index is sorted alphabetically and `selectHighest` deliberately
        // picks a different entry, so the URL could name an older release than the
        // one reported. `.versionTemplate` fills the resolved version instead,
        // which is exactly the string that was compared.
        //
        // aarch64 only, like the other arm64-pinned recipes here (GIMP, pgAdmin,
        // Meld): Apple silicon is every host DuoUpdater runs on (`App/project.yml`,
        // `ARCHS: arm64`), so the x86-64 dmg LibreOffice also publishes is never
        // the one wanted.
        //
        // VERSION SCHEME TRAP: the index publishes 3-segment versions (e.g.
        // `26.2.5`) but the installed bundle reports 4, in both
        // `CFBundleShortVersionString` and `CFBundleVersion` (e.g. `26.2.5.2`). The
        // aarch64 dmg is notarized Developer ID, Team 7P5S3ZLCN7, "The Document
        // Foundation", spctl accepted (checked 2026-08-16 by mounting it). Comparing a
        // bare `26.2.5` against `26.2.5.2` is safe either way `VersionComparator`
        // treats missing trailing components as `0`: it reads the installed copy as
        // (at worst) equal, never triggers a phantom update. The only blind spot is
        // a pure 4th-component hotfix under an unchanged 3-segment folder, which
        // this index can't see at all — same acceptable direction as OneDrive's
        // first-three-components recipe (`Recipes/com-microsoft-OneDrive.swift`).
        VendorProbeRecipe(
            bundleID: "org.libreoffice.script",
            url: URL(string: "https://download.documentfoundation.org/libreoffice/stable/")!,
            mode: .responseBody,
            versionPattern: #"href="([0-9]+\.[0-9]+\.[0-9]+)/""#,
            downloadURL: URL(string: "https://www.libreoffice.org/download/download-libreoffice/"),
            changelogURL: URL(string: "https://www.libreoffice.org/release-notes/"),
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://download.documentfoundation.org/libreoffice/stable/"
                    + "{version}/mac/aarch64/LibreOffice_{version}_MacOS_aarch64.dmg"),
                kind: .dmg)),
        ])
}
