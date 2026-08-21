import Foundation

/// Decodes the handful of vendor changelog feeds whose JSON is too irregular for
/// the regex `ChangelogExtractor` — nested objects, or entries that aren't in
/// newest-first document order. Pure and side-effect-free (no network) so each
/// format is unit-testable against a fixture string, exactly like
/// `ChangelogExtractor` and `VendorProbeRecipe.extractVersion`.
///
/// Totally defensive: malformed JSON, a missing channel, or an entry with no usable
/// notes yields fewer entries (or nil), never a throw — a nil/empty result is the
/// caller's signal to fall back to the embedded web page.
public enum StructuredChangelogDecoder {

    /// Dispatch on the recipe's structured format. nil when the body can't be parsed
    /// into at least one entry for the requested channel.
    public static func decode(
        _ body: String, format: ChangelogRecipe.StructuredFormat,
        channel: ReleaseChannel?, maxEntries: Int?
    ) -> Changelog? {
        switch format {
        case .warpChannelVersions:
            return decodeWarp(body, channel: channel ?? .stable, maxEntries: maxEntries)
        case .typelessReleaseNotes:
            return decodeTypeless(body, maxEntries: maxEntries)
        case .weChatDevToolsLog:
            return decodeWeChatDevTools(body)
        case .chatwiseReleases:
            return decodeChatWise(body, maxEntries: maxEntries)
        case .sunLoginSoftwareLogs:
            return decodeSunLogin(body, maxEntries: maxEntries)
        case .gitHubDesktopChangelog:
            return decodeGitHubDesktop(body, maxEntries: maxEntries)
        case .postmanReleaseNotes:
            return decodePostman(body, maxEntries: maxEntries)
        case .jetBrainsProductReleases:
            return decodeJetBrainsProductReleases(body, maxEntries: maxEntries)
        case .zedGitHubReleases:
            return decodeZedGitHubReleases(body, channel: channel ?? .stable, maxEntries: maxEntries)
        case .notionPageChunk:
            return decodeNotionPageChunk(body, maxEntries: maxEntries)
        }
    }

    // MARK: - Warp (releases.warp.dev/channel_versions.json)

    /// Top-level shape we care about: `changelogs.<channel>.<versionKey> = {date,
    /// markdown_sections:[{title, markdown}]}`. Everything else in the document
    /// (current-version pointers, `oz_updates`, empty `sections`) is ignored.
    private struct WarpFeed: Decodable {
        let changelogs: [String: [String: WarpVersionNotes]]
    }
    private struct WarpVersionNotes: Decodable {
        let date: String?
        let markdownSections: [WarpSection]?
        enum CodingKeys: String, CodingKey {
            case date
            case markdownSections = "markdown_sections"
        }
    }
    private struct WarpSection: Decodable {
        let title: String?
        let markdown: String?
    }

    static func decodeWarp(
        _ body: String, channel: ReleaseChannel, maxEntries: Int?
    ) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let feed = try? JSONDecoder().decode(WarpFeed.self, from: data),
              let versions = feed.changelogs[channel.rawValue]
        else { return nil }

        // The JSON is NOT in newest-first order. The version key is
        // `v0.YYYY.MM.DD.HH.MM.<channel>_NN`: the timestamp segment is fixed-width
        // zero-padded so it orders lexically, but the trailing `_NN` build counter is
        // variable-width — a plain lexical sort would rank `_9` above `_10`. So sort by
        // (timestamp string, build number) descending, comparing the counter
        // numerically.
        let orderedKeys = versions.keys.sorted {
            let a = sortKey($0), b = sortKey($1)
            return a.stamp != b.stamp ? a.stamp > b.stamp : a.build > b.build
        }

