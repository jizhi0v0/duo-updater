import Foundation

/// The Junie CLI — JetBrains' coding agent — as its installer leaves it, identified
/// by **its launcher**, `~/.local/bin/junie`.
///
/// The layout, from the vendor's `install.sh` (`JetBrains/junie`, read 2026-10-02)
/// and an install made with it in a scratch HOME the same day:
/// - `~/.local/bin/junie` is a bash script, the "shim". Every launch goes through
///   it: it applies a pending update, then execs the build `current` names. Both
///   paths are hard-coded from `$HOME` in `install.sh` (`JUNIE_BIN`, `JUNIE_DATA`);
///   only `HOME` moves them.
/// - `~/.local/share/junie/current` → `versions/<build>`, an absolute symlink the
///   installer sets with `ln -sfn`. The shim takes the **basename** of the link as
///   the build and runs `versions/<build>` (`resolve_version`), so that is what
///   is read here too, not wherever the link points.
/// - `versions/<build>/Applications/junie.app` is a jpackage bundle: the launcher
///   `Contents/MacOS/junie`, a JRE, and `Contents/app/junie-<channel>-<build>.jar`.
///   Builds from 3419.26 on (release), 3579.2 (EAP) and 3612.1 (nightly) also carry
///   a `channel` file at the build's root (`release\n`, `eap\n`, `nightly\n`); the
///   first-generation 1543.24 does not.
/// - `updates/` is where a running Junie stages its own update
///   (`JunieActivity`, `pendingUpdate`).
///
/// The bundle lives in Junie's own data directory — Junie's own layout — so it is
/// read here even though DuoUpdater's rule is otherwise that a file inside an
/// `.app` belongs to that app. Copies an IDE keeps for its ACP agent
/// (`~/Library/Caches/JetBrains/*/acp-agents/junie/*`) are the IDE's and are never
/// looked at.
///
/// Nothing here runs Junie: the build, the bundle's version and the channel are all
/// on disk, and the binary touches the keychain when it starts.
public struct JunieInstall: Sendable, Equatable, Codable {

    /// Which shim generation the launcher is. Both apply staged updates; the
    /// managed one also knows channels and is refreshed by Junie itself.
    public enum Shim: String, Sendable, Codable {
        /// Carries `# JUNIE_MANAGED_SHIM` (the shim `install.sh` writes today, 703
        /// lines on 2026-10-02).
        case managed
        /// The first generation: `# Junie CLI Shim` and `apply_pending_update`,
        /// without the marker (295 lines, written by the May 2026 installer).
        case legacy
    }

    public enum Problem: String, Sendable, Codable {
        /// `current` is missing or not a symlink — the shim then has no build to run.
        case noCurrent
        /// `current` names something that is not a build number.
        case versionUnreadable
        /// `versions/<build>` is not there.
        case versionMissing
        /// The build has no `Applications/junie.app` with an executable in it.
        case appMissing
        /// Neither a `channel` file nor a `junie-<channel>-<build>.jar` says which
        /// channel the build is from.
        case channelUnknown
        /// The `channel` file and the jar's name disagree.
        case channelConflict
    }

    /// The launcher, `~/.local/bin/junie`: the row's identity.
    public let path: String
    /// `~/.local/share/junie`.
    public let dataDirectory: String
    public let shim: Shim
    /// The build `current` names (`basename(readlink current)`), as the shim reads it.
    public let version: String?
    /// `CFBundleShortVersionString` of that build's `junie.app`. Equal to `version`
    /// on every build looked at (1543.24, 3419.26, 3579.2, 3612.1); a difference
    /// means the directory does not hold the build its name says.
    public let bundleVersion: String?
    /// As Junie spells it: `release`, `eap`, `nightly`, `experimental`.
    public let channel: String?
    /// The bundle's signature against JetBrains' Team ID (`JunieScanner.teamIdentifier`).
    /// Read by the check, not the scan (a Developer ID bundle is ~330 MB to hash);
    /// nil until then. Informational before an update — Junie is never run — and a
    /// gate after one (`JunieUpdater`).
    public let signature: CLIToolTrust.Signature?
    /// The build `updates/pending-update.json` names, when Junie has downloaded an
    /// update and its shim will install it at the next launch.
    public let pendingUpdate: String?
    public let problem: Problem?

