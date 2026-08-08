import Foundation

/// Installs/updates a Mac App Store app by delegating to the `mas` CLI, which
/// replays the same private-framework purchase request the App Store app sends
/// (`SSPurchase` → `CKDownloadQueue` → `storedownloadd`). We can't perform the
/// install ourselves: the binary is DRM-bound to the signed-in Apple ID and only
/// the store's own daemon may lay it down.
///
/// Getting this to run headlessly took three macOS-specific pieces, each found
/// the hard way:
///   • **Root.** mas talks to the install daemon. From a GUI app we can't feed
///     its internal `sudo` a password, so we run mas as root via an
///     `osascript … with administrator privileges` prompt (native Touch ID).
///   • **The user's identity.** Run as a clean root, mas can't find the per-user
///     App Store account and bails with "Failed to get sudo uid". Invoked via
///     `sudo` it would read SUDO_UID/SUDO_GID to seteuid back to the user; we
///     inject those ourselves (this process IS the user), reproducing sudo.
///   • **The user's GUI session.** The download is driven by `storedownloadd`,
///     which only transfers inside the user's Aqua session. osascript escalation
///     lands in a sessionless context where the download silently never starts
///     (queued forever, no network). `launchctl asuser <uid>` re-associates the
///     command with that session — the missing piece that makes downloads run.
///
/// Progress: mas only draws its download bar to a TTY, so output redirected to a
/// file is both block-buffered (nothing until the end) and bar-less. We wrap the
/// command in `script` (a pseudo-TTY): mas then line-buffers and prints
/// "N% downloaded", which we parse into real `InstallStage.downloading` updates.
/// Obtains root and runs a `mas install` as root on the caller's behalf. The
/// concrete implementation (in the app target) hands the request to a privileged
/// helper over XPC, so there is no per-install password prompt. Kept as a protocol
/// here so Core stays free of `ServiceManagement`/XPC.
public protocol PrivilegedMASRunner: Sendable {
    /// Run `mas install <adamID> --force` as root, re-associated into the user's
    /// GUI session, writing `mas`'s output to `logPath` (the caller tails it for
    /// progress). Returns `mas`'s exit status. Throws `MASInstaller.MASError`
    /// `.helperNotApproved` when root is unavailable (helper not approved).
    func installMAS(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String) async throws -> Int32
}