        var entries: [Changelog.Entry] = []
        for key in orderedKeys {
            guard let notes = versions[key] else { continue }
            let items = (notes.markdownSections ?? []).flatMap { bulletItems(from: $0.markdown) }
            guard !items.isEmpty else { continue }
            entries.append(.init(
                version: displayVersion(fromKey: key),
                date: displayDate(notes.date, key: key),
                items: items))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// Newest-first sort key for a version key: the fixed-width timestamp prefix
    /// (compared lexically) and the trailing `_NN` build counter (compared as an Int,
    /// so a wider counter doesn't get mis-ranked by a leading digit). A key without
    /// the `.<channel>_NN` suffix sorts on its whole string with build 0.
    static func sortKey(_ key: String) -> (stamp: String, build: Int) {
        let stamp = key.replacingOccurrences(
            of: #"\.[a-z]+_\d+$"#, with: "", options: .regularExpression)
        var build = 0
        if let r = key.range(of: #"_\d+$"#, options: .regularExpression) {
            build = Int(key[r].dropFirst()) ?? 0
        }
        return (stamp, build)
    }

    /// `v0.2026.06.10.09.27.stable_01` → `0.2026.06.10.09.27.01` — drop the leading
    /// `v` and fold the trailing `.<channel>_NN` into a plain `.NN`, which is how
    /// the app itself spells its version and therefore what the vendor probe
    /// reports. The rail label has to line up with the version on the row next to
    /// it; a key with no `_NN` suffix keeps its bare timestamp.
    static func displayVersion(fromKey key: String) -> String {
        var v = key.hasPrefix("v") ? String(key.dropFirst()) : key
        v = v.replacingOccurrences(
            of: #"\.[a-z]+_(\d+)$"#, with: ".$1", options: .regularExpression)
        return v
    }

    /// `2026-06-10` for the rail subtitle. The JSON `date` is ISO-8601 whose offset
    /// form varies (`+0000` vs `+00:00`), so rather than parse it we just take the
    /// leading `YYYY-MM-DD` it always begins with. Falls back to reconstructing the
    /// date from the version key's `.YYYY.MM.DD.` components.
    static func displayDate(_ raw: String?, key: String) -> String? {
        if let raw, raw.count >= 10 {
            let ymd = String(raw.prefix(10))
            if ymd.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                return ymd
            }
        }
        // `v0.2026.06.10.09.27.stable_01` → ["v0","2026","06","10",…]
        let parts = key.split(separator: ".")
        if parts.count >= 4,
           parts[1].count == 4, parts[2].count == 2, parts[3].count == 2 {
            return "\(parts[1])-\(parts[2])-\(parts[3])"
        }
        return nil
    }

    /// Turn one markdown section body ("* a\n* b ([#1](url))\n") into clean change
    /// lines: split on newlines, drop the leading `*`/`-`/`+` list marker, strip inline
    /// images and hard-break `<br>` tags, flatten `[text](url)` markdown links to just
    /// `text`, and trim. Blank lines vanish.
    static func bulletItems(from markdown: String?) -> [String] {
        guard let markdown else { return [] }
        return markdown
            // `whereSeparator`, not `separator: "\n"` — see the note in
            // `postmanItems`: Swift treats "\r\n" as one Character that does not
            // equal "\n", so a CRLF body would come back as a single giant line.
            // ChatWise's feed is LF today; this costs nothing and removes the
            // trap for the next vendor that isn't.
            .split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline })
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespaces)
                s = s.replacingOccurrences(
                    of: #"^[*+-]\s+"#, with: "", options: .regularExpression)
                // Markdown allows raw HTML, and Typeless uses `<br>` for the hard break
                // after a lead-in phrase. We render plain strings, so it would show up
                // literally ("Dictate the way you think <br>"); the line split already
                // did the breaking, so just drop it.
                s = s.replacingOccurrences(
                    of: #"<br\s*/?>"#, with: " ",
                    options: [.regularExpression, .caseInsensitive])
                // Remove inline images outright, BEFORE link-flattening, so `![alt](url)`
                // doesn't decay to a stray `!alt`.
                s = s.replacingOccurrences(
                    of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
                // Flatten `[text](url)` to `text`. The URL sub-pattern allows one level
                // of nested parens (e.g. a Wikipedia `..._(bar)` URL) so the match
                // consumes the whole link instead of leaving a dangling `)`.
                s = s.replacingOccurrences(
                    of: #"\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)"#, with: "$1",
                    options: .regularExpression)
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - WeChat DevTools (devtools.wxqcloud.qq.com.cn/…/logs/<channel>_v<ver>.json)

    /// One release's notes: `categories[]` of `{title, items[]}`, where each item is
    /// a line of Chinese prose prefixed by a literal ordinal and a backticked marker
    /// ("1. `F` 修复 …" / "1. `修复` …" — the marker vocabulary is inconsistent across
    /// channels, which is why it's stripped rather than mapped).
    ///
    /// The endpoint is per-version — the recipe templates `{version}` into the URL —
    /// so a document is always exactly ONE entry. There is no multi-version document
    /// to page through: the vendor's index (`history_<channel>.json`) carries only
    /// version→filename pointers, no notes.
    private struct WeChatDevToolsLog: Decodable {
        let version: String?
        let updateTime: String?
        let categories: [WeChatDevToolsCategory]?
        enum CodingKeys: String, CodingKey {
            case version
            case updateTime = "update_time"
            case categories
        }
    }
    private struct WeChatDevToolsCategory: Decodable {
        let title: String?
        let items: [String]?
    }

    static func decodeWeChatDevTools(_ body: String) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let log = try? JSONDecoder().decode(WeChatDevToolsLog.self, from: data),
              let version = log.version?.trimmingCharacters(in: .whitespaces),
              !version.isEmpty
        else { return nil }

        var blocks: [Changelog.Entry.Block] = []
        var items: [String] = []
        for category in log.categories ?? [] {
            let lines = (category.items ?? []).compactMap { weChatDevToolsItem($0) }
            guard !lines.isEmpty else { continue }
            // The category title ("🐛 问题修复" / " 问题修复") is the only thing that
            // says what a group of lines IS, so it rides along as a heading note.
            if let title = category.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
                blocks.append(.note(title))
                items.append(title)
            }
            for line in lines {
                blocks.append(.note(line))
                items.append(line)
            }
        }
        guard !blocks.isEmpty else { return nil }
        return Changelog(entries: [.init(
            version: version,
            date: log.updateTime,
            items: items,
            content: blocks)])
    }

