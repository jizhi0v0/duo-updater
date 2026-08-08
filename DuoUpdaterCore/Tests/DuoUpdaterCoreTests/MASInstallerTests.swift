import Testing
import Foundation
@testable import DuoUpdaterCore

/// mas draws its download bar to a (pseudo-)TTY using ANSI clear-line + cursor
/// moves instead of newlines. The tailer normalizes those into line breaks and
/// strips colors so the phase markers and "N% downloaded" ticks come out as clean
/// lines; `stage(for:)` then maps them to install stages. This is the exact byte
/// shape captured from a real `mas install … --force` run under `script`.
@Test func parsesLiveProgressFromAnsiBar() {
    let esc = "\u{1B}"
    let raw =
        "\(esc)[2K\(esc)[0G\(esc)[1;34m==>\(esc)[0m Downloading LocalSend (1.17.0)\r" +
        "\(esc)[2K\(esc)[0G------------------------------------ 0% downloaded" +
        "\(esc)[2K\(esc)[0G#################################### 87% downloaded" +
        "\(esc)[2K\(esc)[0G#################################### 100% downloaded\r" +
        "\(esc)[1;34m==>\(esc)[0m Installing LocalSend (1.17.0)\r"

    // Reproduce the tailer's normalization pipeline.
    var s = raw.replacingOccurrences(of: "\r", with: "\n")
    s = MASInstaller.replaceCursorMovesWithNewlines(s)
    s = MASInstaller.stripANSI(s)
    let lines = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    let stages = lines.compactMap { MASInstaller.stage(for: $0) }
    #expect(stages.contains(.downloading(fraction: 0)))
    #expect(stages.contains(.downloading(fraction: 0.87)))
    #expect(stages.contains(.downloading(fraction: 1.0)))
    #expect(stages.contains(.installing))
}

/// Phase-marker and percentage mapping, independent of ANSI handling.
@Test func mapsMasLinesToStages() {
    #expect(MASInstaller.stage(for: "==> Downloading Microsoft Excel (16.109.3)") == .downloading(fraction: 0))
    #expect(MASInstaller.stage(for: "45% downloaded") == .downloading(fraction: 0.45))
    #expect(MASInstaller.stage(for: "==> Downloaded Microsoft Excel (16.109.3)") == .downloading(fraction: 1.0))
    #expect(MASInstaller.stage(for: "==> Installing Microsoft Excel (16.109.3)") == .installing)
    // The terminal line and unrelated noise produce no stage (completion is the
    // caller's job; "Install progress cannot be displayed" must not be mistaken).
    #expect(MASInstaller.stage(for: "==> Installed Microsoft Excel (16.109.3) in /Applications/Microsoft Excel.app") == nil)
    #expect(MASInstaller.stage(for: "Install progress cannot be displayed") == nil)
}

/// `mas outdated` leads each line with the numeric adamID; the install pre-flight
/// parses those out to tell whether the app being installed is one the store
/// actually considers outdated (so it can skip a doomed `--force` reinstall of an
/// already-current app). Tolerant of leading whitespace (mas right-aligns short
/// ids) and any trailing columns. Blank output — nothing outdated — is an EMPTY set,
/// deliberately distinct from the `nil` "couldn't check" the caller returns when mas
/// can't run, so a broken check is never mistaken for "nothing to update".
@Test func parsesOutdatedAdamIDs() {
    let output = """
    497799835  Xcode (15.0 -> 15.1)
     640199958  Developer (11.0.1 -> 11.0.2)
    899247664  TestFlight (4.2.0 -> 4.2.2)
    """
    #expect(MASInstaller.parseOutdatedAdamIDs(from: output) == [497799835, 640199958, 899247664])
    // Nothing outdated → empty set (NOT nil — that's the runner's "couldn't check").
    #expect(MASInstaller.parseOutdatedAdamIDs(from: "").isEmpty)
    #expect(MASInstaller.parseOutdatedAdamIDs(from: "\n  \n\t\n").isEmpty)
    // A non-numeric warning/notice line is ignored, not misparsed into a bogus id.
    #expect(MASInstaller.parseOutdatedAdamIDs(from: "Warning: hmm\n747648890 Telegram (12.7 -> 12.8)") == [747648890])
}

