import Foundation

enum org_gnu_Emacs {
    static let set = AppRecipeSet(
        family: "org-gnu-Emacs",
        probes: [
        // History: docs/app-audits/org-gnu-Emacs.md#历史与实测
        // Emacs for Mac OS X — the maintainer's own Atom feed, newest entry first.
        // `<title>Emacs Version 30.2-2</title>`.
        //
        // VERSION SCHEME TRAP: some entries carry a `-N` repack suffix (`30.2-2`,
        // `30.2-1`) for a re-signed rebuild of the SAME release, but the shipped
        // app does not: mounting the 30.2-2 dmg and reading Info.plist gives
        // `CFBundleShortVersionString = 30.2` (no suffix at all; `CFBundleVersion`
        // is an unrelated `9.0`, not usable either). Capturing the suffix would
        // make the probe report `30.2-2 > 30.2` forever — a phantom update that can
        // never clear. The pattern anchors to the `<title>` tag (skipping the
        // duplicate plain-text title inside `<content>`) and captures only the two
        // numeric segments, dropping any `-N` tail.
        //
        // One-click: the dmg's Emacs.app is org.gnu.Emacs, Team 5BRAQAFB8B
        // (Galvanix), notarized Developer ID (checked 2026-08-16 on a mounted dmg;
        // History has the version). The install pattern reuses the same
        // `<title>`-scoped entry's `<link type="binary/octet-stream">` href, so it
        // always fetches the dmg for the version just matched (suffix included,
        // since that's the real filename) rather than a template that would guess
        // wrong when a repack bumps only the suffix.
        VendorProbeRecipe(
            bundleID: "org.gnu.Emacs",
            url: URL(string: "https://emacsformacosx.com/atom/release")!,
            mode: .responseBody,
            versionPattern: #"<title>Emacs Version ([0-9]+\.[0-9]+)(?:-[0-9]+)?</title>"#,
            downloadURL: URL(string: "https://emacsformacosx.com/"),
            changelogURL: URL(string: "https://www.gnu.org/software/emacs/news/"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<link type="binary/octet-stream" href="(https://emacsformacosx\.com/emacs-builds/Emacs-[^"]+-universal\.dmg)""#),
                kind: .dmg)),
        ])
}
