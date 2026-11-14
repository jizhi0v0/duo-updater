import CryptoKit
import Darwin
import DuoUpdaterCore
import Foundation

/// XPC reply blocks may be invoked from the task that owns the operation.
/// It is sent exactly once by HelperService, after the installer finishes.
final class HelperPackageReply: @unchecked Sendable {
    private let reply: (Int32, String?) -> Void
    init(_ reply: @escaping (Int32, String?) -> Void) { self.reply = reply }
    func send(_ status: Int32, _ message: String?) { reply(status, message) }
}

/// Executes only a verified, root-private copy of a package. XPC supplies file
/// descriptors rather than paths root could be tricked into opening or writing.
actor HelperPackageInstall {
    static let shared = HelperPackageInstall()
    private let permits = InstallPermits(downloads: 1, applies: 1)
    private let validator = PackageInstaller()

    enum Failure: LocalizedError {
        case invalidRequest
        case invalidDescriptor
        case invalidProgress
        case unsafeStorage
        case changedPackage
        case installedIdentity
        case untrustedInstalledDeveloper
        case io(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidRequest: return "The package install request is invalid."
            case .invalidDescriptor: return "The package must be a readable regular file."
            case .invalidProgress: return "The package progress file is not owned by the caller."
            case .unsafeStorage: return "The helper's package storage is not private."
            case .changedPackage: return "The package changed after verification. Nothing was installed."
            case .installedIdentity: return "The installed app no longer matches the selected copy."
            case .untrustedInstalledDeveloper: return "The installed app does not match its trusted developer. Nothing was installed."
            case .io(let code): return "Package staging failed (errno \(code))."
            }
        }
    }

    struct Staged: Sendable {
        let directory: URL
        let package: URL

        func remove() {
            do { try FileManager.default.removeItem(at: directory) }
            catch { NSLog("duo-helper: package staging cleanup failed: %@", error.localizedDescription) }
        }
    }

    static let stagingParent = URL(fileURLWithPath:
        "/var/root/Library/Caches/com.duoupdater.helper/PackageInstallation", isDirectory: true)

    /// Synchronous file I/O, called on Dispatch. `owner` and `under` are fixture
    /// seams; production always uses root's fixed, inaccessible cache directory.
    static func stage(_ source: FileHandle, fingerprint: Data,
                      under parent: URL = stagingParent, owner: uid_t = 0) throws -> Staged {
        var sourceInfo = stat()
        guard fingerprint.count == SHA256.Digest.byteCount,
              fstat(source.fileDescriptor, &sourceInfo) == 0,
              sourceInfo.st_mode & S_IFMT == S_IFREG, sourceInfo.st_size > 0,
              fcntl(source.fileDescriptor, F_GETFL) & O_ACCMODE != O_WRONLY else {
            throw Failure.invalidDescriptor
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var parentInfo = stat()
        guard lstat(parent.path, &parentInfo) == 0,
              parentInfo.st_mode & S_IFMT == S_IFDIR,
              parentInfo.st_uid == owner, parentInfo.st_mode & 0o077 == 0 else {
            throw Failure.unsafeStorage
        }
        var template = Array(parent.appendingPathComponent("install.XXXXXX").path.utf8CString)
        guard let made = mkdtemp(&template) else { throw Failure.io(errno) }
        let directory = URL(fileURLWithPath: String(cString: made), isDirectory: true)
        let staged = Staged(directory: directory, package: directory.appendingPathComponent("update.pkg"))
        var keep = false
        defer { if !keep { staged.remove() } }
        let fd = open(staged.package.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.io(errno) }
        defer { close(fd) }
        var hash = SHA256()
        var offset: off_t = 0
        var buffer = Data(count: 1024 * 1024)
        while offset < sourceInfo.st_size {
            let count = min(buffer.count, Int(sourceInfo.st_size - offset))
            let readCount = buffer.withUnsafeMutableBytes {
                pread(source.fileDescriptor, $0.baseAddress, count, offset)
            }
            if readCount < 0, errno == EINTR { continue }
            guard readCount > 0 else { throw Failure.io(errno) }
            let chunk = buffer.prefix(readCount)
            hash.update(data: chunk)
            try chunk.withUnsafeBytes { bytes in
                var written = 0
                while written < readCount {
                    let count = write(fd, bytes.baseAddress!.advanced(by: written), readCount - written)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw Failure.io(errno) }
                    written += count
                }
            }
            offset += off_t(readCount)
        }
        guard Data(hash.finalize()) == fingerprint else { throw Failure.changedPackage }
        guard fsync(fd) == 0, fchmod(fd, 0o400) == 0 else { throw Failure.io(errno) }
        keep = true
        return staged
    }

    static func validateProgress(_ progress: FileHandle, caller: uid_t) throws {
        var info = stat()
        let flags = fcntl(progress.fileDescriptor, F_GETFL)
        guard flags >= 0, flags & O_ACCMODE != O_RDONLY,
              fstat(progress.fileDescriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_uid == caller else { throw Failure.invalidProgress }
    }

    static func validateInstalledIdentity(
        at app: URL, bundleIdentifier: String,
        verifiedTeam: @Sendable (URL) throws -> String? = {
            try SignatureVerifier.verifyCodeSignature(appAt: $0)
            return try SignatureVerifier.teamIdentifier(at: $0)
        }
    ) throws {
        guard !bundleIdentifier.isEmpty, bundleIdentifier.utf8.count <= 255,
              !app.path.contains("\0"), app.pathExtension == "app" else { throw Failure.invalidRequest }
        let installedTeam = try verifiedTeam(app)
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == bundleIdentifier else { throw Failure.installedIdentity }
        guard let trustedTeam = PackageInstallTrust.teamIdentifier(for: bundleIdentifier),
              installedTeam == trustedTeam else {
            throw Failure.untrustedInstalledDeveloper
        }
    }

    /// Runs to completion independently of the client's connection lifetime.
    /// The permit serializes package operations across every XPC connection.
    func install(package: FileHandle, fingerprint: Data, installedAppPath: String,
                 bundleIdentifier: String, automatic: Bool, progress: FileHandle,
                 caller: uid_t) async -> (Int32, String?) {
        await permits.waitForApply()
        defer { permits.signalApply() }
        guard geteuid() == 0 else {
            return (77, "The package helper is not running as root. Use macOS Installer.")
        }
        guard PackageInstallTrust.teamIdentifier(for: bundleIdentifier) != nil else {
            return (77, "This app's package developer is not registered for the helper. Use macOS Installer.")
        }
        do {
            guard installedAppPath.hasPrefix("/"),
                  !installedAppPath.contains("\0") else { throw Failure.invalidRequest }
            try Self.validateProgress(progress, caller: caller)
            let app = URL(fileURLWithPath: installedAppPath).resolvingSymlinksInPath()
            let staged = try await offCooperativePool {
                try Self.stage(package, fingerprint: fingerprint)
            }
            defer { staged.remove() }
            try await offCooperativePool { try Self.validateInstalledIdentity(at: app, bundleIdentifier: bundleIdentifier) }
            try await validator.validateProtectedPackage(staged.package, installedApp: app,
                                                         bundleIdentifier: bundleIdentifier)
            let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "USER": "root", "LOGNAME": "root"]
            let restart = try await ChildProcess.run("/usr/sbin/installer",
                ["-query", "RestartAction", "-pkg", staged.package.path, "-target", "/"],
                environment: environment,
                deadline: .init(terminateAfter: .seconds(30), killAfter: .seconds(32)), onCancel: .runToCompletion)
            guard restart.succeeded else {
                return (77, "The package's restart requirements could not be checked. Use macOS Installer.")
            }
            let action = String(decoding: restart.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard action == "None" else {
                return (77, "This package requires a system restart or shutdown. Use macOS Installer.")
            }
            try await AutomaticInstall.$active.withValue(automatic) {
                try await AutomaticInstall.checkPackageTarget(app)
            }
            try await offCooperativePool { try Self.validateInstalledIdentity(at: app, bundleIdentifier: bundleIdentifier) }
            let outcome = try await ChildProcess.run("/usr/sbin/installer",
                ["-pkg", staged.package.path, "-target", "/", "-verboseR"],
                environment: environment, standardError: .mergeIntoOutput,
                onCancel: .runToCompletion, onOutputChunk: { data in
                    // A closed client's log must never interrupt PackageKit.
                    do { try progress.write(contentsOf: data) }
                    catch { NSLog("duo-helper: package progress unavailable: %@", error.localizedDescription) }
                })
            guard outcome.succeeded else {
                let tail = String(decoding: outcome.standardOutput.suffix(4096), as: UTF8.self)
                // Installer has already run. Never forward its exit code as a
                // protocol-level pre-execution decline (77) or deferral (75).
                return (1, "Installer exited with status \(outcome.terminationStatus). \(tail)")
            }
            try await offCooperativePool { try Self.validateInstalledIdentity(at: app, bundleIdentifier: bundleIdentifier) }
            return (0, nil)
        } catch let deferred as AutomaticInstall.Deferred {
            return (75, deferred.reason)
        } catch {
            return (1, error.localizedDescription)
        }
    }
}
