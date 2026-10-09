import Foundation

/// Deno — the JavaScript runtime — as its installer leaves it, identified by
/// **its path**, `~/.deno/bin/deno`.
///
/// The layout, from the vendor's installer (`curl -fsSL https://deno.land/install.sh
/// | sh`, which redirects to `deno.land/x/install@v0.3.3/install.sh`, read
/// 2026-10-09):
/// - It reads `https://dl.deno.land/release-latest.txt`, downloads
///   `https://dl.deno.land/release/<version>/deno-<aarch64|x86_64>-apple-darwin.zip`
///   and unzips its one file into `${DENO_INSTALL:-$HOME/.deno}/bin`. It writes
///   no receipt. `DENO_INSTALL` set in a shell is not in a GUI app's
///   environment, so only the default is looked at.
/// - `~/.deno/bin` also holds the shims `deno install -g` writes; only `deno`
///   itself is the install.
/// - Every build looked at (1.46.3, 2.0.0, 2.0.0-rc.10, 2.5.0, 2.9.3 stable and
///   LTS, 2.9.6, 2.9.7, a 2.9.7 canary) is Developer ID signed by Deno Land Inc.,
///   Team `2H4KBF436B`, with the hardened runtime. `deno upgrade` checks no hash
///   of what it installs, so the Team ID is what the trust rule rests on,
///   before an update and after it.
/// - **The version** is compiled in as `Deno/<version>+<7 hex>` — the user agent
///   a canary build sends, a literal in every build whatever its channel — once
///   in each of those ten builds, and with no other value. It is read from the
///   bytes, so nothing is run to read it. (`Deno/<version>` alone is no anchor:
///   it is also `Deno/0.80.0` in 2.9.6, another component's user agent; and the
///   `denover<version>` the research first found is two adjacent literals that
///   read `denover2.5.02.5.0+c6adba1` in 2.5.0.)
/// - **The channel** is not in those bytes. Deno decides it at run time: a
///   `denover` section the release pipeline adds to LTS and RC builds, else
///   whether the build was compiled as a canary; a canary's `Deno/<v>+<hash>`
///   looks like any other build's. So the check runs the vendor-signed file's
///   `--version`, which prints it (`deno 2.9.6 (stable, release, …)`), and only
///   a stable build is offered `deno upgrade`, which installs the newest
///   *stable* release whatever the build it runs from (`RequestedVersion` in
///   `cli/tools/upgrade.rs`, v2.9.7): on an LTS, RC or canary build it would
///   switch the channel.
///
/// A deno from Homebrew (`/opt/homebrew/bin/deno`) is brew's and is not looked
/// at; a `~/.deno/bin/deno` that links into a Homebrew Cellar, a `.app`, Nix,
/// cargo or mise's installs belongs to that owner and is skipped.
public struct DenoInstall: Sendable, Equatable, Codable {

    public enum Problem: String, Sendable, Codable {
        /// The path is a symlink to nothing, or not a non-empty file.
        case executableMissing
        /// No single `Deno/<version>+<hash>` literal in the file.
        case versionUnreadable
    }

    /// `~/.deno/bin/deno`: the row's identity.
    public let path: String
    /// The version compiled into the file, without its `+<hash>`.
    public let version: String?
    /// The build's short git revision (`0c07124`).
    public let revision: String?
    /// Deno Land's Team ID on the file, measured by the check
    /// (`DenoScanner.withSignature`); nil until then.
    public let signature: CLIToolTrust.Signature?
    /// What the file's `--version` printed, run only once the signature is
    /// Deno Land's: its version and channel (`stable`, `lts`, `rc`, `canary`).
    /// nil until then, or when it printed nothing readable.
    public let reported: Reported?
    public let quarantined: Bool
    /// Whether this user may create and rename files in the directory holding
    /// the file — what `deno upgrade` needs to put the new build in its place.
    public let writable: Bool
    public let problem: Problem?

    public struct Reported: Sendable, Equatable, Codable {
        public let version: String
        public let channel: String

