import Foundation

/// The Boat CLI — boat.dev's sandbox client — as its installer leaves it,
/// identified by **its path**, `~/.ascii/bin/boat`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://boat.dev/install
/// | sh`, read 2026-10-04) and an install made from its download in a scratch
/// HOME the same day:
/// - `$HOME/.ascii/bin/boat` is one Mach-O executable, hard-coded from `$HOME`
///   (`INSTALL_DIR`). The installer fetches it from
///   `boat.dev/api/boat/cli/download?platform=darwin-<arm64|x64>&channel=prod`,
///   which 302s to the GitHub release asset
///   (`ariana-dot-dev/agent-server`, tag `boat-cli-v<version>`, asset
///   `boat-darwin-<arch>`). It may also link `/usr/local/bin/boat` to that file;
///   the link is the same install and is not looked at.
/// - The binary is Rust, ad hoc and linker-signed (`Signature=adhoc`, no Team),
///   so it is trusted by its published sha256 alone (`CLIToolTrust`): every
///   release carries a `SHA256SUMS` asset (`BoatRelease.publishedDigest`).
/// - The version is compiled in: the binary builds its update-check URL from a
///   literal `&current=<version>`, present exactly once in every build looked at
///   (1.0.0, 1.0.20-staging1, 1.0.34-staging1, 1.0.37, 1.0.38). It is read from
///   the file's bytes rather than by running `boat --version`, so nothing of an
///   unverified file runs.
/// - Its settings are `~/Library/Application Support/ascii/boat/config.json`
///   (Rust's `config_dir()` on macOS, whatever `XDG_CONFIG_HOME` says —
///   `boat status` reports that path). The installer *also* writes
///   `~/.config/ascii/boat/config.json` with `"channel": "prod"`, which the macOS
///   binary never reads. The real file carries the session `token` too, so only
///   `channel` and `api_url` are taken out of it (`BoatSettings`).
public struct BoatInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or an empty file.
        case executableMissing
        /// No single `&current=<version>` in the file: not a Boat build this code
        /// knows how to read.
        case versionUnreadable
    }

    /// `~/.ascii/bin/boat`: the row's identity.
    public let path: String
    /// The version compiled into the file (`BoatScanner.compiledVersion`), nil
    /// when it could not be read.
    public let version: String?
    /// The file's CPU in Boat's asset spelling, `arm64` or `x64`.
    public let architecture: String?
    public let signature: CLIToolTrust.Signature?
    public let quarantined: Bool
    public let settings: BoatSettings
    public let problem: Problem?

    public init(
        path: String, version: String?, architecture: String? = "arm64",
        signature: CLIToolTrust.Signature? = .adHoc, quarantined: Bool = false,
        settings: BoatSettings = BoatSettings(), problem: Problem? = nil
    ) {
        self.path = path
        self.version = version
        self.architecture = architecture
        self.signature = signature
        self.quarantined = quarantined
        self.settings = settings
        self.problem = problem
    }

    /// `darwin-arm64`, the `platform` Boat's endpoints and assets are named by.
    public var platform: String? { architecture.map { "darwin-\($0)" } }
}

/// What Boat's own config says about where it updates from.
///
/// `channel` is `null` until the user picks one, and the binary then asks for
/// `prod` (`boat status` on a fresh config: `"channel":"prod"`). `api_url` is
/// `null` for boat.dev; anything else points the binary — its `self-update`
/// included — at another Boat backend, which DuoUpdater does not ask.
public struct BoatSettings: Sendable, Equatable, Codable {
    public static let defaultChannel = "prod"
    public static let defaultAPI = "https://boat.dev"

    public let channel: String
    /// The config's `api_url` when it names a server other than boat.dev.
    public let customAPI: String?

    public init(channel: String = BoatSettings.defaultChannel, customAPI: String? = nil) {
        self.channel = channel
        self.customAPI = customAPI
    }

    public static func location(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/ascii/boat/config.json")
    }

    /// Blocking.
    public static func read(home: URL) -> BoatSettings {
        guard let data = try? Data(contentsOf: location(home: home)) else { return BoatSettings() }
        return parse(data)
    }

    /// Only the two keys; the file's `token` is never looked at.
    static func parse(_ data: Data) -> BoatSettings {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return BoatSettings() }
        let channel = (json["channel"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultChannel
        var custom: String? = nil
        if let api = json["api_url"] as? String, !api.isEmpty {
            let trimmed = api.hasSuffix("/") ? String(api.dropLast()) : api
            if trimmed.lowercased() != defaultAPI { custom = api }
        }
        return BoatSettings(channel: channel, customAPI: custom)
    }
}

/// Finds the Boat CLI: `~/.ascii/bin/boat`, the one place its installer puts it.
///
/// Network-free, and nothing is run: the version is read out of the file.
public struct BoatScanner: Sendable {

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature
    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// The CPU of an executable's bytes. Injected so tests can stand a script in
    /// for the Mach-O file.
    typealias ArchitectureRead = @Sendable (Data) -> String?

