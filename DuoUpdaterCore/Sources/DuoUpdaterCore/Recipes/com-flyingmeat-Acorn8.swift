import Foundation

enum com_flyingmeat_Acorn8 {
    static let bundleID = "com.flyingmeat.Acorn8"
    static let stableFeed = URL(string: "https://flyingmeat.com/download/acorn8update.xml")!
    static let betaFeed = URL(string: "https://flyingmeat.com/download/latest/acorn8update.xml")!

    // Acorn registers the stable address by default and writes the selected
    // address into SUFeedURL when the user toggles test releases.
    static func resolve(feedPreference: String?) -> ResolvedChannel {
        feedPreference == betaFeed.absoluteString
            ? ResolvedChannel(channel: .beta, feedOverride: betaFeed)
            : ResolvedChannel(channel: .stable, feedOverride: stableFeed)
    }

    static func resolveCurrent() -> ResolvedChannel {
        CFPreferencesAppSynchronize(bundleID as CFString)
        let preference = CFPreferencesCopyAppValue("SUFeedURL" as CFString, bundleID as CFString) as? String
        return resolve(feedPreference: preference)
    }

    static func matchesFeed(bundleID installedID: String?, feedURL: URL) -> Bool {
        installedID?.lowercased() == bundleID.lowercased()
            && (feedURL == stableFeed || feedURL == betaFeed)
    }

    // The appcast inlines the same version blocks as the vendor notes page.
    // Use those bytes without fetching a second page. The feed supplies the
    // current release's date; some dates inside the HTML are placeholders.
    private static let notes = ChangelogRecipe(
        bundleID: bundleID,
        source: URL(string: "https://flyingmeat.com/acorn/releasenotes.html")!,
        entryPattern:
            #"<div\s+class="releaseT">\s*<div\s+class="releaseInfo">\s*(?:<a\b[^>]*>\s*)?<div\s+class="releaseTitleT">\s*Acorn\s+(?<version>8(?:\.[0-9]+)*(?:b[0-9]+)?)\s*</div>\s*(?:<div\s+class="releaseDate">[^<]*</div>\s*)?</div>(?<body>.*?)(?=<div\s+class="releaseT">|</body>|\z)"#,
        itemPatterns: [#"<(li|p|pre)\b[^>]*>(?<item>.*?)</\1\s*>"#],
        headingPattern: #"<h3\b[^>]*>\s*#?\s*(?<heading>.*?)</h3>"#)

    static func changelog(for item: SparkleAppcastItem, feedURL: URL) -> Changelog? {
        guard let html = item.descriptionHTML, let version = item.shortVersionString else { return nil }
        // The feed carries commented-out draft notes inside the HTML.
        let publishedHTML = html.replacingOccurrences(
            of: #"(?s)<!--.*?(?:-->|\z)"#, with: "", options: .regularExpression)
        guard let log = ChangelogExtractor.extract(from: publishedHTML, using: notes),
              let head = log.entries.first
        else { return nil }
        // Preview notes may label a section by the release series (e.g. 8.8)
        // rather than the offered build (8.8b1). Only the matching first block
        // can describe the offer; an adjacent stable block stays separate.
        if head.version != version {
            guard feedURL == betaFeed,
                  let suffix = version.range(of: #"b[0-9]+$"#, options: .regularExpression),
                  head.version == String(version[..<suffix.lowerBound])
            else { return nil }
        }
        let current = Changelog.Entry(version: version, date: AppcastMarkdownParser.displayDate(from: item.pubDate),
                                      items: head.items, content: head.content)
        return Changelog(entries: [current] + log.entries.dropFirst())
    }

    static let set = AppRecipeSet(
        family: "com-flyingmeat-Acorn8",
        bindingProofs: [
            ChannelProofKey(bundleID, .beta):
                .recipeAnchor(#"^https://flyingmeat\.com/download/latest/acorn8update\.xml$"#, in: ["feedOverride"]),
        ])
}
