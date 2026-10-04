import Foundation

/// Amp — Amp Frontier's coding agent — as its installer leaves it, identified by
/// **its path**, `~/.amp/bin/amp`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://ampcode.com/install.sh
/// | bash`, read 2026-10-04) and installs of 0.0.1791091069-gb9917f and
/// 0.0.1791121193-ge297b9 made with it in a scratch HOME the same day:
/// - `$AMP_HOME/bin/amp` (default `~/.amp`) is one Mach-O executable, ~109 MB,
///   Developer ID signed by Amp Frontier Corporation, Team `PZT9BJUAA5`
///   (identifier `com.ampcode.amp.cli`). The installer stages it as
///   `bin/tmp.XXXXXX`, checks it against the release's sha256 (and its minisign
///   signature when `minisign` is installed), and renames it into place.
/// - `~/.local/bin/amp` → `~/.amp/bin/amp` when that directory is on `PATH` (or
///   the first of its preferred directories that is); otherwise it appends
///   `~/.local/bin` to the shell's profile.
/// - The version is compiled in as the user agent `Amp-CLI/<version>`, once in
///   the file, ended by a NUL or a space. It is read from the bytes.
///
/// Amp updates itself in place (binary patches, `AMP_BINARY_PATCH_UPDATES`)
/// unless `amp.updates.mode` is `"disabled"`; DuoUpdater's click is for a copy
/// that has not run in a while. An npm install (`@sourcegraph/amp`) is the npm
/// group's.
public struct AmpInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        case executableMissing
        case versionUnreadable
    }

    /// `~/.amp/bin/amp`: the row's identity.
    public let path: String
    public let version: String?
    /// Amp Frontier's Team ID on the file, measured by the check.
    public let signature: CLIToolTrust.Signature?
    public let problem: Problem?

    public init(path: String, version: String?, signature: CLIToolTrust.Signature? = nil, problem: Problem? = nil) {
        self.path = path
        self.version = version
        self.signature = signature
        self.problem = problem
    }

    func with(signature: CLIToolTrust.Signature?) -> AmpInstall {
        AmpInstall(path: path, version: version, signature: signature, problem: problem)
    }
}

/// Amp's own setting that decides an offer: `amp.updates.mode` in
/// `~/.config/amp/settings.json`. `"disabled"` turns its update checks off
/// ("checking disabled", in the 2026-10-04 binary), and is read as the user's
/// choice to take updates some other way: reported with the command, never run.
/// Not seen: `AMP_SKIP_UPDATE_CHECK` in the user's shell, and workspace settings.
public struct AmpSettings: Sendable, Equatable, Codable {

    public var updatesMode: String?

    public init(updatesMode: String? = nil) {
        self.updatesMode = updatesMode
    }

    public var autoUpdate: Bool { updatesMode != "disabled" }

    public static func location(home: URL) -> URL {
        home.appendingPathComponent(".config/amp/settings.json")
    }

    /// Blocking file read; only the one key is taken (the file also holds MCP
    /// servers and their environment).
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AmpSettings {
        guard let data = try? Data(contentsOf: location(home: home)),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any],
              let mode = json["amp.updates.mode"] as? String, mode.count <= 32
        else { return AmpSettings() }
        return AmpSettings(updatesMode: mode)
    }
}

/// Finds Amp at `~/.amp/bin/amp`. Network-free, and nothing is run.
public struct AmpScanner: Sendable {

    /// Amp Frontier Corporation.
    public static let teamIdentifier = "PZT9BJUAA5"

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature

    let home: URL
    let checkSignature: SignatureCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = { CLIToolTrust.signature(of: $0, teamIdentifier: AmpScanner.teamIdentifier) }
    ) {
        self.home = home
        self.checkSignature = checkSignature
    }

    /// `$AMP_HOME`'s default; a value set in the user's shell is not in a GUI
    /// app's environment.
    var root: URL { home.appendingPathComponent(".amp") }
    var location: URL { root.appendingPathComponent("bin/amp") }

    /// Amp, or nothing. Blocking: the file is read (never mapped, `ExecutableBytes`).
    public func scan() -> AmpInstall? {
        let url = location
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return nil }
        let resolved = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0,
              let literals = ExecutableBytes.joinedWindows(in: resolved, marker: Self.marker, before: 0, after: 48)
        else {
            return AmpInstall(path: url.path, version: nil, problem: .executableMissing)
        }
        let version = Self.compiledVersion(in: literals)
        return AmpInstall(path: url.path, version: version, problem: version == nil ? .versionUnreadable : nil)
    }

    /// The install with its signature read: blocking, the file is hashed.
    public func withSignature(_ install: AmpInstall) -> AmpInstall {
        guard install.problem != .executableMissing else { return install }
        return install.with(signature: checkSignature(URL(fileURLWithPath: install.path).resolvingSymlinksInPath()))
    }

    static let marker = Data("Amp-CLI/".utf8)

    /// The version after each `Amp-CLI/` literal, up to the first byte a version
    /// does not contain; nil when there is none, or several that disagree.
    static func compiledVersion(in data: Data) -> String? {
        var found: Set<String> = []
        var start = data.startIndex
        while let range = data.range(of: marker, in: start..<data.endIndex) {
            var end = range.upperBound
            while end < data.endIndex, end - range.upperBound < 48, isVersionByte(data[end]) { end += 1 }
            found.insert(String(decoding: data[range.upperBound..<end], as: UTF8.self))
            start = range.upperBound
        }
        guard found.count == 1, let version = found.first, AmpRelease.isVersion(version) else { return nil }
        return version
    }

    static func isVersionByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
            || byte == 0x2E || byte == 0x2D
    }
}