    let home: URL
    let checkSignature: SignatureCheck
    let isQuarantined: QuarantineCheck
    let readArchitecture: ArchitectureRead

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        // Boat has no Team ID; any team reads as `.otherSigner`, and only the
        // published hash decides (`BoatCheck`).
        checkSignature: @escaping SignatureCheck = { CLIToolTrust.signature(of: $0, teamIdentifier: "-") },
        isQuarantined: @escaping QuarantineCheck = CLIToolTrust.hasQuarantine
    ) {
        self.init(home: home, checkSignature: checkSignature, isQuarantined: isQuarantined,
                  readArchitecture: BoatScanner.architecture)
    }

    init(
        home: URL, checkSignature: @escaping SignatureCheck, isQuarantined: @escaping QuarantineCheck,
        readArchitecture: @escaping ArchitectureRead
    ) {
        self.home = home
        self.checkSignature = checkSignature
        self.isQuarantined = isQuarantined
        self.readArchitecture = readArchitecture
    }

    var location: URL { home.appendingPathComponent(".ascii/bin/boat") }

    public func scan() async -> [BoatInstall] {
        await offCooperativePool { self.locate() }.map { [$0] } ?? []
    }

    /// The install read again with the same rules — right before an update runs,
    /// and after it.
    public func reread() async -> BoatInstall? {
        await offCooperativePool { self.locate() }
    }

    /// Blocking.
    func locate() -> BoatInstall? {
        let url = location
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return nil }
        let settings = BoatSettings.read(home: home)
        let resolved = url.resolvingSymlinksInPath()
        // Read, never mapped (`ExecutableBytes`).
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0,
              let head = ExecutableBytes.head(of: resolved),
              let literals = ExecutableBytes.joinedWindows(in: resolved, marker: Self.marker, before: 0, after: 64)
        else {
            return BoatInstall(path: url.path, version: nil, architecture: nil, signature: nil,
                               settings: settings, problem: .executableMissing)
        }
        let version = Self.compiledVersion(in: literals)
        return BoatInstall(
            path: url.path, version: version, architecture: readArchitecture(head),
            signature: checkSignature(resolved), quarantined: isQuarantined(resolved),
            settings: settings, problem: version == nil ? .versionUnreadable : nil)
    }

    static let marker = Data("&current=".utf8)

    /// The version after the file's one `&current=` literal; nil when there is
    /// none, or more than one that disagree.
    ///
    /// Read as `<n>.<n>.<n>` and, when a `-` follows, the alphanumeric run after
    /// it — the shape of every `boat-cli-v` tag — so a letter that starts the next
    /// literal in the binary does not run on into the version.
    static func compiledVersion(in data: Data) -> String? {
        var found: Set<String> = []
        var start = data.startIndex
        while let range = data.range(of: marker, in: start..<data.endIndex) {
            found.insert(version(at: range.upperBound, in: data) ?? "")
            start = range.upperBound
        }
        guard found.count == 1, let version = found.first, BoatRelease.isVersion(version) else { return nil }
        return version
    }

    static func version(at index: Data.Index, in data: Data) -> String? {
        func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
        func isAlphanumeric(_ byte: UInt8) -> Bool {
            isDigit(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
        }
        var i = index
        func run(_ accept: (UInt8) -> Bool) -> Bool {
            let first = i
            while i < data.endIndex, i - first < 20, accept(data[i]) { i += 1 }
            return i > first
        }
        for part in 0..<3 {
            guard run(isDigit) else { return nil }
            if part < 2 {
                guard i < data.endIndex, data[i] == 0x2E else { return nil }
                i += 1
            }
        }
        var end = i
        if i < data.endIndex, data[i] == 0x2D {
            i += 1
            if run(isAlphanumeric) { end = i }
        }
        return String(decoding: data[index..<end], as: UTF8.self)
    }

    /// Boat ships thin executables; `arm64` or `x64`, the asset names' spelling.
    static func architecture(_ data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data.prefix(8))
        // MH_MAGIC_64, little-endian: cf fa ed fe.
        guard bytes[0...3] == [0xCF, 0xFA, 0xED, 0xFE] else { return nil }
        let cpu = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
        switch cpu {
        case 0x0100_000C: return "arm64"  // CPU_TYPE_ARM64
        case 0x0100_0007: return "x64"    // CPU_TYPE_X86_64
        default: return nil
        }
    }
}
