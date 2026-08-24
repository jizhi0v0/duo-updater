import Foundation

/// Resolves updates for apps that ship a Sparkle `SUFeedURL`. Fetches the
/// appcast RSS, parses the items, filters to macOS releases the current system
/// can run, and returns the highest-versioned one.
public struct SparkleAppcastSource: UpdateSource {
    public let name = "Sparkle"

    private let session: URLSession
    private let currentSystemVersion: String

    public init(session: URLSession = .updates, currentSystemVersion: String? = nil) {
        self.session = session
        self.currentSystemVersion = currentSystemVersion
            ?? ProcessInfo.processInfo.operatingSystemVersionString
        // operatingSystemVersionString is verbose; prefer the numeric form.
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard let feedURL = app.sparkleFeedURL else { return nil }

        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 15
        // Always revalidate the appcast against the origin — never serve it from
        // the shared `URLCache` on max-age freshness alone. Some vendor CDNs stamp
        // a static feed with an absurd `Cache-Control: max-age` (Fork's fork.dev
        // sends ~10 years + `Expires: 2037`): under the default `.useProtocolCache`
        // policy the cached copy stays "fresh" effectively forever, so once we'd
        // fetched it we'd replay that stale feed and never see a new release — the
        // exact reason Fork 2.68.0 went undetected. `.reloadRevalidatingCacheData`
        // ignores freshness and sends a conditional GET (If-None-Match /
        // If-Modified-Since from the cached ETag/Last-Modified): unchanged → cheap
        // 304 served from cache, changed → 200 with the new feed. So we keep the
        // bandwidth win on quiet feeds without ever going blind to an update.
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        // Header-keyed apps (TablePlus) share one appcast across channels and let
        // a request header pick which builds the server returns. See `ChannelBinding`.
        for (field, value) in app.sparkleFeedHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SparkleError.badStatus(http.statusCode)
        }

        let items = SparkleAppcastParser.parse(data)
        let usable = Self.usableItems(for: app, from: items, osVersion: Self.numericSystemVersion())
        guard let best = usable.first else { return nil }

        // When the feed inlines Markdown notes (e.g. Surge's `<markdownDescription>`)
        // rather than HTML, parse them into a native, multi-version changelog so the
        // detail window renders entries instead of falling back to a web view.
        let structured = Self.structuredChangelog(from: usable)

        // Every in-channel item that carries a date — the appcast usually keeps the
        // last N releases, so this backfills the app's whole visible history into
        // the release timeline in one shot (not just the newest). Keyed on the same
        // version string the timeline dedupes by.
        let history: [ReleaseHistoryEntry] = usable.compactMap { item in
            guard let v = item.shortVersionString ?? item.version,
                  let date = ReleaseDate.parse(item.pubDate) else { return nil }
            return ReleaseHistoryEntry(version: v, publishedAt: date)
        }

