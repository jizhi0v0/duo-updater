import Foundation
import Testing
@testable import DuoKit
@testable import DuoUpdaterCore

@Suite struct AuditedUpdateFeedsTests {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func isElectron(_ entry: AuditedUpdateFeeds.Entry) -> Bool {
        if case .electron = entry.source { return true }
        return false
    }

    private func sparkleDetails(
        _ entry: AuditedUpdateFeeds.Entry
    ) -> (feed: URL, publicKey: String?, channelNames: Set<String>)? {
        guard case .sparkle(let feed, let publicKey, let channelNames) = entry.source else {
            return nil
        }
        return (feed, publicKey, channelNames)
    }

    private func entry(_ bundleID: String, trackID: String) -> AuditedUpdateFeeds.Entry? {
        AuditedUpdateFeeds.entries.first {
            $0.bundleID == bundleID && $0.trackID == trackID
        }
    }

    /// Reads only the authoritative section's app-audit links, stopping at the
    /// next level-two heading so later audit categories do not inflate coverage.
    private func indexedAuditDocuments(in section: String) throws -> Set<String> {
        let readmeURL = repositoryRoot.appending(path: "docs/app-audits/README.md")
        let lines = try String(contentsOf: readmeURL, encoding: .utf8)
            .components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("## \(section) ") }) else {
            Issue.record("Missing README section: \(section)")
            return []
        }

        var documents = Set<String>()
        for line in lines.dropFirst(start + 1) {
            if line.hasPrefix("## ") { break }
            guard line.hasPrefix("- [x] "),
                  let linkStart = line.range(of: "](")?.upperBound,
                  let linkEnd = line[linkStart...].firstIndex(of: ")")
            else { continue }
            let target = String(line[linkStart..<linkEnd])
            guard target.hasSuffix(".md") else { continue }
            documents.insert("docs/app-audits/\(target)")
        }
        return documents
    }

    private func fileExists(_ repoRelativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: repositoryRoot.appending(path: repoRelativePath).path)
    }

    @Test func recipeIDsAreUniqueAndCopyGroupsRemainDistinct() {
        let ids = AuditedUpdateFeeds.entries.map(\.recipeID)
        #expect(ids.count == Set(ids).count, "duplicate recipe IDs: \(ids)")

        let douchat = AuditedUpdateFeeds.entries.filter {
            $0.bundleID == "ai.thinkany.douchat"
        }
        #expect(douchat.count == 2)
        #expect(Set(douchat.map(\.recipeID)) == [
            "electron:ai.thinkany.douchat:stable:legacy-root",
            "electron:ai.thinkany.douchat:stable:thinkany",
        ])
    }

    @Test func allCatalogURLsArePublicHTTPSWithoutCredentialsOrQuery() {
        #expect(AuditedUpdateFeeds.entries.count == 73)
        for entry in AuditedUpdateFeeds.entries {
            let url: URL?
            if case .electron(let config) = entry.source {
                url = config.url.flatMap(URL.init(string:))
            } else {
                url = sparkleDetails(entry)?.feed
            }
            guard let url else {
                Issue.record("Missing or invalid URL for \(entry.recipeID)")
                continue
            }
            #expect(url.scheme == "https", "non-HTTPS URL: \(entry.recipeID)")
            #expect(url.host != nil, "URL without public host: \(entry.recipeID)")
            #expect(url.user == nil && url.password == nil,
                    "credentials in URL: \(entry.recipeID)")
            #expect(url.query == nil && url.fragment == nil,
                    "query or fragment in catalog URL: \(entry.recipeID)")
        }
    }

    @Test func catalogCoversEveryIndexedRowOrNamesAWholeRowGap() throws {
        let electronRows = try indexedAuditDocuments(in: "Electron-covered")
        let sparkleRows = try indexedAuditDocuments(in: "Sparkle-covered")
        let electronEntries = AuditedUpdateFeeds.entries.filter(isElectron)
        let sparkleEntries = AuditedUpdateFeeds.entries.filter { sparkleDetails($0) != nil }
        let electronDocuments = Set(electronEntries.map(\.auditDocument))
        let sparkleDocuments = Set(sparkleEntries.map(\.auditDocument))
        let excludedDocuments = Set(AuditedUpdateFeeds.uncoveredRows.map(\.auditDocument))

        #expect(electronEntries.count == 12)
        #expect(sparkleEntries.count == 61)
        #expect(electronDocuments == electronRows)
        #expect(sparkleDocuments.isDisjoint(with: excludedDocuments))
        #expect(sparkleDocuments.union(excludedDocuments) == sparkleRows)
        #expect(excludedDocuments == [
            "docs/app-audits/now-typeless-desktop.md",
            "docs/app-audits/com-openai-atlas.md",
        ])

        for document in electronDocuments.union(sparkleDocuments)
            .union(excludedDocuments)
        {
            #expect(fileExists(document), "missing audit document: \(document)")
        }

        let allIndexedDocuments = electronRows.union(sparkleRows)
        #expect(AuditedUpdateFeeds.uncoveredTracks.allSatisfy {
            !allIndexedDocuments.isDisjoint(with: [$0.auditDocument])
                && !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && fileExists($0.auditDocument)
        })
        let trackGapIDs = AuditedUpdateFeeds.uncoveredTracks.map(\.id)
        #expect(trackGapIDs.count == Set(trackGapIDs).count)
    }

    @Test func criticalElectronAndSparkleConfigurationsKeepTheirTracks() throws {
        let legacyDouchat = try #require(entry("ai.thinkany.douchat", trackID: "stable"))
        let currentDouchat = try #require(AuditedUpdateFeeds.entries.first {
            $0.bundleID == "ai.thinkany.douchat" && $0.copyGroup == "thinkany"
        })
        guard case .electron(let legacyConfig) = legacyDouchat.source,
              case .electron(let currentConfig) = currentDouchat.source
        else {
            Issue.record("Douchat should remain an Electron feed")
            return
        }
        #expect(legacyDouchat.copyGroup == "legacy-root")
        #expect(legacyConfig.url == "https://cdn.douchat.ai")
        #expect(currentConfig.url == "https://cdn.douchat.ai/thinkany")
        #expect(legacyConfig.channel == "latest" && currentConfig.channel == "latest")
        #expect(legacyDouchat.recipeID != currentDouchat.recipeID)

        let dsh = try #require(entry("com.deepseek.dsh", trackID: "stable"))
        guard case .electron(let dshConfig) = dsh.source else {
            Issue.record("DeepSeek Harness should remain an Electron feed")
            return
        }
        #expect(dsh.channel == .stable)
        #expect(dshConfig.channel == "nightly")
        #expect(dshConfig.url == "https://download.deepseek.com/dsh-desk/feeds/mac-arm64/")

        let testRelease = try #require(entry(
            "com.googlecode.iterm2", trackID: "test-release"))
        let testReleaseDetails = try #require(sparkleDetails(testRelease))
        #expect(testRelease.channel == .beta)
        #expect(testReleaseDetails.feed.absoluteString
            == "https://iterm2.com/appcasts/testing_modern.xml")
        #expect(testReleaseDetails.channelNames.isEmpty)
        #expect(testReleaseDetails.publicKey
            == "xdqAa0KXBPhMbUrutVTe87i6U7yWf7WKaCeRG7AAZ0w=")

        let rc = try #require(entry("com.typewhisper.mac", trackID: "release-candidate"))
        let rcDetails = try #require(sparkleDetails(rc))
        #expect(rc.channel == .rc)
        #expect(rcDetails.channelNames == ["release-candidate"])
        let daily = try #require(entry("com.typewhisper.mac", trackID: "daily"))
        let dailyDetails = try #require(sparkleDetails(daily))
        #expect(daily.channel == .nightly)
        #expect(dailyDetails.channelNames == ["daily"])

        let snapshot = try #require(entry(
            "com.vivaldi.Vivaldi.snapshot", trackID: "snapshot"))
        #expect(snapshot.channel == .preview)

        let pdfExpert = try #require(entry("com.readdle.PDFExpert-Mac", trackID: "stable"))
        #expect(sparkleDetails(pdfExpert)?.feed.absoluteString
            == "https://downloads.pdfexpert.com/pem3/release/appcast.xml")
        #expect(sparkleDetails(pdfExpert)?.publicKey
            == "K5sdt9UTWp/TcP48oRVycKUqWUbi0Tp37zrWtFYCCfw=")

        let kuvoCode = try #require(entry("run.kuvo.code", trackID: "stable"))
        #expect(sparkleDetails(kuvoCode)?.publicKey
            == "uG/YbzL4kf+DAYCiTTfK8ztEOBo96hkEAuKk9rw9BE4=")
    }

    @Test func syntheticAppsCarryAnExplicitNonInstalledChannel() throws {
        let beta = try #require(entry("com.colliderli.iina", trackID: "beta"))
        let app = beta.app
        #expect(app.bundleID == beta.bundleID)
        #expect(app.releaseChannel == .beta)
        #expect(app.channelIsAuthoritative)
        #expect(app.path.path.hasPrefix("/__duo_audited_feed_catalog__/"))
        #expect(!FileManager.default.fileExists(atPath: app.path.path))
        #expect(app.shortVersion == "0" && app.buildVersion == "0")
        #expect(app.hasSparkleUpdater && app.electronUpdate == nil)
        #expect(app.sparkleFeedURL?.absoluteString == "https://www.iina.io/appcast-beta.xml")
    }

    @Test func pawKeepsTheLegacyAndCurrentKeyGroups() throws {
        let entries = AuditedUpdateFeeds.entries.filter { $0.bundleID == "com.luckymarmot.Paw" }
        #expect(Set(entries.map(\.recipeID)) == [
            "sparkle:com.luckymarmot.Paw:stable:ed25519",
            "sparkle:com.luckymarmot.Paw:stable:legacy-dsa",
        ])
        let current = try #require(entries.first { $0.copyGroup == "ed25519" })
        let legacy = try #require(entries.first { $0.copyGroup == "legacy-dsa" })
        #expect(sparkleDetails(current)?.publicKey == "EbtjNsFuPe0o0UZDSFr/514GIusvouXngkfdmiKApHY=")
        #expect(sparkleDetails(legacy)?.publicKey == nil)
        for entry in entries {
            #expect(sparkleDetails(entry)?.feed.absoluteString == "https://paw.cloud/api/v2/updates/appcast")
            #expect(sparkleDetails(entry)?.channelNames.isEmpty == true)
        }
    }

    @Test func everyKnownPublicKeyIsAValidSparkleKeyAndEveryMissingOneIsExplained() {
        let sparkleEntries = AuditedUpdateFeeds.entries.filter { sparkleDetails($0) != nil }
        let keyedBundleIDs = Set(sparkleEntries.compactMap { item -> String? in
            sparkleDetails(item)?.publicKey == nil ? nil : item.bundleID
        })
        let missingBundleIDs = Set(sparkleEntries.compactMap { item -> String? in
            sparkleDetails(item)?.publicKey == nil ? item.bundleID : nil
        })
        let gaps = AuditedUpdateFeeds.unavailablePublicKeys
        let gapBundleIDs = Set(gaps.map(\.bundleID))

        #expect(keyedBundleIDs.count == 21)
        #expect(missingBundleIDs.count == 25)
        #expect(gapBundleIDs == missingBundleIDs)
        #expect(gaps.count == gapBundleIDs.count)

        for item in sparkleEntries {
            guard let key = sparkleDetails(item)?.publicKey else { continue }
            #expect(Data(base64Encoded: key)?.count == 32,
                      "invalid EdDSA public key for \(item.recipeID)")
        }
        for gap in gaps {
            #expect(!gap.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(fileExists(gap.auditDocument), "missing key audit: \(gap.auditDocument)")
            #expect(sparkleEntries.contains { $0.bundleID == gap.bundleID })
        }
    }
}
