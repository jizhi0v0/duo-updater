import Foundation

/// Resolves updates for apps that ship a Sparkle `SUFeedURL`. Fetches the
/// appcast RSS, parses the items, filters to macOS releases the current system
/// can run, and returns the highest-versioned one.
public struct SparkleAppcastSource: UpdateSource {
    public let name = "Sparkle"

    // Not private: `readFeed` (SparkleFeedProbe.swift) is the same fetch with no
    // installed copy behind it, and a sweep that opened its own session would be
    // sweeping a different client than the one that ships.
    let session: URLSession

    public init(session: URLSession = .updates) {
        self.session = session
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard let feedURL = app.sparkleFeedURL else { return nil }

        let request = Self.feedRequest(url: feedURL, headers: app.sparkleFeedHeaders)

        let (data, response) = try await session.versionFeedData(
            for: request, label: "Sparkle \(app.name)")
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SparkleError.badStatus(http.statusCode)
        }

        let items = SparkleAppcastParser.parse(data, relativeTo: feedURL)
        let osVersion = Self.numericSystemVersion()
        let usable = Self.usableItems(for: app, from: items, osVersion: osVersion)
        guard let best = Self.offerableItem(for: app, from: usable) else {
            if let (refusal, missed) = Self.osWindowRefusal(for: app, from: items, osVersion: osVersion) {
                Log.source.notice(
                    "sparkle: \(app.bundleID ?? "?", privacy: .public) — nothing to offer, \(refusal.logDescription, privacy: .public)")
                // The release as this source would have reported it, so the checker
                // can ask whether it was an update at all (`OSWindowRefused`).
                throw OSWindowRefused(refusal, release: RemoteVersion(
                    shortVersion: missed.shortVersionString,
                    version: missed.version,
                    marketingMatchesBundle: true,
                    downloadURL: missed.enclosureURL,
                    sourceName: name))
            }
            return nil
        }
        // The offer is not the head only when the head would walk this copy
        // backwards (see `offerableItem`). Log it with both builds: without them
        // this reads exactly like an ordinary "you are ahead of your feed" row,
        // and it is the build that made the head an OFFER rather than a no-op.
        if let head = usable.first, head.version != best.version {
            Log.source.info(
                "sparkle: \(app.bundleID ?? "?", privacy: .public) — offering \(best.shortVersionString ?? "?", privacy: .public)/\(best.version ?? "?", privacy: .public) instead of the feed's newest \(head.shortVersionString ?? "?", privacy: .public)/\(head.version ?? "?", privacy: .public), which is older than the installed \(app.shortVersion ?? "?", privacy: .public)/\(app.buildVersion ?? "?", privacy: .public)")
        }

        // When the feed inlines Markdown notes (e.g. Surge's `<markdownDescription>`)
        // rather than HTML, parse them into a native, multi-version changelog so the
        // detail window renders entries instead of falling back to a web view.
        let structured = Self.structuredChangelog(from: usable)

        // Every in-channel item that carries a date — the appcast usually keeps the
        // last N releases, so this backfills the app's whole visible history into
        // the release timeline in one shot (not just the newest). Keyed on the same
        // version string, and read through the same `publishedFields` call, that the
        // timeline dedupes by — so the newest item does not double-record.
        let history = Self.releaseHistory(from: usable)
        let bestFields = ReleaseDate.publishedFields(from: best.pubDate)

