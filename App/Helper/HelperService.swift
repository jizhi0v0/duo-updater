import Foundation
import Security

/// Accepts incoming XPC connections only from the genuine, correctly-signed main
/// app, then vends `MASHelperProtocol`.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        guard HelperService.isValidClient(conn) else {
            NSLog("duo-helper: rejected connection — client failed code-signing check")
            return false
        }
        conn.exportedInterface = NSXPCInterface(with: MASHelperProtocol.self)
        conn.exportedObject = HelperService()
        conn.resume()
        return true
    }
}

/// The root-side worker. Each accepted connection gets its own instance; all
/// installs funnel through one serial queue so two `mas` processes never run as
/// root at the same time (Update All fans out concurrent calls).
final class HelperService: NSObject, MASHelperProtocol {
    static let machServiceName = "com.duoupdater.helper"

    /// The caller (main app) must satisfy this requirement: Apple-anchored, our
    /// bundle id, and the **same Developer ID team that signed this helper**. This
    /// is THE security gate — only the DuoUpdater app built alongside this helper
    /// can drive root through it.
    ///
    /// nil when our own team can't be read (unsigned/ad-hoc), which
    /// `isValidClient` treats as "reject everything" — see `OwnTeamIdentifier`.
    private static let clientRequirement =
        OwnTeamIdentifier.requirement(bundleIdentifier: "com.duoupdater.app")

    private static let workQueue = DispatchQueue(label: "com.duoupdater.helper.install")

    // MARK: Peer validation

    static func isValidClient(_ conn: NSXPCConnection) -> Bool {
        // No resolvable team ⇒ no requirement we're willing to accept. Refuse
        // rather than degrade to a team-less (forgeable) requirement.
        guard let clientRequirement else { return false }
        guard var token = auditToken(of: conn) else { return false }
        let data = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let attrs = [kSecGuestAttributeAudit: data] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let guest = code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(clientRequirement as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }
        return SecCodeCheckValidity(guest, [], req) == errSecSuccess
    }

    /// `auditToken` is SPI on NSXPCConnection (stable since macOS 11) — no public
    /// API exposes it, so read it via KVC, where it bridges as an NSValue wrapping
    /// the `audit_token_t` struct. This is the long-standing pattern for XPC peer
    /// validation. If it ever returns nil we fail closed (reject the connection).
    private static func auditToken(of conn: NSXPCConnection) -> audit_token_t? {
        guard conn.responds(to: NSSelectorFromString("auditToken")),
              let value = conn.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { buf in
            value.getValue(buf.baseAddress!, size: buf.count)
        }
        return token
    }

    // MARK: MASHelperProtocol

