import Testing
import Foundation
@testable import DuoUpdaterCore

/// Failures kept for a later report: stored and read back whole, pruned with
/// the request log, and turned into a report that leaves the account name out.
@Suite(.serialized)
struct InstallFailureEventTests {

    private static func store(
        retentionDays: Int = 30, now: @escaping @Sendable () -> Date = Date.init
    ) -> (EventStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).sqlite")
        return (EventStore(fileURL: url, retentionDays: retentionDays,
                           flushEventCount: 1, flushDelay: .milliseconds(10),
                           pruneInterval: .zero, now: now), url)
    }

    private static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + suffix))
        }
    }

    private static let failure = InstallFailureEvent(
        appID: "/Applications/Surge.app", appName: "Surge",
        bundleID: "com.nssurge.surge-mac", fromVersion: "6.9.0", toVersion: "6.9.1",
        sourceName: "Sparkle", stage: .relaunch,
        message: "Surge restarted without applying the update.")

    @Test func roundTripsThroughTheStore() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await store.append(DuoEvent(payload: .failure(Self.failure)))
        await store.flush()

        let read = await store.events(EventQuery(kind: "failure"))
        #expect(read.count == 1)
        #expect(read.first?.failure == Self.failure)
        // The app column is filled, so a per-app query over every kind finds it.
        let rows = await store.rawRows(EventQuery(kind: "failure"))
        #expect(rows.first?.kind == "failure")
    }

    @Test func aPayloadThisBuildCannotReadStaysUnknown() {
        let row = EventRow(
            id: UUID(), date: Date(), client: .app, kind: "failure",
            payloadJSON: #"{"appName":"Surge"}"#)
        let event = DuoEvent(row: row)
        #expect(event?.failure == nil)
        #expect(event?.kind == "failure")
    }

    @Test func prunedWithTheRequestLog() async {
        let (store, url) = Self.store(retentionDays: 30)
        defer { Self.remove(url) }
        let old = Date().addingTimeInterval(-40 * 86_400)
        await store.append(DuoEvent(date: old, payload: .failure(Self.failure)))
        await store.flush()
        await store.append(DuoEvent(payload: .failure(Self.failure)))
        await store.flush()

        let left = await store.events(EventQuery(kind: "failure"))
        #expect(left.count == 1)
        #expect(left.first.map { $0.date > old } == true)
    }

    @Test func clearingTheRequestLogKeepsFailures() async {
        let (store, url) = Self.store()
        defer { Self.remove(url) }
        await store.append(DuoEvent(payload: .failure(Self.failure)))
        await store.flush()
        await store.reset()

        #expect(await store.events(EventQuery(kind: "failure")).count == 1)
    }

    @Test func reportAbbreviatesTheHomeDirectory() {
        let failure = InstallFailureEvent(
            appID: "/Users/someone/Applications/Foo.app", appName: "Foo",
            bundleID: "com.example.foo", fromVersion: "1.0", toVersion: "1.1",
            sourceName: "GitHub", stage: .install,
            message: "Couldn’t replace /Users/someone/Applications/Foo.app")
        let text = InstallFailureReport.text(
            for: failure, at: Date(timeIntervalSince1970: 1_760_000_000),
            duoUpdaterVersion: "0.6.0 (600)", osVersion: "Version 27.2",
            architecture: "arm64", homeDirectory: "/Users/someone")
        #expect(!text.contains("someone"))
        #expect(text.contains("Couldn’t replace ~/Applications/Foo.app"))
        #expect(text.contains("App: Foo (com.example.foo)"))
        #expect(text.contains("Update: 1.0 → 1.1 via GitHub"))
        #expect(text.contains("Stage: install"))
        #expect(text.contains("DuoUpdater: 0.6.0 (600)"))
        #expect(text.contains("macOS: Version 27.2 (arm64)"))
    }
}

/// Turning a report into something the user sends themselves.
struct InstallFailureReportSendingTests {

    private static let failure = InstallFailureEvent(
        appID: "/Applications/Foo.app", appName: "Foo", bundleID: "com.example.foo",
        fromVersion: "1.0", toVersion: "2.0", sourceName: "Sparkle", stage: .install,
        message: "The download failed.")