    /// - Parameter dataDirectory: nil for the one `install.sh` pairs with `path`:
    ///   `<home>/.local/bin/junie` → `<home>/.local/share/junie`.
    public init(
        path: String, dataDirectory: String? = nil, shim: Shim = .managed, version: String?,
        bundleVersion: String? = nil, channel: String? = nil, signature: CLIToolTrust.Signature? = nil,
        pendingUpdate: String? = nil, problem: Problem? = nil
    ) {
        self.path = path
        self.dataDirectory = dataDirectory ?? URL(fileURLWithPath: path)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("share/junie").path
        self.shim = shim
        self.version = version
        self.bundleVersion = bundleVersion
        self.channel = channel
        self.signature = signature
        self.pendingUpdate = pendingUpdate
        self.problem = problem
    }

    /// `versions/<build>/Applications/junie.app`, when the build is known.
    public var bundle: String? {
        version.map { "\(dataDirectory)/versions/\($0)/Applications/junie.app" }
    }

    func with(signature: CLIToolTrust.Signature?) -> JunieInstall {
        JunieInstall(
            path: path, dataDirectory: dataDirectory, shim: shim, version: version,
            bundleVersion: bundleVersion, channel: channel, signature: signature,
            pendingUpdate: pendingUpdate, problem: problem)
    }
}

/// Junie's own setting that decides an offer: `auto-update` in the user's
/// `~/.junie/config.json`.
///
/// Junie's configuration reference (https://junie.jetbrains.com/docs/junie-cli-configuration.html,
/// read 2026-10-02) lists `auto-update` among the supported fields — "Enable or
/// disable automatic update checks" — and names `~/.junie/config.json` as the user
/// scope, below a project's `<project-root>/.junie/config.json`. In 3419.26 the key
/// is a nullable `Boolean` (`JunieConfigurationFile.autoUpdateEnabled`, read with
/// kotlinx's `BooleanSerializer`; from the class file, 2026-10-02). A missing file
/// or key means on, and only a JSON `false` is read as off.
///
/// What this does not see: a project's own `config.json`, which overrides the
/// user's in that project; `--skip-update-check` and `JUNIE_SKIP_UPDATE_CHECK`,
/// which live on a command line or in the user's shell.
public struct JunieSettings: Sendable, Equatable, Codable {

    /// Off means the update is the user's to take: reported with the command, never
    /// run (`JunieCheck`) — Claude Code's rule.
    public var autoUpdate: Bool = true

    public init() {}

    public init(autoUpdate: Bool) {
        self.autoUpdate = autoUpdate
    }

    public static func location(home: URL) -> URL {
        home.appendingPathComponent(".junie/config.json")
    }

    /// Blocking file read: keep it off the cooperative pool.
    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> JunieSettings {
        guard let data = try? Data(contentsOf: location(home: home)) else { return JunieSettings() }
        return parse(data)
    }

    static func parse(_ data: Data) -> JunieSettings {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = root["auto-update"] as? NSNumber,
              // A JSON bool only: `JSONSerialization` hands `0` back as the same
              // NSNumber type as `false`.
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else { return JunieSettings() }
        return JunieSettings(autoUpdate: number.boolValue)
    }
}

/// Finds the Junie install: `~/.local/bin/junie`, the only place the vendor's
/// installer puts it. Network-free and runs nothing.
public struct JunieScanner: Sendable {

    /// JetBrains s.r.o. Every build of the three channels' current heads — 3419.26,
    /// 3579.2, 3612.1 — is Developer ID signed with it (`codesign -dv`, 2026-10-02);
    /// 1543.24 shipped ad hoc.
    public static let teamIdentifier = "2ZEFAR8TH3"

    /// Reads a bundle's signature. Injected so tests build fake installs out of
    /// plain files.
    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature

