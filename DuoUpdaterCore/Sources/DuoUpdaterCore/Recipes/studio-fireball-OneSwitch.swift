import Foundation

enum studio_fireball_OneSwitch {
    static let bundleID = "studio.fireball.OneSwitch"
    private static let stableFeed = URL(string:
        "https://fireball.studio/api/release_manager/studio.fireball.OneSwitchOfficial.xml")!
    private static let betaFeed = URL(string:
        "https://fireball.studio/api/release_manager/studio.fireball.OneSwitchOfficial.xml?beta=1")!

    static func resolve(includeBeta: Bool, declaredFeed: URL? = nil) -> ResolvedChannel? {
        // Leave a bundle's own different address in place if it starts
        // declaring one. The current bundle builds the address at runtime.
        guard declaredFeed == nil || declaredFeed == stableFeed else { return nil }
        return includeBeta
            ? ResolvedChannel(channel: .beta, feedOverride: betaFeed)
            : ResolvedChannel(channel: .stable, feedOverride: stableFeed)
    }

    static func resolveCurrent(declaredFeed: URL?) -> ResolvedChannel? {
        CFPreferencesAppSynchronize(bundleID as CFString)
        let value = CFPreferencesCopyAppValue("SUUpdaterChecksForBetaUpdates" as CFString, bundleID as CFString)
        return resolve(includeBeta: enablesBeta(value), declaredFeed: declaredFeed)
    }

    static func enablesBeta(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    // History: docs/app-audits/studio-fireball-OneSwitch.md#历史与实测
    // Each appcast item links to its own localized notes. The page titles name
    // the product, and the current prose-only page has no version in its body.
    // The build belongs to the selected appcast item, not to a heading inside
    // a notes page that may also summarize an earlier release.
    private static func notes(channel: ReleaseChannel, feed: URL) -> ChangelogRecipe {
        ChangelogRecipe(
            bundleID: bundleID,
            source: feed,
            entryPattern: #"<title>\s*(?<title>One Switch Official)\s*</title>.*?<div\s+class="content">(?<body>.*?)</div>"#,
            itemPatterns: [#"<(li|p)\b[^>]*>(?![^<]*[:：]\s*</p>\s*<[uo]l\b)(?<item>.*?)</\1>"#],
            maxEntries: 1,
            channel: channel,
            headingPattern: #"<p\b[^>]*>\s*(?<heading>[^<]+?[:：])\s*</p>\s*(?=<[uo]l\b)"#,
            feedPagePattern: #"^https://fireball\.studio/api/release_manager/releasenotes/[0-9]+/[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*/studio\.fireball\.OneSwitchOfficial\.xml$"#)
    }

    static let set = AppRecipeSet(
        family: "studio-fireball-OneSwitch",
        changelogs: [notes(channel: .stable, feed: stableFeed), notes(channel: .beta, feed: betaFeed)],
        bindingProofs: [
            ChannelProofKey(bundleID, .beta):
                .recipeAnchor(#"^https://fireball\.studio/api/release_manager/studio\.fireball\.OneSwitchOfficial\.xml\?beta=1$"#,
                              in: ["feedOverride"]),
        ],
        oneClickGates: [
            OneClickGate(
                bundleID: bundleID,
                requirement: .migratedMajor(source: "Sparkle", firstMajor: 2),
                reason: "open One Switch and use Check for Updates to migrate its Keep Awake helper"),
        ])
}
