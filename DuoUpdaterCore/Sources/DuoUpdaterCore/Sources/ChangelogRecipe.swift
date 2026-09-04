import Foundation

/// A per-app recipe for turning a vendor's changelog *page* into a structured
/// `Changelog`. This is the changelog analogue of `VendorProbeRecipe`: a
/// hand/AI-authored, declarative extraction config that a deterministic offline
/// parser (`ChangelogExtractor`) runs — no model in the runtime loop. The intent
/// is "AI writes the regex once; the device parses forever".
///
/// Design notes that differ deliberately from `VendorProbeRecipe`:
///   - **Low stakes.** A bad version probe can invent a false "update available";
///     a bad changelog parse can only show ugly/empty notes, and we always fall
///     back to the embedded web page. So this is `Codable` and forgiving by
///     design, and the registry can carry loose, redundant patterns.
///   - **Redundant by design.** `itemPatterns` is an *ordered* list: the first
///     pattern that yields ≥1 item for an entry wins. Add several to survive a
///     page's variants (old vs new markup) without branching code.
///   - **Serializable.** Every field is plain data, so a recipe can later live in
///     a remote catalog and be fixed without shipping a new app build.
///
/// A field here is not just config — it's an input to `ChangelogExtractor` /
/// `StructuredChangelogDecoder` exactly like their own source code is, and an edit
/// that changes what an EXISTING cached version's notes parse to (`entryPattern`,
/// `itemPatterns`, `skipSections`, `stripTags`, `escapedMarkup`, `markdownSource`,
/// `minItemLength`, `newestLast`, `maxEntries`, `source`, …) needs the same
/// `Changelog.parserGeneration` bump a parser-code change does — see its doc
/// comment. Two already-merged recipe-only edits prove this isn't hypothetical:
/// `0d9d424` (Figma's `entryPattern`/`source` moved to a different feed) and
/// `a6ac16b` (`skipSections` added, below).
public struct ChangelogRecipe: Codable, Sendable {
    /// `CFBundleIdentifier` (lowercased by convention) of the app this targets.
    public let bundleID: String

    /// The changelog page to fetch and parse. When `sourceTemplate` is set and a
    /// version is supplied at load time, the resolved per-version URL is used
    /// instead and `source` is only a fallback (see `resolvedSource(forVersion:)`).
    public let source: URL

    /// A per-version source URL template containing the literal `{version}`, for
    /// vendors who publish **one page per release** with no inline multi-version
    /// page or "latest" alias (Thunderbird). At load time the app's target
    /// version is substituted so the rendered notes always match the exact
    /// installed/offered build — no version-pin to bump, no index-ordering guess.
    /// nil for the common case (a single fixed `source`). See
    /// `resolvedSource(forVersion:)` for the substitution + channel normalization.
    ///
    /// `{major}` is also substituted, with the version's first component, for
    /// vendors who publish one page per MAJOR release listing every build in it
    /// (Opera's `changelog-for-134`). Same reason as `{version}`: a fixed URL
    /// there would silently stop covering the installed build at the next major,
    /// and majors ship every few weeks.
    ///
    /// `{appleDocVersion}` is the third, for `developer.apple.com` release notes,
    /// whose path spells the version its own way (`26.6` → `26_6`, `27.0` → `27`).
    /// See `appleDocVersionToken(for:)` for why neither of the other two can stand
    /// in for it.
    public let sourceTemplate: String?


    /// Response shape. `.html` runs the regexes against the raw markup; `.json`
    /// is identical mechanically (regex over the body) but named separately so a
    /// future structured-JSON path can branch on it. Defaults to `.html`.
    public var mode: Mode

    /// Regex iterated over the whole document; **each match is one version block**.
    /// Consumed named capture groups:
    ///   - `version` (required) — the version string;
    ///   - `date` (optional) — the release date, verbatim;
    ///   - `body`  (optional) — the chunk the `itemPatterns` then run against;
    ///     when absent, the patterns run against the entire entry match.
    /// Matched with dot-matches-newline + case-insensitive, so a single `.*?`
    /// spans the multi-line block.
    public let entryPattern: String

    /// Regexes tried **in order** against each entry's `body`; the first that
    /// produces ≥1 match wins, and each match contributes one change line (its
    /// `item` named group, else capture group 1, else the whole match). Multiple
    /// entries here = redundancy across page layouts.
    public let itemPatterns: [String]

    /// Strip inner HTML tags (`<b>`, `<a …>`, …) from captured text. Default true.
    public var stripTags: Bool

    /// Decode HTML entities (`&quot;` `&amp;` `&#39;` …) in captured text.
    /// Default true.
    public var decodeEntities: Bool

    /// The captured text is HTML that was itself entity-escaped — an RSS
    /// `<description>` carrying `&lt;a href=…&gt;…&lt;/a&gt;` (1Password's feed).
    /// Cleaning strips tags BEFORE decoding entities, so on such a body the first
    /// strip sees no tags and the decode then turns the escapes back into visible
    /// `<a href="…">` markup in the rendered note. This runs one more strip after
    /// decoding.
    ///
    /// Opt-in rather than always-on: a normal HTML changelog may deliberately
    /// SHOW markup as text (`use &lt;div&gt; instead`), and a second unconditional
    /// strip would eat exactly that.
    public var escapedMarkup: Bool

    /// The captured text is Markdown source, not HTML — so the inline syntax that
    /// `stripTags` would have removed from an HTML equivalent survives into the
    /// rendered note as literal punctuation. HBuilderX's official release notes
    /// spell inline code as `` `CLI pack cancel` ``; the HTML page they replaced
    /// spelled it `<code>CLI pack cancel</code>`, which `stripTags` removed, so
    /// without this the migration puts visible backticks in front of the user.
    ///
    /// Deliberately narrow: it unwraps inline code spans and flattens
    /// `[text](url)` to `text`, and nothing else. Bold, emphasis and headings would
    /// need real Markdown rendering (`Changelog` already has `.markdown` item
    /// syntax for producers that keep their source intact); this flag exists for
    /// recipes whose *output contract is plain text*, so that the syntax a plain
    /// renderer would print literally is removed rather than shown.
    ///
    /// Link flattening was added for Docker, whose notes carry links mid-sentence
    /// (`[Docker Compose v5.4.0](…)`) that no `itemPattern` can practically consume
    /// — HBuilderX's trailing links are eaten by its own pattern, and flattening
    /// was verified a no-op there before this widened: 0 of the 116 items in its
    /// live top-10 window change.
    public var markdownSource: Bool

    /// Keep at most this many entries (changelogs run for years; the detail view
    /// only needs the recent ones). Nil = keep all. Default 40.
    public var maxEntries: Int?

    /// Drop change lines shorter than this after cleaning — kills stray markup
    /// fragments that survive tag-stripping. Default 1 (keep anything non-empty).
    public var minItemLength: Int

    /// When the source page lists releases **oldest-first** (ascending), set this
    /// so the parser reverses the extracted entries to newest-first and applies
    /// `maxEntries` from the NEW (recent) end. Default false — nearly every vendor
    /// changelog is already newest-first, and for those the streaming early-stop at
    /// `maxEntries` is correct. WeType's official changelog is the exception: its
    /// inline release list runs oldest→newest, so without this the cap would keep
    /// the most ancient versions and drop the latest.
    public var newestLast: Bool

    /// When non-nil, `source` is treated as a **version index** page — a
    /// newest-first list of per-version changelog links — not the changelog
    /// itself. `ChangelogService` fetches `source`, takes the **first** match of
    /// this pattern (its `link` named group, else capture group 1), resolves it
    /// against `source`, and runs `entryPattern`/`itemPatterns` on *that* page.
    /// This pins the recipe to "latest" with zero maintenance and sidesteps
    /// version→URL naming quirks: VLC, for instance, merges 3.0.19/3.0.20 (and
    /// 3.0.22/3.0.23) onto a single page, so following the real href is correct
    /// where templating a version number into the URL would 404. Both VLC and
    /// Ghostty publish such a newest-first index; their per-version detail pages
    /// share one structure, so the entry/item patterns are written against that
    /// detail page exactly as for a direct-source recipe. Nil = `source` is the
    /// changelog page directly (the common case).
    public let indexLinkPattern: String?

    /// The release channel this recipe targets, or nil for a channel-agnostic
    /// recipe (the common case — most apps have one changelog regardless of
    /// channel). This matters only when **several channels share one bundle id**
    /// and want *different* changelog pages: Thunderbird's Stable and ESR are both
    /// `org.mozilla.thunderbird` but live on separate version trains, so each gets
    /// its own recipe distinguished by `channel`. `recipe(forBundleID:channel:)`
    /// prefers an exact channel match, then a channel-agnostic recipe, then a
    /// `.stable` one — so existing single-recipe apps (channel nil) keep matching
    /// every channel exactly as before.
    public let channel: ReleaseChannel?

    /// For a non-stable recipe over a feed that splits by GitHub's `prerelease`
    /// bit: also keep the releases that bit calls stable.
    ///
    /// Set only where the vendor's preview builds GRADUATE into the same
    /// numbering rather than running as a parallel train. UTM is the case: a copy
    /// on `v4.7.3 (Beta)` is offered `v4.7.5`, which is not a prerelease, so a
    /// prerelease-only history would render that update's notes as nothing at all.
    /// Keep it false for a true parallel channel (Zed Preview), where stable
    /// entries belong to the OTHER train and would be noise.
    public let includesPromotedStable: Bool

    /// Optional regex run over each entry's `body` to pull illustration image URLs
    /// (capture group 1, or the named `image` group). Every match becomes one image,
    /// rendered after the change lines. nil = no images (the common case). Only
    /// absolute `http(s)` URLs are kept; relative paths are skipped. Use for vendors
    /// who embed release screenshots in their notes (WeChat's updates page puts a
    /// feature illustration between the change lines).
    public let imagePattern: String?

    /// Lowest app version this recipe's page covers, inclusive. nil → no floor.
    ///
    /// This and `belowAppVersion` are the changelog analogue of a
    /// `VendorProbeRecipe`'s `hostRequirement`: "which installs is this recipe
    /// for", when `channel` cannot answer because the vendor forked its notes
    /// across two trains that are BOTH stable.
    ///
    /// Raycast is the case in hand. `www.raycast.com/changelog` became the v2 notes
    /// when v2 shipped and the v1 archive moved to `/changelog/macos` — same markup,
    /// different history — while both trains keep the one bundle id
    /// `com.raycast.macos` and the one `.stable` channel. Without a version window
    /// a 1.104.x install would be shown the 2.x notes.
    public let minimumAppVersion: String?

    /// Exclusive upper bound: this recipe's page covers app versions strictly BELOW
    /// this. nil → no ceiling. Exclusive so a pair of recipes tiles the range with
    /// no gap and no overlap — `belowAppVersion: "2"` and `minimumAppVersion: "2"`
    /// meet exactly at 2.0.
    public let belowAppVersion: String?

    /// The newest entry this vendor's page is KNOWN to stop at, when the page is
    /// genuinely behind the builds the vendor is shipping.
    ///
    /// `duo verify` flags a changelog whose newest entry trails the detected
    /// version by a whole release, on the theory that the entry pattern is reading
    /// a stale section. Usually right. Sometimes the pattern is perfect and the
    /// VENDOR is the stale one — WorkBuddy's international docs site carries two
    /// entries and stops at 5.2.7 (2026-07-17) while its own endpoint ships 5.4.2,
    /// and the identical pattern returns 58 entries from the Chinese site. There
    /// is nothing to fix, so the warning can never clear: it re-files an issue
    /// every sweep against a recipe that works (issue #88).
    ///
    /// **A version, not a boolean, and that is the whole design.** A `true` here
    /// would switch the check off for this recipe forever, silencing the one
    /// detector that would notice the day the pattern really does break. Naming
    /// the version means the acknowledgement is only good while the page still
    /// says exactly that: if the pattern slips to an older section the complaint
    /// comes back, if the vendor publishes anything newer the complaint comes back
    /// once so a human can re-read the situation, and if the vendor catches up
    /// entirely the check passes on its own and this field can go.
    ///
    /// Set it only after reading the live page and confirming the vendor is the
    /// one behind — record what you saw next to the recipe, as WorkBuddy's comment
    /// does. nil for every recipe whose notes track its releases (the common case).
    public var acknowledgedStaleEntry: String?

    /// Whether this recipe restricts itself to a version range at all. Used to keep
    /// the lookup's behaviour byte-identical for every recipe that doesn't: a group
    /// with no windows is never filtered, so a nil version can't start excluding
    /// recipes that were always eligible.
    public var declaresVersionWindow: Bool {
        minimumAppVersion != nil || belowAppVersion != nil
    }

    /// The stable identity this recipe is recorded under — by the health store and
    /// by `duo verify`'s baseline, which is why both read it from here rather than
    /// each spelling it out.
    ///
    /// A recipe with no version window keeps the id it has always had, so adding
    /// this field orphaned no history. A windowed one appends its window, because
    /// two recipes for one bundle id and channel would otherwise share a single
    /// verify identity and overwrite each other's `lastGoodVersion` every sweep —
    /// which reads as "version went BACKWARDS" on alternate runs.
    public var recipeID: String {
        let base = "changelog:\(bundleID):\(channel?.rawValue ?? "-")"
        switch (minimumAppVersion, belowAppVersion) {
        case (nil, nil):            return base
        case let (min?, nil):       return "\(base):\(min)+"
        case let (nil, below?):     return "\(base):<\(below)"
        case let (min?, below?):    return "\(base):\(min)-\(below)"
        }
    }

    /// Whether `appVersion` falls in this recipe's window. Always true for a recipe
    /// that declares none.
    public func covers(appVersion: String) -> Bool {
        if let minimumAppVersion,
           VersionComparator.compare(appVersion, minimumAppVersion) == .orderedAscending {
            return false
        }
        if let belowAppVersion,
           VersionComparator.compare(appVersion, belowAppVersion) != .orderedAscending {
            return false
        }
        return true
    }

    public enum Mode: String, Codable, Sendable { case html, json }

    /// A vendor JSON feed too irregular for the regex `ChangelogExtractor` — nested
    /// objects, or entries that aren't in newest-first document order — that instead
    /// gets a small bespoke decoder. When set, `ChangelogService` decodes the fetched
    /// body with this format's structured parser and `entryPattern`/`itemPatterns`
    /// are unused (and may be empty). nil = the common regex path. The `channel`
    /// selects which sub-feed to read for formats that pack every channel into one
    /// document (Warp's `channel_versions.json`).
    public enum StructuredFormat: String, Codable, Sendable {
        /// Warp's `releases.warp.dev/channel_versions.json` — a `changelogs.<channel>`
        /// map of `v0.YYYY.MM.DD.HH.MM.<channel>_NN` → `{date, markdown_sections}`.
        /// Read instead of the docs site, which now sits behind a Vercel bot wall.
        case warpChannelVersions
        /// Typeless's `help/release-notes/macos` page — the whole release-notes JSON
        /// is base64+gzip in the Next.js `__NEXT_DATA__.props.pageProps.compressedData`
        /// (a `<version> -> <locale> -> {date, features:[{title, content}]}` map, with
        /// markdown content carrying a leading illustration image). No regex can reach
        /// it; the decoder inflates and walks the JSON.
        case typelessReleaseNotes
        /// WeChat DevTools' per-version notes,
        /// `…/versions/logs/<channel>_v<version>.json` — `categories[]` of
        /// `{title, items[]}`, one document per release (the recipe templates
        /// `{version}` into the URL). Regex-extractable in principle, but the items
        /// need the vendor's ordinal/marker decoration stripped and the category
        /// headings folded in, which the extractor has no shape for.
        case weChatDevToolsLog
        /// ChatWise's `releases.chatwise.app/releases` — a newest-first ARRAY of
        /// `{version, changelog, assets, date}` where `changelog` is a markdown
        /// bullet list. Shallow enough for the regex path in principle, but the
        /// notes live inside a JSON *string*, so every newline in them is a
        /// two-character `\n` escape and an item pattern has to spell its
        /// separators as `\\n` — a trap the shipped pattern fell into (its tail
        /// alternative `\\n?$` read as "a backslash, optionally followed by an
        /// `n`", so any entry whose notes did NOT end in a trailing `\n` escape
        /// lost its last bullet). Decoding the JSON hands us real newlines and
        /// retires that whole class of bug.
        case chatwiseReleases
        /// SunLogin/AweSun's `client-webapi.oray.com/softwares/…` API — the same
        /// endpoint the `VendorProbeRecipe` reads for the version number. Its
        /// top-level `logs` array holds one object per release, already
        /// newest-first; each object's own `logs` field is a fixed
        /// `<ol><li>version</li><li>item</li>…</ol>` HTML fragment (the first
        /// `<li>` names the version, the rest are the change lines) alongside a
        /// plain `updatedate` timestamp. Regex-extractable in principle (and
        /// previously extracted that way), but JSONDecoder resolves the payload's
        /// `\uXXXX`/`\/` escapes for free, which the regex path had to redo by hand.
        case sunLoginSoftwareLogs
        /// GitHub Desktop's `central.github.com/deployments/desktop/desktop/
        /// changelog.json` (and its `?env=beta` twin, a separate URL/recipe) — a flat
        /// array of `{name, notes, pub_date, version}`, newest-first, where `notes` is
        /// already an array of one-line strings. No regex needed; the decoder just
        /// walks the array.
        case gitHubDesktopChangelog
        /// Postman's `mkt.cdn.postman.com/.../app-release-notes.json` — a `notes[]`
        /// array (newest-first) of `{version, content, createdAt}`, `content` being
        /// markdown whose line separator is `\r\n` in *recent* entries but a bare
        /// `\n` in older ones. The prior regex path only recognized the escaped
        /// `\r\n` (`\\r\\n`) form and, worse, its item capture (`[^\\]{10,}`) stops
        /// at the first backslash — so a line with an escaped quote (`\"8000\"`)
        /// got silently truncated mid-sentence. Decoding the JSON for real yields
        /// genuine newlines and un-escaped text, sidestepping both problems.
        case postmanReleaseNotes
        /// JetBrains' `data.services.jetbrains.com/products/releases?code=<CODE>`
        /// (shared by IntelliJ IDEA's `IIU` and Toolbox App's `TBA`) —
        /// `{"<CODE>": [{date, version, whatsnew, …}]}`. Regex-extractable in
        /// principle (and formerly regex-extracted), but `whatsnew` is JSON-escaped
        /// HTML whose embedded `\n` is exactly the two-char-escape trap that motivated
        /// this decoder family: an item pattern that gets that wrong silently drops
        /// entries. `Decodable` sidesteps it entirely — the JSON string is already
        /// unescaped by the time the decoder sees it.
        case jetBrainsProductReleases
        /// The GitHub Releases API list for `zed-industries/zed`
        /// (`api.github.com/repos/zed-industries/zed/releases?per_page=40`), read
        /// instead of scraping `zed.dev/releases/{stable,preview}` — those pages
        /// are 2+ MB of server-rendered HTML for content GitHub already serves as
        /// compact JSON, and we already fetch this same endpoint for version
        /// detection (`GitHubReleaseRule`, see `GitHubReleasesSource.swift`).
        /// Verified 2026-08-21 that a release's `body` is byte-identical in
        /// substance to the zed.dev page's rendered notes for that version (42/42
        /// and 65/65 bullets matched exactly on a real stable and a real preview
        /// release). One endpoint, both channels: `prerelease` (true ⟺ the tag
        /// ends `-pre`, no exceptions in 100 sampled releases) selects Preview vs
        /// Stable via the recipe's existing `channel` field, same as Warp's
        /// `warpChannelVersions`. `per_page=40` is sized off a real sample where
        /// stable/preview releases interleave roughly 1:1 with occasional bursts
        /// of 2 in a row: the first 40 releases held 22 preview / 18 stable, both
        /// comfortably over the `maxEntries: 15` this recipe (like the old one)
        /// asks for. A single page, never paginated — GitHub's rate limit is
        /// unauthenticated (60/hour/IP) and `ChangelogService` doesn't attach a
        /// token.
        case zedGitHubReleases
        /// A plain `api.github.com/repos/<owner>/<repo>/releases` array, decoded
        /// with the same `GitHubMarkdownParser` the GitHub *version* source uses.
        /// For an app whose real changelog is its GitHub releases but whose update
        /// source is something else (Waku ships a Sparkle appcast, and its
        /// `releaseNotesLink` points at a single per-version `.md` with no index —
        /// so the feed alone can only ever show one version).
        ///
        /// Stable releases only: a prerelease is a track the user did not opt into,
        /// and unlike `zedGitHubReleases` this format carries no channel split.
        case gitHubReleases
        /// Alcove's own changelog API, `api.tryalcove.com/changelog` — public and
        /// unauthenticated, unlike the license-gated update endpoint beside it.
        case alcoveChangelog
        /// Notion's own desktop "What's New" page,
        /// `notion.notion.site/What-s-New-Mac-Windows-…` — distinct from
        /// `www.notion.com/releases`, which is Notion's *product* announcement feed
        /// and carries no build numbers (see the `notion.id` recipe comment). The
        /// rendered HTML is an empty Next.js shell; the real content is fetched
        /// separately from Notion's internal, unauthenticated page API
        /// (`notion.notion.site/api/v3/loadPageChunk`), which requires a POST with a
        /// JSON body naming the page id — hence `ChangelogRecipe.httpMethod`/
        /// `requestBody`. See `StructuredChangelogDecoder.decodeNotionPageChunk` for
        /// the response shape and how release order is derived.
        case notionPageChunk
        /// Apple's own release notes for Xcode, as DocC serves them:
        /// `developer.apple.com/tutorials/data/documentation/xcode-release-notes/
        /// xcode-<version>-release-notes.json`. The page a user sees at the
        /// `/documentation/…` URL is a 17 KB SPA shell — fetched 2026-09-03, it
        /// contains no note text at all — so this JSON is the only readable form.
        ///
        /// Regex is not an option here, which is the whole reason this is a
        /// decoder: a note's text is an *array* of fragments (`text`, `codeVoice`,
        /// `strong`, `reference`), and on the live Xcode 27 page 83 of 335 notes
        /// have more than one. Any pattern that captures "the text" captures the
        /// first fragment, so a quarter of the notes would be silently truncated
        /// mid-sentence ("When streaming " — the rest lives past a `codeVoice`).
        case appleDeveloperReleaseNotes
    }

    /// Non-nil → this recipe is parsed by a structured decoder, not the regex
    /// extractor (see ``StructuredFormat``). nil for the common HTML/JSON-regex case.
    public let structuredFormat: StructuredFormat?

    /// The HTTP method to fetch `source`/`resolvedSource(forVersion:)` with.
    /// Default (and every recipe until Notion) is `.get`. `.post` exists solely
    /// for endpoints — like Notion's internal page API — that only answer a
    /// POST carrying a JSON body; there is no GET form of that endpoint at all.
    public enum HTTPMethod: String, Codable, Sendable { case get, post }

