import Foundation

/// Parses Duo Updater's OWN `CHANGELOG.md` into a `Changelog`.
///
/// That file is the single source of truth for release notes — `publish-release.sh`
/// lifts a version's section straight into the GitHub release and the Sparkle
/// appcast — so reading it is reading exactly what a user was told at the time,
/// with no second copy to drift.
///
/// Read from the repository rather than the app bundle, deliberately. Bundling it
/// would freeze the notes at build time: the copy running on someone's Mac would
/// describe its own version and nothing after it, so the one release they most
/// want to read about — the one they haven't taken yet — would be the one missing.
/// The appcast is not the source either: it carries a rolling window of the last
/// few releases, while this file has every one.
///
/// Format, which we control: `## <version>` headings, then blank-line-separated
/// paragraphs, each opening with a bold lead sentence. One paragraph is one item.
/// Everything before the first heading is the file's own preamble and is dropped.
public enum SelfChangelogParser {

    /// nil when the text carries no version section at all — a 404 body, an error
    /// page, or a file whose shape changed. The caller shows its own failure state
    /// rather than an empty list, which would read as "no releases".
    public static func parse(_ markdown: String, maxEntries: Int? = nil) -> Changelog? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?m)^##[ \t]+(?<version>[0-9][0-9A-Za-z.\-]*)[ \t]*$"#)
        else { return nil }

        let ns = markdown as NSString
        let headings = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        guard !headings.isEmpty else { return nil }

        var entries: [Changelog.Entry] = []
        for (i, heading) in headings.enumerated() {
            let version = ns.substring(with: heading.range(withName: "version"))
            // Body runs from the end of this heading to the start of the next one,
            // or to the end of the file for the last (oldest) section.
            let start = heading.range.location + heading.range.length
            let end = i + 1 < headings.count ? headings[i + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: start, length: end - start))

            let items = paragraphs(in: body)
            guard !items.isEmpty else { continue }
            entries.append(Changelog.Entry(version: version, date: nil, items: items))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        guard !entries.isEmpty else { return nil }
        // `.markdown`: the bold lead sentence that opens every paragraph is the
        // whole readability of this file. Rendered as plain text it would show the
        // asterisks instead.
        return Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// Blank-line-separated paragraphs, each collapsed onto one line. A paragraph
    /// wrapped across source lines is one item, not several — the wrapping is an
    /// artifact of editing the file, not of what it says.
    private static func paragraphs(in body: String) -> [String] {
        body
            .components(separatedBy: "\n\n")
            .map { block in
                block
                    .split(whereSeparator: { $0.isNewline })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
}
