import Foundation

/// Leaf's standalone binary. Homebrew, Cargo, mise, Nix and app-owned copies
/// belong to their managers. Scanning reads the compiled version banner, never runs it.
public struct LeafInstall: Sendable, Equatable, Codable {
    public let path: String
    public let binary: String?
    public let version: String?
    public let target: String?
    public let quarantined: Bool
    public let writable: Bool

    public init(path: String, binary: String?, version: String?, target: String?,
                quarantined: Bool = false, writable: Bool = true) {
        self.path = path
        self.binary = binary
        self.version = version
        self.target = target
        self.quarantined = quarantined
        self.writable = writable
    }
}

public struct LeafScanner: Sendable {
    let home: URL
    let directories: [URL]
    let quarantine: @Sendable (URL) -> Bool
    let target: @Sendable (URL) -> String?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        var directories = [home.appendingPathComponent(".local/bin"), URL(fileURLWithPath: "/usr/local/bin")]
        if let custom = ProcessInfo.processInfo.environment["LEAF_INSTALL_DIR"], custom.hasPrefix("/") {
            directories.append(URL(fileURLWithPath: custom))
        }
        self.init(home: home, directories: directories, quarantine: CLIToolTrust.hasQuarantine,
                  target: LuvusScanner.target(of:))
    }

    init(home: URL, directories: [URL], quarantine: @escaping @Sendable (URL) -> Bool,
         target: @escaping @Sendable (URL) -> String?) {
        self.home = home
        self.directories = directories
        self.quarantine = quarantine
        self.target = target
    }

    public func scan() -> [LeafInstall] {
        var found: [LeafInstall] = []
        for directory in directories {
            guard let install = read(directory.appendingPathComponent("leaf").path) else { continue }
            if let index = found.firstIndex(where: { $0.binary != nil && $0.binary == install.binary }) {
                if install.path == install.binary { found[index] = install }
            } else if !found.contains(where: { $0.path == install.path }) {
                found.append(install)
            }
        }
        return found
    }

    func read(_ path: String) -> LeafInstall? {
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return LeafInstall(path: path, binary: nil, version: nil, target: nil)
        }
        let components = binary.split(separator: "/")
        let canonicalHome = LuvusScanner.canonicalPath(home.path) ?? home.path
        let cargoRoot = LuvusScanner.canonicalPath(home.appendingPathComponent(".cargo").path) ?? canonicalHome + "/.cargo"
        if components.contains("Cellar") || components.contains(where: { $0.hasSuffix(".app") })
            || binary.hasPrefix("/opt/homebrew/") || binary.hasPrefix("/nix/store/")
            || binary.hasPrefix(cargoRoot + "/") || binary.contains("/mise/installs/") {
            return nil
        }
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        let version = Self.version(of: url)
        return LeafInstall(path: path, binary: binary, version: version, target: target(url),
                           quarantined: quarantine(url),
                           writable: access(url.deletingLastPathComponent().path, W_OK) == 0)
    }

    static let marker = Data("leaf ".utf8)

    static func version(of url: URL) -> String? {
        ExecutableBytes.windows(in: url, marker: marker, before: 0, after: 64).flatMap(compiledVersion)
    }

    /// `--version`'s complete `leaf <version>\n` banner. The User-Agent has no
    /// terminator: v0.17.0's `leaf/0.17.0` directly precedes DER's 0x31 SET tag,
    /// which reads as an extra ASCII "1". Require the banner's newline instead.
    /// Keep prerelease suffixes so they cannot become stable.
    static func compiledVersion(_ windows: [Data]) -> String? {
        var found: Set<String> = []
        for window in windows {
            guard let version = LuvusScanner.version(at: window.startIndex + marker.count, in: window) else { continue }
            let end = window.startIndex + marker.count + version.utf8.count
            guard end < window.endIndex, window[end] == 0x0A else { continue }
            found.insert(version)
        }
        return found.count == 1 ? found.first : nil
    }
}