    func installMASApp(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String,
                       withReply reply: @escaping (Int32, String?) -> Void) {
        Self.workQueue.async {
            guard adamID > 0 else { reply(-1, "invalid adamID"); return }
            // logPath is a path the *client* chose that root will redirect onto, so
            // pin it to exactly what `MASInstaller` builds: the basename is the
            // adamID we were already given, and the directory must be a temp area.
            // A prefix check is not enough — it leaves both the directory and the
            // rest of the basename free, and the basename is interpolated into a
            // `/bin/sh -c` string below.
            let expectedLogName = "duo-mas-\(adamID).log"
            let logDirectory = (logPath as NSString).deletingLastPathComponent
            guard (logPath as NSString).lastPathComponent == expectedLogName,
                  Self.isTemporaryDirectory(logDirectory) else {
                reply(-1, "invalid log path"); return
            }
            guard let mas = Self.bundledMASPath() else {
                reply(-1, "bundled mas not found"); return
            }
            // Open the log ourselves instead of letting root's shell do `> path`.
            // The lexical checks above cannot make a shell redirect safe: `>` follows
            // symlinks, so a same-user process (which needs no XPC access at all) can
            // swap the predictable `duo-mas-<id>.log` for a link to a root-owned file
            // between the client creating it and root writing it — turning this into
            // an arbitrary-root-file truncation primitive.
            let logHandle: FileHandle
            do {
                logHandle = try Self.openLogFile(at: logPath, owner: uid)
            } catch {
                reply(-1, "invalid log path: \(error.localizedDescription)"); return
            }
            // Identical orchestration to the old MASInstaller osascript command — only
            // the privilege source changed (this process is already root):
            //   launchctl asuser <uid> → user's Aqua session (storedownloadd runs there)
            //   script -q /dev/null     → pseudo-TTY (mas emits live "N% downloaded")
            //   env SUDO_*              → mas seteuid's back to the account owner
            // The trailing `2>&1` still folds stderr into the log, but onto the fd we
            // opened and verified rather than a path the shell re-resolves.
            let command =
                "/bin/launchctl asuser \(uid) "
                + "/usr/bin/script -q /dev/null "
                + "/usr/bin/env SUDO_UID=\(uid) SUDO_GID=\(gid) SUDO_USER=\(Self.shellQuoted(userName)) MAS_NO_AUTO_INDEX=1 "
                + "\(Self.shellQuoted(mas)) install \(adamID) --force 2>&1"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = logHandle
            do {
                try process.run()
            } catch {
                reply(-1, "launch failed: \(error.localizedDescription)")
                return
            }
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let err = String(data: errData, encoding: .utf8)
            reply(process.terminationStatus, (err?.isEmpty ?? true) ? nil : err)
        }
    }

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0")
    }

    enum LogFileError: LocalizedError {
        case cannotOpen(Int32)
        case notARegularFile
        case wrongOwner(uid_t)
        case multiplyLinked(UInt16)
        case cannotTruncate(Int32)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let e):     return "open failed (errno \(e))"
            case .notARegularFile:       return "not a regular file"
            case .wrongOwner(let u):     return "owned by uid \(u), not the requesting user"
            case .multiplyLinked(let n): return "hard-linked \(n) times"
            case .cannotTruncate(let e): return "truncate failed (errno \(e))"
            }
        }
    }

    /// Open the `mas` log for writing as root, without ever being tricked into
    /// writing somewhere else.
    ///
    /// Three things have to hold at once, and the *order* is the point:
    ///   • `O_NOFOLLOW` — refuse if the final component is a symlink;
    ///   • **no `O_TRUNC`** — truncation is the damaging step, so it must not happen
    ///     until after the checks below. This is why we `ftruncate` afterwards
    ///     instead of asking `open` to do it;
    ///   • the opened fd must be a regular file, owned by the user we are installing
    ///     for, with exactly one link. Ownership is what defeats a *directory*
    ///     symlink further up the path (`/tmp/x -> /etc`), which `O_NOFOLLOW` alone
    ///     does not cover: anything root-owned fails the check and is left untouched.
    ///
    /// Note there is no `O_CREAT`: the client creates the file before calling (see
    /// `MASInstaller`), so root never has to. That matters — with `O_CREAT`, a
    /// *directory* symlink such as `/tmp/x -> /etc` (which passes the lexical check,
    /// since `O_NOFOLLOW` only guards the last component) would have root create a
    /// brand-new file in the target directory, and a freshly created file trivially
    /// satisfies every check below. Requiring the file to already exist and already
    /// belong to the user removes that file-planting primitive entirely.
    private static func openLogFile(at path: String, owner uid: Int) throws -> FileHandle {
        let fd = open(path, O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw LogFileError.cannotOpen(errno) }

        var closed = false
        func closeAndThrow(_ error: LogFileError) throws -> Never {
            if !closed { close(fd); closed = true }
            throw error
        }

        var st = stat()
        guard fstat(fd, &st) == 0 else { try closeAndThrow(.cannotOpen(errno)) }
        guard (st.st_mode & S_IFMT) == S_IFREG else { try closeAndThrow(.notARegularFile) }

        // Ownership is the check that survives a directory symlink: anything
        // root-owned (or belonging to another account) is refused untouched.
        guard st.st_uid == uid_t(uid) else { try closeAndThrow(.wrongOwner(st.st_uid)) }
        guard st.st_nlink == 1 else { try closeAndThrow(.multiplyLinked(st.st_nlink)) }

        // Only now is it safe to destroy the contents.
        guard ftruncate(fd, 0) == 0 else { try closeAndThrow(.cannotTruncate(errno)) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Quote a value for `/bin/sh -c`: wrap it in single quotes and rewrite each
    /// embedded quote as `'\''` (close, escaped quote, reopen). Every value this
    /// helper interpolates into a shell string goes through here — stripping the
    /// quote instead would silently corrupt legitimate values, and forgetting one
    /// value turns a root helper into a root shell.
    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Whether `path` is one of the per-user temp areas `NSTemporaryDirectory()`
    /// resolves to. Root's own temp dir differs from the calling user's, so the
    /// client has to supply the path — this bounds where it may point.
    private static func isTemporaryDirectory(_ path: String) -> Bool {
        // `standardizingPath` only collapses `..` for paths that exist, so reject
        // the component outright rather than trusting it to be resolved away.
        guard !(path as NSString).pathComponents.contains("..") else { return false }
        let standardized = (path as NSString).standardizingPath + "/"
        return ["/var/folders/", "/private/var/folders/", "/tmp/", "/private/tmp/"]
            .contains { standardized.hasPrefix($0) }
    }

    /// Locate `mas` relative to the helper's own embedded location:
    /// `…/Contents/MacOS/<helper>` → `…/Contents/Resources/mas`. Never trusts a
    /// path supplied by the client.
    private static func bundledMASPath() -> String? {
        guard let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first else {
            return nil
        }
        let mas = URL(fileURLWithPath: execPath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()   // …/Contents/MacOS
            .deletingLastPathComponent()   // …/Contents
            .appendingPathComponent("Resources/mas")
            .path
        return FileManager.default.isExecutableFile(atPath: mas) ? mas : nil
    }
}
