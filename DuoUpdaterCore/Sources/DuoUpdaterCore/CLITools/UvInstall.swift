import Foundation

/// One copy of uv — Astral's Python package manager — on this Mac, identified by
/// **where it is**.
///
/// uv is two executables, `uv` and `uvx`, with no Info.plist. The standalone
/// installer (`curl -LsSf https://astral.sh/uv/install.sh | sh`, cargo-dist)
/// puts both in `$XDG_BIN_HOME`, `$XDG_DATA_HOME/../bin` or `~/.local/bin` — a
/// GUI process sees no XDG variables, so `~/.local/bin` — and before 0.5.0 in
/// `~/.cargo/bin`. It also writes a receipt, `~/.config/uv/uv-receipt.json`
/// (`$XDG_CONFIG_HOME/uv` first when set), which is what `uv self update` reads
/// to find the install it may replace. This Mac on 2026-10-01:
///
///     {"binaries":["uv","uvx"],"install_layout":"flat",
///      "install_prefix":"/Users/bobby/.local/bin","modify_path":true,
///      "provider":{"source":"cargo-dist","version":"0.30.2"},
///      "source":{"app_name":"uv","name":"uv","owner":"astral-sh","release_type":"github"},
///      "version":"0.9.18"}
///
/// Signing: from **0.12.12** (2026-09-09, its changelog says so) the release
/// binaries are Developer ID signed by "OpenAI OpCo, LLC", Team `2DC432GLL2`, and
/// notarized; the arm64 identifier is derived by the linker and changes every
/// release, so only the Team is matched (`CLIToolTrust.signature`). Up to 0.12.11,
/// and every Homebrew build, they are ad hoc (linker-signed, no team): this
/// Mac's 0.9.18 is, and its `uv` and `uvx` are byte for byte the ones in the
/// `uv-aarch64-apple-darwin.tar.gz` of the 0.9.18 release, whose own sha256 is
/// the one that release publishes (`dc3bee4a…`, checked 2026-10-02).
///
/// Identity is the path. Homebrew's uv is the brew list's business and is not
/// looked for here.
public struct UvInstall: Sendable, Equatable, Codable {

    /// What put the file there, as far as the disk can tell.
    public enum Layout: String, Sendable, Codable {
        /// A regular file in the directory the standalone installer's receipt
        /// names, and that receipt is the official one (`astral-sh/uv` on
        /// GitHub): what `uv self update` updates.
        case standalone
        /// A symbolic link: `uv tool install uv` and pipx both link `~/.local/bin/uv`
        /// into a virtual environment, which `uv self update` refuses to touch.
        case link
        /// A regular file no official receipt names: copied by hand, built with
        /// `cargo install`, or left behind after another copy took the receipt.
        case unreceipted
    }

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or an empty file.
        case executableMissing
    }

    /// What a previous click learned by comparing an unsigned copy with the
    /// release it claims to be (`UvVerifier`), still true for the files on disk
    /// now — it is forgotten the moment either file changes.
    public enum HashVerdict: String, Sendable, Codable {
        /// `uv` (and `uvx`) are byte for byte the published release.
        case matches
        /// They are not: nothing of this copy is run.
        case differs
    }

    public let path: String
    public let layout: Layout
    /// The file that runs, symlinks resolved; nil when there is none.
    public let executable: String?
    /// The version the row shows: what `uv --version` printed for a copy signed
    /// by Astral's Team, or what the receipt says for an unsigned one (which is
    /// never run). nil when neither could be had.
    public let version: String?
    /// The receipt's `version`, for a `.standalone` copy.
    public let receiptVersion: String?
    public let signature: CLIToolTrust.Signature?
    /// `uvx` beside `uv`, when there is one, and its signature.
    public let uvx: String?
    public let uvxSignature: CLIToolTrust.Signature?
    public let problem: Problem?
    /// The file carries `com.apple.quarantine`, so it was not run.
    public let quarantined: Bool
    public let hashVerdict: HashVerdict?

    public init(
        path: String, layout: Layout = .standalone, executable: String? = nil, version: String?,
        receiptVersion: String? = nil, signature: CLIToolTrust.Signature? = nil, uvx: String? = nil,
        uvxSignature: CLIToolTrust.Signature? = nil, problem: Problem? = nil, quarantined: Bool = false,
        hashVerdict: HashVerdict? = nil
    ) {
        self.path = path
        self.layout = layout
        self.executable = executable
        self.version = version
        self.receiptVersion = receiptVersion
        self.signature = signature
        self.uvx = uvx
        self.uvxSignature = uvxSignature
        self.problem = problem
        self.quarantined = quarantined
        self.hashVerdict = hashVerdict
    }

    /// Signed by Astral's Team: trusted by the signature alone.
    var isVendorSigned: Bool { signature == .vendor }

    /// No identity at all — only a published hash can vouch for it.
    var needsHash: Bool { signature == .adHoc || signature == .unsigned }

    /// The directory `uv self update` installs into, and the one put first on the
    /// child's `PATH`.
    var directory: String { (path as NSString).deletingLastPathComponent }
}

