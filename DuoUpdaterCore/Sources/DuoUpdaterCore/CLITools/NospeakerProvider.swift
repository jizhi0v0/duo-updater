import Darwin
import Foundation

public struct NospeakerInstall: Sendable, Equatable {
    public let path: String
    fileprivate let executable: String
    fileprivate let file: StandaloneCLIFileStamp
    fileprivate let directory: CLIToolProcesses.FileID
    fileprivate let digest: String
    fileprivate let replaceable: Bool
    fileprivate var pending: NospeakerRelease.Published?
}

/// Standalone copies in the official script's bin or the usual manual install bin.
public struct NospeakerProvider: CLIToolProvider {
    // History: docs/app-audits/nospeaker.md#历史与实测
    public let kind: CLIToolKind = .nospeaker
    public let readsGitHubAPI = true

    private let paths: [String]
    private let fingerprints: URL
    private let release: NospeakerRelease
    private let lookupBudget: Duration

    public init() {
        let state = DuoStateDirectory.isTestProcess ? DuoStateDirectory.testProcessScratchRoot : DuoStateDirectory.base
        self.init(home: FileManager.default.homeDirectoryForCurrentUser,
                  fingerprints: state.appendingPathComponent("com.duoupdater.app/nospeaker-fingerprints", isDirectory: true),
                  release: NospeakerRelease(), manualBin: URL(fileURLWithPath: "/usr/local/bin"))
    }

    init(home: URL, fingerprints: URL, release: NospeakerRelease, manualBin: URL? = nil,
         lookupBudget: Duration = .seconds(12)) {
        let vendorBin = home.appendingPathComponent(".local/bin")
        paths = ([vendorBin] + (manualBin.map { [$0] } ?? [])).map { $0.appendingPathComponent("nospeaker").path }
        self.fingerprints = fingerprints
        self.release = release
        self.lookupBudget = lookupBudget
    }

    private func installations() -> [NospeakerInstall] {
        var found: [NospeakerInstall] = []
        for install in paths.compactMap(installed(at:)) {
            if let index = found.firstIndex(where: { $0.executable == install.executable }) {
                if install.replaceable && !found[index].replaceable { found[index] = install }
            } else {
                found.append(install)
            }
        }
        return found
    }

    private func installed(at path: String) -> NospeakerInstall? {
        guard let executable = CLIToolProcesses.realpath(path) else { return nil }
        let url = URL(fileURLWithPath: executable)
        let parent = url.deletingLastPathComponent().path
        guard let file = StandaloneCLIFileStamp.read(at: executable), file.bytes <= NospeakerRelease.maximumExecutableBytes,
              let directory = CLIToolProcesses.fileID(parent), release.isVendorBinary(url),
              let digest = CLIToolTrust.sha256(of: url),
              CLIToolProcesses.realpath(path) == executable,
              StandaloneCLIFileStamp.read(at: executable) == file, CLIToolProcesses.fileID(parent) == directory
        else { return nil }

        // A bin directory alias is supported. An executable symlink is read-only.
        let replaceable = StandaloneCLIFileStamp.read(at: path) == file
            && file.links == 1 && file.owner == geteuid() && (file.mode & 0o7000) == 0
            && access(path, W_OK) == 0 && access(parent, W_OK | X_OK) == 0
            && !CLIToolTrust.hasQuarantine(url)
        return NospeakerInstall(path: path, executable: executable, file: file, directory: directory,
                                digest: digest, replaceable: replaceable)
    }

    private func version(for digest: String) -> String? {
        // The first release has neither a version switch nor version metadata.
        if digest == NospeakerRelease.initialDigest { return "1.0" }
        let file = fingerprints.appendingPathComponent(digest)
        guard let tag = try? String(contentsOf: file, encoding: .utf8), NospeakerRelease.isStableTag(tag),
              tag != "v1.0"
        else { return nil }
        return String(tag.dropFirst())
    }

    private func remember(_ digest: String, for release: NospeakerRelease.Published) throws {
        if let previous = version(for: digest) {
            guard VersionComparator.compare(previous, release.version) == .orderedSame else {
                throw NospeakerRelease.Failure.wrongBinary
            }
            return
        }
        // Separate atomic entries let the app and duo remember different
        // versions concurrently without losing each other's observations.
        try FileManager.default.createDirectory(at: fingerprints, withIntermediateDirectories: true)
        try release.tag.write(to: fingerprints.appendingPathComponent(digest), atomically: true, encoding: .utf8)
    }

