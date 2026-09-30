import Foundation

/// The block structure of a Markdown notes body (`Changelog.Entry.markdown`), for
/// a renderer that draws the author's own headings and lists rather than one
/// flattened bullet list.
///
/// Parsing is Foundation's own (`AttributedString(markdown:)` with `.full`
/// syntax), which tags every run with a `PresentationIntent` — header, list item
/// inside an (un)ordered list, code block, block quote. SwiftUI's `Text` draws
/// only the inline part of that, so this turns the tags into a flat list of
/// blocks a view can lay out one by one. Inline styling (emphasis, code spans,
/// links) stays on each block's `text` for `Text` to draw.
public enum ChangelogMarkdown {

    public struct Block: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case heading(level: Int)
            case paragraph
            /// `depth` is 1 for a top-level item. `marker` is "•" or "3." — nil
            /// for a later paragraph of an item already drawn, which is indented
            /// like the item but carries no marker of its own.
            case listItem(depth: Int, marker: String?)
            case code
            case quote
        }
        public let kind: Kind
        public let text: AttributedString

        public init(kind: Kind, text: AttributedString) {
            self.kind = kind
            self.text = text
        }
    }

    /// The blocks of `markdown`, in document order. Empty when Foundation cannot
    /// parse it at all; a caller with notes to show then has `items` to fall back on.
    public static func blocks(from markdown: String) -> [Block] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options)
        else { return [] }

        var blocks: [Block] = []
        var seenListItems: Set<Int> = []
        var pending: (intent: PresentationIntent?, text: AttributedString)?

        func flush() {
            guard let (intent, text) = pending else { return }
            pending = nil
            let (kind, listItem) = kind(of: intent, seenListItems: seenListItems)
            if let listItem { seenListItems.insert(listItem) }
            var body = text
            if kind == .code {
                // A code block's text keeps the newline that ended its last line.
                while body.characters.last?.isNewline == true { body.characters.removeLast() }
            }
            guard !String(body.characters).allSatisfy(\.isWhitespace) else { return }
            blocks.append(Block(kind: kind, text: body))
        }

        // Consecutive runs with the same intent are one block: a paragraph with a
        // bold word in it is three runs, one `PresentationIntent`.
        for run in parsed.runs {
            let intent = run.presentationIntent
            if pending != nil, pending?.intent == intent {
                pending?.text.append(parsed[run.range])
            } else {
                flush()
                pending = (intent, AttributedString(parsed[run.range]))
            }
        }
        flush()
        return blocks
    }

    /// What one intent draws as, plus the identity of the list item it sits in
    /// (so a later paragraph of an item already drawn — even after a nested list
    /// in between — is told apart from a new item).
    /// `components` runs innermost first: `paragraph < listItem < unorderedList`.
    private static func kind(
        of intent: PresentationIntent?, seenListItems: Set<Int>
    ) -> (Block.Kind, listItem: Int?) {
        let components = intent?.components ?? []
        var depth = 0
        var innermostOrdered: Bool?
        var item: (identity: Int, ordinal: Int)?
        for component in components {
            switch component.kind {
            case let .header(level):
                return (.heading(level: level), nil)
            case .codeBlock:
                return (.code, nil)
            case let .listItem(ordinal):
                if item == nil { item = (component.identity, ordinal) }
            case .orderedList:
                depth += 1
                if innermostOrdered == nil { innermostOrdered = true }
            case .unorderedList:
                depth += 1
                if innermostOrdered == nil { innermostOrdered = false }
            default:
                break
            }
        }
        if depth > 0, let item {
            let marker: String? = seenListItems.contains(item.identity)
                ? nil
                : (innermostOrdered == true ? "\(item.ordinal)." : "•")
            return (.listItem(depth: depth, marker: marker), item.identity)
        }
        if components.contains(where: { if case .blockQuote = $0.kind { return true }; return false }) {
            return (.quote, nil)
        }
        return (.paragraph, nil)
    }
}
