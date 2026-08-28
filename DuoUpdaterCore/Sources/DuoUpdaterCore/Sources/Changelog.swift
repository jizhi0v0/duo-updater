import Foundation

/// A normalized, render-ready changelog: the *output* of running a
/// `ChangelogRecipe` against a vendor's changelog page. The detail window renders
/// this natively (version headers + bulleted lists), so the app never has to
/// embed a vendor's own page styling — which is how we sidestep the "white text
/// on white background / content cut off" problems some pages show in a bare
/// `WKWebView`.
///
/// `Codable` on purpose: this is the shape an offline pipeline can pre-compute and
/// (later) ship in a remote catalog, and it's also what `ChangelogExtractor`
/// produces on-device. Either way the renderer only ever sees this struct.
public struct Changelog: Codable, Sendable, Hashable {

    /// The extraction logic's generation. `ChangelogDiskCache` stamps every entry
    /// it writes with this number and treats a stored entry whose number doesn't
    /// match the running build's as a miss — falls through to the network, exactly
    /// like a cold cache (see `ChangelogDiskCache`). That's what lets a parser fix
    /// reach a version whose notes were already cached under the OLD logic: without
    /// this, an entry written by an older build is served forever for that exact
    /// version, no matter what `ChangelogExtractor`, `StructuredChangelogDecoder`,
    /// or `GitHubMarkdownParser` have learned since (issue #112).
    ///
    /// **Bump this whenever a change to any of those three files could change what
    /// a PREVIOUSLY-parsed version's `Changelog` would come out as** — a change to
    /// parsing/extraction *rules*, not merely support for a newly-encountered vendor
    /// shape that no cached entry could have hit. Each of those files carries a
    /// pointer comment back here for exactly this reason: the constant living only
    /// in the cache file, which a parser author has no reason to ever open, is the
    /// same hand-maintained-list failure this codebase has already been bitten by
    /// (see `VendorProbeRecipe.channelAnchorSurface`'s doc comment).
    ///
    /// One line per bump — what changed and why:
    /// - 1: baseline. Introduced with the generation field itself (issue #112); no
    ///   prior bump history exists because the field didn't. Ships as of this
    ///   commit already carrying the `GitHubMarkdownParser.isImageOnly` HTML `<img>`
    ///   arm (`9963e3e`), so that fix is folded into generation 1 rather than
    ///   triggering a bump on its own.
    public static let parserGeneration = 1

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
    /// before it gets here, and an older cached `Changelog` (this type is
    /// `Codable` and lands on disk) decodes without the key.
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
        /// images — so a text-only consumer never needs to walk `content`.
        public let items: [String]
        /// Notes and illustration images in their original document order. Empty for
        /// the common (text-only) case, where the renderer just bullets `items`.
        /// Populated only when a recipe sets `imagePattern` AND the entry actually
        /// embeds an image — then the renderer walks this so a screenshot lands
        /// between the change lines exactly as it does on the vendor's page (WeChat).
        public let content: [Block]

        /// One ordered piece of a rich entry: a change line, or an embedded image.
        public enum Block: Codable, Sendable, Hashable {
            case note(String)
            case image(URL)
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

        // Custom decode so entries cached before `content` existed still decode —
        // a missing key falls back to empty rather than throwing.
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
