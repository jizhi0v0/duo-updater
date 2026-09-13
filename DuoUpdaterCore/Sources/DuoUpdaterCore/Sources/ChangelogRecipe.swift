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

    /// When non-nil, the page to parse is not in the registry at all: it is the
    /// URL the update source already resolved, `RemoteVersion.changelogURL`, and
    /// this is an anchored regex that URL must match before it is fetched.
    ///
    /// For a feed that inlines nothing and links out per item and per language —
    /// Mac Mouse Fix's appcast carries one `<sparkle:releaseNotesLink xml:lang>`
    /// per language on every item. `SparkleAppcastParser.preferredVariant` has
    /// already picked this reader's language and this version's page, so a
    /// `{lang}` token in `sourceTemplate` would be a second, hand-maintained
    /// language decision beside that one, free to disagree with it (#557).
    ///
    /// A pattern rather than a flag, because the URL is written by whichever
    /// source answered, and `entryPattern` is written against one vendor's page.
    /// A link somewhere else is not this recipe's page; the recipe then does
    /// nothing and the pane embeds that page as it would with no recipe.
    /// `ChangelogURLPolicy` is applied too (see `acceptedFeedPage(_:)`), so this
    /// path cannot fetch a URL the web view would refuse to open.
    ///
    /// With no accepted URL the recipe is inert: `ChangelogRecipeSelection`
    /// does not offer it. `source` is then read only by `duo verify`, which has
    /// no update result: it must be the appcast the page is resolved from, and
    /// `ChangelogService.loadDiagnostic` reads that feed with the production
    /// parser to find the page. Mutually exclusive with `sourceTemplate`,
    /// `indexLinkPattern` and `structuredFormat`, which
    /// `ChangelogReviewRegressionTests` enforces.
    public let feedPagePattern: String?

    /// The release channel this recipe targets, or nil for a channel-agnostic
    /// recipe (the common case — most apps have one changelog regardless of
    /// channel). This matters only when **several channels share one bundle id**
    /// and want *different* changelog pages: Thunderbird's Stable and ESR are both
    /// `org.mozilla.thunderbird` but live on separate version trains, so each gets
    /// its own recipe distinguished by `channel`. `recipe(forBundleID:channel:)`
    /// prefers an exact channel match, then a channel-agnostic recipe, then a
    /// `.stable` one, and finally ANY recipe in the group — so existing
    /// single-recipe apps (channel nil) keep matching every channel exactly as
    /// before, and a bundle id whose recipes are all non-stable still answers.
    /// See that method for the fourth step, which is easy to reason past.
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

    /// Optional regex run over each entry's `body` to pull out category headings
    /// (`### Added`, `### Fixed`, …) so the renderer can show them as their own
    /// styled line instead of silently dropping them the way a plain `itemPattern`
    /// boundary does. Every match becomes one `.heading` block (capture group 1,
    /// or the named `heading` group), cleaned the same way an item is — including
    /// `markdownSource` unwrapping. nil = no headings (the common case).
    ///
    /// Opt-in and unconditional, unlike `GitHubMarkdownParser`'s "≥2 siblings, no
    /// digit" heuristic (see `Changelog.parserGeneration`'s generation-3 entry):
    /// that heuristic exists because ONE parser has to guess at structure across
    /// dozens of GitHub-hosted vendors with no per-app tuning. A recipe that sets
    /// this is already curated for one vendor's page — Mac Performance Monitor's
    /// real Keep a Changelog file, where `### Added`/`### Fixed`/… are always
    /// genuine categories — so every match renders, the same way `imagePattern`
    /// renders every matched image without a similar guess.
    public let headingPattern: String?

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
        /// super.engineering's `releases.superconductor.so/changelog.json` — a
        /// `releases[]` array, newest first, of `{version, date, groups[{title,
        /// commits[{message, pr}]}]}`. `version` is a commit hash (40 hex digits
        /// for most releases, 8 for the oldest ones); the decoder shortens it to
        /// the eight the installed bundle reports, so an entry's heading is the
        /// same string the row shows. Group titles ("Features", "Bug Fixes", …)
        /// become lines of their own ahead of their commits, as
        /// `alcoveChangelog`'s do.
        case superconductorChangelog
        /// Claude Desktop's docs changelog, `claude.com/docs/cowork/changelog.md` —
        /// `<Update label="v…" description="YYYY-MM-DD">` blocks whose bullets sit
        /// under `**General**` / `**Code**` / `**Cowork**` / `**3P**`. Decoded
        /// rather than regex-extracted because the in-app "What's new" groups the
        /// same notes differently — by kind (New / Improved / Fixed), not by
        /// surface — and regrouping is not something a pattern can do. See
        /// `StructuredChangelogDecoder.decodeClaudeDesktop`.
        case claudeDesktopChangelog
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

    /// Which releases on a `.gitHubReleases` endpoint belong to THIS app, and how
    /// their tag spells the version. nil (every recipe before Cline) keeps the
    /// historic behaviour: every release is this app's, and the version is the tag
    /// minus a leading `v`.
    ///
    /// Set it for a **monorepo** — a repo whose Releases carry several products.
    /// `cline/cline` ships four trains from one repo (measured 2026-09-12 over its
    /// newest 100 releases: 33 `desktop-*`, 24 `v*` VS Code extension, 22
    /// `sdk/sdk/v*`, 21 `cli-v*`), and the decoder's two assumptions each break in
    /// their own way, neither of them loudly:
    ///
    ///   * **No filter** — the panel for Cline Desktop would list the extension's
    ///     and the CLI's releases as if they were its own. They are real releases
    ///     with real notes, so nothing looks malformed; it is just another
    ///     product's changelog under this app's name.
    ///   * **Tag-is-version** — `stripLeadingV` only removes a leading `v`, so
    ///     `desktop-v0.0.26` stays `desktop-v0.0.26` and no entry ever matches the
    ///     version the row shows.
    ///
    /// Capture group 1 is the version. A pattern with no group falls back to the
    /// same `stripLeadingV` the unfiltered path uses, so this can be used as a
    /// pure filter.
    ///
    /// Only `.gitHubReleases` reads it. Setting it on any other format is a silent
    /// no-op, which `ChangelogReviewRegressionTests` refuses — same stance as
    /// `skipSections`.
    public let tagPattern: String?

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
        headingPattern: String? = nil,
        minimumAppVersion: String? = nil,
        belowAppVersion: String? = nil,
        structuredFormat: StructuredFormat? = nil,
        httpMethod: HTTPMethod = .get,
        requestBody: Data? = nil,
        skipSections: [String] = [],
        tagPattern: String? = nil,
        acknowledgedStaleEntry: String? = nil,
        feedPagePattern: String? = nil
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
        self.headingPattern = headingPattern
        self.minimumAppVersion = minimumAppVersion
        self.belowAppVersion = belowAppVersion
        self.httpMethod = httpMethod
        self.requestBody = requestBody
        self.skipSections = skipSections
        self.tagPattern = tagPattern
        self.acknowledgedStaleEntry = acknowledgedStaleEntry
        self.feedPagePattern = feedPagePattern
    }

    /// `url` when this recipe reads the feed-resolved page and `url` is that page:
    /// it matches `feedPagePattern` in full and passes `ChangelogURLPolicy`. Nil
    /// for every other input, including every recipe with no `feedPagePattern`.
    ///
    /// Whole-string match on `absoluteString`, not `firstMatch` anywhere in it:
    /// a registry pattern that forgot its anchors must not accept
    /// `https://elsewhere.example/?u=https://raw.githack.com/…`.
    public func acceptedFeedPage(_ url: URL?) -> URL? {
        guard let feedPagePattern, let url, ChangelogURLPolicy.isDisplayable(url),
              let regex = try? NSRegularExpression(pattern: feedPagePattern)
        else { return nil }
        let string = url.absoluteString
        let whole = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, options: [.anchored], range: whole),
              match.range == whole
        else { return nil }
        return url
    }

    /// The page `ChangelogService` fetches: the accepted feed-resolved page for a
    /// `feedPagePattern` recipe (nil when there is none — never `source`, which
    /// for such a recipe is an appcast, not a page), else
    /// `resolvedSource(forVersion:)`.
    public func pageURL(forVersion version: String?, feedPage: URL?) -> URL? {
        guard feedPagePattern != nil else { return resolvedSource(forVersion: version) }
        return acceptedFeedPage(feedPage)
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
        headingPattern = try c.decodeIfPresent(String.self, forKey: .headingPattern)
        minimumAppVersion = try c.decodeIfPresent(String.self, forKey: .minimumAppVersion)
        belowAppVersion = try c.decodeIfPresent(String.self, forKey: .belowAppVersion)
        httpMethod = try c.decodeIfPresent(HTTPMethod.self, forKey: .httpMethod) ?? .get
        requestBody = try c.decodeIfPresent(Data.self, forKey: .requestBody)
        skipSections = try c.decodeIfPresent([String].self, forKey: .skipSections) ?? []
        tagPattern = try c.decodeIfPresent(String.self, forKey: .tagPattern)
        acknowledgedStaleEntry = try c.decodeIfPresent(
            String.self, forKey: .acknowledgedStaleEntry)
        feedPagePattern = try c.decodeIfPresent(String.self, forKey: .feedPagePattern)
    }
}

