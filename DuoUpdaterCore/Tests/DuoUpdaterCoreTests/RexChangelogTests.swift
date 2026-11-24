import Foundation
import Testing
@testable import DuoUpdaterCore

struct RexChangelogTests {
    // The vendor index includes separate Mac and Server entries with the same version name.
    private static let index = """
        {"schemaVersion":1,"releases":[
          {"platform":"server","version":"0.1.0-preview.23","build":null},
          {"platform":"mac","version":"0.1.0-preview.33","build":2061},
          {"platform":"mac","version":"0.1.0-preview.23","build":1642}
        ]}
        """
    private static let preview = "202b1b3fc0219883112258a8d0f9f95e2d47daa9"
    private static let snapshot = "c67cc2d0c88ecc86f5d751079b809dd9e9047636"
    private static let macCommit = "1a480a41a003ce9c3488c647cae2c747abaf5d23"
    private static let macPath = "/public/changelog/mac/0.1.0-preview.33.json"
    private static let serverPath = "/public/changelog/server/0.1.0-preview.23.json"
    private static let indexPath = "/public/changelog/index.json"
    private static let macNotes = "- Tabs along the bottom."
    private static let serverNotes = "- REX_BLOCK replaces REX_SESSION."

    @Test func previewUsesTheMacBuildAndFollowsItsEmbeddedServerReference() async {
        let responses = [
            Self.indexPath: Self.index,
            Self.macPath: """
                {"schemaVersion":1,"platform":"mac","build":2061,"version":"0.1.0-preview.33",
                "commit":"\(Self.macCommit)","markdown":"\(Self.macNotes)","includes":[
                  {"platform":"server","version":"0.1.0-preview.21","commit":"\(Self.preview)"}
                ]}
                """,
            "/public/changelog/server/0.1.0-preview.21.json": Self.server(
                version: "0.1.0-preview.21", commit: Self.preview, notes: "- Closing terminals.")
        ]
        let summary = """
            Preview 2061

            [View Rex.app commit 1a480a41a003](https://github.com/superlogical/rex-app/commit/\(Self.macCommit))
            """
        let notes = await RexChangelog.load(build: 2061, summary: summary) { responses[$0.path] }
        #expect(notes.mac == .published(Self.macNotes))
        #expect(notes.server == .published("- Closing terminals."))
        #expect(notes.serverVersion == "0.1.0-preview.21")
    }

    @Test func historicalSnapshotUsesTheServerVersionAndCommitFromItsOwnSummary() async throws {
        let responses = [
            Self.indexPath: Self.index,
            Self.serverPath: Self.server(version: "0.1.0-preview.23", commit: Self.snapshot)
        ]
        let older = Self.snapshotSummary.replacingOccurrences(of: "Snapshot 2104", with: "Snapshot 2103")
        let xml = """
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
              <item><sparkle:version>2104</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <description sparkle:format="markdown"><![CDATA[\(Self.snapshotSummary)]]></description></item>
              <item><sparkle:version>2103</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <description sparkle:format="markdown"><![CDATA[\(older)]]></description></item>
            </channel></rss>
            """
        let items = SparkleAppcastSource.parsedItems(
            Data(xml.utf8), feedURL: RexChannel.snapshotFeed, bundleID: RexChannel.bundleID)
        let history = try #require(SparkleAppcastSource.structuredChangelog(
            from: items, bundleID: RexChannel.bundleID))
        let entry = try #require(history.entries.first { $0.title == "0.1.0 (2103)" })
        #expect(entry.markdown == older)
        let notes = try #require(await RexChangelog.load(entry) { responses[$0.path] })
        #expect(notes.mac == .unpublished)
        #expect(notes.server == .published(Self.serverNotes))
        #expect(notes.serverVersion == "0.1.0-preview.23")
    }

    @Test func missingIndexAndWrongCommitAreFailures() async {
        let notes = await RexChangelog.load(build: 2104, summary: Self.snapshotSummary) { url in
            guard url.path == Self.serverPath else { return nil }
            return Self.server(version: "0.1.0-preview.23", commit: Self.preview)
        }
        #expect(notes.mac == .failed)
        #expect(notes.server == .failed)
    }

    @Test func indexedMacWithMissingBodyDoesNotLookUnpublished() async {
        let notes = await RexChangelog.load(build: 2061, summary: nil) {
            $0.path == Self.indexPath ? Self.index : nil
        }
        #expect(notes.mac == .failed)
        #expect(notes.server == .unidentified)
    }

    @Test func usesTheSelectedFeedEvenWhenInstalledSnapshotIsNewerThanPreview() {
        let app = InstalledApp(
            name: "Rex", bundleID: RexChannel.bundleID, shortVersion: "0.1.0", buildVersion: "2104",
            path: URL(fileURLWithPath: "/Rex.app"), isMASApp: false,
            sparkleFeedURL: RexChannel.previewFeed)
        let remote = RemoteVersion(
            shortVersion: "0.1.0", version: "2061", downloadURL: nil, sourceName: "Sparkle")
        let result = UpdateResult(app: app, remote: remote, status: .upToDate)
        #expect(RexChangelog.feed(for: result) == RexChannel.previewFeed)
    }

    private static var snapshotSummary: String {
        """
        Snapshot 2104

        Rex 0.1.0-preview.23 (`\(snapshot)`)
        """
    }

    private static func server(version: String, commit: String, notes: String = serverNotes) -> String {
        """
        {"schemaVersion":1,"platform":"server","version":"\(version)","build":null,
        "commit":"\(commit)","includes":[],"markdown":"\(notes)"}
        """
    }
}
