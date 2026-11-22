import Foundation

enum com_backblaze_Backblaze {
    static let bundleID = "com.backblaze.Backblaze"

    static let set = AppRecipeSet(
        family: "com-backblaze-Backblaze",
        // History: docs/app-audits/com-backblaze-Backblaze.md#历史与实测
        // The public cask record pins the versioned Backblaze DMG and its
        // SHA-256. A direct copy uses the digest and vendor signature, then
        // launches the GUI installer rather than executing the package.
        probes: [
            VendorProbeRecipe(
                bundleID: bundleID,
                url: URL(string: "https://formulae.brew.sh/api/cask/backblaze.json")!,
                mode: .responseBody,
                versionPattern: #"^\{\s*"token"\s*:\s*"backblaze"(?=[\s\S]*?"version"\s*:\s*"([0-9]+(?:\.[0-9]+){3})")[\s\S]*?"url"\s*:\s*"https://secure\.backblaze\.com/api/install_backblaze\?file=bzinstall-mac-\1\.dmg""#,
                downloadURL: URL(string: "https://www.backblaze.com/status/update")!,
                install: VendorInstallSpec(
                    urlSource: .bodyPattern(
                        #""url"\s*:\s*"(https://secure\.backblaze\.com/api/install_backblaze\?file=bzinstall-mac-[0-9]+(?:\.[0-9]+){3}\.dmg)""#),
                    kind: .dmg,
                    checksumPattern: #""sha256"\s*:\s*"([a-fA-F0-9]{64})""#,
                    checksumFormat: .sha256Hex,
                    installerApp: VendorInstallerApp(
                        bundleIdentifier: "com.backblaze.bzdoinstall",
                        teamIdentifier: "G4K4BQ7S8J",
                        installedPath: "/Applications/Backblaze.app"))),
        ])
}