        public init(version: String, channel: String) {
            self.version = version
            self.channel = channel
        }
    }

    public init(
        path: String, version: String?, revision: String? = nil, signature: CLIToolTrust.Signature? = .vendor,
        reported: Reported? = nil, quarantined: Bool = false, writable: Bool = true, problem: Problem? = nil
    ) {
        self.path = path
        self.version = version
        self.revision = revision
        self.signature = signature
        self.reported = reported
        self.quarantined = quarantined
        self.writable = writable
        self.problem = problem
    }

    /// A version with a prerelease part (`2.0.0-rc.10`): an RC build.
    public var isPrerelease: Bool { version?.contains("-") == true }

    func with(signature: CLIToolTrust.Signature?) -> DenoInstall {
        DenoInstall(path: path, version: version, revision: revision, signature: signature, reported: reported,
                    quarantined: quarantined, writable: writable, problem: problem)
    }

    func with(reported: Reported?) -> DenoInstall {
        DenoInstall(path: path, version: version, revision: revision, signature: signature, reported: reported,
                    quarantined: quarantined, writable: writable, problem: problem)
    }
}

/// Finds Deno at `~/.deno/bin/deno`.
///
/// Network-free. The scan runs nothing: the version is read out of the file.
/// The check adds the signature and, for a file signed by Deno Land and not
/// quarantined, what its `--version` prints.
public struct DenoScanner: Sendable {

    /// Deno Land Inc.
    public static let teamIdentifier = "2H4KBF436B"

    public typealias SignatureCheck = @Sendable (URL) -> CLIToolTrust.Signature
    public typealias QuarantineCheck = @Sendable (URL) -> Bool
    /// Runs a vendor-signed executable's `--version`. Injected so tests never run
    /// one.
    public typealias VersionReader = @Sendable (URL) async -> DenoInstall.Reported?

