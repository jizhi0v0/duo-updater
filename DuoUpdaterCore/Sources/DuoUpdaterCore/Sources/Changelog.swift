import Foundation

/// A normalized, render-ready changelog: the *output* of running a
/// `ChangelogRecipe` against a vendor's changelog page. The detail window renders
/// this natively (version headers + bulleted lists), so the app never has to
/// embed a vendor's own page styling — which is how we sidestep the "white text
/// on white background / content cut off" problems some pages show in a bare
/// `WKWebView`.
///
/// `Codable` on purpose: this is the shape an offline pipeline can pre-compute and
/// (later) ship in a remote catalog, and it's also what `ChangelogExtractor`,
/// `StructuredChangelogDecoder`, and `GitHubMarkdownParser` produce on-device —
/// the last of those directly for Homebrew formula release notes too, not only
/// for app changelogs. Either way the renderer only ever sees this struct.
public struct Changelog: Codable, Sendable, Hashable {

    /// The extraction logic's generation. TWO cross-launch disk caches stamp every
    /// entry they write with this number and treat a stored entry whose number
    /// doesn't match the running build's as a miss — falls through to the network,
    /// exactly like a cold cache: `ChangelogDiskCache` (app changelogs) and
    /// `BrewFormulaReleaseService`'s own on-disk cache (Homebrew formula release
    /// notes, which are also parsed by `GitHubMarkdownParser` — same generation,
    /// same rule, separate store — see both types' doc comments). That's what lets
    /// a parser fix reach a version whose notes were already cached under the OLD
    /// logic: without this, an entry written by an older build is served forever
    /// for that exact version, no matter what extraction has learned since
    /// (issue #112).
    ///
    /// **Bump this whenever a change could alter what a PREVIOUSLY-parsed version's
    /// `Changelog` would come out as** — a change to parsing/extraction *rules*, not
    /// merely support for a newly-encountered vendor shape that no cached entry
    /// could have hit. That covers two different kinds of change, both of which
    /// need a bump:
    /// - the extraction CODE: `ChangelogExtractor`, `StructuredChangelogDecoder`,
    ///   `GitHubMarkdownParser`;
    /// - the per-recipe DATA in `ChangelogRecipeRegistry` (`ChangelogRecipe.swift`)
    ///   that's threaded into that code and changes its output just as directly —
    ///   `entryPattern`, `itemPatterns`, `skipSections`, `stripTags`,
    ///   `escapedMarkup`, `markdownSource`, `minItemLength`, `newestLast`,
    ///   `maxEntries`, `source`, `headingPattern`, and so on. A recipe edit that
    ///   changes what an EXISTING cached version's notes would parse to (not just
    ///   what a *new* release's notes will) is exactly as invalidating as a code
    ///   change; two
    ///   already-merged commits prove it — `0d9d424` (Figma moved to a different
    ///   feed with a different `entryPattern`, same bundle id) and `a6ac16b`
    ///   (`skipSections` added, changing BetterDisplay's existing releases' output).
    ///
    /// Each of the four files above carries a pointer comment back here for exactly
    /// this reason: the constant living only in the cache file, which a parser
    /// author has no reason to ever open, is the same hand-maintained-list failure
    /// this codebase has already been bitten by (see
    /// `VendorProbeRecipe.channelAnchorSurface`'s doc comment). Unlike that surface,
    /// there is no mechanical derivation for "did extraction's output change" —
    /// parsing is a function from (recipe data, page bytes) to `Changelog`, not a
    /// field list reflection can enumerate — so the closest available mechanical
    /// guard is `ChangelogParserGenerationGuardTests`, which pins the actual parsed
    /// output of two registry-driven fixtures and fails when either moves.
    ///
    /// One line per bump — what changed and why:
    /// - 1: baseline. Introduced with the generation field itself (issue #112); no
    ///   prior bump history exists because the field didn't. Ships as of this
    ///   commit already carrying the `GitHubMarkdownParser.isImageOnly` HTML `<img>`
    ///   arm (`9963e3e`) and `ChangelogRecipe.skipSections` (`a6ac16b`), so those are
    ///   folded into generation 1 rather than triggering a bump on their own.
    /// - 2: Ollama's recipe gained a paragraph item pattern, so a release written as
    ///   prose (no bullet list) parses to an entry instead of being dropped. Notes
    ///   already cached for 0.34.0 were stored without 0.34.0's own entry.
    /// - 3: Keep a Changelog / GitHub category headings (`### Added`, `### Fixed`,
    ///   …) now survive as `.heading` blocks in `content` instead of being
    ///   silently flattened into `items` — `GitHubMarkdownParser` styles a heading
    ///   only when it has ≥2 non-boilerplate sibling headings AND contains no
    ///   digit (a version-restating heading like UTM's `Changes (v5.0.4)` or
    ///   Rockxy's `Rockxy 0.38.3 (build 58)` fails that second test and stays
    ///   folded away exactly as before); `ChangelogRecipe.headingPattern` lets a
    ///   hand-written recipe (Mac Performance Monitor) opt in unconditionally.
    ///   Notes already cached under the old logic had every group's heading
    ///   dropped with no way to tell which category a line belonged to.
    /// - 4: HTML entity decoding is one left-to-right pass instead of a loop over a
    ///   `Dictionary`, whose iteration order Swift randomises per process — so a
    ///   double-escaped note (`&amp;lt;`, a vendor showing the reader a literal
    ///   `&lt;`) decoded once on one launch and twice on the next, and whichever
    ///   reading the cache happened to catch is now wrong half the time. Typeless's
    ///   decoder also splits CRLF bodies correctly, so an entry cached from one kept
    ///   only its first note.
    public static let parserGeneration = 4