        return RemoteVersion(
            shortVersion: best.shortVersionString,
            version: best.version,
            downloadURL: best.enclosureURL,
            downloadSize: best.enclosureLength,
            edSignature: best.edSignature,
            minimumSystemVersion: best.minimumSystemVersion,
            sourceName: name,
            minimumAutoupdateVersion: best.minimumAutoupdateVersion,
            releaseNotesHTML: best.descriptionHTML,
            structuredChangelog: structured,
            changelogURL: best.releaseNotesLink,
            publishedAt: ReleaseDate.parse(best.pubDate),
            releaseHistory: history,
            deltas: best.deltas
        )
    }

    /// Build a native changelog from the in-channel items that ship inline notes
    /// — either `<markdownDescription>` (Surge) or HTML `<description>` that has
    /// enough list structure to convert (`AppcastHTMLChangelogParser.isStructured`;
    /// verified against real TablePro/Fork/TablePlus feeds in the parser's own
    /// tests — a feed of pure `<p>` prose fails this and keeps rendering through
    /// the HTML fallback instead). Markdown wins when a feed carries both. Newest
    /// first, capped at `maxEntries` (this function has no caller-supplied cap, so
    /// a trimmed-history feed like TablePro's 137-item appcast doesn't turn into
    /// 137 rendered entries) — matches the cap-while-building style
    /// `StructuredChangelogDecoder.decodeWarp`/`decodeTypeless` use.
    ///
    /// Returns nil when no item produced any notes at all (the HTML
    /// `<description>` / web-view fallback paths stay in charge for those feeds).
    static func structuredChangelog(from usable: [SparkleAppcastItem]) -> Changelog? {
        let maxEntries = 40
        var entries: [Changelog.Entry] = []
        // One RELEASE can be several <item>s. TablePro publishes its 0.67.0 twice —
        // once per architecture (…-arm64.zip / …-x86_64.zip), same build, same
        // notes, `pubDate` one second apart — so walking items 1:1 rendered every
        // version twice in the rail. Key on the version the entry will display and
        // keep the first item that yields notes; that's the same defence
        // `ChangelogExtractor` already applies to pages that repeat their content.
        var seen: Set<String> = []
        for item in usable {
            if entries.count >= maxEntries { break }
            let version = item.shortVersionString ?? item.version ?? ""
            guard !version.isEmpty, !seen.contains(version) else { continue }
            let date = AppcastMarkdownParser.displayDate(from: item.pubDate)

            if let md = item.markdownDescription {
                let notes = AppcastMarkdownParser.items(from: md)
                guard !notes.isEmpty else { continue }
                entries.append(Changelog.Entry(version: version, date: date, items: notes))
                seen.insert(version)
                continue
            }

            if let html = item.descriptionHTML,
               let entry = AppcastHTMLChangelogParser.entry(html: html, version: version, date: date) {
                entries.append(entry)
                seen.insert(version)
            }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// Pick the best appcast item for an app: the highest-versioned, runnable,
    /// in-channel entry. Pure (no network) so the selection — especially the
    /// channel gating — is unit-testable.
    ///
    /// Sparkle gates prerelease items behind a `<sparkle:channel>`. The host app
    /// opts into a channel in code (`SPUUpdaterDelegate.allowedChannels`), which
    /// is compiled in and NOT exposed in Info.plist or the app's UserDefaults —
    /// so we can't read the subscription from outside the bundle. We infer it
    /// instead from the build the user is actually running: match the installed
    /// version to a feed item and read its channel. A stable build (default
    /// channel) is then never offered a prerelease, and a beta build is offered
    /// only same-channel betas — never a stable that may be incompatible. When
    /// the installed build isn't in the feed (trimmed history) we fall back to
    /// the default channel, the conservative choice that never pushes a surprise
    /// prerelease.
    static func bestItem(
        for app: InstalledApp,
        from items: [SparkleAppcastItem],
        osVersion: String,
        hostArch: HostArch = .current,
        allowingIntelTranslation canRunIntel: Bool = HostArch.canRunIntelBuilds
    ) -> SparkleAppcastItem? {
        usableItems(
            for: app, from: items, osVersion: osVersion,
            hostArch: hostArch, allowingIntelTranslation: canRunIntel
        ).first
    }

    /// The runnable, in-channel items for an app, highest version first. The head
    /// is the update we'd offer; the tail gives the changelog its version history.
    static func usableItems(
        for app: InstalledApp,
        from items: [SparkleAppcastItem],
        osVersion: String,
        hostArch: HostArch = .current,
        allowingIntelTranslation canRunIntel: Bool = HostArch.canRunIntelBuilds
    ) -> [SparkleAppcastItem] {
        guard !items.isEmpty else { return [] }
        // Sparkle's real rule: the default (untagged) channel is allowed to
        // everyone, plus the one channel the user opted into. We learn that
        // channel authoritatively from the app's own preference when we can
        // (this catches "opted into beta but still on a stable build", which the
        // installed build alone can't reveal); otherwise we infer it from the
        // build they're running.
        let optedChannel = app.channelIsAuthoritative
            ? sparkleChannelName(app.releaseChannel)
            : channel(ofInstalled: app, in: items)
        let allowed: Set<String?> = optedChannel == nil ? [nil] : [nil, optedChannel]
        let usable = items.filter { item in
            // Skip delta updates — they patch a specific old build.
            guard item.deltaFrom == nil else { return false }
            // Skip items with no usable version: their comparisonKey falls back to
            // "0", so a malformed feed entry would otherwise surface as a phantom
            // (and produce a RemoteVersion with no version) instead of "no update".
            guard item.version != nil || item.shortVersionString != nil else { return false }
            // Default channel ∪ the user's channel — never a higher one.
            guard allowed.contains(normalizeChannel(item.channel)) else { return false }
            // Honor minimum system version when declared.
            if let minOS = item.minimumSystemVersion, !minOS.isEmpty,
               VersionComparator.compare(osVersion, minOS) == .orderedAscending {
                return false
            }
            // A per-architecture twin (TablePro publishes an arm64 and an x86_64
            // item per release, same version) this Mac cannot run at all — never
            // offer it, changelog history included. See `archVerdict`.
            return archVerdict(for: item, hostArch: hostArch, canRunIntel: canRunIntel) != .unrunnable
        }
        // Deterministic tie-break on equal versions. `sorted(by:)` is NOT a stable
        // sort in Swift, so per-architecture twins could come back in either order
        // from run to run — and the changelog dedupe below keeps the FIRST item
        // that yields notes. Rank the twin built for this Mac first; only fall
        // back to the enclosure URL when architecture doesn't disambiguate
        // (identical bodies, or neither item names an architecture at all).
        return usable.sorted { (lhs: SparkleAppcastItem, rhs: SparkleAppcastItem) -> Bool in
            switch VersionComparator.compare(lhs.comparisonKey, rhs.comparisonKey) {
            case .orderedDescending: return true
            case .orderedAscending: return false
            case .orderedSame:
                let lRank = archVerdict(for: lhs, hostArch: hostArch, canRunIntel: canRunIntel)
                let rRank = archVerdict(for: rhs, hostArch: hostArch, canRunIntel: canRunIntel)
                if lRank != rRank { return lRank < rRank }
                return (lhs.enclosureURL?.absoluteString ?? "") < (rhs.enclosureURL?.absoluteString ?? "")
            }
        }
    }

    /// How well an item's download suits this Mac, cheapest-to-worst. Two
    /// signals feed it, in priority order:
    ///
    ///  1. `<sparkle:hardwareRequirements>` — Sparkle's own structured gate
    ///     (comma-delimited; today the only value it defines is "arm64").
    ///     TablePro's real appcast sets it on exactly the arm64-native item of
    ///     each release pair and leaves the x86_64 twin untagged
    ///     (fetched 2026-08-24: raw.githubusercontent.com/TableProApp/TablePro/
    ///     main/appcast.xml). It requires Apple-silicon hardware — never
    ///     satisfiable on a real Intel Mac, which has no reverse Rosetta — so a
    ///     tagged item is `.unrunnable` there regardless of anything else.
    ///     https://sparkle-project.org/documentation/publishing/#minimum-system-version-requirements
    ///  2. Filename tokens on the enclosure, exactly like
    ///     `GitHubReleaseRule.installableAsset`: native beats an arch-neutral
    ///     build beats a foreign-arch one, and a foreign-arch build is only
    ///     `.foreignButRunnable` (never preferred, but not excluded) while this
    ///     Mac can still translate it — i.e. only Apple silicon, and only
    ///     `HostArch.canRunIntelBuilds`. This is the fallback for the vendors
    ///     that don't set the Sparkle tag at all, and it's also what actually
    ///     resolves the TablePro pair: only the arm64 item carries the tag, so
    ///     without this the untagged x86_64 twin would tie with it.
    private static func archVerdict(
        for item: SparkleAppcastItem, hostArch: HostArch, canRunIntel: Bool
    ) -> ArchVerdict {
        if item.hardwareRequirements.contains("arm64"), hostArch != .arm64 {
            return .unrunnable
        }
        let name = (item.enclosureURL?.lastPathComponent ?? "").lowercased()
        func has(_ tokens: [String]) -> Bool { tokens.contains { name.contains($0) } }
        if has(hostArch.assetTokens), !has(hostArch.foreignTokens) { return .native }
        if !has(hostArch.assetTokens), !has(hostArch.foreignTokens) { return .neutral }
        // Named for the other architecture. Only Apple silicon can still run an
        // Intel build (via Rosetta, and only while `canRunIntel` holds) — the
        // reverse direction has never worked, an arm64 build has never run on
        // an Intel Mac.
        return (hostArch == .arm64 && canRunIntel) ? .foreignButRunnable : .unrunnable
    }

    private enum ArchVerdict: Int, Comparable {
        case native, neutral, foreignButRunnable, unrunnable
        static func < (lhs: ArchVerdict, rhs: ArchVerdict) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The Sparkle channel the installed build sits on, found by matching the
    /// installed version to a feed item — build number first (Sparkle's
    /// canonical key), then the marketing string. nil = the default (stable)
    /// channel, either because the matched item carried no `<sparkle:channel>`
    /// or because the installed build isn't in the feed at all.
    static func channel(ofInstalled app: InstalledApp, in items: [SparkleAppcastItem]) -> String? {
        let match = items.first { item in
            if let b = app.buildVersion, let v = item.version, !b.isEmpty, b == v {
                return true
            }
            if let s = app.shortVersion, let sv = item.shortVersionString, !s.isEmpty, s == sv {
                return true
            }
            return false
        }
        return normalizeChannel(match?.channel)
    }

    /// Collapse an absent or whitespace-only channel to nil so the default
    /// channel compares equal however the feed spells it.
    static func normalizeChannel(_ raw: String?) -> String? {
        guard let c = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else {
            return nil
        }
        return c
    }

    /// The `<sparkle:channel>` name for a release channel — nil for stable (the
    /// default, untagged channel), else the channel's raw name ("beta",
    /// "canary", …), which is how feeds spell it.
    static func sparkleChannelName(_ channel: ReleaseChannel) -> String? {
        channel == .stable ? nil : channel.rawValue
    }

    /// e.g. "26.6.0" — used to evaluate `minimumSystemVersion`.
    static func numericSystemVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// A feed fetch that came back with a non-200. `LocalizedError`, not a bare
    /// `Error`: without a description this surfaced as "The operation couldn't be
    /// completed. (DuoUpdaterCore.SparkleAppcastSource.SparkleError error 0.)" — a
    /// message that names the enum case index and hides the one fact that matters.
    /// Alfred's feed 404'd for weeks behind exactly that text.
    enum SparkleError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(404):
                return "The app's update feed returned HTTP 404 — the vendor moved or retired it."
            case .badStatus(let code):
                return "The app's update feed returned HTTP \(code)."
            }
        }
    }
}

