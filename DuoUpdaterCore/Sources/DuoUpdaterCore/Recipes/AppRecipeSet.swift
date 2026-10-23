import Foundation

/// Everything the recipe registries know about one app family — one product
/// across its channels and bundle ids — declared in `Recipes/<family>.swift`.
///
/// Pure data. `VendorProbeRegistry.recipes`, `ChangelogRecipeRegistry.recipes`,
/// `GitHubReleaseRegistry.rules`, `OneClickGateRegistry.gates`, `LoginItemAgentRestart.agentsByHost`, `ProductSunsetCatalog.sunsets`, `MacAppStoreProbeRegistry.cases`, the three
/// `ChannelProofRegistry` maps, `SparkleFeedCatalog.feeds` / `.supersededFeeds` / `.loginWalls`
/// and `ChangelogCatalog.pages` are all derived from `AppRecipeIndex.all`.
///
/// Order across families carries no meaning. What a family file must keep is
/// the relative order of ONE bundle id's entries within an array:
/// `ChangelogRecipeRegistry.recipe(forBundleID:channel:version:)`,
/// `VendorProbeSource` and `GitHubReleasesSource` all group by bundle id first
/// and then read that order.
///
/// The three channel-proof maps stay separate for the reason given on
/// `ChannelProofRegistry.githubProofs`: a `ChannelProofKey` does not say which
/// registry it was written for.
public struct AppRecipeSet: Sendable {
    /// The family's file name without `.swift`: its primary bundle id with dots as
    /// dashes. It matches the family's `docs/app-audits/` file when one exists.
    public let family: String
    public let probes: [VendorProbeRecipe]
    public let changelogs: [ChangelogRecipe]
    public let githubRules: [GitHubReleaseRule]
    public let appStoreCases: [MacAppStoreProbeCase]
    public let channelProofs: [ChannelProofKey: ChannelArtifactProof]
    public let githubChannelProofs: [ChannelProofKey: ChannelArtifactProof]
    public let bindingProofs: [ChannelProofKey: ChannelArtifactProof]
    let sparkleFeeds: [String: URL]
    let supersededFeeds: [String: SparkleFeedCatalog.SupersededFeed]
    let loginWalls: [String: SparkleFeedCatalog.LoginWall]
    let changelogPages: [String: URL]
    public let oneClickGates: [OneClickGate]
    /// Host bundle id → bundle ids of login-item agents in its
    /// `Contents/Library/LoginItems/` to restart after we replace the host's
    /// bundle. See `LoginItemAgentRestart`.
    public let loginItemAgentRestarts: [String: [String]]
    /// Bundle id → the vendor's published end of the app. See `ProductSunset`.
    public let sunsets: [String: ProductSunset]

    init(
        family: String,
        probes: [VendorProbeRecipe] = [],
        changelogs: [ChangelogRecipe] = [],
        githubRules: [GitHubReleaseRule] = [],
        appStoreCases: [MacAppStoreProbeCase] = [],
        channelProofs: [ChannelProofKey: ChannelArtifactProof] = [:],
        githubChannelProofs: [ChannelProofKey: ChannelArtifactProof] = [:],
        bindingProofs: [ChannelProofKey: ChannelArtifactProof] = [:],
        sparkleFeeds: [String: URL] = [:],
        supersededFeeds: [String: SparkleFeedCatalog.SupersededFeed] = [:],
        loginWalls: [String: SparkleFeedCatalog.LoginWall] = [:],
        changelogPages: [String: URL] = [:],
        oneClickGates: [OneClickGate] = [],
        loginItemAgentRestarts: [String: [String]] = [:],
        sunsets: [String: ProductSunset] = [:]
    ) {
        self.family = family
        self.probes = probes
        self.changelogs = changelogs
        self.githubRules = githubRules
        self.appStoreCases = appStoreCases
        self.channelProofs = channelProofs
        self.githubChannelProofs = githubChannelProofs
        self.bindingProofs = bindingProofs
        self.sparkleFeeds = sparkleFeeds
        self.supersededFeeds = supersededFeeds
        self.loginWalls = loginWalls
        self.changelogPages = changelogPages
        self.oneClickGates = oneClickGates
        self.loginItemAgentRestarts = loginItemAgentRestarts
        self.sunsets = sunsets
    }

    /// Every bundle id this family names, across all fourteen kinds, as written.
    public var bundleIDs: Set<String> {
        var ids = Set<String>()
        ids.formUnion(probes.map(\.bundleID))
        ids.formUnion(changelogs.map(\.bundleID))
        ids.formUnion(githubRules.map(\.bundleID))
        ids.formUnion(appStoreCases.map(\.bundleID))
        ids.formUnion(channelProofs.keys.map(\.bundleID))
        ids.formUnion(githubChannelProofs.keys.map(\.bundleID))
        ids.formUnion(bindingProofs.keys.map(\.bundleID))
        ids.formUnion(sparkleFeeds.keys)
        ids.formUnion(supersededFeeds.keys)
        ids.formUnion(loginWalls.keys)
        ids.formUnion(changelogPages.keys)
        ids.formUnion(oneClickGates.map(\.bundleID))
        ids.formUnion(loginItemAgentRestarts.keys)
        ids.formUnion(sunsets.keys)
        return ids
    }
}

extension AppRecipeIndex {
    /// One dictionary kind merged across every family. A key declared twice is a
    /// bug — the dictionary literal this replaced trapped on a duplicate key too —
    /// so it traps here, naming both families.
    static func merged<Key: Hashable, Value>(
        _ kind: KeyPath<AppRecipeSet, [Key: Value]>, into table: String
    ) -> [Key: Value] {
        var merged: [Key: Value] = [:]
        var owner: [Key: String] = [:]
        for set in all {
            for (key, value) in set[keyPath: kind] {
                if let first = owner[key] {
                    preconditionFailure(
                        "\(table): key \(key) declared by both \(first) and \(set.family)")
                }
                owner[key] = set.family
                merged[key] = value
            }
        }
        return merged
    }
}
