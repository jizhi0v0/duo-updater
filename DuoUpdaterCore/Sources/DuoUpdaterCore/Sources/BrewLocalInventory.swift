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
    /// Default Caskroom locations: Apple Silicon, then Intel.
    public static let defaultCaskroomPaths = [
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom",
    ]

    private let installedTokens: Set<String>
    /// Token → the version Homebrew records as installed, for the casks where
    /// it records one (see `installedVersion(inCaskDirectory:token:)`).
    private let installedVersions: [String: String]

    /// Scans the given Caskroom paths once at construction. Cheap (a directory
    /// listing of a few dozen entries), so it's fine to build per check run.
    public init(caskroomPaths: [String] = BrewLocalInventory.defaultCaskroomPaths) {
        let fm = FileManager.default
        var tokens: Set<String> = []
        var versions: [String: String] = [:]
        for path in caskroomPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                tokens.insert(entry.lowercased())
                let dir = URL(fileURLWithPath: path).appendingPathComponent(entry)
                if versions[entry.lowercased()] == nil,
                   let version = Self.installedVersion(inCaskDirectory: dir, token: entry) {
                    versions[entry.lowercased()] = version
                }
            }
        }
        self.installedTokens = tokens
        self.installedVersions = versions
    }

    /// Test seam: build directly from a known token set (and, optionally, the
    /// version Homebrew recorded for some of them).
    public init(installedTokens: Set<String>, installedVersions: [String: String] = [:]) {
        self.installedTokens = Set(installedTokens.map { $0.lowercased() })
        self.installedVersions = Dictionary(
            installedVersions.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The cask version Homebrew itself considers installed, read the way
    /// `Caskroom.cask_installed_version` does: the newest
    /// `.metadata/<version>/<timestamp>/` (by timestamp name) that holds
    /// `Casks/<token>.rb` or `.json` names it. `brew outdated` compares exactly
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
        let recorded = ["rb", "json"].contains {
            fm.fileExists(atPath: casks.appendingPathComponent("\(token).\($0)").path)
        }
        return recorded ? newest.version : nil
    }

    /// True when Homebrew actually installed this cask on this machine.
    public func isInstalled(caskToken: String) -> Bool {
        installedTokens.contains(caskToken.lowercased())
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
