import Testing
import Foundation
@testable import DuoUpdaterCore

/// The automatic retry a scheduled round with transient failures earns (#899):
/// which rows `UpdateChecker` marks as transient, which of them
/// `CheckFailureRules.automaticRetryTargets` hands the retry, and that the retry
/// never advances the chronic streak (`CheckFailureRules.streaks`).
///
/// Every fixture is fabricated: one scripted source per behaviour, apps under
/// `com.example.*`, no network.
@Suite("Automatic check retry")
struct AutomaticCheckRetryTests {

    /// Throws the error it was given, or answers a version.
    private struct ScriptedSource: UpdateSource {
        let name: String
        let error: (any Error)?
        init(name: String = "Scripted", throwing error: (any Error)?) {
            self.name = name
            self.error = error
        }
        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            if let error { throw error }
            return RemoteVersion(
                shortVersion: "2.0.0", version: nil, downloadURL: nil,
                sourceName: name, requiresManualInstaller: true)
        }
    }

    /// A definitive, non-transport failure: what a source throws for a 404.
    private struct NotFound: LocalizedError {
        var errorDescription: String? { "The feed answered 404." }
    }

    private static func app(_ id: String = "subject") -> InstalledApp {
        InstalledApp(
            name: id, bundleID: "com.example.\(id)",
            shortVersion: "1.0.0", buildVersion: "1",
            path: URL(fileURLWithPath: "/Applications/\(id).app"),
            isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil)
    }

    private static func row(
        _ id: String, _ status: UpdateStatus, transient: Bool = false
    ) -> UpdateResult {
        var result = UpdateResult(app: app(id), remote: nil, status: status)
        result.failureIsTransient = transient
        return result
    }

    private static func check(_ sources: [any UpdateSource]) async -> UpdateResult {
        await UpdateChecker(sources: sources).check(app())
    }

    // MARK: - What UpdateChecker marks as transient

    @Test("a transport failure marks the error row transient", arguments: [
        URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
    ])
    func transportFailureIsTransient(code: URLError.Code) async {
        let result = await Self.check([ScriptedSource(throwing: URLError(code))])
        guard case .error = result.status else {
            Issue.record("expected .error, got \(result.status)"); return
        }
        #expect(result.failureIsTransient)
    }

    /// The other side of the same branch. Without it, a checker that marked every
    /// `.error` transient would pass the test above.
    @Test("a definitive failure does not", arguments: [
        NotFound() as any Error, URLError(.cannotFindHost), URLError(.serverCertificateUntrusted),
        URLError(.cancelled), URLError(.badServerResponse),
    ])
    func definitiveFailureIsNot(error: any Error) async {
        let result = await Self.check([ScriptedSource(throwing: error)])
        guard case .error = result.status else {
            Issue.record("expected .error, got \(result.status)"); return
        }
        #expect(!result.failureIsTransient)
    }

    /// Any source, not the last: the row shows the later 404, but the feed that
    /// timed out is the one a retry could still get an answer from.
    @Test func anEarlierTransientFailureStillCounts() async {
        let result = await Self.check([
            ScriptedSource(name: "First", throwing: URLError(.timedOut)),
            ScriptedSource(name: "Second", throwing: NotFound()),
        ])
        guard case .error(let message) = result.status else {
            Issue.record("expected .error, got \(result.status)"); return
        }
        #expect(message == NotFound().localizedDescription)
        #expect(result.failureIsTransient)
    }

    @Test func anAnsweredRowIsNotTransient() async {
        let result = await Self.check([
            ScriptedSource(name: "First", throwing: URLError(.timedOut)),
            ScriptedSource(name: "Second", throwing: nil),
        ])
        #expect(result.status == .updateAvailable(latest: "2.0.0"))
        #expect(!result.failureIsTransient)
    }

    // MARK: - Which rows the automatic retry takes

    private static let round: [UpdateResult] = [
        row("timedout", .error("timed out"), transient: true),
        row("notfound", .error("404"), transient: false),
        row("current", .upToDate),
        row("chronic", .error("timed out"), transient: true),
    ]
    private static let streaks = CheckFailureRules.streaks(
        [app("chronic").id: CheckFailureRules.chronicThreshold - 1], after: .round, checked: round)

    @Test func aScheduledRoundRetriesOnlyItsTransientNonChronicFailures() {
        #expect(CheckFailureRules.isChronic(consecutiveFailures: Self.streaks[Self.app("chronic").id] ?? 0),
                "fixture: the chronic row must be chronic after this round")
        #expect(!CheckFailureRules.isChronic(consecutiveFailures: Self.streaks[Self.app("timedout").id] ?? 0),
                "fixture: the transient row must not be")
        let targets = CheckFailureRules.automaticRetryTargets(
            afterRound: Self.round, intent: .scheduled, streaks: Self.streaks)
        #expect(targets == [Self.app("timedout").id])
    }

    /// Only the scheduled tick earns one. The same round from the refresh button
    /// or a menu open retries nothing, however transient its failures.
    @Test("a round the user was present for earns no automatic retry",
          arguments: [RefreshIntent.userRequested, .userPresent])
    func userRoundsDoNotRetry(intent: RefreshIntent) {
        #expect(!CheckFailureRules.automaticRetryTargets(
            afterRound: Self.round, intent: .scheduled, streaks: Self.streaks).isEmpty,
            "fixture: this round must earn a retry when scheduled")
        #expect(CheckFailureRules.automaticRetryTargets(
            afterRound: Self.round, intent: intent, streaks: Self.streaks).isEmpty)
    }

    /// The transient flag is only meaningful on an `.error` row; a row that says
    /// otherwise is not retried on its word.
    @Test func aNonErrorRowIsNeverATarget() {
        let stray = [Self.row("current", .upToDate, transient: true)]
        #expect(CheckFailureRules.automaticRetryTargets(
            afterRound: stray, intent: .scheduled, streaks: [:]).isEmpty)
    }

    // MARK: - The retry never advances the chronic streak

    /// A row that fails transiently every round and every retry is retried
    /// automatically after rounds 1 and 2 and becomes chronic at round 3 — the
    /// threshold counted in rounds, not in rounds plus retries. If a retry
    /// counted, it would be chronic after round 2 (1 + retry + 2 + retry) and the
    /// second retry would never be offered.
    @Test func retriesDoNotCountTowardsTheChronicStreak() {
        let failing = [Self.row("flaky", .error("timed out"), transient: true)]
        let id = Self.app("flaky").id
        var streaks: [String: Int] = [:]
        var retriedAfterRound: [Int] = []
        for round in 1...CheckFailureRules.chronicThreshold {
            streaks = CheckFailureRules.streaks(streaks, after: .round, checked: failing)
            #expect(streaks[id] == round, "round \(round)")
            let targets = CheckFailureRules.automaticRetryTargets(
                afterRound: failing, intent: .scheduled, streaks: streaks)
            if targets.contains(id) {
                retriedAfterRound.append(round)
                streaks = CheckFailureRules.streaks(streaks, after: .retry, checked: failing)
            }
        }
        #expect(retriedAfterRound == Array(1..<CheckFailureRules.chronicThreshold))
        #expect(streaks[id] == CheckFailureRules.chronicThreshold)
    }

    /// And a retry that succeeds leaves the streak to the next round too: the
    /// round, not the retry, is what clears it.
    @Test func aRoundClearsAStreakARetryDoesNot() {
        let id = Self.app("flaky").id
        let before = [id: 2]
        let recovered = [Self.row("flaky", .upToDate)]
        #expect(CheckFailureRules.streaks(before, after: .retry, checked: recovered) == before)
        #expect(CheckFailureRules.streaks(before, after: .round, checked: recovered).isEmpty)
    }
}
