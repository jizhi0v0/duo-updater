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
                versionPattern: #"\A(v?[0-9]+\.[0-9]+\.[0-9]+)\z"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"\AParetoSecurity\.dmg\z"#,
                installerKind: .dmg,
                channel: channel)
        },
        // Pareto's opt-in admits both stable and prerelease tags and chooses
        // the highest version. Their DMGs have the same filename.
        githubChannelProofs: [
            ChannelProofKey(bundleID, .beta):
                .recipeAnchor(#"^true$|^highestVersion$"#, in: ["usePrereleases", "candidateScope"]),
        ])
}