public actor MASInstaller {

    private let runner: PrivilegedMASRunner
    /// Base unit for the between-retry backoff (multiplied by the attempt number:
    /// 1×, 2×, 3×). Injectable so tests can exercise the retry loop without the
    /// real multi-second waits; production always uses one second.
    private let retryBackoffNanos: UInt64

    public init(runner: PrivilegedMASRunner) {
        self.runner = runner
        self.retryBackoffNanos = 1_000_000_000
    }

    /// Test seam: same as `init(runner:)` but with a caller-chosen backoff unit.
    init(runner: PrivilegedMASRunner, retryBackoffNanos: UInt64) {
        self.runner = runner
        self.retryBackoffNanos = retryBackoffNanos
    }

    public enum MASError: LocalizedError {
        case masNotFound
        case cancelled
        case helperNotApproved
        case failed(code: Int32, output: String)

        public var errorDescription: String? {
            switch self {
            case .masNotFound:
                return "The mas CLI isn’t installed — run: brew install mas"
            case .cancelled:
                return "Authorization cancelled."
            case .helperNotApproved:
                return "App Store updates need DuoUpdater's background helper. \(MASError.helperApprovalHint)"
            case .failed(let code, let output):
                // A known dead end on recent macOS: mas downloads the app fully, then
                // CommerceKit refuses the final receipt import ("Failed to find receipt
                // to import") because Apple gated the private API mas drives. Retrying
                // just re-downloads and fails again, so instead of the raw red log tail
                // we tell the user plainly and offer the App Store's own Updates page
                // (the UI keys the "Open App Store" button off this sentinel).
                if Self.isReceiptImportFailure(output) {
                    return "The App Store blocked mas from finishing this update. \(MASError.appStoreUpdatesHint)"
                }
                let tail = output.split(separator: "\n").suffix(3).joined(separator: " ")
                return tail.isEmpty ? "mas failed (\(code))." : "mas failed (\(code)): \(tail)"
            }
        }

        /// Stable fragment embedded in the receipt-import failure message; the UI
        /// matches on it to show a manual "Open App Store" button for the row.
        public static let appStoreUpdatesHint = "Update it from the App Store’s Updates page."

        /// Stable fragment embedded in the helper-approval message. Same contract as
        /// `appStoreUpdatesHint`: the UI matches on it to attach a "Turn On Helper…"
        /// action to the row, so the user isn't left reading an error that names a
        /// Settings pane they'd have to find themselves.
        public static let helperApprovalHint = "Turn it on in Login Items."

        /// True for the one error the helper-approval flow can act on.
        public var isHelperApproval: Bool {
            if case .helperNotApproved = self { return true }
            return false
        }

        /// True when mas downloaded the app but the store tooling couldn't import the
        /// receipt — a deterministic macOS/CommerceKit limitation, not a transient
        /// hiccup, so it should be surfaced as actionable guidance rather than retried.
        static func isReceiptImportFailure(_ output: String) -> Bool {
            output.lowercased().contains("failed to find receipt to import")
        }
    }

    /// True when the `mas` binary is present, so callers can decide whether to
    /// offer a one-click MAS update at all (vs. deep-linking to the App Store).
    /// Evaluated once and cached — a filesystem probe per UI render is wasteful,
    /// and mas is rarely installed mid-session.
    public static var isAvailable: Bool { executablePath != nil }

    /// Run `mas install <adamID> --force` as root, in the user's GUI session,
    /// streaming progress as parsed `InstallStage` values. `--force` reinstalls
    /// the latest the account can fetch (we only reach here when detection already
    /// found a newer version), so it always lands the current build.
    ///
    /// mas reaches the store over the network twice — a metadata lookup, then the
    /// download — and a flaky link (a local proxy resetting connections, a brief
    /// drop) makes either fail with an `NSURLErrorDomain` code and a non-zero exit
    /// (`Failed to lookup app … Code=-1004`). Those are transient, so we retry a
    /// few times with a growing backoff before surfacing the error — a momentary
    /// hiccup shouldn't strand an update a second attempt lands cleanly. Definitive
    /// failures ("Not purchased", wrong storefront, cancelled auth) carry no such
    /// code and are thrown on the first pass without retrying. Retries don't
    /// re-prompt: the helper holds root over XPC, so there's no per-attempt auth.
    public func install(
        adamID: Int,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        let maxAttempts = 4
        var lastError: Error = MASError.failed(code: -1, output: "")
        for attempt in 0..<maxAttempts {
            do {
                try await runOnce(adamID: adamID, onStage: onStage)
                if attempt > 0 {
                    Log.install.info("mas ADAM \(adamID, privacy: .public): succeeded on retry \(attempt, privacy: .public)")
                }
                return
            } catch let error as MASError {
                lastError = error
                guard case .failed(let code, let output) = error else { throw error }
                // Two retry policies, both throwing to the actionable error otherwise:
                //  • Transient network failure (proxy reset, brief drop): retry up to
                //    `maxAttempts - 1` with a growing backoff — a momentary hiccup
                //    shouldn't strand an update a later attempt lands cleanly.
                //  • Receipt-import failure: mas downloaded the app fully but
                //    CommerceKit balked at the final receipt import. Observed to clear
                //    on a plain second attempt, so retry — but EXACTLY ONCE, since mas
                //    has no install-only mode and each retry re-downloads the whole
                //    (often large) app; one retry bounds that waste. If it fails again
                //    it surfaces the "Open App Store" guidance (see `errorDescription`).
                //  Definitive answers ("Not purchased", wrong storefront, cancelled
                //  auth) match neither and are thrown on the first pass.
                let allowRetry: Bool
                let reason: String
                if Self.isTransientNetworkFailure(output) {
                    allowRetry = attempt < maxAttempts - 1
                    reason = "transient network failure"
                } else if MASError.isReceiptImportFailure(output) {
                    allowRetry = attempt < 1   // one retry only
                    reason = "receipt-import failure"
                } else {
                    allowRetry = false
                    reason = ""
                }
                guard allowRetry else { throw error }
                Log.install.notice("mas ADAM \(adamID, privacy: .public): \(reason, privacy: .public) (exit \(code, privacy: .public)); retrying \(attempt + 1, privacy: .public)")
                // Growing backoff (1s, 2s, 3s) so we ride over a proxy/CDN that's
                // momentarily resetting connections rather than hammering it.
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * retryBackoffNanos)
            }
        }
        throw lastError
    }

    /// One `mas install` attempt: obtain root via the helper, stream progress by
    /// tailing the log it writes, and throw `MASError.failed` (with mas's output)
    /// on a non-zero exit. `install` wraps this in the transient-retry loop.
    private func runOnce(
        adamID: Int,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        // A fresh log per attempt; created up front so the tailer can open it before
        // the (root) helper starts writing. Recreated (truncated) each attempt so a
        // prior try's error tail never bleeds into this one's output or progress.
        let logPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("duo-mas-\(adamID).log")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        // The helper rebuilds the `launchctl asuser … mas install …` command
        // server-side (so a caller can never hand the root helper an arbitrary
        // command); we pass only the structured parameters it needs. uid/gid/user
        // identify the GUI session storedownloadd must run in.
        let uid = Int(getuid())
        let gid = Int(getgid())
        let user = NSUserName()

        // Stream progress exactly as before: tail the log the helper writes.
        let tailer = LogTailer(path: logPath) { line in
            if let stage = Self.stage(for: line) { onStage(stage) }
        }
        tailer.start()
        defer { tailer.stop() }  // idempotent; flushes trailing lines

        let status = try await runner.installMAS(
            adamID: adamID, uid: uid, gid: gid, userName: user, logPath: logPath)
        tailer.stop()  // flush before reading the log for an error tail

        guard status == 0 else {
            // The real failure reason (e.g. "Not purchased") is in mas's output.
            let log = (try? String(contentsOfFile: logPath, encoding: .utf8)).map(Self.stripANSI) ?? ""
            throw MASError.failed(code: status, output: log)
        }
    }

    /// Whether `mas` currently lists this App Store app as outdated, or `nil` when
    /// that can't be determined (mas absent, a non-zero exit, or the check timed
    /// out). This is `mas`'s OWN verdict, computed with the same store machinery the
    /// install uses, so it's the authority on whether `mas install … --force` could
    /// actually fetch a newer build — a pre-flight consults it to avoid force-
    /// reinstalling an app that's already current (which macOS's installer rejects
    /// with "The upgrade failed"). It's a read (no root, no GUI-session re-
    /// association), so we run it directly here rather than through the helper.
    ///
    /// Returns `nil` — deliberately, not `false` — on any failure: `mas outdated`
    /// has been flaky across macOS releases, so a caller must treat "couldn't check"
    /// as inconclusive, NOT as "nothing outdated". Gating a skip on a bare `nil`
    /// would let a silently-broken check suppress every update.
    public func outdatedContains(adamID: Int) async -> Bool? {
        guard let ids = await runOutdated() else { return nil }
        return ids.contains(adamID)
    }

    /// Run `mas outdated` and parse the outdated adamIDs, or `nil` on any failure
    /// (absent binary, non-zero exit, timeout). `mas outdated` reaches the store for
    /// every installed MAS app, so we cap the wait: a stalled network must not hang
    /// the install pipeline.
    private func runOutdated() async -> Set<Int>? {
        guard let mas = Self.executablePath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mas)
        process.arguments = ["outdated"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Terminate by pid if we overrun; the work item is cancelled on a normal
        // exit, so the kill only fires when we actually timed out. Capturing the pid
        // (a value) rather than the Process keeps the closure Sendable.
        let pid = process.processIdentifier
        let timeout = DispatchWorkItem { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        timeout.cancel()

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Self.parseOutdatedAdamIDs(from: String(data: data, encoding: .utf8) ?? "")
    }

    /// Parse `mas outdated` output into the set of outdated adamIDs. Each line leads
    /// with the numeric adamID, e.g. "497799835  Xcode (15.0 -> 15.1)". Tolerant of
    /// leading whitespace and any trailing columns. Internal for offline tests.
    static func parseOutdatedAdamIDs(from output: String) -> Set<Int> {
        var ids: Set<Int> = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let leading = raw.drop { $0 == " " || $0 == "\t" }.prefix { $0.isNumber }
            if let id = Int(leading) { ids.insert(id) }
        }
        return ids
    }

    /// True when mas's output shows a *transient* network failure — a connection
    /// that dropped or couldn't be made — rather than a definitive store answer
    /// ("Not purchased", "No apps found"). mas surfaces the URL error as text (via
    /// `storedownloadd`) instead of a typed `URLError`, so we match the string: the
    /// same codes `Downloader.isTransient` resumes on, plus notConnectedToInternet.
    static func isTransientNetworkFailure(_ output: String) -> Bool {
        // URLError/CFNetwork codes worth another pass, printed as mas emits them.
        let transientCodes = [
            "-1001",  // timedOut
            "-1004",  // cannotConnectToHost ("Could not connect to the server")
            "-1005",  // networkConnectionLost
            "-1009",  // notConnectedToInternet
            "-1200",  // secureConnectionFailed (TLS reset)
        ]
        if output.contains("NSURLErrorDomain") || output.contains("kCFErrorDomainCFNetwork") {
            if transientCodes.contains(where: { output.contains("Code=\($0)") }) { return true }
        }
        // Fallback to the human-readable messages, in case a mas version prints the
        // localized description without the numeric code. Case-insensitive so a
        // spelling/casing drift across mas versions still matches.
        let lowered = output.lowercased()
        let transientPhrases = [
            "could not connect to the server",
            "network connection was lost",
            "internet connection appears to be offline",
            "the request timed out",
        ]
        return transientPhrases.contains(where: lowered.contains)
    }

    /// Map a cleaned mas output line to an install stage. mas prints "N% downloaded"
    /// during the transfer and "==> Downloading/Downloaded/Installing/Installed"
    /// phase markers. We ignore the terminal "Installed" line — completion is the
    /// caller's job (it re-reads the bundle from disk).
    static func stage(for line: String) -> InstallStage? {
        if let percent = firstMatch(#"(\d+)% downloaded"#, in: line),
           let value = Double(percent) {
            return .downloading(fraction: min(max(value / 100, 0), 1))
        }
        let lower = line.lowercased()
        if lower.contains("==> downloading") { return .downloading(fraction: 0) }
        if lower.contains("==> downloaded")  { return .downloading(fraction: 1) }
        if lower.contains("==> installing")  { return .installing }
        return nil
    }

    /// First capture group of `pattern` in `text`, or nil.
    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Strip ANSI/VT100 escape sequences (colors and cursor moves) from a string.
    static func stripANSI(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]") else { return s }
        return re.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    /// Locate `mas`: Apple Silicon default, then Intel default. (Unlike brew we
    /// don't fall through to PATH — this runs under osascript with a minimal
    /// environment, so we resolve an absolute path here.) The Homebrew `mas`
    /// shim just `exec`s libexec/bin/mas, so the shim path works under launchctl.
    static let executablePath: String? = {
        let candidates = ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Polls a growing log file and emits cleaned lines as they land. mas redraws
    /// its progress bar with ANSI clear-line sequences (`ESC[2K ESC[0G`) and `\r`
    /// rather than newlines, so we normalize all three into line breaks, strip the
    /// remaining color codes, and emit each non-empty segment — turning the live
    /// in-place bar into a stream of "N% downloaded" lines.
    private final class LogTailer: @unchecked Sendable {
        private let path: String
        private let onLine: @Sendable (String) -> Void
        private let queue = DispatchQueue(label: "com.duoupdater.mas.tailer")
        private var timer: DispatchSourceTimer?
        private var handle: FileHandle?
        private var carry = ""

        init(path: String, onLine: @escaping @Sendable (String) -> Void) {
            self.path = path
            self.onLine = onLine
        }

        func start() {
            handle = FileHandle(forReadingAtPath: path)
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
            t.setEventHandler { [weak self] in self?.drain() }
            timer = t
            t.resume()
        }

        /// Read everything appended since the last offset and flush complete lines.
        private func drain() {
            guard let handle else { return }
            let data = handle.readDataToEndOfFile()  // current offset → EOF, advances
            guard !data.isEmpty, var s = String(data: data, encoding: .utf8) else { return }
            // Treat carriage returns and ANSI clear-line / cursor-home moves (how
            // mas redraws the bar in place) as segment boundaries, then drop the
            // leftover color codes.
            s = s.replacingOccurrences(of: "\r", with: "\n")
            s = MASInstaller.replaceCursorMovesWithNewlines(s)
            s = MASInstaller.stripANSI(s)
            carry += s
            while let nl = carry.firstIndex(of: "\n") {
                let line = String(carry[carry.startIndex..<nl]).trimmingCharacters(in: .whitespaces)
                carry.removeSubrange(carry.startIndex...nl)
                if !line.isEmpty { onLine(line) }
            }
        }

        func stop() {
            queue.sync {
                drain()  // catch any tail written between the last tick and exit
                let line = carry.trimmingCharacters(in: .whitespaces)
                if !line.isEmpty { onLine(line) }
                carry = ""
                timer?.cancel()
                timer = nil
                try? handle?.close()
                handle = nil
            }
        }
    }

    /// Convert ANSI cursor-control sequences that mas uses to redraw its bar
    /// (`ESC[2K` erase-line, `ESC[<n>G` cursor-column) into newlines, so each
    /// redraw becomes its own line. Color/style codes (`…m`) are left for stripANSI.
    static func replaceCursorMovesWithNewlines(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[GKHJ]") else { return s }
        return re.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n")
    }
}
