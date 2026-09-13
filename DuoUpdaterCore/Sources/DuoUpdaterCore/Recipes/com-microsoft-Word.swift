import Foundation

enum com_microsoft_Word {
    static let set = AppRecipeSet(
        family: "com-microsoft-Word",
        probes: [
        // Microsoft Word — Office suite, unified version. Same CDN/fwlink pattern
        // as PowerPoint. MAU-managed.
        VendorProbeRecipe(
            bundleID: "com.microsoft.Word",
            url: URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525134")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/word")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/p/?linkid=525134")!),
                kind: .pkg),
            followRedirects: false),
        ])
}
