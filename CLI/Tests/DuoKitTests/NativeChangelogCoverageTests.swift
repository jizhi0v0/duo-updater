import Foundation
import Testing
@testable import DuoKit
@testable import DuoUpdaterCore

@Suite struct NativeChangelogCoverageTests {

    private struct ObservedEntry: Sendable {
        let bundleID: String
        let channel: ReleaseChannel
        let recipeID: String
    }

    private actor CallLog {
        private var items: [ObservedEntry] = []

        func append(_ entry: AuditedUpdateFeeds.Entry) {
            items.append(ObservedEntry(
                bundleID: entry.bundleID, channel: entry.channel, recipeID: entry.recipeID))
        }

        func snapshot() -> [ObservedEntry] { items }
    }

    private func gap(_ bundleID: String) -> Finding {
        Finding(
            recipeID: "coverage:\(bundleID)", registry: .changelogCoverage,
            bundleID: bundleID, channel: "-", status: .warn,
            failureKind: "noChangelogRecipe",
            failureDetail: "links a changelog page (https://notes.example.invalid/\(bundleID)) "
                + "but has no ChangelogRecipe. Source-native structured notes have not yet been checked.",
            endpointHost: "notes.example.invalid")
    }

    private func recipe(_ bundleID: String) -> ChangelogRecipe {
        ChangelogRecipe(
            bundleID: bundleID,
            source: URL(string: "https://notes.example.invalid/\(bundleID)")!,
            entryPattern: #"<h2>(?<version>[0-9.]+)</h2>"#,
            itemPatterns: [#"<li>(?<item>[^<]+)</li>"#])
    }

    private static func remote(_ changelog: Changelog?) -> RemoteVersion {
        RemoteVersion(
            shortVersion: "0.1.3", version: "0.1.3", downloadURL: nil,
            sourceName: "Sparkle", structuredChangelog: changelog)
    }

    private static func outcome(
        for entry: AuditedUpdateFeeds.Entry,
        changelog: Changelog? = nil,
        failure: ProbeFailure? = nil
    ) -> ProbeOutcome {
        ProbeOutcome(
            recipeID: entry.recipeID, bundleID: entry.bundleID, channel: entry.channel,
            remote: failure == nil ? Self.remote(changelog) : nil,
            failure: failure)
    }

    private func kuvoBoxFeed() throws -> AuditedUpdateFeeds.Entry {
        try #require(AuditedUpdateFeeds.entries.first {
            $0.bundleID == "run.kuvo.app" && $0.channel == .stable
        })
    }

