import Foundation

/// nodejs.org's own list of every Node release (`https://nodejs.org/dist/index.json`):
/// what nvm Node and fnm Node rows are checked on, with no spawn of either
/// manager (design §4.5/§4.6). It is fnm's source and carries nvm's
/// `index.tab` data (NODE-01).
///
/// Read 2026-10-27: 875 releases, 334,935 bytes, newest first, `cache-control:
/// public, max-age=3600` with an ETag, so a check revalidates it cheaply.
/// `lts` is the line's codename or `false`; `security` marks a security
/// release; `files` names the builds published — a release without this
/// Mac's (`osx-arm64-tar`) is one both managers would build from source, and
/// is never offered.
public enum NodeDistIndex {

    public static let source = URL(string: "https://nodejs.org/dist/index.json")!

    public struct Release: Sendable, Equatable {
        /// "22.23.4": without nodejs.org's `v`.
        public let version: String
        public let date: String?
        /// "Jod"; nil for a release outside LTS.
        public let lts: String?
        public let security: Bool
        public let files: [String]

        public var major: Int? { Int(version.prefix { $0 != "." }) }
    }

    /// The build file this Mac's managers install: `osx-arm64-tar` on Apple
    /// silicon, `osx-x64-tar` on Intel.
    public static var platformFile: String {
        #if arch(arm64)
        return "osx-arm64-tar"
        #else
        return "osx-x64-tar"
        #endif
    }

    public static func parse(_ data: Data) -> [Release]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let releases = list.compactMap { entry -> Release? in
            guard let tag = entry["version"] as? String, tag.hasPrefix("v") else { return nil }
            return Release(
                version: String(tag.dropFirst()), date: entry["date"] as? String, lts: entry["lts"] as? String,
                security: entry["security"] as? Bool ?? false, files: entry["files"] as? [String] ?? [])
        }
        return releases.isEmpty ? nil : releases
    }

    /// The newest release of `major` with a build for `platform`.
    static func newest(major: Int, in releases: [Release], platform: String) -> Release? {
        releases.filter { $0.major == major && $0.files.contains(platform) }
            .max { VersionComparator.compare($0.version, $1.version) == .orderedAscending }
    }

    public static func fetch() async throws -> Data {
        var request = URLRequest(url: source)
        request.cachePolicy = URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.updates.countedData(for: request, purpose: .versionCheck)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        return data
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case http(Int)
        public var description: String {
            switch self { case .http(let status): return "nodejs.org answered HTTP \(status)" }
        }
    }
}

/// What nvm Node and fnm Node share: one row per major (D1) from a manager's
/// version directories, and the check against `NodeDistIndex`.
enum NodeLines {

    /// One installed patch: `v22.21.1` → 22, "22.21.1".
    struct Patch {
        let directoryName: String
        let version: String
        let major: Int

        init?(directoryName: String) {
            guard directoryName.hasPrefix("v"), let version = NodePrefixes.versionName(directoryName),
                  let major = Int(version.prefix { $0 != "." }), major > 0,
                  version.split(separator: ".").count == 3
            else { return nil }
            self.directoryName = directoryName
            self.version = version
            self.major = major
        }
    }

    /// One item per major among `names` (the entries of `versions`), at its
    /// newest patch, older patches beside it. `node` is where a patch keeps its
    /// interpreter below its directory ("bin/node", "installation/bin/node"):
    /// a directory the manager is still writing has none, and is unreadable.
    /// `default` is the patch the manager's `default` alias names exactly, if
    /// any: the update leaves it there.
    static func items(
        names: [String], versions: String, root: String, node: String, default defaultPatch: String?,
        descriptor: ManagerDescriptor, extraEffects: [ManagedItem.Effect], exists: (String) -> Bool
    ) -> [ManagedItem] {
        var lines: [Int: [Patch]] = [:]
        for name in names {
            guard let patch = Patch(directoryName: name) else { continue }
            lines[patch.major, default: []].append(patch)
        }
        return lines.sorted { $0.key > $1.key }.map { major, patches in
            let ordered = patches.sorted { VersionComparator.compare($0.version, $1.version) == .orderedDescending }
            let newest = ordered[0]
            let directory = versions + "/" + newest.directoryName
            let older = ordered.dropFirst().map(\.version)
            var effects: [ManagedItem.Effect] = [.oldKept(for: nil)]
            var facts: [ManagedItem.Fact] = []
            if !older.isEmpty { facts.append(.alsoInstalled(older)) }
            if let defaultPatch, patches.contains(where: { $0.version == defaultPatch }) {
                facts.append(.defaultAlias(defaultPatch))
                if defaultPatch == newest.version { effects.append(.defaultStays(defaultPatch)) }
            }
            return ManagedItem(
                descriptor: descriptor, root: root, key: "v\(major)", name: "Node \(major)", installPath: directory,
                shape: .line, installed: exists(directory + "/" + node) ? newest.version : nil, alsoInstalled: older,
                notes: .rawMarkdown(NodeChangelog.source(major: major)), effects: effects + extraEffects, facts: facts)
        }
    }

