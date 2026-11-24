import Foundation

/// Rex publishes component notes separately from its signed Sparkle summaries.
public enum RexChangelog {
    private static let base = URL(string: "https://blob.superlogical.com/public/changelog/")!

    public static func feed(for result: UpdateResult) -> URL? {
        guard result.app.bundleID?.lowercased() == RexChannel.bundleID,
              !result.app.isMASApp, result.remote?.sourceName == "Sparkle",
              let feed = result.app.sparkleFeedURL,
              feed == RexChannel.previewFeed || feed == RexChannel.snapshotFeed
        else { return nil }
        return feed
    }

    public enum Section: Equatable, Sendable {
        case published(String)
        case unpublished
        case failed
        case unidentified
    }

    public struct Sections: Sendable {
        public let mac: Section
        public let server: Section
        public let serverVersion: String?
    }

    public static func load(_ entry: Changelog.Entry) async -> Sections? {
        await load(entry) { await ChangelogService.fetchBody($0, session: .updates) }
    }

    static func load(
        _ entry: Changelog.Entry, fetch: @Sendable (URL) async -> String?
    ) async -> Sections? {
        guard entry.titleNamesVersionAndBuild, let title = entry.title,
              let build = Int(title.dropFirst(entry.version.count + 2).dropLast())
        else { return nil }
        return await load(build: build, summary: entry.markdown, fetch: fetch)
    }

    static func load(
        build: Int, summary: String?, fetch: @Sendable (URL) async -> String?
    ) async -> Sections {
        let lines = summary?.split(whereSeparator: \.isNewline) ?? []
        let feedServer = lines.lazy.compactMap { line -> Reference? in
            guard let match = line.wholeMatch(of: /Rex ([A-Za-z0-9.-]+) \(`([0-9a-f]{40})`\)/)
            else { return nil }
            return Reference(platform: "server", version: String(match.1), commit: String(match.2))
        }.first
        let macCommit = lines.lazy.compactMap { line -> String? in
            guard let match = line.wholeMatch(
                of: #/\[View Rex\.app commit [^\]]+\]\(https://github\.com/superlogical/rex-app/commit/([0-9a-f]{40})\)/#
            ) else { return nil }
            return String(match.1)
        }.first

        let index: Index? = decode(await fetch(base.appending(path: "index.json")))
        let macEntries = index?.releases.filter { $0.platform == "mac" && $0.build == build } ?? []
        var macRelease: Release?
        let mac: Section
        if index?.schemaVersion != 1 {
            mac = .failed
        } else if macEntries.isEmpty {
            mac = .unpublished
        } else if macEntries.count == 1, let entry = macEntries.first,
                  let release = await release(platform: "mac", version: entry.version, fetch: fetch),
                  release.build == build, macCommit.map({ $0 == release.commit }) ?? true {
            macRelease = release
            mac = .published(release.markdown)
        } else {
            mac = .failed
        }

        let serverReference = macRelease?.includes?.first(where: { $0.platform == "server" }) ?? feedServer
        let server: Section
        if let ref = serverReference {
            if let release = await release(platform: "server", version: ref.version, fetch: fetch),
               release.commit == ref.commit {
                server = .published(release.markdown)
            } else {
                server = .failed
            }
        } else {
            server = .unidentified
        }
        return Sections(mac: mac, server: server, serverVersion: serverReference?.version)
    }

    private struct Index: Decodable {
        struct Entry: Decodable {
            let platform: String
            let build: Int?
            let version: String
        }

        let schemaVersion: Int
        let releases: [Entry]
    }

    private struct Reference: Decodable {
        let platform: String
        let version: String
        let commit: String
    }

    private struct Release: Decodable {
        let schemaVersion: Int
        let platform: String
        let build: Int?
        let version: String
        let commit: String
        let markdown: String
        let includes: [Reference]?
    }

    private static func release(
        platform: String, version: String, fetch: @Sendable (URL) async -> String?
    ) async -> Release? {
        guard version.wholeMatch(of: /[0-9][A-Za-z0-9.-]*/) != nil else { return nil }
        let url = base.appending(path: platform).appending(path: version + ".json")
        let release: Release? = decode(await fetch(url))
        guard let release, release.schemaVersion == 1,
              release.platform == platform, release.version == version,
              !release.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return release
    }

    private static func decode<Value: Decodable>(_ body: String?) -> Value? {
        guard let body else { return nil }
        return try? JSONDecoder().decode(Value.self, from: Data(body.utf8))
    }
}