/// A flaky link (a local proxy resetting connections, a brief drop) makes mas's
/// store lookup/download fail with an `NSURLErrorDomain` code — those are worth a
/// retry. A definitive store answer ("Not purchased", "No apps found") is not: it
/// must be surfaced on the first pass, never retried.
@Test func classifiesTransientMasFailures() {
    // The exact shape from the field report: lookup couldn't reach the store.
    let cannotConnect = """
    ==> Downloading Microsoft Word
    Error: Failed to lookup app for ADAM ID 462054704
    Error Domain=NSURLErrorDomain Code=-1004 "Could not connect to the server." \
    UserInfo={_kCFStreamErrorCodeKey=61, NSUnderlyingError=0x7788c65380 \
    {Error Domain=kCFErrorDomainCFNetwork Code=-1004 "(null)"}}
    """
    #expect(MASInstaller.isTransientNetworkFailure(cannotConnect))

    // The other transient codes we ride over.
    #expect(MASInstaller.isTransientNetworkFailure("Error Domain=NSURLErrorDomain Code=-1005 \"The network connection was lost.\""))
    #expect(MASInstaller.isTransientNetworkFailure("Error Domain=NSURLErrorDomain Code=-1009 \"The Internet connection appears to be offline.\""))
    #expect(MASInstaller.isTransientNetworkFailure("Error Domain=NSURLErrorDomain Code=-1001 \"The request timed out.\""))
    // Message-only fallback (no numeric code / domain present).
    #expect(MASInstaller.isTransientNetworkFailure("could not connect to the server, retrying"))

    // Definitive store answers must NOT be retried.
    #expect(!MASInstaller.isTransientNetworkFailure("Error: Not purchased"))
    #expect(!MASInstaller.isTransientNetworkFailure("Error: No apps found for ADAM ID 462054704"))
    #expect(!MASInstaller.isTransientNetworkFailure("==> Downloaded\n==> Installing\nError: Download failed"))
    #expect(!MASInstaller.isTransientNetworkFailure(""))
    // A non-transient URL-domain error (unsupported URL) isn't in the retry set.
    #expect(!MASInstaller.isTransientNetworkFailure("Error Domain=NSURLErrorDomain Code=-1002 \"unsupported URL\""))
}

/// A scripted `PrivilegedMASRunner`: returns the next (exit-status, log) pair on
/// each call, writing the log where the installer will read it, and records how
/// many times it was invoked so a test can assert the retry count.
private actor ScriptedMASRunner: PrivilegedMASRunner {
    private let script: [(status: Int32, log: String)]
    private(set) var calls = 0
    init(_ script: [(Int32, String)]) { self.script = script.map { (status: $0.0, log: $0.1) } }
    func installMAS(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String) async throws -> Int32 {
        let entry = script[min(calls, script.count - 1)]
        calls += 1
        try? entry.log.write(toFile: logPath, atomically: true, encoding: .utf8)
        return entry.status
    }
}

private let transientLog =
    "Error: Failed to lookup app for ADAM ID 462054704\n" +
    "Error Domain=NSURLErrorDomain Code=-1004 \"Could not connect to the server.\""

// mas downloads the app fully, then CommerceKit balks at the receipt import — the
// exact shape from the WhatsApp field report.
private let receiptImportLog =
    "==> Downloaded WhatsApp Messenger (26.27.73)\n" +
    "==> Installing WhatsApp Messenger (26.27.73)\n" +
    "Install progress cannot be displayed" +
    "Error: Failed to find receipt to import for WhatsApp Messenger (26.27.73)"

/// The receipt-import failure is its own bucket: not a transient *network* error,
/// not a definitive store answer. It's retryable (clears on a second attempt in the
/// field), and the surfaced message is actionable guidance rather than the raw log.
@Test func classifiesReceiptImportFailure() {
    #expect(MASInstaller.MASError.isReceiptImportFailure(receiptImportLog))
    #expect(!MASInstaller.MASError.isReceiptImportFailure("Error: Not purchased"))
    #expect(!MASInstaller.MASError.isReceiptImportFailure(transientLog))
    #expect(!MASInstaller.isTransientNetworkFailure(receiptImportLog))
    // The surfaced message swaps the raw log tail for the actionable hint the UI
    // keys its "Open App Store" button off.
    let msg = MASInstaller.MASError.failed(code: 1, output: receiptImportLog).errorDescription ?? ""
    #expect(msg.contains(MASInstaller.MASError.appStoreUpdatesHint))
    #expect(!msg.contains("Failed to find receipt"))
}

