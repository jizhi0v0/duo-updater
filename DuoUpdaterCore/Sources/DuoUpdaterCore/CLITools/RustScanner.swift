import Foundation

/// What a local, network-free look at a rustup install finds: rustup's own
/// binary and the toolchains that follow a channel. Nothing is run.
///
/// Where: `~/.cargo` and `~/.rustup`, rustup's defaults. A GUI app sees neither
/// `CARGO_HOME` nor `RUSTUP_HOME` from the user's shell, so a relocated install
/// is not found; both homes are injected for tests and for running in a scratch
/// install. Homebrew's rustup (`/opt/homebrew/opt/rustup`, keg-only, built with
/// `no-self-update`) is not looked for: it is a formula, on the brew list.
///
/// The layout, as rustup 1.29.1 leaves it (measured 2026-10-01):
/// - `~/.cargo/bin/rustup`, a regular file, ad hoc and linker-signed (identifier
///   `rustup_init-<16 hex>`, no Team ID); `cargo`, `rustc`, … beside it are
///   symlinks to it;
/// - `~/.rustup/toolchains/<name>/`, one directory per toolchain, whose
///   `lib/rustlib/multirust-channel-manifest.toml` (~1 MB) is the channel
///   manifest it was installed from; `[pkg.rust]` sits ~80–86 KB in;
/// - `~/.rustup/update-hashes/<name>`: the first 20 hex digits of the channel
///   manifest's sha256 at the last update — what `rustup update` compares to skip
///   an unchanged channel (`UPDATE_HASH_LEN` in `src/dist/download.rs`).
struct RustScanner: Sendable {

    let cargoHome: URL
    let rustupHome: URL
    /// The binary's target triple. Injected so tests can stand a script in for
    /// a Mach-O build.
    let readHostTriple: @Sendable (URL) -> String?
    /// Whether a file carries `com.apple.quarantine`. Injected so tests never
    /// have to set one.
    let isQuarantined: @Sendable (URL) -> Bool