    /// The method to fetch this recipe's page with. Defaults to `.get` so every
    /// existing recipe (and any future one that doesn't set this) is completely
    /// unaffected.
    public var httpMethod: HTTPMethod

    /// The literal request body to send when `httpMethod == .post`, as raw bytes
    /// (already-encoded JSON, in practice). nil for every `.get` recipe.
    ///
    /// ⚠️ Cache-key caveat, stated precisely because the first version of this
    /// comment named the wrong mechanism for both caches: `ChangelogCache` keys on
    /// (resolved URL, channel) — no bundle id and no body — so two recipes POSTing
    /// different bodies to the same URL on the same channel would collide, and the
    /// second would read the first's response. `ChangelogDiskCache.Key` is
    /// (bundleID, channel, version), which cannot collide on URL at all and is
    /// therefore not part of this hazard.
    ///
    /// Safe today because exactly one recipe (Notion) uses POST and its body is a
    /// fixed, hardcoded literal. Fixing it properly means folding a body hash into
    /// `ChangelogCache`'s key — not done here because it is unneeded until a
    /// second POST recipe exists (paginating with a different cursor, or another
    /// page id on the same host).
    public let requestBody: Data?

    /// Headings whose whole section this app's notes should drop, matched WHOLE and
    /// case-insensitively (see `GitHubMarkdownParser.parse`). Only consulted by the
    /// formats that go through `GitHubMarkdownParser` — `.gitHubReleases` and
    /// `.zedGitHubReleases`; a recipe on any other format that sets this is a silent
    /// no-op, which `ChangelogReviewRegressionTests` refuses.
    ///
    /// Per-recipe on purpose. `GitHubMarkdownParser.skippedSectionKeywords` is the
    /// other way to do this and it is a substring rule applied to every app, which
    /// is measurably the wrong tool here: a keyword wide enough to catch
    /// BetterDisplay's contributor roster ("Included Localizations") also catches
    /// `## Localization` in exelban/stats and `## 🌐 Localization` in block/goose,
    /// both of which are real change bullets — as is BetterDisplay's own
    /// "Localization Improvements", one release away from the roster. Measured
    /// 2026-08-27 across the 67 GitHub-sourced repos in this codebase, 15 releases
    /// each. So: name the exact headings, for the one app that has them.
    public let skipSections: [String]

    public init(
        bundleID: String,
        source: URL,
        entryPattern: String = "",
        itemPatterns: [String] = [],
        mode: Mode = .html,
        stripTags: Bool = true,
        decodeEntities: Bool = true,
        escapedMarkup: Bool = false,
        markdownSource: Bool = false,
        maxEntries: Int? = 40,
        minItemLength: Int = 1,
        indexLinkPattern: String? = nil,
        channel: ReleaseChannel? = nil,
        includesPromotedStable: Bool = false,
        sourceTemplate: String? = nil,
        newestLast: Bool = false,
        imagePattern: String? = nil,
        minimumAppVersion: String? = nil,
        belowAppVersion: String? = nil,
        structuredFormat: StructuredFormat? = nil,
        httpMethod: HTTPMethod = .get,
        requestBody: Data? = nil,
        skipSections: [String] = [],
        acknowledgedStaleEntry: String? = nil
    ) {
        self.bundleID = bundleID
        self.source = source
        self.entryPattern = entryPattern
        self.itemPatterns = itemPatterns
        self.mode = mode
        self.structuredFormat = structuredFormat
        self.stripTags = stripTags
        self.decodeEntities = decodeEntities
        self.escapedMarkup = escapedMarkup
        self.markdownSource = markdownSource
        self.maxEntries = maxEntries
        self.minItemLength = minItemLength
        self.indexLinkPattern = indexLinkPattern
        self.channel = channel
        self.includesPromotedStable = includesPromotedStable
        self.sourceTemplate = sourceTemplate
        self.newestLast = newestLast
        self.imagePattern = imagePattern
        self.minimumAppVersion = minimumAppVersion
        self.belowAppVersion = belowAppVersion
        self.httpMethod = httpMethod
        self.requestBody = requestBody
        self.skipSections = skipSections
        self.acknowledgedStaleEntry = acknowledgedStaleEntry
    }

    /// The actual page URL to fetch for a given target version. When
    /// `sourceTemplate` is set and `version` is non-empty, `{version}` is replaced
    /// by the URL token for that version and channel; otherwise `source` is
    /// returned unchanged.
    ///
    /// Channel normalization handles Mozilla's URL version forms, since the
    /// installed `CFBundleShortVersionString` is stripped of channel suffixes (see
    /// ReleaseChannel): an ESR install reads "140.11.1" but its notes page is
    /// `/140.11.1esr/…`, so the `esr` suffix is re-appended when missing. A bare
    /// version (`.stable` and the nil default) is used verbatim.
    public func resolvedSource(forVersion version: String?) -> URL {
        guard let sourceTemplate, let version, !version.isEmpty else { return source }
        let token = Self.urlVersionToken(for: version, channel: channel)
        var urlString = sourceTemplate.replacingOccurrences(of: "{version}", with: token)
        if urlString.contains("{major}") {
            // First component only — the version is already channel-normalized, so
            // an ESR/beta suffix can't leak in here.
            let major = token.split(separator: ".").first.map(String.init) ?? token
            urlString = urlString.replacingOccurrences(of: "{major}", with: major)
        }
        if urlString.contains("{appleDocVersion}") {
            urlString = urlString.replacingOccurrences(
                of: "{appleDocVersion}", with: Self.appleDocVersionToken(for: token))
        }
        return URL(string: urlString) ?? source
    }

    /// The version as Apple spells it in a `developer.apple.com` release-notes
    /// path: dots become underscores, and a `.0` release is named by its major
    /// alone. `26.6` → `26_6`, `26.0.1` → `26_0_1`, `27.0` → `27`.
    ///
    /// Checked against every `links.notes.url` in `xcodereleases.com/data.json`,
    /// which carries the real page for each release: **103 rows at 16.x or newer,
    /// one mismatch.** That one is 26.1.1, which Apple filed under `xcode-26_1`
    /// (a page whose own title reads "Xcode 26.1.1 Release Notes") while filing
    /// 26.0.1 and 26.4.1 under their own `_1` pages. It is a vendor inconsistency,
    /// not a rule this function is failing to express — no mapping satisfies both
    /// 26.1.1 → `26_1` and 26.4.1 → `26_4_1`.
    ///
    /// So a 26.1.1 install fetches a 404 and the pane falls back to embedding
    /// Apple's page, which is what every Xcode row did before this recipe existed.
    /// Pinned in `XcodeReleaseNotesChangelogTests` so the gap is a recorded
    /// measurement rather than something the next reader has to rediscover.
    ///
    /// Neither `{version}` nor `{major}` can express this, and both get it wrong
    /// in a way that shows the user another release's notes rather than failing:
    /// `{major}` maps every 26.x to the Xcode 26.0 page, and Apple ships betas for
    /// nearly every minor (16.1 … 16.4, 26.1 … 26.5 all had them), so that is the
    /// common case, not the corner.
    ///
    /// Only the leading numeric run is read, because the version handed in is the
    /// row's *display* version and a prerelease carries its track in that string
    /// ("27.0 beta 6"). Every beta of a release shares that release's page.
    static func appleDocVersionToken(for version: String) -> String {
        var parts = version.prefix { $0.isNumber || $0 == "." }
            .split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return version }
        // Trailing `.0` only, and only on a two-part version: `26.0.1` keeps its
        // zero (`xcode-26_0_1-release-notes` is a real page).
        if parts.count == 2, parts[1] == "0" { parts.removeLast() }
        return parts.joined(separator: "_")
    }

    /// Map a (possibly suffix-stripped) version string to the token a vendor uses
    /// in its per-version URL path, given the channel. Only ESR needs fixing up
    /// today; every other channel uses the version as-is.
    static func urlVersionToken(for version: String, channel: ReleaseChannel?) -> String {
        switch channel {
        case .esr:
            return version.hasSuffix("esr") ? version : version + "esr"
        case .beta:
            // Thunderbird beta notes live at "<major.minor>beta" (e.g. 152.0beta).
            // The install strips the bN build suffix (152.0); the probe carries it
            // (152.0b3). Drop any trailing bN, then append "beta".
            let base = version.replacingOccurrences(
                of: #"b\d+$"#, with: "", options: .regularExpression)
            return base.hasSuffix("beta") ? base : base + "beta"
        default:
            return version
        }
    }

    /// Forgiving decode: a remotely-authored recipe only needs `bundleID`,
    /// `source`, `entryPattern`, and `itemPatterns`; every tuning field falls back
    /// to its default when omitted. Lets the catalog stay terse.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        source = try c.decode(URL.self, forKey: .source)
        // Empty defaults so a structured recipe (no regex fields) decodes cleanly.
        entryPattern = try c.decodeIfPresent(String.self, forKey: .entryPattern) ?? ""
        itemPatterns = try c.decodeIfPresent([String].self, forKey: .itemPatterns) ?? []
        structuredFormat = try c.decodeIfPresent(StructuredFormat.self, forKey: .structuredFormat)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .html
        stripTags = try c.decodeIfPresent(Bool.self, forKey: .stripTags) ?? true
        decodeEntities = try c.decodeIfPresent(Bool.self, forKey: .decodeEntities) ?? true
        escapedMarkup = try c.decodeIfPresent(Bool.self, forKey: .escapedMarkup) ?? false
        markdownSource = try c.decodeIfPresent(Bool.self, forKey: .markdownSource) ?? false
        maxEntries = try c.decodeIfPresent(Int?.self, forKey: .maxEntries) ?? 40
        minItemLength = try c.decodeIfPresent(Int.self, forKey: .minItemLength) ?? 1
        indexLinkPattern = try c.decodeIfPresent(String.self, forKey: .indexLinkPattern)
        channel = try c.decodeIfPresent(ReleaseChannel.self, forKey: .channel)
        includesPromotedStable = try c.decodeIfPresent(
            Bool.self, forKey: .includesPromotedStable) ?? false
        sourceTemplate = try c.decodeIfPresent(String.self, forKey: .sourceTemplate)
        newestLast = try c.decodeIfPresent(Bool.self, forKey: .newestLast) ?? false
        imagePattern = try c.decodeIfPresent(String.self, forKey: .imagePattern)
        minimumAppVersion = try c.decodeIfPresent(String.self, forKey: .minimumAppVersion)
        belowAppVersion = try c.decodeIfPresent(String.self, forKey: .belowAppVersion)
        httpMethod = try c.decodeIfPresent(HTTPMethod.self, forKey: .httpMethod) ?? .get
        requestBody = try c.decodeIfPresent(Data.self, forKey: .requestBody)
        skipSections = try c.decodeIfPresent([String].self, forKey: .skipSections) ?? []
        acknowledgedStaleEntry = try c.decodeIfPresent(
            String.self, forKey: .acknowledgedStaleEntry)
    }
}

/// The two spellings BetterDisplay has used for its contributor roster, shared by
/// its three per-track recipes so a third spelling is added in one place rather
/// than three. See the recipes' comment for why this is per-app and whole-heading.
private let betterDisplayContributorRosters = [
    "Included Localizations",
    "Localizations included in this release",
]