/// A receipt-import failure is retried and lands on the second attempt — the field
/// scenario, where a plain retry cleared it.
@Test func retriesReceiptImportFailureThenSucceeds() async throws {
    let runner = ScriptedMASRunner([(1, receiptImportLog), (0, "==> Installing")])
    let installer = MASInstaller(runner: runner, retryBackoffNanos: 0)
    try await installer.install(adamID: 900000004) { _ in }
    let calls = await runner.calls
    #expect(calls == 2)  // failed once, retried once, succeeded
}

/// Unlike a network drop (up to 4 attempts), a persistent receipt-import failure is
/// retried EXACTLY ONCE — each retry re-downloads the whole app, so the waste is
/// bounded — then surfaced with the actionable guidance.
@Test func receiptImportFailureRetriesExactlyOnce() async {
    let runner = ScriptedMASRunner([(1, receiptImportLog)])  // always fails
    let installer = MASInstaller(runner: runner, retryBackoffNanos: 0)
    await #expect(throws: MASInstaller.MASError.self) {
        try await installer.install(adamID: 900000005) { _ in }
    }
    let calls = await runner.calls
    #expect(calls == 2)  // one retry only, not maxAttempts
}

// `runOnce` writes/reads a temp log keyed by adamID, so each test below uses a
// distinct adamID to stay isolated when Swift Testing runs them in parallel.
// (Production serializes App Store installs through a single-slot gate, so real
// installs never share a log path.)

/// A transient network failure is retried and, when the link recovers, the retry
/// lands the update — the field scenario (a proxy resetting the store lookup).
@Test func retriesTransientMasFailureThenSucceeds() async throws {
    let runner = ScriptedMASRunner([(1, transientLog), (0, "==> Installing")])
    let installer = MASInstaller(runner: runner, retryBackoffNanos: 0)
    try await installer.install(adamID: 900000001) { _ in }
    let calls = await runner.calls
    #expect(calls == 2)  // failed once, retried once, succeeded
}

/// A definitive store answer is surfaced on the first pass — never retried.
@Test func doesNotRetryDefinitiveMasFailure() async {
    let runner = ScriptedMASRunner([(1, "Error: Not purchased")])
    let installer = MASInstaller(runner: runner, retryBackoffNanos: 0)
    await #expect(throws: MASInstaller.MASError.self) {
        try await installer.install(adamID: 900000002) { _ in }
    }
    let calls = await runner.calls
    #expect(calls == 1)  // no retry on a definitive failure
}

/// A link that stays down exhausts the retries (4 attempts) and then surfaces the
/// error, rather than retrying forever.
@Test func exhaustsRetriesWhenTransientPersists() async {
    let runner = ScriptedMASRunner([(1, transientLog)])  // always transient
    let installer = MASInstaller(runner: runner, retryBackoffNanos: 0)
    await #expect(throws: MASInstaller.MASError.self) {
        try await installer.install(adamID: 900000003) { _ in }
    }
    let calls = await runner.calls
    #expect(calls == 4)  // maxAttempts
}

@Test func installerUpgradeFailureIsTreatedAsAnAppStoreDeadEnd() {
    // TestFlight 4.2.2 → 4.3.0: mas downloaded the package, then macOS's own
    // `installer` refused to replace the bundle. Retrying re-downloads and fails
    // the same way, so the row should offer the App Store instead.
    let output = """
        ==> Downloading TestFlight (4.3.0)\r####### 100% downloaded==> Installing TestFlight (4.3.0)
        Error: Failed to install TestFlight (4.3.0) from /var/folders/vs/T/NSIRD_mas/899247664.pkg
        installer: The upgrade failed. (The Installer encountered an error that caused the \
        installation to fail. An unexpected error occurred while moving files to the final destination.)
        """
    #expect(MASInstaller.MASError.isReceiptImportFailure(output))
    let msg = MASInstaller.MASError.failed(code: 1, output: output).errorDescription ?? ""
    #expect(msg.contains(MASInstaller.MASError.appStoreUpdatesHint))
}

@Test func masFailureTailStaysShortAndDropsProgressNoise() {
    // mas draws progress with carriage returns, so splitting on "\n" alone left the
    // whole blob as one "line" — the popover rendered ~40 lines of red text.
    let output = "==> Downloading TestFlight\r"
        + (0..<50).map { "###### \($0)% downloaded" }.joined(separator: "\r")
        + "\rsomething went wrong at the very end"
    let tail = MASInstaller.MASError.tail(of: output)
    #expect(tail.count <= 221)
    #expect(!tail.contains("% downloaded"))
    #expect(tail.contains("something went wrong at the very end"))
}