    init(
        cargoHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo"),
        rustupHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".rustup"),
        readHostTriple: @escaping @Sendable (URL) -> String? = RustScanner.hostTriple(of:),
        isQuarantined: @escaping @Sendable (URL) -> Bool = CLIToolTrust.hasQuarantine
    ) {
        self.cargoHome = cargoHome
        self.rustupHome = rustupHome
        self.readHostTriple = readHostTriple
        self.isQuarantined = isQuarantined
    }

    var rustupPath: URL { cargoHome.appendingPathComponent("bin/rustup") }

    /// rustup's binary as it is on disk.
    struct Rustup: Sendable, Equatable {
        enum Problem: String, Sendable {
            /// A link to nothing, an empty file, or not a file.
            case notAFile
        }
        let path: String
        let problem: Problem?
        let sha256: String?
        /// The target its Mach-O header says it was built for — which archive
        /// entry its hash is compared with. nil for a fat or unknown header.
        let hostTriple: String?
        /// The version its own user-agent string names (`rustup/1.29.1 (`), a
        /// claim for picking which published hash to compare, never proof.
        let claimedVersion: String?
        let quarantined: Bool
    }

    struct Toolchain: Sendable, Equatable {
        enum Problem: String, Sendable {
            /// No `[pkg.rust]` version in its manifest.
            case versionUnreadable
        }
        let path: String
        let name: RustToolchainName
        let version: RustToolchainVersion?
        /// The 20 hex digits in `update-hashes/<name>`, nil when there is none.
        let updateHash: String?
        var problem: Problem? { version == nil ? .versionUnreadable : nil }
    }

    // MARK: - rustup

    /// nil when there is nothing at `~/.cargo/bin/rustup`. Blocking: reads the
    /// whole file (11 MB for 1.29.1 arm64) twice, for its hash and its claim.
    func rustup() -> Rustup? {
        let path = rustupPath
        guard (try? FileManager.default.attributesOfItem(atPath: path.path)) != nil else { return nil }
        let resolved = path.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? Int ?? 0) > 0
        else {
            return Rustup(path: path.path, problem: .notAFile, sha256: nil, hostTriple: nil, claimedVersion: nil,
                          quarantined: false)
        }
        return Rustup(
            path: path.path, problem: nil, sha256: CLIToolTrust.sha256(of: resolved),
            hostTriple: readHostTriple(resolved), claimedVersion: Self.claimedVersion(in: resolved),
            quarantined: isQuarantined(resolved))
    }

    /// The target triple rust-lang files the build under, from the binary's own
    /// Mach-O header (`ClaudeCodeRelease.platform`) — not the Mac's: an Apple
    /// Silicon Mac can hold an x86_64 rustup (installed under Rosetta), whose hash
    /// is the `x86_64-apple-darwin` one.
    static func hostTriple(of executable: URL) -> String? {
        switch ClaudeCodeRelease.platform(of: executable) {
        case "darwin-arm64": return "aarch64-apple-darwin"
        case "darwin-x64": return "x86_64-apple-darwin"
        default: return nil
        }
    }

    /// The version in rustup's user-agent string, `rustup/<version> (<target>)`,
    /// which every build carries (three times in 1.29.1, measured 2026-10-01 with
    /// `grep -aoE 'rustup/[0-9.]+ \('`). The first occurrence that is a version.
    /// Read, never mapped (`ExecutableBytes`): rustup is ad hoc signed, and a
    /// copy whose signature no longer validates must not end a hardened process.
    static func claimedVersion(in executable: URL) -> String? {
        guard let literals = ExecutableBytes.joinedWindows(
            in: executable, marker: Data("rustup/".utf8), before: 0, after: 64)
        else { return nil }
        return claimedVersion(in: literals)
    }

    static func claimedVersion(in data: Data) -> String? {
        let marker = Data("rustup/".utf8)
        var start = data.startIndex
        while let found = data.range(of: marker, in: start..<data.endIndex) {
            var index = found.upperBound
            var version = ""
            // Digits and dots only, and never more than a version could be.
            while index < data.endIndex, version.count < 32 {
                let byte = data[index]
                guard byte == 0x2E || (0x30...0x39).contains(byte) else { break }
                version.append(Character(UnicodeScalar(byte)))
                index += 1
            }
            if data.endIndex - index >= 2, data[index] == 0x20, data[index + 1] == 0x28,
               version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil {
                return version
            }
            start = found.upperBound
        }
        return nil
    }

    // MARK: - Toolchains

    /// Every toolchain that follows a channel, sorted stable, beta, nightly, then
    /// `X.Y` newest first. A symlink is a toolchain linked from a local build
    /// (`rustup toolchain link`): not rustup's to update, not shown.
    func toolchains() -> [Toolchain] {
        let directory = rustupHome.appendingPathComponent("toolchains")
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        var found: [Toolchain] = []
        for entry in entries {
            guard let name = RustToolchainName.parse(entry) else { continue }
            let url = directory.appendingPathComponent(entry)
            guard let attributes = try? fm.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory
            else { continue }
            found.append(Toolchain(
                path: url.path, name: name,
                version: Self.manifestVersion(
                    url.appendingPathComponent("lib/rustlib/multirust-channel-manifest.toml")),
                updateHash: updateHash(for: entry)))
        }
        return found.sorted { Self.order($0.name, $1.name) }
    }

    func updateHash(for name: String) -> String? {
        let file = rustupHome.appendingPathComponent("update-hashes").appendingPathComponent(name)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text.lowercased()
    }

    static func order(_ a: RustToolchainName, _ b: RustToolchainName) -> Bool {
        let rank = ["stable": 0, "beta": 1, "nightly": 2]
        let (ra, rb) = (rank[a.channel] ?? 3, rank[b.channel] ?? 3)
        if ra != rb { return ra < rb }
        if a.channel != b.channel {
            return VersionComparator.compare(a.channel, b.channel) == .orderedDescending
        }
        return a.name < b.name
    }

    /// `[pkg.rust]`'s `version` in a channel manifest, read in 64 KB chunks and
    /// stopped as soon as it is found — ~90 KB of the ~1 MB file today, and the
    /// whole of it at worst.
    static func manifestVersion(_ file: URL) -> RustToolchainVersion? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var buffer = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            if let version = RustRelease.packageVersion(in: buffer) { return version }
        }
        return nil
    }
}
