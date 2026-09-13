import Foundation

enum com_getdropbox_dropbox {
    static let set = AppRecipeSet(
        family: "com-getdropbox-dropbox",
        probes: [
        // Dropbox (desktop, mac) — the website's "latest" download link. A single
        // 302 from www.dropbox.com/download?plat=mac&full=1 lands on the versioned
        // package edge.dropboxstatic.com/dbx-releng/client/Dropbox%20<ver>.dmg, so
        // the version rides in the %20-encoded Location filename. The target is a
        // ~200 MB dmg, so don't follow — read the small 302 Location
        // (followRedirects:false). NOTE the scheme is 3-component (254.4.2518 =
        // 254/4/2518, not four) — the pattern is three numeric groups. Detection
        // Dropbox self-updates, so this row usually just confirms that. (Homebrew
        // cask has no livecheck; its url/version confirm this host + build.)
        //
        // One-click verified 2026-08-09 on 264.4.3385: the image is labelled
        // "Dropbox Offline Installer" but holds the real `Dropbox.app` —
        // com.getdropbox.dropbox, Team G7HH3F8CAK, spctl "Notarized Developer ID",
        // version matching the redirect filename. (Worth stating, since the sibling
        // 1Password download turned out to be a stub installer, not the app.)
        VendorProbeRecipe(
            bundleID: "com.getdropbox.dropbox",
            url: URL(string: "https://www.dropbox.com/download?plat=mac&full=1")!,
            mode: .redirectFilename,
            versionPattern: #"Dropbox(?:%20| )([0-9]+\.[0-9]+\.[0-9]+)\.dmg"#,
            changelogURL: URL(string: "https://www.dropbox.com/release_notes")!,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://www.dropbox.com/download?plat=mac&full=1")!),
                kind: .dmg),
            followRedirects: false),
        ])
}
