import Foundation

/// ghcup's release notes, from its own `CHANGELOG.md` on `master`.
///
/// Raw file rather than the GitHub Releases, read 2026-10-09: the releases'
/// bodies are the same bullets, cut shorter (0.2.6.2's drops a sub-bullet, 0.2.6.1's
/// its `### Bugfixes affecting VSCode` heading), followed by a `Release
/// pipeline:` link, and each costs one of the API's 60 anonymous calls an hour.
/// The changelog (32,444 bytes) is every release, newest first, under
/// `# Version history for ghcup`:
///
///     ## 0.2.6.2 -- 2026-06-16
///
///     * Fix X.Y symlinks wrt [#1365](…)
///       - you may want to run `ghcup fixup symlinks` if you are affected
///
///     ## 0.2.6.1 -- 2026-06-13
///
///     ### Bugfixes affecting VSCode
///
///     * Fix another bug with `ghcup run --hls` …
///
/// Dates are ISO from 0.1.19.5 on (`2023-7-02` before), and `## 0.1.0` has none.
/// Each section goes through `GitHubMarkdownParser.parse(body:version:date:)`.
public enum GhcupChangelog {

    public static let source = URL(string: "https://raw.githubusercontent.com/haskell/ghcup-hs/master/CHANGELOG.md")!

    /// One entry per `## <version>` section that yields any change, in file order
    /// (newest first). nil when there is none.
    public static func parse(_ markdown: String) -> Changelog? {
        let entries = sections(markdown).compactMap { section in
            GitHubMarkdownParser.parse(body: section.body.joined(separator: "\n"), version: section.version,
                                       date: section.date)?.entries.first
        }
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// The `## <version> -- <date>` sections and their lines. Any other `#` or `##`
    /// heading ends the section before it; `###` and deeper belong to it.
    static func sections(_ markdown: String) -> [(version: String, date: String?, body: [String])] {
        var result: [(version: String, date: String?, body: [String])] = []
        var current: (version: String, date: String?, body: [String])?
        for raw in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("#"), !line.hasPrefix("###") {
                if let current { result.append(current) }
                current = heading(line).map { ($0.version, $0.date, []) }
                continue
            }
            current?.body.append(line)
        }
        if let current { result.append(current) }
        return result
    }

    /// `## 0.2.6.2 -- 2026-06-16` → ("0.2.6.2", "2026-06-16"); a date that is
    /// not `YYYY-MM-DD` is dropped. nil for any other heading.
    static func heading(_ line: String) -> (version: String, date: String?)? {
        guard line.hasPrefix("## ") else { return nil }
        let parts = line.dropFirst(3).components(separatedBy: " -- ")
        let version = parts[0].trimmingCharacters(in: .whitespaces)
        guard GhcupRelease.isVersion(version) else { return nil }
        let date = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
        let iso = date.flatMap { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil ? $0 : nil }
        return (version, iso)
    }

    static func fetch(force: Bool, session: URLSession = .updates) async throws -> Changelog {
        var request = URLRequest(url: source)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: source)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