/// The verified recipe table. Looked up by bundle id when the detail window opens;
/// a miss simply means we keep the existing behavior (embed `changelogURL` in a
/// web view). Adding a recipe is the same loop as a vendor probe: confirm it
/// extracts real entries from the live page (see `ChangelogExtractorTests`) before
/// landing it here.
public enum ChangelogRecipeRegistry {
        // The same feed for the two prerelease tracks, with
    // `includesPromotedStable` — which is the ladder, expressed in a field
    // that already existed. `decodeGitHubReleases` shows non-stable channels
    // the prereleases PLUS the releases that graduated, and "the newest build
    // from tracks 0…N" is exactly that: a beta copy is offered whichever of
    // the beta and release lines is newer, so the pane has to be able to hold
    // both or it omits the very entry the row offers.
    //
    // Without these two, `recipe(forBundleID:channel:)` walks past the exact
    // match it cannot find and lands on the `.stable` recipe above rather than
    // on nil, so a beta copy got a list filtered to release builds —
    // containing the offered version only while release leads, about a quarter
    // of each cycle.
    //
    // ⚠️ WHAT THIS LISTS THAT IT SHOULD NOT, measured on the newest 40
    // releases (2026-09-07): 9 are stable and 31 are prereleases, and GitHub
    // marks all 31 the same way — it has no idea which track a build is on.
    // Cross-referenced against the vendor's own `beta` numbers, those 31 are
    // 12 guinea pig, 7 beta, and 12 that the vendor's feed does not list at
    // all (2.24.11 is one: built as stable, published as a GitHub prerelease,
    // on no track). So a beta reader sees guinea pig entries too, and both
    // readers see builds the vendor never announced.
    //
    // ⚠️ AND IT DOES NOT REMOVE THAT FAILURE ENTIRELY, only most of it. The
    // version comes from the vendor's feed and the notes come from GitHub,
    // and those two do not hold the same set of releases: of the 70 versions
    // the vendor has listed since 2024, three have no GitHub release at all
    // (2.21.1 guinea pig, 2.20.6 beta, 2.15.9 release). Each was the newest
    // on its track for a while, so in those windows the row offers a version
    // this pane cannot show — the same shape as before, at roughly 4% instead
    // of the ~75% it does fix. Worth knowing before reading an occasionally
    // empty-looking pane as a parser bug. The proper fix removes this too,
    // since the vendor's feed is by construction the set the probe reads.
    //
    // Shipped anyway because the failure it replaces is worse — a pane that
    // omits the release being offered three quarters of the time — and
    // because the precise fix is a different endpoint, not a better pattern:
    // the vendor's
    // `ChangeLogs?platform=osx` states each entry's track, but it 403s
    // without an `Authorization` header that `ChangelogRecipe` has no field
    // for, and its notes are markdown escaped inside a JSON string, which
    // wants its own `structuredFormat` rather than a regex. See the audit.
    public static let recipes: [ChangelogRecipe] = AppRecipeIndex.all.flatMap(\.changelogs)

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
    ///   3. the `.stable` recipe (an unknown/odd channel still gets *some* notes
    ///      rather than none);
    ///   4. failing all of those, the group's first recipe in declaration order.
    /// Step 4 is not a rounding error: a bundle id whose recipes are ALL on
    /// non-stable channels (a preview-only app, like Zed Preview or Warp Preview)
    /// has nothing for steps 2 and 3 to find, so without it an off-channel lookup
    /// returns nil and an app that HAS notes shows none. Reasoning as though the
    /// ladder stopped at step 3 gives the wrong answer for exactly those groups —
    /// two comments in this file did, which is why the property is now pinned by
    /// `ChangelogURLPolicyTests.aGroupWithNoStableRecipeStillResolves` (derived
    /// from the registry, so a new preview-only app is covered the day it lands).
    /// Passing `channel: nil` skips step 1 and lands on step 2/3/4 — the behavior
    /// the old single-arg lookup had. Step 0 is inert for every group whose
    /// recipes declare no window, which is all of them but Raycast's.
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

