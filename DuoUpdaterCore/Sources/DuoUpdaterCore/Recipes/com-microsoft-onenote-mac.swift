import Foundation

enum com_microsoft_onenote_mac {
    static let set = AppRecipeSet(
        family: "com-microsoft-onenote-mac",
        probes: [
        // History: docs/app-audits/com-microsoft-onenote-mac.md#历史与实测
        // Microsoft OneNote — Office suite, unified version. MAU-managed, and read
        // from the MAU manifest rather than the suite fwlink, the same way Outlook
        // is in `Recipes/com-microsoft-Outlook.swift`.
        //
        // It used to use the suite fwlink (linkid=525133), on the reasoning that
        // there is no dedicated OneNote fwlink and the suite reports the same
        // version. That is true for DETECTION and wrong for INSTALL: that link
        // serves `Microsoft_365_and_Office_<build>_Installer.pkg`, which declares
        // eight destinations — Word, Excel, PowerPoint, Outlook, OneNote, OneDrive,
        // AutoUpdate and a Defender shim. Someone who has only OneNote installed
        // and clicks Update would have had the entire Office suite put on their
        // machine.
        //
        // `FullUpdaterLocation` in the MAU manifest is a standalone OneNote
        // package that declares exactly one destination,
        // `/Applications/Microsoft OneNote.app`, signed
        // `Developer ID Installer: Microsoft Corporation (UBF8T346G9)`.
        //
        // It must be `FullUpdaterLocation` and not `Location`/`Payload`: those are
        // deltas keyed to a specific starting build, and applying one without its
        // baseline installs a broken app.
        VendorProbeRecipe(
            bundleID: "com.microsoft.onenote.mac",
            url: URL(string: "https://officecdn.microsoft.com/pr/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/0409ONMC2019.xml")!,
            mode: .responseBody,
            versionPattern: #"<key>Update Version</key>\s*<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-365/onenote/digital-note-taking-app")!,
            changelogURL: URL(string: "https://learn.microsoft.com/en-us/officeupdates/release-notes-office-for-mac")!,
            versionIsBuild: true,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"<key>FullUpdaterLocation</key>\s*<string>(https://[^<\s]+/Microsoft_OneNote_[0-9.]+_Updater\.pkg)</string>"#),
                kind: .pkg)),
        ])
}
