import Foundation

/// A receipt and an exact installed path, not an app name, own this update.
/// Resolve before the official catalogue so a same-token cask cannot adopt it.
public actor ThirdPartyCaskSource: UpdateSource {
    public nonisolated let name = "Homebrew"

    struct Ownership: Sendable, Equatable {
        let token: String
        let tap: String
        let paths: Set<String>
        var qualifiedName: String { "\(tap)/\(token)" }
    }

    struct Unavailable: LocalizedError {
        let cask: String
        var errorDescription: String? {
            "Cannot check the original Homebrew tap for \(cask). Check its availability and trust in Homebrew; other update sources were not used."
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
              let cask = casks.first(where: { ($0["token"] as? String) == owner.token }),
              cask["tap"] as? String == owner.tap,
              let version = cask["version"] as? String, !version.isEmpty, version != "latest"
        else { throw Unavailable(cask: qualified) }
        // The receipt owns the install even when the tap is auto_updates or its
        // current release lags GitHub. Never borrow a newer vendor installer.
        let marketing = version.split(whereSeparator: { $0 == "," || $0 == ":" }).first.map(String.init)
        return RemoteVersion(
            shortVersion: marketing, version: nil,
            downloadURL: nil, pageURL: (cask["homepage"] as? String).flatMap(URL.init(string:)),
            sourceName: name, sourceIdentifier: qualified)
    }

    static func ownership(in roots: [String]) async -> [Ownership] {
        let fm = FileManager.default
        var result: [Ownership] = []
        for root in roots {
            guard let tokens = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for token in tokens where !token.hasPrefix(".") {
                guard let tap = BrewFormulaService.realCaskReceiptTap(token, caskroomPaths: [root]),
                      tap != "homebrew/cask" else { continue }
                let directory = URL(fileURLWithPath: root).appendingPathComponent(token)
                var paths: Set<String> = []
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
                        }
                    }
                }
                let receipt = (try? Data(contentsOf: directory.appendingPathComponent(".metadata/INSTALL_RECEIPT.json"))) ?? Data()
                for pattern in BrewFormulaService.pkgutilPatterns(installReceipt: receipt) {
                    for path in await BrewFormulaService.receiptApps(pkgutilPattern: pattern) ?? [] {
                        paths.insert(URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path)
                    }
                }
                result.append(Ownership(token: token, tap: tap, paths: paths))
            }
        }
        return result
    }
}