        return RemoteVersion(
            shortVersion: best.shortVersionString,
            version: best.version,
            // `sparkle:shortVersionString` IS the bundle's own
            // `CFBundleShortVersionString` — it is the string the vendor's own
            // Sparkle compares — so `evaluate` may weigh it against the installed
            // one and refuse a build that walks it backwards. See #368.
            marketingMatchesBundle: true,
            downloadURL: best.enclosureURL,
            downloadSize: best.enclosureLength,
            edSignature: best.edSignature,
            minimumSystemVersion: best.minimumSystemVersion,
            sourceName: name,
            minimumAutoupdateVersion: best.minimumAutoupdateVersion,
            releaseNotesHTML: best.descriptionHTML,
            structuredChangelog: structured,
            changelogURL: best.releaseNotesLink,
            publishedAt: bestFields.publishedAt,
            vendorDay: bestFields.vendorDay,
            releaseHistory: history,
            deltas: best.deltas
        )
    }

    /// The one request shape every appcast fetch uses — the live check and
    /// `duo verify`'s feed sweep alike.
    ///
    /// Extracted rather than copied because a sweep that builds its own request
    /// is not sweeping the request production makes — and every field below is
    /// load-bearing enough that a second copy drifting from this one would be a
    /// sweep whose green answer says nothing about the app.
    ///
    /// Always revalidate the appcast against the origin — never serve it from
    /// the shared `URLCache` on max-age freshness alone. Some vendor CDNs stamp
    /// a static feed with an absurd `Cache-Control: max-age` (Fork's fork.dev
    /// sends ~10 years + `Expires: 2037`): under the default `.useProtocolCache`
    /// policy the cached copy stays "fresh" effectively forever, so once we'd
    /// fetched it we'd replay that stale feed and never see a new release — the
    /// exact reason Fork 2.68.0 went undetected. `.reloadRevalidatingCacheData`
    /// ignores freshness and sends a conditional GET (If-None-Match /
    /// If-Modified-Since from the cached ETag/Last-Modified): unchanged → cheap
    /// 304 served from cache, changed → 200 with the new feed. So we keep the
    /// bandwidth win on quiet feeds without ever going blind to an update.
    ///
    /// `headers` is for the header-keyed apps (TablePlus) that share one appcast
    /// across channels and let a request header pick which builds the server
    /// returns. See `ChannelBinding`.
    static func feedRequest(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.setValue("DuoUpdater/0.1", forHTTPHeaderField: "User-Agent")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }

    /// Every in-channel item with a parseable vendor date, turned into a
    /// timeline entry at whatever precision the vendor actually stated (see
    /// `ReleaseDate.publishedFields(from:)` — Eudic's appcast is the fixture
    /// that proves a bare calendar day, `<pubDate>2026-08-31</pubDate>`, routes
    /// to `vendorDay` rather than a fabricated midnight `publishedAt`, #239).
    /// Pure and separated from `latestVersion` so the day/minute routing is
    /// unit-testable without a network fetch.
    static func releaseHistory(from usable: [SparkleAppcastItem]) -> [ReleaseHistoryEntry] {
        usable.compactMap { item in
            guard let v = item.shortVersionString ?? item.version else { return nil }
            let fields = ReleaseDate.publishedFields(from: item.pubDate)
            guard fields.publishedAt != nil || fields.vendorDay != nil else { return nil }
            return ReleaseHistoryEntry(version: v, publishedAt: fields.publishedAt, vendorDay: fields.vendorDay)
        }
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
    /// in-channel entry, stepping over a head that would walk the user's
    /// marketing version backwards when the feed has something better below it
    /// (see `offerableItem`). Pure (no network) so the selection — especially the
    /// channel gating — is unit-testable.
    ///
    /// Sparkle gates prerelease items behind a `<sparkle:channel>`. The host app
    /// opts into a channel in code (`SPUUpdaterDelegate.allowedChannels`), which
    /// is compiled in and NOT exposed in Info.plist or the app's UserDefaults —
    /// so we can't read the subscription from outside the bundle. We infer it
    /// instead from the build the user is actually running: match the installed
    /// version to a feed item and read its channel. A stable build (default
    /// channel) is then never offered a prerelease, and a beta build is offered its
    /// own channel's prereleases IN ADDITION to the default channel — so a newer
    /// stable is still offered, and only prereleases from channels this copy is not
    /// on are withheld. When
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
        offerableItem(
            for: app,
            from: usableItems(
                for: app, from: items, osVersion: osVersion,
                hostArch: hostArch, allowingIntelTranslation: canRunIntel))
    }

    /// Why a feed that offers nothing offers nothing, when the reason is the
    /// vendor's OS window — or nil when it is anything else.
    ///
    /// Only the window is set aside: channel, delta, architecture and version-less
    /// items stay filtered. So a non-nil answer means "without the window there
    /// WAS a release for this copy, and the vendor says it is not for this macOS";
    /// a feed emptied by the channel or architecture filters stays a plain nil,
    /// which is still the honest "nothing here for this app".
    ///
    /// The release named is the one the copy would have been offered
    /// (`offerableItem`), returned with the refusal so the caller can report it
    /// as a release. Whether it would have been an UPDATE is not decided here:
    /// `offerableItem` answers the head even when it walks the copy backwards,
    /// and a copy already on (or past) the refused build must not be told it is
    /// missing it — `UpdateChecker` asks `evaluate(installed:remote:)` that.
    ///
    /// Called only once `usableItems` came back empty, so every item this sees
    /// was refused by the window; the evaluation is repeated rather than assumed,
    /// and a nil from it (which that precondition makes unreachable) stays nil.
    static func osWindowRefusal(
        for app: InstalledApp,
        from items: [SparkleAppcastItem],
        osVersion: String,
        hostArch: HostArch = .current,
        allowingIntelTranslation canRunIntel: Bool = HostArch.canRunIntelBuilds
    ) -> (refusal: OSWindowRefusal, item: SparkleAppcastItem)? {
        let unwindowed = usableItems(
            for: app, from: items, osVersion: osVersion,
            hostArch: hostArch, allowingIntelTranslation: canRunIntel, honouringOSWindow: false)
        guard let missed = offerableItem(for: app, from: unwindowed),
              let refusal = OSWindowRefusal.evaluate(
                  minimum: missed.minimumSystemVersion, maximum: missed.maximumSystemVersion,
                  osVersion: osVersion, version: missed.shortVersionString ?? missed.version ?? "")
        else { return nil }
        return (refusal, missed)
    }

    /// The runnable, in-channel items for an app, highest version first. The head
    /// is the update we'd offer; the tail gives the changelog its version history.
    ///
    /// `honouringOSWindow: false` skips the vendor's OS floor and ceiling and
    /// nothing else. It exists for one question only — "was it the OS window that
    /// left nothing to offer?" (`latestVersion(for:)`) — and is never what an offer
    /// is picked from.
    static func usableItems(
        for app: InstalledApp,
        from items: [SparkleAppcastItem],
        osVersion: String,
        hostArch: HostArch = .current,
        allowingIntelTranslation canRunIntel: Bool = HostArch.canRunIntelBuilds,
        honouringOSWindow: Bool = true
    ) -> [SparkleAppcastItem] {
        guard !items.isEmpty else { return [] }
        // Sparkle's real rule: the default (untagged) channel is allowed to
        // everyone, plus whatever the user opted into — read from the app's own
        // preference when a binding exists (this catches "opted into beta but
        // still on a stable build", which the installed build alone can't
        // reveal), else inferred from the build they're running. See
        // `allowedChannels`.
        let allowed = allowedChannels(for: app, in: items)
        let usable = items.filter { item in
            // Skip delta updates — they patch a specific old build.
            guard item.deltaFrom == nil else { return false }
            // Skip items with no usable version: their comparisonKey falls back to
            // "0", so a malformed feed entry would otherwise surface as a phantom
            // (and produce a RemoteVersion with no version) instead of "no update".
            guard item.version != nil || item.shortVersionString != nil else { return false }
            // Default channel ∪ the user's channel — never a higher one.
            guard allowed.contains(normalizeChannel(item.channel)) else { return false }
            // The vendor's OS window: the floor it states for the item, and the
            // ceiling — "this build is not for an OS this new", the only way any
            // source we read can say "we haven't adapted to macOS 27 yet". Both
            // predicates live in `OSWindowRefusal.evaluate`: the floor is
            // `SignatureVerifier.canRun`, the one every OS floor calls (see
            // `HostOS`, #640), the ceiling is Sparkle's own
            // (`SPUAppcastItemStateResolver -isMaximumOperatingSystemVersionOK:`
            // is `!= NSOrderedAscending` on max-vs-host). `VendorProbeSource` calls
            // the same function for a recipe's response-read bounds, so the two
            // paths cannot drift.
            //
            // Dropping the item is Sparkle's own choice of what to OFFER. Its
            // REPORTING differs, and that part is ours too now: Sparkle keeps the
            // condition and names it (`SPUBasicUpdateDriver.m` "Your macOS version
            // is too new", `SPUNoUpdateFoundInfo.m` an explanation carrying the
            // version and the cap). When the window is what left nothing to offer,
            // `latestVersion(for:)` throws `OSWindowRefused` instead of returning
            // nil — nil meant `.unknown`, the "no source covers this app" dash, and
            // for a ceiling that dash never went away on its own: a min-filtered
            // item reappears when the user upgrades macOS, a max-filtered one waits
            // on the vendor (#634).
            //
            // Note this also removes refused items from `structuredChangelog` and
            // `releaseHistory` below, since both read this same list — consistent
            // with what the architecture filter already does ("never offer it,
            // changelog history included"), and called out because it is a
            // behaviour change that no test covers.
            //
            // Rare, not dead: none of the 14 reachable feeds among this machine's
            // installed Sparkle apps declared one (2026-08-30), but WeChat's feed
            // caps 3 of its 7 items — that one is read by `VendorProbeSource`,
            // which consults a bound only where the recipe declares a pattern
            // for it (WeChat's does not; its capped items are old OS buckets
            // that lose the highest-version pick anyway), so this filter never
            // sees it.
            if honouringOSWindow, OSWindowRefusal.evaluate(
                minimum: item.minimumSystemVersion, maximum: item.maximumSystemVersion,
                osVersion: osVersion, version: item.shortVersionString ?? item.version ?? "") != nil {
                return false
            }
            // A per-architecture twin (TablePro publishes an arm64 and an x86_64
            // item per release, same version) this Mac cannot run at all — never
            // offer it, changelog history included. See `archVerdict`.
            return archVerdict(for: item, hostArch: hostArch, canRunIntel: canRunIntel) != .unrunnable
        }
        // Tie-break on equal versions, because the comparison alone does not say
        // which of a release's per-architecture twins wins and the changelog dedupe
        // below keeps the FIRST item that yields notes. Not a stability repair:
        // Swift's sort IS stable and documented as such (SE-0372, Swift 5.8 —
        // "The sorting algorithm is guaranteed to be stable"), so without this the
        // winner would simply be whichever twin the VENDOR happened to list first,
        // which is their layout decision leaking into which enclosure we install.
        // Rank the twin built for this Mac first; only fall back to the enclosure
        // URL when architecture doesn't disambiguate (identical bodies, or neither
        // item names an architecture at all), which makes the answer depend on the
        // items themselves rather than on their order in the feed.
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

    /// The item to REPORT out of `usableItems` — its head, unless a lower entry
    /// is the one this copy should actually be offered.
    ///
    /// The list is ranked by `comparisonKey`, i.e. the BUILD, and the ranking is
    /// cross-channel. So when a vendor's builds run monotonically across two
    /// trains, the head can be a release that is numerically newer and
    /// functionally older than what a prerelease copy is running — CotEditor
    /// publishes 7.0.9 at build 843 above 7.1.0-beta.6 at 845, and a copy on
    /// 7.1.0-beta.3 whose build the vendor has trimmed out of the feed sees only
    /// the default channel and lands on 7.0.9 (#368).
    ///
    /// Two halves, and the split matters:
    ///
    ///  - **Which item to name.** Here. Stepping over a marketing downgrade lets
    ///    the copy find the entry it should actually take when the feed has one —
    ///    the next beta sitting BELOW a stable patch in build order, which taking
    ///    the head unconditionally would hide.
    ///  - **Whether it is an update.** Not here. `UpdateChecker.evaluate` asks the
    ///    marketing version again before it puts an Update button on a row, and
    ///    that is the half that actually protects the user (it also covers the
    ///    case below, where every entry is a downgrade and there is nothing to
    ///    step onto).
    ///
    /// ⚠️ **It never answers nil for a feed that had usable items.** Being ahead
    /// of your own feed is ordinary — a vendor pulls a release, or trims the build
    /// you are running — and those rows read "up to date" beside the feed's newest
    /// entry today. Withholding the answer instead makes `latestVersion` return
    /// nil, and nil means `.unknown`, whose own documentation is "no source COVERS
    /// this app, nothing was tried" — rendered as a dead "—" with no retry. That
    /// would be a false statement about an app whose feed we just read, and it
    /// would take the release notes and the release timeline with it. Simulated
    /// over all 13 Sparkle feeds this Mac reads, with the installed build trimmed
    /// out of each in turn, withholding hit 12 (app, version) pairs: Bartender
    /// 6.6.2 against a feed topping out at 6.6.1, six DuoPaste betas, Ghostty,
    /// IINA, MonitorControl, Rectangle, Surge.
    ///
    /// The accepted cost, stated rather than left to be discovered: a copy on an
    /// ABANDONED prerelease train — vendor ships 2.0-beta, cancels 2.0, keeps
    /// shipping 1.6, 1.7 on stable — is no longer moved onto the maintained line.
    /// It reads "up to date" against a version it can see is newer by date and
    /// older by number, and nothing offers it a way across. That was the one real
    /// user of the old behaviour, and there is no state in `RowActionState` that
    /// says "your train was withdrawn".
    static func offerableItem(
        for app: InstalledApp, from usable: [SparkleAppcastItem]
    ) -> SparkleAppcastItem? {
        guard let head = usable.first else { return nil }
        guard isMarketingDowngrade(head, for: app) else { return head }
        // Past a head that walks backwards, "cannot tell" is not good enough, and
        // neither is an entry that cannot be installed. `usableItems` admits an
        // item with NO enclosure at all (its filter asks only for a version), and
        // before this scan existed such an entry was reachable only by topping the
        // build ranking. Requiring the artifact keeps this from newly promoting
        // one into an Update button over a nil download.
        return usable.dropFirst().first {
            $0.enclosureURL != nil && !isMarketingDowngrade($0, for: app)
                && VersionComparator.comparableMarketingVersion($0.shortVersionString) != nil
        } ?? head
    }

    /// Whether taking `item` would walk this copy's marketing version backwards.
    ///
    /// Only `shortVersionString` is read. Fork's feed states none at all — its
    /// marketing string lives in `sparkle:version` ("2.66.7") — and reaching for
    /// `shortVersionString ?? version` here would compare a BUILD field against a
    /// marketing one, the namespace mistake `VersionComparator`'s pair API exists
    /// to prevent. The shape test that follows is in `VersionComparator`, with the
    /// Ghostty tip-build label that motivates it.
    static func isMarketingDowngrade(_ item: SparkleAppcastItem, for app: InstalledApp) -> Bool {
        VersionComparator.isMarketingDowngrade(
            offered: item.shortVersionString, from: app.shortVersion)
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
        // Sparkle's structured requirement is authoritative. On Apple silicon it
        // proves the item is compatible even if an unrelated part of the product
        // name resembles a filename token (for example, `IntelliJ-…-arm64.zip`).
        if item.hardwareRequirements.contains("arm64") {
            return hostArch == .arm64 ? .native : .unrunnable
        }
        let name = (item.enclosureURL?.lastPathComponent ?? "").lowercased()
        let native = hostArch.isMarked(inAssetName: name)
        let foreignArch: HostArch = hostArch == .arm64 ? .x86_64 : .arm64
        let foreign = foreignArch.isMarked(inAssetName: name)
        if native && !foreign { return .native }
        // Neither marker means an ordinary neutral name; both markers explicitly
        // describe a fat/universal artifact.
        if native == foreign { return .neutral }
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

    /// The `<sparkle:channel>` values an app may be offered: always the default
    /// (untagged) channel, plus whatever the user opted into.
    ///
    /// Three ways we learn the opt-in, most authoritative first:
    ///  1. A `ChannelBinding` that named the feed's tags outright
    ///     (`sparkleChannelNames`). Needed when the feed does not spell a channel
    ///     the way `ReleaseChannel.rawValue` does — BetterDisplay tags `pre` and
    ///     `internal`, neither of which is a `ReleaseChannel` case — and needed as
    ///     a Set because one opt-in can unlock several tags at once (BetterDisplay's
    ///     "internal" toggle also keeps the plain `pre` builds).
    ///  2. A `ChannelBinding` that only named the channel: derive the tag from it,
    ///     which is what every binding did before (1) existed and still what
    ///     DuoPaste/Fork/OrbStack/… want.
    ///  3. No binding: infer from the build the user is actually running.
    ///
    /// Kept as one function so the "default channel is always allowed" rule can't
    /// drift between the branches.
    static func allowedChannels(
        for app: InstalledApp, in items: [SparkleAppcastItem]
    ) -> Set<String?> {
        var allowed: Set<String?> = [nil]
        guard app.channelIsAuthoritative else {
            if let inferred = channel(ofInstalled: app, in: items) { allowed.insert(inferred) }
            return allowed
        }
        if !app.sparkleChannelNames.isEmpty {
            for name in app.sparkleChannelNames { allowed.insert(name) }
            return allowed
        }
        if let derived = sparkleChannelName(app.releaseChannel) { allowed.insert(derived) }
        return allowed
    }

    /// Find the feed item that describes an installed build. Prefer a byte-for-byte
    /// match before accepting a comparator-equivalent spelling: normalization must
    /// not let an earlier `1.0.0` entry steal a later exact `1.0` match.
    static func item(
        matchingInstalledBuild build: String,
        in items: [SparkleAppcastItem]
    ) -> SparkleAppcastItem? {
        if let exact = items.first(where: { $0.version == build }) { return exact }
        let installedBuild = VersionSide(build: build)
        return items.first(where: {
            VersionComparator.isSame(
                VersionSide(build: $0.version), as: installedBuild)
        })
    }

    /// The Sparkle channel the installed build sits on, found by matching the
    /// installed version to a feed item — build number first (Sparkle's
    /// canonical key), then the marketing string. nil = the default (stable)
    /// channel, either because the matched item carried no `<sparkle:channel>`
    /// or because the installed build isn't in the feed at all.
    ///
    /// TWO passes, and the order between them is the whole point: the build is
    /// scanned across EVERY item before the marketing string is tried on any of
    /// them. One pass that took the first item matching on *either* key read the
    /// weaker key off an earlier item and never reached the exact build match
    /// later in the feed — and prerelease trains are exactly where marketing
    /// strings collide, because a prerelease usually keeps the release's
    /// `CFBundleShortVersionString`. Both multi-channel feeds audited on
    /// 2026-08-31 misfired that way, verified against the real bundles:
    ///
    /// - Supacode `tip` (build `1787740786`) is item #10, tagged `tip`; item #0
    ///   is the default `0.10.8` — the same short string the tip build carries.
    /// - TypeWhisper `release-candidate` (build `1083`) is item #2; item #1 is
    ///   the default `1.6.0`, and the rc bundle's short string is also `1.6.0`.
    ///
    /// Both read as the default channel, which makes the user's OWN train
    /// invisible: `usableItems` drops every `tip`/`rc` entry, so the next build
    /// on that train is never offered and the notes and history come from the
    /// stable line instead. It does not show up as a wrong version being pushed
    /// — the default channel is allowed to everyone, so whenever stable is the
    /// newer of the two (it was, in both feeds on the day) the offered version
    /// is identical either way. That is what makes it quiet. Feeds whose
    /// prerelease short strings differ (OpenUsage's `0.7.10-beta.3`) never
    /// showed it at all.
    static func channel(ofInstalled app: InstalledApp, in items: [SparkleAppcastItem]) -> String? {
        if let b = app.buildVersion, !b.isEmpty,
           let match = item(matchingInstalledBuild: b, in: items) {
            return normalizeChannel(match.channel)
        }
        if let s = app.shortVersion, !s.isEmpty,
           let match = items.first(where: { $0.shortVersionString == s }) {
            return normalizeChannel(match.channel)
        }
        return nil
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
    ///
    /// Forwards to `HostOS.numericVersion()`: the install-time OS gate
    /// (`SignatureVerifier` gate 6) has to answer "what is this Mac running?"
    /// the same way this one does, and two independent readings of
    /// `operatingSystemVersion` is exactly the shape that drifts. Kept as a name
    /// here because callers already reach for it through this type.
    static func numericSystemVersion() -> String { HostOS.numericVersion() }

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
    var maximumSystemVersion: String?
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
    /// One language's worth: a feed repeating the element per `xml:lang` is
    /// narrowed to the reader's by `preferredVariant`.
    var descriptionHTML: String?
    /// Inline release notes shipped as Markdown via `<markdownDescription>` — some
    /// feeds (e.g. Surge) publish only this and no HTML `<description>`. Parsed
    /// into a structured changelog so the notes render natively instead of falling
    /// back to a web view. Localized the same way `descriptionHTML` is.
    var markdownDescription: String?
    /// `<pubDate>` — the item's publish date, verbatim. RSS spells this many ways
    /// (RFC822, ISO8601, or a bare Unix epoch as Surge does); kept raw and
    /// normalized only when we build a changelog entry.
    var pubDate: String?
    /// `<sparkle:releaseNotesLink>` — an external notes page, when the feed links
    /// out instead of (or in addition to) inlining them. Localized the same way
    /// `descriptionHTML` is, and this is the field where it bites hardest: the
    /// link is one page per language, so picking the wrong variant means fetching
    /// and rendering a whole page of notes nobody asked for.
    var releaseNotesLink: URL?

    /// Prefer the build version (Sparkle's canonical key); fall back to short.
    var comparisonKey: String { version ?? shortVersionString ?? "0" }
}

/// Minimal XMLParser-backed appcast reader. Version metadata in Sparkle feeds
/// may live either on the `<enclosure>` attributes or as child elements of
/// `<item>`; we collect both.
final class SparkleAppcastParser: NSObject, XMLParserDelegate {

    /// `relativeTo` is the URL the appcast itself was fetched from, and every URL
    /// in the document is resolved against it — which is what Sparkle does:
    /// `SUAppcastItem` builds each one as
    /// `[NSURL URLWithString:string relativeToURL:appcastURL]` (enclosure, delta
    /// enclosure, release-notes link, full-release-notes link alike) whenever it
    /// knows the appcast URL, which in the real update flow it always does.
    ///
    /// So a RELATIVE enclosure is a supported Sparkle appcast, not a malformed
    /// one — even though RSS 2.0 says of `<enclosure>` that "the url must be an
    /// http url". Helium's feed is the one that made this matter: its enclosures
    /// read `assets/helium_0.16.2.1_arm64-macos.dmg`, and every one of them came
    /// out of here as a schemeless URL nothing could fetch. Passing nil keeps the
    /// old behaviour and is only for callers with no URL to give (tests, and a
    /// body already in hand).
    ///
    /// One difference from Sparkle left deliberately: it also rewrites a literal
    /// space to `%20` in the enclosure string before parsing. Nothing we read
    /// needs that yet, and doing it here would quietly start accepting items this
    /// has always dropped.
    static func parse(
        _ data: Data,
        relativeTo base: URL? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [SparkleAppcastItem] {
        let parser = XMLParser(data: data)
        // Sparkle's vocabulary is a NAMESPACE, not the literal string "sparkle:".
        // Both flags are load-bearing and neither defaults on:
        // `shouldProcessNamespaces` is what splits an element into (URI, local
        // name); `shouldReportNamespacePrefixes` is the only way to learn the
        // prefix→URI bindings, because turning the first one on REMOVES the
        // `xmlns:*` declarations from the attribute dictionary while leaving
        // attribute keys qualified. See `sparkleLocalName` / `sparkleAttribute`
        // and docs/engine-notes/sparkle-appcast-source.md §1.
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        let delegate = SparkleAppcastParser(base: base, preferredLanguages: preferredLanguages)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    /// The namespace every Sparkle element and attribute actually lives in. The
    /// `sparkle:` prefix conventionally bound to it is the vendor's choice, not
    /// part of the format.
    static let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    /// The appcast's own URL, for resolving the relative URLs inside it.
    private let base: URL?

    /// The reader's language preferences, most-preferred first. Injected rather
    /// than read from the process inside `preferredVariant` so a test can state
    /// which reader it is describing instead of inheriting whatever language the
    /// host Mac — or a CI runner — happens to be set to.
    private let preferredLanguages: [String]

    init(base: URL? = nil, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.base = base
        self.preferredLanguages = preferredLanguages
        super.init()
    }

    /// Resolve one URL string out of the document the way Sparkle would.
    /// `.absoluteURL` so what comes out carries no lingering base — every
    /// consumer downstream reads `absoluteString` or hands it to `URLSession`,
    /// and a relative `URL` would print as `assets/…` in a log or a report.
    private func resolve(_ string: String) -> URL? {
        URL(string: string, relativeTo: base)?.absoluteURL
    }

    // MARK: - Localized children

    /// One `<item>` child element repeated per language, in document order.
    ///
    /// Sparkle lets a vendor ship the SAME child of `<item>` several times, each
    /// tagged with `xml:lang`, and picks the one matching the reader
    /// (https://sparkle-project.org/documentation/publishing/). Two feeds we track
    /// do exactly that, in the two different shapes the format allows, and until
    /// this existed we read BOTH of them by position — which is to say, at random
    /// from the user's point of view (issue #399):
    ///
    ///  * Mac Mouse Fix links out: 12 `<sparkle:releaseNotesLink xml:lang>` per
    ///    item (de, es, fr, pt-BR, vi, tr, cs, ru, zh-Hans, zh-Hant, zh-HK, ko) and
    ///    no untagged one at all. `releaseNotesLink` was first-wins, so every
    ///    reader on earth got `…/3.0.8/de.html`.
    ///  * Mole inlines: 10 CDATA `<description xml:lang>` per item. `descriptionHTML`
    ///    was last-wins, so every reader got the language the vendor happened to
    ///    list last.
    ///
    /// Collected per item and resolved at `</item>` rather than assigned as each
    /// element closes, because the choice cannot be made until every variant has
    /// been seen.
    private var localizedChildren: [String: [(language: String?, text: String)]] = [:]

    /// The `xml:lang` of the element currently being read, or nil when it carries
    /// none. Set on every `didStartElement` exactly like `textBuffer` is cleared
    /// there, which is sound for the three elements below because all of them are
    /// leaves — their content arrives as characters or CDATA, never as child
    /// elements that would overwrite this mid-read.
    private var currentLanguage: String?

    /// Record one language variant of a localizable `<item>` child.
    ///
    /// Guarded on `current` for the same reason `<description>` always was: a feed
    /// may carry a channel-level copy of these elements outside any `<item>`, and
    /// attaching those to the first item that comes along would be worse than
    /// dropping them.
    private func recordLocalized(_ name: String, _ text: String) {
        guard current != nil, !text.isEmpty else { return }
        localizedChildren[name, default: []].append((currentLanguage, text))
    }

    /// Pick the variant to use, following Sparkle's `-[SUAppcast bestNodeInNodes:]`
    /// exactly (Sparkle 2.x, `Sparkle/SUAppcast.m`):
    ///
    ///  1. A lone variant wins outright — its `xml:lang` is never even read. This
    ///     is what keeps every single-variant feed we already parse byte-for-byte
    ///     unchanged, including one whose only `<description>` is tagged `de`.
    ///  2. Otherwise an untagged variant counts as `"en"` (Sparkle logs an error
    ///     and assumes the same), and `preferredLocalizations` picks the winner.
    ///  3. A reader matching nothing gets the FIRST variant.
    ///
    /// ⚠️ Step 3 is not a corner case, and it is not the `else` below doing it:
    /// `Bundle.preferredLocalizations(from:forPreferences:)` itself answers with
    /// the array's first element when nothing matches (measured 2026-09-12 on
    /// macOS 27 — `["de","es",…,"ko"]` against `["en-US"]` and against `["ja-JP"]`
    /// both come back `["de"]`). So an English reader still sees German for Mac
    /// Mouse Fix, whose feed lists no `en` variant even though `…/3.0.8/en.html`
    /// is published and reachable. That is the vendor's omission — Sparkle's own
    /// updater shows German there too — and deviating would mean guessing at URLs
    /// the feed does not offer.
    ///
    /// The `else` is therefore belt-and-braces rather than the mechanism, and it
    /// is stated that way because it cannot be tested: no input reaches it. The
    /// API returned a non-empty array present in the input for every adversarial
    /// list tried (`""`, `"EN"`, `"en_US"`, `"Deutsch"`, `"🙂"`), and a lone
    /// variant has already returned above. Sparkle carries the same unreachable
    /// fallback (it logs an error beside it), and a future OS could make it live.
    static func preferredVariant(
        _ variants: [(language: String?, text: String)],
        preferredLanguages: [String]
    ) -> String? {
        guard variants.count > 1 else { return variants.first?.text }
        let languages = variants.map { $0.language.flatMap { $0.isEmpty ? nil : $0 } ?? "en" }
        guard
            let choice = Bundle.preferredLocalizations(
                from: languages, forPreferences: preferredLanguages).first,
            let index = languages.firstIndex(of: choice)
        else { return variants.first?.text }
        return variants[index].text
    }

    /// Resolve every collected variant onto the item that is closing.
    ///
    /// The table is emptied when an item OPENS rather than here, so "these
    /// variants belong to the item currently being read" holds because of where
    /// the reset lives and not because the feed closed its tags. `</item>` is the
    /// vendor's to get wrong; `<item>` is what actually creates `current`.
    ///
    /// ⚠️ A chosen `<sparkle:releaseNotesLink>` that does not resolve leaves the
    /// field nil, where the old first-wins guard (`releaseNotesLink == nil`) would
    /// have gone on to try the next element in the item. That fall-through was an
    /// accident of the guard, not a design: the next element is a different
    /// LANGUAGE, so what it rescued was a reader silently getting notes they
    /// cannot read. `resolve` only fails on a string `URL(string:)` refuses — a
    /// literal space is the realistic one, since this parser deliberately skips
    /// Sparkle's space→%20 rewrite (see `parse`) — and no notes URL is better than
    /// the wrong language's.
    private func applyLocalizedChildren() {
        func best(_ name: String) -> String? {
            localizedChildren[name].flatMap {
                Self.preferredVariant($0, preferredLanguages: preferredLanguages)
            }
        }
        if let text = best("description") { current?.descriptionHTML = text }
        if let text = best("markdownDescription") { current?.markdownDescription = text }
        if let text = best("sparkle:releaseNotesLink") {
            current?.releaseNotesLink = resolve(text)
        }
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

    // MARK: - Namespace resolution

    /// prefix → the stack of URIs it is currently bound to, innermost last.
    ///
    /// A stack rather than one URI because a feed may rebind a prefix on an inner
    /// element; `didStartMappingPrefix` fires just before that element's start tag
    /// and `didEndMappingPrefix` just after its end tag, so push/pop is exact.
    /// Only needed for ATTRIBUTES: elements arrive with their URI already
    /// resolved, attributes do not (their keys stay qualified).
    private var prefixBindings: [String: [String]] = [:]

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        prefixBindings[prefix, default: []].append(namespaceURI)
    }

    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        if prefixBindings[prefix]?.popLast() != nil, prefixBindings[prefix]?.isEmpty == true {
            prefixBindings[prefix] = nil
        }
    }

    /// The URI `prefix` is bound to here, or nil if it is bound to nothing.
    private func uri(forPrefix prefix: String) -> String? { prefixBindings[prefix]?.last }

    /// The Sparkle local name this element carries, or nil if it is not Sparkle's.
    ///
    /// Two ways in, in this order:
    ///
    ///  1. The element resolved into Sparkle's namespace — whatever prefix the
    ///     vendor bound it to, or no prefix at all under `xmlns="…sparkle"`.
    ///  2. Its qualified name reads `sparkle:…` — whatever that prefix is or
    ///     isn't bound to. This is the whole of the pre-namespace parser's rule,
    ///     kept so the change is a strict SUPERSET of what already worked: a feed
    ///     that declares nothing (libxml2 recovers rather than failing, handing
    ///     back the local name with an empty URI) and, just as important, a feed
    ///     that declares the URI with a typo in it. Both parse today; narrowing
    ///     (2) to "bound to nothing" would turn either into a silent total loss
    ///     of the vocabulary, which is the failure this change exists to prevent.
    ///     The price is the pre-existing one: a non-Sparkle vocabulary that
    ///     picked the same short prefix is misread, exactly as it is today.
    private func sparkleLocalName(
        _ elementName: String, _ namespaceURI: String?, _ qName: String?
    ) -> String? {
        if namespaceURI == SparkleAppcastParser.sparkleNamespace { return elementName }
        let qualified = qName ?? elementName
        guard qualified.hasPrefix("sparkle:") else { return nil }
        return String(qualified.dropFirst("sparkle:".count))
    }

    /// The RSS local name of this element, or nil if the element belongs to
    /// somebody else's vocabulary.
    ///
    /// ⚠️ The rule is "its qualified name carries NO PREFIX", which is exactly
    /// what matching `elementName` meant before namespaces were processed —
    /// deliberately, because that switch reads `item`, `enclosure`,
    /// `description`, `markdownDescription` and `pubDate`, all names a foreign
    /// vocabulary may also use. Once `elementName` became the bare local name,
    /// matching it alone started accepting every namespace: measured on this
    /// checkout, a `<dc:description>` ahead of the real one silently became the
    /// release notes, and an `<x:item>` nested inside `<item>` reset `current`
    /// and made the entire genuine release disappear.
    ///
    /// Gating on `namespaceURI` instead would be wrong in the other direction —
    /// also measured: a feed with a foreign DEFAULT namespace (`xmlns=`
    /// RSS 1.0's URI) parses today, and every one of its elements would stop
    /// matching. A feed that makes SPARKLE the default namespace still works
    /// here because it spells those elements unprefixed too.
    private func rssLocalName(_ elementName: String, _ qName: String?) -> String? {
        (qName ?? elementName).contains(":") ? nil : elementName
    }

    /// The value of the Sparkle attribute named `local`, by the same two ways in.
    ///
    /// ⚠️ An UNPREFIXED attribute is in no namespace even under a default
    /// `xmlns` — that is the XML namespaces spec, not a shortcut — so there is no
    /// third case here matching a bare `version="…"` on `<enclosure>`. Sorted so
    /// a feed binding the URI to two prefixes at once resolves the same way twice
    /// instead of by dictionary order.
    ///
    /// ⚠️ Resolved binding first, literal `sparkle:` second. Within ONE element's
    /// attributes this is a real precedence rule: both spellings are visible in
    /// the same dictionary at the same moment, so one of them has to win, and the
    /// properly bound one should. The literal fallback still fires for the cases
    /// it exists for — when no prefix resolves to Sparkle's URI, the scan simply
    /// finds nothing.
    ///
    /// ⚠️ This does NOT generalise to elements, and it would be wrong to say the
    /// parser "resolves both the same way round". `sparkleLocalName` checks the
    /// namespace first only to decide whether THIS element is Sparkle's; separate
    /// elements arrive in separate `didEndElement` calls with no memory of each
    /// other, so when a feed carries both `<s:maximumSystemVersion>` (real URI)
    /// and `<sparkle:maximumSystemVersion>` (foreign vocabulary, reaching the
    /// switch via the literal fallback), the winner is decided by DOCUMENT ORDER
    /// and by each field's own guard — not by which prefix is properly bound.
    /// The direction is not even uniform: `version` / `shortVersionString` /
    /// `channel` keep the FIRST value (`== nil` guard) while
    /// `maximumSystemVersion` / `minimumSystemVersion` assign unconditionally and
    /// so keep the LAST. `aFeedCarryingBothSpellingsOfAnElementIsOrderDecided`
    /// pins this rather than pretending it does not exist; it is pre-existing
    /// behaviour that namespace support merely makes reachable, and no observed
    /// feed carries two vocabularies claiming the same element name.
    private func sparkleAttribute(
        _ local: String, _ attributes: [String: String], _ sortedKeys: [String]
    ) -> String? {
        for key in sortedKeys {
            guard let colon = key.firstIndex(of: ":") else { continue }
            guard String(key[key.index(after: colon)...]) == local,
                  uri(forPrefix: String(key[key.startIndex..<colon]))
                    == SparkleAppcastParser.sparkleNamespace
            else { continue }
            return attributes[key]
        }
        return attributes["sparkle:\(local)"]
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        textBuffer = ""
        // `xml` is bound implicitly by the XML spec, never declared, and Foundation
        // leaves the key qualified whether namespaces are processed or not.
        currentLanguage = attributeDict["xml:lang"]

        // Sparkle's own vocabulary first; anything Sparkle does not define falls
        // through to the RSS switch below, which only accepts UNPREFIXED names
        // (see `rssLocalName`). That is what keeps a feed making Sparkle the
        // DEFAULT namespace working — it spells `<item>` and `<enclosure>`
        // unprefixed — without accepting a foreign vocabulary's `<x:item>`.
        if sparkleLocalName(elementName, namespaceURI, qName) == "deltas" {
            deltasDepth += 1
            return
        }

        // Sorted once per element rather than once per attribute read: `<enclosure>`
        // alone asks five times, and the sort exists so a feed binding Sparkle's URI
        // to two prefixes at once resolves the same way twice instead of by
        // dictionary order.
        let sortedAttributeKeys = attributeDict.keys.sorted()

        switch rssLocalName(elementName, qName) {
        case "item":
            current = SparkleAppcastItem()
            // Whatever is still in the table belongs to an item that is over. See
            // `applyLocalizedChildren` for why the reset lives here.
            localizedChildren.removeAll(keepingCapacity: true)
        case "enclosure":
            // Inside <sparkle:deltas> this is a patch, not the release download.
            // Collected rather than merely skipped: it is the same release, reachable
            // for a fraction of the bytes when its `deltaFrom` is the build on disk.
            // Everything below still runs only for the real enclosure — letting a
            // patch through would restore the hijack this depth counter exists to
            // prevent (`deltaEnclosuresDontHijackTheItemsDownload`).
            guard deltasDepth == 0 else {
                if let urlString = attributeDict["url"],
                   let url = resolve(urlString),
                   let from = sparkleAttribute("deltaFrom", attributeDict, sortedAttributeKeys) {
                    current?.deltas.append(DeltaPatch(
                        fromBuild: from,
                        url: url,
                        size: attributeDict["length"].flatMap { Int64($0) },
                        edSignature: sparkleAttribute("edSignature", attributeDict, sortedAttributeKeys)))
                }
                break
            }
            current?.enclosureURL = attributeDict["url"].flatMap { resolve($0) }
            if let length = attributeDict["length"], let n = Int64(length) {
                current?.enclosureLength = n
            }
            if let v = sparkleAttribute("version", attributeDict, sortedAttributeKeys) { current?.version = v }
            if let s = sparkleAttribute("shortVersionString", attributeDict, sortedAttributeKeys) {
                current?.shortVersionString = s
            }
            if let sig = sparkleAttribute("edSignature", attributeDict, sortedAttributeKeys) {
                current?.edSignature = sig
            }
            if let delta = sparkleAttribute("deltaFrom", attributeDict, sortedAttributeKeys) {
                current?.deltaFrom = delta
            }
            // Usually an item-level child element, but tolerate it on enclosure.
            if let m = sparkleAttribute("minimumAutoupdateVersion", attributeDict, sortedAttributeKeys) {
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

        // Sparkle's vocabulary first; anything it does not define falls through
        // to the RSS switch, which is how a feed that makes Sparkle the DEFAULT
        // namespace still gets its `<item>` / `<description>` / `<pubDate>` read.
        //
        // `handled` stops an element whose local name is in BOTH switches
        // (`markdownDescription`) from being recorded twice when it arrives
        // Sparkle-namespaced.
        var handled = true
        switch sparkleLocalName(elementName, namespaceURI, qName) {
        case "deltas":
            deltasDepth = max(0, deltasDepth - 1)
        case "version":
            if current?.version == nil, !text.isEmpty { current?.version = text }
        case "shortVersionString":
            if current?.shortVersionString == nil, !text.isEmpty {
                current?.shortVersionString = text
            }
        case "maximumSystemVersion":
            current?.maximumSystemVersion = text
        case "minimumSystemVersion":
            current?.minimumSystemVersion = text
        case "channel":
            // In a feed that makes Sparkle the DEFAULT namespace, RSS's own
            // `</channel>` also lands here. It closes after `</item>`, so
            // `current` is nil and the assignment is a no-op on nil — the same
            // guard that has always kept a channel-level `<description>` off the
            // first item (see `recordLocalized`).
            if current?.channel == nil, !text.isEmpty { current?.channel = text }
        case "hardwareRequirements":
            if !text.isEmpty {
                current?.hardwareRequirements = Set(
                    text.lowercased().split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) })
            }
        case "minimumAutoupdateVersion":
            if current?.minimumAutoupdateVersion == nil, !text.isEmpty {
                current?.minimumAutoupdateVersion = text
            }
        case "markdownDescription":
            // Sparkle defines this one and so does the bare RSS spelling some
            // feeds use. Both land on the one shared key, so a feed mixing them
            // compares its variants against each other rather than letting
            // whichever spelling came first win outright. This case is what
            // makes `handled` load-bearing: it is the only local name in both
            // switches, and without the guard a Sparkle-namespaced copy would be
            // recorded twice.
            recordLocalized("markdownDescription", text)
        case "releaseNotesLink":
            recordLocalized("sparkle:releaseNotesLink", text)
        default:
            handled = false
        }
        guard !handled else { textBuffer = ""; return }

        switch rssLocalName(elementName, qName) {
        case "description":
            // Only inside an <item>; the channel-level <description> has no
            // `current` to attach to, so it's harmlessly dropped (see
            // `recordLocalized`).
            //
            // ⚠️ This was last-non-empty-wins, and for a localized feed that was
            // the bug. For an item repeating <description> with NO xml:lang on any
            // of them — vendor duplication rather than translation — every copy now
            // reads as "en" and the FIRST one wins instead of the last. That is
            // Sparkle's behaviour, and the two feeds known to repeat a localizable
            // child at all — Mac Mouse Fix's and Mole's, both fetchable by anyone —
            // tag every duplicate with xml:lang, so neither takes this branch.
            recordLocalized("description", text)
        case "markdownDescription":
            // The bare spelling; Sparkle's own is handled above and shares this
            // same key.
            recordLocalized("markdownDescription", text)
        case "pubDate":
            if current?.pubDate == nil, !text.isEmpty { current?.pubDate = text }
        case "item":
            // Before appending: the localized children can only be resolved once
            // every variant in this item has been seen.
            applyLocalizedChildren()
            if let item = current { items.append(item) }
            current = nil
        default:
            break
        }
        textBuffer = ""
    }
}