// MARK: - Appcast parsing

struct SparkleAppcastItem {
    var shortVersionString: String?
    var version: String?
    var enclosureURL: URL?
    /// `<enclosure length>` — the declared download size in bytes, used to
    /// order "Update All" shortest-first. Absent on feeds that omit it.
    var enclosureLength: Int64?
    var edSignature: String?
    var minimumSystemVersion: String?
    var deltaFrom: String?
    /// Patches published alongside this release inside `<sparkle:deltas>`, each
    /// naming the one build it upgrades from. Empty for the vast majority of feeds.
    var deltas: [DeltaPatch] = []
    /// `<sparkle:channel>` — names a non-default release track (e.g. "beta").
    /// nil/absent means the default (stable) channel, which Sparkle always ships.
    var channel: String?
    /// `<sparkle:hardwareRequirements>` — a comma-delimited list Sparkle itself
    /// defines and enforces client-side; today the only value it recognizes is
    /// "arm64", meaning this item's build requires Apple-silicon hardware.
    /// Lowercased on parse. Empty for the vast majority of feeds (only vendors
    /// publishing separate per-architecture items, like TablePro, set it).
    var hardwareRequirements: Set<String> = []
    /// `<sparkle:minimumAutoupdateVersion>` — the vendor-declared build version
    /// below which this release must never silently auto-install. Sparkle derives
    /// `SUAppcastItem.majorUpgrade` from it, and vendors set it at a paid/license
    /// boundary or other notable upgrade. Expressed in `sparkle:version` (build)
    /// terms. Absent for the vast majority of feeds.
    var minimumAutoupdateVersion: String?
    /// Inline release notes — the `<description>` body, usually CDATA-wrapped HTML.
    var descriptionHTML: String?
    /// Inline release notes shipped as Markdown via `<markdownDescription>` — some
    /// feeds (e.g. Surge) publish only this and no HTML `<description>`. Parsed
    /// into a structured changelog so the notes render natively instead of falling
    /// back to a web view.
    var markdownDescription: String?
    /// `<pubDate>` — the item's publish date, verbatim. RSS spells this many ways
    /// (RFC822, ISO8601, or a bare Unix epoch as Surge does); kept raw and
    /// normalized only when we build a changelog entry.
    var pubDate: String?
    /// `<sparkle:releaseNotesLink>` — an external notes page, when the feed links
    /// out instead of (or in addition to) inlining them.
    var releaseNotesLink: URL?

