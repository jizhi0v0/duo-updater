import Darwin
import Foundation

/// The set of casks Homebrew has actually installed on this machine, read from
/// the local Caskroom. This is the source of truth for *provenance*: an app's
/// `.app` filename matching a cask in the catalog does NOT mean the app came
/// from Homebrew — it may have been installed straight from the vendor's site or
/// the App Store. Installing a cask over a differently-sourced build risks
/// changing its code signature or moving its data (e.g. App Store sandbox
/// containers vs. `Application Support`), so we only treat an app as
/// brew-managed when its cask token appears here.
///
/// Reads the Caskroom directory directly (each immediate subdirectory is an
/// installed cask token) rather than shelling out to `brew list` — no
/// subprocess, and it works even if `brew` isn't on PATH.
public struct BrewLocalInventory: Sendable {
    let caskroomPaths: [String]
    /// Default Caskroom locations: Apple Silicon, then Intel.
    public static let defaultCaskroomPaths = [
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom",
    ]

    private let installedTokens: Set<String>
    private let thirdPartyTokens: Set<String>
    /// Token → the version Homebrew records as installed, for the casks where
    /// it records one (see `installedVersion(inCaskDirectory:token:)`).
    private let installedVersions: [String: String]

    /// Scans the given Caskroom paths once at construction. Cheap (a directory
    /// listing of a few dozen entries), so it's fine to build per check run.
    public init(caskroomPaths: [String] = BrewLocalInventory.defaultCaskroomPaths) {
        self.caskroomPaths = caskroomPaths
        let fm = FileManager.default
        var tokens: Set<String> = []
        var thirdParty: Set<String> = []
        var versions: [String: String] = [:]
        for path in caskroomPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                tokens.insert(entry.lowercased())
                if let tap = BrewFormulaService.realCaskReceiptTap(entry, caskroomPaths: [path]), tap != "homebrew/cask" {
                    thirdParty.insert(entry.lowercased())
                }
                let dir = URL(fileURLWithPath: path).appendingPathComponent(entry)
                if versions[entry.lowercased()] == nil,
                   let version = Self.installedVersion(inCaskDirectory: dir, token: entry) {
                    versions[entry.lowercased()] = version
                }
            }
        }
        self.installedTokens = tokens
        self.thirdPartyTokens = thirdParty
        self.installedVersions = versions
    }

    /// Test seam: build directly from a known token set (and, optionally, the
    /// version Homebrew recorded for some of them).
    public init(installedTokens: Set<String>, installedVersions: [String: String] = [:]) {
        self.caskroomPaths = []
        self.installedTokens = Set(installedTokens.map { $0.lowercased() })
        self.thirdPartyTokens = []
        self.installedVersions = Dictionary(
            installedVersions.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The cask version Homebrew itself considers installed, read the way
    /// `Caskroom.cask_installed_version` does: the newest
    /// `.metadata/<version>/<timestamp>/` (by timestamp name) that holds
    /// `Casks/<token>.rb`, `.json` or `.internal.json` names it. `brew outdated` compares
    /// this against the cask's current version.
    static func installedVersion(inCaskDirectory dir: URL, token: String) -> String? {
        let fm = FileManager.default
        let metadata = dir.appendingPathComponent(".metadata")
        guard let versions = try? fm.contentsOfDirectory(atPath: metadata.path) else { return nil }
        var newest: (stamp: String, version: String, dir: URL)?
        for version in versions where !version.hasPrefix(".") {
            let versionDir = metadata.appendingPathComponent(version)
            guard let stamps = try? fm.contentsOfDirectory(atPath: versionDir.path) else { continue }
            for stamp in stamps where !stamp.hasPrefix(".") && stamp > (newest?.stamp ?? "") {
                newest = (stamp, version, versionDir.appendingPathComponent(stamp))
            }
        }
        guard let newest else { return nil }
        let casks = newest.dir.appendingPathComponent("Casks")
        let recorded = ["json", "internal.json", "rb"].contains {
            fm.fileExists(atPath: casks.appendingPathComponent("\(token).\($0)").path)
        }
        return recorded ? newest.version : nil
    }

    /// The old `app` artifact is what an ordinary upgrade tries to move back
    /// into staging. Use the installed receipt and saved appdir (or a staged
    /// link for older receipts). The current cask can name a different app.
    static func missingRegisteredAppPath(token: String, caskroomPaths: [String]) -> String? {
        for root in caskroomPaths {
            let directory = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(token)
            guard let version = installedVersion(inCaskDirectory: directory, token: token) else { continue }
            let paths = receiptAppTargets(directory: directory, version: version)
                ?? stagedAppTargets(directory: directory.appendingPathComponent(version))
            return paths.sorted().first { path in
                var info = stat()
                return stat(path, &info) != 0 && (errno == ENOENT || errno == ENOTDIR)
            }
        }
        return nil
    }

    private static func receiptAppTargets(directory: URL, version: String) -> [String]? {
        let metadata = directory.appendingPathComponent(".metadata")
        guard let data = try? Data(contentsOf: metadata.appendingPathComponent("INSTALL_RECEIPT.json")),
              let receipt = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let artifacts = receipt["uninstall_artifacts"] as? [[String: Any]]
        else { return nil }
        if let recorded = (receipt["source"] as? [String: Any])?["version"] as? String,
           recorded != version { return nil }
        let apps = artifacts.compactMap { $0["app"] as? [Any] }
        // An installed definition with no `app` stanza can still contain a
        // staged installer bundle. It has no registered app target.
        guard !apps.isEmpty else { return [] }

        let config = (try? Data(contentsOf: metadata.appendingPathComponent("config.json")))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let appdir = ["explicit", "env", "default"].lazy.compactMap {
            (config?[$0] as? [String: Any])?["appdir"] as? String
        }.first
        let paths: [String] = apps.compactMap { args in
            guard let source = args.first as? String, !source.isEmpty else { return nil }
            let options = args.dropFirst().first as? [String: Any]
            let target = (options?["target"] as? String) ?? (source as NSString).lastPathComponent
            guard !target.isEmpty else { return nil }
            if target.hasPrefix("/") { return target }
            if target.hasPrefix("~/") { return (target as NSString).expandingTildeInPath }
            guard let appdir, appdir.hasPrefix("/") else { return nil }
            return (appdir as NSString).appendingPathComponent(target)
        }
        return paths.isEmpty ? nil : paths
    }

    private static func stagedAppTargets(directory: URL) -> [String] {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: directory, includingPropertiesForKeys: nil,
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var paths: [String] = []
        while let entry = walk.nextObject() as? URL {
            if walk.level >= BrewFormulaService.stagedDepth { walk.skipDescendants() }
            guard entry.pathExtension.lowercased() == "app",
                  let target = try? fm.destinationOfSymbolicLink(atPath: entry.path),
                  target.hasPrefix("/"), target.lowercased().hasSuffix(".app") else { continue }
            paths.append(target)
        }
        return paths
    }

    /// True when Homebrew actually installed this cask on this machine.
    public func isInstalled(caskToken: String) -> Bool {
        installedTokens.contains(caskToken.lowercased())
    }

    /// A third-party receipt must not satisfy the official catalogue's match,
    /// including when the scanner is looking at another same-named app copy.
    func isOfficialCandidate(caskToken: String) -> Bool {
        isInstalled(caskToken: caskToken) && !thirdPartyTokens.contains(caskToken.lowercased())
    }

    /// The version Homebrew records as installed for this cask, when it records
    /// one; nil says nothing about whether the cask is installed.
    public func installedVersion(caskToken: String) -> String? {
        installedVersions[caskToken.lowercased()]
    }

    /// No casks installed at all — so no app can possibly clear the provenance
    /// gate, and the ~2 MB catalog behind it never needs fetching. Lets
    /// `HomebrewCaskSource` decline before the network on a machine that doesn't
    /// use brew casks.
    public var isEmpty: Bool { installedTokens.isEmpty }
}
