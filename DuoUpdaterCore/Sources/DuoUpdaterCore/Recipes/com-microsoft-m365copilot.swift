import Foundation

enum com_microsoft_m365copilot {
    static let set = AppRecipeSet(
        family: "com-microsoft-m365copilot",
        probes: [
        // MARK: - 2026-08-30 Microsoft 365 Copilot

        // Microsoft 365 Copilot — the standalone AI productivity app. Same
        // shape as the Office family: the cask is `auto_updates`, and the
        // vendor's "latest" fwlink 302s to a versioned pkg on the Office CDN
        // (`Microsoft_365_Copilot_universal_1.2608.0301_Installer.pkg`,
        // observed 2026-08-30). The pkg filename carries the BUILD — the
        // expanded app's CFBundleVersion is exactly `1.2608.0301` while its
        // CFBundleShortVersionString is `1.2608` — so versionIsBuild routes it
        // to build-vs-build (unlike the Office apps, the filename build here
        // IS the bundle build verbatim, so no segment surgery is needed).
        //
        // The fwlink is a TWO-hop chain: fwlink → 302 → `aka.ms/
        // M365CopilotForMac` → 301 → CDN pkg. `followRedirects: false` reads
        // only the FIRST Location, which is the bare aka.ms alias — so the
        // probe points at the aka.ms alias directly (one hop, whose Location
        // is the versioned CDN URL), while the install follows the canonical
        // fwlink (all hops, same artifact).
        //
        // One-click `kind: .pkg` is mandatory: the pkg installs the app PLUS
        // `Microsoft AutoUpdate` (Office16_all_autoupdate) as a sibling —
        // verified by expanding the real pkg 2026-08-30 (payload contains
        // com.microsoft.autoupdate2). Signed Developer ID Installer, notarized.
        VendorProbeRecipe(
            bundleID: "com.microsoft.m365copilot",
            url: URL(string: "https://aka.ms/M365CopilotForMac")!,
            mode: .redirectFilename,
            versionPattern: #"_(\d+\.\d+\.\d+)_Installer\.pkg"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365-copilot/download-copilot-app")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .redirect(URL(string: "https://go.microsoft.com/fwlink/?linkid=2325438")!),
                kind: .pkg),
            followRedirects: false),

        // Deliberately NOT covered by a ChangelogRecipe, checked 2026-09-03 against the real
        // bytes rather than assumed:
        //
        //   * **Microsoft 365 Copilot** (`com.microsoft.m365copilot`).
        //     `learn.microsoft.com/en-us/microsoft-365-copilot/release-notes` is
        //     organised by DATE and then by PRODUCT (Excel, Word, Outlook,
        //     PowerPoint, OneNote, Viva Insights, …) for the whole Microsoft 365
        //     Copilot service. The string `1.2608` — the build our probe reads
        //     out of the pkg filename — appears ZERO times on the page, so no
        //     version-keyed recipe can bind, and a date-keyed one would show
        //     Excel and Outlook features under the Copilot app's row.
        ])
}
