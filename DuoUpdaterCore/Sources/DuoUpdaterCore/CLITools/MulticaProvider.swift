import Darwin
import Foundation

public struct MulticaProvider: CLIToolProvider {
    public var kind: CLIToolKind { .multica }
    public var readsGitHubAPI: Bool { true }

    typealias Usage = @Sendable ([CLIToolProcesses.Target]) -> [CLIToolProcesses.Target: CLIToolUsage]

    let scanner: MulticaScanner
    let release: MulticaRelease
    let usage: Usage

    public init() {
        self.init(scanner: MulticaScanner(), release: MulticaRelease(), usage: { CLIToolProcesses.usage(of: $0) })
    }

    init(scanner: MulticaScanner, release: MulticaRelease, usage: @escaping Usage) {
        self.scanner = scanner
        self.release = release
        self.usage = usage
    }

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool { scanner.scan().map(Self.sighting) }
    }

    private static func sighting(_ install: MulticaInstall) -> CLIToolSighting {
        CLIToolSighting(
            kind: .multica, path: install.path, version: install.version,
            state: [install.executable, install.binary.architecture.rawValue,
                    "\(install.file.identity.device)", "\(install.file.identity.inode)",
                    "\(install.file.changedSeconds)", "\(install.file.changedNanoseconds)",
                    "\(install.canReplace)"].joined(separator: "|"))
    }

    public func check() async -> CLIToolReport {
        let installs = await offCooperativePool { scanner.scan() }
        let candidates = installs.filter { $0.version.map(MulticaRelease.isVersion) == true }
        let published: Result<MulticaRelease.Published, any Error>?
        if candidates.isEmpty {
            published = nil
        } else {
            do { published = .success(try await release.latest()) }
            catch { published = .failure(error) }
        }
        let outdated: [CLIToolProcesses.Target]
        if case .success(let latest)? = published {
            outdated = candidates.filter { install in
                install.version.map { VersionComparator.isNewer(latest.version, than: $0) } == true
            }.map(\.target)
        } else {
            outdated = []
        }
        let processes = outdated.isEmpty ? [:] : await offCooperativePool { usage(outdated) }
        let statuses = installs.map { Self.status($0, published: published, usage: processes[$0.target]) }
        return CLIToolReport(kind: .multica, statuses: statuses, context: .multica,
                             sightings: installs.map(Self.sighting))
    }

    private static func status(
        _ install: MulticaInstall, published: Result<MulticaRelease.Published, any Error>?, usage: CLIToolUsage?
    ) -> CLIToolStatus {
        func verdict(_ state: CLIToolState, latest: String? = nil, oneClick: CLIToolCommand? = nil,
                     withheld: CLIToolWithheld? = nil, note: String? = nil,
                     manual: CLIToolCommand? = nil) -> CLIToolStatus {
            CLIToolStatus(
                kind: .multica, path: install.path, installedVersion: install.version, latestVersion: latest,
                channel: nil, state: state, oneClick: oneClick, withheld: withheld, note: note,
                manualCommand: manual, detail: .multica(install))
        }

        guard let installed = install.version, MulticaRelease.isVersion(installed), let published else {
            return verdict(.unknown, withheld: .versionUnreadable, note: "No stable Multica version was recorded in this build.")
        }
        let latest: MulticaRelease.Published
        switch published {
        case .success(let release):
            latest = release
        case .failure(let error):
            let limited = GitHubRateLimitGate.isRefusal(error) || (error as? CLIToolReleaseNotesError) == .rateLimited
            return verdict(.unknown, withheld: limited ? .rateLimited : .channelUnreadable,
                           note: "Could not read Multica’s latest GitHub release: \(error.localizedDescription)")
        }
        switch VersionComparator.compare(installed, latest.version) {
        case .orderedSame: return verdict(.upToDate, latest: latest.version)
        case .orderedDescending: return verdict(.ahead, latest: latest.version)
        case .orderedAscending: break
        }

        if let usage, usage.isRunning {
            return verdict(.updateAvailable, latest: latest.version, withheld: .busy, note: busyMessage)
        }
        guard !install.linked, !install.quarantined, install.file.links == 1 else {
            return verdict(.updateAvailable, latest: latest.version, withheld: .unsupportedInstaller,
                           note: "Multica is linked or quarantined.")
        }
        guard latest.archive(for: install.binary.architecture) != nil, latest.checksums != nil else {
            return verdict(.updateAvailable, latest: latest.version, withheld: .unverified,
                           note: "The Multica release has no matching archive and checksum manifest.")
        }
        let quotedPath = NvmCheck.shellQuoted(install.path)
        guard install.writable else {
            // v0.1.14 added standalone updates; v0.2.10 added versioned
            // archive names to the updater's existing legacy name lookup.
            let hasStandaloneUpdate = VersionComparator.compare(installed, "0.1.14") != .orderedAscending
            let findsArchive = VersionComparator.compare(installed, "0.2.10") != .orderedAscending
                || latest.legacyArchive(for: install.binary.architecture) != nil
            let command = hasStandaloneUpdate && findsArchive
                ? CLIToolCommand(executable: install.path, arguments: ["update"], pathPrefix: nil,
                                 shellLine: quotedPath + " update")
                : nil
            return verdict(.updateAvailable, latest: latest.version, withheld: .unsupportedInstaller,
                           note: "Multica’s executable or installation directory cannot be updated by this user.",
                           manual: command)
        }
        let command = CLIToolCommand(executable: "duo", arguments: ["install", install.path], pathPrefix: nil,
                                     shellLine: "duo install " + quotedPath)
        return verdict(.updateAvailable, latest: latest.version, oneClick: command)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await release.notes(force: force)
    }

    static let busyMessage = "This Multica executable is in use. Close its running CLI or daemon and try again."

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        guard status.kind == .multica, status.oneClick != nil, status.state == .updateAvailable,
              case .multica(let installed) = status.detail, status.path == installed.path,
              status.installedVersion == installed.version, installed.canReplace,
              let before = installed.version, let after = status.latestVersion,
              MulticaRelease.isVersion(before), MulticaRelease.isVersion(after),
              VersionComparator.isNewer(after, than: before)
        else { return .notOffered }

        do {
            let snapshot = try await offCooperativePool {
                guard scanner.reread(installed.path) == installed else { throw MulticaReplacement.Failure.changed }
                guard usage([installed.target])[installed.target]?.isRunning != true else {
                    throw MulticaReplacement.Failure.busy
                }
                return CLIToolTrust.sha256(of: URL(fileURLWithPath: installed.executable))
            }
            progress("Verifying the installed Multica release")
            let work = try await offCooperativePool {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("duo-multica-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                return directory
            }
            defer { await removeItemOffCooperativePool(at: work) }

            let oldBinary = try await verifiedExecutable(version: before, for: installed.binary.architecture, at: work)
            let originalMatches = await offCooperativePool {
                let digest = CLIToolTrust.sha256(of: oldBinary)
                return CLIToolTrust.matches(snapshot, published: digest)
            }
            guard originalMatches else { throw MulticaReplacement.Failure.unpublished }

            progress("Downloading and verifying Multica \(after)")
            let newBinary = try await verifiedExecutable(version: after, for: installed.binary.architecture, at: work)
            progress("Replacing Multica \(before) with \(after)")
            return try await InstallCommit.run("Multica replacement") {
                try await offCooperativePool {
                    try MulticaReplacement.replace(installed, with: newBinary) {
                        guard scanner.reread(installed.path) == installed else {
                            throw MulticaReplacement.Failure.changed
                        }
                        guard usage([installed.target])[installed.target]?.isRunning != true else {
                            throw MulticaReplacement.Failure.busy
                        }
                    }
                }
                return .updated(version: after)
            }
        } catch MulticaReplacement.Failure.busy {
            return .busy(Self.busyMessage)
        } catch {
            if Task.isCancelled || error is CancellationError {
                return .stopped(message: "Multica update cancelled", output: "", complete: true)
            }
            return .failed(message: error.localizedDescription, output: "")
        }
    }

    private func verifiedExecutable(version: String, for architecture: MulticaBinary.Architecture, at work: URL)
        async throws -> URL
    {
        let published = try await release.tagged(version)
        let archive = work.appendingPathComponent("\(version).tar.gz")
        let binary = work.appendingPathComponent("multica-\(version)")
        try await release.verifiedArchive(published, architecture: architecture, into: archive)
        try await MulticaArchive.extract(archive, version: version, architecture: architecture, into: binary)
        return binary
    }
}