    /// Clean one change line: drop the literal ordinal every item carries ("1. " —
    /// the vendor authors these as markdown lists and every single one is numbered
    /// "1.", so they are decoration, not a sequence) and the leading backticked
    /// marker (`A` / `F` / `修复` / `新增`, inconsistent between channels and already
    /// implied by the category heading). Then run the shared markdown cleanup.
    /// nil when nothing readable is left.
    static func weChatDevToolsItem(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(
            of: #"^\d+[.、)]\s*"#, with: "", options: .regularExpression)
        // Only a SHORT backticked token is a marker; a longer one is real inline
        // code the note is about (`wx.login`), which must survive.
        s = s.replacingOccurrences(
            of: #"^`[^`]{1,4}`\s*"#, with: "", options: .regularExpression)
        return bulletItems(from: s).first
    }

    // MARK: - ChatWise (releases.chatwise.app/releases)

    /// One published release. `changelog` is a markdown bullet list, `date` is
    /// ISO-8601. `assets` is the updater payload (per-platform archives + hashes)
    /// and is ignored here — the changelog pane only wants the notes.
    private struct ChatWiseRelease: Decodable {
        let version: String?
        let changelog: String?
        let date: String?
    }

    /// `2026-06-26T16:04:26.161Z` → `2026-06-26` for the rail subtitle; nil when
    /// the field is missing or isn't a leading `YYYY-MM-DD`.
    static func isoDay(_ raw: String?) -> String? {
        guard let raw, raw.count >= 10 else { return nil }
        let ymd = String(raw.prefix(10))
        guard ymd.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        else { return nil }
        return ymd
    }

    /// The document is a flat array in newest-first order (the same order the
    /// vendor's own /changelog page renders), so we keep it as-is and just cap.
    /// A release with an empty changelog is skipped rather than shown as a bare
    /// version heading, and does not count toward the cap.
    static func decodeChatWise(_ body: String, maxEntries: Int?) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let releases = try? JSONDecoder().decode([ChatWiseRelease].self, from: data)
        else { return nil }

        var entries: [Changelog.Entry] = []
        for release in releases {
            guard let version = release.version?.trimmingCharacters(in: .whitespaces),
                  !version.isEmpty
            else { continue }
            let items = bulletItems(from: release.changelog)
            guard !items.isEmpty else { continue }
            entries.append(.init(
                version: version,
                date: isoDay(release.date),
                items: items))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    // MARK: - GitHub Desktop (central.github.com/deployments/desktop/desktop/changelog.json)

    /// The feed is a flat JSON array, newest-first, of `{name, notes, pub_date,
    /// version}` — `notes` is already an array of one-line strings (each keeping the
    /// vendor's own `[Fixed]`/`[Added]`/`[Improved]` prefix and trailing `- #issue`),
    /// so there is no markdown to split or clean, just JSON strings to decode as-is.
    /// `name` is always empty in practice and unused. Stable and beta are two
    /// separate URLs (`?env=beta` on the same host), not one document with a
    /// per-channel key, so unlike Warp this decoder takes no `channel` — the two
    /// `ChangelogRecipe`s just point at different endpoints and share this format.
    private struct GitHubDesktopEntry: Decodable {
        let notes: [String]?
        let pubDate: String?
        let version: String?
        enum CodingKeys: String, CodingKey {
            case notes
            case pubDate = "pub_date"
            case version
        }
    }

    static func decodeGitHubDesktop(_ body: String, maxEntries: Int?) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let feed = try? JSONDecoder().decode([GitHubDesktopEntry].self, from: data),
              !feed.isEmpty
        else { return nil }

        var entries: [Changelog.Entry] = []
        for entry in feed {
            guard let version = entry.version, !version.isEmpty else { continue }
            let items = (entry.notes ?? []).filter { !$0.isEmpty }
            guard !items.isEmpty else { continue }
            entries.append(.init(
                version: version, date: isoDay(entry.pubDate), items: items))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    // MARK: - Postman (mkt.cdn.postman.com/www-next/release-notes/app-release-notes.json)

    /// Top-level shape: `{"notes": [{version, content, createdAt}, ...]}`, newest
    /// first. `content` is markdown; we deliberately do NOT run it through
    /// `bulletItems` — the prior regex path left markdown syntax (`**bold**`,
    /// `[text](url)`) verbatim in the rendered items, and this recipe's item text
    /// must not change shape out from under that, only stop being truncated.
    private struct PostmanFeed: Decodable {
        let notes: [PostmanNote]
    }
    private struct PostmanNote: Decodable {
        let version: String?
        let content: String?
        let createdAt: String?
    }

    static func decodePostman(_ body: String, maxEntries: Int?) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let feed = try? JSONDecoder().decode(PostmanFeed.self, from: data)
        else { return nil }

        var entries: [Changelog.Entry] = []
        for note in feed.notes {
            guard let version = note.version?.trimmingCharacters(in: .whitespaces),
                  !version.isEmpty
            else { continue }
            let items = postmanItems(from: note.content)
            guard !items.isEmpty else { continue }
            entries.append(.init(
                version: version, date: postmanDate(note.createdAt), items: items))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// Reproduces, line-for-line, what the old regex itemPattern
    /// (`\r\n(?:####\s+)?(?!##|\r\n|\w+ \d+, \d{4})(?<item>[^\\]{10,})`) picked out
    /// of the *escaped* JSON text — but working on the real, decoded markdown, so a
    /// line containing an escaped quote is no longer cut off at the backslash.
    /// Per line:
    ///   - blank lines are dropped (this also eats the trailing `\r\n\r\n` and, for
    ///     older entries, absorbs the plain-`\n` line separator the same way);
    ///   - a `#### ` feature-heading prefix is stripped but the heading text is KEPT
    ///     as an item (the old pattern's optional non-capturing group did the same);
    ///   - any other line starting with `##` (a `##`/`###` document/section heading)
    ///     is skipped entirely;
    ///   - a line that IS (or starts with) a "Month D, YYYY" date stamp is skipped —
    ///     this is the "## Postman X.Y.Z" / date pair at the top of every entry;
    ///   - anything left under 10 characters is dropped (matches the old pattern's
    ///     `{10,}` floor, there to filter stray short fragments);
    ///   - everything else is kept as-is, including leading `- ` list markers and
    ///     inline markdown syntax.
    static func postmanItems(from content: String?) -> [String] {
        guard let content else { return [] }
        // NOTE: split on `Character.isNewline`, not `separator: "\n"`. Swift
        // Strings treat "\r\n" as a SINGLE Character (one grapheme cluster) that
        // is not equal to the standalone "\n" Character — so `split(separator:
        // "\n")` does not split inside it at all, and a whole `\r\n`-separated
        // body comes back as one giant "line". `isNewline` recognizes "\n", "\r",
        // and the "\r\n" cluster alike, so both this recipe's current (`\r\n`)
        // and legacy (`\n`) entries split the same way. (Caught by running this
        // against a real 4-entry feed slice in the regression test below — three
        // of the four entries silently produced zero items before this fix.)
        return content
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .compactMap { rawLine -> String? in
                var line = String(rawLine)
                if line.isEmpty { return nil }
                if line.hasPrefix("#### ") {
                    line = String(line.dropFirst(5))
                } else if line.hasPrefix("##") {
                    return nil
                }
                if postmanIsDateLine(line) { return nil }
                // Trim/collapse BEFORE the length floor, not after. The regex path
                // ended in `ChangelogExtractor.clean` → `collapseWhitespace`, so its
                // `{10,}` quantifier counted the raw match but the *stored* item was
                // normalized. Skipping this left 129 lines of today's feed with
                // trailing spaces and 23 with internal double spaces — invisible in
                // most renderings but a real diff against the old output — and made
                // the floor measure untrimmed length, so a line of eleven spaces
                // would have become a blank bullet where the old path dropped it.
                let cleaned = ChangelogExtractor.collapseWhitespace(line)
                guard cleaned.count >= 10 else { return nil }
                return cleaned
            }
    }

    /// True when `line` begins with a "Month D, YYYY" stamp (e.g. "August 21,
    /// 2026"), the exact date line Postman prints under the "## Postman X.Y.Z"
    /// title. A prefix match, not a whole-line match — matching the old regex's
    /// negative lookahead, which only asserted the pattern at the start.
    static func postmanIsDateLine(_ line: String) -> Bool {
        line.range(of: #"^\w+ \d+, \d{4}"#, options: .regularExpression) != nil
    }

    /// `2026-08-19` from `2026-08-19T06:06:19.000Z` — the leading `YYYY-MM-DD` the
    /// old regex's `[^"T]+` capture also stopped at.
    static func postmanDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if let t = raw.firstIndex(of: "T") { return String(raw[raw.startIndex..<t]) }
        return raw.isEmpty ? nil : raw
    }

    // MARK: - Zed (api.github.com/repos/zed-industries/zed/releases)

    /// One element of the GitHub Releases API array. Only the fields we use;
    /// everything else (assets, author, reactions, …) is ignored by Decodable.
    private struct ZedRelease: Decodable {
        let tagName: String
        let prerelease: Bool
        let publishedAt: String?
        let body: String?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease
            case publishedAt = "published_at"
            case body
        }
    }

    /// `prerelease` is the channel split: Zed's Preview builds tag as
    /// `vX.Y.Z-pre` and always carry `prerelease: true`, Stable never does
    /// (confirmed 1:1 with the tag suffix across 100 sampled releases — no
    /// exceptions). The list is already newest-first, so filtering by channel
    /// preserves that order; no re-sort needed (unlike Warp's unordered map).
    static func decodeZedGitHubReleases(
        _ body: String, channel: ReleaseChannel, maxEntries: Int?
    ) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let releases = try? JSONDecoder().decode([ZedRelease].self, from: data)
        else { return nil }

        let wantsPrerelease = channel == .preview
        var entries: [Changelog.Entry] = []
        for release in releases where release.prerelease == wantsPrerelease {
            guard let body = release.body, !body.isEmpty else { continue }
            let version = zedDisplayVersion(fromTag: release.tagName)
            let date = release.publishedAt.map { String($0.prefix(10)) }
            // Reuse the same parser GitHub-release version detection already
            // uses for a single release's notes (`GitHubMarkdownParser`), rather
            // than a second bespoke bullet-extractor for the same markdown shape.
            if let parsed = GitHubMarkdownParser.parse(body: body, version: version, date: date),
               let entry = parsed.entries.first {
                entries.append(entry)
            } else if let prose = zedProseFallback(body: body) {
                // `GitHubMarkdownParser` returns nil for a body with no bullets, and
                // Zed ships such releases: 1 of the newest 100 today (`v1.5.3-pre`,
                // whose whole body is "No public-facing changes in this release.").
                // Skipping them left a Preview user sitting on exactly that build
                // with NO entry for their own version — the retired zed.dev recipe
                // had a `<p>` item pattern that covered this, so dropping them was a
                // content regression against the source this replaced.
                entries.append(.init(version: version, date: date, items: [prose]))
            } else {
                continue
            }
            if let cap = maxEntries, entries.count >= cap { break }
        }
        guard !entries.isEmpty else { return nil }
        return Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// The first non-empty, non-heading prose line of a release body that has no
    /// bullets at all — Zed's "No public-facing changes in this release." shape.
    /// Markdown links are flattened to their text so the trailing
    /// "[View the commits](…)" doesn't render as raw bracket syntax; the entry is
    /// emitted with `.markdown` syntax like every other Zed entry, so anything
    /// left is rendered rather than shown literally. nil when the body is only
    /// headings/links, in which case the release really is skipped.
    static func zedProseFallback(body: String) -> String? {
        for rawLine in body.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("<") else { continue }
            let flattened = ChangelogExtractor.collapseWhitespace(
                line.replacingOccurrences(
                    of: #"\[([^\]]*)\]\((?:[^()]|\([^()]*\))*\)"#, with: "$1",
                    options: .regularExpression))
            guard !flattened.isEmpty else { continue }
            return flattened
        }
        return nil
    }

    /// `v1.17.0-pre` → `1.17.0`, `v1.16.1` → `1.16.1`: drop the leading `v` and
    /// the `-pre` suffix so the rail version matches the installed
    /// `CFBundleShortVersionString`, which is what `GitHubReleaseRule`'s
    /// `versionPattern` (`v([0-9]+\.[0-9]+\.[0-9]+)-pre`) already extracts for
    /// Preview and what the tag is verbatim (minus `v`) for Stable.
    static func zedDisplayVersion(fromTag tag: String) -> String {
        var v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if v.hasSuffix("-pre") { v = String(v.dropLast(4)) }
        return v
    }

    // MARK: - SunLogin/AweSun (client-webapi.oray.com/softwares/…)

    /// Top-level shape we care about: a `logs` array, one object per release,
    /// already newest-first in the document (verified against the live feed
    /// 2026-08-21: entries ran 2026-08-05 → 2024-07-08 in that order).
    private struct SunLoginFeed: Decodable {
        let logs: [SunLoginLogEntry]
    }
    /// One release. `logs` (yes, same name as the array) is a fixed
    /// `<ol><li>version</li><li>item</li>…</ol>` HTML fragment; `updatedate` is a
    /// `YYYY-MM-DD HH:mm:ss` timestamp.
    private struct SunLoginLogEntry: Decodable {
        /// Optional, like every other field every decoder in this file declares.
        /// Non-optional here would make a single `"logs": null` anywhere in the
        /// array throw out of `JSONDecoder.decode`, returning nil for the WHOLE
        /// feed and dropping the user back to the embedded web page — where the
        /// regex this replaced would simply have skipped that one entry. The
        /// file's own contract is "an entry with no usable notes yields fewer
        /// entries", not "yields none".
        let logs: String?
        let updatedate: String?
    }

    static func decodeSunLogin(_ body: String, maxEntries: Int?) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let feed = try? JSONDecoder().decode(SunLoginFeed.self, from: data)
        else { return nil }

        var entries: [Changelog.Entry] = []
        for entry in feed.logs {
            guard let logs = entry.logs else { continue }
            let (version, items) = sunLoginParseLogHTML(logs)
            guard let version, !items.isEmpty else { continue }
            entries.append(.init(
                version: version,
                date: isoDay(entry.updatedate),
                items: items))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// Split one entry's `<ol><li>…</li>…</ol>` fragment into (version, items):
    /// the first `<li>` names the version, every subsequent `<li>` is one change
    /// line. JSONDecoder has already resolved the JSON string's `\uXXXX`/`\/`
    /// escapes by the time this runs, so the fragment is plain HTML with real
    /// UTF-8 text and unescaped slashes — no entity/unicode decoding needed here.
    ///
    /// Each `<li>`'s inner text goes through the same `stripTags` → `decodeEntities`
    /// → `collapseWhitespace` the retired recipe's defaults applied, so a nested
    /// `<b>`/`<a>` or an `&amp;` renders as text rather than as markup. (The
    /// JetBrains decoder alongside this one already does; this was the odd sibling
    /// out. Today's payload has neither, so it is a robustness fix, not a visible
    /// one.)
    static func sunLoginParseLogHTML(_ html: String) -> (version: String?, items: [String]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"<li>(.*?)</li>"#, options: [.dotMatchesLineSeparators])
        else { return (nil, []) }
        let ns = html as NSString
        let lines = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                let raw = ns.substring(with: match.range(at: 1))
                let s = ChangelogExtractor.collapseWhitespace(
                    ChangelogExtractor.decodeEntities(
                        ChangelogExtractor.stripTags(raw)))
                return s.isEmpty ? nil : s
            }
        guard let version = lines.first else { return (nil, []) }
        return (version, Array(lines.dropFirst()))
    }

    // MARK: - JetBrains product releases
    // (data.services.jetbrains.com/products/releases?code=<CODE>)

    /// One release from the feed. Verified against the live `IIU` (IntelliJ IDEA)
    /// and `TBA` (Toolbox App) endpoints: both return `{"<CODE>": [ {…}, … ]}` —
    /// exactly one top-level key — with each element carrying `date` (already
    /// plain `YYYY-MM-DD`, no parsing needed), `version` (marketing string, e.g.
    /// "2026.2.1" / "3.7.2"), and `whatsnew` (release-notes HTML). Fields present
    /// in the real response but unused here (`type`, `build`, `downloads`,
    /// `patches`, `notesLink`, `uninstallFeedbackLinks`, …) are simply omitted —
    /// `Decodable` ignores keys a struct doesn't declare.
    private struct JetBrainsRelease: Decodable {
        let date: String?
        let version: String?
        let whatsnew: String?
    }

    /// The array is NOT a global newest-first-by-date sort — verified against both
    /// live feeds: entries group by major-version branch (descending), and only
    /// within a branch by date (descending). So IntelliJ IDEA's `2026.1.5` patch
    /// (dated 2026-08-12) sits AFTER `2026.2.1` (dated 2026-08-10) in the array,
    /// because 2026.1 is the older branch — even though 2026.1.5 is objectively the
    /// more recently published file. That's the vendor's own "current branch first"
    /// intent (matches what jetbrains.com/idea/whatsnew shows), so entries are kept
    /// in document order rather than re-sorted by date.
    static func decodeJetBrainsProductReleases(_ body: String, maxEntries: Int?) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let root = try? JSONDecoder().decode([String: [JetBrainsRelease]].self, from: data),
              let releases = root.first?.value
        else { return nil }
        let code = root.first?.key ?? ""

        var entries: [Changelog.Entry] = []
        for release in releases {
            guard let version = release.version?.trimmingCharacters(in: .whitespaces),
                  !version.isEmpty,
                  let whatsnew = release.whatsnew, !whatsnew.isEmpty
            else { continue }
            let items = jetBrainsItems(from: whatsnew, code: code)
            guard !items.isEmpty else { continue }
            entries.append(.init(version: version, date: release.date, items: items))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// Extract discrete change lines from one release's `whatsnew` HTML.
    ///
    /// IntelliJ IDEA (`IIU`) documents are standalone: the lead `<p>` is always
    /// boilerplate ("IntelliJ IDEA X is out with…") and the trailing `<p>` is
    /// always a "Get more details in our blog post" pointer, so only `<li>`
    /// bullets are discrete changes. A hotfix release with no `<li>` at all (its
    /// only content is prose `<p>`, e.g. 2026.2.0.1, or just a "see the release
    /// notes" pointer, e.g. 2026.1.5) yields zero items and is skipped — same as
    /// the regex recipe this replaces did.
    ///
    /// Toolbox App (`TBA`) documents are CUMULATIVE: one entry concatenates its
    /// own `<li>` bullets with the full prior minor release's write-up as `<h3>`/
    /// `<h4>` headings each followed by a `<p>` description, ending in a "See the
    /// full list of release notes…" `<p>` footer. Headings aren't matched by this
    /// sweep (only `<li>`/`<p>`), so both tags count as items; only that trailing
    /// footer paragraph is dropped.
    static func jetBrainsItems(from whatsnew: String, code: String) -> [String] {
        let tags = code == "TBA" ? "li|p" : "li"
        guard let regex = try? NSRegularExpression(
            pattern: "<(\(tags))>(.*?)</\\1>",
            options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let ns = whatsnew as NSString
        var items: [String] = []
        for match in regex.matches(in: whatsnew, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 2 else { continue }
            let raw = ns.substring(with: match.range(at: 2))
            if raw.range(
                of: #"^\s*See the full list"#, options: [.regularExpression, .caseInsensitive]
            ) != nil { continue }
            let cleaned = ChangelogExtractor.collapseWhitespace(
                ChangelogExtractor.decodeEntities(ChangelogExtractor.stripTags(raw)))
            if !cleaned.isEmpty { items.append(cleaned) }
        }
        return items
    }
    // MARK: - Typeless (typeless.com/help/release-notes/macos)

    /// Typeless's release-notes page is a Next.js SSG page whose entire content is
    /// base64+gzip in `__NEXT_DATA__.props.pageProps.compressedData`. The
    /// decompressed JSON has had **two shapes**, and we accept both (`typelessNotes`):
    ///
    ///   - v3 (current, `pageProps.dataKey == "typeless-release-notes--v3--macos"`):
    ///     a flat ARRAY of `{version, date, platform, tags, features:[{title,
    ///     content}]}`, already one locale (the page is locale-scoped via
    ///     `pageProps.embeddedLangCode`).
    ///   - legacy: a MAP `<version> -> <locale> -> {version, date, …}`.
    ///
    /// `content` is markdown either way (a leading `![](url)` illustration then
    /// prose paragraphs). Neither shape guarantees order, so we sort
    /// semver-descending. Single channel — no channel arg.
    private struct TypelessNote: Decodable {
        let version: String?
        let date: String?
        let features: [TypelessFeature]?
    }
    private struct TypelessFeature: Decodable {
        let title: String?
        let content: String?
    }

    static func decodeTypeless(_ body: String, maxEntries: Int?) -> Changelog? {
        // 1. Pull the __NEXT_DATA__ blob, navigate to the compressed payload, and
        //    inflate it. JSONSerialization (not Decodable) for the navigation — the
        //    surrounding document is huge and we only want one deep string.
        guard let nextData = extractNextData(body),
              let root = try? JSONSerialization.jsonObject(with: Data(nextData.utf8)) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let compressed = pageProps["compressedData"] as? String,
              let gz = Data(base64Encoded: compressed),
              let json = GzipDecode.decompress(gz),
              let notes = typelessNotes(from: json)
        else { return nil }

        var entries: [Changelog.Entry] = []
        for (key, note) in notes {
            let features = note.features ?? []
            let single = features.count == 1
            var blocks: [Changelog.Entry.Block] = []
            var items: [String] = []
            for feature in features {
                // With multiple features, fold each title in as a heading note; a
                // lone feature's title rides on the Entry instead (see below).
                if !single, let t = feature.title?.trimmingCharacters(in: .whitespaces), !t.isEmpty {
                    blocks.append(.note(t))
                    items.append(t)
                }
                for line in (feature.content ?? "").split(separator: "\n") {
                    let s = line.trimmingCharacters(in: .whitespaces)
                    if s.isEmpty { continue }
                    if let url = imageURL(inMarkdownLine: s) {
                        blocks.append(.image(url))
                    } else if let text = bulletItems(from: s).first {
                        blocks.append(.note(text))
                        items.append(text)
                    }
                }
            }
            guard !blocks.isEmpty else { continue }

            entries.append(.init(
                title: single ? features.first?.title : nil,
                version: note.version ?? key,
                date: note.date,
                items: items,
                content: blocks))
            if let cap = maxEntries, entries.count >= cap { break }
        }
        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// The inflated payload as `(fallbackVersion, note)` pairs, newest-first, from
    /// whichever of Typeless's two shapes it turns out to be. The array form is tried
    /// first because it's what the site serves today; the map form is kept so an
    /// older cached/served payload still parses. nil when it's neither.
    ///
    /// `fallbackVersion` is the map's key (the array carries no key, so the note's own
    /// `version` is all there is) — used only when a note omits `version`.
    private static func typelessNotes(from json: Data) -> [(String, TypelessNote)]? {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([TypelessNote].self, from: json), !list.isEmpty {
            return list
                .map { ($0.version ?? "", $0) }
                .sorted { semverDescending($0.0, $1.0) }
        }
        if let map = try? decoder.decode([String: [String: TypelessNote]].self, from: json),
           !map.isEmpty {
            return map.keys.sorted { semverDescending($0, $1) }.compactMap { key in
                guard let locales = map[key], !locales.isEmpty else { return nil }
                // English when available; otherwise any locale (deterministically the
                // alphabetically-first) so a missing `en` never drops the entry.
                guard let note = locales["en"] ?? locales[locales.keys.sorted().first!]
                else { return nil }
                return (key, note)
            }
        }
        return nil
    }

    /// Extract the JSON text inside `<script id="__NEXT_DATA__" …>…</script>`.
    static func extractNextData(_ html: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"<script id="__NEXT_DATA__"[^>]*>(.*?)</script>"#,
            options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// When a whole markdown line is just an image (`![alt](url)`), return its URL.
    static func imageURL(inMarkdownLine line: String) -> URL? {
        guard let re = try? NSRegularExpression(pattern: #"^!\[[^\]]*\]\(([^)]+)\)$"#),
              let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return URL(string: String(line[r]))
    }

    /// Descending comparison of dotted numeric versions ("1.10.0" > "1.9.0"),
    /// missing trailing components treated as 0. Non-numeric components sort as 0.
    static func semverDescending(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Notion (notion.notion.site/api/v3/loadPageChunk)

    /// Notion's internal, unauthenticated page-rendering API — POSTed with a fixed
    /// page id (see `ChangelogRecipe.httpMethod`/`requestBody`) — for the desktop
    /// app's real "What's New" page
    /// (`notion.notion.site/What-s-New-Mac-Windows-…`), which carries actual build
    /// numbers (`v7.31.0`). Distinct from `www.notion.com/releases`, Notion's
    /// *product* announcement feed with no build numbers at all (see the
    /// `notion.id` recipe comment in `ChangelogRecipe.swift`) — that page answers a
    /// different question and is kept as a separate, channel-agnostic recipe.
    ///
    /// Shape: `recordMap.block` is a MAP keyed by block id, each entry wrapped
    /// `{value: {value: {...}}}` — note the DOUBLE `value`. Losing the inner layer
    /// yields every block's `type`/`properties` as nil silently (not a decode
    /// error), which looks exactly like "the page structure changed" rather than
    /// "wrong path" — confirmed by hand while building this decoder.
    ///
    /// The map's own iteration/key order is NOT the page's reading order (Swift
    /// dictionary order is unspecified, and nothing here guarantees the JSON's
    /// on-the-wire key order means anything either). The real order comes from the
    /// root `page`-type block's OWN `content: [id, id, …]` array, which lists every
    /// child block id in document order. We walk that array — filtering to ids
    /// actually present in this (paginated, `limit`-bounded) chunk — and group the
    /// blocks into releases:
    ///   `header` (title text is the version, "v7.31.0") → `text` (a "📅 Released
    ///   ‣ (macOS & Windows)" line whose `‣` is a real Notion date mention) → one
    ///   or more `bulleted_list` (the change lines), repeating until the next
    ///   `header`.
    ///
    /// Verified live 2026-08-22 against
    /// `https://notion.notion.site/What-s-New-Mac-Windows-5936dabc8dd6497895786c91b9d6f12a`
    /// via `loadPageChunk` (`pageId` = that page's id, `chunkNumber: 0, limit: 50`):
    /// 101 blocks (1 page + 24 header + 24 text + 52 bulleted_list), `content`-array
    /// order running v7.31.0 → v7.29.0 → v7.28.0 → … — newest first, matching the
    /// installed app's own version (from the vendor probe's `.redirectFilename`).
    private struct NotionPageChunk: Decodable {
        let recordMap: NotionRecordMap
    }
    private struct NotionRecordMap: Decodable {
        let block: [String: NotionBlockEnvelope]
    }
    private struct NotionBlockEnvelope: Decodable {
        let value: NotionValueWrapper
    }
    private struct NotionValueWrapper: Decodable {
        let value: NotionBlock
    }
    private struct NotionBlock: Decodable {
        let type: String?
        let properties: NotionProperties?
        /// Present only on the `page` block: every child block id, in reading order.
        let content: [String]?
    }
    private struct NotionProperties: Decodable {
        let title: [NotionTitleSegment]?
    }

    /// One `title` segment: `[text]` or `[text, [decoration, …]]`. Only the plain
    /// `text` and (when present) a date decoration's ISO day are extracted — rich
    /// formatting (bold/italic/links) is not reproduced, matching every other
    /// structured decoder's plain-text items.
    private struct NotionTitleSegment: Decodable {
        let text: String
        /// Set only when one of this segment's decorations is a date mention.
        let dateDay: String?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            text = try container.decode(String.self)
            guard !container.isAtEnd,
                  let decorations = try? container.decode([NotionDecoration].self)
            else {
                dateDay = nil
                return
            }
            dateDay = decorations.compactMap(\.dateDay).first
        }
    }

    /// One decoration entry: `[code]` or `[code, payload]`. Only the `"d"` (date
    /// mention) code's payload is consumed — a Notion date-mention object with a
    /// `start_date` of `YYYY-MM-DD` (optionally followed by a time-of-day, which we
    /// don't need). Every other code (bold `"b"`, italic `"i"`, link `"a"`, comment
    /// `"ce"`, user mention `"u"`, …) decodes its leading code string fine and is
    /// otherwise ignored — `dateDay` just stays nil for it.
    private struct NotionDecoration: Decodable {
        let dateDay: String?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let code = try container.decode(String.self)
            guard code == "d", !container.isAtEnd else {
                dateDay = nil
                return
            }
            struct DateProps: Decodable {
                let startDate: String?
                enum CodingKeys: String, CodingKey { case startDate = "start_date" }
            }
            dateDay = (try? container.decode(DateProps.self))?.startDate
        }
    }

    static func decodeNotionPageChunk(_ body: String, maxEntries: Int?) -> Changelog? {
        guard let data = body.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(NotionPageChunk.self, from: data)
        else { return nil }
        let blocks = chunk.recordMap.block
        // The reading order lives on the page block's own `content` array, NOT on
        // the surrounding map's key order (see the doc comment above) — so find
        // that one block first rather than iterating `blocks` directly.
        guard let order = blocks.values.first(where: { $0.value.value.type == "page" })?
            .value.value.content
        else { return nil }

        var entries: [Changelog.Entry] = []
        var version: String?
        var date: String?
        var items: [String] = []

        func flush() {
            guard let v = version, !items.isEmpty else { return }
            entries.append(.init(version: v, date: date, items: items))
        }

        for id in order {
            guard let block = blocks[id]?.value.value else { continue }
            if block.type == "header" {
                flush()
                // Cap BEFORE starting a new entry, not after finishing it — an
                // entry-count check placed after processing every child block
                // would have already parsed one release too many.
                if let cap = maxEntries, entries.count >= cap {
                    version = nil  // so the trailing `flush()` below is a no-op
                    break
                }
                var v = notionText(block.properties?.title ?? [])
                    .trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("v") { v = String(v.dropFirst()) }
                version = v
                date = nil
                items = []
                continue
            }
            // A stray text/bulleted_list block before the first header (shouldn't
            // happen on this page, but the page is fetched live) has nowhere to go.
            guard version != nil else { continue }
            switch block.type {
            case "text":
                // First date mention wins; the "📅 Released" line is the only
                // `text` block per release in every sample seen.
                if date == nil {
                    date = (block.properties?.title ?? []).compactMap(\.dateDay).first
                }
            case "bulleted_list":
                let line = notionText(block.properties?.title ?? [])
                    .trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { items.append(line) }
            default:
                break
            }
        }
        flush()

        return entries.isEmpty ? nil : Changelog(entries: entries)
    }

    /// Join a title's segments' visible text, dropping the bare `‣` placeholder a
    /// mention (date/user/page/comment) renders as in the raw JSON — it carries no
    /// useful text of its own. (A date mention's real value is read separately, via
    /// `NotionTitleSegment.dateDay`; a user/page/comment mention has no plain-text
    /// substitute at all, so it is simply omitted rather than shown as a stray `‣`.)
    private static func notionText(_ segments: [NotionTitleSegment]) -> String {
        segments.map { $0.text == "‣" ? "" : $0.text }.joined()
    }
}
