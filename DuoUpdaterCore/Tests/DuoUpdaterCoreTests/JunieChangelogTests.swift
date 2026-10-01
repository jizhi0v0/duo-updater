import Testing
import Foundation
@testable import DuoUpdaterCore

/// Junie's release notes: which builds' GitHub Releases are asked for, and what
/// each answer becomes. The fetch is injected; nothing reaches the network.
@Suite struct JunieChangelogTests {

    /// The release channel's macOS builds from 3013.4 up, as `update-info.jsonl`
    /// listed them on 2026-10-02.
    static let builds = ["3013.4", "3013.5", "3013.7", "3110.6", "3110.7", "3196.4", "3196.5", "3294.5",
                         "3419.7", "3419.19", "3419.22", "3419.26", "1543.24"]

    /// A release object shaped like `releases/tags/3419.26` (2026-10-02).
    static func release(_ build: String, body: String?, draft: Bool = false) -> Data {
        var object: [String: Any] = [
            "tag_name": build, "name": "Junie Release 26.9.22 (\(build))", "draft": draft, "prerelease": false,
            "published_at": "2026-10-01T13:50:26Z",
        ]
        object["body"] = body ?? NSNull()
        return try! JSONSerialization.data(withJSONObject: object)
    }

    /// The unseen builds, newest first and at most `maximumRequests` of them, up to
    /// the channel's latest. Mutation: taking the unseen list's `suffix` (its
    /// oldest) instead of its `prefix` fails the first expectation.
    @Test func windowIsTheNewestUnseenBuilds() {
        let window = JunieChangelog.window(builds: Self.builds, installed: "1543.24", latest: "3419.26")
        #expect(window == ["3419.26", "3419.22", "3419.19", "3419.7", "3294.5", "3196.5", "3196.4", "3110.7"])
        // A build above the reader's latest is not theirs to read about yet.
        #expect(JunieChangelog.window(builds: Self.builds, installed: "3419.19", latest: "3419.22")
            == ["3419.22", "3419.19", "3419.7", "3294.5", "3196.5"])
    }

    /// Up to date, the reader still sees what their build and the ones before it
    /// brought.
    @Test func upToDateReadersGetTheirOwnBuilds() {
        #expect(JunieChangelog.window(builds: Self.builds, installed: "3419.26", latest: "3419.26")
            == ["3419.26", "3419.22", "3419.19", "3419.7", "3294.5"])
        #expect(JunieChangelog.window(builds: Self.builds, installed: nil, latest: nil)
            == ["3419.26", "3419.22", "3419.19", "3419.7", "3294.5"])
    }

    @Test func aReleaseBecomesAnEntry() throws {
        let entry = try #require(JunieChangelog.parse(
            Self.release("3419.19", body: "- Claude Sonnet 5.5 support\n- Fixed an issue causing false safety refusals with Claude Opus 5"),
            build: "3419.19"))
        #expect(entry.version == "3419.19")
        #expect(entry.date == "2026-10-01")
        #expect(entry.items == ["Claude Sonnet 5.5 support", "Fixed an issue causing false safety refusals with Claude Opus 5"])
    }

    /// An empty body is "no notes"; a draft, or another build's release, is not this
    /// build's notes.
    @Test func emptyDraftAndForeignReleasesGiveNoEntry() {
        #expect(JunieChangelog.parse(Self.release("3196.5", body: ""), build: "3196.5") == nil)
        #expect(JunieChangelog.parse(Self.release("3196.5", body: nil), build: "3196.5") == nil)
        #expect(JunieChangelog.parse(Self.release("3196.5", body: "  \n"), build: "3196.5") == nil)
        #expect(JunieChangelog.parse(Self.release("3196.5", body: "- x", draft: true), build: "3196.5") == nil)
        #expect(JunieChangelog.parse(Self.release("3196.4", body: "- x"), build: "3196.5") == nil)
        #expect(JunieChangelog.parse(Data("{}".utf8), build: "3196.5") == nil)
    }

    final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    /// One request per build in the window, newest first in the result; a missing
    /// release (404) and an empty body are simply absent.
    @Test func fetchAsksEachBuildAndKeepsTheOnesWithNotes() async throws {
        let asked = Asked()
        let changelog = try await JunieChangelog.fetch(
            builds: Self.builds, installed: "3196.4", latest: "3419.26", force: false,
            fetch: { url, _ in
                asked.add(url.absoluteString)
                let build = url.lastPathComponent
                switch build {
                case "3419.22": return (Data(), 404)
                case "3294.5", "3196.5": return (Self.release(build, body: ""), 200)
                default: return (Self.release(build, body: "- notes of \(build)"), 200)
                }
            })
        #expect(changelog.entries.map(\.version) == ["3419.26", "3419.19", "3419.7"])
        #expect(changelog.itemSyntax == .markdown)
        #expect(Set(asked.all) == Set(["3419.26", "3419.22", "3419.19", "3419.7", "3294.5", "3196.5"].map {
            "https://api.github.com/repos/JetBrains/junie/releases/tags/\($0)"
        }))
    }

    /// Nothing answered: an error, not "no notes". Something answered: what did.
    @Test func onlyATotalFailureThrows() async throws {
        await #expect(throws: CLIToolReleaseNotesError.http(403)) {
            try await JunieChangelog.fetch(
                builds: Self.builds, installed: "3419.19", latest: "3419.26", force: false,
                fetch: { _, _ in (Data(), 403) })
        }
        let partial = try await JunieChangelog.fetch(
            builds: Self.builds, installed: "3419.19", latest: "3419.26", force: false,
            fetch: { url, _ in
                url.lastPathComponent == "3419.26" ? (Self.release("3419.26", body: "- Added Junie Lite"), 200) : (Data(), 403)
            })
        #expect(partial.entries.map(\.version) == ["3419.26"])
        let empty = try await JunieChangelog.fetch(
            builds: Self.builds, installed: "3419.19", latest: "3419.26", force: false,
            fetch: { url, _ in (Self.release(url.lastPathComponent, body: ""), 200) })
        #expect(empty.entries.isEmpty)
    }
}