    /// Each line against nodejs.org's list: offered when a newer patch of its
    /// major has this Mac's build. `moveDefault` spells the command that moves
    /// a `default` left on the old patch to the new one (D6), for the pane.
    static func verdicts(
        _ items: [ManagedItem], releases: [NodeDistIndex.Release]?, failure: String?, platform: String,
        moveDefault: (String) -> String
    ) -> [ManagedVerdict] {
        items.map { item in
            guard let installed = item.installed else { return ManagedVerdict(item: item, vendorWouldUpgrade: nil) }
            guard let releases else {
                return ManagedVerdict(
                    item: item, vendorWouldUpgrade: nil,
                    blocker: .channelUnreadable("nodejs.org/dist/index.json did not answer: \(failure ?? "unreadable")"))
            }
            guard let major = Int(item.key.dropFirst()),
                  let newest = NodeDistIndex.newest(major: major, in: releases, platform: platform)
            else {
                return ManagedVerdict(
                    item: item, vendorWouldUpgrade: nil,
                    blocker: .channelUnreadable("nodejs.org lists no \(item.name) build for this Mac"))
            }
            var answered = item.with(latestOverall: newest.version)
            if let lts = newest.lts { answered = answered.adding(fact: .note("LTS '\(lts)'")) }
            let newer = VersionComparator.isNewer(newest.version, than: installed)
            if newer {
                let security = releases.filter {
                    $0.major == major && $0.security && VersionComparator.isNewer($0.version, than: installed)
                        && !VersionComparator.isNewer($0.version, than: newest.version)
                }.count
                if security > 0 {
                    answered = answered.adding(fact: .note(
                        security == 1 ? "1 of the newer releases is a security release"
                            : "\(security) of the newer releases are security releases"))
                }
                if item.effects.contains(.defaultStays(installed)) {
                    answered = answered.adding(fact: .note("to move default afterwards: \(moveDefault(newest.version))"))
                }
            }
            return ManagedVerdict(item: answered, vendorWouldUpgrade: newer)
        }
    }
}

/// Node's own changelog of a major, `doc/changelogs/CHANGELOG_V<major>.md` on
/// `main` (NODE-05): raw, no API.
///
/// Read 2026-10-27 (V22: 887,419 bytes, `max-age=300` with an ETag; V24 the
/// same shape): each release is
///
///     <a id="22.23.4"></a>
///
///     ## 2026-10-21, Version 22.23.4 'Jod' (LTS), @aduh95
///
///     ### Notable Changes
///     …
///     ### Commits
///     …
///
/// newest first, under a table of links. Each section goes through
/// `GitHubMarkdownParser.parse(body:version:date:)`.
public enum NodeChangelog {

    public static func source(major: Int) -> URL {
        URL(string: "https://raw.githubusercontent.com/nodejs/node/main/doc/changelogs/CHANGELOG_V\(major).md")!
    }

    /// One entry per release section that yields any change, newest first;
    /// nil when there is none.
    public static func parse(_ markdown: String) -> Changelog? {
        let entries = sections(markdown).compactMap { section in
            GitHubMarkdownParser.parse(body: section.body.joined(separator: "\n"), version: section.version, date: section.date)?
                .entries.first
        }
        return entries.isEmpty ? nil : Changelog(entries: entries, itemSyntax: .markdown)
    }

    /// The `## <date>, Version <x.y.z> …` sections and their lines. Any other
    /// `#` or `##` heading ends the section before it. The `<a id>` anchor
    /// before each heading ends up in the section above, where the Markdown
    /// parser drops it with the other HTML.
    static func sections(_ markdown: String) -> [(version: String, date: String, body: [String])] {
        var result: [(version: String, date: String, body: [String])] = []
        var current: (version: String, date: String, body: [String])?
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

    /// `## 2026-10-21, Version 22.23.4 'Jod' (LTS), @aduh95` → ("22.23.4", "2026-10-21").
    static func heading(_ line: String) -> (version: String, date: String)? {
        let pattern = #"^## (\d{4}-\d{2}-\d{2}), Version (\d+\.\d+\.\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let date = Range(match.range(at: 1), in: line), let version = Range(match.range(at: 2), in: line)
        else { return nil }
        return (String(line[version]), String(line[date]))
    }

    static func fetch(_ url: URL, force: Bool, session: URLSession = .updates) async throws -> Changelog {
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : URLRequest.versionFeedCachePolicy
        request.timeoutInterval = 15
        let (data, response) = try await session.countedData(for: request, purpose: .changelog)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CLIToolReleaseNotesError.status(http, url: url)
        }
        let parsed = await offCooperativePool { parse(String(decoding: data, as: UTF8.self)) }
        guard let parsed else { throw CLIToolReleaseNotesError.noSections }
        return parsed
    }
}
