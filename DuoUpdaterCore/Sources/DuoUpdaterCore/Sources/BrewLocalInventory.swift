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

    /// Scans the given Caskroom paths once at construction. Cheap (a directory
    /// listing of a few dozen entries), so it's fine to build per check run.
    public init(caskroomPaths: [String] = BrewLocalInventory.defaultCaskroomPaths) {
        let fm = FileManager.default
        var tokens: Set<String> = []
        for path in caskroomPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                tokens.insert(entry.lowercased())
            }
        }
        self.installedTokens = tokens
    }

    /// Test seam: build directly from a known token set.
    public init(installedTokens: Set<String>) {
        self.installedTokens = Set(installedTokens.map { $0.lowercased() })
    }

    /// True when Homebrew actually installed this cask on this machine.
    public func isInstalled(caskToken: String) -> Bool {
        installedTokens.contains(caskToken.lowercased())
    }
}
