import Foundation

/// A receipt and an exact installed path, not an app name, own this update.
/// Resolve before the official catalogue so a same-token cask cannot adopt it.
public actor ThirdPartyCaskSource: UpdateSource {
    public nonisolated let name = "Homebrew"

    struct Ownership: Sendable, Equatable {
        let token: String
        let tap: String
        let paths: Set<String>
        var brewPrefix: String? = nil
        var qualifiedName: String { "\(tap)/\(token)" }
    }

    static let officialTap = "homebrew/cask"

    struct Unavailable: LocalizedError {
        let cask: String
        var errorDescription: String? {
            "Cannot check the original Homebrew tap for \(cask). Check its availability and trust in Homebrew; other update sources were not used."
        }
    }

    /// The owner was read successfully, but `:latest` supplies no comparable version.
    struct Unversioned: LocalizedError {
        let cask: String
        let selfUpdating: Bool
        var errorDescription: String? {
            "Homebrew does not provide a version for \(cask) (version :latest), so whether this copy is current cannot be determined."
        }
    }

    private let roots: [String]
    private let executor: BrewFormulaService.Executor
    private var ownershipTask: Task<[Ownership], Never>?
    private var reads: [String: Task<Data?, Never>] = [:]

    public init(caskroomPaths: [String] = BrewLocalInventory.defaultCaskroomPaths) {
        roots = caskroomPaths
        executor = BrewFormulaService.executor(brewPath: HomebrewInstaller.brewPath)
    }

    init(caskroomPaths: [String], executor: @escaping BrewFormulaService.Executor) {
        roots = caskroomPaths
        self.executor = executor
    }

    public func prewarm(_ apps: [InstalledApp]) async {
        ownershipTask = nil
        reads = [:]
    }

    public func invalidateMemo(for apps: [InstalledApp]) async {
        ownershipTask = nil
        reads = [:]
    }

    public func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
        guard !app.isMASApp else { return nil }
        if ownershipTask == nil {
            let roots = roots
            ownershipTask = Task { await Self.ownership(in: roots) }
        }
        let path = app.path.standardizedFileURL.resolvingSymlinksInPath().path
        let owners = await ownershipTask!.value.filter { $0.paths.contains(path) }
        guard let owner = owners.first else { return nil }
        guard Set(owners.map(\.qualifiedName)).count == 1 else {
            throw Unavailable(cask: owners.map(\.qualifiedName).sorted().joined(separator: ", "))
        }
        for owner in owners { try HomebrewInstaller.validateOwnerPrefix(owner.brewPrefix) }
        let qualified = owner.qualifiedName
        if reads[qualified] == nil {
            let executor = executor
            reads[qualified] = Task {
                guard let result = try? await executor(["info", "--json=v2", "--cask", "--", qualified]),
                      result.status == 0 else { return nil }
                return result.stdout
            }
        }
        guard let data = await reads[qualified]!.value,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]],
              let cask = casks.first,
              let tap = cask["tap"] as? String,
              // The receipt's tap, or the official one its own `tap_migrations.json`
              // moved the cask to (brew resolves the old name there itself). A move
              // to another third-party tap is someone else's package: fail closed.
              tap == owner.tap || tap == Self.officialTap,
              tap == Self.officialTap || (cask["token"] as? String) == owner.token,
              let version = cask["version"] as? String, !version.isEmpty
        else { throw Unavailable(cask: qualified) }
        if version == "latest" {
            throw Unversioned(cask: qualified,
                selfUpdating: tap == Self.officialTap && (cask["auto_updates"] as? Bool) == true)
        }
        // The receipt owns the install even when the tap is auto_updates or its
        // current release lags GitHub. The checker owns the explicit fallback policy.
        let marketing = version.split(whereSeparator: { $0 == "," || $0 == ":" }).first.map(String.init)
        var remote = RemoteVersion(
            shortVersion: marketing, version: nil,
            downloadURL: nil, pageURL: (cask["homepage"] as? String).flatMap(URL.init(string:)),
            sourceName: name, sourceIdentifier: qualified)
        // Moved to the official tap: it follows the official cask's rules from
        // here, its `auto_updates` included. Upgrades keep the old qualified
        // name, which brew follows to the new home and records there.
        if tap == Self.officialTap {
            remote.homebrewSelfUpdating = (cask["auto_updates"] as? Bool) ?? false
        }
        remote.homebrewPinned = (cask["pinned"] as? Bool) == true
        remote.homebrewCaskVersion = version
        remote.homebrewInstalledCaskVersion = BrewLocalInventory(caskroomPaths: roots)
            .installedVersion(caskToken: owner.token, brewPrefix: owner.brewPrefix)
            ?? (cask["installed"] as? String)
        return remote
    }

    static func ownership(in roots: [String], includeOfficial: Bool = false) async -> [Ownership] {
        let fm = FileManager.default
        var result: [Ownership] = []
        for root in roots {
            guard let tokens = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for token in tokens where !token.hasPrefix(".") {
                let directory = URL(fileURLWithPath: root).appendingPathComponent(token)
                guard let tap = BrewFormulaService.realCaskReceiptTap(token, caskroomPaths: [root]),
                      includeOfficial || tap != "homebrew/cask" else { continue }
                var paths: Set<String> = []
                let installedVersion = BrewLocalInventory.installedVersion(inCaskDirectory: directory, token: token)
                var stagedSources: Set<String> = []
                // Walk staged artifacts only, never into an app or arbitrary deep
                // extracted trees. A real staged .app is an installer, not a copy
                // Homebrew moved into the user's Applications directory.
                if let versions = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) {
                    for version in versions {
                        guard let walk = fm.enumerator(at: version, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                        while let entry = walk.nextObject() as? URL {
                            if walk.level >= BrewFormulaService.stagedDepth { walk.skipDescendants() }
                            guard entry.pathExtension.lowercased() == "app",
                                  (try? fm.destinationOfSymbolicLink(atPath: entry.path)) != nil else { continue }
                            paths.insert(entry.standardizedFileURL.resolvingSymlinksInPath().path)
                            if let installedVersion, version.lastPathComponent == installedVersion {
                                let source = String(entry.path.dropFirst(version.path.count + 1))
                                stagedSources.insert((source as NSString).standardizingPath)
                            }
                        }
                    }
                }
                // Resolve each absent artifact link from the receipt (#2036).
                // A surviving link supersedes only that same artifact's saved
                // target, so a helper cannot hide the main app's ownership, and
                // an old target is not adopted after that artifact was moved.
                if let version = installedVersion,
                   let targets = BrewLocalInventory.receiptAppTargets(
                       directory: directory, version: version, excludingStagedSources: stagedSources) {
                    for target in targets {
                        var isDirectory: ObjCBool = false
                        guard fm.fileExists(atPath: target, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                        paths.insert(URL(fileURLWithPath: target).standardizedFileURL.resolvingSymlinksInPath().path)
                    }
                }
                let receipt = (try? Data(contentsOf: directory.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))) ?? Data()
                for pattern in BrewFormulaService.pkgutilPatterns(installReceipt: receipt) {
                    for path in await BrewFormulaService.receiptApps(pkgutilPattern: pattern) ?? [] {
                        paths.insert(URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path)
                    }
                }
                let prefix = BrewLocalInventory.defaultCaskroomPaths.contains(root)
                    ? URL(fileURLWithPath: root).deletingLastPathComponent().path : nil
                result.append(Ownership(token: token, tap: tap, paths: paths, brewPrefix: prefix))
            }
        }
        return result
    }
}
