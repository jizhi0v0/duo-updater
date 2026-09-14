import Foundation

enum com_getdropbox_dropbox {
    static let set = AppRecipeSet(
        family: "com-getdropbox-dropbox",
        probes: [
        // History: docs/app-audits/com-getdropbox-dropbox.md#历史与实测
        // Dropbox (desktop, mac) — the website's "latest" download link. A single
        // 302 from www.dropbox.com/download?plat=mac&full=1 lands on the versioned
        // package edge.dropboxstatic.com/dbx-releng/client/Dropbox%20<ver>.dmg, so
        // the version rides in the %20-encoded Location filename. The target is the
        // full dmg, so don't follow — read the small 302 Location
        // (followRedirects:false). NOTE the scheme is 3-component (e.g. 254.4.2518 =
        // 254/4/2518, not four) — the pattern is three numeric groups.
        // Dropbox self-updates, so this row usually just confirms that. (The
        // Homebrew cask's livecheck read this same redirect when checked — adding
        // `&arch=arm64` on Apple silicon — and its url confirms this host; History.)
        //
        // One-click: the image is labelled "Dropbox Offline Installer" but holds
        // the real `Dropbox.app` — com.getdropbox.dropbox, Team G7HH3F8CAK,
        // notarized Developer ID, version matching the redirect filename. (Worth
        // stating, since the 1Password download (`Recipes/com-1password-1password.swift`)
        // turned out to be a stub installer, not the app.)
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