    /// Prefer the build version (Sparkle's canonical key); fall back to short.
    var comparisonKey: String { version ?? shortVersionString ?? "0" }
}

/// Minimal XMLParser-backed appcast reader. Version metadata in Sparkle feeds
/// may live either on the `<enclosure>` attributes or as child elements of
/// `<item>`; we collect both.
final class SparkleAppcastParser: NSObject, XMLParserDelegate {

    static func parse(_ data: Data) -> [SparkleAppcastItem] {
        let parser = XMLParser(data: data)
        let delegate = SparkleAppcastParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private var items: [SparkleAppcastItem] = []
    private var current: SparkleAppcastItem?
    private var textBuffer = ""
    /// Depth inside `<sparkle:deltas>`, whose children are `<enclosure>` elements
    /// for INCREMENTAL patches — not the item's download. Sparkle names them with
    /// the same tag as the real one, so a parser that treats every enclosure alike
    /// ends up holding the last delta it saw: the item's URL becomes
    /// `Rectangle104-99.delta` and `deltaFrom` gets set, which `usableItems` then
    /// (correctly) rejects. Every item in the feed is dropped that way and the app
    /// reports "no source applied" — Rectangle and Keka were both invisible for
    /// exactly this reason, with no error anywhere to say so.
    private var deltasDepth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        textBuffer = ""
        switch elementName {
        case "item":
            current = SparkleAppcastItem()
        case "sparkle:deltas":
            deltasDepth += 1
        case "enclosure":
            // Inside <sparkle:deltas> this is a patch, not the release download.
            // Collected rather than merely skipped: it is the same release, reachable
            // for a fraction of the bytes when its `deltaFrom` is the build on disk.
            // Everything below still runs only for the real enclosure — letting a
            // patch through would restore the hijack this depth counter exists to
            // prevent (`deltaEnclosuresDontHijackTheItemsDownload`).
            guard deltasDepth == 0 else {
                if let urlString = attributeDict["url"],
                   let url = URL(string: urlString),
                   let from = attributeDict["sparkle:deltaFrom"] {
                    current?.deltas.append(DeltaPatch(
                        fromBuild: from,
                        url: url,
                        size: attributeDict["length"].flatMap { Int64($0) },
                        edSignature: attributeDict["sparkle:edSignature"]))
                }
                break
            }
            current?.enclosureURL = attributeDict["url"].flatMap { URL(string: $0) }
            if let length = attributeDict["length"], let n = Int64(length) {
                current?.enclosureLength = n
            }
            if let v = attributeDict["sparkle:version"] { current?.version = v }
            if let s = attributeDict["sparkle:shortVersionString"] {
                current?.shortVersionString = s
            }
            if let sig = attributeDict["sparkle:edSignature"] {
                current?.edSignature = sig
            }
            if let delta = attributeDict["sparkle:deltaFrom"] {
                current?.deltaFrom = delta
            }
            // Usually an item-level child element, but tolerate it on enclosure.
            if let m = attributeDict["sparkle:minimumAutoupdateVersion"] {
                current?.minimumAutoupdateVersion = m
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    /// Release notes in `<description>` are almost always CDATA-wrapped HTML,
    /// which arrives here rather than through `foundCharacters`.
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        textBuffer += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "sparkle:deltas":
            deltasDepth = max(0, deltasDepth - 1)
        case "sparkle:version":
            if current?.version == nil, !text.isEmpty { current?.version = text }
        case "sparkle:shortVersionString":
            if current?.shortVersionString == nil, !text.isEmpty {
                current?.shortVersionString = text
            }
        case "sparkle:minimumSystemVersion":
            current?.minimumSystemVersion = text
        case "sparkle:channel":
            if current?.channel == nil, !text.isEmpty { current?.channel = text }
        case "sparkle:hardwareRequirements":
            if !text.isEmpty {
                current?.hardwareRequirements = Set(
                    text.lowercased().split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) })
            }
        case "sparkle:minimumAutoupdateVersion":
            if current?.minimumAutoupdateVersion == nil, !text.isEmpty {
                current?.minimumAutoupdateVersion = text
            }
        case "description":
            // Only inside an <item>; the channel-level <description> has no
            // `current` to attach to, so it's harmlessly dropped.
            if !text.isEmpty { current?.descriptionHTML = text }
        case "markdownDescription", "sparkle:markdownDescription":
            if current?.markdownDescription == nil, !text.isEmpty {
                current?.markdownDescription = text
            }
        case "pubDate":
            if current?.pubDate == nil, !text.isEmpty { current?.pubDate = text }
        case "sparkle:releaseNotesLink":
            if current?.releaseNotesLink == nil, !text.isEmpty {
                current?.releaseNotesLink = URL(string: text)
            }
        case "item":
            if let item = current { items.append(item) }
            current = nil
        default:
            break
        }
        textBuffer = ""
    }
}