/// The standalone installer's receipt, as `uv self update` reads it.
///
/// What uv does with it (uv `crates/uv/src/commands/self_update.rs` and
/// axoupdater `receipt.rs`, both `main` on 2026-10-02):
/// - it is `<XDG_CONFIG_HOME>/uv/uv-receipt.json` when that directory exists,
///   else `$HOME/.config/uv/uv-receipt.json` (`AXOUPDATER_CONFIG_PATH` and
///   `AXOUPDATER_CONFIG_WORKING_DIR` override both);
/// - a receipt that does not parse, or no receipt, ends `uv self update` with
///   "Self-update is only available for uv binaries installed via the standalone
///   installation scripts";
/// - `check_receipt_is_for_this_executable`: the running file's directory,
///   canonicalized — with a trailing `bin` dropped when the prefix's own last
///   component is not `bin` — must equal the canonicalized install prefix, else
///   the same refusal;
/// - only a source of `astral-sh/uv/uv` on GitHub takes uv's official update
///   path; any other is "custom".
public struct UvReceipt: Sendable, Equatable {
    public let installPrefix: String
    public let version: String
    public let isOfficial: Bool
    /// `provider.source` / `provider.version`, for axoupdater's cargo-dist
    /// 0.10–0.15 rule (`installRoot`).
    let provider: (source: String, version: String)?

    public static func == (a: UvReceipt, b: UvReceipt) -> Bool {
        a.installPrefix == b.installPrefix && a.version == b.version && a.isOfficial == b.isOfficial
            && a.provider?.source == b.provider?.source && a.provider?.version == b.provider?.version
    }

    static func location(home: URL) -> URL {
        home.appendingPathComponent(".config/uv/uv-receipt.json")
    }

    /// Blocking file read.
    static func read(home: URL) -> UvReceipt? {
        (try? Data(contentsOf: location(home: home))).flatMap(parse)
    }

    static func parse(_ data: Data) -> UvReceipt? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prefix = json["install_prefix"] as? String, !prefix.isEmpty,
              let version = json["version"] as? String
        else { return nil }
        let source = json["source"] as? [String: Any]
        let official = source?["release_type"] as? String == "github"
            && source?["owner"] as? String == "astral-sh"
            && source?["name"] as? String == "uv"
            && source?["app_name"] as? String == "uv"
        let provider = (json["provider"] as? [String: Any]).flatMap { p -> (String, String)? in
            guard let source = p["source"] as? String, let version = p["version"] as? String else { return nil }
            return (source, version)
        }
        return UvReceipt(installPrefix: prefix, version: version, isOfficial: official, provider: provider)
    }

    /// axoupdater's `install_prefix_root`: cargo-dist from 0.10.0 up to 0.15.0
    /// wrote the prefix with its `bin` included, which axoupdater strips.
    var installRoot: String {
        let url = URL(fileURLWithPath: installPrefix)
        if let provider, provider.source == "cargo-dist",
           VersionComparator.compare(provider.version, "0.10.0") != .orderedAscending,
           VersionComparator.compare(provider.version, "0.15.0") == .orderedAscending,
           url.lastPathComponent == "bin" {
            return url.deletingLastPathComponent().path
        }
        return installPrefix
    }

    /// `check_receipt_is_for_this_executable`, for the file at `executable`.
    func isFor(executable: String) -> Bool {
        let root = URL(fileURLWithPath: installRoot).standardizedFileURL.resolvingSymlinksInPath()
        var exeRoot = URL(fileURLWithPath: executable).standardizedFileURL.resolvingSymlinksInPath()
            .deletingLastPathComponent()
        if exeRoot.lastPathComponent == "bin", root.lastPathComponent != "bin" {
            exeRoot = exeRoot.deletingLastPathComponent()
        }
        return exeRoot.path == root.path
    }
}

