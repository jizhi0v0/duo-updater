import Foundation

/// Maestro's (`com.maestro.app`, RunMaestro/Maestro) release bodies, rewritten
/// into the shape `GitHubMarkdownParser` reads, for `.maestroReleases`.
///
/// Maestro writes its headline changes as paragraphs, one per change, each led
/// by an emoji and a bold sentence, under a heading that carries the version
/// (`# 1.0.2 Highlights`), and the smaller ones as a list under another
/// (`## Also in 1.0.2`). The shared parser reads list items only once a body
/// has any, and treats a heading with a digit as a restated version, so of
/// 1.0.2's ten changes it kept the six listed ones, without either heading.
///
/// Rewriting the body here instead of changing the shared parser keeps every
/// other GitHub source byte-for-byte as it was. Two rewrites:
///   - a paragraph outside a list becomes a list item (its hard-wrapped lines
///     joined), except a lead-in that ends in `:`, a thank-you roster, the
///     `**Full Changelog**` link and an image or bare URL, which stay as they
///     were and the shared parser goes on ignoring;
///   - a heading loses its version: `in v0.15.2` / `in 0.17.x` /
///     `to v0.12.3` reads `… this release`, any other version token is
///     dropped, and so is a colon left at the end, so
///     `1.0.2 Highlights` → `Highlights`, `Major 0.17.x Additions` →
///     `Major Additions`, `Also in 1.0.2` → `Also in this release`.
///
/// A section repeating an earlier release is cut first, by the version its
/// heading names, as the shared parser would have cut it. Fenced code and
/// tables are left alone. A line right under a list item
/// with no blank line between is that item's continuation in Markdown and is
/// left alone too: the shared parser already joins it onto the item.
enum MaestroReleaseNotes {
    static func normalized(_ body: String, version: String) -> String {
        // The shared parser cuts a section repeating an earlier release
        // (`### v0.13.0 Changes` in 0.13.1's body) by the version in its
        // heading, which the rewrite below takes out: cut first.
        let body = GitHubMarkdownParser.withoutEarlierReleases(in: body, version: version)
        var out: [String] = []
        var paragraph: [String] = []
        // What the previous non-blank line was, for telling a paragraph's
        // start from a list item's continuation.
        var afterListItem = false
        var inFence = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            out.append("- " + paragraph.joined(separator: " "))
            paragraph = []
        }

        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                inFence.toggle()
                out.append(line)
                continue
            }
            if inFence { out.append(line); continue }
            if trimmed.isEmpty {
                flushParagraph()
                afterListItem = false
                out.append(line)
                continue
            }
            if let heading = GitHubMarkdownParser.headingRawText(of: trimmed) {
                flushParagraph()
                afterListItem = false
                let hashes = trimmed.prefix { $0 == "#" }
                let text = withoutVersion(heading)
                out.append(text.isEmpty ? line : "\(hashes) \(text)")
                continue
            }
            if isListItem(trimmed) {
                flushParagraph()
                afterListItem = true
                out.append(line)
                continue
            }
            if trimmed.hasPrefix("•") {
                flushParagraph()
                afterListItem = true
                out.append("- " + trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            if afterListItem {
                out.append(line)
                continue
            }
            if !paragraph.isEmpty {
                paragraph.append(trimmed)
                continue
            }
            if keepsAsIs(trimmed) {
                out.append(line)
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        return out.joined(separator: "\n")
    }

    /// `-`, `*`, `+` or `1.` followed by a space, at any indent.
    private static func isListItem(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^([-*+]|[0-9]+[.)])\s"#, options: .regularExpression) != nil
    }

    /// A non-list line that is not a change of its own.
    private static func keepsAsIs(_ trimmed: String) -> Bool {
        let lowered = trimmed.lowercased()
        return trimmed.hasSuffix(":")
            || lowered.hasPrefix("thanks") || lowered.hasPrefix("thank you")
            || lowered.hasPrefix("**full changelog")
            || trimmed.hasPrefix("|") || trimmed.hasPrefix("<")
            || GitHubMarkdownParser.isImageOnly(trimmed)
            || GitHubMarkdownParser.isBareURL(trimmed)
    }

    /// The heading's text with its version taken out (see the type's comment).
    static func withoutVersion(_ heading: String) -> String {
        let version = #"v?[0-9]+(?:\.(?:[0-9]+|x))+(?:-[A-Za-z]+[0-9]*)?"#
        var text = heading.replacingOccurrences(
            of: #"\b(in|to|for)\s+"# + version, with: "$1 this release",
            options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: version, with: "", options: .regularExpression)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while text.hasSuffix(":") { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        return text
    }
}