    public let entries: [Entry]

    /// What the change lines in `items` are written in, so the renderer knows
    /// whether to parse them or print them.
    ///
    /// This is declared, never sniffed. A GitHub release body is Markdown and
    /// keeps its inline syntax through `GitHubMarkdownParser` (`**bold**`,
    /// `[text](url)`); everything scraped from a web page has already had its
    /// tags stripped by `ChangelogExtractor` and is plain prose. Rendering the
    /// first as plain text shows raw `**` and bracketed URLs to the user;
    /// rendering the second as Markdown would eat any stray `*` or `_` a vendor
    /// wrote literally. Neither is recoverable from the text itself.
    public enum ItemSyntax: String, Codable, Sendable, Hashable {
        case plain
        case markdown
    }

    /// Defaults to `.plain`: every producer except the GitHub one strips markup
    /// before it gets here, and a `Changelog` encoded before this field existed
    /// decodes without the key. NO LONGER the path that protects either on-disk
    /// changelog cache, though: `ChangelogDiskCache.Stored` and
    /// `BrewFormulaReleaseService`'s own `Stored` wrapper both carry a
    /// `parserGeneration` (see `Changelog.parserGeneration`) that fails to decode
    /// FIRST for an entry old enough to predate this field — by the time
    /// `parserGeneration` existed, `itemSyntax` already did, so nothing reaches this
    /// default through either cache any more. What still needs it: the "shape an
    /// offline pipeline can pre-compute and ship in a remote catalog" this type is
    /// also `Codable` for (see the type's own doc comment), which carries no
    /// generation wrapper at all — exercised directly (bypassing both caches) by
    /// `ChangelogItemSyntaxTests.syntaxSurvivesTheDiskCacheAndOldPayloadsDecode`.
    public let itemSyntax: ItemSyntax

    public init(entries: [Entry], itemSyntax: ItemSyntax = .plain) {
        self.entries = entries
        self.itemSyntax = itemSyntax
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode([Entry].self, forKey: .entries)
        itemSyntax = try c.decodeIfPresent(ItemSyntax.self, forKey: .itemSyntax) ?? .plain
    }

    /// One released version's worth of notes.
    public struct Entry: Codable, Sendable, Hashable {
        /// Optional human-readable title for the release entry, when the vendor's
        /// changelog is organized around named posts rather than bare versions.
        /// Example: "Use Codex with Amazon Bedrock". Nil for version-centric feeds.
        public let title: String?
        /// The version string exactly as the page presents it, e.g. "4.8.8".
        public let version: String
        /// Human-readable release date as printed on the page (e.g.
        /// "23 March, 2026"); we keep it verbatim rather than parsing — it's for
        /// display only, and formats vary wildly across vendors. Nil when the page
        /// shows no date for this entry.
        public let date: String?
        /// The individual change lines, in document order. Emoji/category prefixes
        /// (✨ 🔔 🎨 …) are kept inline as the vendor wrote them. Always the full set
        /// of text lines, even when `content` also carries them interleaved with
        /// images or headings — so a text-only consumer never needs to walk
        /// `content`. A category heading (`### Added`) is NOT a change line and
        /// never appears here, styled or not — see `Block.heading`.
        public let items: [String]
        /// Notes, illustration images, and category headings in their original
        /// document order. Empty for the common (flat) case, where the renderer
        /// just bullets `items`. Populated when a recipe sets `imagePattern` AND
        /// the entry actually embeds an image (then the renderer walks this so a
        /// screenshot lands between the change lines exactly as it does on the
        /// vendor's page, WeChat) OR when at least one of the entry's headings
        /// earned a `.heading` block (see `Block.heading`) — either producer can
        /// populate this independent of the other, so an entry can carry headings
        /// with no images, images with no headings, or both.
        public let content: [Block]

        /// One ordered piece of a rich entry: a change line, an embedded image, or
        /// a category heading (`### Added`, `### Fixed`, …) worth styling as its
        /// own line rather than flattening into the notes around it. Never present
        /// in `items` — see that property's doc comment.
        public enum Block: Codable, Sendable, Hashable {
            case note(String)
            case image(URL)
            case heading(String)
        }

        public init(
            title: String? = nil, version: String, date: String?,
            items: [String], content: [Block] = []
        ) {
            self.title = title
            self.version = version
            self.date = date
            self.items = items
            self.content = content
        }

        // Custom decode so an `Entry` encoded before `content` existed still
        // decodes — a missing key falls back to empty rather than throwing. As with
        // `itemSyntax` above, this is no longer what protects either on-disk
        // changelog cache (both wrap `Changelog` in a `Stored` type whose own
        // `parserGeneration` fails to decode first for an entry this old — see
        // `Changelog.parserGeneration`'s doc comment); it remains live for the
        // generation-less remote-catalog path this type is also `Codable` for.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            version = try c.decode(String.self, forKey: .version)
            date = try c.decodeIfPresent(String.self, forKey: .date)
            items = try c.decode([String].self, forKey: .items)
            content = try c.decodeIfPresent([Block].self, forKey: .content) ?? []
        }
    }
}
