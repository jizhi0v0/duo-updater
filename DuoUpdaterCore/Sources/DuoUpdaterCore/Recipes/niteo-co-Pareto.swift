import Foundation

enum niteo_co_Pareto {
    static let bundleID = "niteo.co.Pareto"

    private static let legacyKey = "betaChannel"
    private static let currentKey = "showBeta"

    static func resolveCurrent(installedVersion: String?, domain: String = bundleID) -> ResolvedChannel {
        guard let installedVersion, !VersionComparator.isNewer("0.0.19", than: installedVersion)
        else { return ResolvedChannel(channel: .stable) }
        let key = VersionComparator.isNewer("1.9.1", than: installedVersion) ? legacyKey : currentKey
        CFPreferencesAppSynchronize(domain as CFString)
        return ResolvedChannel(channel: preference(key, domain: domain) ? .beta : .stable)
    }

    // From 0.0.22 until 1.21.2 the opted-in updater considered only
    // prereleases. The current updater also accepts promoted stable releases.
    static func betaRequiresPrerelease(installedVersion: String?) -> Bool {
        guard let installedVersion else { return false }
        return !VersionComparator.isNewer("0.0.22", than: installedVersion)
            && VersionComparator.isNewer("1.21.2", than: installedVersion)
    }

    // The watcher has an ID but no installed version. Either key can affect an
    // installed copy. The triggered scan uses that copy's version to pick one.
    static func preferenceFingerprint(domain: String = bundleID) -> String {
        CFPreferencesAppSynchronize(domain as CFString)
        return "\(preference(legacyKey, domain: domain))|\(preference(currentKey, domain: domain))"
    }

    private static func preference(_ key: String, domain: String) -> Bool {
        CFPreferencesGetAppBooleanValue(key as CFString, domain as CFString, nil)
    }

    // History: docs/app-audits/niteo-co-Pareto.md#历史与实测
    static let set = AppRecipeSet(
        family: "niteo-co-Pareto",
        githubRules: [.stable, .beta].map { (channel: ReleaseChannel) in
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "ParetoSecurity", repo: "pareto-mac",
                usePrereleases: channel == .beta,
                // The longest measured run before a usable prerelease was 31 rows.
                listPageSize: channel == .beta ? 40 : 30,
                versionPattern: #"\A(v?[0-9]+\.[0-9]+\.[0-9]+)\z"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"\AParetoSecurity\.dmg\z"#,
                installerKind: .dmg,
                channel: channel)
        },
        // Both channels rank releases by version and use the same DMG name.
        // The installed updater generation narrows older beta copies to prereleases.
        githubChannelProofs: [
            ChannelProofKey(bundleID, .beta):
                .recipeAnchor(#"^true$|^highestVersion$"#, in: ["usePrereleases", "candidateScope"]),
        ])
}
