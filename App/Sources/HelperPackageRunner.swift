import Darwin
import DuoUpdaterCore
import Foundation

/// One signed XPC connection per operation. Approval and protocol support are
/// checked without registering a daemon or opening an authorization dialog.
struct HelperPackageRunner: Sendable {
    let connect: @Sendable () -> NSXPCConnection?
    var timeout: Duration = .seconds(5)

    func isAvailable() async -> Bool {
        guard let connection = connected() else { return false }
        defer { connection.invalidate() }
        guard let version = await version(connection) else { return false }
        return HelperProtocolRevision.supportsPackageInstall(versionReply: version)
    }

    func executor(bundleIdentifier: String?) -> PackageInstaller.Executor {
        { package, app, fingerprint, progress in
            guard let bundleIdentifier else {
                throw PackageInstaller.PackageError.installationFailed("The installed app has no bundle identifier.")
            }
            try await install(package: package, installedApp: app, bundleIdentifier: bundleIdentifier,
                              fingerprint: fingerprint, progress: progress)
        }
    }

    func install(package: URL, installedApp: URL, bundleIdentifier: String, fingerprint: Data,
                 progress: @escaping @Sendable (String) -> Void) async throws {
        guard let connection = connected() else {
            throw PackageInstaller.PackageError.requiresInteractiveInstaller("The package helper is not enabled.")
        }
        defer { connection.invalidate() }
        guard let version = await version(connection),
              HelperProtocolRevision.supportsPackageInstall(versionReply: version) else {
            throw PackageInstaller.PackageError.requiresInteractiveInstaller("The package helper is unavailable or needs restarting.")
        }
        let files = try await offCooperativePool { try PackageFiles(package: package) }
        defer { files.close() }
        let poll = Task {
            while !Task.isCancelled {
                await offCooperativePool { files.report(to: progress) }
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { break }
            }
        }
        let automatic = AutomaticInstall.active
        let result: (Int32, String?)
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                let once = PackageReplyOnce<(Int32, String?)>()
                connection.interruptionHandler = {
                    once.run { continuation.resume(throwing: PackageInstaller.PackageError.installationFailed("The helper connection was interrupted. Check the installed version before retrying.")) }
                }
                connection.invalidationHandler = connection.interruptionHandler
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    once.run { continuation.resume(throwing: error) }
                }) as? MASHelperProtocol else {
                    once.run { continuation.resume(throwing: PackageInstaller.PackageError.installationFailed("The helper connection is unavailable.")) }
                    return
                }
                proxy.installPackage(package: files.package, fingerprint: fingerprint,
                    installedAppPath: installedApp.path, bundleIdentifier: bundleIdentifier,
                    automatic: automatic, progress: files.writer) { status, message in
                        once.run { continuation.resume(returning: (status, message)) }
                    }
            }
        } catch {
            // A transport failure cannot prove the helper did not start work.
            InstallCommit.handedOver()
            poll.cancel()
            await poll.value
            throw error
        }
        poll.cancel()
        await poll.value
        await offCooperativePool { files.report(to: progress) }
        if result.0 == 77 {
            throw PackageInstaller.PackageError.requiresInteractiveInstaller(result.1 ?? "Use macOS Installer for this package.")
        }
        if result.0 == 75 {
            throw AutomaticInstall.Deferred(result.1 ?? "The package update is temporarily deferred.")
        }
        guard result.0 == 0 else {
            throw PackageInstaller.PackageError.installationFailed(result.1 ?? "Installer exited with status \(result.0).")
        }
    }

    private func connected() -> NSXPCConnection? {
        guard let connection = connect() else { return nil }
        connection.remoteObjectInterface = NSXPCInterface(with: MASHelperProtocol.self)
        connection.resume()
        return connection
    }

    private func version(_ connection: NSXPCConnection) async -> String? {
        await withCheckedContinuation { continuation in
            let once = PackageReplyOnce<String?>()
            Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                once.run { continuation.resume(returning: nil) }
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                once.run { continuation.resume(returning: nil) }
            }) as? MASHelperProtocol else {
                once.run { continuation.resume(returning: nil) }
                return
            }
            proxy.helperVersion { reply in once.run { continuation.resume(returning: reply) } }
        }
    }
}

private final class PackageReplyOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var sent = false
    func run(_ body: () -> Void) {
        let claimed = lock.withLock { if sent { return false }; sent = true; return true }
        if claimed { body() }
    }
}

/// Only the polling task reads; cleanup starts after it has finished. The root
/// helper receives a duplicated write descriptor, not the private log's path.
private final class PackageFiles: @unchecked Sendable {
    let package: FileHandle
    let writer: FileHandle
    private let reader: FileHandle
    private let directory: URL

    init(package source: URL) throws {
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let package = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            try? package.close()
            throw PackageInstaller.PackageError.requiresInteractiveInstaller("This package format needs macOS Installer.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("duo-pkg-progress-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let log = directory.appendingPathComponent("progress.log")
            let logFD = open(log.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard logFD >= 0 else { throw CocoaError(.fileWriteUnknown) }
            let writer = FileHandle(fileDescriptor: logFD, closeOnDealloc: true)
            do {
                self.reader = try FileHandle(forReadingFrom: log)
                self.writer = writer
            } catch {
                try? writer.close()
                throw error
            }
            self.package = package
            self.directory = directory
        } catch {
            try? package.close()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func report(to progress: @Sendable (String) -> Void) {
        guard let data = try? reader.readToEnd(), !data.isEmpty else { return }
        InstallCommit.handedOver()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            progress(String(line))
        }
    }

    func close() {
        try? package.close()
        try? writer.close()
        try? reader.close()
        do { try FileManager.default.removeItem(at: directory) }
        catch { NSLog("package progress cleanup failed: %@", error.localizedDescription) }
    }
}
