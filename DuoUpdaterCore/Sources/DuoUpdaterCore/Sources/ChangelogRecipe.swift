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

    public enum Mode: String, Codable, Sendable { case html, json }

    public init(
        bundleID: String,
        source: URL,
        entryPattern: String,
        itemPatterns: [String],
        mode: Mode = .html,
        stripTags: Bool = true,
        decodeEntities: Bool = true,
        maxEntries: Int? = 40,
        minItemLength: Int = 1,
        indexLinkPattern: String? = nil,
        channel: ReleaseChannel? = nil,
        sourceTemplate: String? = nil,
        newestLast: Bool = false
    ) {
        self.bundleID = bundleID
        self.source = source
        self.entryPattern = entryPattern
        self.itemPatterns = itemPatterns
        self.mode = mode
        self.stripTags = stripTags
        self.decodeEntities = decodeEntities
        self.maxEntries = maxEntries
        self.minItemLength = minItemLength
        self.indexLinkPattern = indexLinkPattern
        self.channel = channel
        self.sourceTemplate = sourceTemplate
        self.newestLast = newestLast
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
        let urlString = sourceTemplate.replacingOccurrences(of: "{version}", with: token)
        return URL(string: urlString) ?? source
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
        entryPattern = try c.decode(String.self, forKey: .entryPattern)
        itemPatterns = try c.decode([String].self, forKey: .itemPatterns)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .html
        stripTags = try c.decodeIfPresent(Bool.self, forKey: .stripTags) ?? true
        decodeEntities = try c.decodeIfPresent(Bool.self, forKey: .decodeEntities) ?? true
        maxEntries = try c.decodeIfPresent(Int?.self, forKey: .maxEntries) ?? 40
        minItemLength = try c.decodeIfPresent(Int.self, forKey: .minItemLength) ?? 1
        indexLinkPattern = try c.decodeIfPresent(String.self, forKey: .indexLinkPattern)
        channel = try c.decodeIfPresent(ReleaseChannel.self, forKey: .channel)
        sourceTemplate = try c.decodeIfPresent(String.self, forKey: .sourceTemplate)
        newestLast = try c.decodeIfPresent(Bool.self, forKey: .newestLast) ?? false
    }
}

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

        // ChatWise — the /changelog page hydrates client-side from the public
        // releases JSON endpoint. The current payload order is:
        //   {"version":"26.5.3","changelog":"- Add Claude Opus 4.8...\\n",
        //    "assets":[...],"date":"2026-05-29T07:02:44.116Z"}
        // Notes are markdown bullet lines, so keep tags intact and split on `- `.
        // We match the fields in the order the live endpoint currently emits them;
        // a parse miss simply falls back to the page link, so shipping coverage is
        // still the right bias here.
        ChangelogRecipe(
            bundleID: "app.chatwise",
            source: URL(string: "https://releases.chatwise.app/releases")!,
            entryPattern:
                #"\{\s*"version"\s*:\s*"(?<version>[^"]+)".*?"changelog"\s*:\s*"(?<body>(?:\\.|[^"\\])*)".*?"date"\s*:\s*"(?<date>[^"]+)""#,
            itemPatterns: [
                #"(?:^|\\n)-\s*(?<item>.*?)\s*(?=\\n-\s|\\n?$)"#,
                #"\s*(?<item>.+?)\s*$"#
            ],
            mode: .json,
            stripTags: false,
            decodeEntities: false,
            maxEntries: 20),

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
        ChangelogRecipe(
            bundleID: "com.openai.codex",
            source: URL(string: "https://developers.openai.com/codex/changelog?type=codex-app")!,
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

        // CleanShot X — Nuxt page, very regular markup:
        //   <div class="version"><div class="number">4.8.8</div>
        //     <div class="date">23 March, 2026</div>
        //     <ul class="changes"><li class="change">…</li>…</ul></div>
        ChangelogRecipe(
            bundleID: "pl.maketheweb.cleanshotx",
            source: URL(string: "https://cleanshot.com/changelog")!,
            entryPattern:
                #"<div class="version"[^>]*>\s*"#
                + #"<div class="number"[^>]*>(?<version>[^<]+)</div>\s*"#
                + #"(?:<div class="date"[^>]*>(?<date>[^<]*)</div>\s*)?"#
                + #"<ul[^>]*class="changes"[^>]*>(?<body>.*?)</ul>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

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

        // AweSun (Oray) — same JSON API as the VendorProbeRecipe. The response is a
        // top-level object; its `logs` array has one element per release. Each element
        // has an HTML `logs` field (<ol><li>version<\/li><li>item…<\/li>…<\/ol>) and
        // an ISO-date `updatedate`. Non-ASCII text is \uXXXX-encoded in the raw JSON;
        // `decodeEntities` resolves those via the JSON-Unicode-escape pass.
        ChangelogRecipe(
            bundleID: "com.oray.sunlogin.macclient",
            source: URL(string: "https://client-webapi.oray.com/softwares/SUNLOGIN_X_MAC_ARM?versiontype=stable")!,
            entryPattern:
                #""logid":\d+.*?"logs":"<ol><li>(?<version>[^<]+)<\\/li>(?<body>.*?)<\\/ol>".*?"updatedate":"(?<date>\d{4}-\d{2}-\d{2})"#,
            itemPatterns: [#"<li>(?<item>.*?)<\\/li>"#],
            mode: .json),

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
        // Items are <li class="...weightRegular..."> in the Full Changelog section
        // (id="full-changelog-2"), which follows the Highlights prose.
        ChangelogRecipe(
            bundleID: "com.mitchellh.ghostty",
            source: URL(string: "https://ghostty.org/docs/install/release-notes")!,
            entryPattern:
                #"<meta name="description" content="Release notes for Ghostty (?<version>[^,]+), released on (?<date>[^.]+)\."[^>]*>"#
                + #".*?"#
                + #"id="full-changelog-2">.*?</div></div>\s*(?<body>.*?)</main>"#,
            itemPatterns: [
                #"<li class="[^"]*weightRegular[^"]*">(?<item>.*?)</li>"#,
            ],
            indexLinkPattern: #"href="(?<link>/docs/install/release-notes/\d[^"]*)""#),

        // Postman — CDN-hosted JSON array under the "notes" key. Each element has
        // "version", "content" (Markdown, \\r\\n line separators in raw JSON), and
        // "createdAt" (ISO-8601). itemPattern strips the #### feature-heading prefix
        // and skips ## / ### section headers and the trailing date line; plain
        // description lines that follow a heading are also captured.
        ChangelogRecipe(
            bundleID: "com.postmanlabs.mac",
            source: URL(string: "https://mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json")!,
            entryPattern:
                #""version"\s*:\s*"(?<version>[^"]+)""#
                + #".*?"content"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#
                + #".*?"createdAt"\s*:\s*"(?<date>[^"T]+)"#,
            itemPatterns: [
                #"\\r\\n(?:####\s+)?(?!##|\\r\\n|\w+ \d+, \d{4})(?<item>[^\\]{10,})"#,
            ],
            mode: .json,
            stripTags: false,
            decodeEntities: false,
            maxEntries: 30),

        // HBuilderX (DCloud) — two-stage, and deliberately NOT pointed at
        // update.dcloud.net.cn: that host 302s the changelog HTML to a per-request
        // tokenized CDN node on a non-standard port (…qrstuvwxyzab.com:22443),
        // which under many networks crawls past the 15s fetch timeout — the app
        // then spins and degrades to the embedded web page. The download-site host
        // download1.dcloud.net.cn serves the very same HTML directly (200, no
        // redirect, ~0.3s), so we go there instead.
        //
        // `source` is the download page's `release.json` config; `indexLinkPattern`
        // follows its `release` field to the current changelog page on download1.
        // That field always names the latest build, so this also retires the old
        // version-pinned URL — a new HBuilderX release is picked up with no rebuild
        // (same win as VLC/Ghostty). The detail page is a cumulative list: each
        // release is an <h2>X.Y.Z</h2> (the build encodes YYYYMMDD, no separate
        // date), then module-section <h3>s and <li> change items.
        ChangelogRecipe(
            bundleID: "io.dcloud.HBuilderX",
            source: URL(string: "https://download1.dcloud.net.cn/hbuilderx/release.json")!,
            entryPattern:
                #"<h2[^>]*>(?<version>[0-9]+\.[0-9]+\.[0-9]+)</h2>"#
                + #"(?<body>.*?)"#
                + #"(?=<h2[^>]*>[0-9]|$)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            // The page is a years-long cumulative list (~28 builds, each with many
            // module-section items); cap to the recent handful — the detail view
            // only needs "what changed lately", and this also halts the parse early.
            maxEntries: 10,
            minItemLength: 4,
            indexLinkPattern: #""release"\s*:\s*"(?<link>https://[^"]+)""#),

        // HBuilderX Alpha (DCloud) — the alpha is a SEPARATE app (bundle id
        // io.dcloud.HBuilderXAlpha, ships as HBuilderX-Alpha.app), so it needs its
        // own recipe; the stable io.dcloud.HBuilderX one never matches it. Same
        // two-stage shape as stable but reading `alpha.json`, whose `release` field
        // points at the alpha changelog page on download1. The page is structured
        // exactly like the stable one except every version <h2> carries an "-alpha"
        // suffix (5.11.2026052520-alpha), so the version group requires it — which
        // also means a stray stable <h2> could never be mis-captured here.
        ChangelogRecipe(
            bundleID: "io.dcloud.HBuilderXAlpha",
            source: URL(string: "https://download1.dcloud.net.cn/hbuilderx/alpha.json")!,
            entryPattern:
                #"<h2[^>]*>(?<version>[0-9]+\.[0-9]+\.[0-9]+-alpha)</h2>"#
                + #"(?<body>.*?)"#
                + #"(?=<h2[^>]*>[0-9]|$)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            // Alpha lists 60+ builds; same cap as stable — recent handful only.
            maxEntries: 10,
            minItemLength: 4,
            indexLinkPattern: #""release"\s*:\s*"(?<link>https://[^"]+)""#),

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

        // Zed Preview — zed.dev/releases/preview is a fully server-rendered page
        // with all recent pre-release versions inline. Each version block is a
        // <div id="zed-X.Y.Z"> with a two-cell header (version + date) and an
        // <article> containing the notes — either a simple <ul><li>…</li></ul>
        // for patch releases, or section <h2>/<h3> + nested <ul> for weekly
        // feature releases. The item pattern picks up all <li> regardless of
        // nesting depth. Entries with no <li> items (e.g. "No public-facing
        // changes…") naturally produce zero items and are silently skipped.
        ChangelogRecipe(
            bundleID: "dev.zed.Zed-Preview",
            source: URL(string: "https://zed.dev/releases/preview")!,
            entryPattern:
                #"id="zed-(?<version>\d+\.\d+\.\d+)"[^>]*>.*?"#
                + #"<p[^>]*whitespace-nowrap[^>]*>(?<date>[^<]+)</p>"#
                + #".*?(?<body><article[^>]*>.*?</article>)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                // Fallback for "no public-facing changes" entries that have
                // only a <p> note and no <li> items.
                #"<p[^>]*>(?<item>.+?)</p>"#,
            ],
            maxEntries: 15),

        // Zed Stable — identical page structure, different channel URL.
        ChangelogRecipe(
            bundleID: "dev.zed.Zed",
            source: URL(string: "https://zed.dev/releases/stable")!,
            entryPattern:
                #"id="zed-(?<version>\d+\.\d+\.\d+)"[^>]*>.*?"#
                + #"<p[^>]*whitespace-nowrap[^>]*>(?<date>[^<]+)</p>"#
                + #".*?(?<body><article[^>]*>.*?</article>)"#,
            itemPatterns: [
                #"<li[^>]*>(?<item>.*?)</li>"#,
                #"<p[^>]*>(?<item>.+?)</p>"#,
            ],
            maxEntries: 15),

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

        // LM Studio — Next.js changelog index. The /changelog index page already
        // carries the *full* release notes for the latest ~10 versions inline
        // (the visible truncation is a CSS mask only; the markup is complete), so
        // we parse it directly rather than the per-version pages. Each entry is:
        //   <a href="/changelog/lmstudio-v0.4.15">
        //     <span class="sr-only">LM Studio 0.4.15</span></a>
        //   …<div class="markdown-body …"><p><strong>Build 2</strong></p>
        //     <ul class="list-disc"><li>…</li>…</ul>…</div></div></div>
        // No per-entry date is printed on the index, so `date` is omitted. Notes
        // use nested <ul> for sub-bullets; the <li> pattern folds a sub-list into
        // its parent line — cosmetically fine, and a miss just falls back to the
        // embedded page.
        ChangelogRecipe(
            bundleID: "ai.elementlabs.lmstudio",
            source: URL(string: "https://lmstudio.ai/changelog")!,
            entryPattern:
                #"href="/changelog/lmstudio-v[^"]*">\s*"#
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

        // Warp — official Starlight-rendered changelog at docs.warp.dev/changelog/2026/.
        // Each entry is a `<div class="sl-heading-wrapper level-h3">` containing an
        // `<h3>` with heading text `YYYY.MM.DD (v0.YYYY.MM.DD.HH.MM)`. The pattern
        // requires the `(v…)` version qualifier, so the rare date-only headings (no
        // build info) are gracefully skipped. Items are plain `<li>` within the
        // `<ul>` blocks that follow. NOTE: URL is year-pinned; update to `/2027/`
        // when the new year's page goes live — same as the Ghostty version-pin pattern.
        ChangelogRecipe(
            bundleID: "dev.warp.Warp-Stable",
            source: URL(string: "https://docs.warp.dev/changelog/2026/")!,
            entryPattern:
                #"<div class="sl-heading-wrapper level-h3">\s*"#
                + #"<h3[^>]*>(?<date>\d{4}\.\d{2}\.\d{2})\s*\(v(?<version>[\d.]+)\)"#
                + #".*?</h3>.*?</div>\s*(?<body>.*?)"#
                + #"(?=<div class="sl-heading-wrapper level-h3"|$)"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            maxEntries: 20),

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

        // Notion — www.notion.com/releases is Notion's *product* changelog: a
        // server-rendered Next.js page of dated feature posts, NOT the desktop
        // app's build version. There is no build number on the page, so the post
        // title is used as the `version` string (e.g. "Plan Mode"). Acceptable
        // because this is the low-stakes changelog tier — a miss just falls back
        // to embedding the page. (notion.so/releases 301s here; /help/whats-new
        // 404s.) Each post is:
        //   <article class="release_release__…">
        //     <time class="release_date__…">May 26, 2026</time>
        //     <a class="release_titleLink__…"><h2 class="… release_title__…">Title</h2></a>
        //     <article class="contentfulRichText_richText__…">
        //       <p class="contentfulRichText_paragraph__…">…note…</p> …</article>
        //   </article>
        // Items target <p class="contentfulRichText_paragraph__…"> — a class the
        // decorative <p class="videoPlayer_errorLine__…"> ad-blocker notices do
        // NOT share, so they're skipped. The inner contentfulRichText article also
        // closes with </article>, so the body bounds on the next release article.
        ChangelogRecipe(
            bundleID: "notion.id",
            source: URL(string: "https://www.notion.com/releases")!,
            entryPattern:
                #"<article class="release_release__[^"]*">.*?"#
                + #"<time class="release_date__[^"]*">(?<date>[^<]+)</time>.*?"#
                + #"<h2 class="[^"]*release_title__[^"]*">(?<version>.*?)</h2>"#
                + #"(?<body>.*?)(?=<article class="release_release__|</main>|<footer)"#,
            itemPatterns: [
                #"<p class="contentfulRichText_paragraph__[^"]*">(?<item>.*?)</p>"#,
            ],
            maxEntries: 20,
            minItemLength: 4),

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

        // Figma (desktop) — figma.com/release-notes is Figma's *product*
        // release-notes feed (Figma Design / Make / FigJam announcements), NOT
        // desktop-app build notes: there is no per-entry app version. The desktop
        // build version lives only at desktop.figma.com/mac/RELEASE.json with no
        // human notes, so this product feed is the best changelog surface; a parse
        // miss just falls back to embedding the page (low stakes). The page is
        // fully server-rendered. Each post is an <article> with
        //   <time dateTime="Jun 3, 2026">…</time><h2>Title</h2>…<p>…</p>…
        // We surface the post title as the entry "version" and the post date as
        // `date`. Figma's CSS class names are hashed per deploy (fig-XXXX), so we
        // anchor ONLY on generic tags. The item pattern requires <p + whitespace/`>`
        // so it cannot match the SVG <path> elements inside the "Copy link" button.
        ChangelogRecipe(
            bundleID: "com.figma.Desktop",
            source: URL(string: "https://www.figma.com/release-notes/")!,
            entryPattern:
                #"<article[^>]*>.*?"#
                + #"<time[^>]*dateTime="(?<date>[^"]+)"[^>]*>[^<]*</time>\s*"#
                + #"<h2[^>]*>(?<version>.*?)</h2>"#
                + #"(?<body>.*?)</article>"#,
            itemPatterns: [#"<p(?:\s[^>]*)?>(?<item>.*?)</p>"#],
            maxEntries: 20),

        // 1Password 8 (Mac) — releases.1password.com/mac/stable/ is the STABLE
        // channel notes page (the bare /mac/ landing page is only a two-card hub —
        // latest beta + latest stable — with no change items; the beta channel
        // lives at the sibling /mac/beta/). Fully server-rendered, all recent
        // 8.12.x releases inline, newest-first. Each release is:
        //   <article class="c-updates__release …">…<time …class="…c-updates__date …">
        //     June 2 2026</time><h6 class="…c-updates__title">1Password for Mac 8.12.22</h6>
        //   …<div class="…c-updates__content …"><ul><li>…</li>…</ul></div></article>
        // We capture the *visible* date text from <time> rather than the datetime
        // attr, whose value is a space-separated timestamp ("… 00:00:00 +0000 UTC")
        // that would display ugly. Items keep their trailing GitLab issue refs
        // (!37801 / #DESK-541) inline as the vendor writes them — the page's
        // "Show issue numbers" toggle only hides them via CSS.
        ChangelogRecipe(
            bundleID: "com.1password.1password",
            source: URL(string: "https://releases.1password.com/mac/stable/")!,
            entryPattern:
                #"<article class="c-updates__release[^"]*"[^>]*>.*?"#
                + #"<time[^>]*class="[^"]*c-updates__date[^"]*"[^>]*>(?<date>[^<]+)</time>\s*"#
                + #"<h6[^>]*c-updates__title[^>]*>1Password for Mac\s*(?<version>[\d.]+)\s*</h6>.*?"#
                + #"<div[^>]*c-updates__content[^>]*>(?<body>.*?)</div>\s*</article>"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),

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
            entryPattern:
                #"title='Stable Channel Update for Desktop'>.*?"#
                + #"<span class='publishdate'[^>]*>\s*(?<date>[^<]+?)\s*</span>.*?"#
                + #"<script type='text/template'>\s*"#
                + #"(?<body>.*?(?<version>\d+\.\d+\.\d+\.\d+).*?)</script>"#,
            itemPatterns: [
                #"(?<item>CVE-\d{4}-\d+:[^<]*)"#,
                #"<p[^>]*>(?<item>(?:(?!</p>).)*?(?:promotion of Chrome|been updated to)(?:(?!</p>).)*?)</p>"#,
            ],
            minItemLength: 8),

        // TablePro — docs.tablepro.app/changelog is a Mintlify changelog page,
        // fully server-rendered with every release inline (newest-first). Each
        // release is a labeled block:
        //   <div … data-component-part="update-label">June 2, 2026</div>
        //   <div … data-component-part="update-description">v0.48.0</div>
        //   <div … data-component-part="update-content"><h3>New Features</h3>
        //     <ul><li><strong>JSON Import</strong>: …</li>…</ul>…</div>
        // The label div is the date, the description div the version (leading "v"
        // dropped), the content div the body. The <h3> section headings are
        // ignored; only <li> items surface. Body bounds on the next update-label.
        ChangelogRecipe(
            bundleID: "com.TablePro",
            source: URL(string: "https://docs.tablepro.app/changelog")!,
            entryPattern:
                #"data-component-part="update-label"[^>]*>(?<date>[^<]+)</div>"#
                + #".*?data-component-part="update-description"[^>]*>v?(?<version>[\d.]+)</div>"#
                + #".*?data-component-part="update-content"[^>]*>(?<body>.*?)"#
                + #"(?=<div[^>]*data-component-part="update-label"|$)"#,
            itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
            maxEntries: 20),

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
        // product code, stable releases only via `type=release`). Each entry's
        // `whatsnew` is well-structured HTML: a lead `<p>` summary then `<ul><li>`
        // bug/feature bullets with YouTrack links. The item pattern sweeps `<li>`
        // only — the lead `<p>` ("IntelliJ IDEA X is out with…") is a boilerplate
        // intro, not a discrete change line, so skipping it is cleaner. Major
        // releases (2026.1) carry a richer `whatsnew` with `<strong>` section
        // headings inside `<p>` tags; those section labels are short enough to
        // read as items, so the `<li>` pattern suffices for both shapes.
        ChangelogRecipe(
            bundleID: "com.jetbrains.intellij",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=IIU&type=release")!,
            entryPattern:
                #""date"\s*:\s*"(?<date>\d{4}-\d{2}-\d{2})".*?"#
                + #""version"\s*:\s*"(?<version>[^"]+)".*?"#
                + #""whatsnew"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            mode: .json,
            maxEntries: 20),

        // JetBrains Toolbox App — JetBrains publishes no public changelog page
        // (long-requested: YouTrack TBX-2807), but the official product-releases
        // API the download site itself uses returns the full history as JSON. The
        // `TBA` product code is the Toolbox App; each element of the TBA array is
        // one release with `version` ("3.5"), `build` ("3.5.0.84344"), `date`, and
        // a `whatsnew` HTML string. Fields run date … version … build … whatsnew,
        // so the entry anchors date→version→whatsnew. The whatsnew HTML mixes <h4>
        // section headings with <p> feature paragraphs and <ul><li> bullet lists,
        // so the single item pattern sweeps BOTH <p> and <li> (the <h4> labels are
        // skipped) and a negative lookahead drops the trailing "See the full list…"
        // footer <p>. Older releases omit whatsnew and are silently skipped; the
        // top entries we keep all carry it and stay correctly attributed.
        ChangelogRecipe(
            bundleID: "com.jetbrains.toolbox",
            source: URL(string: "https://data.services.jetbrains.com/products/releases?code=TBA")!,
            entryPattern:
                #""date"\s*:\s*"(?<date>\d{4}-\d{2}-\d{2})".*?"#
                + #""version"\s*:\s*"(?<version>[^"]+)".*?"#
                + #""whatsnew"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [#"<(?:li|p)>\s*(?!See the full list)(?<item>.*?)</(?:li|p)>"#],
            mode: .json,
            maxEntries: 20),

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
        // `version` is LAST in each object, so the entry pattern walks name→notes→
        // pub_date→version in document order; `body` is the notes array, sliced into
        // items by the JSON-string pattern (each note keeps its `[Fixed]`/`[Added]`
        // prefix and trailing `- #issue`). Stable feed carries bare `3.5.12`; beta
        // carries `3.5.12-beta2`. JSON mode + decodeEntities unescapes the `\"` some
        // beta notes contain. A parse miss just falls back to embedding the SPA.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json")!,
            entryPattern:
                #"\{"name":"[^"]*","notes":\[(?<body>.*?)\],"#
                + #""pub_date":"(?<date>\d{4}-\d{2}-\d{2})[^"]*","version":"(?<version>[^"]+)"\}"#,
            itemPatterns: [#""(?<item>(?:\\.|[^"\\])*)""#],
            mode: .json,
            stripTags: false,
            channel: .stable),

        // GitHub Desktop Beta — same feed with `?env=beta`, matched by `channel:
        // .beta` so a `-betaN`-detected install gets beta notes (`3.5.12-beta2`)
        // instead of the stable train. Identical structure/patterns.
        ChangelogRecipe(
            bundleID: "com.github.GitHubClient",
            source: URL(string: "https://central.github.com/deployments/desktop/desktop/changelog.json?env=beta")!,
            entryPattern:
                #"\{"name":"[^"]*","notes":\[(?<body>.*?)\],"#
                + #""pub_date":"(?<date>\d{4}-\d{2}-\d{2})[^"]*","version":"(?<version>[^"]+)"\}"#,
            itemPatterns: [#""(?<item>(?:\\.|[^"\\])*)""#],
            mode: .json,
            stripTags: false,
            channel: .beta),

        // Alcove — same endpoint the VendorProbeRecipe reads (update.tryalcove.com),
        // a single GitHub-release-shaped JSON object: `tag_name` is the version,
        // `published_at` an ISO timestamp (date prefix taken), `body` a Markdown
        // changelog with `## section` headers and `- bullet` lines. We flatten every
        // bullet across sections into change lines (headers are skipped — they aren't
        // `- ` items); newlines arrive escaped as `\n`, so the item pattern matches
        // `\\n` like the chatwise/GitHub Desktop JSON recipes. stripTags/decode off
        // (plain Markdown, no HTML); the leading emoji on section headers never
        // reaches an item, so the `\u….` escapes in the body are harmless.
        ChangelogRecipe(
            bundleID: "com.henrikruscon.Alcove",
            source: URL(string: "https://update.tryalcove.com")!,
            entryPattern:
                #""tag_name"\s*:\s*"(?<version>[0-9][^"]*)".*?"#
                + #""published_at"\s*:\s*"(?<date>\d{4}-\d{2}-\d{2})[^"]*".*?"#
                + #""body"\s*:\s*"(?<body>(?:\\.|[^"\\])*)""#,
            itemPatterns: [#"(?:^|\\n)-\s*(?<item>.*?)\s*(?=\\n-\s|\\n\\n|\\n#|$)"#],
            mode: .json,
            stripTags: false,
            decodeEntities: false,
            maxEntries: 20),
    ]

    /// Group recipes by lowercased bundle id. Most bundle ids map to a single
    /// recipe; a few (Thunderbird Stable + ESR) map to several that differ by
    /// `channel`. Order within a group preserves declaration order.
    private static let byBundleID: [String: [ChangelogRecipe]] = Dictionary(
        grouping: recipes, by: { $0.bundleID.lowercased() })

    /// The recipe for an app on a given channel, if we have one. Case-insensitive
    /// on bundle id, to match `ChangelogCatalog`'s convention.
    ///
    /// Selection within a bundle id's group, in order of preference:
    ///   1. a recipe whose `channel` exactly matches the install's channel;
    ///   2. a channel-agnostic recipe (`channel == nil`) — every existing
    ///      single-recipe app, so passing a channel never changes their result;
    ///   3. the `.stable` recipe as a last resort (an unknown/odd channel still
    ///      gets *some* notes rather than none).
    /// Passing `channel: nil` skips step 1 and lands on step 2/3 — the behavior the
    /// old single-arg lookup had.
    public static func recipe(
        forBundleID bundleID: String?, channel: ReleaseChannel? = nil
    ) -> ChangelogRecipe? {
        guard let bundleID else { return nil }
        let group = byBundleID[bundleID.lowercased()] ?? []
        if let channel, let exact = group.first(where: { $0.channel == channel }) {
            return exact
        }
        return group.first(where: { $0.channel == nil })
            ?? group.first(where: { $0.channel == .stable })
            ?? group.first
    }

    /// Every recipe registered for a bundle id (across channels). Used to clear all
    /// channel variants' caches on update — see `AppListModel.invalidateChangelog`.
    public static func recipes(forBundleID bundleID: String?) -> [ChangelogRecipe] {
        guard let bundleID else { return [] }
        return byBundleID[bundleID.lowercased()] ?? []
    }
}