/// Finds uv installs: `~/.local/bin/uv`, where the standalone installer puts it
/// by default, and `~/.cargo/bin/uv`, where it did before 0.5.0.
///
/// Network-free. A copy signed by Astral's Team is run once for `--version`; an
/// unsigned one is never run, and its version is the receipt's — which a later
/// click checks against the published release before anything of it runs
/// (`UvVerifier`). What that click learned is looked up here
/// (`UvVerifiedFiles`), so a copy found not to be the release reads as such
/// without another download.
public struct UvScanner: Sendable {

    public static let teamIdentifier = "2DC432GLL2"
    /// The first release whose binaries carry the Developer ID (2026-09-09).
    public static let firstSignedVersion = "0.12.12"

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature
    /// Runs a vendor-signed executable's `--version`. Injected so tests never run
    /// anything.
    public typealias VersionReader = @Sendable (URL) async -> String?
    public typealias QuarantineCheck = @Sendable (URL) -> Bool

    let home: URL
    let checkSignature: SignatureCheck
    let readVersion: VersionReader
    let isQuarantined: QuarantineCheck
    let verified: UvVerifiedFiles

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = { CLIToolTrust.signature(of: $0, teamIdentifier: UvScanner.teamIdentifier) },
        readVersion: @escaping VersionReader = UvScanner.runVersion,
        isQuarantined: @escaping QuarantineCheck = CLIToolTrust.hasQuarantine,
        verified: UvVerifiedFiles = .shared
    ) {
        self.home = home
        self.checkSignature = checkSignature
        self.readVersion = readVersion
        self.isQuarantined = isQuarantined
        self.verified = verified
    }

    var candidates: [URL] {
        [home.appendingPathComponent(".local/bin/uv"), home.appendingPathComponent(".cargo/bin/uv")]
    }

    /// Every install found, `~/.local/bin` first. The file-system and Security
    /// work runs off the cooperative pool; each vendor-signed copy is then run
    /// once for its version.
    public func scan() async -> [UvInstall] {
        let found = await offCooperativePool { self.locate() }
        var installs: [UvInstall] = []
        for install in found {
            installs.append(await withVersion(install))
        }
        return installs
    }

    /// The install at the same path, read again with the same rules — right
    /// before an update runs, and after it.
    public func reread(_ install: UvInstall) async -> UvInstall? {
        let path = install.path
        guard let located = await offCooperativePool({ self.locate().first { $0.path == path } }) else { return nil }
        return await withVersion(located)
    }

    /// Everything but a run version: blocking.
    func locate() -> [UvInstall] {
        let receipt = UvReceipt.read(home: home)
        return candidates.compactMap { install(at: $0, receipt: receipt) }
    }

    func install(at url: URL, receipt: UvReceipt?) -> UvInstall? {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let isLink = attributes[.type] as? FileAttributeType == .typeSymbolicLink
        let resolved = url.resolvingSymlinksInPath()
        let layout: UvInstall.Layout
        if isLink {
            layout = .link
        } else if let receipt, receipt.isOfficial, receipt.isFor(executable: url.path) {
            layout = .standalone
        } else {
            layout = .unreceipted
        }
        guard nonEmptyFile(resolved) else {
            return UvInstall(path: url.path, layout: layout, version: nil, problem: .executableMissing)
        }
        let signature = checkSignature(resolved)
        let uvxURL = url.deletingLastPathComponent().appendingPathComponent("uvx")
        let uvx = nonEmptyFile(uvxURL.resolvingSymlinksInPath()) ? uvxURL.path : nil
        let receiptVersion = layout == .standalone ? receipt?.version : nil
        let needsHash = signature == .adHoc || signature == .unsigned
        return UvInstall(
            path: url.path, layout: layout, executable: resolved.path,
            // An unsigned copy is never run: the receipt is all there is to go on.
            version: needsHash ? receiptVersion : nil,
            receiptVersion: receiptVersion, signature: signature, uvx: uvx,
            uvxSignature: uvx.map { checkSignature(URL(fileURLWithPath: $0).resolvingSymlinksInPath()) },
            quarantined: isQuarantined(resolved),
            hashVerdict: layout == .standalone && needsHash ? verified.verdict(for: url.path, uvx: uvx) : nil)
    }

    /// The signature is the gate: `--version` runs only for a file of Astral's
    /// Team with no quarantine flag.
    func withVersion(_ install: UvInstall) async -> UvInstall {
        guard install.isVendorSigned, !install.quarantined, let executable = install.executable else { return install }
        let version = await readVersion(URL(fileURLWithPath: executable))
        return UvInstall(
            path: install.path, layout: install.layout, executable: executable, version: version,
            receiptVersion: install.receiptVersion, signature: install.signature, uvx: install.uvx,
            uvxSignature: install.uvxSignature, problem: install.problem, quarantined: install.quarantined,
            hashVerdict: install.hashVerdict)
    }

    func nonEmptyFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular
        else { return false }
        return (attributes[.size] as? Int ?? 0) > 0
    }

    // MARK: - The host

    /// `uv --version` is answered by the argument parser before uv reads any
    /// configuration. Measured 2026-10-02 on the published 0.12.21 under
    /// `sandbox-exec` denying all network and every file write under `/private`
    /// and `/Users`, with `HOME` and `TMPDIR` an empty directory: printed
    /// `uv 0.12.21 (7af826859 2026-09-29 aarch64-apple-darwin)`, exit 0, 0.7 s
    /// wall (first launch of a notarized file), nothing created. With no
    /// environment at all it printed the same. So the child gets only a `PATH`.
    public static func runVersion(_ executable: URL) async -> String? {
        guard let outcome = try? await ChildProcess.run(
            executable.path, ["--version"], environment: ["PATH": CLIToolCommandRunner.systemPath],
            standardOutput: .capture, standardError: .discard,
            deadline: versionDeadline, onCancel: .terminateChild),
              outcome.succeeded, !outcome.timedOut
        else { return nil }
        return parseVersion(String(decoding: outcome.standardOutput, as: UTF8.self))
    }

    static let versionDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10), killAfter: .seconds(11))

    /// `uv 0.12.21 (7af826859 2026-09-29 aarch64-apple-darwin)` → "0.12.21"; 0.9.18
    /// prints `uv 0.9.18 (0cee76417 2025-12-16)`. The second word, when it is a
    /// release version.
    static func parseVersion(_ output: String) -> String? {
        let words = output.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words[0] == "uv" || words[0] == "uvx" else { return nil }
        let version = String(words[1])
        return UvRelease.isVersion(version) ? version : nil
    }

    /// The CPU a Mach-O executable is built for, in the spelling of uv's archive
    /// names (`uv-aarch64-apple-darwin.tar.gz`). uv ships thin executables; a fat
    /// file, or anything else, reads as nil. Blocking.
    static func architecture(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 8), header.count == 8 else { return nil }
        let bytes = [UInt8](header)
        // MH_MAGIC_64, little-endian: cf fa ed fe.
        guard bytes[0...3] == [0xCF, 0xFA, 0xED, 0xFE] else { return nil }
        let cpu = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
        switch cpu {
        case 0x0100_000C: return "aarch64"  // CPU_TYPE_ARM64
        case 0x0100_0007: return "x86_64"   // CPU_TYPE_X86_64
        default: return nil
        }
    }
}
