import Foundation

enum com_microsoft_OneDrive {
    static let set = AppRecipeSet(
        family: "com-microsoft-OneDrive",
        probes: [
        // Microsoft OneDrive — Microsoft's "latest" download fwlink. A single 302
        // lands on a versioned .pkg URL on oneclient.sfx.ms. The version is a
        // 4-component path segment (e.g. `26.078.0426.0002`), not a filename, so
        // followRedirects:false reads the Location header instead of lastPathComponent.
        //
        // Capture only the FIRST THREE components: the installed bundle's
        // CFBundleShortVersionString is exactly those (e.g. `26.078.0426`), while the
        // 4th path component is a build revision that the marketing version omits —
        // and CFBundleVersion uses a *different* scheme (e.g. `26078.0426.0002`, first
        // two merged), so neither installed field matches the full 4-component path.
        // Comparing the full path version would read the trailing `.0002` as newer
        // than `26.078.0426` and phantom-update forever. (Verified against a real
        // install: short `26.078.0426`, build `26078.0426.0002`.) A genuine release
        // bumps one of the first three, so first-3 detection stays correct; the only
        // blind spot is a pure 4th-component re-spin under an unchanged marketing
        // version — the safe direction (a missed check, never a phantom), and
        // OneDrive self-updates via OneDriveStandaloneUpdaterDaemon anyway.
        // Install follows the same fwlink.
        VendorProbeRecipe(
            bundleID: "com.microsoft.OneDrive",
            url: URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!,
            mode: .redirectFilename,
            versionPattern: #"/Installers/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onedrive/download")!,
            changelogURL: URL(string: "https://support.microsoft.com/en-us/office/onedrive-release-notes-845dcf18-f921-435e-bf28-4e24b95e5fc0")!,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=823060")!),
                kind: .pkg),
            followRedirects: false),
        ])
}