    /// The entry shape both Qoder release-note pages render. Shared for the same
    /// reason `workBuddyEntryPattern` is: the two pages come off one docs build,
    /// so a fix applied to one and not the other would leave the two products
    /// silently disagreeing about which releases they can show.
    ///
    /// The `Qoder ` prefix is optional because only the app's page carries it
    /// ("Qoder 0.1.8" vs the IDE's bare "1.28.0").
    /// Tempered dots, not plain `.*?`, for the reason `workBuddyEntryPattern`
    /// spells out below — and it is not hypothetical here either. Every gap
    /// refuses to cross the NEXT release's `update-label` (see `qoderEntryGap`;
    /// that label sits INSIDE the next release's container, so a gap can and does
    /// cross the container's opening tag — an earlier draft of this sentence said
    /// otherwise and contradicted the sentinel it was describing).
    /// With a plain `.*?`, an entry missing any one of its three parts
    /// does not merely fail to parse: the pattern reaches forward into the next
    /// release for the part it could not find, so the newest release's date is
    /// shown against the second-newest's version AND the newest release
    /// disappears from the pane entirely. Measured on the real IDE page with one
    /// `update-description` attribute renamed: the plain form returns a single
    /// entry reading `1.27.0 / September 2, 2026` — a version and a date from two
    /// different releases — where the tempered form correctly returns
    /// `1.27.0 / August 29, 2026`. (On the LIVE page both forms return 107 further
    /// entries after that one; "a single entry" is what the two-entry fixture
    /// gives. The straddle is the same either way.) On the undamaged pages the two
    /// are identical — 108 matches, same versions, same items — so this costs
    /// nothing. It is also 19x faster on the failure path, where a plain `.*?`
    /// backtracks: 1.03 s against 0.055 s with every `update-description` renamed.
    static let qoderEntryPattern =
        #"data-component-part="update-label">(?<date>[^<]{3,40})</div>"#
        + qoderEntryGap + #"data-component-part="update-description">"#
        + #"(?:Qoder\s+)?(?<version>[0-9]+(?:\.[0-9]+)+)</div>"#
        + qoderEntryGap + #"data-component-part="update-content">"#
        + #"(?<body>"# + qoderEntryGap + #")</div></div></div>"#