    @Test func issueURLCarriesTitleAndBodyExactly() throws {
        // The characters that a hand-built query gets wrong: `&` and `#` end the
        // value, a bare `+` reads as a space, `%` starts an escape.
        let body = "a & b #1 (50%+)\nline two → done = yes"
        let url = InstallFailureReport.issueURL(title: "Update failed: Foo", body: body)
        #expect(url.absoluteString.hasPrefix("https://github.com/jizhi0v0/duo-updater/issues/new?"))
        let query = try #require(url.query(percentEncoded: true))
        #expect(!query.contains("+"))
        #expect(query.contains("%26") && query.contains("%23") && query.contains("%2B") && query.contains("%0A"))
        // Decoded the way a server does (no `+`-as-space left to confuse it).
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "title" }?.value == "Update failed: Foo")
        #expect(items?.first { $0.name == "body" }?.value == body)
    }

    @Test func aLongBodyIsShortenedToFitTheLink() {
        let body = String(repeating: "é", count: 10_000)
        let url = InstallFailureReport.issueURL(title: "t", body: body)
        #expect(url.absoluteString.count <= InstallFailureReport.maxIssueURLLength)
        let sent = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value ?? ""
        #expect(sent.hasSuffix(InstallFailureReport.shortenedMarker))
        #expect(sent.count > 1_000)  // cut to fit, not emptied
        // A short one is untouched.
        let short = InstallFailureReport.issueURL(title: "t", body: "ok")
        #expect(URLComponents(url: short, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value == "ok")
    }

    @Test func userFixableErrorsAreRecognised() {
        #expect(InstallFailureReport.isUserFixable(
            DiskSpaceGuard.InsufficientSpace(needed: 2_000_000_000, free: 1_000).errorDescription!))
        #expect(InstallFailureReport.isUserFixable(
            AppStoreAXInstaller.AXError.notTrusted.errorDescription!))
        #expect(InstallFailureReport.isUserFixable(
            "The helper isn’t allowed to run. " + MASInstaller.MASError.helperApprovalHint))
        #expect(InstallFailureReport.isUserFixable(
            "not enough disk space to extract the update — free up space and try again"))
        // A VMPal VM still open: the user shuts it down and closes its window.
        // Mutation: drop `NestedAppRunningError.userFixableFragments` → red.
        for blockers: [NestedAppGuard.Blocker] in [
            [.init(name: "VMPalMachine", pid: 1, vmName: "macOS VM 1")],
            [.init(name: "VMPalMachine", pid: 1, vmName: "A"), .init(name: "VMPalMachine", pid: 2, vmName: "B")],
        ] {
            #expect(InstallFailureReport.isUserFixable(
                NestedAppRunningError(appName: "ZZFixtureVM", blockers: blockers).errorDescription!))
        }
        // Any other nested app may be one the user cannot quit (a background
        // helper), and a report is how such a case reaches us (BetterTouchTool's
        // watchdog did). Mutation: count the general sentence as fixable → red.
        #expect(!InstallFailureReport.isUserFixable(NestedAppRunningError(
            appName: "ZZFixtureVM", blockers: [.init(name: "ZZFixtureMachine", pid: 1)]).errorDescription!))
        #expect(!InstallFailureReport.isUserFixable("The download failed."))
        #expect(!InstallFailureReport.isUserFixable("Couldn’t verify the signature."))
    }

    @Test func promptKeyChangesWithVersionOrError() {
        let base = InstallFailureReport.promptKey(for: Self.failure)
        let newVersion = InstallFailureEvent(
            appID: "/Applications/Foo.app", appName: "Foo", bundleID: "com.example.foo",
            fromVersion: "1.0", toVersion: "2.1", sourceName: "Sparkle", stage: .install,
            message: "The download failed.")
        let otherError = InstallFailureEvent(
            appID: "/Applications/Foo.app", appName: "Foo", bundleID: "com.example.foo",
            fromVersion: "1.0", toVersion: "2.0", sourceName: "Sparkle", stage: .install,
            message: "Couldn’t verify the signature.")
        let retried = InstallFailureEvent(
            appID: "/Applications/Foo.app", appName: "Foo", bundleID: "com.example.foo",
            fromVersion: "1.0", toVersion: "2.0", sourceName: "GitHub", stage: .relaunch,
            message: "The download failed.")
        #expect(InstallFailureReport.promptKey(for: newVersion) != base)
        #expect(InstallFailureReport.promptKey(for: otherError) != base)
        #expect(InstallFailureReport.promptKey(for: retried) == base)
    }
}
