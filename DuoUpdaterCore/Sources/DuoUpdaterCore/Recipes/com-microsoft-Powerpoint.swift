import Foundation

enum com_microsoft_Powerpoint {
    static let set = AppRecipeSet(
        family: "com-microsoft-Powerpoint",
        probes: [
        // Microsoft PowerPoint — Office suite, unified version. The fwlink 302s to
        // a versioned .pkg on the Office CDN. MAU-managed. The pkg filename carries
        // the BUILD (e.g. `16.109.26053122`, = the app's CFBundleVersion), not the
        // shorter marketing CFBundleShortVersionString (e.g. `16.109.3`), so
        // versionIsBuild routes it to the build-vs-build comparison — otherwise the
        // build would read as "newer" than the marketing version forever.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Powerpoint",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525136")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/powerpoint")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525136")!),
                kind: .pkg),
            followRedirects: false),
        ])
}
