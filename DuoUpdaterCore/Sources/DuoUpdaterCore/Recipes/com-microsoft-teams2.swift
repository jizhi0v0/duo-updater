import Foundation

enum com_microsoft_teams2 {
    static let set = AppRecipeSet(
        family: "com-microsoft-teams2",
        probes: [
        // Microsoft Teams — Microsoft's config/v1 version API (same family as
        // VS Code & Edge). The "WebView2Canary" track is the production/Public R4
        // build despite the confusing name (Homebrew's `microsoft-teams` cask
        // tracks this same 4-component version). Teams self-updates via Microsoft
        // AutoUpdate (com.microsoft.autoupdate2). The full version is the app's
        // marketing string, so this is a normal (non-build) recipe. The install
        // buildLink MUST be anchored to the WebView2Canary block: the JSON lists a
        // separate "WebView2" track first whose (lower) buildLink a bare
        // "buildLink" pattern would grab — installing a different track than the
        // one we detected.
        VendorProbeRecipe(
            bundleID: "com.microsoft.teams2",
            url: URL(string: "https://config.teams.microsoft.com/config/v1/MicrosoftTeams/1?environment=prod&audienceGroup=general&teamsRing=general&agent=TeamsBuilds")!,
            mode: .responseBody,
            versionPattern: #""WebView2Canary":\{"macOS":\{"latestVersion":"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)""#,
            downloadURL: URL(string: "https://www.microsoft.com/en-us/microsoft-teams/download-app")!,
            changelogURL: URL(string: "https://support.microsoft.com/en-us/office/what-s-new-in-microsoft-teams-d7092a6d-c896-424c-b362-a472d5f105de")!,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#""WebView2Canary":\{"macOS":\{"latestVersion":"[^"]*","buildLink":"([^"]+MicrosoftTeams\.pkg)""#),
                kind: .pkg)),
        ])
}