/// The verified recipe table. Looked up by bundle id when the detail window opens;
/// a miss simply means we keep the existing behavior (embed `changelogURL` in a
/// web view). Adding a recipe is the same loop as a vendor probe: confirm it
/// extracts real entries from the live page (see `ChangelogExtractorTests`) before
/// landing it here.
public enum ChangelogRecipeRegistry {
    public static let recipes: [ChangelogRecipe] = [
        // Air (JetBrains) — air.dev/changelog is a Vite/React SPA: the HTML is an
        // empty shell and the changelog data is baked into the hashed JS bundle as
        // *compiled JSX* (no clean HTML, no JSON API). Two-stage handles the hash:
        // `source` is the shell, `indexLinkPattern` follows the `<script src=
        // "/assets/index-<hash>.js">` to the current bundle (the hash changes every
        // deploy, so we must follow it, never pin it). The entry/item patterns then
        // run against that JS. Each release is an object literal:
        //   {version:"261.681.18",date:"June 2, 2026",title:"...",
        //    description:"...",[image:qE,]content:i.jsxs(i.Fragment,{children:[...]})}
        // `description` and `image` are optional and vary per entry, so `body`
        // captures everything from after `title` to the next `},{version:"` (or the
        // array close `}][,;]`) rather than anchoring on those fields.
        //
        // The content JSX takes three shapes, so itemPatterns are tried in order:
        //   1. after-link — <li>/<p> whose children array opens with an AIR issue
        //      link (i.jsx("a",…)); we grab the description text that follows it.
        //      This is what the older structured releases (h4 section + <ul>) use,
        //      so it must run BEFORE h4 or those entries degrade to the bare
        //      "Features and improvements:" section labels.
        //   2. h4 — feature releases render each feature as an <h4> heading; that
        //      heading list is the change summary.
        //   3. prose — small fix releases are just <p> paragraphs; capture the
        //      lead string, skipping the boilerplate "Share your feedback" footer
        //      that closes nearly every entry.
        //   4. description — when content is only that footer, the real note lives
        //      in the entry's `description` field (anchored to the body start).
        // Feature <p>/<li> open with a plain string (not a link), so after-link
        // never fires on them; a parse miss anywhere just falls back to embedding
        // the SPA, which renders fine in a WKWebView.
        ChangelogRecipe(
            bundleID: "com.jetbrains.air",
            source: URL(string: "https://air.dev/changelog")!,
            entryPattern:
                #"\{version:"(?<version>[^"]+)",date:"(?<date>[^"]*)",title:"(?<title>(?:\\.|[^"\\])*)","#
                + #"(?<body>.*?)(?=\},\{version:"|\}\][,;])"#,
            itemPatterns: [
                #"children:\[i\.jsx\("a",.*?children:"(?:\\.|[^"\\])*"\}\)," ","(?<item>(?:\\.|[^"\\])+)""#,
                #""h4",\{.*?children:"(?<item>(?:\\.|[^"\\])+)""#,
                #""p",\{[^{}]*?children:\[?"(?!Share your feedback)(?<item>(?:\\.|[^"\\])+)""#,
                #"^description:"(?<item>(?:\\.|[^"\\])+)""#,
            ],
            minItemLength: 4,
            indexLinkPattern: #"src="(?<link>/assets/index-[^"]*\.js)""#),

        // Claude Desktop — the official docs changelog at
        // claude.com/docs/cowork/changelog. We fetch the `.md` twin (Mintlify serves a
        // text/markdown form of every docs page): server-rendered, on a stable URL, and
        // free of the hashed-JS + zstd-cache fragility of the in-app "What's new" popup
        // (which reads an inline array baked into claude.ai's web bundle — variable
        // names rotate every deploy). Each release is one block:
        //   <Update label="v1.22209.0" description="2026-07-16"> … </Update>
        // version = the label minus its leading "v" (matches the
        // com.anthropic.claudefordesktop build the VendorProbe reads); date = the
        // description verbatim. Inside, notes are grouped into `**General**`, `**Code**`,
        // `**Cowork**`, and `**3P**` sections of `* ` markdown bullets, in that fixed
        // order. We deliberately DROP the trailing **3P** section — it's enterprise/MDM
        // only (managed-settings.json keys) that a normal user never sees in-app (the
        // popup filters by surface) — by bounding `body` to stop at `**3P**` (or
        // `</Update>` for a block with none). stripTags is OFF because Code notes carry
        // literal angle-bracket text (e.g. a typed `<channel-message>` turn) that
        // tag-stripping would eat; the source is markdown, so there's nothing else to
        // strip or entity-decode. A parse miss just falls back to embedding the page.
        ChangelogRecipe(
            bundleID: "com.anthropic.claudefordesktop",
            source: URL(string: "https://claude.com/docs/cowork/changelog.md")!,
            entryPattern:
                #"<Update label="v(?<version>[^"]+)" description="(?<date>[^"]*)">"#
                + #"(?<body>.*?)(?=\*\*3P\*\*|</Update>)"#,
            itemPatterns: [#"\n[ \t]*\*[ \t]+(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false,
            maxEntries: 20),

        // ChatWise — the public /changelog page is a SvelteKit shell (a ~4 KB
        // document with no notes in it) that hydrates from the releases JSON
        // endpoint, so we read that endpoint directly. It is a newest-first array:
        //   {"version":"26.6.0","changelog":"- new provider: cloudflare workers ai",
        //    "assets":[...],"date":"2026-06-26T16:04:26.161Z"}
        // Decoded as JSON rather than regex-scraped: the notes are a markdown
        // bullet list living inside a JSON string, so on the regex path every
        // newline is a literal `\n` escape that an item pattern must spell as
        // `\\n` — see `.chatwiseReleases` for the last-bullet bug that cost us.
        ChangelogRecipe(
            bundleID: "app.chatwise",
            source: URL(string: "https://releases.chatwise.app/releases")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .chatwiseReleases),

        // VS Code — the official `/updates` page redirects to the latest stable
        // release page (e.g. /updates/v1_123). The top summary is:
        //   <h1>Visual Studio Code 1.123</h1>
        //   ...<hr><p><em>Release date: June 3, 2026</em></p>
        //   ...<ul><li><a …>…</a>: …</li>...</ul>
        //   [<blockquote><p>…event plug…</p></blockquote>]   ← optional, varies
        //   <p>Happy Coding!</p>
        // The highlights <ul> is the only list before "Happy Coding!", so the
        // body anchor is unambiguous; the trailing <blockquote> (an occasional
        // event/announcement aside, e.g. "VS Code Live at Build") is matched
        // optionally so its presence/absence doesn't break the close anchor — the
        // 1.122→1.123 page added it, which is what regressed the old pattern to a
        // webview fallback. We intentionally parse the latest release only; the
        // page itself is the vendor's stable "what changed now" surface.
        ChangelogRecipe(
            bundleID: "com.microsoft.VSCode",
            source: URL(string: "https://code.visualstudio.com/updates")!,
            entryPattern:
                #"<h1>Visual Studio Code (?<version>[0-9.]+)</h1>\s*"#
                + #".*?<p><em>Release date:\s*(?<date>[^<]+)</em></p>\s*"#
                + #".*?<ul>(?<body>.*?)</ul>\s*"#
                + #"(?:<blockquote>.*?</blockquote>\s*)?"#
                + #"<p>Happy Coding!</p>"#,
            itemPatterns: [#"<li>\s*(?:<p>)?(?<item>.*?)(?:</p>)?\s*</li>"#],
            maxEntries: 1),

        // Codex — parse the app-specific OpenAI Developers changelog view rather
        // than the mixed all-topics page. The HTML still contains non-app entries,
        // so we additionally require `data-codex-topics` to include `codex-app`.
        // Capture the human title separately from the optional trailing build
        // number (`<span class="text-tertiary">26.527</span>`), which some app
        // posts have and some do not.
        //
        // The page moved to learn.chatgpt.com in August 2026; the old
        // developers.openai.com/codex/changelog address still 308s here, but a
        // permanent redirect is the vendor's to withdraw, so we follow it once in
        // the registry rather than on every fetch.
        ChangelogRecipe(
            bundleID: "com.openai.codex",
            source: URL(string: "https://learn.chatgpt.com/docs/changelog?type=codex-app")!,
            entryPattern:
                #"<li id="codex-[^"]*"[^>]*data-codex-topics="[^"]*codex-app[^"]*"[^>]*>.*?"#
                + #"<time[^>]*>(?<date>[^<]+)</time>.*?"#
                + #"<h3[^>]*>\s*<span>\s*(?<title>.*?)\s*(?:<span[^>]*>\s*(?<version>[^<]+)\s*</span>)?\s*</span>.*?</h3>.*?"#
                + #"<article[^>]*>(?<body>.*?)</article>"#,
            itemPatterns: [
                #"<li[^>]*>\s*(?:<p>)?(?<item>.*?)(?:</p>)?\s*</li>"#,
                #"<p>(?<item>.*?)</p>"#
            ],
            maxEntries: 20),

        // CleanShot X — Nuxt page, very regular markup. Re-derived 2026-09-01, when
        // the 5.0 release shipped with the page rebuilt around it:
        //   <div class="version"><div class="date">1 September, 2026</div>
        //     <div class="content"><div class="topbar">
        //       <div class="number">5.0</div><div class="text-badge">Major Update</div>
        //     </div>
        //     <p class="change-intro">…</p> <a class="video-link">…</a>   ← 5.0 only
        //     <ul class="changes"><li class="change">…</li>…</ul></div></div>
        //
        // Three things moved at once, which is why nothing matched afterwards: the
        // date now comes *before* the number rather than after it, two wrappers
        // (`content`, `topbar`) appeared between the version div and the number, and
        // a feature release puts a paragraph and two video links between the number
        // and the list. The first two are why the old pattern's `\s*` joints failed;
        // the third is why the number→list gap has to be permissive.
        //
        // That gap is tempered rather than a plain `.*?` so it cannot leave the
        // block it started in. All 102 blocks on today's page carry a
        // `ul.changes`, so a lazy `.*?` finds the right one — but the day one of
        // them doesn't, a lazy gap silently pairs that version with the *next*
        // one's notes, which is the failure that reads as correct. Costs 0.6 ms
        // over the whole 183 KB page.
        ChangelogRecipe(
            bundleID: "pl.maketheweb.cleanshotx",
            source: URL(string: "https://cleanshot.com/changelog")!,
            entryPattern:
                #"<div class="version"[^>]*>\s*"#
                + #"<div class="date"[^>]*>(?<date>[^<]*)</div>\s*"#
                + #"<div class="content"[^>]*>\s*<div class="topbar"[^>]*>\s*"#
                + #"<div class="number"[^>]*>(?<version>[^<]+)</div>"#
                + #"(?:(?!<div class="version").)*?"#
                + #"<ul[^>]*class="changes"[^>]*>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

        // Cursor — the changelog is organised as dated POSTS, not versions: nothing
        // on the page carries a "3.16.17" anywhere, so the date takes the version
        // column and the post's headline becomes the entry title (same shape as
        // Codex above). Structure per post:
        //   <a href="/changelog/08-13-26"><time dateTime="2026-08-13T…">Aug 13, 2026</time></a>
        //   … <h1 class="type-lg" id="…"><a href="/changelog/08-13-26">Title</a></h1>
        //   … <div class="prose prose--block"><p>…</p><ul><li>…</li></ul></div>
        //
        // Two things the real response teaches that the markup doesn't:
        //  • The document contains its whole `<main>` TWICE (it has two `</html>`
        //    tags — a Next.js streaming artifact), so every post matches twice.
        //    `ChangelogExtractor` de-duplicates on version+title; without that the
        //    pane listed each release two rows apart.
        //  • The last post has no following post to stop at, so `<footer` closes the
        //    body — otherwise it swallowed 26KB of page chrome as "items".
        // `www.cursor.com` 308s to the apex domain; followed once here rather than
        // on every fetch.
        ChangelogRecipe(
            bundleID: "com.todesktop.230313mzl4w4u92",
            source: URL(string: "https://cursor.com/changelog")!,
            entryPattern:
                #"href="/changelog/[^"]+"><time[^>]*>(?<version>[^<]+)</time>.*?"#
                + #"<h1[^>]*>\s*<a[^>]*href="/changelog/[^"]+"[^>]*>(?<title>.*?)</a>\s*</h1>.*?"#
                + #"<div class="prose[^"]*">(?<body>.*?)(?=<p class="text-theme-text-sec|<footer|\z)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<p>(?<item>.*?)</p>"#
            ],
            maxEntries: 20),

        // Conductor — Next.js page, each version is an <article> element. Version
        // lives in a font-mono <div>; date in a text-muted-foreground <span>;
        // items in <li class="text-base text-foreground"> (same class throughout).
        // Some entries are image-only posts (no <li> items); they contribute zero
        // items and are silently dropped, which is fine.
        ChangelogRecipe(
            bundleID: "com.conductor.app",
            source: URL(string: "https://www.conductor.build/changelog")!,
            entryPattern:
                #"<article[^>]*>\s*<div[^>]*>.*?font-mono[^>]*>(?<version>[^<]+)</div>.*?"#
                + #"<span[^>]*text-muted-foreground[^>]*>(?<date>[^<]*)</span>.*?"#
                + #"</div></div>\s*<div class="min-w-0">(?<body>.*?)</article>"#,
            itemPatterns: [#"<li[^>]*class="text-base text-foreground"[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 20),

        // TablePlus — Jekyll blog post at /osx/changelog. Each version block:
        //   <h3 id="…">Version 7.1.0 (710) - Liquid Glass</h3>
        //   <h4 id="…">Release date: 26 May 2026.</h4>
        //   <h5>…SHA / Download…</h5>
        //   <ul><li>…</li>…</ul>
        // `title` captures the release name after the build number (e.g. "Liquid Glass").
        ChangelogRecipe(
            bundleID: "com.tinyapp.tableplus",
            source: URL(string: "https://tableplus.com/osx/changelog")!,
            entryPattern:
                #"<h3[^>]*>Version (?<version>\d+\.\d+(?:\.\d+)?) \(\d+\)(?:\s*-\s*(?<title>[^<]+))?</h3>\s*"#
                + #"<h4[^>]*>Release date:\s*(?<date>[^.<]+)[^<]*</h4>"#
                + #".*?"#
                + #"<ul>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li>\s*(?<item>.*?)\s*</li>"#]),

        // AppCleaner — freemacsoft.net/appcleaner/releasenotes.html (referenced as
        // `releaseNotesLink` in the Sparkle feed). Each version is an <h2> with the
        // version number and date, followed by a <ul> of change items:
        //   <h2>AppCleaner 3.6.8 <span class="releasedate">- 4 July, 2023</span></h2>
        //   <ul><li>…</li>…</ul>
        ChangelogRecipe(
            bundleID: "net.freemacsoft.AppCleaner",
            source: URL(string: "https://freemacsoft.net/appcleaner/releasenotes.html")!,
            entryPattern:
                #"<h2>AppCleaner\s+(?<version>[^\s<]+)\s*"#
                + #"<span[^>]*releasedate[^>]*>\s*-\s*(?<date>[^<]+)</span>.*?</h2>\s*"#
                + #"<ul[^>]*>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

        // AweSun (Oray) — same JSON API as the VendorProbeRecipe (verified live
        // 2026-08-21: GET returns 200/~15KB; the earlier "50 bytes" observation
        // that prompted a re-check did not reproduce and the endpoint/logic are
        // both healthy — see `sunLoginSoftwareLogs`'s doc comment for the shape).
        ChangelogRecipe(
            bundleID: "com.oray.sunlogin.macclient",
            source: URL(string: "https://client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM?versiontype=stable")!,
            mode: .json,
            structuredFormat: .sunLoginSoftwareLogs),

        // WeType (微信输入法) — same official changelog page as its VendorProbe.
        // Next.js page with the data server-rendered inline (an `__next_f` RSC blob,
        // no JS needed): a flat list of release objects for ALL platforms, tagged
        // `"platform":1`=iOS / `2`=Android / `3`=macOS / `4`=Windows. The entry
        // pattern ties the captured version/body to its OWN object's `"platform":3`
        // (version precedes platform; `[^"]*` can't cross a structural quote, so it
        // can't bleed into an adjacent platform's object) — so only macOS releases
        // become entries. The notes live in `content_html`, where each line is its
        // own tag — usually `<h2>` (including the dash-bulleted lines), sometimes
        // `<ul><li>` or `<p>` — so itemPatterns try all three. No human per-entry
        // date is published (only a unix `release_date`), so `date` is omitted
        // rather than shown as a raw epoch. CRUCIAL: the list runs oldest→newest, so
        // `newestLast` flips it to newest-first before the cap. Quotes inside notes
        // are `&quot;`-encoded (no raw `"`), so the `[^"]*` field bounds hold and the
        // default HTML entity decode renders them. A parse miss falls back to
        // embedding this same page (the VendorProbe's changelogURL).
        ChangelogRecipe(
            bundleID: "com.tencent.inputmethod.wetype",
            source: URL(string: "https://z.weixin.qq.com/web/change-log/macos")!,
            entryPattern:
                #""version":"(?<version>[0-9][^"]*)","content":"[^"]*","#
                + #""content_html":"(?<body>[^"]*)","platform":3"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<h2[^>]*>(?<item>.*?)</h2>"#,
                #"<p[^>]*>(?<item>.*?)</p>"#,
            ],
            maxEntries: 20,
            newestLast: true),

        // 豆包输入法 (DoubaoIme) — the vendor publishes no release-notes page; the
        // notes only exist inside the endpoint the app's own updater polls:
        //
        //   ime.doubao.com/api/v1/version/list?channel=&version_code=&platform=
        //
        // It answers "what should a client on <version_code> be offered", so it needs
        // all three parameters (it 400s with 渠道/当前版本/平台不能为空 otherwise) and
        // returns [] once the caller is current. We pass `version_code=1` — an
        // impossibly old client — so the newest release's notes always come back,
        // whatever the reader has installed. `channel=release` is the user-facing
        // track; `inhouse` and `test` also answer but are ByteDance's internal builds
        // (the installed bundle's Info.plist carries `CHANNEL_NAME = release`).
        //
        //   {"list":[{"channel":"release","platform":"macOS","version_name":"0.9.6",
        //     "version_code":90601,"change_log":"- 新增账号登录…；\n- 新增离线语音…",
        //     …,"push_message":{"title":"豆包输入法已更新至 0.9.6 版本",…}}]}
        //
        // The entry pattern is anchored on `"platform":"macOS"` immediately before
        // `version_name` and walks the fields in emitted order, so it can only ever
        // bind a version to the `change_log` of its OWN object — and it cannot reach
        // the version number sitting in `push_message.title`.
        //
        // `change_log` is one string of `- `-prefixed lines joined by escaped `\n`,
        // so the item pattern splits on those. NOTE the tail alternative is `|$)`,
        // NOT the `|\\n?$)` used by the ChatWise recipe above: `\\n?` means "a literal
        // backslash, optionally followed by n", which requires the body to END in a
        // backslash and therefore drops the last bullet. Verified against the real
        // 2026-08-21 response: 6 bullets in, 6 out.
        ChangelogRecipe(
            bundleID: "com.bytedance.inputmethod.doubaoime",
            source: URL(string:
                "https://ime.doubao.com/api/v1/version/list"
                + "?channel=release&version_code=1&platform=macos")!,
            entryPattern:
                #""platform":"macOS","version_name":"(?<version>[0-9][^"]*)","#
                + #""version_code":\d+,"change_log":"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [
                #"(?:^|\\n)-\s*(?<item>.*?)\s*(?=\\n-\s|$)"#,
                #"\s*(?<item>.+?)\s*$"#,
            ],
            mode: .json,
            stripTags: false,
            maxEntries: 20),

        // WeChat (微信, 官网版) — the official updates site publishes ONE page per
        // Mac version at `weixin.qq.com/updates?platform=mac&version=<X.Y.Z>`, with the
        // exact labels/dates the user sees in-app (4.1.10, 4.1.9, …). The Sparkle feed
        // the VendorProbe reads is NOT a usable changelog source: it carries 4-segment
        // labels (4.1.10.53) and a sparse, gap-ridden history. So this is a templated
        // recipe (like Thunderbird): `{version}` is the marketing version the probe
        // offers (or the installed one), substituted to fetch exactly that release's
        // page. It's a Nuxt SSR page but the notes are server-rendered: a `faq_title`
        // "微信 <ver> for Mac …", a `发布日期：<date>`, then the change lines as `<h4>`
        // inside `#page_center`. We bound `body` to that container so unrelated `<h4>`
        // (footer/marketing) can't leak in. A parse miss falls back to the webview
        // (the VendorProbe's changelogURL).
        ChangelogRecipe(
            bundleID: "com.tencent.xinWeChat",
            source: URL(string: "https://weixin.qq.com/updates?platform=mac")!,
            entryPattern:
                #"微信 (?<version>[0-9]+(?:\.[0-9]+)+) for Mac.*?"#
                + #"发布日期[：: ]*(?<date>[0-9-]+).*?"#
                + #"<div id="page_center"[^>]*>(?<body>.*?)</div>"#,
            itemPatterns: [
                // Notes carry a literal "- " bullet; drop it so the UI's own bullet
                // doesn't render as "• - …".
                #"<h4[^>]*>\s*-?\s*(?<item>.*?)</h4>"#,
            ],
            sourceTemplate: "https://weixin.qq.com/updates?platform=mac&version={version}",
            // Each release embeds one or more feature screenshots between the change
            // lines (res.wxqcloud.qq.com.cn / res.wx.qq.com); surface them inline.
            imagePattern: #"<img[^>]+src="(?<image>https?://[^"]+)""#),

        // Fork — git-fork.com/releasenotes is a single server-rendered page with all
        // Mac releases. Each version block opens with:
        //   <h4 class="header4 release-notes">Fork 2.67</h4>
        //   ...
        //   <h5 class="date">15 May 2026</h5>
        // and contains any number of items wrapped in:
        //   <div class="media-body"><p class="lead">text</p></div>
        // The block ends at the next <h4 class="header4 release-notes"> tag.
        ChangelogRecipe(
            bundleID: "com.DanPristupov.Fork",
            source: URL(string: "https://git-fork.com/releasenotes")!,
            entryPattern:
                #"<h4 class="header4 release-notes">Fork (?<version>[^<]+)</h4>"#
                + #".*?<h5 class="date">(?<date>[^<]+)</h5>"#
                + #"(?<body>.*?)"#
                + #"(?=<h4 class="header4 release-notes">|$)"#,
            itemPatterns: [
                #"<div class="media-body">\s*<p class="lead">\s*(?<item>.*?)\s*</p>"#,
            ]),

        // Ghostty — two-stage, same shape as VLC. `source` is the newest-first
        // release-notes index; `indexLinkPattern` follows its first per-version link
        // (currently /docs/install/release-notes/1-3-1) to that version's page. This
        // replaces the old version-pinned URL, so a new release is picked up with no
        // re-run of the fragile-recipe skill. The detail page is unchanged in shape:
        // version and date live in the <meta name="description"> tag near the top:
        //   content="Release notes for Ghostty 1.3.1, released on March 13, 2026."
        // Items are <li class="...weightRegular..."> in the Full Changelog section,
        // which follows the Highlights prose. That heading's generated id changed
        // from `full-changelog-2` to `full-changelog` in August 2026; accept the
        // stable slug plus an optional numeric suffix rather than pinning either
        // build artifact.
        ChangelogRecipe(
            bundleID: "com.mitchellh.ghostty",
            source: URL(string: "https://ghostty.org/docs/install/release-notes")!,
            entryPattern:
                #"<meta name="description" content="Release notes for Ghostty (?<version>[^,]+), released on (?<date>[^.]+)\."[^>]*>"#
                + #".*?"#
                + #"id="full-changelog(?:-\d+)?">.*?</div></div>\s*(?<body>.*?)</main>"#,
            itemPatterns: [
                #"<li class="[^"]*weightRegular[^"]*">(?<item>.*?)</li>"#,
            ],
            indexLinkPattern: #"href="(?<link>/docs/install/release-notes/\d[^"]*)""#),

        // Postman — CDN-hosted JSON array under the "notes" key (newest-first).
        // Each element has "version", "content" (Markdown; `\r\n` line separators in
        // recent entries, bare `\n` in older ones) and "createdAt" (ISO-8601).
        // Structured decode (StructuredChangelogDecoder.decodePostman): split
        // `content` on real newlines, strip the `#### ` feature-heading prefix
        // (keeping the heading text as an item), skip `##`/`###` section headers and
        // the "August 21, 2026"-style date line, drop lines under 10 chars, keep
        // everything else (including markdown syntax like `**bold**` / `[t](url)`
        // verbatim — nothing downstream strips it for this recipe). This replaces a
        // regex itemPattern that only recognized the escaped `\\r\\n` form and, on
        // top of that, truncated any line containing an escaped quote at the
        // backslash (`[^\\]{10,}` stops there) — confirmed against the live feed:
        // 2 of the 30 most recent releases had a mid-sentence truncation the old
        // path produced silently.
        ChangelogRecipe(
            bundleID: "com.postmanlabs.mac",
            source: URL(string: "https://mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json")!,
            mode: .json,
            maxEntries: 30,
            structuredFormat: .postmanReleaseNotes),

        // HBuilderX (DCloud) — SINGLE-hop now, not two-stage: hx.dcloud.net.cn
        // serves a plain markdown changelog directly (200, ~95 KB, no redirect,
        // no per-request tokenized CDN hop), so there is no index page to follow
        // and no `indexLinkPattern` here anymore (that's how the old
        // download1.dcloud.net.cn/release.json + HTML-detail-page two-stage
        // fetch worked; this recipe replaces it wholesale, not on top of it).
        // NOT `structuredFormat`: that decoder path (`StructuredChangelogDecoder`)
        // is for feeds too irregular for the regex extractor; this one is a
        // clean, uniform `## <version>` / `* <item>` document that the regex
        // path (same as com.anthropic.claudefordesktop above) handles
        // directly — and `structuredFormat` would also disable
        // `indexLinkPattern` handling in `ChangelogService`, which is irrelevant
        // here anyway since there's no second hop to disable.
        //
        // Format: `## 5.24.2026081301` heading (the build IS the version, no
        // separate date — same as the old HTML: there was never a `date` group
        // there either, so this is not a regression), then `* ` bullet lines,
        // e.g. `* 修复 ... [详情](https://issues.dcloud.net.cn/...)`. The
        // trailing `[详情](url)` / `[文档](url)` markdown link (occasionally two
        // in a row, occasionally followed by a bare `<url>` autolink) is stripped
        // by the item pattern rather than kept literal — flattening it to just
        // the link text (as `StructuredChangelogDecoder.bulletItems` does for
        // the structured path) isn't reachable from here without a much bigger
        // change to the regex extractor, so instead the pattern simply excludes
        // any *trailing* link syntax from the captured item. This covers the
        // overwhelming majority of lines (verified: 1301/1303 items across both
        // documents — 618 in release, 685 in alpha — have their link(s) fully
        // stripped this way; the sole exception in EACH document is one line
        // where the link sits mid-sentence rather than at the end — that rare
        // case is left with its `[text](url)` literal intact).
        //
        // Content scope: this md endpoint covers only the HBuilder IDE itself —
        // the old HTML detail page's other module sections (uni-app x, uni-app,
        // uts插件, uniCloud, App插件) aren't in it. That's an intentional
        // narrowing (confirmed against the HTML: every md item matches an
        // HBuilder-section item in the HTML verbatim, including issue ids — it's
        // a subset, not a rewrite/summary), so fewer items per entry here vs.
        // before is expected, not a parsing regression.
        //
        // Version group has no `-alpha` suffix, matching only bare `X.Y.Z`
        // headings (the alpha recipe below requires the suffix) — moot in
        // practice since the two channels are served from separate documents,
        // but kept for the same belt-and-suspenders reason the old HTML regexes
        // did.
        ChangelogRecipe(
            bundleID: "io.dcloud.HBuilderX",
            source: URL(
                string: "https://hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_release.md")!,
            entryPattern:
                #"## (?<version>[0-9]+\.[0-9]+\.[0-9]+)\n"#
                + #"(?<body>.*?)"#
                + #"(?=\n## |$)"#,
            itemPatterns: [
                #"(?:^|\n)[ \t]*\*[ \t]+(?<item>[^\n]+?)(?:\s*\[[^\]\n]*\]\([^)\n]*\))*(?:\s*<[^>\n]*>)?(?=\n|$)"#
            ],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            // The doc is a years-long cumulative list (32 versions); cap to the
            // recent handful, same as before.
            maxEntries: 10,
            minItemLength: 4),

        // HBuilderX Alpha (DCloud) — the alpha is a SEPARATE app (bundle id
        // io.dcloud.HBuilderXAlpha, ships as HBuilderX-Alpha.app), so it needs its
        // own recipe; the stable io.dcloud.HBuilderX one never matches it. Same
        // single-hop markdown shape as stable, reading the alpha document
        // instead, whose version headings all carry an "-alpha" suffix
        // (5.23.2026080313-alpha) — the version group requires it, so a stray
        // stable heading could never be mis-captured here. See the stable
        // recipe above for the full rationale (single-hop rewrite, why not
        // `structuredFormat`, link-stripping, and the HBuilder-IDE-only scope).
        ChangelogRecipe(
            bundleID: "io.dcloud.HBuilderXAlpha",
            source: URL(
                string: "https://hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_alpha.md")!,
            entryPattern:
                #"## (?<version>[0-9]+\.[0-9]+\.[0-9]+-alpha)\n"#
                + #"(?<body>.*?)"#
                + #"(?=\n## |$)"#,
            itemPatterns: [
                #"(?:^|\n)[ \t]*\*[ \t]+(?<item>[^\n]+?)(?:\s*\[[^\]\n]*\]\([^)\n]*\))*(?:\s*<[^>\n]*>)?(?=\n|$)"#
            ],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            // Alpha document lists 67 versions; same cap as stable.
            maxEntries: 10,
            minItemLength: 4),

        // Ollama — GitHub releases page. Each release is a <section> with an
        // sr-only h2 (version tag, e.g. "v0.30.0"), a <relative-time> element
        // (ISO datetime), and a <div class="markdown-body …"> with the release
        // body. The version group strips the leading "v" by not capturing it.
        // Only <h2> values matching v+digits are captured so nav sections skip.
        ChangelogRecipe(
            bundleID: "com.electron.ollama",
            source: URL(string: "https://github.com/ollama/ollama/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>v(?<version>[\d.]+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),

        // RustDesk — GitHub releases page, same shape as Ollama but the sr-only
        // <h2> carries a bare version ("1.4.7", no leading "v"), so the version
        // group matches digits directly. Each release is a <section> with an
        // sr-only h2 (version), a <relative-time datetime="…"> (ISO datetime),
        // and a <div class="markdown-body …"> body. Notes open with a screenshot
        // and a contributor line before the change bullets; those extra <li> are
        // cosmetic and a parse miss just falls back to the embedded page.
        ChangelogRecipe(
            bundleID: "com.carriez.rustdesk",
            source: URL(string: "https://github.com/rustdesk/rustdesk/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>(?<version>[\d.]+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),

        // Zed Preview and Stable — both used to scrape the 2+ MB server-rendered
        // zed.dev/releases/{preview,stable} pages (`<div id="zed-X.Y.Z">` blocks
        // with an `<article>` of `<li>` items). Replaced 2026-08-21 with the
        // GitHub Releases API list we already fetch for version detection
        // (`GitHubReleaseRule` in `GitHubReleasesSource.swift`, bundle ids
        // `dev.zed.Zed` / `dev.zed.Zed-Preview`): one JSON response instead of two
        // multi-megabyte HTML pages, and verified byte-for-byte equivalent notes
        // (see `StructuredFormat.zedGitHubReleases`). Both channels share this one
        // recipe's URL; `StructuredChangelogDecoder` splits on `channel` the same
        // way it does for Warp.
        ChangelogRecipe(
            bundleID: "dev.zed.Zed-Preview",
            source: URL(
                string: "https://api.github.com/repos/zed-industries/zed/releases?per_page=40")!,
            maxEntries: 15,
            channel: .preview,
            structuredFormat: .zedGitHubReleases),

        ChangelogRecipe(
            bundleID: "dev.zed.Zed",
            source: URL(
                string: "https://api.github.com/repos/zed-industries/zed/releases?per_page=40")!,
            maxEntries: 15,
            channel: .stable,
            structuredFormat: .zedGitHubReleases),

        // UTM Stable and Beta publish in one GitHub repository with plain numeric
        // tags and the same `UTM.dmg` asset name. The release record's
        // `prerelease` bit is the only split, matching the corresponding
        // GitHubReleaseRule. Two channel-keyed recipes over the same JSON keep the
        // histories apart: Stable never shows the v5 previews.
        //
        // The Beta recipe is NOT the mirror image, and that asymmetry is the
        // point: UTM's previews graduate into the same numbering (`v4.7.0…v4.7.3`
        // are "(Beta)", `v4.7.4`/`v4.7.5` are not), so a preview install is
        // legitimately offered a release the `prerelease` bit calls stable — and
        // `includesPromotedStable` is what stops that update's notes from
        // rendering as an empty panel. See `GitHubCandidateScope`.
        ChangelogRecipe(
            bundleID: "com.utmapp.UTM",
            source: URL(
                string: "https://api.github.com/repos/utmapp/UTM/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .gitHubReleases),

        ChangelogRecipe(
            bundleID: "com.utmapp.UTM",
            source: URL(
                string: "https://api.github.com/repos/utmapp/UTM/releases?per_page=40")!,
            mode: .json,
            // 40, not stable's 20: this side reads BOTH kinds out of one 40-entry
            // page, so a 20-entry cap would spend part of the window on releases
            // the preview history is not about — and the entry pushed out first is
            // the graduated one an install is actually being offered, which is the
            // whole reason this recipe keeps final releases. Measured on the live
            // page: within the top 40 there are 24 previews and 16 final releases,
            // `v4.7.5` sits at index 7, and 33 further releases would have to ship
            // before it fell out. At the old cap of 20 that margin was 13.
            maxEntries: 40,
            channel: .beta,
            includesPromotedStable: true,
            structuredFormat: .gitHubReleases),

        // OrbStack — VitePress docs at docs.orbstack.dev/release-notes. The page
        // is server-side rendered with the full changelog inline. Each version is
        // an <h2 id="v{major}-{minor}-{patch}-{month}-{day}"> whose visible text
        // is "v{version} ({month} {day})", followed immediately by a <ul>. The id
        // slug uses month names (e.g. "v2-1-3-may-10") so [\w-]+ is needed.
        ChangelogRecipe(
            bundleID: "dev.kdrag0n.MacVirt",
            source: URL(string: "https://docs.orbstack.dev/release-notes")!,
            entryPattern:
                #"<h2[^>]+id="v[\w-]+"[^>]*>v(?<version>[\d.]+)\s*\((?<date>[^)]+)\).*?</a></h2>\s*"#
                + #"<ul>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),

        // LM Studio — Next.js changelog index. The index page already carries the
        // *full* release notes for the latest ~10 versions inline (the visible
        // truncation is a CSS mask only; the markup is complete), so we parse it
        // directly rather than the per-version pages. Each entry is:
        //   <a href="/changelog/lmstudio/lmstudio-v0.4.20">
        //     <span class="sr-only">LM Studio 0.4.20</span></a>
        //   …<div class="markdown-body …"><p><strong>Build 1</strong></p>
        //     <ul class="list-disc"><li>…</li>…</ul>…</div></div></div>
        // No per-entry date is printed on the index, so `date` is omitted. Notes
        // use nested <ul> for sub-bullets; the <li> pattern folds a sub-list into
        // its parent line — cosmetically fine, and a miss just falls back to the
        // embedded page.
        //
        // 2026-08-09: the bare `/changelog` root is NOT this app's changelog any
        // more — Element Labs repurposed it for **Bionic**, a different product
        // ("Bionic Changelog | LM Studio", entries `bionic-v1.0.6` /
        // `<span class="sr-only">Bionic 1.0.6</span>`). LM Studio itself is still on
        // the 0.4.x train (`versions-prod.lmstudio.ai` says 0.4.20) and its notes
        // moved to `/changelog/lmstudio`, with the per-version slug nested one level
        // deeper. Chasing the rebrand by matching `bionic-v` would have shown Bionic
        // 1.0.x notes to an LM Studio 0.4.x install, so the fix is the new URL plus
        // an href that tolerates both the nested and the old flat slug. The literal
        // `LM Studio ` in the sr-only span is the guard that keeps Bionic entries
        // out: a Bionic block simply doesn't match, and zero entries falls back.
        ChangelogRecipe(
            bundleID: "ai.elementlabs.lmstudio",
            source: URL(string: "https://lmstudio.ai/changelog/lmstudio")!,
            entryPattern:
                #"href="/changelog/(?:lmstudio/)?lmstudio-v[^"]*">\s*"#
                + #"<span class="sr-only">LM Studio (?<version>[^<]+)</span></a>"#
                + #".*?"#
                + #"<div class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>\s*</div>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

        // Tailscale — official changelog page. Entries are `<article id="YYYY-MM-DD">`
        // elements; each date group may contain a macOS client entry AND service-only
        // entries (Kubernetes Operator, container image, etc.). The pattern matches only
        // articles whose body contains `<h3 class="changelog-title…">Tailscale v…</h3>`,
        // so service-only dates are silently skipped. The `date` group is the article id
        // (ISO date string). Items are `<li data-change="…">` inside the client div;
        // the body lookahead stops before the next `<div id=` (another entry in the same
        // date group) or the closing `</article>`.
        ChangelogRecipe(
            bundleID: "io.tailscale.ipn.macsys",
            source: URL(string: "https://tailscale.com/changelog")!,
            entryPattern:
                #"<article id="(?<date>[^"]+)"[^>]*>.*?"#
                + #"<h3 class="changelog-title[^"]*">Tailscale v(?<version>[^<]+)</h3>"#
                + #"(?<body>.*?)(?=<div id="|</article>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

        // Warp — read the machine-readable feed, not the docs site. As of mid-2026
        // docs.warp.dev sits behind a Vercel "Security Checkpoint" JS bot wall that
        // returns HTTP 429 + a challenge page to any non-browser fetch, so the old
        // Starlight-HTML scrape (year-pinned `/changelog/2026/`) went permanently
        // dark. `releases.warp.dev/channel_versions.json` is the same ungated
        // endpoint the vendor probe already uses and carries a full per-channel,
        // per-version `changelogs` map (date + markdown sections) — richer and far
        // more stable than scraping rendered HTML. One recipe per channel; both
        // point at the same JSON but the `channel` selects the sub-feed (and gives
        // each its own cache slot — see `ChangelogService`). The entries are NOT in
        // newest-first document order in the JSON, so the structured decoder sorts
        // by the (lexically-chronological) version key — hence not a regex recipe.
        //
        // Stable and Preview only. There is deliberately **no Dev recipe**: Warp
        // ships a real `dev.warp.Warp-Dev` build and the probe tracks its version
        // fine, but the vendor publishes no notes for that track. `changelogs.dev`
        // holds exactly one entry — and it is fixture data, unchanged for years
        // (verified 2026-08-09):
        //   "v0.2026.08.07.08.31.dev_00": { "date": "2021-11-23T10:07:01-06:00",
        //     "sections": [ { "title": "dev", "items": ["dev 1", "dev 2"] } ],
        //     "oz_updates": ["[TEST] Testing Oz recent updates!", …] }
        // The version key tracks the live dev build, but the body is placeholder
        // text under a 2021 date, and it uses the pre-2022 `sections` shape rather
        // than the `markdown_sections` every real entry has had since. Surfacing
        // "dev 1 / dev 2" under the installed dev version would be worse than
        // nothing, so Warp-Dev carries no recipe and falls back to embedding
        // docs.warp.dev/changelog — same call, and the same reasoning, as the
        // VendorProbe declining to probe the abandoned beta/canary tracks.
        ChangelogRecipe(
            bundleID: "dev.warp.Warp-Stable",
            source: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            maxEntries: 20,
            channel: .stable,
            structuredFormat: .warpChannelVersions),
        ChangelogRecipe(
            bundleID: "dev.warp.Warp-Preview",
            source: URL(string: "https://releases.warp.dev/channel_versions.json")!,
            maxEntries: 20,
            channel: .preview,
            structuredFormat: .warpChannelVersions),

        // 微信开发者工具 (WeChat DevTools) — three channels under one (synthesized)
        // bundle id, each with its own notes train, so one recipe per channel keyed
        // by `channel`; `AppScanner` reads the install's channel out of the app's own
        // `package.json` (see `weChatDevToolsIdentity`) and
        // `recipe(forBundleID:channel:)` routes to the matching train.
        //
        // Version-templated, like Thunderbird: the vendor publishes ONE document per
        // release (`logs/<channel>_v<version>.json`) and no "latest" alias, so the
        // target version is substituted at load time and the notes on screen are
        // always the build being offered. The docs page (`log.html#stable-<version>`)
        // renders these very files — it's a Vue SPA reading them over fetch, so the
        // JSON is the source and the page is the rendering, not the other way round.
        ChangelogRecipe(
            bundleID: "com.tencent.wechatdevtools",
            source: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .json,
            channel: .stable,
            sourceTemplate: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/logs/stable_v{version}.json",
            structuredFormat: .weChatDevToolsLog),
        ChangelogRecipe(
            bundleID: "com.tencent.wechatdevtools",
            source: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .json,
            channel: .rc,
            sourceTemplate: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/logs/rc_v{version}.json",
            structuredFormat: .weChatDevToolsLog),
        ChangelogRecipe(
            bundleID: "com.tencent.wechatdevtools",
            source: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .json,
            channel: .nightly,
            sourceTemplate: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/logs/nightly_v{version}.json",
            structuredFormat: .weChatDevToolsLog),

        // Typeless — the release-notes page ships every version's notes (with a
        // hero image per release) base64+gzip'd inside the Next.js `__NEXT_DATA__`.
        // No regex can read that, so the structured decoder inflates it and emits
        // rich entries (image + prose blocks). Single channel. `maxEntries` caps the
        // long history (20 versions back to 0.1.0) at the most recent handful. The
        // page lists an upcoming version a few days ahead of its date; that's fine —
        // the changelog is informational and the vendor probe still gates "update
        // available" on the GA electron-builder feed.
        ChangelogRecipe(
            bundleID: "now.typeless.desktop",
            source: URL(string: "https://www.typeless.com/help/release-notes/macos")!,
            maxEntries: 12,
            structuredFormat: .typelessReleaseNotes),

        // VLC — two-stage. `source` is the newest-first releases index; the
        // `indexLinkPattern` follows its first per-version link (currently
        // /vlc/releases/3.0.23.html) to the detail page, which avoids version-pinning
        // *and* the merge trap: VLC folds 3.0.19/3.0.20 — and 3.0.22/3.0.23 — onto a
        // single page, so the page is not always named after the latest version;
        // following the real href is correct where templating a version would 404.
        // (The companion NEWS file at code.videolan.org is behind an Anubis
        // proof-of-work wall, so it can't be fetched — hence the marketing page.)
        // The detail page is mostly marketing, but the "X Fixes" section carries the
        // real changelog. Its heading reads "3.0.22/3.0.23 Fixes" (the slash form
        // lists the superseded build), so `(?:[\d.]+/)*` skips the leading versions
        // and captures the final one. The Fixes block shares a single <section> with
        // the "3.0 Highlights" / "3.0 Features" marketing lists, so the body lookahead
        // must stop at the next <h1> — bounding to </section> would swallow those
        // feature bullets. No per-entry date is printed.
        ChangelogRecipe(
            bundleID: "org.videolan.vlc",
            source: URL(string: "https://www.videolan.org/vlc/releases/")!,
            entryPattern:
                #"<h1[^>]*>(?:[\d.]+/)*(?<version>[\d.]+)\s*Fixes</h1>\s*"#
                + #"(?<body>.*?)(?=<h1|</section>)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 1,
            indexLinkPattern: #"href="(?<link>/vlc/releases/\d[^"]*\.html)""#),

        // Slack (desktop, mac) — slack.com/release-notes/mac is a fully
        // server-rendered page listing every mac release newest-first. Each
        // release is one <article>:
        //   <article><a name="11727"></a>
        //     <h2 class="u-flex u-align--center">Slack 4.50.128</h2>
        //     <p>May 26, 2026</p>
        //     <h3>Bug Fixes</h3><ul><li>…</li></ul></article>
        // The <a name> anchor and the section <h3> vary (Bug Fixes / What's New /
        // Security Guidance, sometimes several per entry), so the body captures
        // everything up to </article> and the <li> pattern sweeps all sections.
        // The date <p> is wrapped optional for safety though every entry has one.
        ChangelogRecipe(
            bundleID: "com.tinyspeck.slackmacgap",
            source: URL(string: "https://slack.com/release-notes/mac")!,
            entryPattern:
                #"<article>\s*(?:<a name="[^"]*"></a>\s*)?"#
                + #"<h2[^>]*>Slack\s+(?<version>[\d.]+)</h2>\s*"#
                + #"(?:<p[^>]*>(?<date>[^<]*)</p>\s*)?"#
                + #"(?<body>.*?)</article>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 30),

        // Notion — the DESKTOP app's real "What's New" page,
        // `notion.notion.site/What-s-New-Mac-Windows-5936dabc8dd6497895786c91b9d6f12a`.
        // This is the recipe wired up for `notion.id`; see `NOT REGISTERED` below
        // for the *other* Notion recipe this replaces and why.
        //
        // The rendered HTML is a 19 KB empty Next.js shell — zero content. The real
        // notes come from Notion's own internal, unauthenticated page-rendering API,
        // which only answers a POST:
        //   POST https://notion.notion.site/api/v3/loadPageChunk
        //   {"pageId":"5936dabc-8dd6-4978-9578-6c91b9d6f12a","limit":50,
        //    "cursor":{"stack":[]},"chunkNumber":0,"verticalColumns":false}
        // (`source` below is set to that API URL directly — there is nothing
        // useful to fetch at the human-facing page URL itself.) See
        // `StructuredChangelogDecoder.decodeNotionPageChunk` for the response shape
        // (`recordMap.block`, double-`value` wrapping, and the page block's
        // `content` array as the true reading order) and how the header/text/
        // bulleted_list blocks are grouped into releases.
        //
        // Verified live 2026-08-22: the header text is "v7.31.0" (`v` stripped so
        // the rail label reads "7.31.0", matching the installed build the vendor
        // probe's `.redirectFilename` reports) and the release order runs
        // v7.31.0 → v7.29.0 → v7.28.0 → … — newest first, real desktop builds, not
        // the product-announcement post titles the old recipe surfaced.
        ChangelogRecipe(
            bundleID: "notion.id",
            source: URL(string: "https://notion.notion.site/api/v3/loadPageChunk")!,
            maxEntries: 20,
            structuredFormat: .notionPageChunk,
            httpMethod: .post,
            requestBody: Data(
                (#"{"pageId":"5936dabc-8dd6-4978-9578-6c91b9d6f12a","limit":50,"#
                    + #""cursor":{"stack":[]},"chunkNumber":0,"verticalColumns":false}"#
                ).utf8)),

        // Waku — GitHub releases, not the appcast's own notes link.
        //
        // The appcast points `<sparkle:releaseNotesLink>` at a per-version file,
        // `releases.waku.sh/Waku-<version>.md`, whose body is a bare Markdown
        // bullet list — no heading, no title, no version in it — so it produced no
        // entries and the pane fell back to a web view rendering raw `- ` lines.
        // That file is fetchable for any version by name (0.1.9 … 0.1.12 all 200)
        // but the site root 404s, so there is NO index: templating it can only ever
        // show the one version being offered.
        //
        // github.com/egoist/waku carries the same bullets AND the history — seven
        // releases, each with its published date. Same content, more of it, and it
        // reuses the decoder every other GitHub-sourced app already goes through.
        // Two of those seven (v0.1.9, v0.1.7) say only "See CHANGELOG.md for
        // details."; they still get an entry, via `GitHubMarkdownParser`'s prose
        // pass, rather than leaving a gap in the version rail.
        ChangelogRecipe(
            bundleID: "sh.waku",
            source: URL(string: "https://api.github.com/repos/egoist/waku/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),

        // Shotbase — GitHub releases, because the appcast carries no notes at all.
        //
        // `updates.shotbase.com/appcast.xml` is a stock Sparkle 2.9.5 feed served
        // off GitHub Pages, and `SparkleAppcastSource` already answers for the app
        // from it. What it cannot do is render notes: not one of the seven items
        // carries a `<description>` or a `<sparkle:releaseNotesLink>`, so there is
        // neither inline text to parse NOR a page to fall back to in a web view —
        // the pane would simply be blank.
        //
        // github.com/notnotDudu/shotbase-releases is where the notes actually live:
        // one "## What’s new" bullet list per version, same releases the
        // appcast’s enclosures are downloaded from. The trailing
        // "Source build: [`<sha>`](…)" line is not a bullet, so the strict pass
        // drops it; v1.0.0, whose body is a single sentence, still gets an entry
        // through `GitHubMarkdownParser`’s prose pass rather than leaving a gap in
        // the rail. v0.9.0 is flagged prerelease upstream (an "upgrade-rehearsal
        // baseline" kept only to exercise the Sparkle path) and this decoder skips
        // prereleases, which is the right answer — nobody opted into that track.
        ChangelogRecipe(
            bundleID: "com.shotbase.app",
            source: URL(
                string:
                    "https://api.github.com/repos/notnotDudu/shotbase-releases/releases?per_page=40"
            )!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),

        // BetterDisplay — the same GitHub release bodies the vendor's own page was
        // already showing, rendered natively instead of in a web view.
        //
        // The appcast carries no `<description>`; every item points
        // `<sparkle:releaseNotesLink>` at
        // `waydabber.github.io/BetterDisplay/changelog.html?tag=<tag>`. That page is
        // an EMPTY shell — fetched 2026-08-27, 1149 bytes, no body content at all.
        // Its inline script reads `?tag`, GETs
        // `api.github.com/repos/waydabber/BetterDummy/releases/tags/<tag>` (the old
        // repo name, still redirecting) and renders `response.body` with marked.js.
        // So the web view was rendering GitHub markdown the whole time, minus our
        // styling and plus the vendor's "Download app for macOS" button image. Going
        // to the API directly gets the identical text, the version and date headings
        // the shell never had, and the history a per-tag page cannot hold.
        //
        // THREE recipes, one per track — none of them removable as a duplicate,
        // even though `.beta` and `.unstable` differ only in `channel`. The tracks
        // split on GitHub's `prerelease` flag, and BetterDisplay resolves its
        // channel from two Settings toggles rather than from the bundle id (see
        // `BetterDisplayChannel`):
        //   * `.stable`   → prerelease: false — v4.3.6, v4.3.5, …
        //   * `.beta`     ("Receive pre-release updates") → prerelease: true —
        //                 v5.0.3, v5.0.2, … Includes the two `arm64_pre` builds
        //                 (v5.0.0/v5.0.1), which are excluded from what we OFFER
        //                 because they are Apple-silicon-only, but are real history
        //                 and belong in the rail.
        //   * `.unstable` ("Receive internal pre-release updates") → deliberately
        //                 the same feed as `.beta`. The internal track has no
        //                 per-version notes anywhere: its items link
        //                 `changelog.html?tag=pre`, and that rolling release's body
        //                 is static boilerplate about what internal builds are. The
        //                 pre track is where those builds come from and the closest
        //                 true history for them; without this third registration the
        //                 channel-aware lookup would fall back to `.stable` and show
        //                 an internal 5.x user the 4.x notes.
        //
        // That rolling `pre` release cannot leak into either rail as an entry titled
        // "pre": GitHub orders this endpoint by `created_at`, and `pre` was created
        // 2022-04-06 while the 40th-newest release is 2025-01-03 (both read
        // 2026-08-27). It is far outside a `per_page=40` window and sinks further
        // with every release the vendor cuts.
        //
        // `skipSections` drops the contributor roster. It is not a changelog: 18 of
        // the newest 40 releases carry it, and between them they use only TWO
        // distinct texts — the same paragraph repeated down a 15-row rail. The
        // vendor gives no marker for it (no HTML comment, no `<details>` anywhere in
        // those 40 bodies), so the heading IS the marker, and they have spelled it
        // two ways. Both are listed. `### Localization Improvements` (v3.3.4) is
        // deliberately NOT listed — that one holds real changes, which is why the
        // match is whole-heading rather than a substring.
        ChangelogRecipe(
            bundleID: BetterDisplayChannel.bundleID,
            source: URL(
                string:
                    "https://api.github.com/repos/waydabber/BetterDisplay/releases?per_page=40")!,
            mode: .json,
            maxEntries: 15,
            channel: .stable,
            structuredFormat: .gitHubReleases,
            skipSections: betterDisplayContributorRosters),

        ChangelogRecipe(
            bundleID: BetterDisplayChannel.bundleID,
            source: URL(
                string:
                    "https://api.github.com/repos/waydabber/BetterDisplay/releases?per_page=40")!,
            mode: .json,
            maxEntries: 15,
            channel: .beta,
            structuredFormat: .gitHubReleases,
            skipSections: betterDisplayContributorRosters),

        ChangelogRecipe(
            bundleID: BetterDisplayChannel.bundleID,
            source: URL(
                string:
                    "https://api.github.com/repos/waydabber/BetterDisplay/releases?per_page=40")!,
            mode: .json,
            maxEntries: 15,
            channel: .unstable,
            structuredFormat: .gitHubReleases,
            skipSections: betterDisplayContributorRosters),

        // Alcove — its own changelog API. Public and unauthenticated, unlike the
        // update endpoint on the same host, which is license-gated (see
        // `AlcoveUpdateSource`). Structured JSON: majors, each holding its point
        // releases with date, note, features and fixes. Newest is 1.7.9, matching
        // the installed copy on 2026-08-22.
        //
        // This replaces a web view on `tryalcove.com/changelog`, whose text lives
        // in hash-named JS chunks — the reason that page was only ever linked, not
        // read. The API is a different surface and a far better one.
        ChangelogRecipe(
            bundleID: "com.henrikruscon.Alcove",
            source: URL(string: "https://api.tryalcove.com/changelog")!,
            mode: .json,
            maxEntries: 30,
            structuredFormat: .alcoveChangelog),

        // Docker Desktop — the release-notes page in its Markdown source form.
        // `docs.docker.com/desktop/release-notes.md` serves `text/markdown`
        // directly (the `.md` twin of the HTML page), 142 versions deep, newest
        // 4.87.0 on 2026-08-17 — the installed version here.
        //
        // The `- [Windows](…)` / `- [Mac …]` / `- [Linux …]` installer links each
        // release opens with are excluded by the item pattern's negative lookahead:
        // they are the same seven download URLs every time and say nothing about
        // what changed. Everything after them — the `### Updates` component list
        // and the `### Bug fixes and enhancements` sections — is kept.
        //
        // `markdownSource` because the notes link out mid-sentence
        // (`[Docker Compose v5.4.0](…)`); without it a plain-text render prints the
        // brackets and the URL.
        ChangelogRecipe(
            bundleID: "com.docker.docker",
            source: URL(string: "https://docs.docker.com/desktop/release-notes.md")!,
            entryPattern:
                #"## (?<version>[0-9]+\.[0-9]+\.[0-9]+)\n\n"#
                + #"<em[^>]*>(?<date>[0-9-]+)</em>"#
                + #"(?<body>[\s\S]*?)(?=\n## |\z)"#,
            itemPatterns: [#"(?:^|\n)- (?!\[(?:Windows|Mac|Linux))(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            maxEntries: 20,
            minItemLength: 6),

        // Kiro — the changelog's RSS feed, filtered to the IDE.
        //
        // The feed mixes three products (`<category>` is IDE, CLI or Web) and the
        // installed app is the IDE, so the entry pattern requires that category
        // rather than filtering afterwards: a CLI release note under an IDE version
        // heading would be worse than no note.
        //
        // Only some titles carry a version ("IDE 1.0.337: Agent Focus, …"); the
        // rest are titled but unversioned ("IDE: Permission Improvements …"). Both
        // shapes are kept — `Changelog.Entry` accepts a title without a version,
        // and dropping the unversioned ones would silently lose 8 of the 15 IDE
        // entries in today's feed. The `IDE` prefix is consumed either way so the
        // rail doesn't repeat it on every row.
        //
        // Notes are prose paragraphs, not lists, so the whole description is one
        // item — this feed has no bullets to find.
        //
        // `pubDate` is RFC-822 and the rail's date formatter only normalizes
        // ISO-8601, so the weekday and the time are dropped in the capture rather
        // than rendered verbatim as "Tue, 18 Aug 2026 20:04:00 GMT" under every
        // version. What's left ("18 Aug 2026") matches the shape Alcove's feed
        // already supplies.
        ChangelogRecipe(
            bundleID: "dev.kiro.desktop",
            source: URL(string: "https://kiro.dev/changelog/feed.rss")!,
            entryPattern:
                #"<item>\s*<title>(?:IDE(?: (?<version>[0-9][0-9.]*))?: )?(?<title>[^<]*)</title>\s*"#
                + #"<link>[^<]*</link>\s*<guid>[^<]*</guid>\s*"#
                + #"<pubDate>[A-Za-z]{3}, (?<date>[0-9]{2} [A-Za-z]{3} [0-9]{4})[^<]*</pubDate>\s*"#
                + #"<category>IDE</category>\s*"#
                + #"<description><!\[CDATA\[(?<body>[\s\S]*?)\]\]></description>"#,
            itemPatterns: [#"(?<item>[\s\S]+)"#],
            maxEntries: 20,
            minItemLength: 10),

        // Notion's OTHER changelog, deliberately not registered: www.notion.com/
        // releases is the *product* announcement feed (feature launches like "Plan
        // Mode"), server-rendered and scrapeable, but carrying no build number at
        // all — the old recipe used each post's title as the `version`, which never
        // matched the build on the row. That mismatch is what the recipe above
        // fixes, so the two must not both claim to be this app's release notes.
        //
        // The scrape pattern is not kept here as commented-out code; it is in git
        // (3603c3c^ and earlier), and `notionProductAnnouncementsRecipe()` in the
        // tests still builds it, so its regression coverage survives. If those
        // product announcements are ever wanted, they should come back as a
        // separate, clearly-labelled source — not as a second recipe for this id.

        // Obsidian — obsidian.md/changelog is one server-rendered page listing
        // every release newest-first, with BOTH Mobile and Desktop posts. Each
        // block is a sticky header anchor + a notes column. We key on the header
        // anchor's `-desktop-v` slug, which (a) drops the interleaved Mobile posts
        // and (b) yields the version directly from the href — more reliable than
        // the visible <span class="text-sm"> label, which for some releases prints
        // a truncated "1.12" while the slug stays full ("…-desktop-v1.12.4"). The
        // date link must be anchored on its `class="font-semibold…"` — a bare href
        // match also hits in-body links like "<a …>Obsidian Desktop v1.12.7</a>"
        // and would steal the date. The typeset body closes with three nested
        // </div> (notes col → basis-3/4 → flex row); the lookahead stops there so
        // it can't bleed into the next entry. Only <li> become items.
        ChangelogRecipe(
            bundleID: "md.obsidian",
            source: URL(string: "https://obsidian.md/changelog/")!,
            entryPattern:
                #"<a href="/changelog/[^"]*-desktop-v(?<version>[\d.]+)/?"\s+class="font-semibold[^"]*"[^>]*>\s*(?<date>[^<]+?)\s*</a>"#
                + #".*?<div class="typeset break-words"[^>]*>(?<body>.*?)</div>\s*</div>\s*</div>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 20),

        // Figma (desktop) — read the vendor's own Atom feed rather than the HTML
        // page: `https://www.figma.com/release-notes/feed/atom.xml`. The `Content-Type`
        // header on that response reads `application/rss+xml`, but the body is a
        // standard Atom document (`<feed xmlns="http://www.w3.org/2005/Atom">`) —
        // don't trust the header, trust the markup. Switched away from the page
        // (which the entryPattern below used to scrape) because the page's markup is
        // a client-hydrated shell with CSS classes hashed per deploy — the same
        // fragility class as every other "scrape the rendered page" recipe in this
        // file — while the feed's element names (`entry`/`title`/`updated`/`content`)
        // are a published, stable contract. It also fixes a real bug in the old
        // recipe: the page lazy-loads posts as you scroll, so the live DOM only ever
        // had ~8 `<article>` blocks to match against however large `maxEntries` was
        // set — the feed carries hundreds, so the existing `maxEntries: 20` cap now
        // actually engages.
        //
        // Each entry (captured verbatim 2026-08-19):
        //   <entry>
        //       <title type="html"><![CDATA[Recommend resources you want users to discover and use]]></title>
        //       <id>dece0d00-5f03-4a5d-aa04-3b0fad21b5eb</id>
        //       <link href="https://www.figma.com/release-notes/?title=…"/>
        //       <updated>2026-08-17T00:00:00.000Z</updated>
        //       <content type="html"><![CDATA[Admins can now choose which resources…]]></content>
        //   </entry>
        // This is still Figma's *product* release-notes feed (Figma Design / Make /
        // FigJam announcements), NOT desktop-app build notes — there is no per-entry
        // app version. The desktop build version lives only at
        // desktop.figma.com/mac/RELEASE.json with no human notes, so this remains the
        // best changelog surface, and the post title still fills `version` / the post
        // date still fills `date` — same mapping as the old page recipe, just read
        // from a sturdier document.
        //
        // Both `title` and `content` are `<![CDATA[…]]>`-wrapped. A naive `<[^>]*>`
        // tag-stripper applied BEFORE the CDATA payload is pulled out will eat the
        // whole `<![CDATA[…]]>` construct, because `[^>]*` happily reads through to
        // the `>` that closes `]]>` — so the capture groups below land strictly
        // *inside* the CDATA delimiters (`<!\[CDATA\[(?<…>.*?)\]\]>`), and the
        // generic stripTags/decodeEntities cleanup only ever runs on text already
        // isolated that way. Checked against the live feed (444 entries, 2026-08-19):
        // no entry's title or content carries embedded HTML tags today, so that
        // cleanup is currently a no-op — but the ordering is still correct for the
        // day one does.
        //
        // `date` truncates the ISO timestamp to just its date portion (`[^T]+` before
        // the literal `T`) — the same convention already used for the GitHub-releases
        // recipes (Ollama, RustDesk) reading `<relative-time datetime="…">`, and the
        // prevailing `YYYY-MM-DD` shape most recipes in this file use.
        //
        // Trade-off (accepted, not a regression): `content` is a one-sentence
        // summary, not the fuller multi-paragraph prose the HTML page rendered for
        // its top posts. Verified against the same 8 posts on 2026-08-19: combined
        // item text drops from 3390 to 1062 characters (31%) versus the old
        // `<article>`/`<p>` scrape, while every title and date matches byte-for-byte.
        // Chosen deliberately for stability over completeness.
        ChangelogRecipe(
            bundleID: "com.figma.Desktop",
            source: URL(string: "https://www.figma.com/release-notes/feed/atom.xml")!,
            entryPattern:
                #"<entry>\s*"#
                + #"<title type="html"><!\[CDATA\[(?<version>.*?)\]\]></title>\s*"#
                + #"<id>[^<]*</id>\s*"#
                + #"<link[^>]*/>\s*"#
                + #"<updated>(?<date>[^T]+)T[^<]*</updated>\s*"#
                + #"(?<body><content type="html"><!\[CDATA\[.*?\]\]></content>)"#,
            itemPatterns: [#"<content type="html"><!\[CDATA\[(?<item>.*?)\]\]></content>"#],
            maxEntries: 20),

        // 1Password 8 (Mac) — the STABLE channel's RSS feed, `…/mac/stable/index.xml`,
        // not the HTML page next to it (the bare /mac/ landing page is only a
        // two-card hub with no change items; the beta channel has its own
        // /mac/beta/ feed). Both carry the same releases; the feed is the sturdier
        // read — it is a published interface with fixed element names, where the
        // page's `c-updates__release` / `c-updates__title` class names are styling
        // that a site redesign renames without anyone calling it a breaking change.
        //
        // Each item (captured verbatim 2026-08-16):
        //   <item><title>1Password for Mac 8.12.33</title><link>…</link>
        //   <pubDate>Wed, 12 Aug 2026 00:00:00 +0000</pubDate><guid>…</guid>
        //   <description>&lt;ul&gt;&lt;li&gt;We&amp;rsquo;ve fixed …&lt;/li&gt;&lt;/ul&gt;</description></item>
        //
        // Two consequences of it being a feed rather than a page:
        //   * items are ASCENDING (8.7.0 from 2022 first, 89 of them), so
        //     `newestLast` flips them — the HTML page was newest-first;
        //   * the change list lives ENTITY-ESCAPED inside <description>, so the
        //     item pattern matches `&lt;li&gt;`, not `<li>`. Matching a raw `<li>`
        //     here finds nothing at all.
        // Items keep the vendor's inline issue refs ([[!40819]]) as written.
        ChangelogRecipe(
            bundleID: "com.1password.1password",
            source: URL(string: "https://releases.1password.com/mac/stable/index.xml")!,
            entryPattern:
                #"<item>\s*<title>1Password for Mac\s*(?<version>[0-9][0-9.]*)</title>.*?"#
                + #"<pubDate>(?<date>[^<]+)</pubDate>.*?"#
                + #"<description>(?<body>.*?)</description>\s*</item>"#,
            itemPatterns: [#"&lt;li&gt;(?<item>.*?)&lt;/li&gt;"#],
            escapedMarkup: true,
            newestLast: true),

        // Sublime Text 4 — the /download page is fully server-rendered and carries
        // the <h2>Changelog</h2> inline (no hydration). Each release is an <article>
        // (the newest is <article class="current">) shaped as:
        //   <h3>Build 4200</h3><div class="release-date">21 May 2025</div>
        //   <h3>New Features and Improvements</h3>     ← section sub-headings, ignored
        //   <ul class="topic"><li>…</li>…</ul>          ← one or more lists per build
        // Versions are 4-digit BUILD numbers. The version h3 is usually "Build 4200",
        // but the original v4 release reads "4 (Build 4107)", so the h3 capture
        // tolerates a leading "<digit> (Build " and trailing ")" and grabs only the
        // 4xxx digits. `body` runs to the next </article>, spanning every section's
        // <li> in a build; the sub-heading <h3>s between are harmless because
        // itemPatterns only consume <li>. The page mixes stable + dev builds
        // newest-first; we take whatever it presents.
        ChangelogRecipe(
            bundleID: "com.sublimetext.4",
            source: URL(string: "https://www.sublimetext.com/download")!,
            entryPattern:
                #"<article[^>]*>\s*"#
                + #"<h3>(?:[^<]*?\(Build\s+)?(?:Build\s+)?(?<version>4\d{3})\)?</h3>\s*"#
                + #"<div class="release-date">(?<date>[^<]*)</div>"#
                + #"(?<body>.*?)</article>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

        // Calibre — calibre-ebook.com/whats-new is one server-rendered page listing
        // every release newest-first (no hydration). Each release is a
        //   <h2 class="release-title">Release: 9.9 [28 May, 2026]</h2>
        //   <h3 class="category">New features</h3><ul class="entries">
        //     <li class="minor"><span class="title">…text…</span>…</li> …
        // Version and date are both in the <h2> title ("Release: <ver> [<date>]").
        // The body spans the whole release (several category sections), bounded by
        // the next release <h2> or the panes-closing triple </div>. itemPatterns
        // target ONLY <span class="title"> — the real changelog (New features + Bug
        // fixes); the bare <li> "news sources" lists carry no span and are dropped
        // as noise. Item text can contain entities (Preferences-&gt;Searching).
        ChangelogRecipe(
            bundleID: "net.kovidgoyal.calibre",
            source: URL(string: "https://calibre-ebook.com/whats-new")!,
            entryPattern:
                #"<h2 class="release-title">Release:\s*(?<version>[\d.]+)\s*\[(?<date>[^\]]*)\]</h2>"#
                + #"(?<body>.*?)(?=<h2 class="release-title">|</div>\s*</div>\s*</div>)"#,
            itemPatterns: [#"<span class="title">(?<item>.*?)</span>"#]),

        // Audacity — GitHub releases page (same shape as Ollama/RustDesk). Each
        // release is a <section aria-labelledby="hd-…"> with an sr-only <h2> (e.g.
        // "Audacity 3.7.7"), a <relative-time datetime="…"> (ISO date), and a
        // <div class="markdown-body …"> body. The h2 carries an "Audacity " prefix,
        // so the version group anchors on that literal + a \d.\d.\d triple — which
        // also skips interleaved "Audacity-4.0.0.alpha-2" pre-release rows (hyphen,
        // not space). NOTE: Audacity is detected via Homebrew cask, not GitHub —
        // this recipe supplies NOTES only; a parse miss falls back to the page.
        ChangelogRecipe(
            bundleID: "org.audacityteam.audacity",
            source: URL(string: "https://github.com/audacity/audacity/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>Audacity (?<version>\d+\.\d+\.\d+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),

        // Blender — developer.blender.org/docs/release_notes/<major.minor>/ is the
        // clean per-version notes page (the blender.org/download marketing pages are
        // sprawling splash pages with no parseable block). Each page is an <h1>
        // "Blender 5.1 Release Notes", a <p>"Blender 5.1 was released on DATE."</p>,
        // then module-section <ul>s and Compatibility/Bugfixes lists up to the
        // "Corrective Releases" heading. We surface a COARSE summary (changed-module
        // list + compat/bugfix bullets). Requiring the literal "was released on" is a
        // GUARD: the dev-docs nav lists in-development versions first (5.3 Alpha,
        // 5.2 Beta) whose intros read "is currently in Alpha/Beta" and so DON'T
        // match — yielding zero entries (safe embed fallback) rather than a partial
        // changelog. URL is version-pinned to the latest RELEASED minor; bump it when
        // a new Blender ships (same as the old Warp/Ghostty version-pins) — Blender
        // exposes no released-only index to follow.
        ChangelogRecipe(
            bundleID: "org.blenderfoundation.blender",
            source: URL(string: "https://developer.blender.org/docs/release_notes/5.1/")!,
            entryPattern:
                #"<h1[^>]*>Blender\s+(?<version>\d+\.\d+(?:\.\d+)?)\s+Release Notes.*?</h1>\s*"#
                + #"<p>Blender\s+[\d.]+\s+was released on\s+(?<date>[^.<]+)\.</p>"#
                + #"(?<body>.*?)"#
                + #"(?=<h2[^>]*id="corrective-releases")"#,
            itemPatterns: [#"<li>\s*(?<item>.*?)\s*</li>"#],
            maxEntries: 1),

        // Google Chrome — Chrome has no single consumer changelog page; the
        // canonical "what changed" surface is the Chrome Releases blog (Blogger).
        // We fetch the *Stable updates* label page, which is server-rendered and
        // carries each post's full body inline inside a
        // `<script type='text/template'>` block (Blogger hydrates it client-side,
        // but the raw markup is complete). The label page mixes platforms
        // (Android / iOS / ChromeOS / Desktop), so the entryPattern requires the
        // exact post title `Stable Channel Update for Desktop` — that one literal
        // both selects the desktop posts AND excludes the Beta/Dev/Early/Extended
        // channels (whose titles differ: "Chrome Beta for Desktop Update",
        // "Early Stable Update for Desktop", etc.). Structure per post:
        //   <a ... title='Stable Channel Update for Desktop'>…</a>
        //   <span class='publishdate' itemprop='datePublished'>Wednesday, May 27, 2026</span>
        //   <script type='text/template'>…post HTML…</script>
        // No version lives in the title or URL, so `version` is the first 4-part
        // build number in the body prose (e.g. 148.0.7778.216) — display-only and
        // low-stakes, so grabbing the first listed build is fine even though a post
        // lists Windows/Mac/Linux variants.
        //
        // Two item shapes, tried in order:
        //   1. CVE — security updates list each fix as inline spans (NOT <li>):
        //      "[$reward][issue] Severity CVE-2026-9872: Out of bounds write in GPU."
        //      The CVE id + description sit together in one span's text, so anchor on
        //      the `CVE-YYYY-N:` literal and capture to the next tag.
        //   2. lead — promotion posts (no CVEs yet, "Security update coming shortly")
        //      have only prose; capture the announcement sentence ("…promotion of
        //      Chrome N to the stable channel" / "…has been updated to …"), using a
        //      tempered dot so it can't span past its own </p> into the boilerplate
        //      ("Interested in switching release channels?…") or the signature.
        // Security posts match CVE first (≥1 item) so the lead pattern never fires on
        // them; promotion posts fall through to lead. A parse miss just embeds the page.
        ChangelogRecipe(
            bundleID: "com.google.Chrome",
            source: URL(string: "https://chromereleases.googleblog.com/search/label/Stable%20updates")!,
            // Every gap here is written so that a FAILING match costs one pass, not
            // a combinatorial search. This pattern used to be four unbounded lazy
            // gaps (`.*?`) in a row, which is fine while the page still matches and
            // ruinous the day it stops — and a vendor restyle is exactly "it stops".
            // Measured against the live 852 KB page (6 posts) with the old form:
            // renaming the closing `</script>` ran past 150 s, and a page whose
            // 4-part build numbers went away took 20.6 s, both on a thread the
            // caller is awaiting. Every gap below is now either
            //
            //   • an atomic group `(?>…)` around a gap AND the literal that ends it,
            //     so once the first publishdate (then the first template opener)
            //     after the title is found, a later failure cannot send the engine
            //     back to look for another one; or
            //   • a lookahead, which is atomic in ICU: the version is located once,
            //     and a failure downstream cannot retry against the next
            //     version-shaped number in the body.
            //
            // Same seven mutations, new form: worst case 0.074 s, and the pristine
            // page still yields the identical two entries. `ChromeChangelogPatternTests`
            // pins that with a generated page (the real one is too big to commit).
            //
            // What NOT to reach for here: `(?:…)*+` and `(?>(?:…)*)` over the BODY.
            // A possessive/atomic run silently stops matching past ~250 000
            // characters — measured: 100 000 matches, 250 000 does not, and the
            // failure is a quiet "no match", not an error. Chrome's second post is
            // a 324 KB body, so that form drops it and the pane loses an entry with
            // nothing anywhere saying so. The gaps below are atomic only across
            // spans of a few hundred characters, well under that limit.
            entryPattern:
                #"title='Stable Channel Update for Desktop'>"#
                + #"(?>(?:(?!<span class='publishdate').)*?"#
                + #"<span class='publishdate'[^>]*>\s*(?<date>[^<]+?)\s*</span>)"#
                + #"(?>(?:(?!<script type='text/template'>).)*?"#
                + #"<script type='text/template'>\s*)"#
                + #"(?=(?:(?!</script>).)*?(?<version>\d+\.\d+\.\d+\.\d+))"#
                + #"(?<body>(?:(?!</script>).)*?)</script>"#,
            itemPatterns: [
                #"(?<item>CVE-\d{4}-\d+:[^<]*)"#,
                #"<p[^>]*>(?<item>(?:(?!</p>).)*?(?:promotion of Chrome|been updated to)(?:(?!</p>).)*?)</p>"#,
            ],
            minItemLength: 8),

        // TablePro — deliberately NO recipe. The app ships a Sparkle feed
        // (`SUFeedURL` = raw.githubusercontent.com/TableProApp/TablePro/main/
        // appcast.xml) whose every `<item>` carries the full release notes inline
        // in `<description>` (21 KB of `<h3>` + `<ul><li>` for 0.67.0, 137 items
        // deep), so `SparkleAppcastSource` already hands the pane a changelog we
        // fetched for the version check anyway — a recipe here would only preempt
        // it (recipe beats `structuredChangelog`/`releaseNotesHTML` in the
        // workbench) and cost a second request.
        //
        // The recipe this replaces scraped docs.tablepro.app and broke TWICE on
        // pure vendor churn: once when Mintlify swapped the label element to a
        // `<button>` (2026-08-09, fixed by moving to the `.md` twin), then again
        // when TablePro flipped the `<Update>` attributes to `label="v0.67.0"
        // description="August 21, 2026"` — the reverse of what the `.md` pattern
        // required, and now the same order Claude's Mintlify page uses. Two breaks
        // in two weeks on a source we did not need is why this is gone rather than
        // re-patched.

        // MacUpdater — corecode.io/macupdater/history3.html is a single static
        // page of every release newest-first (no hydration). 3.5.0 is the final
        // release (the product is discontinued), so the page is effectively
        // frozen. Each version block is:
        //   <p><b>3.5.0</b> (Jan 2026):</p>
        //   <p>• item…</p>
        //   <p>• item…</p>
        // Version and date are in the <p><b>…</b> (…)</p> header; each change is a
        // bullet <p>• …</p> until the next version header. The bullet is a literal
        // U+2022, so the item pattern anchors on it to skip non-bullet paragraphs.
        ChangelogRecipe(
            bundleID: "com.corecode.MacUpdater",
            source: URL(string: "https://www.corecode.io/macupdater/history3.html")!,
            entryPattern:
                #"<p><b>(?<version>[0-9][0-9.]*)</b>\s*\((?<date>[^)]*)\):</p>"#
                + #"(?<body>.*?)"#
                + #"(?=<p><b>[0-9][0-9.]*</b>\s*\(|$)"#,
            itemPatterns: [#"<p>\s*•\s*(?<item>.*?)</p>"#],
            maxEntries: 20),

        // IntelliJ IDEA — same JetBrains data-services API as Toolbox (`IIU`
        // product code, stable releases only via `type=release`). Structured decode
        // (`StructuredChangelogDecoder.decodeJetBrainsProductReleases`): the old
        // regex path read `whatsnew` as raw JSON-escaped text, where an embedded
        // `\n` is a two-character escape a hand-written item pattern can silently
        // mis-anchor on (the ChatWise-class bug this decoder family exists to avoid).
        // `Decodable` unescapes the JSON string for us, so the decoder walks real
        // HTML instead: `whatsnew` is a lead `<p>` summary then `<ul><li>` bullets,
        // and only the `<li>` bullets count as discrete changes — the lead `<p>`
        // is boilerplate ("IntelliJ IDEA X is out with…"). A hotfix release with no
        // `<li>` at all (its content is plain `<p>` prose, or just a pointer to the
        // release notes) yields zero items and is skipped, same as the regex did.
        ChangelogRecipe(
            bundleID: "com.jetbrains.intellij",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&type=release")!,
            maxEntries: 20,
            structuredFormat: .jetBrainsProductReleases),

        // JetBrains Toolbox App — JetBrains publishes no public changelog page
        // (long-requested: YouTrack TBX-2807), but the official product-releases
        // API the download site itself uses returns the full history as JSON. The
        // `TBA` product code is the Toolbox App; each element of the TBA array has
        // `version` ("3.7.2"), `date`, and a `whatsnew` HTML string. Structured
        // decode, same reason and same decoder as IntelliJ IDEA above (shared
        // endpoint shape, JSON-escaped HTML the regex path used to scrape as text).
        // Toolbox's `whatsnew` is CUMULATIVE — each release concatenates its own
        // `<li>` bullets with the full prior minor release's `<h3>`/`<h4>` + `<p>`
        // write-up — so the decoder sweeps BOTH `<li>` and `<p>` (the decoder
        // branches on the response's own top-level key, "TBA" vs "IIU") and drops
        // only the trailing "See the full list of release notes…" `<p>` footer.
        ChangelogRecipe(
            bundleID: "com.jetbrains.toolbox",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=TBA")!,
            maxEntries: 20,
            structuredFormat: .jetBrainsProductReleases),

        // OpenCode (desktop) — github.com/anomalyco/opencode/releases (the repo
        // moved from sst/opencode via GitHub's org-rename redirect; we pin the
        // canonical anomalyco path). Same GitHub-releases shape as Ollama/RustDesk:
        // each release is a <section aria-labelledby="hd-…"> with an sr-only <h2>
        // carrying the version ("v1.15.13"), a <relative-time datetime="…"> (ISO
        // date), and a <div class="markdown-body …"> body. The leading "v" is
        // dropped. The desktop app and CLI share one version line, so the releases
        // versions match the installed app build.
        ChangelogRecipe(
            bundleID: "ai.opencode.desktop",
            source: URL(string: "https://github.com/anomalyco/opencode/releases")!,
            entryPattern:
                #"<section[^>]*aria-labelledby="hd-[^"]*"[^>]*>\s*"#
                + #"<h2 class="sr-only"[^>]*>v(?<version>[\d.]+)</h2>.*?"#
                + #"<relative-time[^>]*datetime="(?<date>[^T]+)T[^"]*"[^>]*>.*?"#
                + #"<div[^>]*class="markdown-body[^"]*"[^>]*>(?<body>.*?)</div>\s*</div>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#]),

        // ── Thunderbird (Mozilla) — one product, four channels, but only THREE
        // bundle ids: Stable and ESR BOTH ship as `org.mozilla.thunderbird`
        // (the install short-version drops the `esr` suffix, and the channel is
        // only knowable from `application.ini` RemotingName — see ReleaseChannel /
        // AppScanner). So Stable and ESR are distinguished here by the recipe
        // `channel` field; `recipe(forBundleID:channel:)` is given the install's
        // detected channel and picks the matching train. Nightly/Daily
        // (`org.mozilla.thunderbird-daily`) publishes NO structured release-notes
        // page (every /<ver>/releasenotes/ 404s — auto-builds have no curated
        // notes), so it has no recipe and keeps the web-view fallback.
        //
        // Every channel's per-version notes page shares one structure:
        //   <h4>Version 151.0 | Released May 19, 2026</h4>
        //   <h3 class="header-section">What’s New</h3>          ← section labels (ignored)
        //   <div id="note-0" class="note-container"><div class="note-flex">
        //     <h4 class="note-category">…new/changed/fixed…</h4>
        //     <div class="note-text"><p>change text…</p></div></div></div>
        // Each page is ONE version, so maxEntries:1; body runs to end of doc and
        // the item patterns only ever match `note-text`, so the footer is ignored.

        // Thunderbird Stable — version-templated. Each release has its own page
        // (`/<version>/releasenotes/`) and there is no inline multi-version page or
        // "latest" alias, so we substitute the app's target version into
        // `sourceTemplate` and fetch exactly that build's page — the rendered
        // version then always matches what the user has/​is offered (151.0.1, not
        // the 151.0 major), with no pin to bump. `source` is the releases index,
        // used only as a fallback if no version is ever supplied. Each page is one
        // version → maxEntries:1.
        ChangelogRecipe(
            bundleID: "org.mozilla.thunderbird",
            source: URL(string: "https://www.thunderbird.net/en-US/thunderbird/releases/")!,
            entryPattern:
                #"<h[1-6][^>]*>\s*Version\s+(?<version>[^<|]+?)\s*\|\s*Released\s+(?<date>[^<]+?)\s*</h[1-6]>"#
                + #"(?<body>.*)"#,
            itemPatterns: [
                #"<div class="note-text">\s*<p>(?<item>.*?)</p>"#,
                #"<div class="note-text">\s*(?<item>.*?)\s*</div>"#,
            ],
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://www.thunderbird.net/en-US/thunderbird/{version}/releasenotes/"),

        // Thunderbird ESR — SAME bundle id as Stable, matched by `channel: .esr`,
        // same per-version template. The install's short version is stripped of the
        // `esr` suffix (140.11.1), but the notes page is `/140.11.1esr/…`, so
        // `resolvedSource` re-appends `esr` for this channel (see
        // `urlVersionToken`). This keeps ESR's shown version consistent with the
        // install on both the steady state (installed == latest) and when an ESR
        // security update is offered.
        ChangelogRecipe(
            bundleID: "org.mozilla.thunderbird",
            source: URL(string: "https://www.thunderbird.net/en-US/thunderbird/140.0/releasenotes/")!,
            entryPattern:
                #"<h[1-6][^>]*>\s*Version\s+(?<version>[^<|]+?)\s*\|\s*Released\s+(?<date>[^<]+?)\s*</h[1-6]>"#
                + #"(?<body>.*)"#,
            itemPatterns: [
                #"<div class="note-text">\s*<p>(?<item>.*?)</p>"#,
                #"<div class="note-text">\s*(?<item>.*?)\s*</div>"#,
            ],
            maxEntries: 1,
            channel: .esr,
            sourceTemplate: "https://www.thunderbird.net/en-US/thunderbird/{version}/releasenotes/"),

        // Thunderbird Beta — its own bundle id (`org.mozilla.thunderbirdbeta`),
        // version-templated like the others. The notes URL is keyed by MAJOR, not
        // build: `/152.0beta/releasenotes/` is one cumulative page for the whole
        // 152 beta cycle (b1→b2→…, several "What’s Fixed" sections under one
        // "152.0beta" heading, ~41 items). `urlVersionToken` drops the bN build
        // suffix and appends "beta" (152.0 / 152.0b3 → 152.0beta), so the template
        // auto-tracks the current cycle with no pin to bump. `source` is the
        // current cycle page as a fallback only.
        ChangelogRecipe(
            bundleID: "org.mozilla.thunderbirdbeta",
            source: URL(string: "https://www.thunderbird.net/en-US/thunderbird/152.0beta/releasenotes/")!,
            entryPattern:
                #"<h[1-6][^>]*>\s*Version\s+(?<version>[^<|]+?)\s*\|\s*Released\s+(?<date>[^<]+?)\s*</h[1-6]>"#
                + #"(?<body>.*)"#,
            itemPatterns: [
                #"<div class="note-text">\s*<p>(?<item>.*?)</p>"#,
                #"<div class="note-text">\s*(?<item>.*?)\s*</div>"#,
            ],
            maxEntries: 1,
            channel: .beta,
            sourceTemplate: "https://www.thunderbird.net/en-US/thunderbird/{version}/releasenotes/"),

        // ── GitHub Desktop — one bundle id (`com.github.GitHubClient`), TWO channels
        // distinguished only by the install's `-betaN` version suffix (see
        // ReleaseChannel.detect / the GitHubReleaseRule pair). The desktop.github.com
        // /release-notes page is a client-rendered SPA; its data is a JSONP-ish feed
        // at central.github.com/deployments/desktop/desktop/changelog.json, and the
        // page's `?env=beta` maps to a `?env=beta` query on that feed (read from
        // desktop-releases.js). Fetched without the `callback` param it returns a
        // plain JSON array, newest-first, each element:
        //   {"name":"","notes":["[Fixed] …- #22219", …],
        //    "pub_date":"2026-06-01T17:43:05Z","version":"3.5.12"}
        // `notes` is already an array of one-line strings (each keeping the vendor's
        // own `[Fixed]`/`[Added]`/`[Improved]` prefix and trailing `- #issue`) — this
        // feed was structured JSON all along, so it's decoded by
        // `StructuredChangelogDecoder.decodeGitHubDesktop` rather than regex-scraped;
        // see `.gitHubDesktopChangelog` for the shape. Stable feed carries bare
        // `3.5.12`; beta carries `3.5.12-beta2`. A parse miss just falls back to
        // embedding the SPA. `channel` here is only for the recipe-registry lookup
        // (`ChangelogRecipeRegistry.recipe(forBundleID:channel:)` picks stable vs.
        // beta by it) — the decoder itself takes no channel, since stable and beta
        // are two different URLs, not one document split by a channel key.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json")!,
            channel: .stable,
            structuredFormat: .gitHubDesktopChangelog),

        // GitHub Desktop Beta — same feed with `?env=beta`, matched by `channel:
        // .beta` so a `-betaN`-detected install gets beta notes (`3.5.12-beta2`)
        // instead of the stable train. Identical structured decoder.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json?env=beta")!,
            channel: .beta,
            structuredFormat: .gitHubDesktopChangelog),

        // (No Alcove recipe. It parsed the `body` of update.tryalcove.com, which the
        // vendor retired outright — NXDOMAIN. Its replacement as the public version
        // surface, download.tryalcove.com/latest, carries only version/build/date/
        // assets and no release notes of any kind.
        //
        // www.tryalcove.com/changelog IS a real page (an earlier note here said the
        // site served the same SPA shell on every path; that is no longer true), but
        // it carries the notes in the wrong shape: it server-renders version numbers
        // and dates while leaving each entry's body an empty placeholder, with the
        // actual `features[]`/`fixes[]` arrays inlined in a content-hashed, minified
        // route chunk (`/assets/ChangelogPage-<hash>.js`). Parsing it would mean a
        // two-hop fetch, rediscovering the hash on every run because it changes on
        // every site deploy, and anchoring patterns on minifier output — three
        // fragilities stacked. The VendorProbe's `changelogURL` points at that page
        // instead, so the workbench embeds it in a WebView and renders it correctly.
        //
        // Licensed users get full structured notes from `AlcoveUpdateSource`, which
        // reads the `sections` array on the authenticated api.tryalcove.com endpoint.
        // Re-add a recipe here only if Alcove publishes notes in a parseable form.)

        // Opera — one page per MAJOR version, listing every build in it newest
        // first: `blogs.opera.com/desktop/changelog-for-134/`. Each entry is
        //   <h4><strong> 134.0.5954.56 &#8211; 2026-08-12 <a …>blog post</a></strong></h4>
        //   <ul><li>CHR-9416 Updating Chromium…</li>…</ul>
        // (captured verbatim 2026-08-16). The separator is an HTML-entity en dash,
        // not a hyphen, and the trailing "blog post" link sits INSIDE the
        // `<strong>` — both are why the pattern stops at the date instead of
        // matching to `</strong>`.
        //
        // `{major}`, not `{version}`: the page covers a whole major line, and
        // Opera ships a new major every few weeks, so a fixed URL would quietly
        // stop covering the installed build. `source` is the current page, used
        // only if no version is ever supplied.
        //
        // The page also carries developer/beta builds of the same major (the
        // `…5960.0` shapes). That is fine and deliberate: entries are listed
        // newest-first and the workbench shows the ones at the top; pinning to a
        // single build would need a per-build page, which Opera doesn't publish.
        // Inkscape — the project's own wiki carries one release-notes page per
        // version: `wiki.inkscape.org/wiki/Release_notes/1.4.4`. inkscape.org's
        // release page has no notes at all (it is a download page), and the news
        // feed mixes releases with everything else, so the wiki is the only
        // per-version source. Version-templated for the same reason as
        // Thunderbird: each page is exactly one release, so `maxEntries: 1`.
        //
        // The item pattern matches a BARE `<li>` on purpose. MediaWiki's table of
        // contents is a nested list whose items all carry
        // `class="toclevel-N tocsection-N"`, and the page footer's are
        // `<li id="footer-info-…">` — allowing attributes would turn the whole
        // navigation into "changes" (35 TOC entries against 116 real ones on the
        // 1.4.4 page, captured 2026-08-16).
        ChangelogRecipe(
            bundleID: "org.inkscape.Inkscape",
            source: URL(string: "https://wiki.inkscape.org/wiki/Release_notes/1.4")!,
            entryPattern:
                #"<h1 id="firstHeading"[^>]*>Release notes/(?<version>[0-9]+(?:\.[0-9]+)*)</h1>"#
                + #".*?<h2[^>]*>\s*<span[^>]*id="Changes_and_Bug_Fixes""#
                + #"(?<body>.*?)<h2[^>]*>\s*<span[^>]*id="Other_releases""#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://wiki.inkscape.org/wiki/Release_notes/{version}"),

        ChangelogRecipe(
            bundleID: "com.operasoftware.Opera",
            source: URL(string: "https://blogs.opera.com/desktop/changelog-for-134/")!,
            entryPattern:
                #"<h4[^>]*>\s*<strong>\s*(?<version>[0-9]+(?:\.[0-9]+)+)\s*(?:&#8211;|–|-)\s*"#
                + #"(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})[^<]*(?:<a[^>]*>[^<]*</a>)?\s*</strong>\s*</h4>"#
                + #"\s*(?<body><ul>.*?</ul>)"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            channel: .stable,
            sourceTemplate: "https://blogs.opera.com/desktop/changelog-for-{major}/"),

        // Longbridge Desktop — use the English per-version page rather than the
        // compact latest.json notes: the page carries the richer release body and
        // some releases interleave screenshots with their change lines. Stop at
        // Downloads so installer links never become changelog items.
        //
        // `<video>` terminates an item because it is the one element whose INNER
        // text would otherwise survive `stripTags` and land in the notes as
        // "Your browser does not support the video tag."; the native changelog
        // model has no video block, so the element itself is dropped.
        // `<img>` deliberately does NOT terminate an item. It is a void tag with
        // no text, `stripTags` removes it regardless, and `imagePattern` collects
        // images from the whole body independently of item boundaries — so the
        // boundary added nothing and could only truncate. With it, a bullet whose
        // illustration came FIRST captured an empty item, lost it to
        // `minItemLength`, and resumed scanning past its own text: the entire line
        // disappeared. Longbridge puts media last on every page today, so this was
        // latent, not live — the regression test pins the other ordering.
        // The path serves English with no locale prefix and does NOT content-
        // negotiate (verified under `Accept-Language: zh-CN` and `zh-HK`), so the
        // literal `Release Date:` anchor is stable for every user.
        //
        // `source` is the releases INDEX, used only when no version is supplied.
        // It must not be a per-version page: that page parses perfectly, so the
        // no-version fallback would render one pinned release's notes as if they
        // described whatever build the user actually has. The index carries no
        // `Release Date:` block, so it correctly yields nothing and the UI falls
        // back to the embedded web page — which is the same assumption
        // `Verify.sweepChangelog` relies on when it skips version-templated
        // recipes that have no version to resolve.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop",
            source: URL(string: "https://longbridge.com/desktop/release-notes/")!,
            entryPattern:
                #"<div[^>]*class="vp-doc[^"]*"[^>]*>\s*<div>\s*<h1[^>]*>\s*v?(?<version>[0-9]+(?:\.[0-9]+)+).*?</h1>\s*<p>\s*<em>\s*Release Date:\s*(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\s*</em>\s*</p>(?<body>.*?)(?=<h2[^>]*id="downloads")"#,
            itemPatterns: [
                #"<(?:li|p)\b[^>]*>(?<item>.*?)(?=<video\b|</(?:li|p)>)"#,
            ],
            maxEntries: 1,
            channel: .stable,
            sourceTemplate: "https://longbridge.com/desktop/release-notes/v{version}",
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#),

        // Longbridge Desktop Preview — separate bundle id, separate URL subtree
        // (`/release-notes/preview/v<version>`), same page structure as stable.
        //
        // The version group REQUIRES the `-preview.N` suffix. Reusing stable's
        // group here would be a silent mis-read rather than a miss: on this page
        // it matches and stops at `0.19.0`, dropping the suffix, so the pane would
        // label a preview build with the stable version number it is not. Anchored
        // this way the two patterns are mutually exclusive — verified in both
        // directions against the live pages.
        //
        // `source` is the preview index. The vendor currently renders it EMPTY
        // (see the VendorProbeRecipe comment), which makes it a correct no-version
        // fallback for the same reason stable's index is: it yields nothing and
        // the UI embeds the page instead of inventing an entry.
        ChangelogRecipe(
            bundleID: "com.longbridge.app.desktop.preview",
            source: URL(string: "https://longbridge.com/desktop/release-notes/preview/")!,
            entryPattern:
                #"<div[^>]*class="vp-doc[^"]*"[^>]*>\s*<div>\s*<h1[^>]*>\s*v?(?<version>[0-9]+(?:\.[0-9]+)+-preview\.[0-9]+).*?</h1>\s*<p>\s*<em>\s*Release Date:\s*(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\s*</em>\s*</p>(?<body>.*?)(?=<h2[^>]*id="downloads")"#,
            itemPatterns: [
                #"<(?:li|p)\b[^>]*>(?<item>.*?)(?=<video\b|</(?:li|p)>)"#,
            ],
            maxEntries: 1,
            channel: .preview,
            sourceTemplate: "https://longbridge.com/desktop/release-notes/preview/v{version}",
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#),

        // Raycast v2 — www.raycast.com/changelog, server-rendered (the full notes
        // are in the initial HTML; no hydration step to chase). Since v2 shipped
        // this URL is the **v2** macOS changelog and the v1 archive moved to
        // /changelog/macos — the opposite of what the paths suggest, and the reason
        // this recipe points at the bare /changelog.
        //
        // Both trains keep the one bundle id and the one `.stable` channel, so the
        // pair is separated by a version window instead — and this recipe is the
        // one WITHOUT a window, deliberately. This page carries the whole v2 train:
        // 2.0 at GA and the 0.63–0.71 builds that were the v2 beta before it. Those
        // numbers sit BELOW v1's 1.95–1.104, so v2's range is not one side of a
        // line and cannot be written as `2+` — doing so sent a 0.71 install to the
        // v1 archive, the single page that does not carry its notes. Instead the
        // archive claims exactly `[1, 2)` and everything else falls here.
        //
        // One entry per `<article>`:
        //   <span id="2.0"></span>
        //   <div class="…changelogMeta"><a …>v<!-- -->2.0</a>
        //       <span class="…changelogDate">August 25, 2026</span></div>
        //   <div class="markdown …changelogBody"> <p><img …></p> <p>intro…</p>
        //       <h2>✨ New</h2><ul><li>…</li></ul> <h2>💎 Improvements</h2>… </div>
        //
        // The `id` span is the version anchor rather than the visible pill text,
        // whose "v<!-- -->2.0" carries a comment node between the `v` and the
        // number. Class names are CSS-module-hashed
        // (`ChangelogEntry-module__p4g-ca__changelogBody`) so the patterns anchor
        // on the readable SUFFIX, which survives a rebuild; the hash does not.
        //
        // Versions here are the vendor's own MINOR labels — "2.0", "0.71" — while
        // the app reports a four-segment build (2.0.6.0). That is not a mismatch to
        // fix: Raycast publishes one set of notes per minor train and ships several
        // builds under it (the JSON API confirms this from the other side — its
        // /releases list hands 2.0.6.0, 2.0.5.0, 2.0.4.0 and 2.0.3.0 byte-identical
        // changelog text). The 0.6x–0.71 entries are the v2 BETA train, which is
        // what preceded the 2.0 GA number.
        //
        // The single itemPattern deliberately matches `h2` and `li` together rather
        // than listing them as fallbacks: itemPatterns are tried in order and the
        // FIRST to yield anything wins, so a bullets-only pattern would silently
        // drop the New/Improvements/Fixes headings that give 30 flat bullets their
        // shape. Folding the section titles in as items is the same thing
        // `decodeAlcoveChangelog` does with its Features/Fixes labels.
        //
        // NOT sourced from the JSON API next door (x.raycast-releases.com/releases)
        // even though it serves clean markdown: that list endpoint ignores its own
        // `platform` parameter (macos and windows return byte-identical bodies,
        // measured 2026-08-27) and answers with the Windows-flavoured copy of a
        // release note whose macOS twin differs. `…/releases/latest?platform=macos`
        // IS platform-correct, but it is one release deep — no history to show.
        ChangelogRecipe(
            bundleID: "com.raycast.macos",
            source: URL(string: "https://www.raycast.com/changelog")!,
            entryPattern:
                #"<span id="(?<version>[0-9][0-9.]*)"></span>.*?"#
                + #"changelogDate">(?<date>[^<]+)</span>.*?"#
                + #"changelogBody">(?<body>.*?)</article>"#,
            itemPatterns: [#"<(?:h2|li)\b[^>]*>(?<item>.*?)</(?:h2|li)>"#],
            maxEntries: 20,
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#),

        // Raycast v1 archive — /changelog/macos, the page titled "Raycast - macOS
        // V1 Changelog". Byte-for-byte the same component as the v2 page above, so
        // the patterns are the same three strings; only `source` and the version
        // window differ. Verified against the live page 2026-08-27: 10 entries,
        // 1.104.0 back to 1.95.0, all parsing.
        //
        // The window is `[1, 2)`, and the LOWER bound is the load-bearing half: a
        // bare `belowAppVersion: "2"` would also swallow the 0.63–0.71 v2 beta
        // builds, whose notes are on the v2 page above, not here.
        //
        // Its newest entry is 1.104.0 (December 16, 2025) while the v1 endpoint is
        // serving 1.104.25 — not a stale page. Raycast publishes one set of notes
        // per MINOR and ships patches under it, and v1 has been on patches alone
        // since v2 development took over; 1.104.x installs belong under the 1.104.0
        // entry. (The same grouping is visible on the v2 side, where 2.0.6.0
        // through 2.0.3.0 share one note.)
        ChangelogRecipe(
            bundleID: "com.raycast.macos",
            source: URL(string: "https://www.raycast.com/changelog/macos")!,
            entryPattern:
                #"<span id="(?<version>[0-9][0-9.]*)"></span>.*?"#
                + #"changelogDate">(?<date>[^<]+)</span>.*?"#
                + #"changelogBody">(?<body>.*?)</article>"#,
            itemPatterns: [#"<(?:h2|li)\b[^>]*>(?<item>.*?)</(?:h2|li)>"#],
            maxEntries: 20,
            imagePattern: #"<img\b[^>]*\bsrc="(?<image>https://[^"]+)"#,
            minimumAppVersion: "1", belowAppVersion: "2"),

        // WorkBuddy — Tencent's two sites, two apps (see the VendorProbe registry
        // and docs/app-audits/com-workbuddy-workbuddy.md). Both docs sites are the
        // same VitePress build, so ONE set of patterns serves both and only
        // `bundleID` and `source` differ. Each recipe is pinned to its OWN site:
        // the trains are independent, and showing an international install the CN
        // notes (or the reverse) would be quietly wrong in a way nothing else here
        // could catch.
        //
        // Markup (server-rendered, so no JS is needed):
        //   <h2 id="_5-3-14-…">5.3.14 版本发布 🚀（2026-08-17） <a class="header-anchor"…></a></h2>
        //   <ul><li>新增 …</li><li>优化 …</li></ul>
        //
        // TRAP: those parentheses are FULLWIDTH（）in the bytes, on both the
        // Chinese and the English page — they render close enough to ASCII that
        // reading the page in a browser tells you nothing. A pattern written with
        // `\(` matches neither site. Both forms are accepted here so the recipe
        // survives the vendor normalising them either way.
        //
        // The heading text between version and date varies by era — "版本发布 🚀",
        // "Lanched 🚀" (the vendor's own typo), or nothing at all on the oldest
        // entries — so the pattern skips anything that is not a tag or a paren
        // rather than trying to enumerate the variants. The date group is optional
        // for the same reason: 19 of the CN page's older entries have no date.
        //
        // `</h2>\s*<ul>` adjacency is deliberate: it is what keeps a heading whose
        // notes are laid out some other way from swallowing the NEXT release's
        // list. It costs the 17 oldest CN entries (4.5.0–4.7.5, which use a
        // different markup), and that is free — `maxEntries` stops at 40 and the
        // newest 58 all parse. Verified against both live pages 2026-08-27: CN 58
        // entries, newest 5.3.14 with 14 items; intl 2 entries, newest 5.2.7.
        //
        // The intl page IS that short: it carries two entries and stops at 5.2.7
        // (2026-07-17) while its own endpoint ships 5.4.2. A future reader finding
        // "only 2 entries" has found the vendor's page, not a broken recipe — the
        // CN page, parsed by the identical pattern, returns 58.
        //
        // That is also why the intl recipe carries `acknowledgedStaleEntry`
        // (issue #88). `duo verify` reads 5.2.7 against a detected 5.4.2, calls it
        // a whole release behind, and files "recipe degraded" — a complaint that
        // can never clear, because there is nothing on our side to fix. Re-checked
        // live 2026-08-28: intl still 2 entries topping out at 5.2.7, CN still
        // parsing, newest 5.3.14 (2026-08-17). The acknowledgement names 5.2.7
        // rather than switching the check off, so the day the pattern slips to an
        // older section — or the vendor finally publishes — the sweep speaks up
        // again.
        ChangelogRecipe(
            bundleID: "com.workbuddy.workbuddy",
            source: URL(string: "https://www.workbuddy.cn/docs/workbuddy/Changelog")!,
            entryPattern: Self.workBuddyEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

        ChangelogRecipe(
            bundleID: "com.workbuddy.workbuddy-ai",
            source: URL(string: "https://www.workbuddy.ai/docs/workbuddy/Changelog")!,
            entryPattern: Self.workBuddyEntryPattern,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            acknowledgedStaleEntry: "5.2.7"),

        // 百度网盘 — the notes ARE published, just not anywhere a person would
        // look: `pan.baidu.com/disk/version` ("版本更新") renders eight empty
        // `<section>`s and fills the Mac版 tab from JS, so the page's own markup
        // carries no release note at all. `changelog.js` shows what it asks for —
        // `/disk/cmsdata?platform=<tab>&page=<n>&num=<n>` — which is the same
        // `/disk/cmsdata` endpoint the version probe reads, on its other calling
        // convention. This recipe reads that endpoint directly; the human page is
        // what `VendorProbeRegistry`'s `changelogURL` points at for the fallback.
        //
        // 145 releases are on offer; `num=40` matches `maxEntries` so the request
        // is 24 KB rather than 58 KB. Newest-first, so no `newestLast`.
        //
        // Entry shape (verbatim, compact — the vendor emits no spaces):
        //   {"detail":[{"more":["【团队空间】…"],"stable":true,"title":"百度网盘全新升级"}],
        //    "publish":"2026-08-28 14:39:00","size":"444.2M","system":"Mac OS X 10.13+",
        //    "title":"百度网盘Mac电脑客户端V8.7.9","url":"…_x64.dmg","url_1":"…_arm64.dmg",
        //    "version":"百度网盘Mac电脑客户端V8.7.9"}
        //
        // Three shapes in the live data the patterns are built around, not guessed:
        //
        //  1. **`more` is empty for 11 of the 141 releases the feed returns, and
        //     the note moves into the detail object's `title`.** Those are not
        //     note-less releases — 4.54.9's title is
        //     "百度网盘优化了一些已知的体验问题，欢迎升级体验~", the whole note.
        //     So `body` captures the WHOLE detail object and the item patterns are
        //     ordered: bullets first, the title only when there are none.
        //     Capturing just the `more` array would not have shown eleven blank
        //     entries — `ChangelogExtractor` drops an entry whose item patterns
        //     yield nothing (`guard !noteHits.isEmpty`), so those eleven releases
        //     would be MISSING from the changelog entirely, with no blank row to
        //     notice. The fallback is what keeps them.
        //  2. **The key order inside `detail` is not fixed, and neither is the key
        //     set** — measured over all 141 entries (`num=200`; the feed's own
        //     `total` says 145): `more` and `title` are on every one, `stable` on
        //     97, `feature_tips` on 44. So nothing may assume `more` comes first,
        //     and `feature_tips` is a third of the feed rather than a curiosity.
        //     It is a plain STRING in all 44 (`"mac版可以xxx啦"`, vendor filler,
        //     never a release note), which is the only reason the punctuation
        //     anchoring below declines it — a value preceded by `:`. Were the
        //     vendor to make it an array, its elements would start rendering as
        //     notes.
        //  3. **The version string gained a space at some point**: recent releases
        //     say `百度网盘Mac电脑客户端V8.7.9`, older ones `百度网盘Mac电脑客户端 V4.15.0`,
        //     and the oldest drop the prose entirely (`Mac版 V3.9.5`). Anchoring on
        //     `V` + digits rather than on the label survives all three.
        //
        // The first item pattern reads a JSON array element by its PUNCTUATION —
        // a string opened by `[` or `,` and closed by `,` or `]` — which is what
        // separates `more`'s elements from the keys and from `title`'s value in
        // the same object (a key is followed by `:`, a value preceded by one).
        //
        // Its body is `(?:[^"\\]|\\.)+` rather than `[^"]+` so a note containing an
        // escaped quote stays one element. `[^"]+` stops at the backslash's quote
        // and the element is then SILENTLY DROPPED, not reported: the array's other
        // elements still match, so `firstNonEmptyItemHits` is satisfied, never tries
        // the fallback, and the entry renders with fewer notes than the vendor
        // published. (Measured on `"more":["say \"hi\" now","b"]`: `[^"]+` yields
        // `["b"]` alone.) No live item carries a quote today — 0 of 165 — which is
        // exactly why this would have gone unnoticed; the recipe is `.json` because
        // this feed's strings are escaped, so the item pattern has to agree.
        //
        // Verified 2026-08-29 against the live 40-entry response: all 40 entries
        // match, and every version, date and item list is byte-identical to what
        // `json.loads` produces for that entry — including all 7 that fall through
        // to the title.
        ChangelogRecipe(
            bundleID: "com.baidu.BaiduNetdisk-mac",
            source: URL(string: "https://pan.baidu.com/disk/cmsdata?platform=mac&page=1&num=40")!,
            entryPattern:
                #"\{"detail":\[\{(?<body>.*?)\}\],"publish":"(?<date>[^"]+)""#
                + #".*?"version":"[^"]*?V(?<version>[0-9]+(?:\.[0-9]+)*)""#,
            itemPatterns: [
                #"[\[,]"(?<item>(?:[^"\\]|\\.)+)"(?=[,\]])"#,
                #""title":"(?<item>[^"]+)""#,
            ],
            mode: .json,
            maxEntries: 40),

        // QQ音乐 (QQMusic Mac) — the vendor publishes release notes NOWHERE a
        // reader can reach: `y.qq.com/download/index.html` is a JS shell whose
        // served HTML contains no note text at all (measured 2026-08-29), and
        // there is no blog, no appcast and no per-version page. The notes exist
        // only as the `Fdesc` string of the Mac object inside the page's own JSONP
        // data file, which is also this app's `VendorProbeRecipe` endpoint.
        //
        // One entry, by construction: the file states only the CURRENT release per
        // platform, so there is no history to page through.
        //
        // The Mac object (verbatim, 2026-08-29):
        //   "ID":2,"Ftype":2,"Ftitle":"Mac","Fversion":"最新版:11.8.1",…,
        //   "Fdesc":"「AI声景疗愈」…开启\n|「AI伴听」…开启\n|「其他」其他体验优化\n|\n\n|发布时间：2026-08-03",
        //   "Flink1":"https://c.y.qq.com/…QQMusicMac11.8.1Build01.dmg&sign=…"
        // Note the separator is a JSON-escaped `\n` followed by a `|`, so on the
        // regex path every newline is the two characters `\` `n` — the item
        // pattern has to spell it `\\n`, and the trailing `\n|\n\n|` run before
        // 发布时间 has to be eaten by the entry pattern or it becomes a bullet.
        //
        // ANCHORING — the file holds TWO `"Ftitle":"Mac"` objects: the live client
        // (ID 2) and a 2020-era legacy record (ID 15, 7.0.0, "QQ音乐Mac7.0全新改版").
        // Without a discriminator the pane would list a six-year-old release under
        // its own version header. The entry pattern requires the object's own
        // `Flink1` to be a VERSIONED Mac dmg (`QQMusicMac<digit>`); the legacy
        // record links `QQMusicMac_Mgr.dmg`, so it is excluded structurally rather
        // than by an `ID` literal that a table edit could renumber. `[^{}]` between
        // fields is what keeps a lazy gap from wandering into the next platform's
        // object.
        //
        // The date is captured out of `Fdesc`'s own 发布时间 tail so it can only be
        // this entry's — it is display-only here, and `ReleaseDate` cannot parse a
        // bare zone-less day anyway (see the probe recipe's comment).
        //
        // ONE item pattern, not the usual redundant list: it already degenerates
        // correctly. `(?:^|\\n)` matches the start of the body, so a future `Fdesc`
        // with no separators at all yields the whole string as a single note rather
        // than nothing. A second pattern here could never fire.
        //
        // The item body is `(?:[^\\]|\\(?!n))+?`, not `[^\\]+?`: a note has to run
        // THROUGH an escaped quote (`\\"`) while still stopping at the `\\n`
        // separator. The plain negated class cannot tell the two apart — it stops
        // at every backslash, which drops the note carrying the quote instead of
        // splitting it (the extractor is satisfied by the OTHER notes matching, so
        // nothing reports the loss). No live note carries a quote today; the
        // regression test does.
        ChangelogRecipe(
            bundleID: "com.tencent.qqmusicmac",
            source: URL(string: "https://y.qq.com/download/download.js")!,
            entryPattern:
                #""Ftitle":"Mac"[^{}]*?"Fversion":"[^"]*?(?<version>[0-9]+(?:\.[0-9]+)+)""#
                + #"[^{}]*?"Fdesc":"(?<body>(?:[^"\\]|\\.)*?)(?:\\n\|?)*"#
                + #"发布时间[:：]\s*(?<date>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2})"#
                + #"(?:[^"\\]|\\.)*"[^{}]*?"Flink1":"[^"]*QQMusicMac[0-9]"#,
            itemPatterns: [#"(?:^|\\n)\|?(?<item>(?:[^\\]|\\(?!n))+?)(?=\\n|$)"#],
            mode: .json,
            maxEntries: 1,
            minItemLength: 2),

        // MacWhisper — its Sparkle appcast carries no `<description>` on any of
        // its 210 items, only a `sparkle:releaseNotesLink` pointing every release
        // at ONE shared page. So the source-supplied `changelogURL` renders the
        // whole history in a web view no matter which version you are on. That
        // page is plain, hand-written HTML and splits cleanly per version:
        //
        //   <h2>14.8</h2>
        //   <h3>New:</h3>
        //   <li>Dictation: You can now export …</li>
        //   <h3>Bugfixes:</h3>
        //   <li>Fixed: …</li>
        //
        // The `<li>`s are NOT wrapped in a `<ul>` — the vendor emits them bare —
        // so the body is everything up to the next `<h2>`. The `<h3>` group
        // headings are dropped; the items read fine without them. 121 entries
        // parse from the live page (2026-08-31), head 14.8.
        ChangelogRecipe(
            bundleID: "com.goodsnooze.macwhisper",
            source: URL(string: "https://macwhisper-site.vercel.app/release_notes.html")!,
            entryPattern: #"<h2>(?<version>[0-9][^<]*)</h2>(?<body>.*?)(?=<h2>|\z)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

        // GitHub Copilot for Xcode — the Sparkle feed carries no notes on any of
        // its 12 items, and the GitHub release bodies are a single sentence
        // ("Release 0.51.0 of Copilot extension for Xcode"). The real notes are
        // the repo's Keep-a-Changelog file:
        //
        //   ## 0.51.0 - August 12, 2026
        //   ### Added
        //   - Support for Kimi K3 through the updated Copilot language server.
        //
        // `(?:^|\n)##`, not `^##` and not `\n##`: `ChangelogExtractor` compiles
        // with `.dotMatchesLineSeparators` but NOT `.anchorsMatchLines`, so `^`
        // matches ONLY the start of the document — which is why `\n` is needed for
        // the headings, and why `^` has to stay for the one case `\n` cannot see.
        // The file opens with a `# Changelog` preamble today, so every `##` does
        // follow a newline; drop that preamble and a bare `\n##` would silently
        // lose the FIRST entry — the newest release's notes — while every older
        // one kept rendering. `markdownSource` because the
        // items carry inline code (`/v1/messages`) and `[text](url)` links that a
        // plain renderer would otherwise print as punctuation. The `### Added` /
        // `### Fixed` group headings are dropped — only the `- ` bullets become
        // items. 21 entries parse from the live file (2026-08-31), head 0.51.0.
        ChangelogRecipe(
            bundleID: "com.github.copilotforxcode",
            source: URL(string: "https://raw.githubusercontent.com/github/CopilotForXcode/main/CHANGELOG.md")!,
            entryPattern:
                #"(?:^|\n)##\s+(?<version>[0-9][^\s]*)\s*-\s*(?<date>[^\n]+)\n(?<body>.*?)(?=\n##\s|\z)"#,
            itemPatterns: [#"\n-\s+(?<item>[^\n]+)"#],
            markdownSource: true),

        // TypeWhisper — no notes in the appcast either. The official changelog
        // page is the vendor's own, and it interleaves **macOS and Windows**
        // releases in one list (203 mac cards, 167 Windows ones), so the entry
        // pattern is anchored on the platform badge that precedes the version
        // heading. Getting that wrong shows Windows notes under a Mac version.
        //
        //   …</svg>macOS</span><h3 class="font-display …">v1.7.0-daily.20260826</h3>
        //   …<p class="mt-1 text-xs text-muted-foreground">August 26, 2026</p>
        //   <div class="prose …"><h2>Bug Fixes</h2><ul><li>…</li></ul></div>
        //
        // The gap between the heading and the date is a TEMPERED lazy scan
        // (`(?:(?!>macOS</span><h3|>Windows</span><h3).)*?`), not a plain `.*?`:
        // a handful of old cards carry no prose block, and a plain lazy scan ran
        // past them into the NEXT card and filed its notes under the wrong
        // version — two entries did exactly that (0.6.1, 0.5.1) before this was
        // tempered. With it: 194 entries, none spanning a card boundary.
        //
        // Every train lands in one list, so a stable install sees the daily
        // entries above its own release. That is the vendor's page as published;
        // each entry is labelled with its version, and the daily notes are
        // cumulative (successive dailies repeat the same bullets), which is why
        // `maxEntries` is cut to 20 — 40 would be four weeks of near-duplicates.
        ChangelogRecipe(
            bundleID: "com.typewhisper.mac",
            source: URL(string: "https://www.typewhisper.com/en/changelog/")!,
            entryPattern:
                #">macOS</span><h3[^>]*>v?(?<version>[^<]+)</h3>"#
                + #"(?:(?!>macOS</span><h3|>Windows</span><h3).)*?"#
                + #"<p class="mt-1 text-xs text-muted-foreground">(?<date>[^<]*)</p>"#
                + #"<div class="prose[^"]*"[^>]*>(?<body>.*?)</div>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#, #"<p[^>]*>(?<item>.*?)</p>"#],
            maxEntries: 20),
        // Eudic (欧路词典) — `source` is its Sparkle 1 appcast, not a web page,
        // because the appcast IS the changelog: the vendor keeps the app's entire
        // history inside the NEWEST item's `<description>` CDATA — 10,253
        // characters, one `<h2>` for the current release and 34 `<h3>` sections
        // running back to 2.5.0 (measured 2026-09-01). Every older `<item>` in the
        // feed is a 2010-era stub. So without a recipe the row rendered sixteen
        // years of notes under the heading "26.9.0".
        //
        // It cannot reach the appcast's own structured path either:
        // `AppcastHTMLChangelogParser.isStructured` requires at least one `<li>`
        // and this body has ZERO — 29 `<p>` and 154 `<br>` instead — so
        // `SparkleAppcastSource` leaves `structuredChangelog` nil and the pane fell
        // to raw-HTML rendering of the whole blob.
        //
        // The headings are not a clean version list, which is what rules out
        // teaching the generic parser this shape:
        //   * 7 of the 34 are the literal label "更新内容", not a version;
        //   * several carry a suffix — "3.6.0 改进", and "2.5.2改进" with no space.
        // So the entry pattern keys on a heading that CONTAINS a dotted number
        // rather than on the heading tag, and `body` runs to the next such heading
        // — stepping over the label rows, which is exactly why the lookahead
        // demands a digit. The CDATA close is the other terminator, so the last
        // section cannot swallow the 2010 stubs that follow it.
        //
        // Items are `- text<br>` lines inside a `<p>`, and the leading dash is
        // consumed because the renderer draws its own bullet. The capture is
        // `.*?` to the next `<br>`/`</p>` rather than `[^<]+`: the pre-3.7 sections
        // wrap whole lines in `<b>`, and a no-tag capture silently dropped every
        // one of them. Yields 29 entries, validated against the live feed.
        //
        // No dates: the per-version sections carry none (the feed's single
        // `<pubDate>` describes only the newest release), so every entry renders
        // date-less rather than borrowing a wrong one.
        ChangelogRecipe(
            bundleID: "com.eusoft.eudic",
            source: URL(string: "https://static.eudic.net/pkg/eudic_mac.xml")!,
            entryPattern:
                #"<h[23]>[^<]*?(?<version>\d+(?:\.\d+)+)[^<]*</h[23]>"#
                + #"(?<body>.*?)(?=<h[23]>[^<]*\d|\]\]></description>|\z)"#,
            itemPatterns: [
                #"(?:<p[^>]*>|<br\s*/?>)\s*(?:[-–]\s*)?(?<item>.*?)\s*(?=<br\s*/?>|</p>)"#
            ],
            minItemLength: 2),

        // MARK: - 2026-09-03 AnythingLLM / Chatbox

        // AnythingLLM — the desktop build's version source is the vendor CDN
        // (`cdn.anythingllm.com/latest/version.txt`), which is a bare version
        // string and carries no notes at all. The notes live in the project's
        // GitHub releases, and the two are the SAME numbering: `version.txt`
        // answered `1.16.1` on 2026-09-03 and the newest release there is tagged
        // `v1.16.1` (bodies run 1.7–10.7 KB). That alignment is what makes this
        // safe to attach — a changelog keyed to a version the app never reports
        // renders an empty pane, which is worse than the web-view fallback.
        //
        // `docs.anythingllm.com/changelog` is NOT the source: it 404s (checked
        // 2026-09-03). Reuses `.gitHubReleases`, the same decoder Waku and
        // Shotbase go through.
        ChangelogRecipe(
            bundleID: "com.anythingllm",
            source: URL(
                string: "https://api.github.com/repos/Mintplex-Labs/anything-llm/releases?per_page=40")!,
            mode: .json,
            maxEntries: 20,
            structuredFormat: .gitHubReleases),

        // Chatbox — the electron-builder feed we read for the version
        // (`latest-mac.yml`) is a manifest: filenames, sizes and hashes, no prose.
        // The vendor's own changelog page has the notes and uses the same
        // numbering as the feed (`v1.23.1` on the page, `version: 1.23.1` in the
        // yml, 2026-09-03).
        //
        // Each release renders as `<h2>v<ver> - <date></h2>` followed by TWO
        // lists: an `<ol>` of changes and a `<ul>` of per-platform download
        // links. The entry pattern binds the `<ol>` specifically — capturing up
        // to the next `<h2>` instead would put six download links ("MacOS(Apple
        // Silicon)", "Windows", …) into every release's notes. Validated against
        // the live page 2026-09-03: 30 entries, 1.23.1 → 4 items, 1.23.0 → 9,
        // and zero entries whose body contains a `download.chatboxai.app` link.
        ChangelogRecipe(
            bundleID: "xyz.chatboxapp.app",
            source: URL(string: "https://chatboxai.app/en/help-center/changelog")!,
            entryPattern:
                #"<h2>v(?<version>[0-9][0-9.]*) - (?<date>[0-9.]+)</h2>\s*<ol>(?<body>.*?)</ol>"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            maxEntries: 20),

        // Deliberately NOT covered, both checked 2026-09-03 against the real
        // bytes rather than assumed:
        //
        //   * **ChatGPT Classic** (`com.openai.chat`). Its Sparkle appcast has a
        //     `<description>`, so it LOOKS like a changelog source — the content
        //     is vendor marketing, not release notes: "&#8220;Install Update&#8221;
        //     to keep using ChatGPT Classic", then "[Recommended] Or, try the new
        //     ChatGPT app" with a link to the replacement product. One `<item>`,
        //     no per-version history, and the same copy would render under every
        //     future build. Rendering that as "what is new" is worse than the
        //     web-view fallback, which at least shows it as the vendor's page.
        //   * **Microsoft 365 Copilot** (`com.microsoft.m365copilot`).
        //     `learn.microsoft.com/en-us/microsoft-365-copilot/release-notes` is
        //     organised by DATE and then by PRODUCT (Excel, Word, Outlook,
        //     PowerPoint, OneNote, Viva Insights, …) for the whole Microsoft 365
        //     Copilot service. The string `1.2608` — the build our probe reads
        //     out of the pkg filename — appears ZERO times on the page, so no
        //     version-keyed recipe can bind, and a date-keyed one would show
        //     Excel and Outlook features under the Copilot app's row.

        // MARK: - 2026-09-03 AnyDesk / Antigravity / Headlamp / Helium / Xcode

        // AnyDesk — the same plain-text changelog its `VendorProbeRecipe` already
        // reads for version detection. The vendor's HTML changelog
        // (`anydesk.com/en/changelog/mac-os`) answers 403 behind a Cloudflare
        // challenge even under a full Safari UA, so the pane's web-view fallback
        // renders a challenge page rather than notes; `changelog.txt` answers 200.
        //
        // Every platform shares the file, newest first:
        //
        //   22.07.2026 - 9.7.3 (macOS)
        //   ------------------
        //   New Features:
        //   - Visibility and online status for AnyDesk One Chat can be set manually
        //
        // The `(macOS)` anchor is load-bearing for exactly the reason the probe's
        // is: Windows runs on a HIGHER number (9.7.15 the day this was written), so
        // an unanchored pattern lists another platform's releases under this app.
        // 80 macOS entries on the live file (2026-09-03), newest 9.7.3.
        //
        // `[^\n]` in the item pattern, not `.`: every pattern is compiled with
        // dot-matches-newline, so `^-\s+(?<item>.+)$` would swallow the whole
        // section as one item. Tags and entities are left alone because the body is
        // plain text — there is no markup to strip and an `&` is just an `&`.
        //
        // The section labels ("New Features:", "Fixed Bugs:", "Other Changes:") are
        // not captured: items are flat here as everywhere else.
        ChangelogRecipe(
            bundleID: "com.philandro.anydesk",
            source: URL(string: "https://download.anydesk.com/changelog.txt")!,
            entryPattern:
                #"(?<date>\d{2}\.\d{2}\.\d{4}) - (?<version>\d+(?:\.\d+)+) \(macOS\)[ \t]*\n-+\n"#
                + #"(?<body>.*?)(?=\n\d{2}\.\d{2}\.\d{4} - |\z)"#,
            itemPatterns: [#"(?m)^-\s+(?<item>[^\n]+)"#],
            stripTags: false,
            decodeEntities: false),

        // Antigravity — antigravity.google/changelog, which the hub's
        // `VendorProbeRecipe` already links as its `changelogURL`.
        //
        // That recipe's sibling (the IDE) says the page is "JS-rendered — 88 KB
        // with zero version strings in the served HTML". That reading was of a
        // *compressed* body: the server answers gzip even for
        // `Accept-Encoding: identity`, and the 88/99 KB it counted is the gzip
        // stream. Decoded it is 401 KB of fully server-rendered Astro markup
        // carrying every release for all four products (2026-09-03) — which is
        // also why both apps can be covered from the one page.
        //
        // One page, four products, one panel each (`data-list-panel`), so the two
        // recipes must not read each other's releases. They anchor on the release
        // link instead of the panel wrapper, because the wrapper is an ancestor a
        // flat regex cannot scope to: every row's version link carries the product
        // in its own href — `/releases?tab=hub&version=2.12.0`. 18 hub entries and
        // 30 IDE entries on the live page, versions matching what the two probe
        // recipes detect (hub 2.12.0, IDE 2.5.5).
        //
        // `body` stops at the next row, the next panel, or the section close, so a
        // row can never absorb the one after it — and the run up to the `<h3>` is
        // fenced by the same two markers, because it is otherwise the one
        // unbounded part of the match: a row shipped without a heading would pair
        // its version with the NEXT row's notes, and the last hub row would reach
        // into the IDE panel. Every row on the live page has a heading today, which
        // is exactly why nothing would have noticed. Items are the lead paragraph
        // (`div.changes`) followed by every `li.caption` in the "Improvements" /
        // "Fixes" / "Patches" disclosure groups — the group labels themselves are
        // dropped, as everywhere else. `<code>/boost</code>` survives as `/boost`
        // through `stripTags`.
        ChangelogRecipe(
            bundleID: "com.google.antigravity",
            source: URL(string: "https://antigravity.google/changelog")!,
            entryPattern:
                #"href="/releases\?tab=hub&amp;version=[^"]*"[^>]*>(?<version>[^<]+)</a>"#
                + #"<br[^>]*>(?<date>[^<]*)</p>"#
                + #"(?:(?!section-row-wrapper|grid-body).)*?"#
                + #"<h3[^>]*data-h3-pin[^>]*>(?<title>.*?)</h3>"#
                + #"(?<body>.*?)(?=<div class="section-row-wrapper|<div class="grid-body|</section>)"#,
            itemPatterns: [
                #"(?:<div class="changes[^"]*"[^>]*><p>|<li[^>]*class="caption[^"]*"[^>]*>)"#
                + #"(?<item>.*?)(?:</p>|</li>)"#
            ],
            maxEntries: 20),

        // Antigravity IDE — the `ide` panel of the same page, for the second,
        // separate app (`com.google.antigravity-ide`, a VS Code fork) whose probe
        // recipe deliberately carried NO `changelogURL` because it could not
        // confirm the page described the IDE at all. It does: the page's own tab
        // strip has an "Antigravity IDE" panel, and its newest entry is 2.5.5 —
        // the exact version that recipe detects. See the hub recipe above for the
        // shape; this differs only in the `tab=ide` anchor.
        ChangelogRecipe(
            bundleID: "com.google.antigravity-ide",
            source: URL(string: "https://antigravity.google/changelog")!,
            entryPattern:
                #"href="/releases\?tab=ide&amp;version=[^"]*"[^>]*>(?<version>[^<]+)</a>"#
                + #"<br[^>]*>(?<date>[^<]*)</p>"#
                + #"(?:(?!section-row-wrapper|grid-body).)*?"#
                + #"<h3[^>]*data-h3-pin[^>]*>(?<title>.*?)</h3>"#
                + #"(?<body>.*?)(?=<div class="section-row-wrapper|<div class="grid-body|</section>)"#,
            itemPatterns: [
                #"(?:<div class="changes[^"]*"[^>]*><p>|<li[^>]*class="caption[^"]*"[^>]*>)"#
                + #"(?<item>.*?)(?:</p>|</li>)"#
            ],
            maxEntries: 20),

        // Headlamp — its GitHub releases, read with regexes rather than through
        // `structuredFormat: .gitHubReleases`, because that decoder deliberately
        // refuses this body: `GitHubMarkdownParser` bails on a Markdown TABLE, and
        // Headlamp writes its whole changelog as tables (142 table rows in v0.45.0
        // — its own doc comment names this app as the reason the guard exists). So
        // the pane had nothing structured to show and fell back to embedding the
        // releases page.
        //
        // Each table is `| change | Thanks to:<br>@who<br>#issue |` under a
        // section heading, with a two-row preamble per table: an `<img>`-only
        // header pair (stripped to nothing, then dropped by `minItemLength`) and
        // the `|:--|--:|` alignment row (dropped by requiring a letter-ish first
        // character and 15+ characters). Only the first cell is taken — the second
        // is attribution, not a change.
        //
        // The bullet pattern behind it is not redundancy for its own sake: the
        // table layout starts at 0.44.0, and the older releases still on the page
        // (0.30.0 … 0.43.0) are plain bullet lists. First-pattern-wins picks per
        // entry, so both eras render.
        //
        // That bullet is `[-*]`, both markers, because this vendor changed marker
        // mid-history: 0.36.0 and newer write `- `, 0.38.0 and 0.30.0 … 0.35.0
        // write `* `. A `-`-only pattern does not fail on those — it yields an
        // entry with no items, which `ChangelogExtractor` drops, so 8 of the 18
        // releases simply vanished from the rail while the recipe still reported
        // success. Measured against the live endpoint, not inferred.
        //
        // The item capture is `(?:\\[^rn]|[^"\\])`, not `[^\\]`, because the
        // capture happens BEFORE the JSON unescape: a cell containing `\"` would
        // be cut at the backslash and rendered as half a sentence. This is the
        // trap `StructuredFormat.postmanReleaseNotes` documents as the reason that
        // format stopped using regex at all.
        //
        // `"prerelease":false` in the entry pattern keeps this to the track the
        // user is on — the same policy `.gitHubReleases` states — and the `v`
        // prefix keeps it to the app: the repo interleaves `headlamp-helm-<ver>`
        // and `headlamp-plugin-*` tags its own `GitHubReleaseRule` already filters.
        // The gaps between fields refuse to cross a `"tag_name":` so a release with
        // a null body cannot pair one release's version with the next one's notes.
        // 18 entries on the live endpoint (2026-09-03), newest 0.45.0.
        //
        // `\s*` around every colon: this endpoint serves the SAME document compact
        // (`"tag_name":"v0.45.0"`) and pretty-printed (`"tag_name": "v0.45.0"`),
        // and which one you get is not the recipe's to choose — it varied by
        // request on 2026-09-03. A pattern written against either form alone reads
        // as a clean "the vendor restyled their page" failure against the other.
        // The registry's other GitHub-API recipes never met this because they go
        // through `Decodable`, which cannot see whitespace at all.
        ChangelogRecipe(
            bundleID: "com.microsoft.Headlamp",
            source: URL(
                string:
                    "https://api.github.com/repos/kubernetes-sigs/headlamp/releases?per_page=40"
            )!,
            entryPattern:
                #""tag_name"\s*:\s*"v(?<version>[0-9][^"]*)""#
                + #"(?:(?!"tag_name"\s*:).)*?"prerelease"\s*:\s*false\s*,"#
                + #"(?:(?!"tag_name"\s*:).)*?"published_at"\s*:\s*"(?<date>[^"T]+)T"#
                + #"(?:(?!"tag_name"\s*:).)*?"body"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [
                #"\\(?:r\\)?n\|\s(?<item>[A-Za-z(`\[][^|]{15,}?)\s\|"#,
                #"\\(?:r\\)?n[-*]\s(?<item>(?:\\[^rn]|[^"\\]){15,})"#,
            ],
            mode: .json,
            markdownSource: true,
            maxEntries: 20),

        // Helium — its GitHub releases, again with regexes rather than
        // `.gitHubReleases`: the body is a hash dump followed by two fenced commit
        // logs, and `GitHubMarkdownParser`'s prose pass would render the md5/sha
        // lines as "changes" while the fences it skips hold the only real content.
        //
        // Nothing else can supply notes. `updates.helium.computer/mac/appcast-arm64.xml`
        // (the app's own Sparkle feed, and its update source here) carries no
        // `<description>` and no `<sparkle:releaseNotesLink>` on any item, and
        // helium.computer publishes no changelog page at all (`/changelog` and
        // `/releases` both 404) — so the pane fell back to embedding the GitHub
        // releases page.
        //
        // What the vendor does publish is the commit log of the two repos each
        // build merges — `helium-macos` and `helium-chromium` — as
        // `<hash> <subject>` lines inside fenced blocks. The hash is consumed
        // rather than captured: it is a link the pane cannot follow and it pushes
        // the subject off the row. The `[0-9a-f]{7,10} ` anchor after a newline is
        // what keeps the hash block out — `md5:`/`sha256:` lines start with
        // letters and a colon, so no line of them can match at a line start.
        //
        // The item capture is `(?:\\[^rn]|[^"\\])`, not `[^\\]`: the capture runs
        // BEFORE the JSON unescape, so a commit subject containing `\"` — five of
        // them in the current 40-release window — would be cut at the backslash and
        // shown as half a line. Same trap `StructuredFormat.postmanReleaseNotes`
        // documents as the reason that format abandoned regex.
        //
        // That newline is `\\(?:r\\)?n`, both spellings, because the vendor uses
        // both: every stable body sampled ends its lines `\\r\\n` and every
        // prerelease one `\\n`. A pattern that knows only the first does not fail
        // on the second — it yields an entry with no changes, which is invisible.
        //
        // `"prerelease":false` for the same reason as Headlamp above, and it is not
        // theoretical here: the vendor tags a build as prerelease for a day or two
        // before the appcast picks it up (0.16.4.1 on 2026-09-03), and listing it
        // would show notes for a version this app is not being offered. 33 entries
        // on the live endpoint, newest 0.16.3.1 — the version the appcast serves.
        //
        // `\s*` around every colon: this endpoint serves the SAME document compact
        // (`"tag_name":"v0.45.0"`) and pretty-printed (`"tag_name": "v0.45.0"`),
        // and which one you get is not the recipe's to choose — it varied by
        // request on 2026-09-03. A pattern written against either form alone reads
        // as a clean "the vendor restyled their page" failure against the other.
        // The registry's other GitHub-API recipes never met this because they go
        // through `Decodable`, which cannot see whitespace at all.
        ChangelogRecipe(
            bundleID: "net.imput.helium",
            source: URL(
                string: "https://api.github.com/repos/imputnet/helium-macos/releases?per_page=40"
            )!,
            entryPattern:
                #""tag_name"\s*:\s*"(?<version>[0-9][^"]*)""#
                + #"(?:(?!"tag_name"\s*:).)*?"prerelease"\s*:\s*false\s*,"#
                + #"(?:(?!"tag_name"\s*:).)*?"published_at"\s*:\s*"(?<date>[^"T]+)T"#
                + #"(?:(?!"tag_name"\s*:).)*?"body"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [#"\\(?:r\\)?n[0-9a-f]{7,10} (?<item>(?:\\[^rn]|[^"\\]){3,})"#],
            mode: .json,
            maxEntries: 20),

        // Xcode — Apple's own release notes, which `XcodeReleasesSource` already
        // links per release (`links.notes.url` in `xcodereleases.com/data.json`)
        // and which the pane could only ever embed: the `/documentation/…` URL
        // serves a 17 KB SPA shell with no note text in it (fetched 2026-09-03).
        // The `/tutorials/data/…` twin of that URL is the document the shell
        // fetches, and it carries everything.
        //
        // One page per release train, and every beta of a train shares its page:
        // the top of `xcode-27-release-notes` IS beta 6's notes, with each earlier
        // beta below it under `Updates in Xcode 27 Beta N`. So a beta install and a
        // released install read the same recipe and differ only in the page the
        // template resolves to — `26.6` → `xcode-26_6`, `27.0 beta 6` → `xcode-27`.
        // See `appleDocVersionToken(for:)` for why that mapping needs its own token
        // and what `{major}` would get wrong.
        //
        // `source` is only reached when no version is supplied at all (a sweep with
        // no installed Xcode and no detected version); it names the current train,
        // and being a year out of date there costs nothing the templated path uses.
        //
        // Detection-only app, deliberately (an Apple ID gates every prerelease
        // download), so these notes are the whole of what the row can offer beyond
        // a version number.
        ChangelogRecipe(
            bundleID: "com.apple.dt.Xcode",
            source: URL(
                string: "https://developer.apple.com/tutorials/data/documentation"
                    + "/xcode-release-notes/xcode-27-release-notes.json")!,
            mode: .json,
            maxEntries: 20,
            sourceTemplate: "https://developer.apple.com/tutorials/data/documentation"
                + "/xcode-release-notes/xcode-{appleDocVersion}-release-notes.json",
            structuredFormat: .appleDeveloperReleaseNotes),

        // PDF Expert — the appcast's `sparkle:releaseNotesLink` is
        // `pem3/changelog.html`, a 3.5 KB page holding ONLY the newest release's
        // paragraph, so the pane could show one version and no history. The
        // vendor's multi-version page is the `sparkle:fullReleaseNotesLink` beside
        // it (`pem3/changelog`) — a link element `SparkleAppcastParser` does not
        // read at all, which is why this is a recipe and not a feed field.
        //
        // Server-rendered and unusually plain: the whole document uses four tags
        // (`p`, `strong`, `br`, `body`) and carries no links, no images and no
        // dates — so there is no `date` group to capture, and one item pattern
        // covers every entry. Each release is
        //   <p><strong>Version 3.13.2 </strong></p> text<br />more text<br />
        // with the trailing space present on some headings and not others.
        //
        // 88 headings, 85 distinct versions: `3.10.23`, `3.10.22` and `3.9.2` each
        // appear TWICE, and for two of those the two bodies are different text
        // (3.10.23 is "Meet Draw on Mac…" in one and "Hello from the team!…" in
        // the other). `ChangelogExtractor` dedupes on version + title and the
        // title is nil here, so the second body of each pair is dropped silently.
        // Left as is rather than worked around: which of two same-numbered
        // paragraphs is the real one is the vendor's question, not a regex's, and
        // both fall outside the `maxEntries` window anyway except 3.10.2x.
        //
        // `body` runs to the next heading or `</body>`, and items are the runs of
        // text between the `<br />`s — `[^<]+` cannot cross a tag, so the split is
        // the markup's own. The `(?:^|>)` prefix is why the run starts where the
        // text does: without it the engine simply resumes one character past the
        // `<` it stopped on and every item after the first reads "br />…".
        // `\s*(?:-\s+)?` then drops the leading dash the pre-3.1 entries spell
        // their bullets with ("- Stability and performance improvements") — the
        // `\s*` is load-bearing there, since a run opens on the newline after
        // `<br />` and the dash is not at the match start until that is consumed.
        // Empty runs (the `<br /><br />` pairs the older entries pad paragraphs
        // with) clean to "" and are dropped by the default `minItemLength` of 1;
        // no larger floor is set, because across all 88 entries of the live page
        // there is not one cleaned item shorter than four characters, so a floor
        // would be a knob no input measures and a trap for the first short note.
        //
        // ⚠️ The heading is matched as `<p[^>]*>`, not a bare `<p>`, and that is
        // the one piece of slack worth spending here: this recipe's failure mode
        // is NOT the usual zero entries. If the terminator stops matching, the
        // first block simply runs to `</body>` and the result is ONE entry,
        // correctly versioned `3.13.2`, carrying every paragraph on the page —
        // and `duo verify` records only the newest version, never an entry count,
        // so that failure sweeps green. A single added class or attribute on the
        // vendor's `<p>` would have been enough.
        ChangelogRecipe(
            bundleID: "com.readdle.pdfexpert-mac",
            source: URL(string: "https://pdfexpert.com/pem3/changelog")!,
            entryPattern:
                #"<strong>\s*Version\s+(?<version>[0-9][0-9.]*)\s*</strong>\s*</p>"#
                + #"(?<body>.*?)(?=<p[^>]*>\s*<strong>\s*Version\s|</body>)"#,
            itemPatterns: [#"(?:^|>)\s*(?:-\s+)?(?<item>[^<]+)"#],
            maxEntries: 20),
    ]

    /// Group recipes by lowercased bundle id. Most bundle ids map to a single
    /// recipe; a few (Thunderbird Stable + ESR) map to several that differ by
    /// `channel`. Order within a group preserves declaration order.
    private static let byBundleID: [String: [ChangelogRecipe]] = Dictionary(
        grouping: recipes, by: { $0.bundleID.lowercased() })

    /// The recipe for an app on a given channel and version, if we have one.
    /// Case-insensitive on bundle id, to match `ChangelogCatalog`'s convention.
    ///
    /// Selection within a bundle id's group:
    ///   0. narrow to the recipes whose version window covers `version`
    ///      (`scoped(_:toVersion:)`), then, among those:
    ///   1. a recipe whose `channel` exactly matches the install's channel;
    ///   2. a channel-agnostic recipe (`channel == nil`) — every existing
    ///      single-recipe app, so passing a channel never changes their result;
    ///   3. the `.stable` recipe as a last resort (an unknown/odd channel still
    ///      gets *some* notes rather than none).
    /// Passing `channel: nil` skips step 1 and lands on step 2/3 — the behavior the
    /// old single-arg lookup had. Step 0 is inert for every group whose recipes
    /// declare no window, which is all of them but Raycast's.
    public static func recipe(
        forBundleID bundleID: String?, channel: ReleaseChannel? = nil,
        version: String? = nil
    ) -> ChangelogRecipe? {
        guard let bundleID else { return nil }
        let group = scoped(byBundleID[bundleID.lowercased()] ?? [], toVersion: version)
        if let channel, let exact = group.first(where: { $0.channel == channel }) {
            return exact
        }
        return group.first(where: { $0.channel == nil })
            ?? group.first(where: { $0.channel == .stable })
            ?? group.first
    }

    /// Step 0 of the lookup: keep only the recipes covering `version`, most
    /// specific first.
    ///
    /// Written to be a no-op wherever it isn't needed, because it sits in front of
    /// ~100 recipes that have never had a version window and must keep resolving
    /// exactly as before:
    ///   - a group where NO recipe declares a window is returned untouched, so a
    ///     nil version can never start excluding recipes;
    ///   - with a window declared but no version to judge by, the window-LESS
    ///     recipes win. That is the useful default rather than an arbitrary one:
    ///     the catch-all is the vendor's current page and the window exists to
    ///     carve an exception out of it. If every recipe in the group has a window
    ///     the group is kept whole rather than collapsing to nothing;
    ///   - a version outside every window also keeps the group whole.
    /// The last two are the call this file makes everywhere else: a changelog is
    /// low-stakes, and possibly-wrong notes beat no notes — the pane can only fall
    /// back to embedding the page.
    ///
    /// **A windowed recipe outranks a catch-all that merely failed to exclude the
    /// version.** This is what lets one page stay the default while another claims
    /// a range out of it, and it matters because two trains' version numbers need
    /// not be two contiguous halves of a line. Raycast's are not: v1 runs 1.95–1.104,
    /// while v2 ran 0.63–0.71 in beta before jumping to 2.0 at GA — v1 sits *between*
    /// v2's two stretches. Expressing that as `<2` versus `2+` would hand a 0.71
    /// install the v1 archive, the one page that does not carry its notes. So the
    /// archive claims exactly `[1, 2)` and the v2 page keeps everything else.
    static func scoped(
        _ group: [ChangelogRecipe], toVersion version: String?
    ) -> [ChangelogRecipe] {
        guard group.contains(where: \.declaresVersionWindow) else { return group }
        guard let version, !version.isEmpty else {
            let unscoped = group.filter { !$0.declaresVersionWindow }
            return unscoped.isEmpty ? group : unscoped
        }
        let covering = group.filter { $0.covers(appVersion: version) }
        guard !covering.isEmpty else { return group }
        let windowed = covering.filter(\.declaresVersionWindow)
        return windowed.isEmpty ? covering : windowed
    }

    /// The entry shape both WorkBuddy sites render. Shared rather than duplicated
    /// because the two pages come off the same VitePress build: a fix applied to
    /// one and not the other would leave the sites silently disagreeing about
    /// which releases they can show.
    static let workBuddyEntryPattern =
        #"<h2[^>]*>\s*(?<version>\d+(?:\.\d+)+)"#
        + #"(?:[^<（(]*[（(](?<date>[^）)<]+)[）)])?"#
        // Tempered dot, not a plain `.*?`: a lazy gap still BACKTRACKS past the
        // first `</h2>` when that one is not followed by a list, and then binds
        // to the next release's. A heading with no list of its own — a "coming
        // soon" placeholder, say — would then adopt the newest release's items
        // AND consume its heading, so the real entry disappears from the pane
        // while its notes show under the wrong version. Refusing to cross a
        // `</h2>` makes the adjacency requirement below actually hold.
        + #"(?:(?!</h2>).)*</h2>\s*<ul[^>]*>(?<body>.*?)</ul>"#

    /// Every recipe registered for a bundle id (across channels). Used to clear all
    /// channel variants' caches on update — see `AppListModel.invalidateChangelog`.
    public static func recipes(forBundleID bundleID: String?) -> [ChangelogRecipe] {
        guard let bundleID else { return [] }
        return byBundleID[bundleID.lowercased()] ?? []
    }
}
