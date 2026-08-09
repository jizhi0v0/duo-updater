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

    /// `v0.2026.06.10.09.27.stable_01` → `0.2026.06.10.09.27` — drop the leading `v`
    /// and the trailing `.<channel>_NN` build suffix, matching the form the vendor
    /// probe reports (and the docs site's old `(v…)` heading) so the rail label lines
    /// up with the version shown elsewhere in the app.
    static func displayVersion(fromKey key: String) -> String {
        var v = key.hasPrefix("v") ? String(key.dropFirst()) : key
        v = v.replacingOccurrences(
            of: #"\.[a-z]+_\d+$"#, with: "", options: .regularExpression)
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
            .split(separator: "\n", omittingEmptySubsequences: true)
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
}