    /// "Any run of characters that does not reach the next release's label."
    ///
    /// Tempered on `data-component-part`, not on the `update update-container`
    /// class the entries sit in. The class works on today's page and is the wrong
    /// thing to depend on: this recipe's whole stated contract is that it reads
    /// the vendor's semantic attributes rather than its Tailwind soup, and a
    /// sentinel taken from the soup decays silently — rename that class and the
    /// gap degrades back to `.*?`, with no parse failure and no test failure to
    /// say so. Measured on the real page: with the class renamed AND an entry
    /// damaged, the class-tempered form returns `1.27.0 / September 2, 2026`
    /// again, while this one still returns `1.27.0 / August 29, 2026`. On the
    /// undamaged pages the two are identical.
    ///
    /// ⚠️ The third use of this, inside `(?<body>…)`, is a different bet from the
    /// other two: the body is already bounded by `</div></div></div>`, so the
    /// sentinel there is not a "next entry" boundary. It cuts both ways and both
    /// were constructed. Against it: an entry whose note text legitimately
    /// contains the literal `data-component-part="update-label"` is dropped
    /// (108 → 107) where a plain body gap would keep it. For it: mangle an entry's
    /// `</div></div></div>` terminator and a plain body gap silently renders that
    /// release's version and date carrying its own bullets AND the next release's,
    /// while the next release disappears from the pane — the failure this whole
    /// pattern exists to prevent, and worse than a dropped entry. The second is a real
    /// shape a docs generator can produce; the first requires the vendor to write
    /// our own sentinel into prose.
    private static let qoderEntryGap =
        #"(?:(?!data-component-part="update-label").)*?"#

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
