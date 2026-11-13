import Foundation

/// Microsoft's date headings delimit releases; the following `Version` line
/// identifies the release. Keep each body's Markdown and module headings intact.
public enum AzureCLIChangelog {
    public static let source = URL(string: "https://raw.githubusercontent.com/MicrosoftDocs/azure-docs-cli/main/docs-ref-conceptual/Latest-version/release-notes-azure-cli.md")!
    public static let page = URL(string: "https://learn.microsoft.com/en-us/cli/azure/release-notes-azure-cli")!

    public static func parse(_ markdown: String, version: String) -> Changelog? {
        let pattern = #"(?m)^## (?<date>[^\r\n]+)\r?\n\s*Version (?<version>[0-9]+\.[0-9]+\.[0-9]+)[ \t]*\r?\n(?<body>.*?)(?=^## |\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let text = markdown as NSString
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: text.length)) {
            guard text.substring(with: match.range(withName: "version")) == version else { continue }
            return GitHubMarkdownParser.parse(
                body: text.substring(with: match.range(withName: "body")), version: version,
                date: text.substring(with: match.range(withName: "date")))
        }
        return nil
    }
}