    let home: URL
    let checkSignature: SignatureCheck

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = { CLIToolTrust.signature(of: $0, teamIdentifier: JunieScanner.teamIdentifier) }
    ) {
        self.home = home
        self.checkSignature = checkSignature
    }

    var launcher: URL { home.appendingPathComponent(".local/bin/junie") }
    var dataDirectory: URL { home.appendingPathComponent(".local/share/junie") }

    /// The install, or nothing. Blocking.
    public func scan() -> [JunieInstall] {
        install().map { [$0] } ?? []
    }

    /// The install with its signature read: blocking, and slow for a Developer ID
    /// bundle, whose every sealed file is hashed.
    public func withSignature(_ install: JunieInstall) -> JunieInstall {
        guard let bundle = install.bundle, install.problem == nil else { return install }
        return install.with(signature: checkSignature(URL(fileURLWithPath: bundle)))
    }

    /// nil when there is no launcher or it is not Junie's shim: another program
    /// named `junie` is not reported at all.
    func install() -> JunieInstall? {
        guard let shim = Self.shimGeneration(of: launcher.resolvingSymlinksInPath()) else { return nil }
        let data = dataDirectory.path
        func broken(_ problem: JunieInstall.Problem, version: String? = nil) -> JunieInstall {
            JunieInstall(path: launcher.path, dataDirectory: data, shim: shim, version: version, problem: problem)
        }
        let fm = FileManager.default
        let current = dataDirectory.appendingPathComponent("current")
        guard let target = try? fm.destinationOfSymbolicLink(atPath: current.path) else { return broken(.noCurrent) }
        let version = (target as NSString).lastPathComponent
        guard Self.isBuild(version) else { return broken(.versionUnreadable) }
        let root = dataDirectory.appendingPathComponent("versions/\(version)")
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return broken(.versionMissing, version: version)
        }
        let app = root.appendingPathComponent("Applications/junie.app")
        guard fm.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/junie").path) else {
            return broken(.appMissing, version: version)
        }
        let bundleVersion = Self.bundleVersion(of: app)
        let fromFile = Self.channelFile(in: root)
        let fromJar = Self.jarChannel(in: app, version: version)
        let channel: String?
        let problem: JunieInstall.Problem?
        switch (fromFile, fromJar) {
        case let (file?, jar?) where file != jar: (channel, problem) = (nil, .channelConflict)
        case (nil, nil): (channel, problem) = (nil, .channelUnknown)
        case let (file, jar): (channel, problem) = (file ?? jar, nil)
        }
        return JunieInstall(
            path: launcher.path, dataDirectory: data, shim: shim, version: version, bundleVersion: bundleVersion,
            channel: channel, pendingUpdate: Self.pendingUpdate(in: dataDirectory), problem: problem)
    }

    /// Junie's builds are two runs of digits (`1543.24`, `3612.1`) in every
    /// `update-info*.jsonl` line on 2026-10-02; one or more dots are accepted.
    static func isBuild(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 9 && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// The generation the launcher's text says it is, or nil when it is not Junie's.
    static func shimGeneration(of url: URL) -> JunieInstall.Shim? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        // The managed shim is 28 KB; the marker sits on line 3 and the legacy
        // shim's title on line 3, so the head is plenty.
        let text = String(decoding: (try? handle.read(upToCount: 64 * 1024)) ?? Data(), as: UTF8.self)
        guard text.hasPrefix("#!") else { return nil }
        if text.contains("JUNIE_MANAGED_SHIM") { return .managed }
        if text.contains("Junie CLI Shim"), text.contains("apply_pending_update") { return .legacy }
        return nil
    }

    static func bundleVersion(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
    }

    /// `<build>/channel`, trimmed; nil when absent or empty.
    static func channelFile(in root: URL) -> String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("channel"), options: .uncached),
              data.count <= 64
        else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return isChannelName(text) ? text : nil
    }

    /// `Contents/app/junie-<channel>-<build>.jar` → `<channel>`. Only a jar of
    /// this very build counts.
    static func jarChannel(in app: URL, version: String) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: app.appendingPathComponent("Contents/app").path)) ?? []
        let suffix = "-\(version).jar"
        for name in names.sorted() where name.hasPrefix("junie-") && name.hasSuffix(suffix) {
            let channel = String(name.dropFirst("junie-".count).dropLast(suffix.count))
            if isChannelName(channel) { return channel }
        }
        return nil
    }

    static func isChannelName(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 32 && s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }

    /// The build a staged update would install, read the way the shim reads
    /// `updates/pending-update.json` (`apply_pending_update`): it acts on a
    /// manifest with a `version` and a `zipPath` whose file exists, and drops any
    /// other — so only such a manifest is "staged".
    static func pendingUpdate(in dataDirectory: URL) -> String? {
        let manifest = dataDirectory.appendingPathComponent("updates/pending-update.json")
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String, !version.isEmpty,
              let zip = json["zipPath"] as? String, !zip.isEmpty,
              FileManager.default.fileExists(atPath: zip)
        else { return nil }
        return version
    }
}
