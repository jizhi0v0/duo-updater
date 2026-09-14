import Foundation

enum com_getdropbox_dropbox {
    static let set = AppRecipeSet(
        family: "com-getdropbox-dropbox",
        probes: [
        // Dropbox (desktop, mac) — the website's "latest" download link. A single
        // 302 from www.dropbox.com/download?plat=mac&full=1&arch=arm64 lands on the
        // versioned package
        // edge.dropboxstatic.com/dbx-releng/client/Dropbox%20<ver>.arm64.dmg, so the
        // version rides in the %20-encoded Location filename. The target is a
        // several-hundred-MB dmg, so don't follow — read the small 302 Location
        // (followRedirects:false). NOTE the scheme is 3-component (254.4.2518 =
        // 254/4/2518, not four) — the pattern is three numeric groups. Dropbox
        // self-updates, so this row usually just confirms that.
        //
        // `&arch=arm64` is load-bearing, on BOTH URLs. Without it the same link
        // redirects to `Dropbox%20<ver>.dmg`, which is an x86_64-only build (the
        // Homebrew cask labels it `intel:` and adds this same query for `arm:` in
        // its livecheck). Installing that over an arm64 copy is refused after the
        // whole download by the architecture gates in `SignatureVerifier`, so
        // one-click was dead on Apple silicon while `duo verify` stayed green.
        // The probe reads the same URL the installer fetches, so the version we
        // offer is the version of the file we download. And the pattern REQUIRES
        // `.arm64` before `.dmg`: if Dropbox ever stops honouring the query and
        // hands back the Intel filename, detection fails loudly
        // (versionPatternNoMatch in the nightly sweep) instead of offering an
        // update the install gate will refuse. Don't relax it to `(?:\.arm64)?`.
        //
        // The image is labelled "Dropbox Offline Installer" but holds the real
        // `Dropbox.app` — worth stating, since the sibling 1Password download
        // turned out to be a stub installer, not the app.
        VendorProbeRecipe(
            bundleID: "com.getdropbox.dropbox",
            url: URL(string: "https://www.dropbox.com/download?plat=mac&full=1&arch=arm64")!,
            mode: .redirectFilename,
            versionPattern: #"Dropbox(?:%20| )([0-9]+\.[0-9]+\.[0-9]+)\.arm64\.dmg"#,
            changelogURL: URL(string: "https://www.dropbox.com/release_notes")!,
            install: VendorInstallSpec(
                urlSource: .redirect(
                    URL(string: "https://www.dropbox.com/download?plat=mac&full=1&arch=arm64")!),
                kind: .dmg),
            followRedirects: false),
        ])
}
