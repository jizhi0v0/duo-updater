import Foundation

enum niteo_co_Pareto {
    static let bundleID = "niteo.co.Pareto"

    static func resolveCurrent() -> ResolvedChannel {
        // Upstream Defaults.betaChannelComputed reads showBeta from the
        // direct edition's standard preferences; the default is false.
        CFPreferencesAppSynchronize(bundleID as CFString)
        let includeBeta = CFPreferencesGetAppBooleanValue("showBeta" as CFString, bundleID as CFString, nil)
        return ResolvedChannel(channel: includeBeta ? .beta : .stable)
    }

    // History: docs/app-audits/niteo-co-Pareto.md#历史与实测
    static let set = AppRecipeSet(
        family: "niteo-co-Pareto",
        githubRules: [.stable, .beta].map { (channel: ReleaseChannel) in
            GitHubReleaseRule(
                bundleID: bundleID,
                owner: "ParetoSecurity", repo: "pareto-mac",
                usePrereleases: channel == .beta,
                versionPattern: #"\Av?([0-9]+\.[0-9]+\.[0-9]+)\z"#,
                candidateScope: .highestVersion,
                installAssetPattern: #"^ParetoSecurity\.dmg$"#,
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
