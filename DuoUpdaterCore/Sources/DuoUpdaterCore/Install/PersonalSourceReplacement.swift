import Darwin
import Foundation
import Security

/// The candidate is staged beside the destination so both moves can be exclusive
/// renames. Neither installation nor recovery can replace an occupied name.
public struct PersonalSourceReplacement: Codable, Sendable {
    public typealias Identity = PersonalSourceZIP.Identity
    typealias Failure = PersonalGitHubSource.Failure

    public let target: URL
    public let preparationID: UUID
    public let original: Identity
    public let backupIdentity: Identity
    public let candidate: Identity
    public let originalManifest: BackupManifest
    public let candidateManifest: BackupManifest
    public let authorization: UUID
    public let repositoryID: Int64
    public let ownerID: Int64
    public let track: PersonalGitHubSource.Track
    public let releaseID: Int64
    public let asset: PersonalGitHubSource.Asset
    public let tag: String

    public static func signingRequirement(at app: URL) throws -> String {
        try SignatureVerifier.installedSignerRequirement(installedApp: app, downloadedApp: app)
    }

    /// Keep the originally granted requirement even after a successful upgrade.
    public static func verifyRoute(installed: URL, candidate: URL, requirement: String) throws {
        let developerID = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var trust: SecRequirement?
        guard SecRequirementCreateWithString("(\(requirement)) and (\(developerID))" as CFString, [], &trust) == errSecSuccess,
              let trust else { throw Failure("Cannot verify the registered signing identity.") }
        // The installed row already passed ownership detection. Here we need
        // only evidence inside these two bundles, never another app's database.
        let scanner = AppScanner(locations: [], toolbox: ToolboxInventory(managedPaths: []),
                                 testflight: TestFlightInventory(macRows: [], accessible: false),
                                 channelBinding: { _, _, _ in nil })
        for bundle in [installed, candidate] {
            guard let copy = scanner.readApp(at: bundle), copy.myGoUpdate == nil, copy.electronUpdate == nil,
                  copy.sparkleFeedURL == nil, !copy.isMASApp, !copy.isTestFlightApp, !copy.isiOSAppOnMac,
                  OneClickGateRegistry.withholding(copy, offering: nil, fresh: true) == nil else {
                throw Failure("The app has another update route or an unverified edition.")
            }
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), trust) == errSecSuccess,
                  !(try Identity(at: bundle)).build.isEmpty else {
                throw Failure("The registered Developer ID or build could not be verified.")
            }
            let signed = try SignatureVerifier.signingInfo(at: bundle)
            let entitlements = signed[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
            guard !entitlements.keys.contains(where: { $0.hasPrefix("com.apple.developer.networking.networkextension") ||
                $0.hasPrefix("com.apple.developer.system-extension.") || $0.hasPrefix("com.apple.developer.fileprovider.") ||
                $0 == "com.apple.developer.endpoint-security.client" }) else {
                throw Failure("This app has system service entitlements that require a vendor update.")
            }
            let info = SignatureVerifier.infoPlist(of: bundle)
            let keys = ["SMPrivilegedExecutables", "SUFeedURL", "SUUpdateFeedURL", "KSProductID", "KSUpdateURL", "InputMethodConnectionName"]
            guard keys.allSatisfy({ info[$0] == nil }) else { throw Failure("This app uses a vendor installation or update service.") }
            let contents = bundle.appendingPathComponent("Contents")
            for path in ["Library/LaunchServices", "Library/LaunchDaemons", "Library/LaunchAgents", "Library/SystemExtensions",
                         "Library/LoginItems", "PlugIns", "Frameworks/Sparkle.framework", "Frameworks/Squirrel.framework",
                         "Resources/app-update.yml", "Resources/app-update.yaml", "_MASReceipt"] {
                var st = stat()
                guard lstat(contents.appendingPathComponent(path).path, &st) != 0, errno == ENOENT else {
                    throw Failure("This app needs its vendor’s installation procedure.")
                }
            }
        }
        try verifyExternalServices(bundle: installed)
        try SignatureVerifier.verifySatisfiesDesignatedRequirement(installedApp: installed, downloadedApp: candidate)
    }

    private static func verifyExternalServices(bundle: URL) throws {
        let fm = FileManager.default
        let id = try Identity(at: bundle).bundle
        for plist in try fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Library/LaunchDaemons"),
                                                includingPropertiesForKeys: nil) where plist.pathExtension == "plist" {
            // A machine may have unrelated, root-private launchd configuration.
            // A matching vendor namespace or app name is evidence about this app.
            let serviceName = plist.deletingPathExtension().lastPathComponent.lowercased()
            let appName = bundle.deletingPathExtension().lastPathComponent.lowercased()
            let namespace = id.lowercased().split(separator: ".").dropLast().joined(separator: ".")
            if !fm.isReadableFile(atPath: plist.path) {
                guard !serviceName.contains(appName), !namespace.isEmpty, !serviceName.hasPrefix(namespace + ".") else {
                    throw Failure("Cannot verify this app’s privileged service.")
                }
                continue
            }
            let data = try Data(contentsOf: plist)
            guard let job = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw Failure("Cannot verify installed privileged services.")
            }
            let executable = (job["Program"] as? String) ?? (job["ProgramArguments"] as? [String])?.first
            let label = job["Label"] as? String ?? ""
            if label == id || label.hasPrefix(id + ".") {
                throw Failure("This app has an installed privileged service.")
            }
            if let executable, let appEnd = executable.range(of: ".app/") {
                let app = URL(fileURLWithPath: String(executable[..<appEnd.lowerBound]) + ".app")
                if SignatureVerifier.infoPlist(of: app)["CFBundleIdentifier"] as? String == id {
                    throw Failure("This app has an installed privileged service.")
                }
            }
        }
    }

    public static func directory(for target: URL) -> URL {
        target.deletingLastPathComponent().appendingPathComponent("." + target.lastPathComponent + ".duo-update", isDirectory: true)
    }
    private var directory: URL { Self.directory(for: target) }
    public let preparationDirectory: URL
    private var staged: URL { directory.appendingPathComponent("Candidate.app") }
    private var displaced: URL { directory.appendingPathComponent("Original.app") }
    private var backup: URL { directory.appendingPathComponent("Backup.app") }

    public static func load(for target: URL) throws -> Self? {
        let url = directory(for: target).appendingPathComponent("transaction.json")
        var dirStat = stat()
        let folder = directory(for: target)
        if lstat(folder.path, &dirStat) != 0 && errno == ENOENT { return nil }
        guard (dirStat.st_mode & S_IFMT) == S_IFDIR, dirStat.st_uid == geteuid(), dirStat.st_mode & 0o077 == 0 else {
            throw Failure("Cannot verify the recovery directory.")
        }
        var st = stat()
        if lstat(url.path, &st) != 0 && errno == ENOENT { return nil }
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure("Cannot read the recovery record.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        let limit = 1_048_576
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == geteuid(),
              st.st_size > 0, st.st_size <= limit, let data = try file.read(upToCount: limit + 1),
              data.count <= limit else { throw Failure("Cannot read the recovery record.") }
        let plan = try JSONDecoder().decode(Self.self, from: data)
        guard plan.target.isFileURL, plan.target.path == target.path else { throw Failure("The saved installation path changed. Review recovery files.") }
        return plan
    }

    public static func prepare(target: URL, app: URL, anchor: Identity, checked: Identity, manifest: BackupManifest,
                               authorization: UUID, repository: PersonalGitHubSource.Repository,
                               track: PersonalGitHubSource.Track, release: PersonalGitHubSource.Release,
                               asset: PersonalGitHubSource.Asset) throws -> Self {
        let fm = FileManager.default
        guard try Identity(at: target) == anchor, try Identity(at: app) == checked,
              let originalManifest = BackupManifest.compute(for: target) else {
            throw Failure("The installation or verified package changed.")
        }
        let preparationID = UUID()
        // Foundation provides a per-operation replacement directory on this
        // volume, including cleanup of abandoned precommit staging after a crash.
        let directory = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                   appropriateFor: target, create: true)
        do {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let staged = directory.appendingPathComponent("Candidate.app")
            let backup = directory.appendingPathComponent("Backup.app")
            try fm.copyItem(at: app, to: staged)
            try fm.copyItem(at: target, to: backup)
            let candidate = try Identity(at: staged)
            let backupIdentity = try Identity(at: backup)
            guard candidate.device == anchor.device, candidate.sameSignedBuild(as: checked),
                  backupIdentity.sameSignedBuild(as: anchor),
                  BackupManifest.compute(for: staged) == manifest,
                  BackupManifest.compute(for: backup) == originalManifest else {
                throw Failure("The staged app or its backup could not be verified.")
            }
            try SignatureVerifier.verifyCodeSignature(appAt: backup)
            try SignatureVerifier.verifyCodeSignature(appAt: staged)
            return Self(target: target, preparationID: preparationID, original: anchor, backupIdentity: backupIdentity, candidate: candidate, originalManifest: originalManifest,
                        candidateManifest: manifest, authorization: authorization, repositoryID: repository.id,
                        ownerID: repository.owner.id, track: track, releaseID: release.id, asset: asset, tag: release.tag_name, preparationDirectory: directory)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    public func verifyBeforeCommit() throws {
        let staged = preparationDirectory.appendingPathComponent("Candidate.app")
        let backup = preparationDirectory.appendingPathComponent("Backup.app")
        guard matches(target, original, originalManifest), matches(staged, candidate, candidateManifest),
              try Identity(at: backup) == backupIdentity, BackupManifest.compute(for: backup) == originalManifest else {
            throw Failure("The installation, staged package or backup changed.")
        }
        try SignatureVerifier.verifyCodeSignature(appAt: backup)
    }

    public func commit() throws {
        try verifyBeforeCommit()
        let file = preparationDirectory.appendingPathComponent("transaction.json")
        try JSONEncoder().encode(self).write(to: file, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: file)
        try handle.synchronize()
        try handle.close()
        try syncDirectory(preparationDirectory)
        try moveExclusive(preparationDirectory, directory)
        try syncDirectory(target.deletingLastPathComponent())
        guard try Identity(at: target) == original, try Identity(at: staged) == candidate else {
            throw Failure("The installation or verified package changed.")
        }
        try Self.checkStopped(target)
        try moveExclusive(target, displaced)
        // An external updater could have won immediately before our first rename.
        // Put the exact object back, exclusively, before using our candidate.
        guard matches(displaced, original, originalManifest) else {
            try moveExclusive(displaced, target)
            throw Failure("Another updater changed this installation.")
        }
        guard matches(staged, candidate, candidateManifest) else { throw Failure("The staged app changed before replacement.") }
        try moveExclusive(staged, target)
        try syncDirectory(directory)
        try syncDirectory(target.deletingLastPathComponent())
    }

    public enum Outcome: Sendable { case installed, original, restoredBackup, needsReview }

    public func reconcile() throws -> Outcome {
        if matches(target, candidate, candidateManifest) { return .installed }
        if matches(target, original, originalManifest) { return .original }
        if matches(target, backupIdentity, originalManifest) { return .restoredBackup }
        var st = stat()
        // The candidate still at its original inode proves it was never delivered.
        // With the exact displaced original this identifies our interrupted move.
        guard lstat(target.path, &st) != 0, errno == ENOENT, matches(staged, candidate, candidateManifest),
              inodeMatches(displaced, original) else { return .needsReview }
        try Self.checkStopped(target)
        if !matches(displaced, original, originalManifest) {
            guard matches(backup, backupIdentity, originalManifest) else { return .needsReview }
            try moveExclusive(backup, target)
            return matches(target, backupIdentity, originalManifest) ? .restoredBackup : .needsReview
        }
        try moveExclusive(displaced, target)
        return matches(target, original, originalManifest) ? .original : .needsReview
    }

    /// A displaced original can have damaged contents while its volume and
    /// inode still prove that this transaction removed it from the target.
    private func inodeMatches(_ path: URL, _ expected: Identity) -> Bool {
        var st = stat()
        return lstat(path.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR &&
            UInt64(UInt32(bitPattern: st.st_dev)) == expected.device && UInt64(st.st_ino) == expected.inode
    }

    public static func checkStopped(_ target: URL) throws {
        let processes = NestedAppGuard.liveProcesses(includeUninspectable: true)
        guard !processes.isEmpty, !processes.contains(where: { $0.pid == 0 }),
              !AutomaticInstall.hasRunningProcess(at: target, processes: processes) else {
            throw Failure("The app is running or its processes could not be checked.")
        }
        try NestedAppGuard.check(target, appName: target.deletingPathExtension().lastPathComponent) { processes }
    }

    private func matches(_ path: URL, _ expected: Identity, _ manifest: BackupManifest) -> Bool {
        guard (try? Identity(at: path)) == expected, BackupManifest.compute(for: path) == manifest else { return false }
        do {
            try SignatureVerifier.verifyCodeSignature(appAt: path)
            return try Identity(at: path) == expected
        } catch { return false }
    }

    private func moveExclusive(_ from: URL, _ to: URL) throws {
        guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

extension PersonalSourceZIP.Identity {
    func sameSignedBuild(as other: Self) -> Bool {
        code != nil && team != nil && !build.isEmpty && code == other.code && team == other.team &&
        bundle == other.bundle && version == other.version && build == other.build
    }
}
