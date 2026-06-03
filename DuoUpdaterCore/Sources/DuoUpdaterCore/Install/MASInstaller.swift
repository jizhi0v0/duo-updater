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
public actor MASInstaller {

    public init() {}

    public enum MASError: LocalizedError {
        case masNotFound
        case cancelled
        case failed(code: Int32, output: String)

        public var errorDescription: String? {
            switch self {
            case .masNotFound:
                return "The mas CLI isn’t installed — run: brew install mas"
            case .cancelled:
                return "Authorization cancelled."
            case .failed(let code, let output):
                let tail = output.split(separator: "\n").suffix(3).joined(separator: " ")
                return tail.isEmpty ? "mas failed (\(code))." : "mas failed (\(code)): \(tail)"
            }
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
    public func install(
        adamID: Int,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        guard let mas = Self.executablePath else { throw MASError.masNotFound }

        // A fresh log per install; created up front so the tailer can open it
        // before the privileged shell starts writing.
        let logPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("duo-mas-\(adamID).log")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: logPath) }

        let uid = getuid()
        let gid = getgid()
        let user = NSUserName()
        // launchctl asuser <uid> → user's Aqua session (so storedownloadd runs).
        // script -q /dev/null → pseudo-TTY (so mas emits live "N% downloaded").
        // env … → SUDO_UID/GID/USER (so mas seteuid's to the account owner).
        // MAS_NO_AUTO_INDEX silences mas's per-app Spotlight re-index warnings.
        let shellCommand =
            "/bin/launchctl asuser \(uid) "
            + "/usr/bin/script -q /dev/null "
            + "/usr/bin/env SUDO_UID=\(uid) SUDO_GID=\(gid) SUDO_USER='\(user)' MAS_NO_AUTO_INDEX=1 "
            + "'\(mas)' install \(adamID) --force > '\(logPath)' 2>&1"
        // Embed in a double-quoted AppleScript string literal.
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        // mas's own output is in the log; osascript only emits AppleScript-level
        // errors (e.g. "User canceled. (-128)") on stderr.
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        let errBox = OutputBox()
        let errHandle = errPipe.fileHandleForReading
        errHandle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            errBox.append(text)
        }

        let tailer = LogTailer(path: logPath) { line in
            if let stage = Self.stage(for: line) { onStage(stage) }
        }
        tailer.start()

        try process.run()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        errHandle.readabilityHandler = nil
        tailer.stop()  // final flush of any trailing log lines

        guard process.terminationStatus == 0 else {
            let stderr = errBox.text
            // osascript surfaces a user-cancelled auth dialog as error -128.
            if stderr.contains("-128") || stderr.localizedCaseInsensitiveContains("cancel") {
                throw MASError.cancelled
            }
            // The real failure reason (e.g. "Not purchased") is in mas's output.
            let log = (try? String(contentsOfFile: logPath, encoding: .utf8)).map(Self.stripANSI) ?? ""
            let detail = log.isEmpty ? stderr : log
            throw MASError.failed(code: process.terminationStatus, output: detail)
        }
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

    /// Thread-safe accumulator for stderr streamed off a background handler.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = ""
        func append(_ s: String) { lock.lock(); buffer += s; lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return buffer }
    }

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
