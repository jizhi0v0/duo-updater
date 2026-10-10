import Foundation

enum com_tigervnc_tigervnc {
    static let set = AppRecipeSet(
        family: "com-tigervnc-tigervnc",
        probes: [
        // History: docs/app-audits/com-tigervnc-tigervnc.md#历史与实测
        // TigerVNC — read from SourceForge's file RSS for `/stable`, not from
        // `best_release.json`. That JSON's `platform_releases.mac` is the
        // project's chosen *default download*, which a maintainer moves by hand,
        // and it can stay on an older release after a newer dmg is uploaded (see
        // History). The RSS lists the files themselves, newest upload first.
        //
        // Each item's `<title>` is the file's path. The pattern takes only
        // `/stable/<v>/TigerVNC-<v>.dmg` — the backreference requires the folder
        // and the filename to name the same version — so the Windows exes, the
        // VncViewer jar, the Linux packages and the source tarballs in the same
        // feed never match. `path=/stable` keeps beta folders out. With only
        // those titles matching, `selectHighest` is safe and does not depend on
        // the feed's order.
        //
        // The feed holds only the newest files and cannot be widened, and one
        // release fills most of that window with the dmg uploaded early (History
        // has the counts). If a release ever pushes its own dmg out of the window,
        // the probe sees an older dmg or none: a late or unknown answer, never a
        // version that was not shipped.
        //
        // ONE-CLICK via `.versionTemplate`: the URL is SourceForge's permanent
        // `files/<path>/download` redirect, filled with the version that won the
        // comparison, so the download is the dmg being reported. Developer ID
        // (Brian Hinz, S5LX88A9BW), notarized; `spctl` accepts the app mounted
        // from the dmg (checked 2026-10-10; History has the dmg version).
        VendorProbeRecipe(
            bundleID: "com.tigervnc.tigervnc",
            url: URL(string: "https://sourceforge.net/projects/tigervnc/rss?path=/stable")!,
            mode: .responseBody,
            versionPattern:
                #"<title><!\[CDATA\[/stable/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/TigerVNC-\1\.dmg\]\]></title>"#,
            changelogURL: URL(string: "https://github.com/TigerVNC/tigervnc/releases")!,
            selectHighest: true,
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://sourceforge.net/projects/tigervnc/files/stable/"
                    + "{version}/TigerVNC-{version}.dmg/download"),
                kind: .dmg),
            // Same SourceForge edge as `sourceForgeMacRecipe`: it has refused the
            // browser-like default UA, so send a tool UA here too.
            requestHeaders: ["User-Agent": "DuoUpdater/0.1"]),
        ])
}
