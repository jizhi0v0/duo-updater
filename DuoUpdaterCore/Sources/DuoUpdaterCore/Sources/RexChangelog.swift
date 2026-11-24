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
        public var serverVersion: String? { serverReference?.version }
        public var canRetry: Bool { mac == .failed || server == .failed }
        fileprivate let serverReference: Reference?
    }

    typealias Fetch = @Sendable (URL) async -> (body: String?, status: Int?)

    public static func load(_ entry: Changelog.Entry, retrying previous: Sections? = nil) async -> Sections? {
        await load(entry, retrying: previous) { await ChangelogService.fetch($0, session: .updates) }
    }

    static func load(
        _ entry: Changelog.Entry, retrying previous: Sections? = nil, fetch: Fetch
    ) async -> Sections? {
        guard entry.titleNamesVersionAndBuild, let title = entry.title,
              let build = Int(title.dropFirst(entry.version.count + 2).dropLast())
        else { return nil }
        return await load(build: build, summary: entry.markdown, retrying: previous, fetch: fetch)
    }

    static func load(
        build: Int, summary: String?, retrying previous: Sections? = nil, fetch: Fetch
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

        let decodedIndex: Index? = decode(await fetch(base.appending(path: "index.json")).body)
        let index = decodedIndex?.schemaVersion == 1 ? decodedIndex : nil
        let mac: Section
        let serverReference: Reference?
        if let previous, previous.mac != .failed {
            mac = previous.mac
            serverReference = previous.serverReference
        } else if let index {
            let entries = index.releases.filter { $0.platform == "mac" && $0.build == build }
            if entries.isEmpty {
                mac = .unpublished
                serverReference = feedServer
            } else if entries.count == 1, let entry = entries.first,
                      let release = await release(platform: "mac", version: entry.version, fetch: fetch).detail,
                      release.build == build, macCommit.map({ $0 == release.commit }) ?? true {
                mac = .published(release.markdown)
                // The appcast's commit identifies the bundled Server. Release JSON
                // can name a different version alias for that same commit.
                let included = release.includes?.first { $0.platform == "server" }
                if let included, feedServer.map({ $0.commit == included.commit }) ?? true {
                    serverReference = included
                } else {
                    serverReference = feedServer
                }
            } else {
                mac = .failed
                serverReference = feedServer
            }
        } else {
            mac = .failed
            serverReference = feedServer
        }

        let server: Section
        if let previous, previous.server != .failed, previous.serverReference == serverReference {
            server = previous.server
        } else if let ref = serverReference {
            let response = await release(platform: "server", version: ref.version, fetch: fetch)
            if let detail = response.detail, detail.commit == ref.commit {
                server = .published(detail.markdown)
            } else if response.status == 404, let index,
                      !index.releases.contains(where: { $0.platform == "server" && $0.version == ref.version }) {
                server = .unpublished
            } else {
                server = .failed
            }
        } else {
            server = .unidentified
        }
        return Sections(mac: mac, server: server, serverReference: serverReference)
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

    fileprivate struct Reference: Decodable, Equatable, Sendable {
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
        platform: String, version: String, fetch: Fetch
    ) async -> (detail: Release?, status: Int?) {
        guard version.wholeMatch(of: /[0-9][A-Za-z0-9.-]*/) != nil else { return (nil, nil) }
        let url = base.appending(path: platform).appending(path: version + ".json")
        let response = await fetch(url)
        let release: Release? = decode(response.body)
        guard let release, release.schemaVersion == 1,
              release.platform == platform, release.version == version,
              !release.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return (nil, response.status) }
        return (release, response.status)
    }

    private static func decode<Value: Decodable>(_ body: String?) -> Value? {
        guard let body else { return nil }
        return try? JSONDecoder().decode(Value.self, from: Data(body.utf8))
    }
}