    @Test func kuvoNativeListClosesTheRealCatalogGapWithoutAcknowledgement() async throws {
        #expect(ChangelogCoverage.acknowledged["run.kuvo.app"] == nil)
        let original = try #require(ChangelogCoverage.findings(
            probes: [], recipes: [], acknowledged: [:]
        ).first { $0.bundleID == "run.kuvo.app" })
        #expect(original.recipeID == "coverage:run.kuvo.app")
        #expect(original.status == .warn)
        #expect(original.failureKind == "noChangelogRecipe")

        let sourceEntry = try kuvoBoxFeed()
        let native = Changelog(entries: [
            .init(version: "0.1.3", date: nil, items: ["What’s new", "Fixed a bug"]),
            .init(version: "0.1.2", date: nil, items: ["Improved reliability"]),
        ])
        let result = await ChangelogCoverage.checkNativeSources(
            [original], entries: [sourceEntry],
            resolve: { _ in Self.outcome(for: sourceEntry, changelog: native) })

        let finding = try #require(result.first)
        #expect(result.count == 1)
        #expect(finding.recipeID == original.recipeID)
        #expect(finding.status == .ok)
        #expect(finding.failureKind == nil)
        #expect(finding.failureDetail == nil)
        #expect(finding.entryCount == nil)
        #expect(finding.entryVersions == nil)
        #expect(finding.endpointHost == "github.com")
    }

    @Test func nativeFeedTwoToOneDoesNotEnterBaselineCollapseHistory() async throws {
        let sourceEntry = try kuvoBoxFeed()
        let original = gap("run.kuvo.app")
        let lists = [
            Changelog(entries: [
                .init(version: "0.1.3", date: nil, items: ["First change"]),
                .init(version: "0.1.2", date: nil, items: ["Earlier change"]),
            ]),
            Changelog(entries: [
                .init(version: "0.1.3", date: nil, items: ["First change"]),
            ]),
        ]
        var baseline = Baseline()

        for list in lists {
            let result = await ChangelogCoverage.checkNativeSources(
                [original], entries: [sourceEntry],
                resolve: { _ in Self.outcome(for: sourceEntry, changelog: list) })
            let finding = try #require(result.first)
            #expect(finding.status == .ok)
            #expect(finding.entryCount == nil)
            #expect(baseline.reconcile(finding).isEmpty)
        }

        #expect(baseline.entries[original.recipeID]?.lastGoodEntryCount == nil)
    }

    @Test func missingNativeNotesKeepTheGapWithAccurateWording() async throws {
        let sourceEntry = try kuvoBoxFeed()
        let original = gap("run.kuvo.app")
        for changelog in [nil, Changelog(entries: [
            .init(version: "0.1.3", date: nil, items: ["  ", "\n"]),
        ])] as [Changelog?] {
            let result = await ChangelogCoverage.checkNativeSources(
                [original], entries: [sourceEntry],
                resolve: { _ in Self.outcome(for: sourceEntry, changelog: changelog) })
            let finding = try #require(result.first)
            #expect(finding.status == .warn)
            #expect(finding.recipeID == original.recipeID)
            #expect(finding.failureKind == "noChangelogRecipe")
            #expect(finding.failureDetail?.contains("neither a ChangelogRecipe nor source-native structured notes were found") == true)
            #expect(finding.failureDetail?.contains("embeds the page") == false)
            #expect(finding.entryCount == nil)
            #expect(finding.entryVersions == nil)
        }
    }

    @Test func transientFeedFailuresAreInfraRatherThanMissingNotes() async throws {
        let sourceEntry = try kuvoBoxFeed()
        let original = gap("run.kuvo.app")
        let failures: [ProbeFailure] = [
            .transport(urlErrorCode: -1001, "timed out"),
            .httpStatus(503),
        ]
        for failure in failures {
            let result = await ChangelogCoverage.checkNativeSources(
                [original], entries: [sourceEntry],
                resolve: { _ in Self.outcome(for: sourceEntry, failure: failure) })
            let finding = try #require(result.first)
            #expect(finding.status == .infra)
            #expect(finding.failureKind == "nativeSourceUnavailable")
            #expect(finding.failureDetail?.contains("temporarily unavailable") == true)
            #expect(finding.failureDetail?.contains("no structured notes were found") == false)
        }
    }

    @Test func unsupportedHostIsSkippedAndPermanentParseFailureIsInabilityToCheck() async throws {
        let sourceEntry = try kuvoBoxFeed()
        let original = gap("run.kuvo.app")
        let remote = Self.remote(nil)
        let refusal = OSWindowRefusal(
            bound: .floor(minimum: "99.0"), version: "0.1.3", hostOS: "27.0.0")
        let skipped = await ChangelogCoverage.checkNativeSources(
            [original], entries: [sourceEntry],
            resolve: { _ in Self.outcome(
                for: sourceEntry,
                failure: .outsideVendorOSWindow(refusal, release: remote)) })
        let skippedFinding = try #require(skipped.first)
        #expect(skippedFinding.status == .skipped)
        #expect(skippedFinding.failureKind == "nativeSourceNotApplicable")
        #expect(skippedFinding.failureDetail?.contains("Could not check") == true)

        let failed = await ChangelogCoverage.checkNativeSources(
            [original], entries: [sourceEntry],
            resolve: { _ in Self.outcome(
                for: sourceEntry, failure: .archiveExtractionFailed("not an appcast")) })
        let failedFinding = try #require(failed.first)
        #expect(failedFinding.status == .warn)
        #expect(failedFinding.failureKind == "nativeSourceProbeFailed")
        #expect(failedFinding.failureDetail?.contains("Could not determine whether") == true)
        #expect(failedFinding.failureDetail?.contains("structured changelog notes were found") == false)
    }

    @Test func probesOneStableFeedPerBundleAndMatchesBundleIDsCaseInsensitively() async throws {
        let openClaw = AuditedUpdateFeeds.entries.filter {
            $0.bundleID == "ai.openclaw.mac" && $0.channel == .stable
        }
        let iina = AuditedUpdateFeeds.entries.filter {
            $0.bundleID == "com.colliderli.iina"
        }
        #expect(openClaw.count == 2)
        #expect(iina.map(\.channel).contains(.beta))

        let entries = openClaw + iina
        let findings = [gap("AI.OPENCLAW.MAC"), gap("com.colliderli.iina")]
        let calls = CallLog()
        let result = await ChangelogCoverage.checkNativeSources(
            findings, entries: entries,
            resolve: { entry in
                await calls.append(entry)
                return Self.outcome(for: entry, changelog: Changelog(entries: [
                    .init(version: "1.0", date: nil, items: ["A change"]),
                ]))
            })

        let observed = await calls.snapshot()
        #expect(result.allSatisfy { $0.status == .ok })
        #expect(result.map(\.recipeID) == findings.map(\.recipeID))
        #expect(observed.count == 2)
        #expect(observed.filter { $0.bundleID == "ai.openclaw.mac" }.count == 1)
        #expect(observed.filter { $0.bundleID == "com.colliderli.iina" }.count == 1)
        #expect(observed.allSatisfy { $0.channel == .stable })
    }

    @Test func dedicatedRecipesAcknowledgementsAndUnrelatedFindingsAreNotFetched() async throws {
        let url = URL(string: "https://notes.example.invalid/app")!
        let recipeFinding = try #require(ChangelogCoverage.findings(
            probes: [], catalog: ["com.example.recipe": url],
            recipes: [recipe("com.example.recipe")], acknowledged: [:]
        ).first)
        let acknowledgedFinding = try #require(ChangelogCoverage.findings(
            probes: [], catalog: ["com.example.ack": url], recipes: [],
            acknowledged: ["com.example.ack": "intentionally no dedicated recipe"]
        ).first)
        let staleFinding = try #require(ChangelogCoverage.findings(
            probes: [], catalog: ["com.colliderli.iina": url],
            recipes: [recipe("com.colliderli.iina")],
            acknowledged: ["com.colliderli.iina": "stale"]
        ).first)
        let unrelated = Finding(
            recipeID: "vendor:run.kuvo.app:stable", registry: .vendor,
            bundleID: "run.kuvo.app", channel: "stable", status: .warn,
            failureKind: "noChangelogRecipe", endpointHost: "updates.example.invalid")
        let calls = CallLog()
        let result = await ChangelogCoverage.checkNativeSources(
            [recipeFinding, acknowledgedFinding, staleFinding, unrelated],
            entries: AuditedUpdateFeeds.entries,
            resolve: { entry in
                await calls.append(entry)
                return Self.outcome(for: entry, changelog: Changelog(entries: [
                    .init(version: "1.0", date: nil, items: ["A change"]),
                ]))
            })

        let observed = await calls.snapshot()
        #expect(observed.isEmpty)
        #expect(result.map(\.status) == [
            recipeFinding.status, acknowledgedFinding.status, staleFinding.status, unrelated.status,
        ])
    }
}
