import Foundation

enum org_openvanilla_inputmethod_McBopomofo {
    static let bundleID = "org.openvanilla.inputmethod.McBopomofo"
    private static let releases = URL(string: "https://github.com/openvanilla/McBopomofo/releases")!

    static let set = AppRecipeSet(
        family: "org-openvanilla-inputmethod-McBopomofo",
        // History: docs/app-audits/org-openvanilla-inputmethod-McBopomofo.md#历史与实测
        // The developer publishes the interactive installer as a single release
        // ZIP. GitHub includes the SHA-256 in that same asset object.
        probes: [
            VendorProbeRecipe(
                bundleID: bundleID,
                url: URL(string: "https://api.github.com/repos/openvanilla/McBopomofo/releases/latest")!,
                mode: .responseBody,
                versionPattern: #""browser_download_url"\s*:\s*"https://github\.com/openvanilla/McBopomofo/releases/download/([0-9]+(?:\.[0-9]+)+)/McBopomofo-Installer-\1\.zip""#,
                downloadURL: releases,
                entryStartPattern: #""url"\s*:\s*"https://api\.github\.com/repos/openvanilla/McBopomofo/releases/assets/[0-9]+""#,
                install: VendorInstallSpec(
                    urlSource: .bodyPattern(
                        #""browser_download_url"\s*:\s*"(https://github\.com/openvanilla/McBopomofo/releases/download/[0-9.]+/McBopomofo-Installer-[0-9.]+\.zip)""#),
                    kind: .zip,
                    checksumPattern: #""digest"\s*:\s*"sha256:([a-fA-F0-9]{64})""#,
                    checksumFormat: .sha256Hex,
                    installerApp: VendorInstallerApp(
                        bundleIdentifier: "org.openvanilla.McBopomofo.McBopomofoInstaller",
                        teamIdentifier: "JK5M8ENA23",
                        installedPath: "~/Library/Input Methods/McBopomofo.app")),
                channel: .stable),
        ])
}