    public func scan() async -> [CLIToolSighting] {
        await offCooperativePool {
            installations().map { sighting($0, version: version(for: $0.digest)) }
        }
    }

    public func check() async -> CLIToolReport {
        let installs = await offCooperativePool { installations() }
        guard !installs.isEmpty else { return CLIToolReport(kind: kind, statuses: [], context: .nospeaker) }

        var versions = await offCooperativePool {
            Dictionary(installs.compactMap { install in version(for: install.digest).map { (install.digest, $0) } },
                       uniquingKeysWith: { first, _ in first })
        }
        let statuses: [CLIToolStatus]
        do {
            let latest = try await release.latest()
            let unknown = Set(installs.map(\.digest)).subtracting(versions.keys)
            let rateLimit: String?
            if unknown.isEmpty {
                rateLimit = nil
            } else {
                let matched = try await identify(unknown, latest: latest)
                versions.merge(matched.versions) { known, _ in known }
                rateLimit = matched.rateLimit
            }
            let confirmed = versions
            statuses = await offCooperativePool {
                installs.map { install in
                    guard let version = confirmed[install.digest] else {
                        return verdict(install, version: nil, latest: latest.version, state: .unknown,
                                       withheld: rateLimit == nil ? .versionUnreadable : .rateLimited,
                                       note: rateLimit)
                    }
                    return compare(install, version: version, with: latest)
                }
            }
        } catch {
            let limited = Self.isRateLimited(error)
            statuses = installs.map { install in
                verdict(install, version: versions[install.digest], state: .unknown,
                        withheld: limited ? .rateLimited : .channelUnreadable, note: error.localizedDescription)
            }
        }
        return CLIToolReport(kind: kind, statuses: statuses, context: .nospeaker,
                             sightings: zip(installs, statuses).map { sighting($0, version: $1.installedVersion) })
    }

    private static func isRateLimited(_ error: any Error) -> Bool {
        GitHubRateLimitGate.isRefusal(error) || (error as? CLIToolReleaseNotesError) == .rateLimited
    }

    private func identify(_ unknown: Set<String>, latest: NospeakerRelease.Published) async throws
        -> (versions: [String: String], rateLimit: String?)
    {
        var remaining = unknown
        var versions: [String: String] = [:]
        let deadline = ContinuousClock.now.advanced(by: lookupBudget)

        func match(_ candidate: NospeakerRelease.Published) async throws {
            try Task.checkCancellation()
            let digest: String
            do {
                digest = try await before(deadline) {
                    try await withVerifiedRelease(candidate, purpose: .versionCheck) { _, digest in digest }
                }
            } catch {
                try Task.checkCancellation()
                if error is LookupExpired || Self.isRateLimited(error) { throw error }
                return
            }
            guard remaining.remove(digest) != nil else { return }
            versions[digest] = candidate.version
            // This lookup is useful even when our store is temporarily unwritable.
            try? await offCooperativePool { try remember(digest, for: candidate) }
        }

        do {
            try await match(latest)
            if !remaining.isEmpty {
                let history = try await before(deadline) { try await release.recent() }
                for candidate in history where candidate.tag != latest.tag {
                    try await match(candidate)
                    if remaining.isEmpty { break }
                }
            }
        } catch {
            try Task.checkCancellation()
            if Self.isRateLimited(error) { return (versions, error.localizedDescription) }
        }
        return (versions, nil)
    }

    private struct LookupExpired: Error {}

