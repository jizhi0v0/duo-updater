import Foundation
import Security

/// The root-side worker. Each accepted connection gets its own instance; all
/// installs funnel through one serial queue so two `mas` processes never run as
/// root at the same time (Update All fans out concurrent calls).
final class HelperService: NSObject, MASHelperProtocol {
    static let machServiceName = "com.duoupdater.helper"

    private static let workQueue = DispatchQueue(label: "com.duoupdater.helper.install")

    /// Reads (`stagedSparkleBundleVersions`). Its own queue, never `workQueue`:
    /// an install holds that one for as long as `mas` runs — minutes — and a read
    /// must neither wait behind it nor delay it. Serial, so concurrent requests
    /// cost root one walk at a time.
    private static let readQueue = DispatchQueue(label: "com.duoupdater.helper.read")

    /// Fixed at accept time by `HelperPeerGate`, from the connection that passed
    /// the code-signing requirement.
    private let clientIdentity: HelperClientIdentity

    init(clientIdentity: HelperClientIdentity) {
        self.clientIdentity = clientIdentity
        super.init()
    }

    // MARK: MASHelperProtocol

    func installMASApp(adamID: Int, uid: Int, gid: Int, userName: String, logPath: String,
                       withReply reply: @escaping (Int32, String?) -> Void) {
        let identity = clientIdentity
        Self.workQueue.async {
            guard adamID > 0 else { reply(-1, "invalid adamID"); return }
            guard identity.matchesClaim(uid: uid, gid: gid, userName: userName) else {
                reply(-1, "client identity did not match its XPC connection"); return
            }
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
            guard let bundledMAS = Self.bundledMASPath() else {
                reply(-1, "bundled mas not found"); return
            }
            // Run a verified private copy, never the bundle's `mas` by path: the
            // bundle is user-writable, and this runs as root.
            let staged: StagedMAS
            do {
                staged = try Self.stageVerifiedMAS(
                    at: bundledMAS,
                    requirement: OwnTeamIdentifier.requirement(bundleIdentifier: Self.masSigningIdentifier),
                    under: Self.masStagingParent)
            } catch {
                reply(-1, "bundled mas rejected: \(error.localizedDescription)"); return
            }
            defer { staged.remove() }
            let mas = staged.path
            // Open the log ourselves instead of letting root's shell do `> path`.
            // The lexical checks above cannot make a shell redirect safe: `>` follows
            // symlinks, so a same-user process (which needs no XPC access at all) can
            // swap the predictable `duo-mas-<id>.log` for a link to a root-owned file
            // between the client creating it and root writing it — turning this into
            // an arbitrary-root-file truncation primitive.
            let logHandle: FileHandle
            do {
                logHandle = try Self.openLogFile(at: logPath, owner: Int(identity.uid))
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
                "/bin/launchctl asuser \(identity.uid) "
                + "/usr/bin/script -q /dev/null "
                + "/usr/bin/env SUDO_UID=\(identity.uid) SUDO_GID=\(identity.gid) SUDO_USER=\(Self.shellQuoted(identity.userName)) MAS_NO_AUTO_INDEX=1 "
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
        reply(HelperProtocolRevision.versionReply(
            bundleVersion: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"))
    }

    /// Read-only, and takes nothing from the client but the identifier, which
    /// `StagedSparkleVersions.read` allow-lists before building a path from it.
    /// No identity claim to check: nothing here runs in, or writes to, anyone's
    /// session, and the connection itself already passed `HelperPeerGate`.
    func stagedSparkleBundleVersions(bundleID: String,
                                     withReply reply: @escaping (String?, String?, String?) -> Void) {
        Self.readQueue.async {
            guard let fields = StagedSparkleVersions.read(bundleID: bundleID) else {
                reply(nil, nil, nil)
                return
            }
            reply(fields.identifier, fields.shortVersion, fields.buildVersion)
        }
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

    /// The signing identifier `mas` is re-signed with at build time
    /// (`project.yml` post-build, `scripts/sign-sparkle-helpers.sh`).
    static let masSigningIdentifier = "com.duoupdater.mas"

    /// A verified private copy of `mas`, and the directory that holds it.
    struct StagedMAS {
        let directory: String
        let path: String

        func remove() {
            try? FileManager.default.removeItem(atPath: directory)
        }
    }

    enum MASStagingError: LocalizedError {
        case noRequirement
        case cannotCreateDirectory(Int32)
        case cannotOpenSource(Int32)
        case sourceNotARegularFile
        case sourceTooLarge(Int64)
        case cannotCopy(Int32)
        case signatureRejected(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noRequirement:                return "no code requirement for mas"
            case .cannotCreateDirectory(let e): return "cannot create staging directory (errno \(e))"
            case .cannotOpenSource(let e):      return "cannot open mas (errno \(e))"
            case .sourceNotARegularFile:        return "mas is not a regular file"
            case .sourceTooLarge(let n):        return "mas is \(n) bytes, over the limit"
            case .cannotCopy(let e):            return "cannot copy mas (errno \(e))"
            case .signatureRejected(let s):     return "mas failed its code requirement (OSStatus \(s))"
            }
        }
    }

    /// Generous for a thinned `mas` (a few MB); bounds what root reads into memory.
    static let masSizeLimit: Int64 = 64 * 1024 * 1024

    /// Where root stages `mas`. NOT `NSTemporaryDirectory()`: for root that is a
    /// 0700 directory, and `mas` drops to the requesting user (`SUDO_UID`) and
    /// then opens its own path — EACCES, exit 11 (real Mac, 2026-10-25).
    ///
    /// `/private/var/tmp` is `drwxrwxrwt root wheel`. Safe to stage in because:
    ///   • `mkdtemp` is a `mkdir` of a random name that fails if the name exists
    ///     and does not follow symlinks, so nothing can be planted in its place;
    ///   • the parent's sticky bit means a user cannot delete or rename the
    ///     directory root created there.
    static let masStagingParent = "/private/var/tmp"

    /// Copy `mas` into a fresh `mkdtemp` directory under `parent` (0711, owned by
    /// this process — root in the helper), check the COPY against `requirement`,
    /// and return it. Only the returned copy may be run.
    ///
    /// Why a copy: `Contents/Resources/mas` sits in a user-owned bundle, so any
    /// same-user process can replace it. Checking it in place and then running it
    /// by path leaves a window to swap it between the two (macOS has no
    /// `fexecve`). Nothing but this process can write into the directory or the
    /// copy, so what was checked once, here, is what runs.
    ///
    /// Why 0711 / 0555 and not 0700 / 0500: `mas` drops to the requesting user
    /// and then opens its own path, so that user must be able to traverse to the
    /// copy and read it. 0711 lets others pass through without listing or
    /// writing; 0555 lets them read and execute, never write.
    ///
    /// Fails closed: a nil requirement (unsigned or ad-hoc helper, so no team to
    /// pin) refuses. On any failure the staging directory is removed.
    static func stageVerifiedMAS(at source: String, requirement: String?,
                                 under parent: String) throws -> StagedMAS {
        guard let requirement else { throw MASStagingError.noRequirement }
        var compiled: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(requirement as CFString, [], &compiled)
        guard reqStatus == errSecSuccess, let compiled else {
            throw MASStagingError.signatureRejected(reqStatus)
        }

        var template = Array(((parent as NSString).appendingPathComponent("duo-mas.XXXXXX")).utf8CString)
        guard let made = mkdtemp(&template) else { throw MASStagingError.cannotCreateDirectory(errno) }
        let directory = String(cString: made)
        let staged = StagedMAS(directory: directory, path: (directory as NSString).appendingPathComponent("mas"))
        do {
            guard chmod(directory, 0o711) == 0 else { throw MASStagingError.cannotCreateDirectory(errno) }
            try copyRegularFile(from: source, to: staged.path)
            var code: SecStaticCode?
            let createStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: staged.path) as CFURL, [], &code)
            guard createStatus == errSecSuccess, let code else {
                throw MASStagingError.signatureRejected(createStatus)
            }
            let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
            let status = SecStaticCodeCheckValidityWithErrors(code, flags, compiled, nil)
            guard status == errSecSuccess else { throw MASStagingError.signatureRejected(status) }
            return staged
        } catch {
            staged.remove()
            throw error
        }
    }

    /// `O_NOFOLLOW` on the source (a symlinked `mas` is refused), a regular file
    /// under the size limit, written with `O_EXCL` into the private directory and
    /// left 0555.
    private static func copyRegularFile(from source: String, to destination: String) throws {
        let input = open(source, O_RDONLY | O_NOFOLLOW)
        guard input >= 0 else { throw MASStagingError.cannotOpenSource(errno) }
        defer { close(input) }
        var st = stat()
        guard fstat(input, &st) == 0 else { throw MASStagingError.cannotOpenSource(errno) }
        guard (st.st_mode & S_IFMT) == S_IFREG else { throw MASStagingError.sourceNotARegularFile }
        guard Int64(st.st_size) <= masSizeLimit else { throw MASStagingError.sourceTooLarge(Int64(st.st_size)) }

        let output = open(destination, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o700)
        guard output >= 0 else { throw MASStagingError.cannotCopy(errno) }
        defer { close(output) }
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        var total: Int64 = 0
        while true {
            let n = read(input, &buffer, buffer.count)
            if n < 0 { throw MASStagingError.cannotCopy(errno) }
            if n == 0 { break }
            total += Int64(n)
            guard total <= masSizeLimit else { throw MASStagingError.sourceTooLarge(total) }
            var written = 0
            while written < n {
                let w = buffer.withUnsafeBytes { write(output, $0.baseAddress! + written, n - written) }
                if w < 0 { throw MASStagingError.cannotCopy(errno) }
                written += w
            }
        }
        guard fchmod(output, 0o555) == 0 else { throw MASStagingError.cannotCopy(errno) }
    }
}