    let home: URL
    let checkSignature: SignatureCheck
    let isQuarantined: QuarantineCheck
    let readVersion: VersionReader

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        checkSignature: @escaping SignatureCheck = {
            CLIToolTrust.signature(of: $0, teamIdentifier: DenoScanner.teamIdentifier)
        },
        isQuarantined: @escaping QuarantineCheck = CLIToolTrust.hasQuarantine,
        readVersion: @escaping VersionReader = DenoScanner.runVersion
    ) {
        self.home = home
        self.checkSignature = checkSignature
        self.isQuarantined = isQuarantined
        self.readVersion = readVersion
    }

    /// `$DENO_INSTALL`'s default.
    var root: URL { home.appendingPathComponent(".deno") }
    var location: URL { root.appendingPathComponent("bin/deno") }

    /// Deno, or nothing. Blocking: the file is read (~80 MB searched).
    public func scan() -> DenoInstall? {
        let path = location.path
        // `lstat`: a dangling link is still an install, a broken one.
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return nil }
        guard let binary = LuvusScanner.canonicalPath(path) else {
            return DenoInstall(path: path, version: nil, signature: nil, problem: .executableMissing)
        }
        if Self.isOwnedElsewhere(binary) { return nil }
        // Read, never mapped (`ExecutableBytes`).
        let url = URL(fileURLWithPath: binary)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? Int ?? 0) > 0,
              let windows = ExecutableBytes.windows(in: url, marker: Self.marker, before: 0, after: 48)
        else {
            return DenoInstall(path: path, version: nil, signature: nil, problem: .executableMissing)
        }
        let compiled = Self.compiledVersion(in: windows)
        let directory = (binary as NSString).deletingLastPathComponent
        return DenoInstall(
            path: path, version: compiled?.version, revision: compiled?.revision, signature: nil,
            quarantined: isQuarantined(url), writable: access(directory, W_OK) == 0,
            problem: compiled == nil ? .versionUnreadable : nil)
    }

    /// The install with its signature read (blocking, the whole file is hashed)
    /// and, when that is Deno Land's and the file is not quarantined, its
    /// `--version` run.
    public func checked(_ install: DenoInstall) async -> DenoInstall {
        guard install.problem != .executableMissing else { return install }
        let url = URL(fileURLWithPath: install.path).resolvingSymlinksInPath()
        let checkSignature = self.checkSignature
        let signed = install.with(signature: await offCooperativePool { checkSignature(url) })
        guard signed.signature == .vendor, !signed.quarantined else { return signed }
        return signed.with(reported: await readVersion(url))
    }

    /// A path inside a Homebrew Cellar, an app bundle, the Nix store, cargo's
    /// bin or mise's installs: that owner updates it.
    static func isOwnedElsewhere(_ binary: String) -> Bool {
        let parts = binary.split(separator: "/").map(String.init)
        if binary.hasPrefix("/nix/store/") { return true }
        if parts.contains(where: { $0.hasSuffix(".app") }) { return true }
        if parts.contains("Cellar") { return true }
        if let i = parts.firstIndex(of: ".cargo"), parts.dropFirst(i + 1).first == "bin" { return true }
        if let i = parts.firstIndex(of: "mise"), parts.dropFirst(i + 1).first == "installs" { return true }
        return false
    }

    static let marker = Data("Deno/".utf8)

    /// The version in the file's `Deno/<version>+<7 hex>` literals; nil when
    /// there is none, or several that disagree. A `Deno/` followed by anything
    /// else (`Deno/2.9.7` alone, `Deno/0.80.0grpc-…`) is skipped.
    static func compiledVersion(in windows: [Data]) -> (version: String, revision: String)? {
        var found: Set<String> = []
        for window in windows {
            let start = window.startIndex + marker.count
            guard let version = LuvusScanner.version(at: start, in: window) else { continue }
            var i = start + version.utf8.count
            guard i < window.endIndex, window[i] == UInt8(ascii: "+") else { continue }
            i += 1
            guard window.endIndex - i >= 7 else { continue }
            let hash = window[i..<(i + 7)]
            guard hash.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else { continue }
            found.insert(version + "+" + String(decoding: hash, as: UTF8.self))
        }
        guard found.count == 1, let literal = found.first else { return nil }
        let parts = literal.split(separator: "+").map(String.init)
        guard DenoRelease.isVersion(parts[0]) else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: - The host

    /// `deno --version` is answered by its argument parser
    /// (`deno 2.9.6 (stable, release, aarch64-apple-darwin)` on the first line).
    /// The child gets an empty `HOME`-less environment with only a `PATH`, so it
    /// reads no configuration of the user's.
    public static func runVersion(_ executable: URL) async -> DenoInstall.Reported? {
        guard let outcome = try? await ChildProcess.run(
            executable.path, ["--version"], environment: ["PATH": CLIToolCommandRunner.systemPath, "NO_COLOR": "1"],
            standardOutput: .capture, standardError: .discard,
            deadline: versionDeadline, onCancel: .terminateChild),
              outcome.succeeded, !outcome.timedOut
        else { return nil }
        return parseVersion(String(decoding: outcome.standardOutput, as: UTF8.self))
    }

    static let versionDeadline = ChildProcess.Deadline(terminateAfter: .seconds(10), killAfter: .seconds(11))

    /// `deno 2.9.6 (stable, release, aarch64-apple-darwin)` → (2.9.6, stable); a
    /// canary prints `deno 2.9.7+a18ce33 (canary, …)`, read as (2.9.7, canary).
    /// The first line only; nil for anything else.
    static func parseVersion(_ output: String) -> DenoInstall.Reported? {
        guard let line = output.split(whereSeparator: \.isNewline).first else { return nil }
        let words = line.split(separator: " ", maxSplits: 2).map(String.init)
        guard words.count == 3, words[0] == "deno", words[2].hasPrefix("(") else { return nil }
        let version = String(words[1].split(separator: "+", maxSplits: 1)[0])
        guard DenoRelease.isVersion(version) else { return nil }
        let channel = words[2].dropFirst().split(separator: ",", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " )")) } ?? ""
        guard !channel.isEmpty, channel.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return DenoInstall.Reported(version: version, channel: channel)
    }
}