    private func before<T: Sendable>(
        _ deadline: ContinuousClock.Instant, work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard ContinuousClock.now < deadline else { throw LookupExpired() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: work)
            group.addTask {
                try await Task.sleep(until: deadline, clock: .continuous)
                throw LookupExpired()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    private func compare(_ install: NospeakerInstall, version: String, with latest: NospeakerRelease.Published)
        -> CLIToolStatus
    {
        switch VersionComparator.compare(version, latest.version) {
        case .orderedSame: return verdict(install, version: version, latest: latest.version, state: .upToDate)
        case .orderedDescending: return verdict(install, version: version, latest: latest.version, state: .ahead)
        case .orderedAscending: break
        }

        let withheld: CLIToolWithheld?
        if !install.replaceable { withheld = .unsupportedInstaller }
        else if latest.digest == nil { withheld = .unverified }
        else if isRunning(install) { withheld = .busy }
        else { withheld = nil }
        var checked = install
        if withheld == nil { checked.pending = latest }
        return verdict(checked, version: version, latest: latest.version, state: .updateAvailable,
                       withheld: withheld)
    }

    public func releaseNotes(for status: CLIToolStatus, force: Bool) async throws -> Changelog {
        try await release.notes(force: force)
    }

    static let busyMessage = "Close nospeaker and try again."
    private enum InUse: Error { case running }

    public func update(
        _ status: CLIToolStatus, progress: @escaping @Sendable (String) -> Void
    ) async -> CLIToolUpdateOutcome {
        guard status.kind == kind, status.state == .updateAvailable, status.oneClick != nil,
              case .nospeaker(var checked) = status.detail, checked.path == status.path, paths.contains(checked.path),
              checked.replaceable,
              let target = checked.pending, target.version == status.latestVersion,
              let version = status.installedVersion, VersionComparator.isNewer(target.version, than: version)
        else { return .notOffered }

        checked.pending = nil
        let install = checked
        let recheck: @Sendable () throws -> Void = {
            guard installed(at: install.path) == install else {
                throw StandaloneCLIReplacement.Failure.changed
            }
            guard !isRunning(install) else { throw InUse.running }
        }

        do {
            try await offCooperativePool(recheck)
            progress("Downloading and verifying nospeaker \(target.version)")
            return try await withVerifiedRelease(target, purpose: .install) { binary, digest in
                guard digest != install.digest else { throw NospeakerRelease.Failure.wrongBinary }
                progress("Replacing nospeaker \(version) with \(target.version)")
                return try await InstallCommit.run("nospeaker replacement") {
                    try await offCooperativePool {
                        try StandaloneCLIReplacement.replace(
                            at: install.executable, original: install.file, directory: install.directory, with: binary
                        ) {
                            try recheck()
                            // The replacement must have locally readable version metadata.
                            try remember(digest, for: target)
                        }
                    }
                    return .updated(version: target.version)
                }
            }
        } catch InUse.running {
            return .busy(Self.busyMessage)
        } catch StandaloneCLIReplacement.Failure.inProgress {
            return .busy(StandaloneCLIReplacement.Failure.inProgress.localizedDescription)
        } catch {
            if Task.isCancelled || error is CancellationError {
                return .stopped(message: "nospeaker update cancelled", output: "", complete: true)
            }
            return .failed(message: error.localizedDescription, output: "")
        }
    }

    private func withVerifiedRelease<T: Sendable>(
        _ published: NospeakerRelease.Published, purpose: RequestPurpose,
        use: (URL, String) async throws -> T
    ) async throws -> T {
        let work = try await offCooperativePool {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-nospeaker-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return directory
        }
        defer { await removeItemOffCooperativePool(at: work) }
        let binary = work.appendingPathComponent("nospeaker")
        let digest = try await release.verifiedExecutable(published, at: binary, purpose: purpose)
        return try await use(binary, digest)
    }

    private func isRunning(_ install: NospeakerInstall) -> Bool {
        let target = CLIToolProcesses.Target(executable: install.executable)
        return CLIToolProcesses.usage(of: [target])[target]?.isRunning == true
    }

    private func sighting(_ install: NospeakerInstall, version: String?) -> CLIToolSighting {
        CLIToolSighting(kind: kind, path: install.path, version: version,
                        state: "\(install.digest)|\(install.file.identity.inode)|\(install.replaceable)")
    }

    private func verdict(
        _ install: NospeakerInstall, version: String?, latest: String? = nil, state: CLIToolState,
        withheld: CLIToolWithheld? = nil, note: String? = nil
    ) -> CLIToolStatus {
        let command = install.pending.map { _ in
            CLIToolCommand(executable: "duo", arguments: ["install", install.path], pathPrefix: nil,
                           shellLine: "duo install " + NvmCheck.shellQuoted(install.path))
        }
        return CLIToolStatus(kind: kind, path: install.path, installedVersion: version, latestVersion: latest,
                             channel: nil, state: state, oneClick: command, withheld: withheld, note: note,
                             detail: .nospeaker(install))
    }
}
