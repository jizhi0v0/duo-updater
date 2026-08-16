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
