import Foundation

/// Vite+ — VoidZero's `vp` — as its installer (`curl -fsSL https://vite.plus |
/// bash`) and `vp upgrade` leave it, identified by **its data root**.
///
/// The layout, from the installer and `crates/vp_shared` at v1.0.0 (read
/// 2026-10-06), and installs of 0.2.9, 0.3.3 and 1.0.0 made with them in scratch
/// HOMEs the same day:
/// - The root holds one directory per version (`0.3.3/`), each with
///   `bin/vp`, a wrapper `package.json` (`"name": "vp-global"`, `"version":
///   "<v>"`, depending on `vite-plus@<v>`) and the `node_modules` pnpm installed;
///   `current` is a symlink to the active one, and `bin/vp` (with `node`, `npm`,
///   `pnpm`, … as shims) links to `current/bin/vp`. `vp upgrade` installs the new
///   version beside the old, swaps `current`, and keeps the last three.
/// - Two roots: **`~/.vite-plus`** (`SingleRoot`), what every release up to
///   0.2.x installs and what later ones keep using once it exists; and
///   **`~/.local/share/vite-plus`** (`Split`, XDG data), a fresh install from
///   0.3.0 on. `vp` resolves `~/.vite-plus` whenever `~/.vite-plus/current`
///   exists, so a split install beside it is not the one `vp upgrade` would
///   change (`shadowed`). `VP_HOME`, `VP_DATA_DIR` and `XDG_DATA_HOME` move the
///   root; a value set in the user's shell is not in a GUI app's environment.
/// - `bin/vp` is a Rust executable, **ad hoc and linker-signed** (`Signature=adhoc`,
///   no Team) in every release looked at, and byte for byte the `vp` in the npm
///   package `@voidzero-dev/vite-plus-cli-darwin-<arm64|x64>` of its version (and
///   in the GitHub release's archive): 0.3.3 is `e6ba499a…`, 1.0.0 `d787c0a8…`.
///   So it is trusted by that package (`VitePlusVerifier`).
/// - A Homebrew install (`brew install vite-plus`) is the brew group's, and an
///   `npm install -g vite-plus` the npm group's; neither lives under these roots.
public struct VitePlusInstall: Sendable, Equatable, Codable {

    public enum Layout: String, Sendable, Codable {
        /// `~/.vite-plus`.
        case singleRoot
        /// `~/.local/share/vite-plus`.
        case split
    }

    public enum Problem: String, Sendable, Codable {
        /// `current` names no directory with a `bin/vp` in it.
        case executableMissing
        /// The active version's `package.json` names no version.
        case versionUnreadable
        /// A split install while `~/.vite-plus/current` exists: `vp upgrade`
        /// would update `~/.vite-plus`, not this one.
        case shadowed
    }

    /// The data root: the row's identity.
    public let path: String
    public let layout: Layout
    public let version: String?
    /// `current/bin/vp`, symlinks resolved.
    public let binary: String?
    /// The npm platform suffix the binary was built for (`darwin-arm64`), read
    /// from its Mach-O header.
    public let platform: String?
    public let quarantined: Bool
    /// What a click learned by comparing the binary with its version's npm
    /// package (`VitePlusVerifier`), while the file is unchanged.
    public let hashVerdict: UvInstall.HashVerdict?
    public let problem: Problem?

    public init(
        path: String, layout: Layout, version: String?, binary: String? = nil, platform: String? = nil,
        quarantined: Bool = false, hashVerdict: UvInstall.HashVerdict? = nil, problem: Problem? = nil
    ) {
        self.path = path
        self.layout = layout
        self.version = version
        self.binary = binary
        self.platform = platform
        self.quarantined = quarantined
        self.hashVerdict = hashVerdict
        self.problem = problem
    }
}

/// Finds Vite+ under its two default roots. Network-free, and nothing is run.
public struct VitePlusScanner: Sendable {

    /// The npm platform suffix an executable was built for. Blocking.
    typealias PlatformRead = @Sendable (URL) -> String?
    typealias QuarantineCheck = @Sendable (URL) -> Bool

    let home: URL
    let verified: UvVerifiedFiles
    let readPlatform: PlatformRead
    let isQuarantined: QuarantineCheck

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(home: home, verified: .vitePlus, readPlatform: ClaudeCodeRelease.platform(of:),
                  isQuarantined: CLIToolTrust.hasQuarantine)
    }

    /// The seams tests use: scripts stand in for `vp`, and verdicts go to a scratch file.
    init(home: URL, verified: UvVerifiedFiles, readPlatform: @escaping PlatformRead, isQuarantined: @escaping QuarantineCheck) {
        self.home = home
        self.verified = verified
        self.readPlatform = readPlatform
        self.isQuarantined = isQuarantined
    }

    var singleRoot: URL { home.appendingPathComponent(".vite-plus") }
    var splitRoot: URL { home.appendingPathComponent(".local/share/vite-plus") }

    /// Each root that holds an install (a `current` link), single root first.
    /// Blocking: files are stat'd and read.
    public func scan() -> [VitePlusInstall] {
        // As `vp` asks it: the link followed.
        let singleRootActive = FileManager.default.fileExists(atPath: singleRoot.appendingPathComponent("current").path)
        return [(singleRoot, VitePlusInstall.Layout.singleRoot), (splitRoot, .split)].compactMap { root, layout in
            guard Self.exists(root.appendingPathComponent("current")) else { return nil }
            return read(root: root, layout: layout, shadowed: layout == .split && singleRootActive)
        }
    }

    /// The install at `path` as it is now, or nil when it is gone.
    func reread(_ install: VitePlusInstall) -> VitePlusInstall? {
        scan().first { $0.path == install.path }
    }

    func read(root: URL, layout: VitePlusInstall.Layout, shadowed: Bool) -> VitePlusInstall {
        let active = root.appendingPathComponent("current").resolvingSymlinksInPath()
        let binary = active.appendingPathComponent("bin/vp")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0
        else {
            return VitePlusInstall(path: root.path, layout: layout, version: nil, problem: .executableMissing)
        }
        let version = Self.version(inPackage: active.appendingPathComponent("package.json"))
        let problem: VitePlusInstall.Problem? = shadowed ? .shadowed : (version == nil ? .versionUnreadable : nil)
        return VitePlusInstall(
            path: root.path, layout: layout, version: version, binary: binary.path,
            platform: readPlatform(binary),
            quarantined: isQuarantined(binary),
            hashVerdict: verified.verdict(for: binary.path, uvx: nil),
            problem: problem)
    }

    /// The wrapper package's `version`, when it is a release's version. The
    /// directory's own name is not used: a forced reinstall installs into
    /// `<version>+<suffix>`.
    static func version(inPackage url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count < 64 * 1024,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] as? String == "vp-global",
              let version = json["version"] as? String, VitePlusRelease.isVersion(version)
        else { return nil }
        return version
    }

    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}

extension UvVerifiedFiles {
    /// Vite+'s verdicts, keyed by the binary's path (`VitePlusVerifier`).
    static let vitePlus = UvVerifiedFiles(name: "vite-plus-verified-files.json")
}
